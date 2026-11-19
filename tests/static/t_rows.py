"""ROW CHROME — every list a menu prints must be drawn with its rules by EXACTLY ONE party: the viewport (when it takes the list over) or the printer itself.
Born from: delete-by-date with ONE date showed a bare row (no rule above or below, no highlight), because the viewport ignored lists of one row and the picker
helpers never printed their own rules.  The same hole was in _mc_keyed and in the Transfer / CSV pickers (_pick_rows).
Three layers, no terminal, no app start, no sleeps:
  1. PROBE (tests/static/lib/rows_probe.sh): every row printer (_mc_options · _mc_keyed · _pick_group_rows · _pick_marked_rows · _pick_rows) prints 0/1/2/3 rows, with the
     viewport on (managed) and off (plain); its real output goes through the real _sm_detect.   Rules judged here:
       rows:own-rules   the viewport took the list over -> the printer prints NO rule · it did not -> the printer prints BOTH (never none, never doubled)
       rows:takeover    a list of 1, 2, 3 rows is taken over with exactly its rows (the owner's rule: ONE row is a list too; _VP_TAKEOVER_MIN = 1)
       rows:plain       with no viewport (not a tty, VK_SMART_MENUS=0) every printer still draws the same layout itself
  2. STATIC: one source for the take-over minimum (no literal count next to _mc_managed / in _sm_detect) · every picker screen (_pick_header) prints its rows through a
     rule-aware helper · every row printed straight to stdout has a number column the detector recognises (at most 4 leading cells).
Add a new row printer: add a  p_<name>()  to tests/static/lib/rows_probe.sh and its name to PRODUCERS there; the suite then covers it."""
import os, re, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('rows')

# ---------- layer 1: the probe
env = dict(os.environ, BVK_ROOT=bvk.ROOT)
pr = subprocess.run(['bash', os.path.join(bvk.TESTS, 'lib', 'rows_probe.sh')], capture_output=True, text=True, env=env, timeout=120)
if pr.returncode: raise SystemExit('rows_probe.sh failed (%d): %s' % (pr.returncode, (pr.stderr or pr.stdout)[:400]))
tmin = None; kmin = None; probe = []
for l in pr.stdout.splitlines():
    p = l.split('\t')
    if p[0] == 'T' and p[1] == 'takeover_min': tmin = p[2]
    elif p[0] == 'T' and p[1] == 'keyed_min': kmin = p[2]
    elif p[0] == 'P' and len(p) == 10: probe.append((p[1], p[2], int(p[3]), int(p[4]), int(p[5]), int(p[6]), int(p[7]), int(p[8]), int(p[9])))
R.check()
if tmin != '1': R.add('rows:policy:takeover_min', '_VP_TAKEOVER_MIN is %s: the viewport must take over a list of ONE row (it is the single source of the minimum, defined in smartmenu.sh)' % tmin)
for prod, mode, n, rc, found, rules, first, last, ftr in probe:
    R.check(3); fk = 'cells' if ftr == 0 else 'one-cell'
    need = int(kmin) if prod == 'mc_keyed' and (kmin or '').isdigit() else 1      # a LETTERED list needs _VP_TAKEOVER_MIN_KEYED rows (a lettered line is a key hint)
    if mode == 'managed':
        if rc == 0 and rules:
            R.add('rows:own-rules:%s:managed-%d:%s' % (prod, n, fk), '%s prints %d rule line(s) of its own for %d row(s) although the viewport takes the list over: rules drawn twice' % (prod, rules, n))
        if rc != 0 and not (rules == 2 and first and last):
            R.add('rows:own-rules:%s:managed-%d:%s' % (prod, n, fk), '%s: the viewport does not take %d row(s) over and the printer draws %d rule line(s): a bare list (no rule above / below)' % (prod, n, rules))
        if n >= need and (rc != 0 or found != n):
            R.add('rows:takeover:%s:%d:%s' % (prod, n, fk), '%s with %d row(s) and a %s footer: the viewport answers %d and found %d row(s) (a footer taken for a row, or no rules / highlight)' % (prod, n, fk, rc, found))
    else:
        if not (rules == 2 and first and last):
            R.add('rows:plain:%s:%d:%s' % (prod, n, fk), '%s with %d row(s) and NO viewport prints %d rule line(s): the list has no upper / lower line' % (prod, n, rules))

# ---------- layer 2: static
BODY = {}; FILE = {}
fre = re.compile(r'^([A-Za-z_][A-Za-z0-9_.:-]*)\(\)\s*\{')
for p in bvk.bash_files():
    if bvk.is_stub_file(p): continue
    L = bvk.read(p).split('\n'); i = 0
    while i < len(L):
        m = fre.match(L[i])
        if m:
            j = i
            if not (L[i].rstrip().endswith('}') and L[i].count('{') == L[i].count('}')):
                j = i + 1
                while j < len(L) and L[j] != '}': j += 1
            BODY.setdefault(m.group(1), '\n'.join(L[i:j + 1])); FILE.setdefault(m.group(1), bvk.rel(p)); i = j
        i += 1
def code(t): return '\n'.join(l for l in t.split('\n') if not l.lstrip().startswith('#'))

# 2a. one source for the take-over minimum
for fn, body in sorted(BODY.items()):
    c = code(body)
    for m in re.finditer(r'_mc_managed[^\n]*?\(\(\s*\$#\s*>=\s*(\d+)\s*\)\)|_mc_managed[^\n]*?\(\(\s*\$\{?1:-0\}?\s*>=\s*(\d+)\s*\)\)', c):
        R.check(); R.add('rows:literal-min:%s' % fn, '%s (%s) compares a row count with the literal %s next to _mc_managed: use ${_VP_TAKEOVER_MIN:-1}' % (fn, FILE[fn], m.group(1) or m.group(2)))
sd = code(BODY.get('_sm_detect', ''))
R.check()
if re.search(r'\breal\s*<\s*\d', sd): R.add('rows:literal-min:_sm_detect', '_sm_detect (%s) tests the row count against a literal: use _VP_TAKEOVER_MIN' % FILE.get('_sm_detect', '?'))
if '_VP_TAKEOVER_MIN' not in sd: R.add('rows:literal-min:_sm_detect-unused', '_sm_detect does not read _VP_TAKEOVER_MIN')

# 2b. every picker screen prints its rows through a rule-aware helper
SAFE = ('_pick_rows', '_pick_group_rows', '_pick_marked_rows', '_mc_options', '_mc_keyed', '_tpl_section', '_vp_', '_multi_')
for fn, body in sorted(BODY.items()):
    c = code(body)
    if not re.search(r'\b_pick_header\b', c) or fn in ('_pick_header',): continue
    R.check()
    if not any(s in c for s in SAFE): R.add('rows:picker-rows:%s' % fn, '%s (%s) draws a pick screen (_pick_header) but prints its rows through none of the rule-aware helpers' % (fn, FILE[fn]))
# the helpers themselves must own the rule logic
for fn in ('_pick_rows', '_pick_group_rows', '_pick_marked_rows'):
    R.check()
    if fn in BODY and '_pick_rule_open' not in BODY[fn]: R.add('rows:helper-rules:%s' % fn, '%s (%s) does not call _pick_rule_open / _pick_rule_close: the list it prints has no rules when the viewport does not take it over' % (fn, FILE[fn]))
# any code that prints a rule must say who it prints for
for fn, body in sorted(BODY.items()):
    if fn in ('_mc_options', '_mc_keyed', '_pick_rule_open', '_pick_rule_close'): continue
    if re.search(r'(echo|printf)[^\n]*\$_MC_RULE', code(body)):
        R.check(); R.add('rows:rule-print:%s' % fn, '%s (%s) prints _MC_RULE itself: only _mc_options / _mc_keyed / _pick_rule_open may (they know whether the viewport draws it)' % (fn, FILE[fn]))

# 2c. a row printed straight to stdout must be a row the detector recognises:  at most 4 leading cells, then digits and ")"
FMT = re.compile(r"printf\s+(?!-v)(['\"])(\s*)%(-?)(\d*)d\)(.*?)\1")
for p in bvk.bash_files():
    if bvk.is_stub_file(p): continue
    for n, l in enumerate(bvk.read(p).split('\n'), 1):
        if l.lstrip().startswith('#'): continue
        for m in FMT.finditer(l):
            R.check(); w = int(m.group(4) or 0); lead = len(m.group(2)) + (0 if m.group(3) else max(0, w - 1))
            if lead > 4: R.add('rows:format:%s:%d' % (bvk.rel(p), n), '%s:%d prints a numbered row with up to %d leading cells: the smart-menu detector accepts at most 4, so the list is not taken over' % (bvk.rel(p), n, lead))
sys.exit(R.finish())
