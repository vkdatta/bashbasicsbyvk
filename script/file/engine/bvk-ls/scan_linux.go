//go:build linux

package main

import (
	"bytes"
	"encoding/binary"
	"syscall"
	"unsafe"
)

const (
	dtUnknown = 0
	dtDir     = 4
	dtLnk     = 10
)

// arena hands out string storage from big chunks so 500k names cost a few
// hundred allocations instead of 500k.
type arena struct{ cur []byte }

func (a *arena) str(b []byte) string {
	n := len(b)
	if n == 0 {
		return ""
	}
	if cap(a.cur)-len(a.cur) < n {
		sz := 1 << 20
		if n > sz {
			sz = n
		}
		a.cur = make([]byte, 0, sz)
	}
	start := len(a.cur)
	a.cur = append(a.cur, b...)
	return unsafe.String(&a.cur[start], n)
}

// readDir lists dir with raw getdents64 and a 1 MiB buffer.
// keep(nameBytes) decides whether an entry is retained (hidden/prefix filter).
func readDir(dir string, keep func([]byte) bool) ([]ent, error) {
	fd, err := syscall.Open(dir, syscall.O_RDONLY|syscall.O_DIRECTORY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, err
	}
	defer syscall.Close(fd)

	buf := make([]byte, 1<<20)
	out := make([]ent, 0, 4096)
	var ar arena
	for {
		n, err := syscall.ReadDirent(fd, buf)
		if err != nil {
			return out, err
		}
		if n <= 0 {
			return out, nil
		}
		for o := 0; o < n; {
			reclen := int(binary.NativeEndian.Uint16(buf[o+16:]))
			ino := binary.NativeEndian.Uint64(buf[o:])
			typ := buf[o+18]
			nm := buf[o+19 : o+reclen]
			if i := bytes.IndexByte(nm, 0); i >= 0 {
				nm = nm[:i]
			}
			o += reclen
			if ino == 0 || len(nm) == 0 {
				continue
			}
			if nm[0] == '.' && (len(nm) == 1 || (len(nm) == 2 && nm[1] == '.')) {
				continue
			}
			if keep != nil && !keep(nm) {
				continue
			}
			out = append(out, ent{name: ar.str(nm), typ: typ})
		}
	}
}
