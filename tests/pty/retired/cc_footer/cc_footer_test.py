"""Two truths the earlier cc / suggestion fixes never checked, on the REAL app in a pty:
  (1) a suggestion is drawn ONCE (Settings, Home and the cc list used to paint it twice from 100 columns up);
  (2) cc lists every key the screen's footer prints (the review screen's  c) Confirm  x) Remove, the source picker's  v) z) ).
usage: python3 cc_footer_test.py [only-substring]"""
import os, sys, re
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp
only = sys.argv[1] if len(sys.argv) > 1 else ''

class App(PtyApp):
    def __init__(self, cols=100, rows=40):
        def populate(home, work):
            for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
        super().__init__(root, cols, rows, populate)

def rows(a): return [l.rstrip() for l in a.scr.lines() if l.strip()]
fails = 0
def report(name, ok, why='', a=None):
    global fails
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '   [' + why + ']'))
    if not ok:
        fails += 1
        if a: print('   ' + '\n   '.join(rows(a)[-10:]))

def run(name, fn):
    if only and only not in name: return
    a = None
    try: fn(name)
    except Exception as e: report(name, False, 'exception %r' % e)

# ---- (1) one suggestion row, at every width (the second painter only showed from 100 columns up)
def once(opener, cols):
    def t(name):
        a = App(cols)
        try:
            for o in opener: a.line(o); a.settle(0.8)
            a.send('k'); a.settle(0.8)
            n = sum('could become' in l for l in rows(a))
            report(name, n == 1, 'suggestion drawn %d times' % n, a)
        finally: a.close()
    return t
for cols in (80, 100, 140):
    for label, opener in (('Settings', ['s']), ('Home', ['h']), ('cc list', ['cc']), ('cc inside Settings', ['s', 'cc'])):
        run('one suggestion: %s @%d cols' % (label, cols), once(opener, cols))

# ---- (2) cc lists the footer's own keys
def cc_has(path, footer_re, want):
    def t(name):
        a = App()
        try:
            a.line('t'); a.settle(1.0)
            for p in path: a.line(p); a.settle(1.0)
            foot = [l for l in rows(a) if re.search(footer_re, l)]
            if not foot: return report(name, False, 'footer not found on screen', a)
            a.line('cc'); a.settle(1.2)
            keys = set(re.findall(r'^\s*\d+\)\s+(\S+)', '\n'.join(rows(a)), re.M))
            miss = [k for k in want if k not in keys]
            report(name, not miss, 'cc does not list the footer keys %s (lists %s)' % (miss, sorted(keys)), a)
        finally: a.close()
    return t
run('cc lists review footer keys (c x)', cc_has(['1', '1', 'v'], r'c\) Confirm', ['c', 'x']))
run('cc lists source picker footer keys (v z)', cc_has(['1'], r'v\) View selections', ['v', 'z']))
print('ALL OK' if not fails else '%d FAILED' % fails); sys.exit(1 if fails else 0)
