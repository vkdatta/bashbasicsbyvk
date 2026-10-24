"""Real-app navigation test (pty + the tiny terminal emulator of tests/paste_input/vt.py).
  u  = back to the screen you CAME FROM (Home -> Links -> u = Home; Local Surf -> api -> u = Local Surf)
  q  = close to the MAIN LOOP (the file list), never leave the whole app (only q on the main loop does that)
usage: python3 nav_test.py [only-case-substring]"""
import os, pty, sys, time, select, fcntl, termios, struct, tempfile, shutil, signal
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp
COLS, ROWS = 100, 40
only = sys.argv[1] if len(sys.argv) > 1 else ''

class App(PtyApp):
    @staticmethod
    def fake_user(home):   # an active -auth profile (made up: no server is ever reached), so nf / sn / rbam / cs / api open
        import random, string
        def codes(n):
            seen = set()
            while len(seen) < n: seen.add(''.join(random.choice(string.ascii_letters + string.digits) for _ in range(16)))
            return '-'.join(seen)
        d = os.path.join(home, '.config', 'bashbasicsbyvk', 'auth'); os.makedirs(os.path.join(d, 'profiles'))
        pid = 'p_0123456789abcdef'
        open(os.path.join(d, 'active'), 'w').write(pid)
        open(os.path.join(d, 'profiles', pid), 'w').write('MAIL=test@example.com\nDISEPS=%s\nDINONS=%s\nAPIKEY=%s\nSEALKEY=%s\nCREATED=2026-10-21T00:00:00Z\n' % (
            codes(27), codes(29), 'k' * 40, 's' * 50))
    def __init__(self, user=True):
        def populate(home, work):
            for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
            if user: self.fake_user(home)
        super().__init__(root, COLS, ROWS, populate)

def on_main(a):  return a.alive and 'nav path:' in a.text().split('Select')[-2 if False else 0] or (a.alive and 'nav path:' in a.text())
def on_home(a):  return a.alive and 'Home' in a.text() and 'Local Surf' in a.text() and 'Cloud Surf' in a.text()
def last_screen(a):
    t = a.text(); i = max(t.rfind('nav path:'), t.rfind('Home\n'))
    return t

results = []
def case(name, steps, expect, why):
    if only and only not in name: return
    a = App(user=True)
    try:
        for s in steps: a.line(s) if s != '<wait>' else a.settle(0.5)         # each line returns when the app went quiet, never after a guessed time
        ok = a.wait(lambda: expect(a), 8)                                      # the expected screen must appear ...
        if ok: a.settle(0.4); ok = expect(a)                                   # ... and must still be the state once the app is quiet (a screen that flashes by is a failure)
        results.append(ok)
        print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '   [' + why + ']'))
        if not ok: print('   alive=%s\n   ' % a.alive + '\n   '.join(l for l in a.scr.lines() if l.strip())[-1500:])
    finally: a.close()

def title_rows(a):  return [l for l in a.scr.lines() if l.strip()]
def last_header(a):
    # the lowest header line on screen
    best = ''
    for l in a.scr.lines():
        if 'nav path:' in l: best = 'MAIN'
        elif l.strip().startswith('🏠 Home') or l.strip() == 'Home': best = 'HOME'
        elif 'LINKS' in l: best = 'LINKS'
    return best

# --- u goes back to where you came from
case('Local Surf > api > u  = Local Surf', ['api', 'u'], lambda a: a.alive and last_header(a) == 'MAIN', 'must return to the file list')
case('Home > Links > u  = Home', ['h', '10', 'u'], lambda a: a.alive and last_header(a) == 'HOME', 'must return to Home')
case('Home > Functions > u  = Home', ['h', '6', 'u'], lambda a: a.alive and last_header(a) == 'HOME', 'must return to Home')
# --- q closes to the main loop, never leaves the app
# (sn needs the server to open at all: offline it prints an error and returns, so it is not testable here)
for cmd in ('fx', 'sw', '.r', 'api', 'pn', 'bk', 'sv', 'rbam', 'nf', 'cs', '-u'):
    case('main > %s > q  = main loop (app still running)' % cmd, [cmd, 'q'], lambda a: a.alive and last_header(a) == 'MAIN', 'app exited or stayed in the menu')
for num, nm in (('6', 'Functions'), ('5', 'Switch'), ('7', 'Rules'), ('10', 'Links'), ('2', 'Cloud Surf')):
    case('Home > %s > q  = main loop (app still running)' % nm, ['h', num, 'q'], lambda a: a.alive and last_header(a) == 'MAIN', 'app exited or stayed in Home')
case('Home > q  = main loop', ['h', 'q'], lambda a: a.alive and last_header(a) == 'MAIN', 'must return to main loop')
case('Settings > q  = main loop', ['s', 'q'], lambda a: a.alive and last_header(a) == 'MAIN', 'must return to main loop')
case('main > q  exits the app', ['q'], lambda a: not a.alive, 'q on the main loop must exit')
print('ALL OK' if all(results) else 'FAILED'); sys.exit(0 if all(results) else 1)
