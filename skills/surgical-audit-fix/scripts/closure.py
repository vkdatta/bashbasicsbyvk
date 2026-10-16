#!/usr/bin/env python3
"""Bounded dependency closure for named files, at T1 (purpose + exports), not file contents.

  closure.py <repo> a.ts b.ts [--up 1] [--down 1] [--max 40]
Supports Python and JS/TS/Vue/Svelte imports. Other languages: use rg / language server.
Prints cut-off notes so the report can state what was NOT traced.
"""
import argparse, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import build_graph, purpose, exports

def bfs(start, edges, depth):
    seen = {s: 0 for s in start}
    frontier = list(start)
    for d in range(1, depth + 1):
        nxt = []
        for f in frontier:
            for t in sorted(edges.get(f, ())):
                if t not in seen:
                    seen[t] = d
                    nxt.append(t)
        frontier = nxt
    return seen, frontier

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root"); ap.add_argument("files", nargs="+")
    ap.add_argument("--up", type=int, default=1); ap.add_argument("--down", type=int, default=1)
    ap.add_argument("--max", type=int, default=40)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    fs, down, up = build_graph(root)
    start = []
    for f in a.files:
        r = os.path.normpath(os.path.relpath(os.path.abspath(f) if os.path.isabs(f) else os.path.join(root, f), root))
        if r in fs:
            start.append(r)
        else:
            print(f"! not found or unsupported language: {f}", file=sys.stderr)
    if not start:
        sys.exit("no usable files")
    ups, upf = bfs(start, up, a.up)
    downs, downf = bfs(start, down, a.down)

    def line(f, tag):
        full = os.path.join(root, f)
        return f"- [{tag}] `{f}` {purpose(full)} | {', '.join(exports(full, 8))}"

    shown = 0
    print("# closure (T1: purpose + exports)")
    for s in start:
        print(line(s, "target")); shown += 1
    print("## upstream (importers)")
    for f, d in sorted(ups.items(), key=lambda x: x[1]):
        if f in start: continue
        if shown >= a.max: print("... truncated (--max)"); break
        print(line(f, f"up{d}")); shown += 1
    print("## downstream (imports)")
    for f, d in sorted(downs.items(), key=lambda x: x[1]):
        if f in start: continue
        if shown >= a.max: print("... truncated (--max)"); break
        print(line(f, f"down{d}")); shown += 1
    cut_up = sorted({t for f in upf for t in up.get(f, ()) if t not in ups})
    cut_dn = sorted({t for f in downf for t in down.get(f, ()) if t not in downs})
    print("## cut-offs (not traced)")
    print(f"- upstream beyond depth {a.up}: {len(cut_up)} files" + (f" e.g. {cut_up[:3]}" if cut_up else ""))
    print(f"- downstream beyond depth {a.down}: {len(cut_dn)} files" + (f" e.g. {cut_dn[:3]}" if cut_dn else ""))
    print("- dynamic imports, DI, reflection, string-based routing, non-Py/JS languages are NOT captured; confirm with rg")

if __name__ == "__main__":
    main()
