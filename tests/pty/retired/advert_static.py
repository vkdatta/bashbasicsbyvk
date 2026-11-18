#!/usr/bin/env python3
"""ADVERT SCORE, no terminal, all menus, a few seconds.      python3 tests/advert_static.py [menu-substring]

  declared  D  what the menu tells the dispatcher it accepts (what cc lists)                       ← tests/advert_dump.sh (the real code, one process)
  accepted  A  what the menu's loop really handles: the `case` arms of its function (mapgen's harvester, the same one that writes the maps)
               + what the dispatcher itself accepts for it (inherited main words, tools)
  footer    F  the keys its footer call sites print (every _mc_footer / _tm_footer item in the file that owns the menu)

  coverage      = A ∩ D / A × 100            < 100  →  urgent fix for that menu
  phantom in cc = D − A       −100 each         phantom in footer = F − D   −1000 each
"""
import os, re, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(HERE, '..')); F = os.path.join(ROOT, 'script', 'file')
only = sys.argv[1] if len(sys.argv) > 1 else ''

# the harvester of mapgen (it reads menus.list and every source file once)
src = open(os.path.join(F, 'cmdmap', 'bashbasicsbyvk_mapgen')).read().split('# ── existing files')[0]
sys.argv = ['mapgen', '--dry', '--root', os.path.join(ROOT, 'script')]
g = {'__file__': os.path.join(F, 'cmdmap', 'bashbasicsbyvk_mapgen'), '__name__': 'mapgen_lib'}
exec(compile(src, 'mapgen', 'exec'), g)
harvest, sources = g['harvest'], g['sources']
def find_function(name):                       # the REAL definition: the loader stubs (loadmap) are one-liners with the same name
    best = (None, None)
    rx = re.compile(r'^' + re.escape(name) + r'\(\)\s*\{')
    for f, lines in sources.items():
        for i, l in enumerate(lines):
            if rx.match(l):
                j = i + 1
                while j < len(lines) and not lines[j].startswith('}'): j += 1
                if best[1] is None or len(lines[i:j + 1]) > len(best[1]): best = (f, lines[i:j + 1])
    return best

# D : declared
dump = subprocess.run(['bash', os.path.join(HERE, 'advert_dump.sh')], capture_output=True, text=True).stdout
D = {}; H = {}
for line in dump.splitlines():
    m, k, p, free, h = (line.split('\t') + ['', '', '', '', ''])[:5]
    D.setdefault(m, set()).add(k.lower()); H.setdefault(m, {})[k.lower()] = h

# the menus: map | function | kind
menus = []
for l in open(os.path.join(F, 'cmdmap', 'bashbasicsbyvk_menus.list')):
    if l.startswith('#') or '|' not in l: continue
    m, fn, kind, back = [x.strip() for x in l.split('|')[:4]]
    menus.append((m, fn, kind))

IGNORE = {'left', 'right', 'toggle'}                                 # key events of a list screen, not typed words
FUNCS = set()                                                     # every function defined in the project (a handler must exist)
for _f, _ls in sources.items():
    for _l in _ls:
        _m = re.match(r'^([A-Za-z_][A-Za-z0-9_.:-]*)\(\)\s*\{', _l)
        if _m: FUNCS.add(_m.group(1))
BUILTIN = {'-', '', 'bvk_main_exec'}
TOOLS = {'print', 'loadtime', 'cc', '?', '=', 'u', 'q'}            # the dispatcher takes these at every prompt
FOOT_CALL = re.compile(r'^\s*(_mc_footer\w*|_tm_footer|_ux_pk_footer|_mc_keyed)\b')

def footer_keys(lines):
    keys = set()
    for l in lines:
        if not FOOT_CALL.match(l): continue
        for it in re.findall(r'"([^"\s]+?)(?::[^"]*)?"', l.split(None, 1)[1] if ' ' in l.strip() else ''):
            if it in ('|',) or it.startswith('#') or it.startswith('$'): continue
            k = it.split('.')[0] if not it.startswith('.') else it
            m = re.match(r'^(.+-)N$', k)
            k = m.group(1) if m else k
            if k in ('N', 'Enter') or re.search(r'[0-9,]', k): continue
            keys.add(k.lower())
    return keys

ARM = g['ARM']
def tokens_of(pat):
    for tok in re.split(r'\|', pat):
        tok = tok.strip().strip("\"'")
        if not tok or "$" in tok or tok in ('*', '(*') or tok.startswith(('_', '[')) or re.fullmatch(r'[0-9]+', tok): continue
        tok = re.sub(r'\[[A-Za-z]{2}\]', lambda m: m.group(0)[1].lower(), tok)              # [eE]-*  ->  e-*
        pre = tok.endswith('*'); tok = tok.rstrip('*').rstrip('.')
        if tok and re.fullmatch(r'[A-Za-z.=-][A-Za-z0-9.=_-]*', tok): yield tok.lower() + ('-' if pre and not tok.endswith('-') and tok[-1:] != '.' and False else '')

ARM = g['ARM']
def loose_tokens(pat):
    for tok in re.split(r'\|', pat):
        tok = tok.strip().strip("\"'")
        if not tok or "$" in tok or tok in ('*', '(*') or re.fullmatch(r'[0-9]+', tok): continue
        tok = tok.rstrip('*').rstrip('.') if not tok.endswith('-*') else tok[:-1]
        if tok and re.fullmatch(r'[A-Za-z.=-][A-Za-z0-9.=_-]*', tok): yield tok.lower()

GLOBAL = set()                                                   # every case arm / =~ ^x- anywhere in the project: a handler may live in any helper file
for _f, _ls in sources.items():
    if _f.endswith('loadmap_stubs.sh'): continue
    for _l in _ls:
        _l = re.sub(r'\[([A-Za-z])([A-Za-z])\]', lambda m_: m_.group(1).lower() if m_.group(1).lower() == m_.group(2).lower() else m_.group(0), _l)
        _m = ARM.match(_l)
        if _m: GLOBAL.update(loose_tokens(_m.group(1)))
        for _r in re.findall(r'=~\s*\^\(?([A-Za-z]{1,3})-', _l): GLOBAL.add(_r.lower() + '-')

def accepted_of(m, fn, kind):
    if fn == '-': return None
    f, body = find_function(fn)
    if not body: return None
    # a loop hands words to helper functions in its own file: the whole file is searched, with [eE]- read as e-
    lines = [re.sub(r'\[([A-Za-z])([A-Za-z])\]', lambda m_: m_.group(1).lower() if m_.group(1).lower() == m_.group(2).lower() else m_.group(0), l) for l in sources.get(f, body)]
    A = set()                                                    # strict: the arms of `case "$…choice…"` — what coverage is measured against
    for k, kd in harvest(lines):
        if k.lower() in IGNORE: continue
        A.add(k.lower() + ('-' if kd == 'prefix' and not k.endswith('-') else ''))
    L = set(A)                                                   # loose: every case arm and every =~ ^x- in the file — a phantom needs NO arm anywhere
    for l in lines:
        mm = ARM.match(l)
        if mm: L.update(loose_tokens(mm.group(1)))
        for r in re.findall(r'=~\s*\^\(?([A-Za-z]{1,3})-', l): A.add(r.lower() + '-'); L.add(r.lower() + '-')
    return f, body, A, L

tot_bad = 0; rows_out = []
for m, fn, kind in menus:
    if only and only not in m: continue
    d = D.get(m, set())
    r = accepted_of(m, fn, kind)
    if r is None:
        rows_out.append((m, None, None, None, None, None)); continue
    f, body, A, L = r
    # the dispatcher accepts for a menu: tools + every wired / inherited key the resolver runs (it is in D by construction)
    Aall = L | GLOBAL | TOOLS
    cov_set = A & d
    cov = 100.0 * len(cov_set) / len(A) if A else 100.0
    ph_cc = sorted(d - Aall - {k for k in d if k in TOOLS})
    # inherited main words are accepted by the dispatcher itself: not phantoms
    main_words = D.get('main', set())
    ph_cc = [k for k in ph_cc if k not in main_words]
    fk = footer_keys(sources.get(f, []))
    ph_ft = sorted(k for k in fk - d - TOOLS if k not in ('u', 'q', 'z', 'rf', 'h', 'cc'))
    dead = sorted(k for k, h in H.get(m, {}).items() if h not in BUILTIN and h not in FUNCS and not h.startswith('_cm_'))   # declared with a handler that does not exist
    ph_cc = sorted(set(ph_cc) | set(dead))
    score = cov - 100 * len(ph_cc) - 1000 * len(ph_ft)
    rows_out.append((m, cov, ph_cc, ph_ft, sorted(A - d), score))
    if cov < 100 or ph_cc or ph_ft: tot_bad += 1

for m, cov, ph_cc, ph_ft, miss, score in rows_out:
    if cov is None: print('%-10s (no loop function to scan: a shared prompt, judged by its callers)' % m); continue
    print('%-10s coverage %5.1f   phantom cc %d   phantom footer %d   SCORE %.0f' % (m, cov, len(ph_cc), len(ph_ft), score))
    if miss: print('    loop handles but not declared (not in cc):', ' '.join(miss))
    if ph_cc: print('    declared (cc) but the loop does not handle:', ' '.join(ph_cc))
    if ph_ft: print('    footer prints but not declared:', ' '.join(ph_ft))
print('ALL OK (every menu scores 100)' if not tot_bad else '%d menu(s) below 100 — urgent fix' % tot_bad)
sys.exit(1 if tot_bad else 0)
