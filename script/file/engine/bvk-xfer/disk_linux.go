//go:build linux

package main

import (
	"os"
	"syscall"
)

func freeBytes(path string) (uint64, bool) {
	var st syscall.Statfs_t
	if syscall.Statfs(path, &st) != nil {
		return 0, false
	}
	return uint64(st.Bavail) * uint64(st.Bsize), true
}

func getUmask() os.FileMode {
	m := syscall.Umask(0)
	syscall.Umask(m)
	return os.FileMode(m)
}
