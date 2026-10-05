// bvk-ls: fast directory lister for bashbasicsbyvk. Drop-in replacement for
// the Python scan / meta / recursive-size helpers, plus a one-shot "window"
// call so the shell never has to hold a 500k-element array.
//
//	bvk-ls scan   DIR MODE HIDDEN [PREFIX]        sorted full paths
//	bvk-ls meta   PATHS_FILE                      path|size|mtime|children|icon
//	bvk-ls dsize  PATHS_FILE                      path|recursive_size
//	bvk-ls count  DIR HIDDEN                      number of entries
//	bvk-ls window DIR MODE HIDDEN PREFIX START N  "#total" then meta rows for [START, START+N)
//
// MODE: az za new old big small   HIDDEN: 1|0   START is 1-based.
package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

type ent struct {
	name  string
	low   string // lowercase name, computed once (az/za sort)
	typ   byte
	size  int64
	mtime int64
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, "bvk-ls:", err)
	os.Exit(1)
}

func join(dir, name string) string {
	if strings.HasSuffix(dir, "/") {
		return dir + name
	}
	return dir + "/" + name
}

func lowerASCII(s string) string { return strings.ToLower(s) }

func list(dir string, hidden bool, pfx string) []ent {
	lp := strings.ToLower(pfx)
	keep := func(nm []byte) bool {
		if !hidden && nm[0] == '.' {
			return false
		}
		return lp == "" || strings.HasPrefix(strings.ToLower(string(nm)), lp)
	}
	es, err := readDir(dir, keep)
	if err != nil && len(es) == 0 {
		fatal(err)
	}
	return es
}

// statAll fills size/mtime for every entry using all cores.
func statAll(dir string, es []ent) {
	w := runtime.NumCPU()
	if w > 16 {
		w = 16
	}
	var wg sync.WaitGroup
	chunk := (len(es) + w - 1) / w
	for s := 0; s < len(es); s += chunk {
		e := s + chunk
		if e > len(es) {
			e = len(es)
		}
		wg.Add(1)
		go func(part []ent) {
			defer wg.Done()
			var st syscall.Stat_t
			for i := range part {
				if err := syscall.Stat(join(dir, part[i].name), &st); err != nil {
					continue
				}
				part[i].mtime = mtimeSec(&st)
				if st.Mode&syscall.S_IFMT != syscall.S_IFDIR {
					part[i].size = int64(st.Size)
				}
			}
		}(es[s:e])
	}
	wg.Wait()
}

func sortEnts(dir, mode string, es []ent) {
	switch mode {
	case "az", "za":
		for i := range es {
			es[i].low = lowerASCII(es[i].name)
		}
		slices.SortFunc(es, func(a, b ent) int {
			c := strings.Compare(a.low, b.low)
			if c == 0 {
				c = strings.Compare(a.name, b.name)
			}
			if mode == "za" {
				return -c
			}
			return c
		})
	case "new", "old", "big", "small":
		statAll(dir, es)
		slices.SortFunc(es, func(a, b ent) int {
			var x, y int64
			switch mode {
			case "new", "old":
				x, y = a.mtime, b.mtime
			default:
				x, y = a.size, b.size
			}
			c := 0
			if x < y {
				c = -1
			} else if x > y {
				c = 1
			}
			if mode == "new" || mode == "big" {
				c = -c
			}
			if c == 0 {
				c = strings.Compare(a.name, b.name)
			}
			return c
		})
	}
}

func countChildren(p string) int {
	f, err := os.Open(p)
	if err != nil {
		return -1
	}
	defer f.Close()
	n := 0
	for {
		names, err := f.Readdirnames(4096)
		n += len(names)
		if err != nil {
			break
		}
	}
	return n
}

// metaLine is the exact Python stat_one() format.
func metaLine(p string) string {
	var st syscall.Stat_t
	if err := syscall.Stat(p, &st); err != nil {
		return p + "|0|0|-1|plain"
	}
	isDir := st.Mode&syscall.S_IFMT == syscall.S_IFDIR
	size, ch := int64(st.Size), -1
	if isDir {
		size = 0
		ch = countChildren(p)
	}
	return p + "|" + strconv.FormatInt(size, 10) + "|" + strconv.FormatInt(mtimeSec(&st), 10) +
		"|" + strconv.Itoa(ch) + "|" + icon(filepath.Base(p), isDir, uint32(st.Mode))
}

func metaMany(paths []string) []string {
	out := make([]string, len(paths))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 16)
	for i := range paths {
		sem <- struct{}{}
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			out[i] = metaLine(paths[i])
			<-sem
		}(i)
	}
	wg.Wait()
	return out
}

func readLines(file string) []string {
	b, err := os.ReadFile(file)
	if err != nil {
		fatal(err)
	}
	var out []string
	for _, l := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(l) != "" {
			out = append(out, l)
		}
	}
	return out
}

func dirSize(root string) int64 {
	var total int64
	var walk func(string)
	walk = func(d string) {
		ents, err := os.ReadDir(d)
		if err != nil {
			return
		}
		for _, e := range ents {
			if e.IsDir() {
				walk(join(d, e.Name()))
				continue
			}
			if info, err := e.Info(); err == nil {
				total += info.Size()
			}
		}
	}
	walk(root)
	return total
}

func main() {
	if len(os.Args) < 2 {
		fatal(fmt.Errorf("usage: bvk-ls scan|meta|dsize|count|window ..."))
	}
	out := bufio.NewWriterSize(os.Stdout, 1<<20)
	defer out.Flush()
	a := os.Args[2:]
	arg := func(i int) string {
		if i < len(a) {
			return a[i]
		}
		return ""
	}

	switch os.Args[1] {
	case "scan":
		dir, mode := arg(0), arg(1)
		es := list(dir, arg(2) == "1", arg(3))
		sortEnts(dir, mode, es)
		for _, e := range es {
			out.WriteString(join(dir, e.name))
			out.WriteByte('\n')
		}
	case "count":
		fmt.Fprintln(out, len(list(arg(0), arg(1) == "1", "")))
	case "meta":
		for _, l := range metaMany(readLines(arg(0))) {
			out.WriteString(l)
			out.WriteByte('\n')
		}
	case "dsize":
		paths := readLines(arg(0))
		res := make([]int64, len(paths))
		var wg sync.WaitGroup
		sem := make(chan struct{}, runtime.NumCPU()*2)
		for i, p := range paths {
			sem <- struct{}{}
			wg.Add(1)
			go func(i int, p string) {
				defer wg.Done()
				res[i] = dirSize(p)
				<-sem
			}(i, p)
		}
		wg.Wait()
		for i, p := range paths {
			fmt.Fprintf(out, "%s|%d\n", p, res[i])
		}
	case "window":
		dir, mode := arg(0), arg(1)
		start, _ := strconv.Atoi(arg(4))
		n, _ := strconv.Atoi(arg(5))
		if start < 1 {
			start = 1
		}
		es := list(dir, arg(2) == "1", arg(3))
		sortEnts(dir, mode, es)
		fmt.Fprintf(out, "#%d\n", len(es))
		lo, hi := start-1, start-1+n
		if hi > len(es) {
			hi = len(es)
		}
		if lo < hi {
			ps := make([]string, 0, hi-lo)
			for _, e := range es[lo:hi] {
				ps = append(ps, join(dir, e.name))
			}
			for _, l := range metaMany(ps) {
				out.WriteString(l)
				out.WriteByte('\n')
			}
		}
	default:
		fatal(fmt.Errorf("unknown command %q", os.Args[1]))
	}
}
