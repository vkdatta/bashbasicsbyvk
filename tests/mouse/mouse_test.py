"""Real-app mouse / touch test (pty + the tiny terminal emulator of tests/paste_input/vt.py, which here also ANSWERS the cursor-position
query ESC[6n the way a real terminal does).  Clicks are sent as SGR mouse reports (ESC[<0;col;row M / m), exactly what a terminal
(or a touch terminal such as Termux) sends once the app has asked for them with ESC[?1000h ESC[?1006h.
  click an item          -> its number is typed in the prompt, nothing opens yet
  Enter after that       -> opens it
  double click           -> opens it at once (no Enter)
  two clicks, 2 items    -> NOT a double click
  slow second click      -> NOT a double click
  click on ▲ / ▼         -> page up / down
  wheel                  -> scrolls
  click on non-list row  -> nothing
  reports are OFF whenever no list waits for a key (no garbage in a plain `read`), BVK_MOUSE=0 / mouse_mode=off never turns them on
usage: python3 mouse_test.py [only-case-substring]"""
import os, pty, sys, time, select, fcntl, termios, struct, tempfile, shutil, signal, re
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from vt import Screen
COLS, ROWS = 100, 30
only = sys.argv[1] if len(sys.argv) > 1 else ''

class App:
    def __init__(self, nfiles=60, env=None, settings=None, answer_dsr=True):
        self.tmp = tempfile.mkdtemp(); binp = os.path.join(self.tmp, 'bin'); os.makedirs(binp)
        for dp, dn, fn in os.walk(os.path.join(root, 'script')):
            if 'bvk-ls' in dp: continue
            for f in fn:
                if not os.path.exists(os.path.join(binp, f)): os.symlink(os.path.join(dp, f), os.path.join(binp, f))
        home = os.path.join(self.tmp, 'home'); work = os.path.join(home, 'work'); os.makedirs(work)
        self.work = work
        for i in range(1, nfiles + 1):         # folders sort first: items 1-6 are dir010..dir060, the files are items 7...
            if i % 10 == 0: os.makedirs(os.path.join(work, 'dir%03d' % i))
            else: open(os.path.join(work, 'file%03d.txt' % i), 'w').write('x')
        if settings:                             # a settings file (it is parsed as data: key=value lines)
            cfg = os.path.join(home, '.config', 'bashbasicsbyvk'); os.makedirs(cfg, exist_ok=True)
            open(os.path.join(cfg, 'config'), 'w').write(settings)
        self.answer_dsr = answer_dsr; self.raw = b''
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            e = dict(TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8', HOME=home, COLUMNS=str(COLS), LINES=str(ROWS),
                     PATH=binp + ':' + os.environ['PATH'], BVK_BROWSER_TERM='0'); e.update(env or {})
            os.environ.update(e); os.chdir(work); os.execvp('bash', ['bash', os.path.join(binp, 'o')])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLS, 0, 0))
        self.scr = Screen(COLS, ROWS); self.alive = True; self.pump(4)
    def pump(self, t):
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.03)
            if r:
                try: d = os.read(self.fd, 1 << 20)
                except OSError: self.alive = False; return
                if not d: self.alive = False; return
                self.raw += d; self.scr.feed(d)
                if self.answer_dsr and b'\x1b[6n' in d:                          # the terminal answers a cursor-position query
                    row, col = self.scr.cursor
                    try: os.write(self.fd, b'\x1b[%d;%dR' % (row + 1, col + 1))
                    except OSError: pass
        try:
            p, _ = os.waitpid(self.pid, os.WNOHANG)
            if p: self.alive = False
        except ChildProcessError: self.alive = False
    def send(self, s, t=0.5):
        if isinstance(s, str): s = s.encode()
        try: os.write(self.fd, s)
        except OSError: self.alive = False; return
        self.pump(t)
    def lines(self): return self.scr.lines()
    def text(self): return '\n'.join(self.lines())
    def row_of(self, pat):                       # 1-based screen row of the first line matching the regex (searching from the bottom)
        L = self.lines()
        for i in range(len(L) - 1, -1, -1):
            if re.search(pat, L[i]): return i + 1
        return None
    def prompt(self):                            # text after "Select:" on the prompt row
        for l in reversed(self.lines()):
            if 'Select:' in l: return l.split('Select:', 1)[1].strip()
        return None
    def click(self, row, col=10, t=0.35, release=True):
        self.send(b'\x1b[<0;%d;%dM' % (col, row), t)
        if release: self.send(b'\x1b[<0;%d;%dm' % (col, row), 0.05)
    def wheel(self, up, row=10, t=0.35): self.send(b'\x1b[<%d;10;%dM' % (64 if up else 65, row), t)
    def close(self):
        try: os.kill(self.pid, signal.SIGKILL); os.waitpid(self.pid, 0)
        except Exception: pass
        shutil.rmtree(self.tmp, ignore_errors=True)

results = []
def case(name, fn, **kw):
    if only and only not in name: return
    a = App(**kw)
    try:
        ok, why = fn(a); results.append(ok)
        print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '   [' + why + ']'))
        if not ok: print('   prompt=%r alive=%s\n   ' % (a.prompt(), a.alive) + '\n   '.join(l for l in a.lines() if l.strip())[-1800:])
    finally: a.close()

def opened(a, d):                                # the header shows the folder we are in
    return a.alive and any(l.strip().endswith('/' + d) and 'nav path' in l for l in a.lines())

def item_row(a, n):                              # the screen row of list item n (rows look like  " 23. name" / " 23) name")
    return a.row_of(r'^\s*%d\)\s' % n)

def t_enable(a):
    return (b'\x1b[?1000h' in a.raw and b'\x1b[?1006h' in a.raw, 'the list prompt must switch mouse reports on')
case('mouse reports are switched on while the list waits', t_enable)

def t_click(a):
    r = item_row(a, 5)
    if not r: return False, 'item 5 is not on screen'
    a.click(r)
    return a.prompt() == '5' and a.alive, 'prompt is %r after clicking item 5 (nothing may open yet)' % a.prompt()
case('click an item -> its number is in the prompt', t_click)

def t_click_enter(a):
    r = item_row(a, 1)                            # item 1 is the folder dir010
    a.click(r); before = a.text(); a.send(b'\r', 1.5)
    return opened(a, 'dir010') and 'dir010' in before.split('Select:')[-1] + 'dir010' , 'Enter after the click must open item 1'
case('click an item, then Enter -> opens it', t_click_enter)

def t_double(a):
    r = item_row(a, 1)
    a.click(r, t=0.05); a.click(r, t=1.5)
    return opened(a, 'dir010'), 'a double click must open item 1 without Enter'
case('double click -> opens at once (no Enter)', t_double)

def t_two_items(a):
    r1, r2 = item_row(a, 1), item_row(a, 2)
    a.click(r1, t=0.05); a.click(r2, t=0.6)
    return a.prompt() == '2' and a.alive and not opened(a, 'dir010') and not opened(a, 'dir020'), 'two different items quickly: select the 2nd only, open nothing (prompt=%r)' % a.prompt()
case('two clicks on two items is not a double click', t_two_items)

def t_slow(a):
    r = item_row(a, 1)
    a.click(r, t=0.9); a.click(r, t=0.6)
    return a.prompt() == '1' and a.alive and not opened(a, 'dir010'), 'two slow clicks must only select (prompt=%r)' % a.prompt()
case('two slow clicks is not a double click', t_slow, env={'BVK_DBLCLICK_MS': '500'})

def t_below(a):
    n = a.row_of(r'more below')
    if not n: return False, 'no "more below" indicator on screen (list too short?)'
    before = a.prompt(); a.click(n)
    return a.prompt() not in (None, '', before) and int(a.prompt()) >= 10, 'click on ▼ must page down (prompt=%r)' % a.prompt()
case('click on ▼ more below -> page down', t_below)

def t_wheel(a):
    a.wheel(False); a.wheel(False)
    p1 = a.prompt(); a.wheel(True)
    p2 = a.prompt()
    return p1 and p2 and int(p1) == 6 and int(p2) == 3 or False, 'wheel down x2 then up x1 should give 6 then 3 (got %r, %r)' % (p1, p2)
case('wheel scrolls the list (3 items a notch, clamped)', t_wheel)

def t_wheel_top(a):
    a.wheel(True)
    return a.prompt() in ('1',) and a.alive, 'wheel up at the top must clamp on item 1, not wrap (prompt=%r)' % a.prompt()
case('wheel up at the top stays at item 1', t_wheel_top)

def t_outside(a):
    before = a.prompt(); a.click(2); a.click(ROWS)    # header row / the prompt row itself
    return a.prompt() == before and a.alive, 'a click outside the list changes nothing'
case('click outside the list does nothing', t_outside)

def t_off_env(a):
    r = item_row(a, 5); a.click(r)
    return b'\x1b[?1000h' not in a.raw and a.prompt() in (None, '') and a.alive, 'BVK_MOUSE=0 must never enable reports'
case('BVK_MOUSE=0 -> reports never enabled', t_off_env, env={'BVK_MOUSE': '0'})

def t_no_dsr(a):                                   # a terminal that never answers ESC[6n: reports are dropped, app still fine
    r = item_row(a, 5); a.click(r, t=1.0)
    ok = a.alive and b'\x1b[?1000l' in a.raw
    a.send(b'7', 0.4)
    return ok and a.prompt() == '7', 'no cursor answer: reports are switched off, keyboard still works (prompt=%r)' % a.prompt()
case('terminal without cursor-position answer -> mouse switched off, keys still work', t_no_dsr, answer_dsr=False)

def t_off_on_exit(a):
    a.send(b'q', 0.3); a.send(b'\r', 1.5)
    return (not a.alive) and a.raw.rfind(b'\x1b[?1000l') > a.raw.rfind(b'\x1b[?1000h'), 'reports must be switched off when the app quits'
case('quit switches reports off', t_off_on_exit)

def t_off_after_open(a):
    r = item_row(a, 1); a.click(r, t=0.05); a.click(r, t=1.5)
    # after a double click the list prompt was left: the last switch must be "off" until the next list prompt switches on again
    return a.alive and a.raw.count(b'\x1b[?1000l') >= 1 and a.raw.count(b'\x1b[?1000h') >= 2, 'off when leaving a prompt, on again at the next'
case('reports are switched off when a prompt is left, on at the next', t_off_after_open)

def t_no_leak(a):
    r = item_row(a, 5); a.click(r)
    return '<0;' not in a.text() and '[<' not in a.text(), 'a report must never be echoed / typed into the prompt'
case('no mouse bytes leak into the prompt', t_no_leak)

def t_group(a):                                  # Group by view: the rows are groups; click selects, double click drills in
    r = item_row(a, 2)
    if not r: return False, 'item 2 is not on screen in the grouped view'
    a.click(r, t=0.6); ok1 = a.prompt() == '2'
    a.click(r, t=0.05); a.click(r, t=1.5)
    ok2 = 'Group view: .txt' in a.text() and '2026' in a.text()
    return ok1 and ok2 and a.alive, 'grouped view: click selects 2 (%s), double click opens the group (%s)' % (ok1, ok2)
case('Group by view: click selects the group, double click opens it', t_group, settings='group_view_levels_str="ext year"\n')

print('ALL OK' if all(results) else 'FAILED'); sys.exit(0 if all(results) else 1)
