package main

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Format v4 (identical to the node packer it replaces, so every client can still download / decrypt):
//
//	the selection is ONE tar.gz stream cut into fixed-size chunks; each chunk is encrypted on its own with AES-256-GCM:
//	blob = [12B IV][ciphertext][16B tag], AAD "bbvk4|blob|<index>"; manifest.enc = the same around
//	{"version":4,"format":"tar.gz","name":…,"size":<plain bytes>,"chunkBytes":…,"blobCount":…}, AAD "bbvk4|manifest".
func seal(g cipher.AEAD, plain []byte, aad string) ([]byte, error) {
	out := make([]byte, 12, 12+len(plain)+16)
	if _, err := io.ReadFull(rand.Reader, out); err != nil {
		return nil, err
	}
	return g.Seal(out, out[:12], plain, []byte(aad)), nil
}

type chunker struct {
	g          cipher.AEAD
	dir        string
	buf        []byte
	fill       int
	idx        int
	plainTotal int64
	cipherTot  int64
	seen       int64
	t0         time.Time
	lastDraw   time.Time
	tty        bool
}

func (c *chunker) Write(p []byte) (int, error) {
	n := len(p)
	for len(p) > 0 {
		k := copy(c.buf[c.fill:], p)
		c.fill += k
		p = p[k:]
		if c.fill == len(c.buf) {
			if err := c.flush(); err != nil {
				return 0, err
			}
		}
	}
	c.seen += int64(n)
	c.status(false)
	return n, nil
}

func (c *chunker) flush() error {
	if c.fill == 0 {
		return nil
	}
	rec, err := seal(c.g, c.buf[:c.fill], "bbvk4|blob|"+strconv.Itoa(c.idx))
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(c.dir, "blob"+strconv.Itoa(c.idx)), rec, 0o600); err != nil {
		return err
	}
	c.cipherTot += int64(len(rec))
	c.plainTotal += int64(c.fill)
	c.idx++
	c.fill = 0
	return nil
}

func (c *chunker) status(final bool) {
	if !c.tty {
		return
	}
	now := time.Now()
	if !final && now.Sub(c.lastDraw) < 150*time.Millisecond {
		return
	}
	c.lastDraw = now
	fmt.Fprintf(os.Stderr, "\x1b[?7l\r\x1b[K\x1b[36m📦→🔐 %.1f MB (%ds)\x1b[0m\x1b[?7h", float64(c.seen)/1048576, int(now.Sub(c.t0).Seconds()))
	if final {
		fmt.Fprint(os.Stderr, "\n")
	}
}

type zeros struct{}

func (zeros) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 0
	}
	return len(p), nil
}

// pack --out DIR --name NAME [--chunk BYTES] [--level 1-9] [--rc FILE]     (cwd = the staging folder; paths on stdin, NUL-separated)
// stdout: key \n total-cipher-bytes \n blob-count        exit 0 ok · 2 nothing to pack · 3 failed
// --rc FILE gets "0" or "1" (1 = some files changed or could not be read while packing — they may be missing/partial; same meaning as tar's exit 1)
func cmdPack(args []string) int {
	fs := flag.NewFlagSet("pack", flag.ContinueOnError)
	out := fs.String("out", "", "folder for blob<N> and manifest.enc")
	name := fs.String("name", "files.tar.gz", "display name stored in the manifest")
	chunk := fs.Int("chunk", 4<<20, "plain bytes per blob")
	level := fs.Int("level", 6, "gzip level 1-9")
	rcfile := fs.String("rc", "", "file that receives the packing status")
	warnfile := fs.String("warn", "", "file that receives warnings (default: stderr)")
	if err := fs.Parse(args); err != nil || *out == "" {
		return 2
	}
	if *chunk < 1<<20 {
		*chunk = 1 << 20
	}
	if *chunk > 90<<20 {
		*chunk = 90 << 20
	}
	if *level < 1 || *level > 9 {
		*level = 6
	}
	key := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, key); err != nil {
		fmt.Fprintln(os.Stderr, "  ❌ no randomness:", err)
		return 3
	}
	blk, err := aes.NewCipher(key)
	if err != nil {
		return 3
	}
	g, err := cipher.NewGCM(blk)
	if err != nil {
		return 3
	}
	st, _ := os.Stderr.Stat()
	ck := &chunker{g: g, dir: *out, buf: make([]byte, *chunk), t0: time.Now(), tty: st != nil && st.Mode()&os.ModeCharDevice != 0}
	gz, _ := gzip.NewWriterLevel(ck, *level)
	tw := tar.NewWriter(gz)
	rc := 0
	var wf *os.File
	if *warnfile != "" {
		wf, _ = os.OpenFile(*warnfile, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o600)
	}
	warn := func(format string, a ...interface{}) {
		rc = 1
		var w io.Writer = os.Stderr
		if wf != nil {
			w = wf
		}
		fmt.Fprintf(w, "tar: "+format+"\n", a...)
	}
	fail := func(e error) int {
		if ck.tty {
			fmt.Fprint(os.Stderr, "\n")
		}
		msg := "Packing failed: " + e.Error()
		if strings.Contains(e.Error(), "no space left") {
			msg = "Disk full while writing encrypted blobs."
		}
		fmt.Fprintln(os.Stderr, "  ❌ "+msg)
		return 3
	}
	in := bufio.NewReaderSize(os.Stdin, 1<<20)
	for {
		p, rerr := in.ReadString(0)
		p = strings.TrimSuffix(p, "\x00")
		if p != "" {
			// like tar -h: symlinks (the staging links at the top level) are followed; only files and folders are stored
			fi, err := os.Stat(p)
			if err != nil {
				warn("%s: %v", p, err)
			} else if fi.IsDir() {
				if err := tw.WriteHeader(&tar.Header{Typeflag: tar.TypeDir, Name: strings.TrimSuffix(p, "/") + "/", Mode: int64(fi.Mode().Perm()), ModTime: fi.ModTime()}); err != nil {
					return fail(err)
				}
			} else if fi.Mode().IsRegular() {
				f, err := os.Open(p)
				if err != nil {
					warn("%s: %v", p, err)
				} else {
					size := fi.Size()
					if err := tw.WriteHeader(&tar.Header{Typeflag: tar.TypeReg, Name: p, Mode: int64(fi.Mode().Perm()), Size: size, ModTime: fi.ModTime()}); err != nil {
						f.Close()
						return fail(err)
					}
					n, err := io.Copy(tw, io.LimitReader(f, size)) // a file that grew is cut at its announced size …
					f.Close()
					if err != nil {
						return fail(err)
					}
					if n < size { // … one that shrank is padded, so the archive stays valid
						warn("%s: file shrank while packing", p)
						if _, err := io.CopyN(tw, zeros{}, size-n); err != nil {
							return fail(err)
						}
					}
				}
			}
		}
		if rerr != nil {
			break
		}
	}
	if err := tw.Close(); err != nil {
		return fail(err)
	}
	if err := gz.Close(); err != nil {
		return fail(err)
	}
	if err := ck.flush(); err != nil {
		return fail(err)
	}
	ck.status(true)
	if *rcfile != "" {
		_ = os.WriteFile(*rcfile, []byte(strconv.Itoa(rc)+"\n"), 0o600)
	}
	if ck.idx == 0 {
		fmt.Fprintln(os.Stderr, "  ❌ Nothing to pack.")
		return 2
	}
	man, _ := json.Marshal(map[string]interface{}{"version": 4, "format": "tar.gz", "name": *name, "size": ck.plainTotal, "chunkBytes": *chunk, "blobCount": ck.idx})
	rec, err := seal(g, man, "bbvk4|manifest")
	if err != nil {
		return fail(err)
	}
	if err := os.WriteFile(filepath.Join(*out, "manifest.enc"), rec, 0o600); err != nil {
		return fail(err)
	}
	fmt.Printf("%s\n%d\n%d", base64.RawURLEncoding.EncodeToString(key), ck.cipherTot, ck.idx)
	return 0
}
