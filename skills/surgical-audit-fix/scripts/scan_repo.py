#!/usr/bin/env python3
"""T0/T1 skim of a repo with hard output caps.

  scan_repo.py <repo>                 -> T0: folder tree (depth 2) with code-file counts + entry points
  scan_repo.py <repo> --dir src/orders -> T1: one line per file in that folder: purpose + exports
Use the output to pick a scope; never to read whole files.
"""
import argparse, os, json, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import walk, purpose, exports, IGNORE_DIRS

ENTRY_NAMES = {"main.py", "app.py", "manage.py", "__main__.py", "index.js", "index.ts", "index.tsx", "main.ts",
               "main.js", "server.js", "server.ts", "app.js", "app.ts", "main.go", "main.rs", "Main.java", "worker.js"}
MANIFESTS = {"package.json", "pyproject.toml", "setup.py", "go.mod", "Cargo.toml", "pom.xml", "build.gradle",
             "Dockerfile", "wrangler.toml", "vite.config.ts", "vite.config.js", "next.config.js", "tsconfig.json"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--dir", help="repo-relative folder for T1 detail")
    ap.add_argument("--depth", type=int, default=2)
    ap.add_argument("--max-lines", type=int, default=120)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    out = []
    if a.dir:
        base = os.path.join(root, a.dir)
        files = [f for f in walk(base)]
        out.append(f"# T1: {a.dir} ({len(files)} code files)")
        for f in files:
            rel = os.path.join(a.dir, f)
            full = os.path.join(root, rel)
            try:
                n = sum(1 for _ in open(full, "rb"))
            except OSError:
                n = 0
            ex = ", ".join(exports(full, 8))
            out.append(f"- `{rel}` ({n}L) {purpose(full)} | {ex}")
    else:
        counts, entries, manifests = {}, [], []
        total = 0
        for f in walk(root):
            total += 1
            parts = f.split(os.sep)
            key = os.sep.join(parts[:-1][:a.depth]) or "."
            counts[key] = counts.get(key, 0) + 1
            if parts[-1] in ENTRY_NAMES:
                entries.append(f)
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in IGNORE_DIRS and not d.startswith(".")]
            if dp[len(root):].count(os.sep) <= 2:
                manifests += [os.path.relpath(os.path.join(dp, f), root) for f in fns if f in MANIFESTS]
        out.append(f"# T0: {total} code files")
        out.append("## manifests: " + ", ".join(sorted(manifests)[:20]))
        out.append("## entry candidates: " + ", ".join(sorted(entries)[:25]))
        out.append("## folders (code files)")
        for k in sorted(counts):
            out.append(f"- {k}/ ({counts[k]})")
    if len(out) > a.max_lines:
        extra = len(out) - a.max_lines
        out = out[:a.max_lines] + [f"... {extra} more lines truncated; narrow with --dir"]
    print("\n".join(out))

if __name__ == "__main__":
    main()
