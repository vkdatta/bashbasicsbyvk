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
def check(name, cond, a=None):
    """cond is a callable: the screen is polled until it holds (max 8 s, no guessed sleep), and it must STILL hold once the app is quiet
    (a hint that flashes and vanishes is a failure). On failure the screen is printed at once."""
    ok = False
    try:
        ok = a.wait(cond, 8) if a else bool(cond())
        if ok and a: a.settle(0.25); ok = bool(cond())
    except Exception: ok = False
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
    def top3(): return [l for l in a.text().split('\n') if l.strip()][:3]
    check('main header row 1 = lang | ⏰ n | 📣 n', lambda: len(top3()) >= 3 and '| ⏰' in top3()[0] and '| 📣' in top3()[0], a)
    check('main header has cd path then nav path', lambda: 'cd path:' in top3()[1] and 'nav path:' in top3()[2], a)
    cdp = top3()[1].split('cd path:')[1].strip()
    a.line('u')
    def after_up():
        L2 = [l for l in a.text().split('\n') if l.strip()]
        k = max(i for i, l in enumerate(L2) if 'cd path:' in l); t2 = L2[k:k + 2]
        return t2[0].split('cd path:')[-1].strip() == cdp and t2[1].split('nav path:')[-1].strip() == os.path.dirname(cdp)
    check('cd path stays where the shell is; nav path moves when you go up (u)', after_up, a)
    a.line('work')
    a.send('s'); check('main: typing s puts the suggestion right above Select:', lambda: bool(row_above_select(a, 's')) and 'Settings' in row_above_select(a, 's'), a)
    a.send('\x7f'); check('main: erasing the text clears the suggestion row', lambda: row_above_select(a, '') is not None and not row_above_select(a, '').strip(), a)
    a.send('h\r'); a.send('s'); check('Home: typing s shows the suggestion above Select:', lambda: bool(row_above_select(a, 's')) and 'Settings' in row_above_select(a, 's'), a)
    a.send('\x7f'); a.send('2'); check('Home: typing a row number says what Enter does', lambda: bool(row_above_select(a, '2')) and row_above_select(a, '2').startswith('Enter'), a)
    a.send('\x7f'); a.line('u'); a.line('s'); a.send('h'); check('Settings: typing h shows the suggestion above Select:', lambda: bool(row_above_select(a, 'h')) and 'Home' in row_above_select(a, 'h'), a)
    a.send('\x7f'); a.line('u'); a.line('fx'); a.send('s'); check('fx menu: typing s shows the suggestion above Select:', lambda: bool(row_above_select(a, 's')) and 'Settings' in row_above_select(a, 's'), a)
finally:
    a.close()
print('ALL OK' if not fails else 'FAILED: %d' % len(fails)); sys.exit(1 if fails else 0)
