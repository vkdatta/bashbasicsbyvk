package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// untar ARCHIVE STAGE   — safe extraction of a downloaded tar.gz in ONE pass (the shell used three tar passes: list, list names, extract).
// The archive comes from a link, so it is untrusted:
//   - only regular files and folders are accepted (a link/device entry = refuse: no way to write outside STAGE through a planted link)
//   - absolute names and ".." components are refused; every target is checked to stay inside STAGE
//   - the sizes the archive DECLARES are added up as it goes and compared with the free space: a tar.gz bomb stops early
//   - modes follow the umask (like tar --no-same-permissions); owners are never restored
//
// stdout: "OK<TAB>files<TAB>bytes"  or  "ERR<TAB>message"
func cmdUntar(args []string) int {
	if len(args) != 2 {
		fmt.Println("ERR\tusage: untar ARCHIVE STAGE")
		return 2
	}
	arc, stage := args[0], args[1]
	stage, _ = filepath.Abs(stage)
	fail := func(format string, a ...interface{}) int {
		fmt.Printf("ERR\t"+format+"\n", a...)
		return 0
	}
	f, err := os.Open(arc)
	if err != nil {
		return fail("cannot open the archive: %v", err)
	}
	defer f.Close()
	zr, err := gzip.NewReader(f)
	if err != nil {
		return fail("The decrypted archive is not a valid tar.gz — refusing to unpack.")
	}
	tr := tar.NewReader(zr)
	free, haveFree := freeBytes(stage)
	umask := getUmask()
	var files, expanded uint64
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fail("The decrypted archive is not a valid tar.gz — refusing to unpack.")
		}
		switch h.Typeflag {
		case tar.TypeXGlobalHeader:
			continue
		case tar.TypeReg, tar.TypeRegA, tar.TypeDir:
		default:
			return fail("Archive contains a link/special entry — refusing to unpack (possible path-escape attack).")
		}
		name := h.Name
		if strings.HasPrefix(name, "/") {
			return fail("Archive contains absolute or '..' paths — refusing to unpack.")
		}
		for _, c := range strings.Split(name, "/") {
			if c == ".." {
				return fail("Archive contains absolute or '..' paths — refusing to unpack.")
			}
		}
		target := filepath.Join(stage, filepath.FromSlash(name))
		if rel, err := filepath.Rel(stage, target); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return fail("Archive contains absolute or '..' paths — refusing to unpack.")
		}
		if h.Typeflag == tar.TypeDir {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return fail("Unpacking failed: %v", err)
			}
			continue
		}
		if h.Size < 0 {
			return fail("Archive is damaged.")
		}
		expanded += uint64(h.Size)
		if haveFree && expanded > free {
			return fail("Not enough free space: archive expands to more than %d MB, only %d MB free in %s.", expanded/1048576, free/1048576, filepath.Dir(stage))
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return fail("Unpacking failed: %v", err)
		}
		mode := (os.FileMode(h.Mode) & 0o777) &^ umask
		out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, mode|0o600)
		if err != nil {
			return fail("Unpacking failed: %v", err)
		}
		_, cerr := io.Copy(out, tr)
		if e := out.Close(); cerr == nil {
			cerr = e
		}
		if cerr != nil {
			return fail("Unpacking failed: %v", cerr)
		}
		if !h.ModTime.IsZero() {
			_ = os.Chtimes(target, h.ModTime, h.ModTime)
		}
		files++
	}
	fmt.Printf("OK\t%d\t%d\n", files, expanded)
	return 0
}
