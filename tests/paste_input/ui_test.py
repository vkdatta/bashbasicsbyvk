"""Real-app UI test (pty + a tiny terminal emulator, vt.py): a pasted multi-line text is shown as multi-line, the left arrow
moves INSIDE the text (never onto the 'Select:' label), >512 characters are refused with a notice.
tests/stresstest/input.txt is bare paste data. usage: python3 ui_test.py [cols]"""
import os, sys, shutil
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, here); from ptyapp import PtyApp          # the ONE pty driver (waits for what the app shows, no fixed sleeps)
cols = int(sys.argv[1]) if len(sys.argv) > 1 else 80
def populate(home, work):
    for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
a = PtyApp(root, cols, 30, populate, env={'BVK_BROWSER_TERM': None})
scr = a.scr
def send(b, t=0.5, **kw): return a.send(b, t, **kw)
def paste(text): a.send(b'\x1b[200~' + text.encode() + b'\x1b[201~', 3.0, quiet=0.4)
ok = True
def check(name, cond, extra=''):
    """cond may be a callable: polled until true (max 8 s), then it must still hold once the app is quiet"""
    global ok
    if callable(cond):
        v = a.wait(cond, 8)
        if v: a.settle(0.25); v = bool(cond())
        cond = v
    ok &= bool(cond); print(('PASS ' if cond else 'FAIL ') + name + (' ' + extra if not cond else ''))
def rows(): return scr.lines()
def label_row():
    L = rows()
    for i in range(29, -1, -1):
        if L[i].startswith('Select:') or 'Select:' in L[i][:12]: return i
    return -1
src = open(os.path.join(root, 'tests', 'stresstest', 'input.txt'), encoding='utf-8').read()
lines = [l for l in src.split('\n') if l.strip()][:5]
text = '\n'.join(lines)[:380] + '\n'
paste(text)
i0 = label_row()
shown = lambda: [l for l in rows()[i0:i0 + 8] if l.strip()] if i0 >= 0 else []
check('multi-line paste is shown as several rows', lambda: len(shown()) >= 4, repr(shown()))
check('the lines keep their line breaks', lambda: bool(shown()) and shown()[0].startswith('Select: ' + lines[0][:20]), repr(shown()[:2]))
check('cursor is at the end of the text (last row)', lambda: scr.cursor[0] > i0)
bad = 0
for k in range(120):
    send(b'\x1b[D', 0.08, quiet=0.015)
    r, c = scr.cursor
    if r == i0 and c < len('Select: '): bad += 1
check('120 x LEFT never enters the "Select:" label', bad == 0, f'{bad} times')
check('LEFT walks up through the rows to the start of the text', lambda: scr.cursor == (i0, len('Select: ')), f'cursor={scr.cursor} label row={i0}')
send(b'\x1b[C', 0.5); check('RIGHT moves forward again', lambda: scr.cursor == (i0, len('Select: ') + 1), str(scr.cursor))
# a newline must not be an Enter: nothing was accepted yet (still on the same prompt)
a.settle(0.3); check('no Enter was triggered by the line breaks', 'Invalid' not in ''.join(rows()))
send(b'\x1b[F', 0.3)
# limit
send(b'\x7f' * 60, 5.0, quiet=0.3)      # one write: 60 backspaces clear the text (no per-key assertion needed here)
a.settle(0.3)
paste("y" * 513)
check('513 characters are refused with a notice', lambda: any('Too large' in l for l in rows()), '')
check('...and nothing was inserted', lambda: not any('yyyyyyyyyy' in l for l in rows()))
paste("z" * 500); paste("w" * 20)
check('a paste that would pass 512 in total is refused', lambda: any('Too large' in l for l in rows()))
send(b'\r', 3.0)
a.wait(lambda: 'Invalid selection' in ''.join(rows()), 8); a.settle(0.4)           # the answer must appear, and nothing may follow it
check('Enter accepts the text as ONE input (one "Invalid selection", no cascade)', ''.join(rows()).count('Invalid selection') == 1)
a.close()
print('ALL OK' if ok else 'FAILED'); sys.exit(0 if ok else 1)
