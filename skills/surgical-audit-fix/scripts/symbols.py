#!/usr/bin/env python3
"""Symbol locator: jump from a name, file, line or stack trace to the exact lines to read.

Query-driven (never dumps the whole repo), cached by file mtime so reruns on 10k files are fast.
Idea of per-symbol signatures + line numbers + HTML ids/CSS selectors adapted from the user's
UniversalRepoIndexer; rewritten to be scoped, collision-safe, method-aware and capped.

  symbols.py <repo> find NAME [--max 20]      definitions (with line ranges) + referencing lines
  symbols.py <repo> file PATH                 outline of one file: symbol, kind, line range
  symbols.py <repo> at PATH:LINE              enclosing symbol of a line
  symbols.py <repo> slice NAME|PATH:LINE [--ctx 2] [--max-lines 120]   print just that code
  symbols.py <repo> trace < error.txt         map a stack trace / compiler errors to symbols
Languages: Python (ast), JS/TS/Vue/Svelte, Go, Rust, Java/Kotlin/C#, HTML ids, CSS selectors.
Anything else: use rg. Static regex parsing can miss dynamic definitions; confirm with rg.
"""
import argparse, ast, hashlib, json, os, re, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import walk, IGNORE_DIRS

KW = {"if", "for", "while", "switch", "catch", "function", "return", "else", "with", "do", "try", "new", "await", "typeof"}
MARKUP_EXT = {".html", ".htm", ".css", ".scss"}

def cache_path(root):
    h = hashlib.sha1(root.encode()).hexdigest()[:12]
    return os.path.join(os.environ.get("SURGICAL_CACHE", tempfile.gettempdir()), f"surgical-sym-{h}.json")

def brace_end(lines, start, limit=3000):
    depth, seen = 0, False
    for i in range(start, min(len(lines), start + limit)):
        s = re.sub(r"""(['"`])(?:\\.|(?!\1).)*\1""", "", lines[i])
        s = re.sub(r"//.*", "", s)
        for ch in s:
            if ch == "{": depth += 1; seen = True
            elif ch == "}": depth -= 1
        if seen and depth <= 0:
            return i + 1
        if not seen and i - start >= 3:
            break
    return start + 1

# ---------- parsers: return [name, kind, line, end, sig, parent] ----------
def parse_py(text):
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return []
    out = []
    def sig(n):
        try:
            a = ast.unparse(n.args)
        except Exception:
            a = "..."
        r = ""
        if getattr(n, "returns", None) is not None:
            try: r = " -> " + ast.unparse(n.returns)
            except Exception: pass
        return f"{'async ' if isinstance(n, ast.AsyncFunctionDef) else ''}def {n.name}({a}){r}"
    for n in tree.body:
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out.append([n.name, "function", n.lineno, n.end_lineno, sig(n), ""])
        elif isinstance(n, ast.ClassDef):
            out.append([n.name, "class", n.lineno, n.end_lineno, f"class {n.name}", ""])
            for m in n.body:
                if isinstance(m, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    out.append([m.name, "method", m.lineno, m.end_lineno, sig(m), n.name])
    return out

FUNC = re.compile(r'^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*(?:<[^>]*>)?\s*\(([^)]*)\)')
ARROW = re.compile(r'^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*(?::[^=]+)?=>')
FNEXPR = re.compile(r'^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?function\b')
CLASS = re.compile(r'^\s*(?:export\s+(?:default\s+)?)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)')
IFACE = re.compile(r'^\s*(?:export\s+)?(?:interface|type|enum)\s+([A-Za-z_$][\w$]*)')
METHOD = re.compile(r'(?:^|[;{}\s])(?:(?:public|private|protected|static|readonly|override)\s+)*(?:async\s+)?(?:get\s+|set\s+)?([A-Za-z_$][\w$]*)\s*(?:<[^>]*>)?\s*\(([^)]*)\)\s*(?::\s*[^{;=]+)?\{')

def parse_js(text):
    lines = text.splitlines()
    out, classes = [], []
    for i, ln in enumerate(lines):
        for rx, kind in ((FUNC, "function"), (ARROW, "function"), (FNEXPR, "function")):
            m = rx.match(ln)
            if m:
                end = brace_end(lines, i) if "{" in ln or rx is not ARROW else i + 1
                if rx is ARROW and "{" not in ln:
                    j = i
                    while j < len(lines) - 1 and j - i < 40 and not lines[j].rstrip().endswith((";", "}")):
                        j += 1
                    end = j + 1
                sg = f"function {m.group(1)}({m.group(2).strip() if rx is FUNC else '...'})"
                out.append([m.group(1), kind, i + 1, end, sg, ""]); break
        else:
            m = CLASS.match(ln)
            if m:
                end = brace_end(lines, i)
                out.append([m.group(1), "class", i + 1, end, f"class {m.group(1)}", ""])
                classes.append((m.group(1), i, end))
                continue
            m = IFACE.match(ln)
            if m:
                out.append([m.group(1), "type", i + 1, brace_end(lines, i) if "{" in ln else i + 1, ln.strip()[:90], ""])
    for cname, s, e in classes:
        for i in range(s, min(e, len(lines))):
            ln = lines[i]
            if i == s:
                k = ln.find("{")
                ln = ln[k + 1:] if k >= 0 else ""
            for m in METHOD.finditer(ln):
                n = m.group(1)
                if n in KW or n == cname and False:
                    continue
                out.append([n, "method", i + 1, brace_end(lines, i), f"{cname}.{n}({m.group(2).strip()})", cname])
    return out

GO = re.compile(r'^func\s+(?:\((?:\w+\s+)?\*?(\w+)\)\s*)?(\w+)\s*\(([^)]*)\)')
RS = re.compile(r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:fn|struct|enum|trait)\s+(\w+)')
JV = re.compile(r'^\s*(?:(?:public|private|protected|static|final|abstract|override|suspend|internal|open|async)\s+)*(?:class|interface|enum|object|fun)\s+(\w+)|^\s*(?:(?:public|private|protected|static|final|abstract|override|internal|async)\s+)+[\w<>\[\],.? ]+\s+(\w+)\s*\([^)]*\)\s*(?:throws [\w, .]+)?\s*\{')

def parse_other(text, ext):
    lines = text.splitlines(); out = []
    for i, ln in enumerate(lines):
        if ext == ".go":
            m = GO.match(ln)
            if m:
                recv = m.group(1); n = m.group(2)
                out.append([n, "method" if recv else "function", i + 1, brace_end(lines, i), f"func {(recv + '.') if recv else ''}{n}({m.group(3)})", recv or ""])
        elif ext == ".rs":
            m = RS.match(ln)
            if m: out.append([m.group(1), "item", i + 1, brace_end(lines, i), ln.strip()[:90], ""])
        else:
            m = JV.match(ln)
            if m:
                n = m.group(1) or m.group(2)
                if n and n not in KW:
                    out.append([n, "item", i + 1, brace_end(lines, i), ln.strip()[:90], ""])
    return out

def parse_markup(text, ext):
    out = []
    for i, ln in enumerate(text.splitlines()):
        if ext in (".html", ".htm"):
            for m in re.finditer(r'\bid=["\']([\w\-:]+)["\']', ln):
                out.append(["#" + m.group(1), "html_id", i + 1, i + 1, ln.strip()[:90], ""])
        else:
            for m in re.finditer(r'((?:[.#][\w\-]+)(?:[\s>+~:][^{,]*)?)\s*[,{]', ln):
                sel = m.group(1).strip()
                if len(sel) < 80: out.append([sel, "css", i + 1, i + 1, sel, ""])
    return out

def parse_file(full, rel):
    ext = os.path.splitext(rel)[1]
    try:
        text = open(full, encoding="utf-8", errors="ignore").read()
    except OSError:
        return []
    if ext == ".py": return parse_py(text)
    if ext in (".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".vue", ".svelte"): return parse_js(text)
    if ext in (".go", ".rs", ".java", ".kt", ".cs"): return parse_other(text, ext)
    if ext in MARKUP_EXT: return parse_markup(text, ext)
    return []

def all_files(root):
    for f in walk(root):
        yield f
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in IGNORE_DIRS and not d.startswith(".")]
        for f in fns:
            if os.path.splitext(f)[1] in MARKUP_EXT:
                yield os.path.relpath(os.path.join(dp, f), root)

def load_index(root):
    cp = cache_path(root)
    cache = {}
    try:
        cache = json.load(open(cp))
    except Exception:
        pass
    new, dirty = {}, False
    for rel in all_files(root):
        full = os.path.join(root, rel)
        try:
            st = os.stat(full); key = [st.st_mtime_ns, st.st_size]
        except OSError:
            continue
        e = cache.get(rel)
        if e and e["k"] == key:
            new[rel] = e
        else:
            new[rel] = {"k": key, "s": parse_file(full, rel)}; dirty = True
    if dirty or len(new) != len(cache):
        try: json.dump(new, open(cp, "w"))
        except OSError: pass
    return new

# ---------- helpers ----------
def enclosing(idx, rel, line):
    best = None
    for s in idx.get(rel, {}).get("s", []):
        if s[2] <= line <= s[3] and (best is None or (s[3] - s[2]) < (best[3] - best[2])):
            best = s
    return best

def fmt(rel, s):
    par = f" in {s[5]}" if s[5] and s[1] == "method" else ""
    kind = "" if s[4].split(" ")[0] in (s[1], "def", "func", "function", "async") else s[1] + " "
    return f"`{rel}:{s[2]}-{s[3]}` {kind}{s[4]}{par}"

def resolve_rel(root, idx, p):
    p = p.replace("\\", "/")
    if p in idx: return p
    if os.path.isabs(p):
        r = os.path.relpath(p, root)
        if r in idx: return r
    parts = [x for x in p.split("/") if x not in ("", ".", "..")]
    for i in range(len(parts)):  # strip leading dirs until a repo path matches (traces from other machines)
        suffix = "/".join(parts[i:])
        if i == len(parts) - 1 and len(parts) > 1:
            # bare filename taken from a longer path: only trust a repo-root file, never a nested namesake
            cands = [r for r in idx if r == suffix]
        else:
            cands = [r for r in idx if r == suffix or r.endswith("/" + suffix)]
        if len(cands) == 1 or (cands and i < len(parts) - 1):
            return sorted(cands, key=len)[0]
    return None

def read_lines(root, rel):
    return open(os.path.join(root, rel), encoding="utf-8", errors="ignore").read().splitlines()

def print_slice(root, rel, a, b, max_lines):
    lines = read_lines(root, rel)
    a = max(1, a); b = min(len(lines), b)
    trunc = b - a + 1 > max_lines
    if trunc: b = a + max_lines - 1
    for n in range(a, b + 1):
        print(f"{n:5d}  {lines[n-1]}")
    if trunc: print(f"... truncated at {max_lines} lines; request a narrower range")

# ---------- commands ----------
def cmd_find(root, idx, a):
    name = a.name
    defs = [(rel, s) for rel, e in idx.items() for s in e["s"] if s[0] == name or s[0] == "#" + name or s[0].lstrip(".#") == name]
    print(f"# definitions of {name}: {len(defs)}")
    for rel, s in defs[:a.max]:
        print("- " + fmt(rel, s))
    if len(defs) > a.max: print(f"... {len(defs)-a.max} more")
    rx = re.compile(r"(?<![\w$])" + re.escape(name) + r"(?![\w$])")
    refs, files = [], 0
    for rel in idx:
        try: lines = read_lines(root, rel)
        except OSError: continue
        hit = False
        for i, ln in enumerate(lines, 1):
            if rx.search(ln):
                if any(rel == d[0] and d[1][2] == i for d in defs): continue
                refs.append((rel, i, ln.strip()[:100])); hit = True
        files += hit
    print(f"# references: {len(refs)} lines in {files} files")
    for rel, i, t in refs[:a.max]:
        print(f"- `{rel}:{i}` {t}")
    if len(refs) > a.max: print(f"... {len(refs)-a.max} more (raise --max or narrow with the file list above)")
    print("# note: name-based match; same name in unrelated modules is possible; check imports before trusting a reference")

def cmd_file(root, idx, a):
    rel = resolve_rel(root, idx, a.path)
    if not rel: sys.exit(f"not indexed: {a.path}")
    syms = sorted(idx[rel]["s"], key=lambda s: s[2])
    print(f"# {rel} ({len(syms)} symbols)")
    for s in syms[:a.max]:
        print(f"- {s[2]}-{s[3]} {s[4]}" if s[4].split(" ")[0] in (s[1], "def", "func", "function", "async") else f"- {s[2]}-{s[3]} {s[1]} {s[4]}")
    if len(syms) > a.max: print(f"... {len(syms)-a.max} more")

def cmd_at(root, idx, a):
    p, _, ln = a.target.rpartition(":")
    rel = resolve_rel(root, idx, p)
    if not rel or not ln.isdigit(): sys.exit("usage: at PATH:LINE (file must be indexed)")
    s = enclosing(idx, rel, int(ln))
    print(fmt(rel, s) if s else f"`{rel}:{ln}` not inside any indexed symbol (module level)")

def cmd_slice(root, idx, a):
    t = a.target
    if re.search(r":\d+$", t):
        p, _, ln = t.rpartition(":"); rel = resolve_rel(root, idx, p)
        if not rel: sys.exit(f"not indexed: {p}")
        s = enclosing(idx, rel, int(ln))
        lo, hi = (s[2], s[3]) if s else (int(ln) - 15, int(ln) + 15)
        print(f"# {rel}:{lo}-{hi}")
        print_slice(root, rel, lo - a.ctx, hi + a.ctx, a.max_lines)
    else:
        defs = [(rel, s) for rel, e in idx.items() for s in e["s"] if s[0] == t or (s[5] and s[5] + "." + s[0] == t)]
        if not defs: sys.exit(f"no definition of {t}")
        if len(defs) > 3: print(f"# {len(defs)} definitions; showing first 3. Use PATH:LINE to pick one")
        for rel, s in defs[:3]:
            print(f"# {fmt(rel, s)}")
            print_slice(root, rel, s[2] - a.ctx, s[3] + a.ctx, a.max_lines)

TRACE_PATS = [
    re.compile(r'File "([^"]+)", line (\d+)'),
    re.compile(r'\(?((?:[\w@.\-/\\ ]+/)?[\w.\-]+\.(?:ts|tsx|js|jsx|mjs|cjs|vue|svelte)):(\d+)(?::\d+)?\)?'),
    re.compile(r'((?:[\w@.\-/\\]+/)?[\w.\-]+\.(?:go|rs|java|kt|cs|py)):(\d+)'),
]
def cmd_trace(root, idx, a):
    text = sys.stdin.read()
    seen, n = set(), 0
    print("# trace -> repo symbols (frames outside the repo are skipped)")
    for ln in text.splitlines():
        for rx in TRACE_PATS:
            for m in rx.finditer(ln):
                rel = resolve_rel(root, idx, m.group(1).strip())
                if not rel: continue
                key = (rel, m.group(2))
                if key in seen: continue
                seen.add(key); n += 1
                s = enclosing(idx, rel, int(m.group(2)))
                print(f"{n}. " + (fmt(rel, s) if s else f"`{rel}:{m.group(2)}` module level") + f"  [line {m.group(2)}]")
    if not n: print("no repo frames recognised; fall back to rg on the error message")
    else: print("# next: `slice PATH:LINE` on the top frame; the root cause is often a caller, not the throwing line")

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root"); sub = ap.add_subparsers(dest="cmd", required=True)
    for c in ("find", "file", "at", "slice", "trace"):
        p = sub.add_parser(c)
        if c == "find": p.add_argument("name")
        if c == "file": p.add_argument("path")
        if c in ("at", "slice"): p.add_argument("target")
        p.add_argument("--max", type=int, default=20)
        if c == "slice":
            p.add_argument("--ctx", type=int, default=2); p.add_argument("--max-lines", type=int, default=120)
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    idx = load_index(root)
    {"find": cmd_find, "file": cmd_file, "at": cmd_at, "slice": cmd_slice, "trace": cmd_trace}[a.cmd](root, idx, a)

if __name__ == "__main__":
    main()
