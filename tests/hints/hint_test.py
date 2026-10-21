"""Suggestion-row guard (real app in a pty + tests/paste_input/vt.py).  python3 tests/hints/hint_test.py
Every screen with a typed "Select:" prompt must show the live suggestion on the row DIRECTLY ABOVE "Select:":
  main list · Home · Settings · a loop menu (fx).  And the main header is   lang | ⏰ n | 📣 n  /  cd path  /  nav path.
A new menu that draws its own screen (like _st_run does) must call _st_hint_text / _cm_hint, or this test fails."""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
nav = os.path.join(root, 'tests', 'nav_back')
sys.argv = ['x', '__none__']; __file__ = os.path.join(nav, 'nav_test.py')
sys.path.insert(0, nav)
exec(open(__file__).read().split('results = []')[0])
fails = []
def check(name, ok, a=None):
    print(('PASS ' if ok else 'FAIL ') + name)
    if not ok:
        fails.append(name)
        if a: print('   ' + '\n   '.join(l for l in a.scr.lines() if l.strip())[-900:])
def row_above_select(a, typed):
    L = [l.rstrip() for l in a.scr.lines()]
    idx = [i for i, l in enumerate(L) if l == ('Select: ' + typed).rstrip()]
    return L[idx[-1] - 1] if idx and idx[-1] > 0 else None

a = App(user=True)
try:
    t = a.text().split('\n')
    top = [l for l in t if l.strip()][:3]
    check('main header row 1 = lang | ⏰ n | 📣 n', len(top) >= 3 and '| ⏰' in top[0] and '| 📣' in top[0], a)
    check('main header has cd path then nav path', 'cd path:' in top[1] and 'nav path:' in top[2], a)
    a.send('s', 0.8); r = row_above_select(a, 's')
    check('main: typing s puts the suggestion right above Select:', bool(r) and 'Settings' in r, a)
    a.send('\x7f', 0.6); r = row_above_select(a, '')
    check('main: erasing the text clears the suggestion row', r is not None and not r.strip(), a)
    a.send('h\r', 1.8); a.send('s', 0.8); r = row_above_select(a, 's')
    check('Home: typing s shows the suggestion above Select:', bool(r) and 'Settings' in r, a)
    a.send('\x7f', 0.3); a.send('2', 0.8); r = row_above_select(a, '2')
    check('Home: typing a row number says what Enter does', bool(r) and r.startswith('Enter'), a)
    a.send('\x7f', 0.3); a.line('u', 1.2); a.line('s', 1.8); a.send('h', 0.8); r = row_above_select(a, 'h')
    check('Settings: typing h shows the suggestion above Select:', bool(r) and 'Home' in r, a)
    a.send('\x7f', 0.3); a.line('u', 1.2); a.line('fx', 2.2); a.send('s', 0.8); r = row_above_select(a, 's')
    check('fx menu: typing s shows the suggestion above Select:', bool(r) and 'Settings' in r, a)
finally:
    a.close()
print('ALL OK' if not fails else 'FAILED: %d' % len(fails)); sys.exit(1 if fails else 0)
