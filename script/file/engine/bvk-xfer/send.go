package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptrace"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// send — upload a packed folder (blob0..blob<n-1> + manifest.enc) in the fewest possible round trips:
//
//	one blob   PUT /upload/fast   blob + manifest + commit in ONE request                                  → 201
//	n blobs    PUT /upload/fast   init + blob 0 → {id, token}   (auth, size, credits all checked here)
//	           PUT /upload/<id>/blob/<i>   blobs 1..n-2, in parallel on the same connection
//	           PUT /upload/<id>/blob/<n-1> X-Final: 1 + manifest → the server commits right there           → 201
//
// The request headers (auth, nuke time, alias, service, vault key …) arrive on stdin in curl-config form (header = "Name: value"), exactly as the
// shell already builds them, so no secret is ever on a command line.
//
// stdout, first line is the verdict (a last line "TIME\t…" says where the first request's time went):
//
//	OK \n url \n credits-deducted \n balance \n expires-ms        done (the folder may be deleted)
//	HANDOVER \t id                                               init + blob 0 done; the shell continues in the resumable path (big uploads)
//	INTERRUPTED \t id-or-"-"                                     Ctrl-C / kill: keep the folder (Pending) when there is an id
//	REFUSED \t status \t error \t message                         the server said no for good (credits, auth, size …): do not retry
//	FALLBACK \t id-or-"-" \t reason                               something went wrong half-way: hand the folder to the resumable path
type hdrs [][2]string

type cfgSet struct{ auth, initH, commit hdrs }

func unescapeCfg(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func readCfg(r io.Reader) cfgSet {
	var c cfgSet
	data, _ := io.ReadAll(r)
	for _, ln := range strings.Split(string(data), "\n") {
		ln = strings.TrimRight(ln, "\r")
		if !strings.HasPrefix(ln, `header = "`) || !strings.HasSuffix(ln, `"`) {
			continue
		}
		kv := unescapeCfg(ln[len(`header = "`) : len(ln)-1])
		i := strings.Index(kv, ": ")
		if i <= 0 {
			continue
		}
		name, val := kv[:i], kv[i+2:]
		switch strings.ToLower(name) {
		case "x-user-email", "x-user-diseps", "x-user-key":
			c.auth = append(c.auth, [2]string{name, val})
		case "x-vault-kdk", "x-snap-target", "x-snap-sig":
			c.commit = append(c.commit, [2]string{name, val})
		default:
			c.initH = append(c.initH, [2]string{name, val})
		}
	}
	return c
}

type resp struct {
	status int
	body   []byte
	hdr    http.Header
	err    error
}

// where the time of the FIRST request goes (DNS · TCP · TLS · server wait): printed as a TIME line, logged by the shell, shown by `health`
type traceData struct{ t0, dnsS, dnsD, conS, conD, tlsS, tlsD, wrote, first time.Time }

func (t *traceData) clientTrace() *httptrace.ClientTrace {
	return &httptrace.ClientTrace{
		GetConn:              func(string) { t.t0 = time.Now() },
		DNSStart:             func(httptrace.DNSStartInfo) { t.dnsS = time.Now() },
		DNSDone:              func(httptrace.DNSDoneInfo) { t.dnsD = time.Now() },
		ConnectStart:         func(string, string) { if t.conS.IsZero() { t.conS = time.Now() } },
		ConnectDone:          func(string, string, error) { t.conD = time.Now() },
		TLSHandshakeStart:    func() { t.tlsS = time.Now() },
		TLSHandshakeDone:     func(tls.ConnectionState, error) { t.tlsD = time.Now() },
		WroteRequest:         func(httptrace.WroteRequestInfo) { t.wrote = time.Now() },
		GotFirstResponseByte: func() { t.first = time.Now() },
	}
}

func (t *traceData) String() string {
	ms := func(a, b time.Time) int64 {
		if a.IsZero() || b.IsZero() {
			return 0
		}
		return b.Sub(a).Milliseconds()
	}
	return fmt.Sprintf("dns=%dms tcp=%dms tls=%dms wait=%dms first-request=%dms", ms(t.dnsS, t.dnsD), ms(t.conS, t.conD), ms(t.tlsS, t.tlsD), ms(t.wrote, t.first), ms(t.t0, t.first))
}

type sender struct {
	ctx  context.Context
	intr atomic.Bool
	tr   *traceData // set only while the FIRST request runs (later requests run in parallel and must not touch it)
	trLine string
	cl   *http.Client
	base string
	sent int64 // plain progress: bytes of blobs acknowledged
	tot  int64
	tty  bool
	t0   time.Time
}

func (s *sender) put(path string, hs hdrs, body []byte) resp {
	ctx, cancel := context.WithTimeout(s.ctx, 4*time.Minute)
	defer cancel()
	if s.tr != nil {
		ctx = httptrace.WithClientTrace(ctx, s.tr.clientTrace())
	}
	req, err := http.NewRequestWithContext(ctx, "PUT", s.base+path, bytes.NewReader(body))
	if err != nil {
		return resp{err: err}
	}
	for _, h := range hs {
		req.Header.Set(h[0], h[1])
	}
	req.Header.Set("Content-Type", "application/octet-stream")
	r, err := s.cl.Do(req)
	if err != nil {
		return resp{err: err}
	}
	defer r.Body.Close()
	b, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	return resp{status: r.StatusCode, body: b, hdr: r.Header, err: err}
}

func (s *sender) get(path string) resp {
	ctx, cancel := context.WithTimeout(s.ctx, 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "GET", s.base+path, nil)
	if err != nil {
		return resp{err: err}
	}
	r, err := s.cl.Do(req)
	if err != nil {
		return resp{err: err}
	}
	defer r.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(r.Body, 1<<20))
	return resp{status: r.StatusCode, hdr: r.Header}
}

func jfield(body []byte, k string) string {
	var m map[string]interface{}
	if json.Unmarshal(body, &m) != nil {
		return ""
	}
	if v, ok := m[k].(string); ok {
		return v
	}
	return ""
}

func clean(s string) string { return strings.NewReplacer("\t", " ", "\n", " ", "\r", " ").Replace(s) }

func okOut(r resp, url string) int {
	d, b, e := "", "", ""
	if r.hdr != nil {
		d, b, e = r.hdr.Get("X-Credits-Deducted"), r.hdr.Get("X-Credits-Balance"), r.hdr.Get("X-Link-Expires")
	}
	fmt.Printf("OK\n%s\n%s\n%s\n%s\n", url, d, b, e)
	return 0
}

// what to do with an answer: "ok" · "already" (409 already_committed) · "refused" · "retry" (network, 5xx, 429 …)
func classify(r resp) string {
	if r.err != nil {
		return "retry"
	}
	switch {
	case r.status == 200 || r.status == 201:
		return "ok"
	case r.status == 409 && jfield(r.body, "error") == "already_committed":
		return "already"
	case r.status == 408 || r.status == 429 || r.status >= 500:
		return "retry"
	case r.status == 400 && jfield(r.body, "error") == "incomplete_upload":
		return "retry"
	case r.status >= 400:
		return "refused"
	}
	return "retry"
}

func refused(r resp) int {
	fmt.Printf("REFUSED\t%d\t%s\t%s\n", r.status, clean(jfield(r.body, "error")), clean(jfield(r.body, "message")))
	return 0
}

func interrupted(id string) int {
	fmt.Printf("INTERRUPTED\t%s\n", id)
	return 0
}

func fallback(id, why string) int {
	if id == "" {
		id = "-"
	}
	fmt.Printf("FALLBACK\t%s\t%s\n", id, clean(why))
	return 0
}

func (s *sender) draw(final bool) {
	if !s.tty {
		return
	}
	done := atomic.LoadInt64(&s.sent)
	pct := 0
	if s.tot > 0 {
		pct = int(done * 100 / s.tot)
	}
	if pct > 100 {
		pct = 100
	}
	const cols = 24
	f := pct * cols / 100
	fmt.Fprintf(os.Stderr, "\x1b[?7l\r\x1b[K\x1b[36m[%s%s] %3d%%  ☁️ %.1f/%.1f MB\x1b[0m\x1b[?7h", strings.Repeat("█", f), strings.Repeat("░", cols-f), pct, float64(done)/1048576, float64(s.tot)/1048576)
	if final {
		fmt.Fprint(os.Stderr, "\n")
	}
}

func cmdSend(args []string) int {
	fs := flag.NewFlagSet("send", flag.ContinueOnError)
	dir := fs.String("dir", "", "folder with blob<N> and manifest.enc")
	base := fs.String("url", "", "https://host")
	est := fs.Int64("est", 0, "total encrypted bytes (the estimate the server prices and checks)")
	n := fs.Int("n", 0, "number of blobs")
	conc := fs.Int("conc", 8, "blobs in flight at once")
	pending := fs.Bool("pending", true, "let the server note a multi-blob upload (so it can be continued)")
	handover := fs.Int64("handover-over", 0, "estimates above this many bytes: do init + blob 0, then hand over to the resumable path (pause / resume / offline wait)")
	if err := fs.Parse(args); err != nil || *dir == "" || *n < 1 || *est < 1 || !strings.HasPrefix(*base, "https://") {
		fmt.Fprintln(os.Stderr, "usage: bvk-xfer send --dir D --url https://host --est BYTES --n BLOBS [--conc N]   (headers on stdin)")
		return 2
	}
	cfg := readCfg(os.Stdin)
	if len(cfg.auth) < 2 {
		return fallback("-", "no credentials")
	}
	man, err := os.ReadFile(filepath.Join(*dir, "manifest.enc"))
	if err != nil {
		return fallback("-", "manifest missing")
	}
	if *conc < 1 {
		*conc = 1
	}
	if *conc > maxStreams {
		*conc = maxStreams
	}
	rnd := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, rnd); err != nil {
		return fallback("-", "no randomness")
	}
	nonce := base64.RawURLEncoding.EncodeToString(rnd)
	var email, diseps string
	for _, h := range cfg.auth {
		switch strings.ToLower(h[0]) {
		case "x-user-email":
			email = strings.ToLower(strings.TrimSpace(h[1]))
		case "x-user-diseps":
			diseps = strings.TrimSpace(h[1])
		}
	}
	sum := sha256.Sum256([]byte("svcid2|" + email + "|" + diseps + "|" + nonce)) // the id the server will derive: lets us check after a lost answer
	id := base64.RawURLEncoding.EncodeToString(sum[:])

	st, _ := os.Stderr.Stat()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	s := &sender{ctx: ctx, cl: newClient(*conc), base: strings.TrimRight(*base, "/"), tot: *est, t0: time.Now(), tty: st != nil && st.Mode()&os.ModeCharDevice != 0}
	sigc := make(chan os.Signal, 2)
	signal.Notify(sigc, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() { <-sigc; s.intr.Store(true); cancel() }() // Ctrl-C / kill: stop NOW, tell the shell, which keeps the upload in Pending
	s.tr = &traceData{}
	defer func() {
		line := s.trLine
		if line == "" && s.tr != nil {
			line = s.tr.String()
		}
		fmt.Printf("TIME\t%s send=%dms\n", line, time.Since(s.t0).Milliseconds())
	}()
	readBlob := func(i int) ([]byte, error) { return os.ReadFile(filepath.Join(*dir, "blob"+strconv.Itoa(i))) }
	b64man := base64.RawURLEncoding.EncodeToString(man)
	commitH := append(hdrs{{"X-File-Count", strconv.Itoa(*n)}, {"X-Manifest", b64man}, {"X-Final", "1"}}, cfg.commit...)

	// ── request 1: init + blob 0 (+ the whole commit when there is only one blob) ──
	b0, err := readBlob(0)
	if err != nil {
		return fallback("-", "blob0 missing")
	}
	first := append(hdrs{}, cfg.auth...)
	first = append(first, cfg.initH...)
	first = append(first, hdrs{{"X-Estimated-Size", strconv.FormatInt(*est, 10)}, {"X-Upload-Nonce", nonce}}...)
	single := *n == 1
	if !single { // declare the profile (the worker checks it against its limits); blob 0 of a multi-blob upload is always a full chunk
		if cb := len(b0) - blobOverhead; cb >= minChunkBytes && cb <= maxChunkBytes {
			first = append(first, hdrs{{"X-Chunk-Bytes", strconv.Itoa(cb)}, {"X-Streams", strconv.Itoa(*conc)}}...)
		}
	}
	if single {
		first = append(first, commitH...)
	} else if *pending {
		first = append(first, hdrs{{"X-Pending", "1"}, {"X-Blob-Count", strconv.Itoa(*n)}}...)
	}
	var r1 resp
	for attempt := 0; attempt < 3; attempt++ {
		r1 = s.put("/upload/fast", first, b0)
		if k := classify(r1); k != "retry" || s.intr.Load() {
			break
		}
		// the answer may have been lost AFTER the server committed: look before sending anything again (a retry must never charge twice)
		if single && s.get("/"+id+"/manifest").status == 200 {
			return okOut(resp{}, s.base+"/"+id)
		}
		time.Sleep(time.Duration(attempt+1) * 700 * time.Millisecond)
	}
	s.trLine = s.tr.String()
	s.tr = nil
	if s.intr.Load() {
		if single {
			return interrupted("-")
		}
		return interrupted(id)
	}
	switch classify(r1) {
	case "refused":
		return refused(r1)
	case "retry":
		why := "server unreachable"
		if r1.err != nil {
			why = r1.err.Error()
		} else {
			why = "HTTP " + strconv.Itoa(r1.status)
		}
		return fallback("-", why)
	case "already":
		return okOut(resp{}, s.base+"/"+id)
	}
	atomic.AddInt64(&s.sent, int64(len(b0)))
	if single {
		s.draw(true)
		return okOut(r1, strings.TrimSpace(string(r1.body)))
	}
	var init struct {
		ID    string `json:"id"`
		Token string `json:"token"`
	}
	if json.Unmarshal(r1.body, &init) != nil || init.ID == "" || init.Token == "" {
		return fallback("-", "server did not return an upload id/token")
	}
	id = init.ID
	tokH := hdrs{{"X-Upload-Token", init.Token}}
	if *handover > 0 && *est > *handover {
		fmt.Printf("HANDOVER\t%s\n", id) // a big upload goes on in the resumable path: pause, Ctrl-C, offline wait, continue later
		return 0
	}

	// ── requests 2..n-1: the other blobs, in parallel on the same connection ──
	var wg sync.WaitGroup
	sem := make(chan struct{}, *conc)
	var failed int32
	var firstErr atomic.Value
	stopDraw := make(chan struct{})
	go func() {
		t := time.NewTicker(150 * time.Millisecond)
		defer t.Stop()
		for {
			select {
			case <-stopDraw:
				return
			case <-t.C:
				s.draw(false)
			}
		}
	}()
	for i := 1; i < *n-1 && atomic.LoadInt32(&failed) == 0; i++ {
		sem <- struct{}{}
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			defer func() { <-sem }()
			b, err := readBlob(i)
			if err != nil {
				atomic.StoreInt32(&failed, 1)
				firstErr.Store("blob " + strconv.Itoa(i) + " missing")
				return
			}
			var r resp
			for attempt := 0; attempt < 4; attempt++ {
				r = s.put("/upload/"+id+"/blob/"+strconv.Itoa(i), tokH, b)
				if classify(r) != "retry" || s.intr.Load() {
					break
				}
				time.Sleep(time.Duration(attempt+1) * 500 * time.Millisecond)
			}
			if classify(r) != "ok" {
				atomic.StoreInt32(&failed, 1)
				why := "HTTP " + strconv.Itoa(r.status)
				if r.err != nil {
					why = r.err.Error()
				}
				firstErr.Store("blob " + strconv.Itoa(i) + ": " + why)
				return
			}
			atomic.AddInt64(&s.sent, int64(len(b)))
		}(i)
	}
	wg.Wait()
	close(stopDraw)
	if s.intr.Load() {
		s.draw(true)
		return interrupted(id)
	}
	if atomic.LoadInt32(&failed) != 0 {
		s.draw(true)
		why, _ := firstErr.Load().(string)
		return fallback(id, why)
	}

	// ── the last blob carries the commit (X-Final): no separate /commit round trip ──
	bl, err := readBlob(*n - 1)
	if err != nil {
		return fallback(id, "last blob missing")
	}
	lastH := append(append(hdrs{}, tokH...), commitH...)
	var rl resp
	for attempt := 0; attempt < 4; attempt++ {
		rl = s.put("/upload/"+id+"/blob/"+strconv.Itoa(*n-1), lastH, bl)
		if classify(rl) != "retry" || s.intr.Load() {
			break
		}
		time.Sleep(time.Duration(attempt+1) * 700 * time.Millisecond)
	}
	atomic.AddInt64(&s.sent, int64(len(bl)))
	s.draw(true)
	if s.intr.Load() {
		return interrupted(id)
	}
	switch classify(rl) {
	case "ok":
		return okOut(rl, strings.TrimSpace(string(rl.body)))
	case "already":
		return okOut(resp{}, s.base+"/"+id)
	case "refused":
		return refused(rl)
	}
	why := "HTTP " + strconv.Itoa(rl.status)
	if rl.err != nil {
		why = rl.err.Error()
	}
	return fallback(id, why)
}
