//go:build !linux

package main

import "os"

func freeBytes(path string) (uint64, bool) { return 0, false }
func getUmask() os.FileMode               { return 0o022 }
