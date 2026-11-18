"""FOOTER TRUTH — the words a screen's footer advertises must be words its map accepts AND words cc lists.
The footer strings are read statically from the screen's own file ("key:Label" items of _mc_footer / _mc_footer_std / _tm_footer / _mc_footer_register);
what the map answers and what cc lists come from the intent dump (the real resolver).   Catches:  footer shows, cc doesn't · footer shows a word the screen refuses · renamed command still in the footer."""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('footer')
maps_p = bvk.parse_maps(); menus = [dict(map=m, func=v['head'].get('func', '-')) for m, v in sorted(maps_p.items())]
rows = bvk.dump_all(sorted(maps_p), {m: v['file'] for m, v in maps_p.items()})
act = {}; cc = {}
for r in rows:
    if r[0] == 'R': act[(r[1], r[2], r[3])] = r[4]
    elif r[0] == 'C': cc.setdefault((r[1], r[2]), set()).add(r[3])
funcs = bvk.defined_functions()
ITEM = re.compile(r'"([A-Za-z.=-][A-Za-z0-9.=,-]*?):[^"]*"')
CALL = re.compile(r'_(?:mc_footer|mc_footer_std|tm_footer|mc_footer_register)\b|\b_f(?:\+)?=\(|\b_f\[')
def keys_of(text):
    out = set()
    for l in text.splitlines():
        if l.lstrip().startswith('#') or not CALL.search(l): continue
        for k in ITEM.findall(l):
            k = re.sub(r'\.[a-z]+$', '', k)            # u.up -> u
            k = re.sub(r'N$', '', k)                   # r-N -> r-
            if k in ('N', '') or re.search(r'\d', k) or k.startswith('#'): continue
            out.add(k)
    return out
by_file = {}
for m in menus:                      # the screen's own file: its @func, or (xui_* sub-maps) the file that defines <name>_footer
    cands = funcs.get(m['func'], [])[:1] if m['func'] not in ('-', '') else []
    if not cands and m['map'].startswith('xui_'): cands = (funcs.get(m['map'][4:] + '_footer') or funcs.get(m['map'][4:] + '_menu_footer') or [])[:1]
    for f in cands: by_file.setdefault(f, []).append(m['map'])
for f, ms in sorted(by_file.items()):
    for k in sorted(keys_of(bvk.read(f))):
        R.check(); kl = k.lower()
        ok_any = False; best = None
        for m in ms:
            a = act.get((m, 'menu', kl)) or act.get((m, 'text', kl))
            if a in ('run', 'local', 'back') and kl in cc.get((m, 'menu'), set()) | cc.get((m, 'text'), set()): ok_any = True
            elif a in ('run', 'local', 'back'): best = (m, 'accepted, but cc does not list it', 'footer-cc')
            elif a in ('block', 'none', None): ok_any = True   # BY DESIGN: a key the footer prints is the prompt's own at run time (cmdmap _MC_UNDER_FOOTER -> _CM_LOCAL), it beats a block() in the map
            else: best = best or (m, 'the map answers %s' % a, 'footer')
        if not ok_any and best: R.add('%s:%s:%s' % (best[2], best[0], k), 'footer of %s advertises %r, but %s' % (bvk.rel(f), k, best[1]))
sys.exit(R.finish())
