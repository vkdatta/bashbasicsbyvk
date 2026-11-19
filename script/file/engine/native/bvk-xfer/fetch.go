package main

import (
	"crypto/aes"
	"crypto/cipher"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
	"context"
)

// fetch LINK OUTFILE [CONC]     — the Go version of _crypto_fetch_archive (the node one-liner it replaces).
//
//	env  BB_KEY  the link key (base64url)        BB_FETCH_AUTH=1  + BB_EMAIL BB_DISEPS BB_APIKEY for owner-only items (Saved Surf / Snapshots / Backup)
//
// Downloads the manifest, then every blob in parallel over ONE HTTP/2 connection, decrypts each (AES-256-GCM, AAD bbvk4|blob|<i>) and writes the
// plain bytes at their exact offset in OUTFILE (a pre-created empty file), so order does not matter and memory stays at a few chunks.
// stdout: "OK<TAB>name" | EXPIRED | BADKEY | FAILED
func cmdFetch(args []string) int {
	if len(args) < 2 {
		fmt.Println("FAILED")
		return 2
	}
	link, outfile := strings.TrimRight(args[0], "/"), args[1]
	conc := 8
	if len(args) > 2 {
		if v, err := strconv.Atoi(args[2]); err == nil && v > 0 {
			conc = v
		}
	}
	if conc > maxStreams {
		conc = maxStreams
	}
	kb, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(os.Getenv("BB_KEY"), "="))
	if err != nil || len(kb) != 32 {
		fmt.Println("BADKEY")
		return 0
	}
	blk, _ := aes.NewCipher(kb)
	g, _ := cipher.NewGCM(blk)
	dec := func(buf []byte, aad string) ([]byte, error) {
		if len(buf) < 28 {
			return nil, fmt.Errorf("short")
		}
		ct := buf[12:]
		return g.Open(ct[:0], buf[:12], ct, []byte(aad)) // in place: no second copy of the blob
	}
	cl := newClient(conc)
	auth := os.Getenv("BB_FETCH_AUTH") == "1"
	get := func(url string) []byte {
		for a := 0; a < 4; a++ {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
			req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
			if err == nil {
				if auth {
					req.Header.Set("X-User-Email", os.Getenv("BB_EMAIL"))
					req.Header.Set("X-User-Diseps", os.Getenv("BB_DISEPS"))
					req.Header.Set("X-User-Key", os.Getenv("BB_APIKEY"))
				}
				var res *http.Response
				res, err = cl.Do(req)
				if err == nil {
					b, rerr := io.ReadAll(io.LimitReader(res.Body, 100<<20))
					res.Body.Close()
					if res.StatusCode == 200 && rerr == nil {
						cancel()
						return b
					}
					if res.StatusCode == 404 {
						cancel()
						return nil
					}
				}
			}
			cancel()
			time.Sleep(time.Duration(a+1) * 300 * time.Millisecond)
		}
		return nil
	}

	mbuf := get(link + "/manifest")
	if mbuf == nil {
		fmt.Println("EXPIRED")
		return 0
	}
	mp, err := dec(mbuf, "bbvk4|manifest")
	var m struct {
		Version    int    `json:"version"`
		Format     string `json:"format"`
		Name       string `json:"name"`
		Size       int64  `json:"size"`
		ChunkBytes int64  `json:"chunkBytes"`
		BlobCount  int    `json:"blobCount"`
	}
	if err != nil || json.Unmarshal(mp, &m) != nil {
		fmt.Println("BADKEY")
		return 0
	}
	n, C, size := m.BlobCount, m.ChunkBytes, m.Size
	if m.Version != 4 || m.Format != "tar.gz" || n < 1 || n > 199999 || C < 1048576 || C > 94371840 || size <= int64(n-1)*C || size > int64(n)*C {
		fmt.Println("BADKEY")
		return 0
	}
	f, err := os.OpenFile(outfile, os.O_RDWR, 0)
	if err != nil {
		fmt.Println("FAILED")
		return 0
	}
	defer f.Close()

	tty := isTTY(2)
	var done int64
	var drawMu sync.Mutex
	lastPct := -1
	bar := func() {
		if !tty {
			return
		}
		drawMu.Lock()
		defer drawMu.Unlock()
		d := int(atomic.LoadInt64(&done))
		pct := d * 100 / n
		if pct == lastPct && d < n {
			return
		}
		lastPct = pct
		const cols = 24
		fl := pct * cols / 100
		color := "\x1b[36m"
		if d >= n {
			color = "\x1b[32m"
		}
		fmt.Fprintf(os.Stderr, "\x1b[?7l\r\x1b[K%s[%s%s] %3d%%\x1b[0m  📥 Downloading + 🔓 decrypting %d/%d\x1b[?7h", color, strings.Repeat("█", fl), strings.Repeat("░", cols-fl), pct, d, n)
		if d >= n {
			fmt.Fprint(os.Stderr, "\n")
		}
	}
	var next int32 = -1
	var failed atomic.Bool
	workers := conc
	if w := int(134217728 / C); w > workers { // small blobs: keep ~128 MB in flight
		workers = w
	}
	if workers > 24 {
		workers = 24
	}
	if workers > n {
		workers = n
	}
	var wg sync.WaitGroup
	bar()
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for !failed.Load() {
				i := int(atomic.AddInt32(&next, 1))
				if i >= n {
					return
				}
				blob := get(link + "/file/" + strconv.Itoa(i))
				if blob == nil {
					failed.Store(true)
					return
				}
				plain, err := dec(blob, "bbvk4|blob|"+strconv.Itoa(i))
				want := C
				if i == n-1 {
					want = size - int64(n-1)*C
				}
				if err != nil || int64(len(plain)) != want {
					failed.Store(true)
					return
				}
				if _, err := f.WriteAt(plain, int64(i)*C); err != nil {
					failed.Store(true)
					return
				}
				atomic.AddInt64(&done, 1)
				bar()
			}
		}()
	}
	wg.Wait()
	if tty && failed.Load() {
		fmt.Fprint(os.Stderr, "\n")
	}
	if failed.Load() {
		fmt.Println("FAILED")
		return 0
	}
	name := strings.NewReplacer("\t", " ", "\n", " ", "\r", " ").Replace(m.Name)
	if name == "" {
		name = "files.tar.gz"
	}
	fmt.Printf("OK\t%s\n", name)
	return 0
}
