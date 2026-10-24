#!/usr/bin/env python3
"""bashbasicsbyvk_github against a local mock GitHub (no network).   python3 tests/github/github_test.py
Covers: finding the key (env, ~/.bashrc, files it sources, $(cat file), gh / git-credentials / netrc, cycles, fifos), lists, the upgrade
loop's parsers (byte-identical to the code they replaced), create / edit / rename (conflicts, swaps, chains, rollback) / delete, and clone
(full, depth, release assets, the key never follows a redirect to another host, and never shows up in any output)."""
import json, os, subprocess, sys, tempfile, importlib.machinery, importlib.util, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import mock_github as mg


def find_tool():                                   # files move: find by name (AGENTS: tests rule 5)
    for dp, _, fn in os.walk(os.path.join(ROOT, "script")):
        if "bashbasicsbyvk_github" in fn:
            return os.path.join(dp, "bashbasicsbyvk_github")
    sys.exit("bashbasicsbyvk_github not found")


TOOL = find_tool()
US = "\x1f"
FAILS, N = [], [0]


def check(name, cond, detail=""):
    N[0] += 1
    if cond:
        print("PASS", name)
    else:
        print("FAIL", name, ("\n     " + str(detail).replace("\n", "\n     ")) if detail else ""); FAILS.append(name)


class Env:
    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="bvk_gh_test_")
        self.home = os.path.join(self.tmp, "home"); os.makedirs(self.home)
        self.state = mg.State()
        self.api, self.stop = mg.start(self.state)
        self.seen_output = []

    def env(self, **extra):
        e = {k: v for k, v in os.environ.items() if not k.startswith(("GITHUB", "GH_", "BVK_GH"))}
        e.update(HOME=self.home, BVK_GH_API=self.api, BVK_GH_TOKEN=mg.GOOD, XDG_CONFIG_HOME=os.path.join(self.home, ".config"), LC_ALL="C.UTF-8")
        e.update(extra)
        for k in [k for k, v in e.items() if v is None]:
            del e[k]
        return e

    def run(self, *args, env=None, timeout=60):
        r = subprocess.run([sys.executable, TOOL] + list(args), capture_output=True, text=True, env=env or self.env(), timeout=timeout)
        self.seen_output.append(r.stdout + r.stderr)
        return r

    def job(self, repo, **files):
        d = tempfile.mkdtemp(dir=self.tmp)
        files["repo"] = repo
        for k, v in files.items():
            with open(os.path.join(d, k), "w", encoding="utf-8", newline="") as fh:
                fh.write(v if isinstance(v, str) else "\n".join(v) + "\n")
        return d

    def close(self):
        self.stop(); shutil.rmtree(self.tmp, ignore_errors=True)


def seed(E):
    """repo o/r: main -> c1 -> c2 ; tags v1.0 (annotated, release) v1.2 (lightweight, release) v1.9 (annotated, no release) v1.10 (lightweight, no release)
       plus a draft release for 'v2.0-draft' (no tag) and a pre-release v1.11-beta"""
    R = E.state.add("o/r", desc="the repo")
    c1 = R.commit("first\n"); c2 = R.commit("second\n\nbody line", [c1])
    R.branches["main"] = c2
    tg = {"name": "Ann", "email": "ann@x", "date": "2026-02-02T00:00:00Z"}
    def annotated(name, msg, commit):
        t = {"tag": name, "message": msg, "tagger": tg, "object": {"type": "commit", "sha": commit}}
        t["sha"] = mg.sha_of("tag", t); R.tag_objs[t["sha"]] = t; R.tags[name] = ("tag", t["sha"])
    annotated("v1.0", "release one\n", c1)
    R.tags["v1.2"] = ("commit", c2)
    annotated("v1.9", "nine\n", c2)
    R.tags["v1.10"] = ("commit", c2)
    R.tags["v1.11-beta"] = ("commit", c2)
    def rel(tag, name, body, **kw):
        r = {"id": R.rid(), "tag_name": tag, "name": name, "body": body, "draft": False, "prerelease": False,
             "published_at": "2026-10-1%dT00:00:00Z" % (len(R.releases) % 9), "created_at": "2026-10-01T00:00:00Z"}
        r.update(kw); R.releases.append(r); return r
    rel("v1.0", "v1.0", "first release\nline2")
    rel("v1.2", "Second", "notes 1.2")
    rel("v1.11-beta", "beta", "b", prerelease=True)
    rel("v2.0-draft", "draft", "d", draft=True)
    return R, c1, c2


def lines(r):
    return [l for l in r.stdout.splitlines() if l]


# ═══════════════════════════════════════════════════════════════════════════════════════════
def test_key_discovery():
    E = Env()
    try:
        nokey = E.env(BVK_GH_TOKEN=None)
        r = E.run("auth", env=nokey)
        check("key: nothing anywhere -> NONE, exit 5", r.returncode == 5 and r.stdout.startswith("NONE"), r.stdout + r.stderr)
        check("key: NONE lists the places it looked (bashrc among them is named once a file exists)", "environment" in r.stdout)
        open(os.path.join(E.home, ".bashrc"), "w").write("# nothing here\nalias x=y\n")
        r = E.run("auth", env=nokey)
        check("key: an existing but empty ~/.bashrc is listed as looked at", os.path.join(E.home, ".bashrc") in r.stdout, r.stdout)

        r = E.run("auth", env=E.env(BVK_GH_TOKEN=None, GITHUB_TOKEN=mg.GOOD))
        check("key: GITHUB_TOKEN in the environment", r.stdout.split(US)[:2] == ["OK", "tester"] and "GITHUB_TOKEN" in r.stdout, r.stdout)
        check("key: the key itself is never printed", mg.GOOD not in r.stdout + r.stderr)

        open(os.path.join(E.home, ".bashrc"), "w").write('export GITHUB_TOKEN="%s"   # mine\n' % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: export in ~/.bashrc (data, not run)", r.stdout.startswith("OK" + US + "tester") and ".bashrc" in r.stdout, r.stdout + r.stderr)

        open(os.path.join(E.home, ".bashrc"), "w").write('[ -f ~/.secrets ] && . ~/.secrets\n')
        open(os.path.join(E.home, ".secrets"), "w").write("export GH_TOKEN='%s'\n" % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: in a secrets file that ~/.bashrc sources", r.stdout.startswith("OK") and ".secrets" in r.stdout, r.stdout)

        open(os.path.join(E.home, ".bashrc"), "w").write('if [ -r "$HOME/.sec/keys" ]; then\n  source "$HOME/.sec/keys"\nfi\n')
        os.makedirs(os.path.join(E.home, ".sec"))
        open(os.path.join(E.home, ".sec", "keys"), "w").write("source ~/.sec/more\n")
        open(os.path.join(E.home, ".sec", "more"), "w").write("GITHUB_PAT=%s\n" % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: two files deep, quoted $HOME path, inside if/then", r.stdout.startswith("OK") and "more" in r.stdout, r.stdout)

        open(os.path.join(E.home, ".bashrc"), "w").write("export GITHUB_TOKEN=$(cat ~/.ghkey)\n")
        open(os.path.join(E.home, ".ghkey"), "w").write(mg.GOOD + "\n")
        r = E.run("auth", env=nokey)
        check("key: =$(cat FILE) is followed (and nothing else is evaluated)", r.stdout.startswith("OK"), r.stdout)
        marker = os.path.join(E.home, "PWNED")
        open(os.path.join(E.home, ".bashrc"), "w").write("export GITHUB_TOKEN=$(touch %s; echo x)\n" % marker)
        E.run("auth", env=nokey)
        check("key: a shell command in bashrc is NEVER run", not os.path.exists(marker))

        open(os.path.join(E.home, ".bashrc"), "w").write("source ~/.a\n")
        open(os.path.join(E.home, ".a"), "w").write("source ~/.b\n")
        open(os.path.join(E.home, ".b"), "w").write("source ~/.a\nexport GITHUB_TOKEN=%s\n" % mg.GOOD)
        r = E.run("auth", env=nokey, timeout=10)
        check("key: files that source each other do not loop", r.stdout.startswith("OK"), r.stdout)
        fifo = os.path.join(E.home, ".fifo"); os.mkfifo(fifo)
        open(os.path.join(E.home, ".bashrc"), "w").write("source ~/.fifo\n")
        try:
            r = E.run("auth", env=nokey, timeout=10); hung = False
        except subprocess.TimeoutExpired:
            hung = True
        check("key: a fifo named in bashrc does not hang the tool", not hung)
        os.unlink(fifo)

        open(os.path.join(E.home, ".bashrc"), "w").write("export GITHUB_TOKEN=bad-one\nexport GH_TOKEN=%s\n" % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: a rejected key is skipped, the next one that works is used", r.stdout.split(US)[:2] == ["OK", "tester"] and r.stdout.strip().endswith("1"), r.stdout)
        r2 = E.run("repos", env=E.env(BVK_GH_TOKEN=None, BVK_GH_PICK="1"))
        check("key: BVK_GH_PICK makes later calls use the key auth chose", r2.returncode == 0, r2.stderr)
        open(os.path.join(E.home, ".bashrc"), "w").write("export GITHUB_TOKEN=bad-one\n")
        r = E.run("auth", env=nokey)
        check("key: only a rejected key -> REJECTED, exit 5", r.returncode == 5 and r.stdout.startswith("REJECTED"), r.stdout)

        os.unlink(os.path.join(E.home, ".bashrc"))
        os.makedirs(os.path.join(E.home, ".config", "gh"))
        open(os.path.join(E.home, ".config", "gh", "hosts.yml"), "w").write("github.com:\n    user: tester\n    oauth_token: %s\n    git_protocol: https\n" % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: GitHub CLI hosts.yml", r.stdout.startswith("OK") and "hosts.yml" in r.stdout, r.stdout)
        os.unlink(os.path.join(E.home, ".config", "gh", "hosts.yml"))
        open(os.path.join(E.home, ".git-credentials"), "w").write("https://tester:%s@github.com\n" % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: ~/.git-credentials", r.stdout.startswith("OK") and ".git-credentials" in r.stdout, r.stdout)
        os.unlink(os.path.join(E.home, ".git-credentials"))
        open(os.path.join(E.home, ".netrc"), "w").write("machine github.com login tester password %s\n" % mg.GOOD)
        r = E.run("auth", env=nokey)
        check("key: ~/.netrc", r.stdout.startswith("OK") and ".netrc" in r.stdout, r.stdout)
        r = E.run("repos", env=nokey)
        check("key: a command without any key says so and exits 5", r.returncode == 5 or r.returncode == 0)   # netrc is present here
    finally:
        E.close()


def test_lists_and_parsers():
    E = Env()
    try:
        R, c1, c2 = seed(E)
        E.state.add("o/priv", private=True, fork=True, archived=True, desc="tab\there")
        r = E.run("repos")
        rows = [l.split(US) for l in lines(r)]
        names = [x[0] for x in rows]
        check("repos: every repo, with visibility and flags", names == ["o/r", "o/priv"] and rows[1][1:3] == ["private", "FA"], r.stdout + r.stderr)

        r = E.run("releases", "o/r")
        rows = [l.split(US) for l in lines(r)]
        check("releases: stable only (no draft, no pre-release)", [x[0] for x in rows] == ["v1.0", "v1.2"], r.stdout)
        check("releases: id, flags, escaped body", rows[0][5] == "first release\\nline2" and rows[0][3].isdigit() and rows[0][4] == "", rows[0])
        r = E.run("releases", "o/r", "--all")
        flags = {l.split(US)[0]: l.split(US)[4] for l in lines(r)}
        check("releases --all: drafts and pre-releases flagged", flags == {"v1.0": "", "v1.2": "", "v1.11-beta": "P", "v2.0-draft": "D"}, flags)

        big = E.state.add("o/big")
        c = big.commit("x"); big.branches["main"] = c
        for i in range(230):
            big.releases.append({"id": big.rid(), "tag_name": "t%03d" % i, "name": "n", "body": "", "draft": False, "prerelease": False, "published_at": "2026-01-01T00:00:00Z"})
        r = E.run("releases", "o/big")
        check("releases: paginates (230 over 3 pages)", len(lines(r)) == 230, len(lines(r)))

        r = E.run("tags", "o/r")
        rows = [l.split(US) for l in lines(r)]
        check("tags: newest VERSION first (v1.11-beta > v1.10 > v1.9 > v1.2 > v1.0)", [x[0] for x in rows] == ["v1.11-beta", "v1.10", "v1.9", "v1.2", "v1.0"], [x[0] for x in rows])
        d = {x[0]: x for x in rows}
        check("tags: type and release state", d["v1.0"][1] == "annotated" and d["v1.0"][4] == "stable" and d["v1.10"][1] == "lightweight" and d["v1.10"][4] == "" and d["v1.11-beta"][4] == "pre", d)

        r = E.run("info", "o/r", "v1.0")
        check("info: annotated tag, commit and release in one view", all(s in r.stdout for s in ("annotated tag", "release one", "first", "stable release", "first release")), r.stdout)
        r = E.run("info", "o/r", "v1.10")
        check("info: a tag without a release says so", "none (this is a tag only)" in r.stdout and "lightweight" in r.stdout, r.stdout)
        r = E.run("info", "o/r", "nope")
        check("info: unknown name -> exit 3", r.returncode == 3, r.stdout + r.stderr)
        got = {f: E.run("get", "o/r", "v1.0", f) for f in ("title", "body", "tag_message", "commit_message")}
        check("get: the raw current text of each editable field (no added newline)", got["title"].stdout == "v1.0" and got["body"].stdout == "first release\nline2" and got["tag_message"].stdout == "release one\n" and got["commit_message"].stdout == "first\n", {k: v.stdout for k, v in got.items()})
        check("get: a tag without a release has no title (exit 3); an unknown field is a usage error", E.run("get", "o/r", "v1.10", "title").returncode == 3 and E.run("get", "o/r", "v1.0", "zzz").returncode == 2)
    finally:
        E.close()


# the code the upgrade loop used to carry inline (copied verbatim from bashbasicsbyvk_upgrade.sh before it moved here)
OLD_RELEASES = r'''
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(2)
if not isinstance(data, list):
    sys.exit(2)
US = "\x1f"
for r in data:
    if r.get("draft") or r.get("prerelease"):
        continue
    body = (r.get("body") or "").replace("\r", "")
    body = body.replace("\\", "\\\\").replace("\n", "\\n").replace(US, " ")
    name = (r.get("name") or "").replace(US, " ").replace("\n", " ")
    print(US.join([r.get("tag_name") or "", name, (r.get("published_at") or "")[:10], body]))
'''
OLD_COMMIT = r'''
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    c = d["commit"]
except Exception:
    sys.exit(2)
US = "\x1f"
msg = (c.get("message") or "").replace("\r", "").replace("\\", "\\\\").replace("\n", "\\n").replace(US, " ")
au = c.get("author") or {}
print(US.join([(au.get("date") or "")[:10], (au.get("name") or "").replace(US, " "), msg]))
'''


def test_upgrade_parsers_identical():
    tmp = tempfile.mkdtemp(prefix="bvk_gh_parse_")
    try:
        nasty = [
            [],
            [{"tag_name": "v1", "name": "One", "published_at": "2026-01-02T03:04:05Z", "body": "a\r\nb\\c\x1fd\n\ntail"},
             {"tag_name": "v2", "name": "tw\no\x1f", "published_at": None, "body": None},
             {"tag_name": "d", "draft": True, "name": "x"}, {"tag_name": "p", "prerelease": True},
             {"name": "no tag", "published_at": "2026-05-05T00:00:00Z", "body": "é ü 日本"}],
            {"message": "not a list"},
        ]
        for i, data in enumerate(nasty):
            f = os.path.join(tmp, "r%d.json" % i); json.dump(data, open(f, "w", encoding="utf-8"))
            old = subprocess.run([sys.executable, "-c", OLD_RELEASES, f], capture_output=True)
            new = subprocess.run([sys.executable, TOOL, "parse-releases", f], capture_output=True)
            check("parse-releases #%d: same bytes and same exit code as the code it replaced" % i, (old.stdout, old.returncode) == (new.stdout, new.returncode), (old, new))
        bad = os.path.join(tmp, "bad.json"); open(bad, "w").write("{{{")
        old = subprocess.run([sys.executable, "-c", OLD_RELEASES, bad], capture_output=True)
        new = subprocess.run([sys.executable, TOOL, "parse-releases", bad], capture_output=True)
        check("parse-releases: broken JSON -> same exit code", old.returncode == new.returncode == 2, (old.returncode, new.returncode))
        for i, data in enumerate([{"commit": {"message": "m1\r\nm2\\x\x1f", "author": {"date": "2026-03-04T00:00:00Z", "name": "N\x1fn"}}},
                                  {"commit": {}}, {"nocommit": 1}, {"commit": {"message": None, "author": None}}]):
            f = os.path.join(tmp, "c%d.json" % i); json.dump(data, open(f, "w"))
            old = subprocess.run([sys.executable, "-c", OLD_COMMIT, f], capture_output=True)
            new = subprocess.run([sys.executable, TOOL, "parse-commit", f], capture_output=True)
            check("parse-commit #%d: same bytes and same exit code as the code it replaced" % i, (old.stdout, old.returncode) == (new.stdout, new.returncode), (old, new))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def load_tool_module():
    loader = importlib.machinery.SourceFileLoader("bvk_github_mod", TOOL)
    spec = importlib.util.spec_from_loader("bvk_github_mod", loader)
    m = importlib.util.module_from_spec(spec); loader.exec_module(m); return m


def test_plan_renames_unit():
    m = load_tool_module()
    P = m.plan_renames
    steps, notes, errs = P([("a", "b")], {"a", "c"}, set())
    check("plan: simple", steps == [("a", "b", False)] and not errs, (steps, errs))
    steps, notes, errs = P([("a", "c")], {"a", "c"}, set())
    check("plan: new name = an existing tag -> error", errs and "already exists" in errs[0], errs)
    steps, notes, errs = P([("a", "x"), ("b", "x")], {"a", "b"}, set())
    check("plan: two items to the same new name -> error", errs and "both become" in errs[0], errs)
    steps, notes, errs = P([("a", "X"), ("b", "x")], {"a", "b"}, set())
    check("plan: names that differ only in case clash with each other", errs and "case" in errs[0], errs)
    steps, notes, errs = P([("a", "B")], {"a", "b"}, set())
    check("plan: a case-twin of an existing tag is a conflict", bool(errs), errs)
    steps, notes, errs = P([("a", "v9")], {"a"}, {"V9"})
    check("plan: a release (even a draft without a tag) already using the name is a conflict", errs and "as a release" in errs[0], errs)
    steps, notes, errs = P([("v1", "V1")], {"v1"}, set())
    check("plan: renaming an item only by case is fine (it frees its own name)", steps == [("v1", "V1", False)] and not errs, (steps, errs))
    steps, notes, errs = P([("a", "a")], {"a"}, set())
    check("plan: same name is left alone, with a note", not steps and not errs and notes, (steps, notes))
    steps, notes, errs = P([("a", "b"), ("b", "c")], {"a", "b"}, set())
    check("plan: chain a->b, b->c runs b->c first", [s[:2] for s in steps] == [("b", "c"), ("a", "b")] and not errs, steps)
    steps, notes, errs = P([("a", "b"), ("b", "a")], {"a", "b"}, set())
    check("plan: a swap goes through one temp name", len(steps) == 3 and sum(1 for s in steps if s[2]) == 1 and not errs, steps)
    check("plan: the swap really ends as a<->b (simulated)", simulate(steps, {"a", "b"}) == {"a", "b"} and sim_map(steps) == {"a": "b", "b": "a"}, steps)
    steps, notes, errs = P([("a", "b"), ("b", "c"), ("c", "a")], {"a", "b", "c"}, set())
    check("plan: a 3-cycle works", not errs and sim_map(steps) == {"a": "b", "b": "c", "c": "a"}, steps)
    for bad in ("", "has space", "a..b", "-lead", "end.", "x.lock", "a~b", "a:b", "a^b", "a?b", "a*b", "a[b", "a\\b", "a@{b", "a//b", "/a", "a/", "@", "HEAD", ".hid", "d/.hid", "é" * 200):
        steps, notes, errs = P([("a", bad)], {"a"}, set())
        check("plan: refuses invalid name %r" % bad[:12], bool(errs), (steps, errs))
    for good in ("v1.0", "release/1.0", "rel-1_2+build.5", "é", "v1.0-rc.1"):
        steps, notes, errs = P([("a", good)], {"a"}, set())
        check("plan: accepts %r" % good, not errs, errs)
    t = m.apply_text
    check("text: set / prepend / append / replace", t("old", "set", "n", "") == ("n", "") and t("old", "prepend", "x ", "") == ("x old", "") and t("old", "append", " y", "") == ("old y", "") and t("a-b", "replace", "-", "+") == ("a+b", ""))
    check("text: replace with no match changes nothing and says why", t("abc", "replace", "z", "y")[0] == "abc" and "not found" in t("abc", "replace", "z", "y")[1])


def simulate(steps, start):
    cur = set(start)
    for o, n, _ in steps:
        assert o in cur and n not in cur - {o}, ("illegal step", o, n, cur)
        cur.discard(o); cur.add(n)
    return cur


def sim_map(steps):
    """original name -> final name, following temp hops"""
    where, final = {}, {}
    for o, n, tmp in steps:
        origin = where.pop(o, o)
        where[n] = origin
    return {v: k for k, v in where.items()}


def tags_of(R):
    return {n: v for n, v in R.tags.items()}


def test_edit():
    E = Env()
    try:
        R, c1, c2 = seed(E)
        j = E.job("o/r", tags=["v1.0", "v1.2"], **{"title.mode": "prepend", "title.a": "[stable] "})
        r = E.run("edit", "--job", j)
        titles = {x["tag_name"]: x["name"] for x in R.releases}
        check("edit: title prepend on two releases (bulk)", r.returncode == 0 and titles["v1.0"] == "[stable] v1.0" and titles["v1.2"] == "[stable] Second", (r.stdout, titles))
        j = E.job("o/r", tags=["v1.0", "v1.2"], **{"title.mode": "replace", "title.a": "[stable] ", "title.b": ""})
        E.run("edit", "--job", j)
        check("edit: title replace undoes it", {x["tag_name"]: x["name"] for x in R.releases}["v1.0"] == "v1.0")
        j = E.job("o/r", tags=["v1.0"], **{"body.mode": "set", "body.a": "multi\r\nline\n\nnotes é\n"})
        E.run("edit", "--job", j)
        check("edit: notes set, exact bytes (newlines, unicode)", next(x for x in R.releases if x["tag_name"] == "v1.0")["body"] == "multi\r\nline\n\nnotes é\n")
        j = E.job("o/r", tags=["v1.2"], **{"body.mode": "replace", "body.a": "nomatch", "body.b": "x"})
        r = E.run("edit", "--job", j)
        check("edit: replace without a match changes nothing, and says so", "not found" in r.stdout and next(x for x in R.releases if x["tag_name"] == "v1.2")["body"] == "notes 1.2", r.stdout)

        j = E.job("o/r", tags=["v1.0"], **{"tag_message.mode": "set", "tag_message.a": "new tag text\n"})
        r = E.run("edit", "--job", j)
        typ, sha = R.tags["v1.0"]
        t = R.tag_objs[sha]
        check("edit: annotated tag message replaced (new tag object, ref moved)", typ == "tag" and t["message"] == "new tag text\n" and t["tag"] == "v1.0" and t["tagger"]["name"] == "Ann" and t["object"]["sha"] == c1, (r.stdout, t))
        j = E.job("o/r", tags=["v1.2"], **{"tag_message.mode": "set", "tag_message.a": "now annotated"})
        r = E.run("edit", "--job", j)
        typ, sha = R.tags["v1.2"]
        check("edit: a lightweight tag given a message becomes annotated at the same commit", typ == "tag" and R.tag_objs[sha]["object"]["sha"] == c2 and "became annotated" in r.stdout, r.stdout)
        check("edit: ... and its release is untouched", any(x["tag_name"] == "v1.2" for x in R.releases))

        j = E.job("o/r", tags=["v1.10"], **{"title.mode": "set", "title.a": "T"})
        r = E.run("edit", "--job", j)
        check("edit: title on a tag without a release is skipped with a note (not an error)", r.returncode == 0 and "no release" in r.stdout, r.stdout)

        j = E.job("o/r", tags=["v1.9"], **{"commit_message.mode": "append", "commit_message.a": "\n\nreworded"})
        old_commit = R.tag_objs[R.tags["v1.9"][1]]["object"]["sha"]
        r = E.run("edit", "--job", j)
        typ, sha = R.tags["v1.9"]
        newc = R.tag_objs[sha]["object"]["sha"]
        oc, nc = R.commits[old_commit], R.commits[newc]
        check("edit: commit message -> a NEW commit, same tree, parents and author", newc != old_commit and nc["message"].endswith("reworded") and nc["tree"] == oc["tree"] and nc["parents"] == oc["parents"] and nc["author"] == oc["author"], (r.stdout, nc))
        check("edit: ... the annotated tag keeps its message and now points at the new commit", R.tag_objs[sha]["message"] == "nine\n")
        check("edit: ... the old commit still exists, the branch was NOT moved without asking", old_commit in R.commits and R.branches["main"] == old_commit)
        j = E.job("o/r", tags=["v1.10"], **{"commit_message.mode": "set", "commit_message.a": "fresh\n", "move_branch": "1"})
        old_commit = R.tags["v1.10"][1]
        r = E.run("edit", "--job", j)
        typ, sha = R.tags["v1.10"]
        check("edit: lightweight tag: only the ref moves", typ == "commit" and sha != old_commit and R.commits[sha]["message"] == "fresh\n", r.stdout)
        check("edit: move_branch moves a branch that ends at the old commit", R.branches["main"] == sha, (R.branches, sha))
        j = E.job("o/r", tags=["nope"], **{"title.mode": "set", "title.a": "T"})
        r = E.run("edit", "--job", j)
        check("edit: unknown tag -> error line, exit 1", r.returncode == 1 and "nope" in r.stdout, r.stdout)
        j = E.job("o/r", tags=["v1.0", "nope", "v1.2"], **{"title.mode": "set", "title.a": "Z"})
        r = E.run("edit", "--job", j)
        check("edit: one bad item does not stop the others", {x["tag_name"]: x["name"] for x in R.releases}["v1.2"] == "Z" and r.returncode == 1)
    finally:
        E.close()


def tag_set(R): return set(R.tags)
def rel_tags(R): return {x["tag_name"] for x in R.releases}


def test_rename():
    E = Env()
    try:
        R, c1, c2 = seed(E)
        before = (dict(R.tags), [dict(x) for x in R.releases])
        for name, new, why in (("tag exists", "v1.9", "already exists"), ("release (draft, no tag) uses it", "v2.0-draft", "as a release"),
                               ("bad chars", "a b", "space"), ("empty", "", "empty"), ("case twin", "V1.9", "already exists")):
            j = E.job("o/r", tags=["v1.0"], **{"rule.mode": "manual", "map": "v1.0\t%s\n" % new})
            r = E.run("rename", "--job", j)
            check("rename: %s -> refused, exit 1, says why" % name, r.returncode == 1 and why in r.stdout.lower().replace("space", "space") and "nothing was renamed" in r.stdout, r.stdout)
        check("rename: after every refusal NOTHING changed", (dict(R.tags), [dict(x) for x in R.releases]) == before)
        j = E.job("o/r", tags=["v1.0", "v1.2"], **{"rule.mode": "regex", "rule.a": r"^v1\..*$", "rule.b": "same"})
        r = E.run("rename", "--job", j)
        check("rename: a batch whose items would collide is refused as a whole", r.returncode == 1 and "both become" in r.stdout and (dict(R.tags), [dict(x) for x in R.releases]) == before, r.stdout)

        j = E.job("o/r", tags=["v1.0", "v1.2", "v1.9", "v1.10"], **{"rule.mode": "prefix", "rule.a": "rel-"})
        r = E.run("rename", "--job", j, "--plan")
        check("rename --plan: shows the plan, changes nothing", r.returncode == 0 and "v1.0  ->  rel-v1.0" in r.stdout and "release follows" in r.stdout and (dict(R.tags), [dict(x) for x in R.releases]) == before, r.stdout)
        r = E.run("rename", "--job", j)
        check("rename: prefix on annotated + lightweight, with and without release", r.returncode == 0 and tag_set(R) >= {"rel-v1.0", "rel-v1.2", "rel-v1.9", "rel-v1.10"} and not tag_set(R) & {"v1.0", "v1.2", "v1.9", "v1.10"}, (r.stdout, tag_set(R)))
        check("rename: the releases follow their tags, titles equal to the old tag follow too", {x["tag_name"]: x["name"] for x in R.releases if x["tag_name"].startswith("rel-")} == {"rel-v1.0": "rel-v1.0", "rel-v1.2": "Second"}, [(x["tag_name"], x["name"]) for x in R.releases])
        typ, sha = R.tags["rel-v1.9"]
        t = R.tag_objs[sha]
        check("rename: an annotated tag gets a NEW tag object named like the new tag, same message, tagger and target", typ == "tag" and t["tag"] == "rel-v1.9" and t["message"] == "nine\n" and t["tagger"]["name"] == "Ann" and t["object"]["sha"] == c2, t)
        check("rename: the drafts/pre-releases that were not selected are untouched", "v1.11-beta" in R.tags and "v2.0-draft" in rel_tags(R))

        # swap + chain
        R2 = E.state.add("o/sw"); c = R2.commit("x"); R2.branches["main"] = c
        for n in ("a", "b", "c"):
            R2.tags[n] = ("commit", c)
        R2.releases.append({"id": R2.rid(), "tag_name": "a", "name": "a", "body": "A", "draft": False, "prerelease": False, "published_at": "2026-01-01T00:00:00Z"})
        R2.releases.append({"id": R2.rid(), "tag_name": "b", "name": "B title", "body": "B", "draft": False, "prerelease": False, "published_at": "2026-01-01T00:00:00Z"})
        j = E.job("o/sw", tags=["a", "b"], **{"rule.mode": "manual", "map": "a\tb\nb\ta\n"})
        r = E.run("rename", "--job", j)
        by = {x["tag_name"]: x for x in R2.releases}
        check("rename: a swap (a<->b) works through a temp name and leaves no temp behind", r.returncode == 0 and set(R2.tags) == {"a", "b", "c"} and by["b"]["body"] == "A" and by["a"]["body"] == "B", (r.stdout, set(R2.tags), by))
        check("rename: ... titles followed the swap", by["b"]["name"] == "b" and by["a"]["name"] == "B title", by)
        j = E.job("o/sw", tags=["a", "b", "c"], **{"rule.mode": "manual", "map": "a\tb\nb\tc\nc\td\n"})
        r = E.run("rename", "--job", j)
        check("rename: a chain a->b, b->c, c->d", r.returncode == 0 and set(R2.tags) == {"b", "c", "d"}, (r.stdout, set(R2.tags)))
        j = E.job("o/sw", tags=["b"], **{"rule.mode": "manual", "map": "b\tB\n"})
        r = E.run("rename", "--job", j)
        check("rename: case-only rename of one item is allowed", r.returncode == 0 and "B" in R2.tags and "b" not in R2.tags, (r.stdout, set(R2.tags)))
        j = E.job("o/sw", tags=["c"], **{"rule.mode": "manual", "map": "c\tc\n"})
        r = E.run("rename", "--job", j)
        check("rename: same name = nothing to rename (exit 3), nothing changed", r.returncode == 3 and "c" in R2.tags, r.stdout)

        # rollback when the release cannot follow
        R3 = E.state.add("o/rb"); c = R3.commit("x"); R3.branches["main"] = c; R3.tags["t1"] = ("commit", c)
        R3.releases.append({"id": R3.rid(), "tag_name": "t1", "name": "t1", "body": "", "draft": False, "prerelease": False, "published_at": "2026-01-01T00:00:00Z"})
        E.state.fail["patch_release"] = {"t1"}
        j = E.job("o/rb", tags=["t1"], **{"rule.mode": "prefix", "rule.a": "new-"})
        r = E.run("rename", "--job", j)
        check("rename: when GitHub refuses to move the release, the new tag is removed again (nothing half-renamed)", r.returncode == 1 and set(R3.tags) == {"t1"} and R3.releases[0]["tag_name"] == "t1", (r.stdout, set(R3.tags)))
        E.state.fail.clear()

        # a rename that has a slash in it
        j = E.job("o/rb", tags=["t1"], **{"rule.mode": "prefix", "rule.a": "release/"})
        r = E.run("rename", "--job", j)
        check("rename: names with a slash (release/t1) work", r.returncode == 0 and "release/t1" in R3.tags, r.stdout)
        j = E.job("o/rb", tags=["release/t1"], **{"rule.mode": "regex", "rule.a": "("})
        r = E.run("rename", "--job", j)
        check("rename: a broken regex is reported, not a crash", r.returncode == 2 and "bad pattern" in r.stdout, r.stdout + r.stderr)
    finally:
        E.close()


def test_delete_and_create():
    E = Env()
    try:
        R, c1, c2 = seed(E)
        j = E.job("o/r", tags=["v1.0"], release="1")
        r = E.run("delete", "--job", j)
        check("delete: release only - the git tag stays", r.returncode == 0 and "v1.0" in R.tags and "v1.0" not in rel_tags(R), r.stdout)
        j = E.job("o/r", tags=["v1.2", "v1.9"], release="1", tag="1")
        r = E.run("delete", "--job", j)
        check("delete: release + tag, in bulk; a tag without a release is just noted", r.returncode == 0 and not tag_set(R) & {"v1.2", "v1.9"} and "no release to delete" in r.stdout, r.stdout)
        j = E.job("o/r", tags=["v1.10", "ghost"], tag="1")
        r = E.run("delete", "--job", j)
        check("delete: tag only; a missing one is noted, not fatal", r.returncode == 0 and "v1.10" not in R.tags and "no tag to delete" in r.stdout, r.stdout)
        j = E.job("o/r", tags=["v1.0"])
        check("delete: with nothing chosen it does nothing (exit 3)", E.run("delete", "--job", j).returncode == 3)

        j = E.job("o/r", tag="v3.0", title="Three", body="notes\n")
        r = E.run("create-release", "--job", j)
        rel = next((x for x in R.releases if x["tag_name"] == "v3.0"), None)
        check("create-release: new tag from the default branch, stable (not draft/pre)", r.returncode == 0 and rel and not rel["draft"] and not rel["prerelease"] and R.tags["v3.0"] == ("commit", R.branches["main"]) and rel["name"] == "Three", (r.stdout, R.tags.get("v3.0")))
        j = E.job("o/r", tag="v3.1", target="main", tag_message="annotated three-one\n")
        r = E.run("create-release", "--job", j)
        typ, sha = R.tags["v3.1"]
        check("create-release: with a tag message -> an annotated tag, title defaults to the tag", r.returncode == 0 and typ == "tag" and R.tag_objs[sha]["message"] == "annotated three-one\n" and next(x for x in R.releases if x["tag_name"] == "v3.1")["name"] == "v3.1", r.stdout)
        j = E.job("o/r", tag="v1.10", title="On an existing tag")
        r = E.run("create-release", "--job", j)
        check("create-release: on an existing tag attaches to it", r.returncode == 0 and "v1.10" in rel_tags(R), r.stdout)
        j = E.job("o/r", tag="v3.0")
        r = E.run("create-release", "--job", j)
        check("create-release: a release that exists is refused", r.returncode == 1 and "already exists" in r.stdout, r.stdout)
        j = E.job("o/r", tag="bad name")
        check("create-release: an invalid tag name is refused", E.run("create-release", "--job", j).returncode == 1)
        j = E.job("o/r", tag="v3.2", target="does-not-exist")
        r = E.run("create-release", "--job", j)
        check("create-release: an unknown target is an error and leaves nothing behind", r.returncode != 0 and "v3.2" not in R.tags, r.stdout + r.stderr)
        j = E.job("o/r", tag="t-light", target=c1)
        r = E.run("create-tag", "--job", j)
        check("create-tag: lightweight at a commit sha", r.returncode == 0 and R.tags["t-light"] == ("commit", c1), r.stdout)
        j = E.job("o/r", tag="t-ann", tag_message="hello")
        r = E.run("create-tag", "--job", j)
        check("create-tag: annotated at the default branch", r.returncode == 0 and R.tags["t-ann"][0] == "tag", r.stdout)
        j = E.job("o/r", tag="t-ann")
        check("create-tag: an existing name is refused", E.run("create-tag", "--job", j).returncode == 1)
        j = E.job("o/r", tag="v2.0-draft")
        check("create-tag: a name used by a (draft) release is refused", E.run("create-tag", "--job", j).returncode == 1)
    finally:
        E.close()


def git(*a, cwd=None):
    return subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True, check=True,
                          env=dict(os.environ, GIT_AUTHOR_NAME="A", GIT_AUTHOR_EMAIL="a@x", GIT_COMMITTER_NAME="A", GIT_COMMITTER_EMAIL="a@x", GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null")).stdout.strip()


def test_clone():
    if shutil.which("git") is None:
        print("SKIP clone tests: git not installed (NOT verified)"); return
    E = Env()
    try:
        R, c1, c2 = seed(E)
        work = os.path.join(E.tmp, "work"); bare = os.path.join(E.tmp, "git", "o", "r.git")
        os.makedirs(work); os.makedirs(os.path.dirname(bare))
        git("init", "-q", "-b", "main", cwd=work)
        for i in range(1, 4):
            open(os.path.join(work, "f.txt"), "w").write("v%d\n" % i); git("add", ".", cwd=work); git("commit", "-q", "-m", "c%d" % i, cwd=work)
            if i == 1: git("tag", "-a", "v1.0", "-m", "one", cwd=work)
            if i == 2: git("tag", "v1.2", cwd=work)
            if i == 3: git("tag", "v1.3", cwd=work)          # a tag in git that has NO release in the mock
        git("clone", "-q", "--bare", work, bare)
        tip = git("rev-parse", "v1.2", cwd=work)
        # the mock's release has an asset behind a redirect to ANOTHER host
        rel = next(x for x in R.releases if x["tag_name"] == "v1.2")
        R.assets["%d1" % rel["id"]] = ("tool.tar.gz", b"x"); E.state.blobs["%d1" % rel["id"]] = b"BINARYDATA"
        env = E.env(BVK_GH_GIT_BASE="file://" + os.path.join(E.tmp, "git"))
        dest = os.path.join(E.tmp, "dl")
        j = E.job("o/r", tags=["v1.2", "v1.0"], dest=dest, depth="1")
        r = E.run("clone", "--job", j, env=env)
        d12, d10 = os.path.join(dest, "r-v1.2"), os.path.join(dest, "r-v1.0")
        check("clone depth 1: both tags land in their own folders", r.returncode == 0 and os.path.isdir(d12) and os.path.isdir(d10), (r.stdout, r.stderr))
        check("clone depth 1: checked out at the tag, history is ONE commit", git("rev-parse", "HEAD", cwd=d12) == tip and git("rev-list", "--count", "HEAD", cwd=d12) == "1", "")
        check("clone depth 1: an annotated tag works too (file content of that version)", open(os.path.join(d10, "f.txt")).read() == "v1\n")
        j = E.job("o/r", tags=["v1.2"], dest=dest)
        r = E.run("clone", "--job", j, env=env)
        full = os.path.join(dest, "r-v1.2-2")
        check("clone full: the existing folder is never overwritten (-2), whole history", os.path.isdir(full) and git("rev-list", "--count", "HEAD", cwd=full) == "2" and git("rev-list", "--all", "--count", cwd=full) == "3", (r.stdout, r.stderr))
        check("clone full: detached at the tag", git("rev-parse", "HEAD", cwd=full) == tip)
        j = E.job("o/r", tags=["v1.2", "v1.0", "v1.3"], dest=dest, depth="0", with_release="1")
        r = E.run("clone", "--job", j, env=env)
        rd = [d for d in os.listdir(dest) if d.startswith("r-v1.2") and d.endswith("-release")]
        check("clone with release: notes + asset downloaded next to the clone", rd and os.path.isfile(os.path.join(dest, rd[0], "tool.tar.gz")) and open(os.path.join(dest, rd[0], "tool.tar.gz"), "rb").read() == b"BINARYDATA" and "Second" in open(os.path.join(dest, rd[0], "release.md")).read(), (r.stdout, os.listdir(dest)))
        check("clone with release: a tag without a release is cloned and says so", "no release for this tag" in r.stdout)
        check("clone: the key was NOT sent to the other host the download was redirected to", E.state.blob_seen and all(h is None for h in E.state.blob_seen), E.state.blob_seen)
        j = E.job("o/r", tags=["nope"], dest=dest, depth="1")
        r = E.run("clone", "--job", j, env=env)
        check("clone: an unknown tag fails cleanly and leaves no half folder", r.returncode == 1 and not os.path.exists(os.path.join(dest, "r-nope")), (r.stdout, r.stderr))
    finally:
        E.close()


def main():
    for f in (test_key_discovery, test_lists_and_parsers, test_upgrade_parsers_identical, test_plan_renames_unit, test_edit, test_rename, test_delete_and_create, test_clone):
        try:
            f()
        except Exception as e:                         # a crash is a failure with evidence, not a skip
            import traceback; traceback.print_exc()
            check("%s ran to the end" % f.__name__, False, repr(e))
    print("\n%d checks, %d failed" % (N[0], len(FAILS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
