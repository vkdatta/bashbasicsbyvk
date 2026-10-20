"""Real-app UI test (pty + a tiny terminal emulator, vt.py): a pasted multi-line text is shown as multi-line, the left arrow
moves INSIDE the text (never onto the 'Select:' label), >2000 characters are refused with a notice.
tests/stresstest/input.txt is bare paste data. usage: python3 ui_test.py [cols]"""
import os, pty, sys, time, select, fcntl, termios, struct, tempfile, shutil, subprocess
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, here); from vt import Screen
cols = int(sys.argv[1]) if len(sys.argv) > 1 else 80
tmp = tempfile.mkdtemp(); binp = os.path.join(tmp, 'bin'); os.makedirs(binp)
for dp, dn, fn in os.walk(os.path.join(root, 'script')):
    if 'bvk-ls' in dp: continue
    for f in fn: os.symlink(os.path.join(dp, f), os.path.join(binp, f)) if not os.path.exists(os.path.join(binp, f)) else None
home = os.path.join(tmp, 'home'); work = os.path.join(home, 'work'); os.makedirs(work)
for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8', HOME=home, COLUMNS=str(cols), LINES='30', PATH=binp + ':' + os.environ['PATH'])
    os.chdir(work); os.execvp('bash', ['bash', os.path.join(binp, 'o')])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 30, cols, 0, 0))
scr = Screen(cols, 30)
def pump(t):
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 1 << 20)
            except OSError: return
            if d: scr.feed(d)
def send(b, t=0.5): os.write(fd, b); pump(t)
def paste(text): send(b'\x1b[200~' + text.encode() + b'\x1b[201~', 1.2)
ok = True
def check(name, cond, extra=''):
    global ok; ok &= bool(cond); print(('PASS ' if cond else 'FAIL ') + name + (' ' + extra if not cond else ''))
def rows(): return scr.lines()
def label_row():
    L = rows()
    for i in range(29, -1, -1):
        if L[i].startswith('Select:') or 'Select:' in L[i][:12]: return i
    return -1
pump(4)
src = open(os.path.join(root, 'tests', 'stresstest', 'input.txt'), encoding='utf-8').read()
lines = [l for l in src.split('\n') if l.strip()][:5]
text = '\n'.join(lines)[:380] + '\n'
paste(text)
L = rows(); i0 = label_row()
shown = [l for l in L[i0:i0 + 8] if l.strip()] if i0 >= 0 else []
check('multi-line paste is shown as several rows', len(shown) >= 4, repr(shown))
check('the lines keep their line breaks', shown and shown[0].startswith('Select: ' + lines[0][:20]), repr(shown[:2]))
r0, c0 = scr.cursor
check('cursor is at the end of the text (last row)', r0 > i0)
bad = 0
for k in range(120):
    send(b'\x1b[D', 0.04)
    r, c = scr.cursor
    if r == i0 and c < len('Select: '): bad += 1
check('120 x LEFT never enters the "Select:" label', bad == 0, f'{bad} times')
r, c = scr.cursor
check('LEFT walks up through the rows to the start of the text', r == i0 and c == len('Select: '), f'cursor={scr.cursor} label row={i0}')
send(b'\x1b[C', 0.2); check('RIGHT moves forward again', scr.cursor == (i0, len('Select: ') + 1), str(scr.cursor))
# a newline must not be an Enter: nothing was accepted yet (still on the same prompt)
check('no Enter was triggered by the line breaks', 'Invalid' not in ''.join(rows()))
send(b'\x15' if False else b'\x1b[F', 0.2)
# limit
for _ in range(60): send(b'\x7f', 0.01)
pump(0.5)
paste('y' * 2001)
L = rows(); check('2001 characters are refused with a notice', any('Too large' in l for l in L), '')
check('...and nothing was inserted', not any('yyyyyyyyyy' in l for l in L))
paste('z' * 1990); paste('w' * 20)
L = rows(); check('a paste that would pass 2000 in total is refused', any('Too large' in l for l in L))
send(b'\r', 1.5)
check('Enter accepts the text as ONE input (one "Invalid selection", no cascade)', ''.join(rows()).count('Invalid selection') <= 1)
shutil.rmtree(tmp, ignore_errors=True)
print('ALL OK' if ok else 'FAILED'); sys.exit(0 if ok else 1)
