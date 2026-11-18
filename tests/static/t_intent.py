"""INTENT MATRIX — the app's input classifier, judged on every map x both modes x ~100 words, by the REAL _cm_resolve / _cm_hint / _cc_collect.
No terminal.  One bash process per map (parallel), cached by a hash of everything the answer depends on.   Replaces: cc_truth, cc_footer (2), cheatcode parts 1+2,
cc_audit, cmd_drift section 3, advert_pty / advert_static (the accepted-vs-advertised score).
The three input kinds of a menu:   command · choice (1  1,3  1-5  a  a-2) · raw text.   Invariants:
  I1 the answer is one of none/local/run/back/block
  I2 a choice or garbage (numbers, ranges, empty, blanks, emoji, control bytes, 300 chars) is NEVER a command, in any map, in either mode
  I3 case does not matter:   K behaves like k
  I4 an exact-kind word followed by an argument is not that command (sw1 is not sw)
  I5 a prefix-kind word with an argument behaves like the bare prefix (c-1,3 like c-)
  I6 u typed into a question is always "back" (the guide's one promise), unless the map blocks it explicitly
  I7 the live suggestion never offers a word that Enter would reject   (cmd_drift section 3)
  I8 cc lists only words the prompt accepts (no phantom in cc)"""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('intent')
maps_p = bvk.parse_maps(); maps = sorted(maps_p); rows = bvk.dump_all(maps, {m: v['file'] for m, v in maps_p.items()})
res = {}; hints = []; cc = []
for r in rows:
    if r[0] == 'R': res[(r[1], r[2], r[3])] = dict(act=r[4], key=r[5], handler=r[6], cls=r[7], impl=r[8]) if len(r) >= 9 else dict(act=r[4], key='', handler='', cls='', impl='0')
    elif r[0] == 'H': hints.append(r[1:])
    elif r[0] == 'C': cc.append(r[1:])
ACTS = {'none', 'local', 'run', 'back', 'block'}
NEVER_CMD = ['', ' ', 'zzz', '1', '99999', '1,3', '1-5', '-1', '1,,2', '3-1', '<TAB>', '\x01', 'é', '😀', 'x' * 300]
kinds = {}
for (m, md, w), v in res.items(): pass
# the kind of a key, from the wiring (needed for I4 / I5)
defs, _ = bvk.parse_cmd_defs()
def kind_of(m, key):
    for k, t in maps_p[m]['wires']:
        if k.lower() == key and isinstance(t, tuple): return defs.get((t[1], t[0]), {}).get('kind')
    d = defs.get(('bashbasicsbyvk_maincommands.sh', key)); return d['kind'] if d else None

for (m, md, w), v in sorted(res.items()):
    R.check()
    if v['act'] not in ACTS: R.add('I1:%s:%s:%r' % (m, md, w), 'unknown answer %r' % v['act']); continue
    if w in NEVER_CMD and v['act'] != 'none': R.add('I2:%s:%s:%r' % (m, md, w[:12]), 'a choice / garbage input %r is taken as a command (%s -> %s)' % (w[:12], v['key'], v['act']))
    if len(w) > 1 and w.lower() != w and w.isascii():
        lo = res.get((m, md, w.lower()))
        if lo and lo['act'] != v['act']: R.add('I3:%s:%s:%s' % (m, md, w), 'upper case answers %s, lower case %s' % (v['act'], lo['act']))
for m in maps:
    for md in ('menu', 'text'):
        for (mm, mdd, w), v in list(res.items()):
            if mm != m or mdd != md: continue
            for suffix, want in (('1', None), ('1,3', None)):
                if not w.endswith(suffix) or w == suffix: continue
                base = w[:-len(suffix)]; b = res.get((m, md, base))
                if not b or b['key'] != base or base.endswith(('1', '3')): continue
                kd = kind_of(m, base); R.check()
                if kd == 'exact' and v['key'] == base and v['act'] in ('run', 'local'):
                    R.add('I4:%s:%s:%s' % (m, md, w), 'exact word %s followed by an argument is taken as the command' % base)
                if kd == 'prefix' and base.endswith('-') and v['act'] != b['act']:
                    R.add('I5:%s:%s:%s' % (m, md, w), 'prefix %s answers %s, with an argument %s' % (base, b['act'], v['act']))
        u = res.get((m, 'text', 'u'))
        if md == 'text' and u:
            R.check()
            if u['act'] not in ('back', 'block'): R.add('I6:%s:u' % m, 'u inside a question answers %s (must be back)' % u['act'])
for m, md, pre, h in hints:
    R.check(); lst = ''
    if 'could become: ' in h: lst = h.split('could become: ', 1)[1]
    elif '(also: ' in h: lst = h.split('(also: ', 1)[1].rsplit(')', 1)[0]
    for c in [x.strip() for x in lst.split(',') if x.strip()]:
        v = res.get((m, md, c))
        if v is None: continue                      # a word outside the dumped set is not judged
        if v['act'] not in ('run', 'local', 'back'): R.add('I7:%s:%s:%s>%s' % (m, md, pre, c), 'typing %r suggests %r, but Enter answers %s' % (pre, c, v['act']))
for m, md, k, act in cc:
    R.check()
    if act not in ('run', 'local', 'back'): R.add('I8:%s:%s:%s' % (m, md, k), 'cc lists %r, but the prompt answers %s (phantom in cc)' % (k, act))
sys.exit(R.finish())
