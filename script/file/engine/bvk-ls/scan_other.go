//go:build !linux

package main

import "os"

const (
	dtUnknown = 0
	dtDir     = 4
	dtLnk     = 10
)

func readDir(dir string, keep func([]byte) bool) ([]ent, error) {
	f, err := os.Open(dir)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	des, err := f.ReadDir(-1)
	out := make([]ent, 0, len(des))
	for _, d := range des {
		if keep != nil && !keep([]byte(d.Name())) {
			continue
		}
		t := byte(dtUnknown)
		if d.IsDir() {
			t = dtDir
		} else if d.Type()&os.ModeSymlink != 0 {
			t = dtLnk
		}
		out = append(out, ent{name: d.Name(), typ: t})
	}
	return out, err
}
