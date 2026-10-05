//go:build darwin

package main

import "syscall"

func mtimeSec(st *syscall.Stat_t) int64 { return int64(st.Mtimespec.Sec) }
