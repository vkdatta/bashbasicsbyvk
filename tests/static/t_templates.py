"""TEMPLATES EVERYWHERE — a screen is drawn from a template (script/file/templates/*.sh.tpl, laid out once, placeholders defined once in bashbasicsbyvk_tpl_defs.sh).
Three rules, no exceptions list:
  1. every header / footer function a viewport screen is given (_vp_header_fn= · _vp_footer_fn= · _tm_viewport HDR FTR · _xui_screen X -> X_header / X_footer) reaches the processor
     (_tpl_section · _tpl_footer · _tpl_list_header · _tpl_build · _tpl_render · _tm_head) through the functions it calls: a screen never prints its own header or footer rows;
  2. nothing outside the chrome (menuchrome.sh) and the definer calls _mc_footer itself: a footer goes through _tpl_footer, _tm_footer or _mc_footer_std [-T ID];
  3. the prompt word is {footer_acceptor}: no code line types the literal  "Select: "  (a prompt reads ${_TPL_ACCEPTOR}; the definer is the one place that spells it)."""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('templates')
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
ROOT_CALL = re.compile(r'\b(_tpl_section|_tpl_footer|_tpl_list_header|_tpl_build|_tpl_render|_tm_head)\b')
TOK = re.compile(r'[A-Za-z_][A-Za-z0-9_.:-]*')
memo = {}
def reaches(fn, seen=()):
    if fn in memo: return memo[fn]
    if fn in seen or fn not in BODY: return False
    b = '\n'.join(l for l in BODY[fn].split('\n') if not l.lstrip().startswith('#'))
    ok = bool(ROOT_CALL.search(b)) or any(t != fn and t in BODY and reaches(t, seen + (fn,)) for t in set(TOK.findall(b)))
    if ok or not seen: memo[fn] = ok          # a "no" found inside a cycle only means "not through the functions already on the path": never cache it (the result depended on hash order)
    return ok
hooks = {}
for p in bvk.bash_files():
    if bvk.is_stub_file(p): continue
    for ln in bvk.read(p).split('\n'):
        if ln.lstrip().startswith('#'): continue
        for m in re.finditer(r'\b(_vp_header_fn|_vp_footer_fn)=([A-Za-z_]\w*)', ln): hooks.setdefault(m.group(2), bvk.rel(p))
        m = re.search(r'\b_tm_viewport\s+([A-Za-z_]\w*)\s+([A-Za-z_]\w*)', ln)
        if m: hooks.setdefault(m.group(1), bvk.rel(p)); hooks.setdefault(m.group(2), bvk.rel(p))
        m = re.search(r'^\s*_xui_screen\s+([a-z_]+)\s*$', ln)
        if m:
            for suf in ('_header', '_footer'):
                if m.group(1) + suf in BODY: hooks.setdefault(m.group(1) + suf, bvk.rel(p))
for fn, where in sorted(hooks.items()):
    R.check()
    if fn in BODY and not reaches(fn): R.add('templates:hook:%s' % fn, '%s (%s) draws its own rows: call a template (_tpl_section / _tpl_footer / _tpl_list_header / _tm_head)' % (fn, FILE[fn]))
EXEMPT = ('engine/ui/bashbasicsbyvk_menuchrome.sh', 'templates/bashbasicsbyvk_tpl_defs.sh', 'templates/bashbasicsbyvk_tpl.sh')
for p in bvk.bash_files():
    r = bvk.rel(p)
    if bvk.is_stub_file(p): continue
    for n, ln in enumerate(bvk.read(p).split('\n'), 1):
        if ln.lstrip().startswith('#'): continue
        code = re.sub(r'\s#\s.*$', '', ln)
        R.check(2)
        if r.replace('file/', '', 1) not in [e for e in EXEMPT] and re.search(r'(^|[;&|{(]\s*|\s)_mc_footer(\s+[^\s]|\s*$)', code) and not fre.match(ln):
            R.add('templates:footer:%s:%d' % (r, n), '%s:%d calls _mc_footer itself: use _tpl_footer ID items / _tm_footer / _mc_footer_std -T ID' % (r, n))
        if r.endswith('tpl_defs.sh'): continue
        if re.search(r'"(   )?Select: "', code):
            R.add('templates:select:%s:%d' % (r, n), '%s:%d types the prompt word: read ${_TPL_ACCEPTOR} (the definer spells it once)' % (r, n))
sys.exit(R.finish())
