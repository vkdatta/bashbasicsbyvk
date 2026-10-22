package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unicode/utf8"
)

// xfer <upload|ux> <worker-url> <id> <dir>  — the resilient blob transfer behind up- · ux- · backup · save- · snapshot, and behind every
// Pending → continue.  A drop-in for the node script bashbasicsbyvk_staging_pending_xfer: same arguments, same BB_* environment, same files
// in BB_STATE (progress, run.hb, pause.flag, stop.flag), same verdict on the last stdout line:
//
//	OK | PAUSED | INTERRUPTED | STOPPED | TOKEN | OFFLINE | FAIL
//
// Resilience: a lost connection is waited out (backoff up to 30 s) until BB_OFFLINE_MAX of continuous outage; blobs the server already holds
// (BB_DONEFILE) are skipped; p = pause · Ctrl-C/Ctrl-Z/SIGTERM/SIGHUP = stop now but keep everything; the Pending menu's flags are honoured
// within half a second.
const inlineMax = 4 << 20

type xtask struct {
	key  string
	idx  int
	fp   string
	size int64
	url  string
	done bool
}

type errBox struct{ err error } // atomic.Value panics when handed different concrete types: always store this one

type halted struct{}
type fatal struct{ msg string }

func (halted) Error() string  { return "halt" }
func (f fatal) Error() string { return f.msg }

type xf struct {
	pipeline, base, id, dir, utoken, email, state string
	conc                                          int
	chunk                                         int64
	offlineMax                                    time.Duration
	cl                                            *http.Client
	ctx                                           context.Context
	cancel                                        context.CancelFunc

	mu        sync.Mutex
	drawMu    sync.Mutex
	halt      string
	note      string
	tokenDead bool
	offDead   bool
	outage    time.Time

	sent, doneN, safeBytes int64
	lastIdx                int64
	total                  int64
	ntasks                 int
	shown                  int64
	alreadyN               int
	alreadyBytes           int64
	tty                    bool
	t0                     time.Time
	samples                [][2]int64 // unix-ms, sent
}

func envInt(k string, d int) int {
	if v, err := strconv.Atoi(os.Getenv(k)); err == nil && v > 0 {
		return v
	}
	return d
}

func parseRanges(s string) map[int]bool {
	set := map[int]bool{}
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		a, b := part, part
		if i := strings.Index(part, "-"); i >= 0 {
			a, b = part[:i], part[i+1:]
		}
		x, e1 := strconv.Atoi(a)
		y, e2 := strconv.Atoi(b)
		if e1 != nil || e2 != nil || y < x || y-x >= 1000000 {
			continue
		}
		for i := x; i <= y; i++ {
			set[i] = true
		}
	}
	return set
}

func (x *xf) halting() bool {
	x.mu.Lock()
	defer x.mu.Unlock()
	return x.halt != "" || x.tokenDead || x.offDead
}

func (x *xf) requestHalt(why string, grace time.Duration) {
	x.mu.Lock()
	if x.halt != "" {
		x.mu.Unlock()
		return
	}
	x.halt = why
	x.mu.Unlock()
	if grace <= 0 {
		x.cancel()
	} else {
		time.AfterFunc(grace, x.cancel) // let in-flight blobs finish for a moment
	}
}

func (x *xf) setNote(s string) { x.mu.Lock(); x.note = s; x.mu.Unlock() }

func (x *xf) writeState(name, text string) {
	if x.state != "" {
		_ = os.WriteFile(filepath.Join(x.state, name), []byte(text), 0o600)
	}
}

func (x *xf) noter() {
	sent := atomic.LoadInt64(&x.sent)
	if sent > x.total {
		sent = x.total
	}
	x.writeState("progress", fmt.Sprintf("%d %d %d %d %d\n", atomic.LoadInt64(&x.doneN), x.ntasks, atomic.LoadInt64(&x.lastIdx), sent, x.total))
	x.writeState("run.hb", fmt.Sprintf("%d %d\n", os.Getpid(), time.Now().Unix()))
}

// ── progress, in BYTES ──
func fmtT(s float64) string {
	n := int(math.Max(0, math.Round(s)))
	switch {
	case n >= 3600:
		return fmt.Sprintf("%dh%02dm", n/3600, n%3600/60)
	case n >= 60:
		return fmt.Sprintf("%dm%02ds", n/60, n%60)
	}
	return fmt.Sprintf("%ds", n)
}

func (x *xf) fmtB(b int64) string {
	if x.total >= 1048576 {
		return fmt.Sprintf("%.1f", float64(b)/1048576)
	}
	return fmt.Sprintf("%.0f", float64(b)/1024)
}

func (x *xf) unit() string {
	if x.total >= 1048576 {
		return "MB"
	}
	return "KB"
}

func (x *xf) speed() float64 {
	now := time.Now().UnixMilli()
	x.samples = append(x.samples, [2]int64{now, atomic.LoadInt64(&x.sent)})
	for len(x.samples) > 2 && now-x.samples[0][0] > 8000 {
		x.samples = x.samples[1:]
	}
	a, b := x.samples[0], x.samples[len(x.samples)-1]
	dt := float64(b[0]-a[0]) / 1000
	if dt > 0.4 {
		return math.Max(0, float64(b[1]-a[1])/dt)
	}
	return 0
}

func (x *xf) draw(final bool) {
	if !x.tty {
		return
	}
	x.drawMu.Lock()
	defer x.drawMu.Unlock()
	sent := atomic.LoadInt64(&x.sent)
	if s := minI64(sent, x.total); s > x.shown {
		x.shown = s
	}
	doneN := int(atomic.LoadInt64(&x.doneN))
	finished := final && doneN >= x.ntasks
	pct := 100
	if x.total > 0 {
		pct = int(x.shown * 100 / x.total)
	}
	if !finished && pct > 99 {
		pct = 99
	}
	sp := x.speed()
	cols := termCols()
	shownB := x.shown
	if finished {
		shownB = x.total
	}
	parts := []string{fmt.Sprintf("%3d%%", pct), x.fmtB(shownB) + "/" + x.fmtB(x.total) + " " + x.unit()}
	var extra []string
	x.mu.Lock()
	note := x.note
	x.mu.Unlock()
	if !finished {
		if note != "" {
			extra = append(extra, note)
		} else {
			if sp > 0 {
				extra = append(extra, x.fmtB(int64(sp))+" "+x.unit()+"/s", "ETA "+fmtT(float64(x.total-x.shown)/sp))
			} else {
				extra = append(extra, "...")
			}
		}
		extra = append(extra, fmt.Sprintf("%d/%d", doneN, x.ntasks))
	}
	var info string
	for {
		info = strings.Join(append(append([]string{}, parts...), extra...), "  ")
		if cols-utf8.RuneCountInString(info)-4 >= 8 || len(extra) == 0 {
			break
		}
		extra = extra[1:]
	}
	barW := cols - utf8.RuneCountInString(info) - 4
	if barW > 22 {
		barW = 22
	}
	if barW < 6 {
		barW = 6
	}
	filled := pct * barW / 100
	color := "\x1b[36m"
	if finished {
		color = "\x1b[32m"
	} else if note != "" {
		color = "\x1b[33m"
	}
	fmt.Fprintf(os.Stderr, "\x1b[?7l\r\x1b[K%s[%s%s] %s\x1b[0m\x1b[?7h", color, strings.Repeat("█", filled), strings.Repeat("░", barW-filled), info)
	if finished {
		secs := time.Since(x.t0).Seconds()
		mine := x.total - x.alreadyBytes
		if x.alreadyN > 0 {
			fmt.Fprintf(os.Stderr, "\n  ✅ %s %s (%s %s sent now, the rest was already there)\n", x.fmtB(x.total), x.unit(), x.fmtB(mine), x.unit())
		} else {
			avg := ""
			if secs > 0 {
				avg = fmt.Sprintf("  (avg %s %s/s)", x.fmtB(int64(float64(x.total)/secs)), x.unit())
			}
			fmt.Fprintf(os.Stderr, "\n  ✅ %s %s in %s%s\n", x.fmtB(x.total), x.unit(), fmtT(secs), avg)
		}
	}
}

func minI64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}

// ── request bodies that count the bytes that really left ──
type countBody struct {
	r   io.Reader
	f   *os.File
	x   *xf
	ctr *int64
}

func (c *countBody) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	if n > 0 {
		atomic.AddInt64(&c.x.sent, int64(n))
		atomic.AddInt64(c.ctr, int64(n))
	}
	return n, err
}
func (c *countBody) Close() error {
	if c.f != nil {
		return c.f.Close()
	}
	return nil
}

type bodyMaker func(ctr *int64) (io.ReadCloser, int64, error)

func (x *xf) fileBody(fp string, size, start, length int64, whole bool) bodyMaker {
	return func(ctr *int64) (io.ReadCloser, int64, error) {
		if whole && size <= inlineMax {
			b, err := os.ReadFile(fp)
			if err != nil {
				return nil, 0, err
			}
			return io.NopCloser(bytes.NewReader(b)), int64(len(b)), nil
		}
		f, err := os.Open(fp)
		if err != nil {
			return nil, 0, err
		}
		return &countBody{r: io.NewSectionReader(f, start, length), f: f, x: x, ctr: ctr}, length, nil
	}
}

func (x *xf) authHeaders(req *http.Request) {
	if x.pipeline == "upload" {
		req.Header.Set("X-User-Email", x.email)
	}
	req.Header.Set("X-Upload-Token", x.utoken)
}

// ONE request that survives a bad network: transient failures (offline, timeouts, 5xx, 429) are retried with backoff until offlineMax of
// continuous outage; a 4xx will not fix itself (a 401 invalid_upload_token = TOKEN so the caller can mint a new one).
func (x *xf) send(url, method string, mk bodyMaker, extra map[string]string, credit int64, label string) ([]byte, error) {
	for attempt := 0; ; attempt++ {
		if x.halting() {
			return nil, halted{}
		}
		var ctr int64
		var rc io.ReadCloser
		var length int64
		if mk != nil {
			var err error
			rc, length, err = mk(&ctr)
			if err != nil {
				return nil, fatal{"cannot read " + label + ": " + err.Error()}
			}
		}
		var rdr io.Reader
		if rc != nil {
			rdr = rc
		}
		req, err := http.NewRequestWithContext(x.ctx, method, url, rdr)
		if err != nil {
			return nil, fatal{err.Error()}
		}
		if rc != nil {
			req.ContentLength = length
		}
		x.authHeaders(req)
		for k, v := range extra {
			req.Header.Set(k, v)
		}
		transient := ""
		res, err := x.cl.Do(req)
		if err == nil {
			b, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
			res.Body.Close()
			if res.StatusCode >= 200 && res.StatusCode < 300 {
				atomic.AddInt64(&x.sent, credit-atomic.LoadInt64(&ctr))
				x.mu.Lock()
				x.outage = time.Time{}
				x.note = ""
				x.mu.Unlock()
				return b, nil
			}
			atomic.AddInt64(&x.sent, -atomic.LoadInt64(&ctr))
			if res.StatusCode == 401 && jfield(b, "error") == "invalid_upload_token" {
				x.mu.Lock()
				x.tokenDead = true
				x.mu.Unlock()
				return nil, halted{}
			}
			if res.StatusCode < 500 && res.StatusCode != 429 {
				return nil, fatal{"HTTP " + strconv.Itoa(res.StatusCode)}
			}
			transient = "HTTP " + strconv.Itoa(res.StatusCode)
		} else {
			atomic.AddInt64(&x.sent, -atomic.LoadInt64(&ctr))
			if x.halting() {
				return nil, halted{}
			}
			transient = err.Error()
		}
		_ = transient
		// transient: wait the outage out, still listening for pause / stop
		x.mu.Lock()
		if x.outage.IsZero() {
			x.outage = time.Now()
		}
		dead := time.Since(x.outage) > x.offlineMax
		if dead {
			x.offDead = true
		}
		x.mu.Unlock()
		if dead {
			return nil, halted{}
		}
		wait := math.Min(30000, 400*math.Pow(2, math.Min(float64(attempt), 7))) * (0.75 + rand.Float64()*0.5)
		for w := 0.0; w < wait; w += 250 {
			x.setNote(fmt.Sprintf("⏳ offline? retry in %ds (%s)", int(math.Max(1, math.Round((wait-w)/1000))), label))
			if x.halting() {
				return nil, halted{}
			}
			time.Sleep(250 * time.Millisecond)
		}
	}
}

func (x *xf) uploadOne(t *xtask) error {
	if t.size <= x.chunk || x.pipeline == "ux" {
		var extra map[string]string
		if x.pipeline == "ux" {
			extra = map[string]string{"Content-Type": "application/octet-stream"}
		}
		_, err := x.send(t.url, "PUT", x.fileBody(t.fp, t.size, 0, t.size, true), extra, t.size, "blob "+strconv.Itoa(t.idx))
		return err
	}
	// a blob above the single-PUT limit goes up as R2 multipart; an interrupted one is restarted from its first byte
	label := "blob " + strconv.Itoa(t.idx)
	cb, err := x.send(t.url+"/mpu", "POST", nil, nil, 0, label)
	if err != nil {
		return err
	}
	uploadID := jfield(cb, "uploadId")
	if uploadID == "" {
		return fatal{"no uploadId"}
	}
	type rng struct {
		pn         int
		start, len int64
	}
	var ranges []rng
	for off, pn := int64(0), 1; off < t.size; off, pn = off+x.chunk, pn+1 {
		end := off + x.chunk
		if end > t.size {
			end = t.size
		}
		ranges = append(ranges, rng{pn, off, end - off})
	}
	type part struct {
		PartNumber int    `json:"partNumber"`
		Etag       string `json:"etag"`
	}
	parts := make([]part, len(ranges))
	var next int32 = -1
	var wg sync.WaitGroup
	var first atomic.Value
	for w := 0; w < minInt(x.conc, len(ranges)); w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				i := int(atomic.AddInt32(&next, 1))
				if i >= len(ranges) || first.Load() != nil {
					return
				}
				r := ranges[i]
				b, err := x.send(t.url+"/mpu/"+uploadID+"/"+strconv.Itoa(r.pn), "PUT", x.fileBody(t.fp, t.size, r.start, r.len, false), nil, r.len, label+" part "+strconv.Itoa(r.pn))
				if err != nil {
					first.CompareAndSwap(nil, errBox{err})
					return
				}
				var p part
				if json.Unmarshal(b, &p) != nil {
					first.CompareAndSwap(nil, errBox{fatal{"bad part answer"}})
					return
				}
				parts[i] = p
			}
		}()
	}
	wg.Wait()
	if e := first.Load(); e != nil {
		return e.(errBox).err
	}
	body, _ := json.Marshal(parts)
	_, err = x.send(t.url+"/mpu/"+uploadID+"/complete", "POST", func(*int64) (io.ReadCloser, int64, error) {
		return io.NopCloser(bytes.NewReader(body)), int64(len(body)), nil
	}, map[string]string{"Content-Type": "application/json"}, 0, label)
	return err
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func cmdXfer(args []string) int {
	if len(args) != 4 || (args[0] != "upload" && args[0] != "ux") || args[1] == "" || args[2] == "" || args[3] == "" {
		fmt.Println("FAIL")
		return 2
	}
	x := &xf{pipeline: args[0], base: strings.TrimRight(args[1], "/"), id: args[2], dir: args[3], utoken: os.Getenv("BB_UTOKEN"), email: os.Getenv("BB_EMAIL"), state: os.Getenv("BB_STATE"), lastIdx: -1, t0: time.Now()}
	if !strings.HasPrefix(x.base, "https://") {
		fmt.Println("FAIL")
		return 2
	}
	dc := 16
	if x.pipeline == "ux" {
		dc = 8
	}
	x.conc = envInt("BB_CONC", dc)
	if x.conc > 32 {
		x.conc = 32
	}
	x.chunk = int64(envInt("BB_CHUNK", 90<<20))
	om := envInt("BB_OFFLINE_MAX", 1800)
	if om < 10 {
		om = 10
	}
	x.offlineMax = time.Duration(om) * time.Second
	x.ctx, x.cancel = context.WithCancel(context.Background())
	x.cl = newClient(x.conc)
	x.tty = isTTY(2)

	// ── what the server already holds ──
	var dj struct {
		Done      string            `json:"done"`
		DoneItems map[string]string `json:"doneItems"`
		Sizes     map[string]int64  `json:"sizes"`
	}
	if b, err := os.ReadFile(os.Getenv("BB_DONEFILE")); err == nil {
		_ = json.Unmarshal(b, &dj)
	}
	doneUp := parseRanges(dj.Done)
	doneUx := map[string]map[int]bool{}
	for k, v := range dj.DoneItems {
		doneUx[k] = parseRanges(v)
	}

	// ── the work list ──
	var tasks []*xtask
	missing := func(what string) int {
		fmt.Fprintf(os.Stderr, "  ⚠️  %s is missing on this computer\n", what)
		fmt.Println("FAIL")
		return 2
	}
	if x.pipeline == "upload" {
		n := envInt("BB_N", 0)
		for i := 0; i < n; i++ {
			fp := filepath.Join(x.dir, "blob"+strconv.Itoa(i))
			st, err := os.Stat(fp)
			if err != nil {
				return missing("blob " + strconv.Itoa(i))
			}
			key := strconv.Itoa(i)
			sz, have := dj.Sizes[key]
			tasks = append(tasks, &xtask{key: key, idx: i, fp: fp, size: st.Size(), url: x.base + "/upload/" + x.id + "/blob/" + key, done: doneUp[i] && have && sz == st.Size()})
		}
	} else {
		b, err := os.ReadFile(filepath.Join(x.dir, "commit.json"))
		if err != nil {
			fmt.Println("FAIL")
			return 2
		}
		var plan struct {
			Items []map[string]interface{} `json:"items"`
		}
		dec := json.NewDecoder(bytes.NewReader(b))
		dec.UseNumber()
		if dec.Decode(&plan) != nil {
			fmt.Println("FAIL")
			return 2
		}
		n := 0
		for _, it := range plan.Items {
			if k, _ := it["k"].(string); k != "f" {
				continue
			}
			item := fmt.Sprint(it["i"])
			c := 0
			if cn, ok := it["c"].(json.Number); ok {
				c64, _ := cn.Int64()
				c = int(c64)
			}
			for i := 0; i < c; i++ {
				fp := filepath.Join(x.dir, item+"."+strconv.Itoa(i))
				st, err := os.Stat(fp)
				if err != nil {
					return missing("chunk " + item + "." + strconv.Itoa(i))
				}
				key := item + "." + strconv.Itoa(i)
				sz, have := dj.Sizes[key]
				tasks = append(tasks, &xtask{key: key, idx: n, fp: fp, size: st.Size(), url: x.base + "/ux/" + x.id + "/item/" + item + "/blob/" + strconv.Itoa(i), done: doneUx[item][i] && have && sz == st.Size()})
				n++
			}
		}
	}
	var todo []*xtask
	for _, t := range tasks {
		x.total += t.size
		if t.done {
			x.alreadyBytes += t.size
			if int64(t.idx) > x.lastIdx {
				x.lastIdx = int64(t.idx)
			}
		} else {
			todo = append(todo, t)
		}
	}
	x.ntasks = len(tasks)
	x.alreadyN = len(tasks) - len(todo)
	x.sent, x.safeBytes, x.doneN = x.alreadyBytes, x.alreadyBytes, int64(x.alreadyN)

	// ── halting: pause key / flags / signals ──
	sig := make(chan os.Signal, 4)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		for range sig {
			x.requestHalt("INTERRUPTED", 2500*time.Millisecond)
		}
	}()
	rawOn := false
	if isTTY(0) && x.tty {
		if restore, ok := makeRaw(); ok {
			rawOn = true
			defer restore()
			go func() {
				b := make([]byte, 1)
				for {
					if n, err := os.Stdin.Read(b); err != nil || n == 0 {
						return
					}
					switch b[0] {
					case 'p', 'P':
						x.requestHalt("PAUSED", 8*time.Second)
					case 3, 26: // Ctrl-C / Ctrl-Z: raw mode delivers them as keys
						x.requestHalt("INTERRUPTED", 2500*time.Millisecond)
					}
				}
			}()
		}
	}
	flag := func(n string) bool {
		if x.state == "" {
			return false
		}
		_, err := os.Stat(filepath.Join(x.state, n))
		return err == nil
	}
	checkFlags := func() {
		if flag("stop.flag") {
			x.requestHalt("STOPPED", 1500*time.Millisecond)
		} else if flag("pause.flag") {
			x.requestHalt("PAUSED", 8*time.Second)
		}
	}

	if x.alreadyN > 0 {
		fmt.Fprintf(os.Stderr, "↩️  Continuing: %d/%d blob(s) (%d%%) are already on the server — sending the remaining %d.\n", x.alreadyN, x.ntasks, x.alreadyBytes*100/maxI64(1, x.total), len(todo))
	}
	if rawOn && x.tty {
		fmt.Fprintln(os.Stderr, "   p = pause · Ctrl-C / Ctrl-Z = stop now and keep it for later (Pending → continue)")
	}

	var next int32 = -1
	var failed int32
	var errMu sync.Mutex
	var errs []string
	var wg sync.WaitGroup
	for w := 0; w < minInt(x.conc, maxInt(1, len(todo))); w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				if x.halting() {
					return
				}
				i := int(atomic.AddInt32(&next, 1))
				if i >= len(todo) {
					return
				}
				t := todo[i]
				if err := x.uploadOne(t); err != nil {
					if _, h := err.(halted); h {
						return
					}
					atomic.AddInt32(&failed, 1)
					errMu.Lock()
					if len(errs) < 3 {
						errs = append(errs, "blob "+strconv.Itoa(t.idx)+": "+err.Error())
					}
					errMu.Unlock()
					continue
				}
				atomic.AddInt64(&x.doneN, 1)
				atomic.AddInt64(&x.safeBytes, t.size)
				for {
					cur := atomic.LoadInt64(&x.lastIdx)
					if int64(t.idx) <= cur || atomic.CompareAndSwapInt64(&x.lastIdx, cur, int64(t.idx)) {
						break
					}
				}
			}
		}()
	}
	checkFlags() // a flag written just before we started counts too
	stop := make(chan struct{})
	go func() {
		flagT := time.NewTicker(500 * time.Millisecond)
		drawT := time.NewTicker(200 * time.Millisecond)
		noteT := time.NewTicker(2 * time.Second)
		defer flagT.Stop()
		defer drawT.Stop()
		defer noteT.Stop()
		for {
			select {
			case <-stop:
				return
			case <-flagT.C:
				checkFlags()
			case <-drawT.C:
				x.draw(false)
			case <-noteT.C:
				x.noter()
			}
		}
	}()
	x.noter()
	x.draw(false)
	wg.Wait()
	close(stop)
	x.noter()

	x.mu.Lock()
	halt, tokenDead, offDead := x.halt, x.tokenDead, x.offDead
	x.mu.Unlock()
	verdict := "OK"
	switch {
	case halt != "":
		verdict = halt
	case tokenDead:
		verdict = "TOKEN"
	case offDead:
		verdict = "OFFLINE"
	case atomic.LoadInt32(&failed) > 0:
		verdict = "FAIL"
	}
	if verdict == "OK" {
		x.draw(true)
	} else if x.tty {
		fmt.Fprint(os.Stderr, "\n")
	}
	// be honest about what a restart keeps: only COMPLETE blobs are on the server, a half-sent blob starts again from its first byte
	if safe := atomic.LoadInt64(&x.safeBytes); verdict != "OK" && x.tty && safe < x.total {
		fmt.Fprintf(os.Stderr, "  💾 %s of %s %s are safe on the server (%d/%d blobs) — blobs that were half-sent start again from their first byte.\n", x.fmtB(safe), x.fmtB(x.total), x.unit(), atomic.LoadInt64(&x.doneN), x.ntasks)
	}
	for _, m := range errs {
		fmt.Fprintf(os.Stderr, "  ⚠️  %s\n", m)
	}
	fmt.Println(verdict)
	return 0
}

func maxI64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
