//go:build !linux && !darwin && !freebsd

package main

func isTTY(fd int) bool            { return false }
func makeRaw() (func(), bool)      { return nil, false }
func termCols() int                { return 60 }
