"""BLIND SPOTS — the two ways a footer can lie that the map-driven suites (footer, arms, advert) cannot see.
  blind:flag:<file>:<line>     a footer call is handed a bare flag (_mc_footer_std -b).  _mc_footer_std takes ONLY  -T ID  and  "key:Label"  items,
                               so anything else is printed as a footer item: that was the "-b" in the v- buffer footer (the flag belongs to _mc_select).
  blind:fn:<func>:<key>        a function that draws a footer and reads a typed key (a `case` arm) takes <key>, but its footer does not print it, and the function
                               owns no map (menus.list), so cc cannot list it either.  Register the menu in menus.list (mapgen) or print the key in its footer.
The arms / footer / advert suites only walk functions listed in cmdmap/bashbasicsbyvk_menus.list: a screen that is not listed is invisible to them."""
import os, re, sys, glob
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('blind')
reg = set()
for l in bvk.read(os.path.join(bvk.F, 'cmdmap', 'bashbasicsbyvk_menus.list')).splitlines():
    p = [x.strip() for x in l.split('|')]
    if len(p) > 1 and not l.lstrip().startswith('#') and p[1] != '-': reg.add(p[1])
FN = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{', re.M)
NAV = {'u', 'q', 'h', 'cc', '*', 'esac', 'y', 'n_', 'groups', 'flat'}
files = [f for f in glob.glob(os.path.join(bvk.F, '**', '*'), recursive=True) if os.path.isfile(f) and not f.endswith(('.c', '.h', '.go', '.py', '.js', '.md', '.txt', '.list', '.map', '.tpl', '.png'))]
for f in sorted(files):
    t = bvk.read(f)
    if '_mc_footer' not in t: continue
    for n, l in enumerate(t.splitlines(), 1):                       # 1. bare flags handed to the footer
        if l.lstrip().startswith('#'): continue
        m = re.search(r'\b_mc_footer_std\b(.*)', l)
        if not m: continue
        a = re.sub(r'"[^"]*"|\'[^\']*\'', '', m.group(1)); a = re.sub(r'-T\s+\S+', '', a); a = a.split('#')[0]
        R.check()
        if re.search(r'(^|\s)-[A-Za-z]\b', a): R.add('blind:flag:%s:%d' % (bvk.rel(f), n), 'footer call with a bare flag: %s' % l.strip()[:90])
    ms = list(FN.finditer(t))
    for i, m in enumerate(ms):                                      # 2. keys a loop reads that no footer / map advertises
        fn = m.group(1)
        if fn in reg or fn.startswith('_mc_'): continue
        body = t[m.end():(ms[i + 1].start() if i + 1 < len(ms) else len(t))]
        calls = re.findall(r'_mc_footer_std[^\n]*', body)
        if not calls or not re.search(r'\bcase\b', body) or '_mc_read' not in body: continue
        shown = set(k.lower() for c in calls for k in re.findall(r'"([A-Za-z.=-][A-Za-z0-9.=,-]*?):[^"]*"', c))
        for arm in re.findall(r'^\s*([a-zA-Z][a-zA-Z0-9_|.\-]*)\)', body, re.M):
            for k in arm.split('|'):
                k = k.lower(); R.check()
                if k in NAV or k in shown or re.search(r'\d', k): continue
                R.add('blind:fn:%s:%s' % (fn, k), '%s (%s) takes %r but its footer does not print it and it owns no map' % (fn, bvk.rel(f), k))
sys.exit(R.finish())
