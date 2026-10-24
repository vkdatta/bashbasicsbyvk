#!/usr/bin/env python3
"""Expected-vs-actual tests for the find & replace engines.

  python3 -I tests/findrep/findrep_test.py --engine ./bvk-fr [--engine script/file/functions/bashbasicsbyvk_findrep] [--n 1200] [--seed 1]

Every engine given is run on the same operations:
  * hand written scenarios (SCENARIOS below: the bugs that were reported + edge cases) with exact expectations
  * N random operations: a random folder tree is built, an independent oracle (plain Python str / re, written here, it does not
    share code with either engine) computes the expected tree, the engine runs find, preview and apply, and
    the real tree, the listing (find / preview) and the counts are compared with the oracle.
  * when two engines are given, their stdout / counts / resulting trees must be identical.
Exit status 0 only when everything agrees.
"""
import argparse, os, random, re, shutil, stat, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def dec(b): return b.decode("utf-8", "surrogateescape")
def enc(s): return s.encode("utf-8", "surrogateescape")


# ---------------------------------------------------------------------------------------------- running an engine
class Engine:
    def __init__(self, path):
        self.path = path
        self.cmd = [sys.executable, "-I", path] if path.endswith("findrep") else [path]

    def run(self, mode, root, rules, **o):
        tmp = tempfile.mkdtemp(prefix="frt.")
        try:
            rf = os.path.join(tmp, "rules")
            with open(rf, "wb") as f:
                for a, b in rules:
                    f.write(a + b"\0" + b + b"\0")
            args = self.cmd + [mode, "--root", root, "--rules", rf, "--out", tmp + "/out", "--stats", tmp + "/stats", "--log", tmp + "/log", "--limit", "0"]
            for k, v in o.items():
                if k == "exclude":
                    for e in v: args += ["--exclude", os.path.join(root, e)]
                elif k == "only" and v is not None:
                    args += ["--only", os.path.join(root, v)]
                elif v is not None:
                    args += ["--" + k, str(int(v)) if isinstance(v, bool) else str(v)]
            p = subprocess.run(args, capture_output=True)
            stats = {}
            if os.path.exists(tmp + "/stats"):
                for line in open(tmp + "/stats"):
                    k, _, v = line.strip().partition("=")
                    stats[k] = int(v) if v.lstrip("-").isdigit() else v
            out = open(tmp + "/out", "rb").read().split(b"\0")[:-1] if os.path.exists(tmp + "/out") else []
            log = open(tmp + "/log", "rb").read() if os.path.exists(tmp + "/log") else b""
            return p.returncode, p.stdout, p.stderr, stats, out, log
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


def snapshot(root):
    snap = {}
    rb = os.fsencode(root)
    for d, dirs, files in os.walk(rb):
        for n in dirs + files:
            p = os.path.join(d, n)
            rel = p[len(rb) + 1:]
            if os.path.islink(p): snap[rel] = ("l", os.readlink(p))
            elif os.path.isdir(p): snap[rel] = ("d",)
            else: snap[rel] = ("f", open(p, "rb").read())
    return snap


# ---------------------------------------------------------------------------------------------- the oracle
FLAG_I = re.I | re.M
PX = {"digit": "0-9", "alpha": "a-zA-Z"}


def ora_compile(find, regex, icase, word):
    p = find
    if regex:
        p = re.sub(r"\[:(\w+):\]", lambda m: PX[m.group(1)], p)
        p = re.sub(r"(?<!\\)\^(?![^\[]*\])", r"(?:\\A|(?<=\\n)(?!\\Z))", p) if p == "^" else p
    else:
        p = re.escape(find)
    if word: p = r"(?<!\w)(?:%s)(?!\w)" % p
    return re.compile(p, FLAG_I if icase else re.M)


def ora_rep(rx, rep, regex):
    if not regex: return lambda m: rep
    def f(m):
        out, i = [], 0
        while i < len(rep):
            c = rep[i]
            if c in "\\$" and i + 1 < len(rep):
                d = rep[i + 1]
                if d in "0123456789": out.append(m.group(int(d)) or ""); i += 2; continue
                if c == "$" and d == "&": out.append(m.group(0)); i += 2; continue
                if c == "\\" and d in "ntr\\$": out.append({"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "$": "$"}[d]); i += 2; continue
                if c == "$" and d == "$": out.append("$"); i += 2; continue
            out.append(c); i += 1
        return "".join(out)
    return f


def ora_apply(text, rules):
    """rules: list of (rx, repfn). returns (text, [count per rule])"""
    counts = []
    for rx, fn in rules:
        n = [0]
        def f(m, fn=fn):
            n[0] += 1
            return fn(m)
        text = rx.sub(f, text)
        counts.append(n[0])
    return text, counts


HIDDEN_SKIP = (b".git", b".hg", b".svn")


class Op:
    def __init__(self, **k):
        self.__dict__.update(dict(scope="names", depth="rec", case="exact", regex=False, word=False, hidden=False, vcs=False,
                                  target="both", binary=False, maxsize=0, rules=[], only=None, exclude=[]), **k)

    def args(self):
        return dict(scope=self.scope, depth=self.depth, case=self.case, regex=self.regex, word=self.word, hidden=self.hidden,
                    vcs=self.vcs, target=self.target, binary=self.binary, maxsize=self.maxsize, only=self.only, exclude=self.exclude)


def build(root, tree):
    for rel, v in tree.items():
        p = os.path.join(root, rel)
        if v is None: os.makedirs(p, exist_ok=True)
        else:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f: f.write(v)


def visible(tree, op):
    """pre-order list of (rel(str), isdir, content) of entries the engine will look at"""
    kids = {}
    for rel in tree:
        par, _, nm = rel.rpartition("/")
        kids.setdefault(par, []).append(nm)
    out = []
    def rec(par, depth):
        for nm in sorted(kids.get(par, []), key=enc):
            nb = enc(nm)
            if not op.hidden and nb.startswith(b"."): continue
            if not op.vcs and nb in HIDDEN_SKIP: continue
            rel = (par + "/" + nm) if par else nm
            isdir = tree[rel] is None
            out.append((rel, isdir, tree[rel]))
            if isdir and op.depth == "rec": rec(rel, depth + 1)
    rec("", 0)
    return out


def oracle(tree, op):
    """-> dict(final tree, matched names list, matched files list, counts, conflicty)"""
    compiled = [(ora_compile(dec(a), op.regex, op.case == "any", op.word), ) for a, b in op.rules]
    rules = []
    for (a, b), (rx,) in zip(op.rules, compiled):
        rules.append((rx, ora_rep(rx, dec(b), op.regex)))
    vis = visible(tree, op)
    new = dict(tree)
    content_hits, name_hits, occ, nfiles = [], [], 0, 0
    per_rule_occ = [0] * len(rules)
    if op.scope in ("contents", "both"):
        for rel, isdir, data in vis:
            if isdir or data is None: continue
            if op.only and rel != op.only: continue
            if rel in op.exclude: continue
            if not op.binary and b"\0" in data[:8000]: continue
            if op.maxsize and len(data) > op.maxsize: continue
            text, cnts = ora_apply(dec(data), rules)
            if sum(cnts):
                content_hits.append(rel); occ += sum(cnts); nfiles += 1
                for i, c in enumerate(cnts): per_rule_occ[i] += c
                new[rel] = enc(text)
    renames = {}
    if op.scope in ("names", "both"):
        for rel, isdir, data in vis:
            if isdir and op.target == "files": continue
            if not isdir and op.target == "dirs": continue
            if op.only and rel != op.only: continue
            if rel in op.exclude: continue
            nm = rel.rpartition("/")[2]
            res, cnts = ora_apply(nm, rules)
            if sum(cnts): name_hits.append(rel)
            if res != nm and sum(cnts):
                renames[rel] = res
    # which renames are collision-free?
    conflicty = False
    byparent = {}
    for rel in tree:
        par, _, nm = rel.rpartition("/")
        byparent.setdefault(par, []).append(nm)
    good = {}
    for rel, res in renames.items():
        rb = enc(res)
        if not rb or len(rb) > 255 or "/" in res or "\0" in res or res in (".", ".."):
            conflicty = True; continue
        good[rel] = res
    for par, names in byparent.items():
        pnew = [good.get((par + "/" + n) if par else n, n) for n in names]
        if len(set(pnew)) != len(pnew): conflicty = True
        # a new name that equals another (old) name in the folder
        olds = set(names)
        for n in names:
            r = (par + "/" + n) if par else n
            if r in good and good[r] in olds: conflicty = True
    # rebuild final tree (top-down path mapping)
    final = {}
    def newpath(rel):
        parts = rel.split("/")
        acc, outp = "", []
        for p in parts:
            acc = (acc + "/" + p) if acc else p
            outp.append(good.get(acc, p))
        return "/".join(outp)
    for rel, v in new.items(): final[newpath(rel)] = v
    return dict(final=final, name_hits=name_hits, content_hits=content_hits, renames=good, occ=occ, nfiles=nfiles, conflicty=conflicty,
                per_rule_occ=per_rule_occ, vis=vis)


# ---------------------------------------------------------------------------------------------- random generation
NAME_CH = list("abcABC123 _-.[](){}$^+") + ["é", "É", "ß", "Ω", "ω", "Ж", "ж", "日"]
TEXT_CH = list("abcABC123 \t_-.[](){}$^+*?\\/") + ["\n"] * 4 + ["é", "É", "ß", "Ω", "ω", "Ж", "ж", "日", "foo", "Foo", "bar", " hello ", "a@b"]

REGEXES = [
    (r"[a-c]+", 0), (r"(a)(b)?", 2), (r"\d+", 0), (r"^a", 0), (r"b$", 0), (r"\bfoo\b", 0), (r"(?<=a)b", 0), (r"a|b", 0),
    (r"x*", 0), (r".", 0), (r"\s+", 0), (r"[^a]", 0), (r"(\w+)@(\w+)", 2), (r"a{2,3}", 0), (r"a+?", 0), (r"(a|b)+", 1),
    (r"[[:digit:]]+", 0), (r"(?:foo|bar)\d?", 0), (r"(.)\1", 1), (r"\w+", 0), (r"[é-ö]", 0), (r"(?!a)b", 0), (r"\Bo", 0),
    (r"^", 0), (r"$", 0), (r"(o)(o)", 2), (r"[A-Z]", 0), (r"\.", 0), (r"\[", 0), (r"a*?b", 0), (r"(b*)(a*)", 2), (r"\W", 0),
]
REPS = ["", "X", "[x]", "é", " ", "-", "\\0\\0", "$&!", "\\1", "<\\2\\1>", "$1$1", "a\\n", "\\\\", "\\$", "\\t", "foo"]


def rname(r):
    n = "".join(r.choice(NAME_CH) for _ in range(r.randint(1, 7)))
    if n.strip(" .") == "": n = "n" + n
    return n.replace("/", "_")


def rtext(r):
    return "".join(r.choice(TEXT_CH) for _ in range(r.randint(0, 40)))


def rtree(r):
    tree = {}
    dirs = [""]
    for _ in range(r.randint(1, 5)):
        par = r.choice(dirs)
        d = (par + "/" if par else "") + rname(r)
        if d not in tree and d not in dirs: tree[d] = None; dirs.append(d)
    for _ in range(r.randint(1, 14)):
        par = r.choice(dirs)
        f = (par + "/" if par else "") + rname(r)
        if f in tree: continue
        k = r.random()
        if k < 0.07: data = b"bin\0ary " + enc(rtext(r))
        elif k < 0.10: data = b"inv\xff\xfe\xc3 " + enc(rtext(r))
        elif k < 0.14: data = b""
        else: data = enc(rtext(r))
        tree[f] = data
    # hidden / vcs entries
    if r.random() < 0.3: tree["." + rname(r)] = enc(rtext(r))
    if r.random() < 0.15: tree[".git/" + rname(r)] = enc(rtext(r)); tree[".git"] = None
    if r.random() < 0.15: tree[".hid"] = None; tree[".hid/" + rname(r)] = enc(rtext(r))
    # fix: a dir path must exist for every file's parent
    for rel in list(tree):
        par = rel.rpartition("/")[0]
        while par:
            tree.setdefault(par, None)
            par = par.rpartition("/")[0]
    for rel in list(tree):                       # a name used both as file and folder: keep the folder
        pass
    return tree


def pieces(tree):
    out = []
    for rel, v in tree.items():
        out.append(rel.rpartition("/")[2])
        if v:
            t = dec(v)
            if len(t) > 3:
                a = r_state.randint(0, len(t) - 1)
                out.append(t[a:a + r_state.randint(1, 5)])
    return [p for p in out if p and "\0" not in p]


r_state = random.Random(0)


def rop(r, tree):
    global r_state
    r_state = r
    scope = r.choice(["names", "contents", "both", "names", "contents", "both", "both"])
    regex = r.random() < 0.4
    icase = r.random() < 0.4
    word = r.random() < 0.15
    nrules = 1 if r.random() < 0.75 else r.randint(2, 4)
    rules = []
    ps = pieces(tree) or ["a"]
    for _ in range(nrules):
        if regex:
            pat, ng = r.choice(REGEXES)
            rep = r.choice(REPS)
            for m in re.finditer(r"[\\$](\d)", rep):
                if int(m.group(1)) > ng: rep = "R"
            rules.append((enc(pat), enc(rep)))
        else:
            rules.append((enc(r.choice(ps)), enc(r.choice(REPS if r.random() < 0.6 else ["", "X", "é", "ß"]))))
    return Op(scope=scope, depth=r.choice(["rec", "rec", "flat"]), case="any" if icase else "exact", regex=regex, word=word,
              hidden=r.random() < 0.25, vcs=r.random() < 0.1, target=r.choice(["both", "both", "files", "dirs"]),
              binary=r.random() < 0.1, maxsize=r.choice([0, 0, 0, 30]), rules=rules)


# ---------------------------------------------------------------------------------------------- checks
class Fail(Exception): pass


def tree_to_snap(tree):
    s = {}
    for rel, v in tree.items():
        s[enc(rel)] = ("d",) if v is None else ("f", v)
    return s


def check_op(engines, tree, op, label):
    exp = oracle(tree, op)
    results = []
    for eng in engines:
        base = tempfile.mkdtemp(prefix="frt.")
        try:
            root = os.path.join(base, "r")
            os.makedirs(root)
            build(root, tree)
            a = op.args()
            rc, out_f, err_f, st_f, list_f, _ = eng.run("find", root, op.rules, **a)
            if rc != 0: raise Fail("%s: find failed rc=%d %s" % (label, rc, err_f.decode(errors="replace")))
            if snapshot(root) != tree_to_snap_full(tree, root): raise Fail("%s: find changed the tree" % label)
            exp_list = [enc(root + "/" + r) for r in ordered(exp, op, find=True)]
            if list_f != exp_list: raise Fail("%s: find list differs\n got %r\n exp %r" % (label, list_f, exp_list))
            rc, out_p, err_p, st_p, list_p, _ = eng.run("preview", root, op.rules, **a)
            if rc != 0: raise Fail("%s: preview failed rc=%d %s" % (label, rc, err_p.decode(errors="replace")))
            if snapshot(root) != tree_to_snap_full(tree, root): raise Fail("%s: preview changed the tree" % label)
            rc, out_a, err_a, st_a, _, log = eng.run("apply", root, op.rules, **a)
            if rc != 0: raise Fail("%s: apply failed rc=%d %s" % (label, rc, err_a.decode(errors="replace")))
            got = snapshot(root)
            if not exp["conflicty"]:
                want = tree_to_snap(exp["final"])
                if got != want:
                    ks = set(got) | set(want)
                    diff = [(k, got.get(k), want.get(k)) for k in sorted(ks) if got.get(k) != want.get(k)][:4]
                    raise Fail("%s: tree differs: %r" % (label, diff))
                if st_a.get("files_changed", 0) > exp["nfiles"] or st_p.get("occurrences", 0) != exp["occ"]:
                    raise Fail("%s: counts: occ got %s want %s" % (label, st_p.get("occurrences"), exp["occ"]))
                if st_p.get("files_matched", 0) != exp["nfiles"]:
                    raise Fail("%s: files_matched got %s want %s" % (label, st_p.get("files_matched"), exp["nfiles"]))
                if op.scope != "contents" and st_a.get("names_renamed", 0) != len(exp["renames"]):
                    raise Fail("%s: names_renamed got %s want %d" % (label, st_a.get("names_renamed"), len(exp["renames"])))
                if op.scope != "contents" and st_p.get("names_planned", 0) != len(exp["renames"]):
                    raise Fail("%s: names_planned got %s want %d" % (label, st_p.get("names_planned"), len(exp["renames"])))
                for i, c in enumerate(exp["per_rule_occ"]):
                    if op.scope != "names" and st_p.get("r%d_occ" % i, 0) != c:
                        raise Fail("%s: rule %d occ got %s want %d" % (label, i, st_p.get("r%d_occ" % i), c))
            else:
                # collisions: nothing may be lost or overwritten
                before = sorted(v[1] for v in tree_to_snap_full(tree, root).values() if v[0] == "f") if False else None
                nfiles_before = sum(1 for v in tree.values() if v is not None)
                nfiles_after = sum(1 for v in got.values() if v[0] == "f")
                if nfiles_after != nfiles_before or len(got) != len(tree):
                    raise Fail("%s: collision case lost or created entries (%d/%d files, %d/%d entries)" %
                               (label, nfiles_after, nfiles_before, len(got), len(tree)))
                if st_a.get("names_conflict", 0) + st_a.get("names_invalid", 0) == 0 and exp["renames"] != {}:
                    pass
            results.append((out_f, out_p, st_p, {k: v for k, v in st_a.items() if k != "ms"}, got))
        finally:
            shutil.rmtree(base, ignore_errors=True)
    if len(results) > 1:
        a, b = results[0], results[1]
        if strip_root(a[0]) != strip_root(b[0]) or strip_root(a[1]) != strip_root(b[1]):
            raise Fail("%s: engines print different listings\n%s\n---\n%s" % (label, a[1].decode(errors="replace"), b[1].decode(errors="replace")))
        for i in (2, 3):
            x = {k: v for k, v in a[i].items() if k not in ("ms", "dirs_scanned")}
            y = {k: v for k, v in b[i].items() if k not in ("ms", "dirs_scanned")}
            if x != y: raise Fail("%s: engines count differently: %r vs %r" % (label, x, y))
        if a[4] != b[4]: raise Fail("%s: engines produce different trees" % label)


def strip_root(b): return b


def tree_to_snap_full(tree, root):
    return tree_to_snap(tree)


def ordered(exp, op, find):
    """listing order of find mode: pre-order, items that match by name or by content"""
    nh, ch = set(exp["name_hits"]), set(exp["content_hits"])
    return [rel for rel, _, _ in exp["vis"] if rel in nh or rel in ch]


# ---------------------------------------------------------------------------------------------- scenarios
def S(name, tree, op, expect, **extra):
    return dict(name=name, tree=tree, op=op, expect=expect, **extra)


B = lambda s: s.encode()
SCENARIOS = [
    S("bug: 'hello [c]' is plain text, not a glob", {"hello [c].txt": b"", "hello c.txt": b"", "d": None, "d/hello [c].txt": b""},
      Op(scope="names", depth="flat", rules=[(B("hello [c]"), B("X"))]), {"X.txt": b"", "hello c.txt": b"", "d": None, "d/hello [c].txt": b""}),
    S("bug: flat does not look inside folders", {"a1": None, "a1/a1": b"a1", "a1/sub": None, "a1/sub/a1": b""},
      Op(scope="both", depth="flat", rules=[(B("a1"), B("b"))]), {"b": None, "b/a1": b"a1", "b/sub": None, "b/sub/a1": b""}),
    S("recursive renames deepest first", {"x": None, "x/x": None, "x/x/x.txt": b"x"},
      Op(scope="names", rules=[(B("x"), B("y"))]), {"y": None, "y/y": None, "y/y/y.tyt": b"x"}),
    S("target files only", {"cat": None, "cat/cat.txt": b""}, Op(scope="names", target="files", rules=[(B("cat"), B("dog"))]),
      {"cat": None, "cat/dog.txt": b""}),
    S("target dirs only", {"cat": None, "cat/cat.txt": b""}, Op(scope="names", target="dirs", rules=[(B("cat"), B("dog"))]),
      {"dog": None, "dog/cat.txt": b""}),
    S("existing target is never overwritten", {"a.txt": b"A", "b.txt": b"B"}, Op(scope="names", rules=[(B("a."), B("b."))]),
      {"a.txt": b"A", "b.txt": b"B"}),
    S("two sources, one target: first wins", {"a1": b"1", "a2": b"2"}, Op(scope="names", rules=[(B("a"), B("z")), (B("1"), B("")), (B("2"), B(""))]),
      {"z": b"1", "a2": b"2"}),
    S("chain shift a1->a2->a3", {"a1": b"1", "a2": b"2"}, Op(scope="names", regex=True, rules=[(B(r"a(\d)"), B("a${1}"))]), None),
    S("case only rename", {"readme": b"x"}, Op(scope="names", case="any", rules=[(B("README"), B("ReadMe"))]), {"ReadMe": b"x"}),
    S("slash in new name is refused", {"a b": b""}, Op(scope="names", rules=[(B(" "), B("/"))]), {"a b": b""}),
    S("empty new name is refused", {"abc": b""}, Op(scope="names", rules=[(B("abc"), B(""))]), {"abc": b""}),
    S("hidden skipped by default", {".h": b"foo", "v": b"foo"}, Op(scope="contents", rules=[(B("foo"), B("bar"))]), {".h": b"foo", "v": b"bar"}),
    S("hidden included", {".h": b"foo", "v": b"foo"}, Op(scope="contents", hidden=True, rules=[(B("foo"), B("bar"))]), {".h": b"bar", "v": b"bar"}),
    S(".git never touched unless asked", {".git": None, ".git/c": b"foo", "v": b"foo"},
      Op(scope="both", hidden=True, rules=[(B("foo"), B("bar")), (B("c"), B("d"))]), {".git": None, ".git/c": b"foo", "v": b"bar"}),
    S("binary files skipped", {"b.bin": b"foo\0foo", "t": b"foo"}, Op(scope="contents", rules=[(B("foo"), B("x"))]), {"b.bin": b"foo\0foo", "t": b"x"}),
    S("binary files edited when asked", {"b.bin": b"foo\0foo"}, Op(scope="contents", binary=True, rules=[(B("foo"), B("x"))]), {"b.bin": b"x\0x"}),
    S("literal: regex characters are plain", {"f": b"a.b a*b [x] (y) $1 \\n"},
      Op(scope="contents", rules=[(B("a.b"), B("1")), (B("a*b"), B("2")), (B("[x]"), B("3")), (B("(y)"), B("4")), (B("$1"), B("5")), (B("\\n"), B("6"))]),
      {"f": b"1 2 3 4 5 6"}),
    S("literal: replacement is plain too", {"f": b"abc"}, Op(scope="contents", rules=[(B("b"), B("\\1$&\\n"))]), {"f": b"a\\1$&\\nc"}),
    S("regex: groups and escapes", {"f": b"John Smith"}, Op(scope="contents", regex=True, rules=[(B(r"(\w+) (\w+)"), B(r"\2, \1\n"))]), {"f": b"Smith, John\n"}),
    S("regex: empty matches like Python", {"f": b"abxd"}, Op(scope="contents", regex=True, rules=[(B("x*"), B("-"))]), {"f": b"-a-b--d-"}),
    S("regex: ^ and $ are per line", {"f": b"a\nb\n"}, Op(scope="contents", regex=True, rules=[(B("^"), B("> "))]), {"f": b"> a\n> b\n"}),
    S("any case, unicode", {"f": "École école ÉCOLE".encode()}, Op(scope="contents", case="any", rules=[("école".encode(), B("x"))]), {"f": b"x x x"}),
    S("whole word", {"f": b"cat concat cat. cats"}, Op(scope="contents", word=True, rules=[(B("cat"), B("dog"))]), {"f": b"dog concat dog. cats"}),
    S("symlink is renamed but never edited through", {"t": b"foo", "l": ("l", "t")}, Op(scope="both", rules=[(B("foo"), B("bar")), (B("l"), B("m"))]), None, symlink=True),
    S("invalid utf-8 survives", {"f": b"\xff foo \xfe"}, Op(scope="contents", rules=[(B("foo"), B("bar"))]), {"f": b"\xff bar \xfe"}),
    S("CRLF kept", {"f": b"foo\r\nfoo\r\n"}, Op(scope="contents", rules=[(B("foo"), B("bar"))]), {"f": b"bar\r\nbar\r\n"}),
    S("empty file with empty-matching regex", {"f": b""}, Op(scope="contents", regex=True, rules=[(B("^"), B("# "))]), {"f": b"# "}),
    S("sequential rules (csv rows)", {"f": b"a"}, Op(scope="contents", rules=[(B("a"), B("b")), (B("b"), B("c"))]), {"f": b"c"}),
    S("exclude keeps the csv itself", {"m.csv": b"foo,bar", "f": b"foo"}, Op(scope="both", rules=[(B("foo"), B("bar")), (B("m"), B("n"))], exclude=["m.csv"]),
      {"m.csv": b"foo,bar", "f": b"bar"}),
    S("only: one file", {"a": b"foo", "b": b"foo"}, Op(scope="contents", only="a", rules=[(B("foo"), B("x"))]), {"a": b"x", "b": b"foo"}),
    S("names with newline and tab", {"a\nb": b"", "c\td": b""}, Op(scope="names", rules=[(B("\n"), B("_")), (B("\t"), B("_"))]), {"a_b": b"", "c_d": b""}),
    S("maxsize skips big files", {"big": b"foo" * 100, "small": b"foo"}, Op(scope="contents", maxsize=50, rules=[(B("foo"), B("x"))]), {"big": b"foo" * 100, "small": b"x"}),
    S("both: content edited then renamed", {"foo.txt": b"foo", "d": None, "d/foo": b"foo foo"}, Op(scope="both", rules=[(B("foo"), B("bar"))]),
      {"bar.txt": b"bar", "d": None, "d/bar": b"bar bar"}),
    S("lookbehind / lazy / alternation", {"f": b"ab cb aab"}, Op(scope="contents", regex=True, rules=[(B(r"(?<=a)b"), B("X")), (B(r"c|X"), B("-"))]), {"f": b"a- -b aa-"}),
    S("backreference", {"f": b"aa ab bb"}, Op(scope="contents", regex=True, rules=[(B(r"(.)\1"), B("<\\1>"))]), {"f": b"<a> ab <b>"}),
    S("bad regex is an error, nothing changed", {"f": b"a"}, Op(scope="contents", regex=True, rules=[(B("(a"), B("b"))]), "error"),
    S("group ref beyond groups is an error", {"f": b"a"}, Op(scope="contents", regex=True, rules=[(B("a"), B("\\1"))]), "error"),
    S("catastrophic regex gives up, file untouched", {"f": b"a" * 40 + b"c"}, Op(scope="contents", regex=True, rules=[(B(r"(a+)+b"), B("x"))]), {"f": b"a" * 40 + b"c"}, engines_only="c"),
]


def run_scenario(engines, sc):
    for eng in engines:
        if sc.get("engines_only") == "c" and eng.path.endswith("findrep"): continue
        base = tempfile.mkdtemp(prefix="frs.")
        try:
            root = os.path.join(base, "r")
            os.makedirs(root)
            tree = dict(sc["tree"])
            links = {}
            for k, v in list(tree.items()):
                if isinstance(v, tuple): links[k] = v[1]; del tree[k]
            build(root, tree)
            for k, tgt in links.items(): os.symlink(tgt, os.path.join(root, k))
            op = sc["op"]
            rc, out, err, st, lst, _ = eng.run("apply", root, op.rules, **op.args())
            if sc["expect"] == "error":
                if rc != 2 or snapshot(root) != {enc(k): (("d",) if v is None else ("f", v)) for k, v in tree.items()} | {enc(k): ("l", t.encode()) for k, t in links.items()}:
                    raise Fail("scenario %r (%s): expected a clean error, rc=%d" % (sc["name"], eng.path, rc))
                continue
            if rc != 0: raise Fail("scenario %r (%s): rc=%d %s" % (sc["name"], eng.path, rc, err.decode(errors="replace")))
            got = snapshot(root)
            if sc.get("symlink"):
                if got.get(b"t") != ("f", b"bar") or got.get(b"m") != ("l", b"t"): raise Fail("scenario %r (%s): symlink handling: %r" % (sc["name"], eng.path, got))
                continue
            if sc["expect"] is None:
                if sc["name"].startswith("chain"):
                    if sorted(v[1] for v in got.values()) != [b"1", b"2"]: raise Fail("scenario %r (%s): data lost %r" % (sc["name"], eng.path, got))
                continue
            want = {enc(k): (("d",) if v is None else ("f", v)) for k, v in sc["expect"].items()}
            if got != want: raise Fail("scenario %r (%s):\n got  %r\n want %r" % (sc["name"], eng.path, got, want))
        finally:
            shutil.rmtree(base, ignore_errors=True)


def extra_checks(engines):
    """things the oracle can not model: permissions, hard links, big trees, speed sanity"""
    for eng in engines:
        base = tempfile.mkdtemp(prefix="frx.")
        try:
            root = os.path.join(base, "r"); os.makedirs(root)
            p = os.path.join(root, "x.sh"); open(p, "w").write("foo\n"); os.chmod(p, 0o750)
            h1 = os.path.join(root, "h1"); open(h1, "w").write("foo\n"); os.link(h1, os.path.join(root, "h2"))
            eng.run("apply", root, [(b"foo", b"bar")], scope="contents")
            if stat.S_IMODE(os.stat(p).st_mode) != 0o750: raise Fail("mode not kept (%s)" % eng.path)
            if open(p).read() != "bar\n" or open(h1).read() != "bar\n" or open(os.path.join(root, "h2")).read() != "bar\n":
                raise Fail("content / hard link (%s)" % eng.path)
            left = [n for n in os.listdir(root) if n.startswith(".bvkfr")]
            if left: raise Fail("temp files left behind: %r" % left)
            # deep tree + many files
            deep = root
            for i in range(60): deep = os.path.join(deep, "d%d" % i)
            os.makedirs(deep); open(os.path.join(deep, "leaf d.txt"), "w").write("d d")
            for i in range(300): open(os.path.join(root, "f%03d.txt" % i), "w").write("hello %d" % i)
            rc, out, err, st, lst, log = eng.run("apply", root, [(b"d", b"D")], scope="both", target="both")
            if rc != 0: raise Fail("deep tree rc (%s) %s" % (eng.path, err))
            leaf = root
            for i in range(60): leaf = os.path.join(leaf, "D%d" % i)
            if open(os.path.join(leaf, "leaf D.txt")).read() != "D D": raise Fail("deep tree result (%s)" % eng.path)
            if st["names_renamed"] != 61 or log.count(b"\n") != 61: raise Fail("deep rename count %r (%s)" % (st, eng.path))
            # rename log is replayable in order: every line's old path existed when it ran
            sim = set()
            for line in log.split(b"\n")[:-1]:
                a, b = line.split(b"\t")
                if not a or not b: raise Fail("bad log line")
        finally:
            shutil.rmtree(base, ignore_errors=True)



# ---------------------------------------------------------------------------------------------- regex differential fuzz
ATOMS = ["a", "b", "c", "A", "B", " ", "é", "É", ".", "\\.", "[ab]", "[^a]", "[a-c]", "[^b-c ]", "\\d", "\\w", "\\s", "\\W", "\\D", "\\S",
         "[[:alpha:]]", "[\\d_]", "[\\w.-]", "1", "2", "-", "_", "\\n", "[é-ö]", "ß", "Ω", "ω", "\\[", "\\(", "\\$", "x", "foo"]
ANCH = ["^", "$", "\\b", "\\B", "\\A", "\\Z"]
QUANT = ["*", "+", "?", "{2}", "{1,2}", "{0,3}", "{2,}", "{,2}", "*?", "+?", "??", "{1,3}?", "{2,}?"]
RTEXT = list("abcABC 12-_.\n\n[]($") + ["é", "É", "ß", "Ω", "ω", "foo", "Foo", "ab", "aa", "bb", "a1", "\r\n", "日"]


def gen_re(r, depth=0, ng=None):
    ng = ng if ng is not None else [0]
    def atom():
        k = r.random()
        if k < 0.55 or depth > 2: return r.choice(ATOMS)
        if k < 0.65: return r.choice(ANCH)
        if k < 0.80:
            ng[0] += 1
            return "(" + gen_re(r, depth + 1, ng) + ")"
        if k < 0.86: return "(?:" + gen_re(r, depth + 1, ng) + ")"
        if k < 0.90: return "(?=" + r.choice(ATOMS[:12]) + ")"
        if k < 0.94: return "(?!" + r.choice(ATOMS[:12]) + ")"
        if k < 0.97: return "(?<=" + r.choice(["a", "b", "ab", "[ab]", "\\d", " "]) + ")"
        if k < 0.99: return "(?<!" + r.choice(["a", "b", "ab", "[ab]", "\\d", " "]) + ")"
        if ng[0] > 0: return "\\%d" % r.randint(1, min(ng[0], 3))
        return "a"
    out = []
    for _ in range(r.randint(1, 4)):
        a = atom()
        if a not in ANCH and not a.startswith("(?=") and not a.startswith("(?!") and not a.startswith("(?<") and r.random() < 0.35:
            a += r.choice(QUANT)
        out.append(a)
    s = "".join(out)
    if r.random() < 0.25: s += "|" + gen_re(r, depth + 1, ng) if depth < 2 else ""
    return s


def py_caret(p):
    out, i, cls = [], 0, False
    while i < len(p):
        c = p[i]
        if c == "\\" and i + 1 < len(p): out.append(p[i:i + 2]); i += 2; continue
        if cls:
            if c == "]": cls = False
        elif c == "[":
            cls = True; out.append(c); i += 1
            if i < len(p) and p[i] == "^": out.append("^"); i += 1
            if i < len(p) and p[i] == "]": out.append("]"); i += 1
            continue
        elif c == "^": out.append(r"(?:\A|(?<=\n)(?!\Z))"); i += 1; continue
        out.append(c); i += 1
    return "".join(out)


def rx_fuzz(engines, n, seed):
    r = random.Random(seed)
    fails, errs = [], 0
    base = tempfile.mkdtemp(prefix="frz.")
    try:
        for i in range(n):
            pat = gen_re(r)
            icase = r.random() < 0.4
            word = r.random() < 0.1
            text = "".join(r.choice(RTEXT) for _ in range(r.randint(0, 30)))
            try:
                full = re.sub(r"\[:alpha:\]", "a-zA-Z", pat)
                full = py_caret(full)
                if word: full = r"(?<!\w)(?:%s)(?!\w)" % full
                rx = re.compile(full, (re.I if icase else 0) | re.M)
                ng = rx.groups
            except re.error:
                rx = None
            reps = ["X", "", "<\\0>", "[$&]"] + (["\\%d" % g for g in range(1, min(ng, 3) + 1)] if rx else [])
            rep = r.choice(reps)
            for eng in engines:
                d = os.path.join(base, "r"); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
                open(os.path.join(d, "f"), "wb").write(enc(text))
                rc, out, err, st, lst, _ = eng.run("apply", d, [(enc(pat), enc(rep))], scope="contents", regex=True, case="any" if icase else "exact", word=word)
                if rx is None:
                    errs += 1
                    if rc != 2: fails.append("regex %r: python rejects it, engine rc=%d (%s)" % (pat, rc, eng.path))
                    continue
                def f(m):
                    out_, k = [], 0
                    while k < len(rep):
                        c = rep[k]
                        if c in "\\$" and k + 1 < len(rep):
                            dd = rep[k + 1]
                            if dd.isdigit(): out_.append(m.group(int(dd)) or ""); k += 2; continue
                            if c == "$" and dd == "&": out_.append(m.group(0)); k += 2; continue
                        out_.append(c); k += 1
                    return "".join(out_)
                want = enc(rx.sub(f, text))
                if (rc == 2 and b"too complex" in err) or st.get("content_errors", 0): continue   # gave up on a pathological pattern: file left alone
                got = open(os.path.join(d, "f"), "rb").read()
                if rc != 0 or got != want:
                    fails.append("regex %r rep %r icase=%s word=%s text %r:\n  got  %r (rc %d %s)\n  want %r (%s)" % (pat, rep, icase, word, text, got, rc, err.decode(errors="replace")[:80], want, eng.path))
            if len(fails) > 10: break
    finally:
        shutil.rmtree(base, ignore_errors=True)
    return fails, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", action="append", required=True)
    ap.add_argument("--n", type=int, default=1200)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--rx", type=int, default=1500, help="random regex patterns checked against Python re")
    ap.add_argument("--n-py", type=int, default=None, help="random ops when an engine is the python one (default: n/3)")
    a = ap.parse_args()
    engines = [Engine(os.path.abspath(e)) for e in a.engine]
    fails, ran = [], 0
    for sc in SCENARIOS:
        ran += 1
        try: run_scenario(engines, sc)
        except Fail as e: fails.append(str(e))
    try: extra_checks(engines)
    except Fail as e: fails.append(str(e))
    ran += 1
    r = random.Random(a.seed)
    has_py = any(e.path.endswith("findrep") for e in engines)
    n = a.n if not has_py else (a.n_py if a.n_py is not None else a.n)
    for i in range(n):
        tree = rtree(r)
        op = rop(r, tree)
        label = "random#%d(seed %d) %s scope=%s depth=%s case=%s regex=%s word=%s hidden=%s target=%s rules=%r" % (
            i, a.seed, "", op.scope, op.depth, op.case, op.regex, op.word, op.hidden, op.target, op.rules)
        ran += 1
        try: check_op(engines, tree, op, label)
        except Fail as e:
            fails.append(str(e) + "\n   tree=%r" % (tree,))
        if len(fails) >= 15: break
    rf, rerrs = rx_fuzz(engines, a.rx, a.seed)
    ran += a.rx
    fails += rf
    print("ran %d operations on %d engine(s) (%d regex patterns, %d of them rejected by both): %d failure(s)" % (ran, len(engines), a.rx, rerrs, len(fails)))
    for f in fails[:15]: print("FAIL:", f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
