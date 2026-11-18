"""cc / map / Enter must tell the SAME truth on the list screens (Settings, Home), which read keys themselves (_st_run).
A command the map wires as usable and cc lists must DO something when typed there; a blocked one must say so and do nothing.
usage: python3 cc_truth_test.py [only-substring]"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp
only = sys.argv[1] if len(sys.argv) > 1 else ''

class App(PtyApp):
    def __init__(self):
        def populate(home, work):
            for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
        super().__init__(root, 100, 40, populate)

def rows(a): return [l.strip() for l in a.scr.lines() if l.strip()]
# keys wired from maincommands in BOTH maps and runnable from a list screen. `clear` (hash -r) prints nothing by design: not listed.
RUN = ['h', 's', 'i', '-auth', 'health', 'disk', 'ram', 'lang']
BLOCKED = ['fx', 'sw', 'cd', 'kl', 'up-']      # act / danger keys: the screens have no arm for them, the map blocks them
fails = 0
def check(screen, opener, key, expect_change):
    global fails
    name = '%s > %s' % (screen, key)
    if only and only not in name: return
    a = App()
    try:
        a.line(opener); a.settle(0.5); before = rows(a)
        a.line(key); a.settle(0.8); after = rows(a)
        new = [l for l in after if l not in before]
        if expect_change: ok = bool(new)
        else: ok = any('not available here' in l for l in new)
        print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else ('   [typed key did nothing]' if expect_change else '   [blocked key gave no note]')))
        if not ok:
            fails += 1; print('   ' + '\n   '.join(after[-8:]))
    finally: a.close()
for screen, opener in (('Settings', 's'), ('Home', 'h')):
    for k in RUN: check(screen, opener, k, True)
    for k in BLOCKED: check(screen, opener, k, False)
print('ALL OK' if not fails else '%d FAILED' % fails); sys.exit(1 if fails else 0)
