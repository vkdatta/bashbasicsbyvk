#!/usr/bin/env python3
"""The GitHub screens in the REAL app (pty) against the local mock GitHub (no network).   python3 tests/github/ui_test.py
fx -> github_fx -> open github: no key message · repos · Stable / Tags tabs · info · rename (conflict refused, then done) ·
bulk edit · delete · download with depth.  Every step waits for what it needs on screen (AGENTS: no sleeps)."""
import os, subprocess, sys, shutil
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tests", "paste_input")); sys.path.insert(0, HERE)
from ptyapp import PtyApp
import mock_github as mg
import github_test as gt

FAILS = []
def check(name, cond, a=None):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        FAILS.append(name)
        if a is not None: print("   screen:\n   " + "\n   ".join(l.rstrip() for l in a.lines() if l.strip())[-1800:])

def L(a, text, t=1.2, until=None):
    a.line(text, t=t, until=until); a.settle()

def on_tab(a, label):
    """is the NEWEST repo header on screen showing [label]?  (older screens stay visible above it)"""
    hdr = [l for l in a.lines() if "\U0001F419 o/r" in l]
    return bool(hdr) and ("[" + label + "]") in hdr[-1]

def start(E, key=True, extra=None):
    # the app reads GH_TOKEN / GITHUB_PAT before GITHUB_TOKEN: a machine that has one set (CI, agent sandbox) must not leak into the test (None removes the variable)
    env = {"BVK_GH_API": E.api, "GH_TOKEN": None, "GITHUB_PAT": None, "GITHUB_TOKEN": mg.GOOD if key else None}; env.update(extra or {})
    return PtyApp(ROOT, 110, 45, lambda h, w: None, env=env, answer_dsr=True)    # a real terminal answers the cursor-position query the mouse code asks

def to_github(a, wait_for):
    L(a, "fx"); L(a, "3"); L(a, "1", t=4, until=lambda: wait_for in a.text())

def run_no_key():
    E = gt.Env(); gt.seed(E); a = start(E, key=False)
    try:
        to_github(a, "No GitHub key")
        t = a.text()
        check("no key: says so", "No GitHub key was found" in t, a)
        check("no key: tells them to use ~/.bashrc or the secrets file it sources", "~/.bashrc" in t and "export GITHUB_TOKEN=" in t and "secrets file" in t, a)
        check("no key: lists no repos and does not open a screen", "o/r" not in t and "signed in" not in t, a)
    finally: a.close(); E.close()

def run_screens():
    E = gt.Env(); R, c1, c2 = gt.seed(E); E.state.add("o/second", private=True)
    bare = os.path.join(E.tmp, "git", "o", "r.git"); work = os.path.join(E.tmp, "w"); os.makedirs(work); os.makedirs(os.path.dirname(bare))
    for i in range(1, 4):
        open(os.path.join(work, "f"), "w").write(str(i))
        if i == 1: gt.git("init", "-q", "-b", "main", cwd=work)
        gt.git("add", ".", cwd=work); gt.git("commit", "-q", "-m", "c%d" % i, cwd=work)
        if i == 2: gt.git("tag", "v1.2", cwd=work)
    gt.git("clone", "-q", "--bare", work, bare)
    a = start(E, extra={"BVK_GH_GIT_BASE": "file://" + os.path.join(E.tmp, "git")})
    try:
        to_github(a, "signed in")
        t = a.text()
        check("repos: both repos listed with who is signed in and where the key came from", "o/r" in t and "o/second" in t and "tester" in t and "GITHUB_TOKEN" in t and "🔒" in t, a)
        L(a, "1", t=4, until=lambda: "[📦 Stable]" in a.text())
        t = a.text()
        check("repo: Stable tab = stable releases only", "v1.0" in t and "v1.2" in t and "beta" not in t.split("Stable")[-1] and "2 release(s)" in t, a)
        a.send("\x1b[C"); a.wait(lambda: "[🔖 Tags]" in a.text()); a.settle()
        t = a.text()
        check("repo: the right arrow switches to the Tags tab (5 tags, newest version first, stable ones marked)", "5 tag(s)" in t and "✓ stable" in t and t.index("v1.11-beta") < t.index("v1.10") < t.index("v1.9"), a)
        a.send("\x1b[D"); a.wait(lambda: "[📦 Stable]" in a.text()); a.settle()
        L(a, "i-1", until=lambda: "first release" in a.text())
        check("info: release notes of row 1", "stable release" in a.text() and "first release" in a.text(), a)

        # download with depth 1, no release files
        dest = os.path.join(E.tmp, "dl")
        L(a, "g-2", until=lambda: "With depth" in a.text()); L(a, "1", until=lambda: "Depth" in a.text())
        L(a, "", until=lambda: "release notes" in a.text()); L(a, "n", until=lambda: "Download into" in a.text())
        L(a, dest, until=lambda: "Start?" in a.text()); L(a, "y", until=lambda: "depth 1" in a.text().split("Start?")[-1] and "💫" in a.text().split("Start?")[-1] or "❌" in a.text().split("Start?")[-1])
        a.settle()
        d = os.path.join(dest, "r-v1.2")
        check("download: depth 1 clone of v1.2 is in the chosen place, at that tag, one commit", os.path.isdir(d) and gt.git("rev-list", "--count", "HEAD", cwd=d) == "1" and open(os.path.join(d, "f")).read() == "2", a)

        # every key the footer prints must be a command the app accepts HERE (command map, hint, cheat code, loop: one truth)
        for k, word in (("c", "Create"), ("e", "Edit"), ("r", "Rename"), ("d", "Delete"), ("g", "Download"), ("rf", "Reload"),
                        ("e-", "Edit"), ("r-", "Rename"), ("d-", "Delete"), ("g-", "Download"), ("i-", "Info")):
            a.send(k); a.settle(); t = a.text()
            hint = [l for l in t.splitlines() if l.strip().startswith(k + "  \u2192")]
            check("footer key %-2s is accepted here: the hint names it, never 'not available'" % k, "not available" not in t and bool(hint) and word in hint[-1], a)
            a.send("\x7f" * len(k)); a.settle()
        L(a, "cc", until=lambda: "Delete" in a.text()); t = a.text()
        check("cheat codes (cc) list the screen's own commands", all(w in t for w in ("Create", "Edit", "Rename", "Delete", "Download", "Reload")) and "not available" not in t, a)
        L(a, "u"); a.settle()
        # arrows and touch right after an invalid command (the cancel / redraw path) must not be typed into the prompt as text
        L(a, "zzz"); a.send("\x1b[C"); a.settle(); a.send("\x1b[<0;20;12M\x1b[<0;20;12m\x1b[<64;20;12M"); a.settle(); t = a.text()
        check("after an invalid command: arrow, tap and wheel do not appear as text", "[C" not in t and "[<" not in t, a)
        a.send("\x1b[D"); a.wait(lambda: on_tab(a, "\U0001F4E6 Stable")); a.settle()      # the probe's right arrow switched to Tags, as it should

        # rename: conflict first -> refused, nothing changes
        before = dict(R.tags)
        L(a, "r-2", until=lambda: "v1.2 → " in a.text())
        a.send("\x15"); L(a, "v1.0", until=lambda: "naming problem" in a.text())
        check("rename: a name that is already taken is refused before anything is changed", "already exists" in a.text() and "nothing was renamed" in a.text() and dict(R.tags) == before, a)
        # rename: prefix on both, confirmed
        L(a, "r-1,2", until=lambda: "Add a prefix" in a.text()); L(a, "1", until=lambda: "Prefix" in a.text())
        L(a, "rel-", until=lambda: "Rename now?" in a.text() or "naming problem" in a.text())
        check("rename: the plan is shown, with 'release follows'", "v1.0  ->  rel-v1.0" in a.text() and "release follows" in a.text(), a)
        L(a, "y", until=lambda: "rel-v1.2" in a.text().split("Rename now?")[-1] and "Select:" in a.text().split("Rename now?")[-1])
        a.settle()
        check("rename: done on GitHub (tags and releases) and the list reloaded", {"rel-v1.0", "rel-v1.2"} <= set(R.tags) and {"rel-v1.0", "rel-v1.2"} <= {x["tag_name"] for x in R.releases} and "rel-v1.0" in a.text().split("Rename now?")[-1], a)

        # bulk edit: prepend a text to both release titles
        L(a, "e-1,2", until=lambda: "What do you want to change?" in a.text() or "Edit 2" in a.text())
        L(a, "1"); L(a, "d", until=lambda: "How to change" in a.text())
        L(a, "3", until=lambda: "Text to add" in a.text())
        L(a, "[ok] ", until=lambda: "Apply to 2" in a.text()); L(a, "y")
        a.wait(lambda: all(x["name"].startswith("[ok] ") for x in R.releases if x["tag_name"].startswith("rel-")), 8)
        check("edit: two release titles changed in one go (bulk prepend)", all(x["name"].startswith("[ok] ") for x in R.releases if x["tag_name"].startswith("rel-")), a)

        # delete release + tag of row 1
        L(a, "d-1", until=lambda: "release AND its git tag" in a.text()); L(a, "2", until=lambda: "Delete 1 item" in a.text()); L(a, "y")
        a.wait(lambda: len([x for x in R.releases if x["tag_name"].startswith("rel-")]) == 1, 8)
        check("delete: the release and its tag are gone, the other one stays", len([t for t in R.tags if t.startswith("rel-")]) == 1 and len([x for x in R.releases if x["tag_name"].startswith("rel-")]) == 1, a)
        L(a, "u"); L(a, "u")
        check("u twice goes back out of the repo and the repo list", a.alive and "Select" in a.text(), a)
    finally: a.close(); E.close()

if __name__ == "__main__":
    for f in (run_no_key, run_screens):
        try: f()
        except Exception as e:
            import traceback; traceback.print_exc(); FAILS.append(f.__name__)
    print("\n%d failed" % len(FAILS)); sys.exit(1 if FAILS else 0)
