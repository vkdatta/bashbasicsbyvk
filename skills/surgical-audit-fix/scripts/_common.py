"""Shared helpers: file walking, one-line purpose, exports, import parsing. Stdlib only."""
import os, re, ast

IGNORE_DIRS = {".git", "node_modules", "dist", "build", ".next", "venv", ".venv", "__pycache__",
               "target", "vendor", ".idea", ".vscode", "coverage", ".cache", ".turbo", "out"}
CODE_EXT = {".py", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".go", ".rs", ".java", ".kt",
            ".rb", ".php", ".cs", ".c", ".cc", ".cpp", ".h", ".hpp", ".swift", ".vue", ".svelte"}
JS_EXT = {".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".vue", ".svelte"}

def walk(root, max_files=200000):
    n = 0
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(d for d in dns if d not in IGNORE_DIRS and not d.startswith("."))
        for f in sorted(fns):
            if os.path.splitext(f)[1] in CODE_EXT:
                n += 1
                if n > max_files:
                    return
                yield os.path.relpath(os.path.join(dp, f), root)

def read_head(path, nbytes=6000):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as fh:
            return fh.read(nbytes)
    except OSError:
        return ""

def purpose(path):
    """First meaningful comment/docstring line, else ''."""
    head = read_head(path, 2500)
    if path.endswith(".py"):
        try:
            doc = ast.get_docstring(ast.parse(head + "\n")) if head else None
        except SyntaxError:
            doc = None
        if doc:
            return doc.strip().splitlines()[0][:100]
    for line in head.splitlines()[:25]:
        s = line.strip()
        if s.startswith(("#!", "'use strict'", '"use strict"')):
            continue
        m = re.match(r'^(?:/\*+|//+|#+|\*+)\s*(.+?)\s*(?:\*/)?$', s)
        if m and len(m.group(1)) > 8 and not m.group(1).lower().startswith(("eslint", "@ts-", "copyright", "license")):
            return m.group(1)[:100]
    return ""

EXPORT_RES = [
    re.compile(r'^\s*export\s+(?:default\s+)?(?:async\s+)?(?:function\*?|class|const|let|var|interface|type|enum)\s+([A-Za-z_$][\w$]*)', re.M),
    re.compile(r'^\s*module\.exports\.(\w+)\s*=', re.M),
    re.compile(r'^(?:def|class)\s+([A-Za-z_]\w*)', re.M),
    re.compile(r'^func\s+(?:\([^)]*\)\s*)?([A-Z]\w*)', re.M),
    re.compile(r'^\s*pub\s+(?:async\s+)?(?:fn|struct|enum|trait)\s+(\w+)', re.M),
]

def exports(path, limit=12):
    txt = read_head(path, 60000)
    seen, out = set(), []
    for grp in re.findall(r'export\s*\{([^}]*)\}\s*from', txt):
        for n in grp.split(","):
            n = n.strip().split(" as ")[-1].strip()
            if n and "re:" + n not in seen:
                seen.add("re:" + n); out.append("re:" + n)
    for rx in EXPORT_RES:
        for m in rx.finditer(txt):
            n = m.group(1)
            if n not in seen and not (path.endswith(".py") and n.startswith("_")):
                seen.add(n); out.append(n)
    if len(out) > limit:
        return out[:limit] + [f"+{len(out)-limit} more"]
    return out

JS_IMP = re.compile(r'''(?:from\s+|import\s*\(\s*|require\s*\(\s*|import\s+)['"]([^'"]+)['"]''')

def raw_imports(relpath, root):
    full = os.path.join(root, relpath)
    txt = read_head(full, 200000)
    ext = os.path.splitext(relpath)[1]
    out = []
    if ext == ".py":
        try:
            tree = ast.parse(txt)
        except SyntaxError:
            return out
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                out += [("abs", a.name) for a in node.names]
            elif isinstance(node, ast.ImportFrom):
                out.append(("rel" if node.level else "abs", ("." * node.level) + (node.module or "")))
    elif ext in JS_EXT:
        out = [("rel" if m.startswith(".") else "abs", m) for m in JS_IMP.findall(txt)]
    return out

def resolve(relpath, kind, spec, fileset):
    """Resolve an import spec to a repo-relative file in fileset, else None."""
    base = os.path.dirname(relpath)
    ext = os.path.splitext(relpath)[1]
    cands = []
    if ext == ".py":
        if spec.startswith("."):
            lv = len(spec) - len(spec.lstrip("."))
            d = base
            for _ in range(lv - 1):
                d = os.path.dirname(d)
            tail = spec[lv:].replace(".", "/")
            p = os.path.join(d, tail) if tail else d
        else:
            p = spec.replace(".", "/")
        cands = [p + ".py", os.path.join(p, "__init__.py")]
        if kind == "abs":  # also try under common source roots
            for sr in ("src", "app", "lib"):
                cands += [os.path.join(sr, p) + ".py", os.path.join(sr, p, "__init__.py")]
    elif ext in JS_EXT and kind == "rel":
        p = os.path.normpath(os.path.join(base, spec))
        cands = [p] + [p + e for e in (".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".vue", ".svelte")] + \
                [os.path.join(p, "index" + e) for e in (".ts", ".tsx", ".js", ".jsx")]
    for c in cands:
        c = os.path.normpath(c)
        if c in fileset:
            return c
    return None

def build_graph(root, files=None):
    files = files or list(walk(root))
    fs = set(files)
    down, up = {}, {}
    for f in files:
        for kind, spec in raw_imports(f, root):
            t = resolve(f, kind, spec, fs)
            if t and t != f:
                down.setdefault(f, set()).add(t)
                up.setdefault(t, set()).add(f)
    return fs, down, up
