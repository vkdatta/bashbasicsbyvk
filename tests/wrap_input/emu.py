"""Tiny terminal emulator + pty driver. Feeds a paste into the app's line editor on a NARROW screen and reports how many
screen rows hold the prompt (must be 1) and what the app returned.   python3 emu.py <repo-root> <editor> <cols> <text>"""
import os, pty, sys, time, select, struct, fcntl, termios, re, unicodedata
root, ed, cols, text = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
rows = 24
here = os.path.dirname(os.path.abspath(__file__))
pid, fd = pty.fork()
if pid == 0:
    os.environ['TERM'] = 'xterm-256color'; os.environ['LANG'] = 'C.UTF-8'; os.environ['LC_ALL'] = 'C.UTF-8'
    os.execvp('bash', ['bash', os.path.join(here, 'harness.sh'), root, ed])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
screen = [[' '] * cols for _ in range(rows)]; cy = 0; cx = 0; pend = False; tail = ''
def w(ch):
    return 0 if unicodedata.combining(ch) else (2 if unicodedata.east_asian_width(ch) in 'WF' else 1)
def lf():
    global cy
    if cy == rows - 1: screen.pop(0); screen.append([' '] * cols)
    else: cy += 1
def feed(s):
    global cy, cx, pend
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\x1b':
            m = re.match(r'\x1b\[([?0-9;]*)([A-Za-z])', s[i:])
            if m:
                p, k = m.group(1), m.group(2); i += m.end()
                n = int(p) if p.isdigit() else 1
                if k == 'A': cy = max(0, cy - n); pend = False
                elif k == 'B': cy = min(rows - 1, cy + n); pend = False
                elif k == 'C': cx = min(cols - 1, cx + n); pend = False
                elif k == 'D': cx = max(0, cx - n); pend = False
                elif k == 'K':
                    if p == '2': screen[cy] = [' '] * cols
                    else: screen[cy][cx:] = [' '] * (cols - cx)
                elif k == 'J':
                    screen[cy][cx:] = [' '] * (cols - cx)
                    for y in range(cy + 1, rows): screen[y] = [' '] * cols
                continue
            i += 1; continue
        if c == '\r': cx = 0; pend = False
        elif c == '\n': lf(); pend = False
        elif c in '\x07\x08': pass
        else:
            cw = w(c)
            if cw == 0: i += 1; continue
            if pend or cx + cw > cols: cx = 0; lf(); pend = False
            screen[cy][cx] = c
            if cw == 2 and cx + 1 < cols: screen[cy][cx + 1] = ''
            cx += cw
            if cx >= cols: cx = cols - 1; pend = True
        i += 1
def pump(t):
    global tail
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return False
            if not d: return False
            tail += d.decode('utf-8', 'replace'); feed(d.decode('utf-8', 'replace'))
    return True
pump(1.0)
for ch in text:                      # a paste: all characters arrive back to back
    os.write(fd, ch.encode()); pump(0.004)
pump(0.6)
mid = [''.join(r).rstrip() for r in screen]
os.write(fd, b'\r'); pump(1.0)
end = [''.join(r).rstrip() for r in screen]
prompt_rows = sum(1 for r in end if 'Paste link' in r or r.startswith('Select:') or 'Select: ' in r)
print('---- screen while typing (cols=%d) ----' % cols)
print('\n'.join(r for r in mid if r))
print('---- after Enter ----')
print('\n'.join(r for r in end if r))
print('PROMPT_ROWS=%d' % prompt_rows)
