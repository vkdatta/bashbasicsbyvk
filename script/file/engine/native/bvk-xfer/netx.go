package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// A static Go binary on Android/Termux has no /etc/resolv.conf and no CA bundle in the places Go looks.  Both are handled here, so the
// SAME binary works on Linux and on Android (NDK builds behave the same way).

func readNameservers(paths []string) []string {
	var ns []string
	for _, p := range paths {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			fl := strings.Fields(sc.Text())
			if len(fl) >= 2 && fl[0] == "nameserver" {
				ns = append(ns, fl[1])
			}
		}
		f.Close()
		if len(ns) > 0 {
			break
		}
	}
	return ns
}

func resolver() *net.Resolver {
	paths := []string{"/etc/resolv.conf"}
	if pre := os.Getenv("PREFIX"); pre != "" {
		paths = append(paths, pre+"/etc/resolv.conf")
	}
	if _, err := os.Stat("/etc/resolv.conf"); err == nil {
		return nil // a normal system: Go's own resolver reads it
	}
	ns := readNameservers(paths)
	if len(ns) == 0 {
		ns = []string{"1.1.1.1", "8.8.8.8", "9.9.9.9"}
	}
	return &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		d := net.Dialer{Timeout: 4 * time.Second}
		var last error
		for _, s := range ns {
			c, err := d.DialContext(ctx, network, net.JoinHostPort(s, "53"))
			if err == nil {
				return c, nil
			}
			last = err
		}
		return nil, last
	}}
}

func loadRoots() *x509.CertPool {
	if sys, err := x509.SystemCertPool(); err == nil && sys != nil && len(sys.Subjects()) > 0 { //nolint:staticcheck
		return sys
	}
	pool := x509.NewCertPool()
	files := []string{
		"/etc/ssl/certs/ca-certificates.crt", "/etc/pki/tls/certs/ca-bundle.crt", "/etc/ssl/cert.pem",
		"/data/data/com.termux/files/usr/etc/tls/cert.pem",
	}
	dirs := []string{"/apex/com.android.conscrypt/cacerts", "/system/etc/security/cacerts", "/etc/ssl/certs"}
	if pre := os.Getenv("PREFIX"); pre != "" {
		files = append(files, pre+"/etc/tls/cert.pem", pre+"/etc/ssl/certs/ca-certificates.crt")
	}
	if f := os.Getenv("SSL_CERT_FILE"); f != "" {
		files = append([]string{f}, files...)
	}
	loaded := false
	for _, f := range files {
		if b, err := os.ReadFile(f); err == nil && pool.AppendCertsFromPEM(b) {
			loaded = true
		}
	}
	if !loaded {
		for _, d := range dirs {
			ents, err := os.ReadDir(d)
			if err != nil {
				continue
			}
			for _, e := range ents {
				if e.IsDir() {
					continue
				}
				if b, err := os.ReadFile(filepath.Join(d, e.Name())); err == nil && pool.AppendCertsFromPEM(b) {
					loaded = true
				}
			}
			if loaded {
				break
			}
		}
	}
	return pool
}

// Transfer-profile limits (Settings > File API > Transfer speed): the SAME numbers are in the worker (worker.js TRANSFER_LIMITS) and in
// bashbasicsbyvk_xfersettings.sh.  Streams = parallel requests; a chunk is the plain bytes of one encrypted blob.
const (
	maxStreams       = 64
	minChunkBytes    = 1 << 20
	maxChunkBytes    = 64 << 20
	maxInFlightBytes = 512 << 20
	blobOverhead     = 28 // 12-byte IV + 16-byte GCM tag
)

// one client for the whole run: one TCP+TLS handshake, then HTTP/2 streams over it (and a few extra connections when many blobs fly at once)
func newClient(conc int) *http.Client {
	if conc < 2 {
		conc = 2
	}
	tr := &http.Transport{
		Proxy:               http.ProxyFromEnvironment,
		DialContext:         (&net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second, Resolver: resolver()}).DialContext,
		ForceAttemptHTTP2:   true,
		TLSClientConfig:     &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: loadRoots()},
		TLSHandshakeTimeout: 15 * time.Second,
		MaxIdleConns:        conc * 2,
		MaxIdleConnsPerHost: conc * 2,
		IdleConnTimeout:     60 * time.Second,
	}
	return &http.Client{
		Transport:     tr,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }, // never follow a redirect (it could carry headers elsewhere)
	}
}

// netcheck URL — every stage on its own line, so `health` can say WHICH one breaks on a machine:
//
//	resolver system|fallback(1.1.1.1,…)   dns <ms> <ip>   roots <n>   tls <ms> <version> <alpn>   http <status> <ms>      or   ERR <stage> <message>
func cmdNetcheck(args []string) int {
	if len(args) != 1 || !strings.HasPrefix(args[0], "https://") {
		fmt.Fprintln(os.Stderr, "usage: bvk-xfer netcheck https://host")
		return 2
	}
	u, err := url.Parse(args[0])
	if err != nil || u.Hostname() == "" {
		fmt.Println("ERR url bad address")
		return 1
	}
	host := u.Hostname()
	port := u.Port()
	if port == "" {
		port = "443"
	}
	r := resolver()
	if r == nil {
		fmt.Println("resolver system (/etc/resolv.conf)")
		r = net.DefaultResolver
	} else {
		fmt.Println("resolver fallback (no /etc/resolv.conf: Termux file or 1.1.1.1 / 8.8.8.8 / 9.9.9.9)")
	}
	t0 := time.Now()
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	ips, err := r.LookupHost(ctx, host)
	cancel()
	if err != nil || len(ips) == 0 {
		fmt.Printf("ERR dns %v\n", err)
		return 1
	}
	fmt.Printf("dns %d ms %s\n", time.Since(t0).Milliseconds(), ips[0])
	pool := loadRoots()
	fmt.Printf("roots %d\n", len(pool.Subjects())) //nolint:staticcheck
	t1 := time.Now()
	conn, err := tls.DialWithDialer(&net.Dialer{Timeout: 8 * time.Second}, "tcp", net.JoinHostPort(ips[0], port),
		&tls.Config{ServerName: host, RootCAs: pool, MinVersion: tls.VersionTLS12, NextProtos: []string{"h2", "http/1.1"}})
	if err != nil {
		fmt.Printf("ERR tls %v\n", err)
		return 1
	}
	st := conn.ConnectionState()
	conn.Close()
	ver := map[uint16]string{tls.VersionTLS12: "TLS1.2", tls.VersionTLS13: "TLS1.3"}[st.Version]
	fmt.Printf("tls %d ms %s %s\n", time.Since(t1).Milliseconds(), ver, st.NegotiatedProtocol)
	t2 := time.Now()
	req, _ := http.NewRequest("GET", args[0], nil)
	resp, err := newClient(2).Do(req)
	if err != nil {
		fmt.Printf("ERR http %v\n", err)
		return 1
	}
	resp.Body.Close()
	fmt.Printf("http %d %d ms\n", resp.StatusCode, time.Since(t2).Milliseconds())
	return 0
}
