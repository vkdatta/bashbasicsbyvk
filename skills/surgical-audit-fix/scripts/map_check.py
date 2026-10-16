#!/usr/bin/env python3
"""Staleness check for canvas_xd.md using the `synced: <commit>` header.

  map_check.py <repo> [--map canvas_xd.md]
Lists backticked paths in the map that were changed or deleted since the synced commit
(plus uncommitted edits), so only those branches need repair.
"""
import argparse, os, re, subprocess, sys

def git(root, *args):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return r.stdout.rstrip(chr(10)) if r.returncode == 0 else None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root"); ap.add_argument("--map", default="canvas_xd.md")
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    mp = os.path.join(root, a.map)
    if not os.path.exists(mp):
        sys.exit("no map found: create a T0/T1 skeleton (see references/map-format.md)")
    maps = [mp]
    shard_dir = os.path.join(root, os.path.splitext(a.map)[0])
    if os.path.isdir(shard_dir):
        maps += [os.path.join(shard_dir, f) for f in os.listdir(shard_dir) if f.endswith(".md")]
    text = "\n".join(open(m, encoding="utf-8", errors="ignore").read() for m in maps)
    m = re.search(r"synced:\s*([0-9a-f]{6,40})", text)
    paths = sorted(set(p for p in re.findall(r"`([\w./@-]+\.[A-Za-z]{1,5}/?)`", text) if "/" in p or "." in p))
    missing = [p for p in paths if not os.path.exists(os.path.join(root, p))]
    changed = set()
    if m and git(root, "rev-parse", "--git-dir") is not None:
        d = (git(root, "diff", "--name-only", m.group(1), "HEAD") or "").strip()
        d2 = git(root, "status", "--porcelain") or ""
        changed = set(d.splitlines()) | {l[3:] for l in d2.splitlines()}
    elif not m:
        print("! no `synced: <commit>` header; treat all branches as unverified")
    stale = [p for p in paths if p in changed]
    print(f"mapped paths: {len(paths)} | changed since sync: {len(stale)} | missing: {len(missing)}")
    for p in stale: print(f"CHANGED  {p}")
    for p in missing: print(f"MISSING  {p}")
    new = sorted(f for f in changed if f not in paths and os.path.splitext(f)[1] in
                 {".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs", ".java"})
    if new: print(f"unmapped changed code files (may need map entries): {new[:15]}")
    head = (git(root, "rev-parse", "--short", "HEAD") or "").strip()
    if head: print(f"after repairing, set header to: synced: {head}")

if __name__ == "__main__":
    main()
