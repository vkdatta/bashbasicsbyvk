"""STRUCTURE of the command map, read statically (no bash, no app).  Replaces: cmd_docs/adf parts, `o --map-lint`, parts of cmd_drift and menu_templates.
Checks: menus.list <-> .map heads · every wire points at a real cmd_def · every handler is a defined function · duplicate ids / keys ·
every main command is wired (or blocked) explicitly in every map · duplicate concepts (fs / forceshow) · ghost blocked words · loop-only commands no arm handles."""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('structure')
menus = bvk.parse_menus_list(); defs, dups = bvk.parse_cmd_defs(); maps = bvk.parse_maps(); funcs = bvk.defined_functions()
MAIN = 'bashbasicsbyvk_maincommands.sh'

# S1  menus.list <-> the .map heads
for m in menus:
    R.check(); mp = maps.get(m['map'])
    if not mp: R.add('menus:%s:nomap' % m['map'], 'menus.list names map %r but no .map exists' % m['map']); continue
    h = mp['head']
    if h.get('menu') != m['map']: R.add('menus:%s:@menu' % m['map'], '@menu is %r' % h.get('menu'))
    if m['func'] != '-' and h.get('func') != m['func']: R.add('menus:%s:@func' % m['map'], 'menus.list says %s, the map says %s' % (m['func'], h.get('func')))
    if m['func'] != '-' and m['func'] not in funcs: R.add('menus:%s:nofunc' % m['map'], 'owning function %s is not defined anywhere' % m['func'])
    if h.get('kind') != m['kind']: R.add('menus:%s:@kind' % m['map'], 'menus.list says %s, the map says %s' % (m['kind'], h.get('kind')))
    if h.get('back') != m['back']: R.add('menus:%s:@back' % m['map'], 'menus.list says %s, the map says %s' % (m['back'], h.get('back')))
listed = {m['map'] for m in menus}
for name in sorted(maps):
    R.check()
    if name not in listed and maps[name]['head'].get('parent') in listed: continue   # BY DESIGN: hand-written xui_* sub-map, inherits from its @parent (cmdmap guide)
    if name not in listed: R.add('menus:%s:unlisted' % name, 'map exists but is not in menus.list (hand-written or orphan)')

# S2  every wire resolves to a real cmd_def
for name, mp in sorted(maps.items()):
    seen = {}
    for key, t in mp['wires']:
        R.check()
        if key.lower() in seen and seen[key.lower()] != t: R.add('dupkey:%s:%s' % (name, key), 'wired twice with different targets')
        seen[key.lower()] = t
        if isinstance(t, tuple):
            ident, fl = t
            if not os.path.exists(os.path.join(bvk.CMAP, name if False else '', fl)) and not any(os.path.exists(os.path.join(bvk.CMAP, d, fl)) for d in os.listdir(bvk.CMAP) if os.path.isdir(os.path.join(bvk.CMAP, d))):
                R.add('badwire:%s:%s' % (name, key), 'wired from %s, which does not exist' % fl)
            elif (fl, ident) not in defs: R.add('badwire:%s:%s' % (name, key), 'no cmd_def %s in %s' % (ident, fl))

# S3  handlers exist;  duplicate ids
for k in dups: R.add('dupdef:%s:%s' % k, 'cmd_def declared twice in one file')
for (fl, ident), d in sorted(defs.items()):
    R.check(); h = d['handler']
    if h not in ('-', 'back') and h not in funcs: R.add('nohandler:%s:%s' % (fl, ident), 'handler %s is not a defined function' % h)

# S4  every main command is wired (or blocked) explicitly in every map   (what `o --map-lint` lists)
main_ids = sorted(i for (f, i) in defs if f == MAIN)
for name, mp in sorted(maps.items()):
    if name == 'main' or name not in listed: continue      # unlisted maps are the small hand-written xui_* sub-maps: they inherit by design (reported once as menus:<m>:unlisted)
    wired = {k.lower() for k, _ in mp['wires']}
    for i in main_ids:
        R.check()
        if i.lower() not in wired: R.add('gap:%s:%s' % (name, i), 'main command %s is neither wired nor blocked here (inherited silently)' % i)

# S5  duplicate concepts: two main ids with the same description (a rename that added instead of renamed)
by = {}
for (f, i), d in defs.items():
    if f == MAIN and d['desc']: by.setdefault(d['desc'].lower(), []).append(i)
for desc, ids in sorted(by.items()):
    R.check()
    if len(ids) > 1: R.add('dupconcept:%s' % '+'.join(sorted(ids)), 'one description for %d ids: %r' % (len(ids), desc[:60]))
#     a menu that re-defines a main command with the same description (a stale copy)
for (f, i), d in sorted(defs.items()):
    if f == MAIN: continue
    md = defs.get((MAIN, i)); R.check()
    if md and all(md[k] == d[k] for k in ('kind', 'handler', 'cls', 'desc', 'ex')): R.add('shadow:%s:%s' % (f, i), 'is an exact copy of main command %s (delete it, the main one is inherited)' % i)

# S5b vocabulary: one id, different words in different menus (owner decision: unify, or rename one id)
_byid = {}
for (f, i), d in defs.items(): _byid.setdefault(i, {}).setdefault(d['desc'], []).append(f)
for i, ds in sorted(_byid.items()):
    R.check()
    if len(ds) > 1: R.add('labels:%s' % i, '%d different descriptions: %s' % (len(ds), ' | '.join(repr(k[:34]) for k in sorted(ds))))

# S6  ghosts: blocked in many maps, defined nowhere
defined_keys = {i.lower() for (_, i) in defs}
blocked = {}
for name, mp in maps.items():
    for k, t in mp['wires']:
        if t == 'block': blocked.setdefault(k.lower(), set()).add(name)
for k, ms in sorted(blocked.items()):
    R.check()
    if k not in defined_keys: R.add('ghost:%s' % k, 'blocked in %d maps but no cmd_def defines it (a removed / renamed command)' % len(ms))

# S7  loop-only commands (handler "-") that no case arm / literal anywhere handles
arm_tok = set(); lit = set()
CASE_ARM = re.compile(r'^\s*\(?\s*([^\s()#;][^()]*?)\)\s*(?:;;|[:{a-zA-Z_"\'$\[(!]|$)')
for p in bvk.bash_files():
    if '/cmdmap/' in p: continue
    t = bvk.read(p)
    for l in t.splitlines():
        m = CASE_ARM.match(l)
        if m:
            pat = re.sub(r'\[([A-Za-z])([A-Za-z])\]', lambda x: x.group(1) if x.group(1).lower() == x.group(2).lower() else x.group(0), m.group(1))
            for tok in pat.split('|'):
                tok = tok.strip().strip('"\'').rstrip('*').lower()
                if tok: arm_tok.add(tok)
    for tok in re.findall(r'["\']([A-Za-z.=-][A-Za-z0-9.=_-]{0,12})["\']', t): lit.add(tok.lower())
    for tok in re.findall(r'=~\s*\^\(?([A-Za-z]{1,3}-)', t): arm_tok.add(tok.lower())
for (f, i), d in sorted(defs.items()):
    if d['handler'] != '-' : continue
    R.check(); k = i.lower()
    if k not in arm_tok and k not in lit and k.rstrip('-') + '-' not in arm_tok: R.add('deadlocal:%s:%s' % (f, i), 'declared as handled by its loop (handler -), but no case arm or literal anywhere mentions it')
sys.exit(R.finish())
