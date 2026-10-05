//go:build linux

package main

import "syscall"

func mtimeSec(st *syscall.Stat_t) int64 { return int64(st.Mtim.Sec) }
