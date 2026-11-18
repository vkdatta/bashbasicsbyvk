"""WHOLE-APP lints over every bash file under script/ — read only, no app, no terminal.
  undef   a command-position call to an app-style function (has _ or bvk in the name) that nothing defines   (what broke as `_ad_open: command not found`)
  dead    a function defined but named nowhere else in script/        (mark a dynamic call with a comment:  # bvk-live: fn_name)
  syntax  bash -n on every file
  uniq    two files with the same basename (setup.py installs script/ flat)
  label   a generic footer key (u q z rf) typed by hand instead of coming from _MC_KEYLABEL
  menu    a hand-drawn numbered menu / 'Enter choice' prompt outside engine/ and settings/ (rule 18)
  vocab   one action (remove) offered under several keys / labels"""
import os, re, sys, subprocess
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('lint'); files = bvk.bash_files(); funcs = bvk.defined_functions()
text = {p: bvk.read(p) for p in files}

# ---- a tiny scanner: code of one line with comments and string contents blanked (but $( ... ) inside strings is kept)
def code_of(line):
    out = []; i = 0; n = len(line); q = None; depth = 0
    while i < n:
        c = line[i]
        if q is None:
            if c == '\\': out.append('  '); i += 2; continue
            if c == '#' and (i == 0 or line[i-1] in ' \t;'): break
            if c in '"\'': q = c; out.append(' '); i += 1; continue
            out.append(c); i += 1; continue
        if q == "'":
            if c == "'": q = None
            out.append(' '); i += 1; continue
        # inside "..."
        if c == '\\': out.append('  '); i += 2; continue
        if line.startswith('$(', i) and not line.startswith('$((', i): depth += 1; out.append('$('); i += 2; continue
        if depth and c == ')': depth -= 1; out.append(')'); i += 1; continue
        if c == '"' and not depth: q = None; out.append(' '); i += 1; continue
        out.append(c if depth else ' '); i += 1
    return ''.join(out)

KW = {'if', 'elif', 'while', 'until', 'then', 'do', 'else', '!', 'time', 'exec', 'builtin', 'command'}
SEP = re.compile(r'\|\||&&|[;|&{}`]|\$\(')
ARM = re.compile(r'^\s*\(?\s*[\w.*?\[\]|$@:=+-]+(?:\|[\w.*?\[\]|$@:=+-]+)*\)')
HERE = re.compile(r'<<-?\s*[\'"\\]?(\w+)[\'"]?')
def calls(t):
    """app-style names in command position"""
    found = []; tag = None; arr = False; cont = ''
    for l in t.splitlines():
        if cont: l = cont + ' ' + l.lstrip(); cont = ''
        elif l.endswith('\\') and not l.lstrip().startswith('#') and not tag: cont = l[:-1]; continue
        if l.endswith('\\') and not tag: cont = l[:-1]; continue
        if arr:                                      # inside a multi-line array literal
            if ')' in l: arr = False
            continue
        if tag:
            if l.strip() == tag: tag = None
            continue
        s = code_of(l)
        h = HERE.search(l)
        if h and '<<<' not in l: tag = h.group(1)
        if not s.strip(): continue
        if re.search(r'[A-Za-z_]\w*\+?=\([^)]*$', s): arr = True; continue
        s = re.sub(r'\$\{[^{}]*\}', ' ', s)                                              # ${var:-x} expansions
        s = re.sub(r'\$?\(\([^()]*(?:\([^()]*\)[^()]*)*\)\)', ' ', s)                  # (( arithmetic )) and $(( ... ))
        s = re.sub(r'^\s*(?:function\s+)?[A-Za-z_][\w.:-]*\s*\(\)\s*', ' ', s)         # a definition line
        s = re.sub(r'[A-Za-z_]\w*\+?=\([^()]*\)', ' ', s)                              # array literals
        s = ARM.sub(' ', s, count=1) if ARM.match(s) else s                              # a case pattern
        for seg in SEP.split(s):
            w = seg.split()
            while w and (w[0] in KW or re.match(r'^[A-Za-z_]\w*\+?=', w[0])): w = w[1:]
            if not w: continue
            name = w[0]
            if re.fullmatch(r'[A-Za-z_]\w*', name) and name == name.lower() and ('_' in name or 'bvk' in name): found.append(name)
    return found

known = set(funcs) | {os.path.basename(p) for p in bvk.all_files()}
for dp, dn, fn in os.walk(bvk.SCRIPT): known |= set(dn)
LIVE_BY_DESIGN = {'_lm_stub'}      # called only from the generated loader stubs
XUI_PFX = set(re.findall(r'_xui_screen\s+(\w+)', ' '.join(text.values())))   # _xui_screen ru  ->  calls ru_build / ru_header / ru_row / ru_footer by constructed name
LIVE_BY_DESIGN |= {p + '_' + n for p in XUI_PFX for n in ('build', 'header', 'row', 'footer', 'pp_build', 'pp_header', 'pp_row', 'pp_footer')}
live_marks = LIVE_BY_DESIGN | set(re.findall(r'bvk-live:\s*([\w.:-]+)', ' '.join(text.values())))

# undef
for p in files:
    seen = set()
    for name in calls(text[p]):
        if name in seen or name.startswith("_gd_orig_"): continue   # defined at run time by _gd_rename_fn
        seen.add(name); R.check()
        if name not in known and name not in os.environ and not os.path.exists('/usr/bin/' + name):
            R.add('undef:%s:%s' % (bvk.rel(p), name), 'calls %s, which no file defines' % name)

# dead
words = {}
for p_, t in text.items():
    if bvk.is_stub_file(p_): continue        # the loader stubs name every function: counting them would make every function look used
    for w in re.findall(r'[A-Za-z_]\w*', t): words[w] = words.get(w, 0) + 1
for name, defs_in in sorted(funcs.items()):
    R.check()
    if not re.fullmatch(r'[A-Za-z_]\w*', name) or name in live_marks: continue
    if words.get(name, 0) <= len(defs_in): R.add('dead:%s' % name, 'defined in %s but named nowhere else' % bvk.rel(defs_in[0]))

# syntax (bash -n), in parallel
def syn(p):
    r = subprocess.run(['bash', '-n', p], capture_output=True, text=True); return p, r.returncode, r.stderr.strip().splitlines()[:1]
with ThreadPoolExecutor(8) as ex:
    for p, rc, e in ex.map(syn, files):
        R.check()
        if rc: R.add('syntax:%s' % bvk.rel(p), (e or ['bash -n failed'])[0][:120])

# uniq basenames
bn = {}
for p in bvk.all_files():
    if any(("/"+d+"/") in p for d in ("bvk-ls","bvk-fr","bvk-xfer")): continue   # build-time sources, setup.py never installs them
    bn.setdefault(os.path.basename(p), []).append(p)
for b, ps in sorted(bn.items()):
    R.check()
    if len(ps) > 1 and not b.endswith(('.pyc',)): R.add('uniq:%s' % b, 'defined %d times: %s' % (len(ps), ', '.join(bvk.rel(x) for x in ps[:3])))

# label: generic footer keys typed by hand   (cmd_drift section 6)
HAND = re.compile(r'"(u|q|z|rf)(\.[a-z]+)?:|_mc_footer_register .*[ ](u|q|z|rf)(\.[a-z]+)?:[A-Za-z]')
for p in files:
    for n, l in enumerate(text[p].splitlines(), 1):
        if l.lstrip().startswith('#'): continue
        R.check()
        if HAND.search(l): R.add('label:%s:%d' % (bvk.rel(p), n) if False else 'label:%s' % bvk.rel(p), 'a generic footer key is typed with its own label (use the bare key: the label comes from _MC_KEYLABEL)')

# menu: hand-drawn menus (rule 18)
PAT = [('option row', re.compile(r'''(echo|print\(|printf)\s*f?["']\s*[1-9]\) \S''')), ('Enter choice prompt', re.compile(r'Enter choice')),
       ('typed (a/b) question', re.compile(r'''(_bvk_input\(|read\b[^\n]*-p\s+|input\()[^\n]*\((y/n|[a-z0-9]/[a-z0-9])\)''', re.I))]
for p in files:
    if re.search(r'/(engine|settings)/', p): continue
    for n, l in enumerate(text[p].splitlines(), 1):
        if 'bvk-read-ok' in l: continue
        for nm, rx in PAT:
            if rx.search(l): R.check(); R.add('menu:%s:%s' % (bvk.rel(p), nm.replace(' ', '-')), 'hand-drawn %s at line %d' % (nm, n))

# vocab: the remove action under many keys / labels
VERB = re.compile(r'(remove|delete|nuke|erase)', re.I); keys = {}; labels = {}
for p in files:
    for m in re.finditer(r'"([a-z]{1,3}-?)N?:([A-Za-z ]{3,40})"', text[p]):
        k, lab = m.group(1), m.group(2)
        if VERB.search(lab): keys.setdefault(k, set()).add(bvk.rel(p)); labels.setdefault(VERB.search(lab).group(1).lower(), set()).add(k)
R.check()
if len(keys) > 1: R.add('vocab:remove:keys=%s' % ','.join(sorted(keys)), 'the remove action is offered under %d keys (%s) and %d verbs (%s)' % (len(keys), ' '.join(sorted(keys)), len(labels), ' '.join(sorted(labels))))
sys.exit(R.finish())
