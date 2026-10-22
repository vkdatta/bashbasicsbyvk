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


# ── header: status row, nav path ─────────────────────────────────────────────────────────────────────────────────────
def hdr_tap(col, typed, extra=None):
    def t(a):
        r = a.row_of(r'\| ⏰'); a.click(r, col=col, t=3.0)
        ok = (typed in a.raw) and (extra is None or extra in a.raw.lower() or extra in a.text().lower())
        return ok and a.alive, 'tap on the status row at column %d must type and run %r' % (col, typed)
    return t
case('status row: tap 1st field -> lang runs', hdr_tap(1, b'Select: lang', b'drill'), nfiles=20)
case('status row: tap 2nd field -> nf runs', hdr_tap(7, b'Select: nf', b'notif'), nfiles=20)
def t_pn(a):
    r = a.row_of(r'\| ⏰'); a.click(r, col=14, t=3.0)
    return 'Pending' in a.text() and a.alive, 'tap on the 3rd field must open pn (Pending)'
case('status row: tap 3rd field -> pn opens', t_pn, nfiles=20)

def t_nav(a):
    r = a.row_of(r'nav path'); L = a.lines()[r - 1]
    i = L.index('/home/work') + 2                       # a cell of the name "home" (0-based index; click columns are 1-based)
    cd_before = [l for l in a.lines() if 'cd path' in l][0]
    a.click(r, col=i + 1, t=1.5)
    nav = [l for l in a.lines() if 'nav path' in l][0]; cd = [l for l in a.lines() if 'cd path' in l][0]
    return nav.rstrip().endswith('/home') and cd == cd_before and a.alive, 'nav path must become .../home and cd path stay put (nav=%r cd=%r)' % (nav, cd)
case('nav path: tap a folder name -> browse there, cd path untouched', t_nav, nfiles=20)

def t_nav_cur(a):
    r = a.row_of(r'nav path'); L = a.lines()[r - 1]
    before = L; a.click(r, col=len(L.rstrip()) - 1, t=1.2)
    return [l for l in a.lines() if 'nav path' in l][0] == before and a.alive, 'a tap on the current folder name changes nothing'
case('nav path: tap the current folder -> nothing', t_nav_cur, nfiles=20)

# ── Settings / Home (_st_run) ─────────────────────────────────────────────────────────────────────────────────────
def st_row(a, n): return a.row_of(r'^\s*%d\)\s' % n)
def open_screen(a, key):
    a.send(key.encode() + b'\r', 1.5)
def t_settings_click(a):
    open_screen(a, 's')
    if 'Settings' not in a.text(): return False, 'settings did not open'
    r = st_row(a, 3)
    a.click(r); p = a.prompt()
    return p == '3' and a.alive, 'click row 3 in Settings -> prompt 3 (got %r)' % p
case('Settings: click a row -> its number is typed', t_settings_click, nfiles=20)

def t_settings_dbl(a):
    open_screen(a, 's')
    r = st_row(a, 1); before = a.text()
    a.click(r, t=0.05); a.click(r, t=1.5)
    return a.alive and a.text() != before and 'Settings ›' in a.text(), 'double click on row 1 must open that sub screen'
case('Settings: double click -> opens the row', t_settings_dbl, nfiles=20)

def t_home(a):
    open_screen(a, 'h')
    if 'Local Surf' not in a.text(): return False, 'home did not open'
    r = st_row(a, 8); a.click(r, t=0.05); a.click(r, t=2.5)         # 8 = Help
    return a.alive and (b'bashbasicsbyvk_help.txt' in a.raw), 'double click on row 8 (Help) must run Help (the sandbox has no help file, so it says so)'
case('Home: double click -> opens the row', t_home, nfiles=20)

def t_settings_scroll(a):
    open_screen(a, 's')
    a.wheel(False); p1 = a.prompt()
    return p1 is not None and p1 != '' and a.alive, 'wheel in Settings moves the highlight (prompt=%r)' % p1
case('Settings: wheel moves the highlight', t_settings_scroll, nfiles=20)

def t_st_mouse_off_after(a):
    open_screen(a, 's'); n_on = a.raw.count(b'\x1b[?1000h')
    r = st_row(a, 1); a.click(r, t=0.05); a.click(r, t=1.5)         # a row opens a sub screen: reports are cycled off/on around it
    return a.alive and n_on >= 1 and a.raw.count(b'\x1b[?1000l') >= 1, 'reports on while Settings waits, off around what a row opens'
case('Settings: reports on inside, off when a row opens a prompt', t_st_mouse_off_after, nfiles=20)

# ── a read -p menu (_sm_run): the file menu ───────────────────────────────────────────────────────────────────────────
def open_file_menu(a):
    r = item_row(a, 7); a.click(r, t=0.05); a.click(r, t=1.8)       # item 7 = file001.txt
def t_sm(a):
    open_file_menu(a)
    if 'What would you like to do' not in a.text(): return False, 'the file menu did not open'
    r = a.row_of(r'^\s*2\)\s'); a.click(r)
    return a.prompt() == '2' and a.alive, 'click option 2 in the file menu -> prompt 2 (got %r)' % a.prompt()
case('read -p menu (file menu): click an option -> its token is typed', t_sm)

def t_sm_dbl(a):
    open_file_menu(a)
    r = a.row_of(r'^\s*(u|U)\)') or None
    # option 0 = Run; use a harmless one: the file menu's own  u) Up  is a footer key, not a row; so double click row 0 would run the file.
    # instead check that a double click ACCEPTS: row 3 "Copy Content" copies to the clipboard (harmless), and the menu returns to the list
    r3 = a.row_of(r'^\s*3\)\s'); a.click(r3, t=0.05); a.click(r3, t=2.0)
    return a.alive and 'What would you like to do' not in a.text(), 'a double click on option 3 must accept it (the menu closes)'
case('read -p menu: double click -> accepts', t_sm_dbl)

# ── the Item numbers picker ───────────────────────────────────────────────────────────────────────────────────────────
def picker(a):
    a.send(b'd\r', 1.5)
    return 'Item numbers' in a.text()
def pk(a):
    for l in reversed(a.lines()):
        if 'Item numbers:' in l: return l.split('Item numbers:', 1)[1].strip()
def t_picker(a):
    if not picker(a): return False, 'the picker did not open'
    for n in (7, 9): a.click(item_row(a, n))
    p1 = pk(a)
    a.click(item_row(a, 8)); p2 = pk(a)
    a.click(item_row(a, 9)); p3 = pk(a)
    return (p1, p2, p3) == ('7,9', '7-9', '7-8') and a.alive, 'clicks toggle items in the list: expected 7,9 / 7-9 / 7-8, got %r %r %r' % (p1, p2, p3)
case('Item numbers picker: click toggles items (ranges are compacted)', t_picker)

def t_picker_header(a):
    if not picker(a): return False, 'the picker did not open'
    r = a.row_of(r'\| ⏰'); a.click(r, col=1, t=1.0)
    return 'Drill' not in a.text() and b'Select: lang' not in a.raw and a.alive, 'inside a flow the status row must NOT run commands'
case('Item numbers picker: status-row taps are ignored inside a flow', t_picker_header)


# ── tabs (sw, fx, -u, .r ...) ─────────────────────────────────────────────────────────────────────────────────────
import unicodedata
def dispw(t):                                    # display cells, as the app counts them: wide / emoji = 2, variation selector = 0
    return sum(0 if c == '\ufe0f' else (2 if unicodedata.east_asian_width(c) in 'WF' else 1) for c in t)
def tab_click(a, label):                         # tap the middle of a tab label on the tab bar row
    r = a.row_of(r'tabs|switch tab|SWITCH|FUNCTIONS|UPGRADE|RULE BOOK')
    L = a.lines()[r - 1]; i = L.index(label)
    a.click(r, col=dispw(L[:i]) + max(1, dispw(label) // 2) + 1, t=1.5)
def cur_tab(a):
    m = re.search(r'\[([^\]]+)\]', ''.join(l for l in a.lines() if 'tabs' in l or 'switch tab' in l))
    return m.group(1) if m else None
def t_sw_tabs(a):
    a.send(b'sw\r', 2.0)
    if cur_tab(a) != '📌 Bookmarks': return False, 'sw did not open on Bookmarks (%r)' % cur_tab(a)
    tab_click(a, '🕐 Recents');   ok1 = cur_tab(a) == '🕐 Recents'
    tab_click(a, '⭐ Favourites'); ok2 = cur_tab(a) == '⭐ Favourites'
    tab_click(a, '📌 Bookmarks');  ok3 = cur_tab(a) == '📌 Bookmarks'          # two steps back in one tap
    tab_click(a, '⭐ Favourites'); ok4 = cur_tab(a) == '⭐ Favourites'          # two steps forward in one tap
    return ok1 and ok2 and ok3 and ok4 and a.alive, 'sw tabs after taps: %s %s %s %s (now %r)' % (ok1, ok2, ok3, ok4, cur_tab(a))
case('sw: tap a tab -> that tab (also two steps in one tap)', t_sw_tabs, nfiles=20)
def t_fx_tabs(a):
    a.send(b'fx\r', 2.0)
    tab_click(a, '👤 UDF'); ok1 = cur_tab(a) == '👤 UDF'
    tab_click(a, '🛠️  ADF'); ok2 = cur_tab(a) == '🛠️  ADF'
    return ok1 and ok2 and a.alive, 'fx tabs: %s %s (now %r)' % (ok1, ok2, cur_tab(a))
case('fx: tap a tab -> that tab', t_fx_tabs, nfiles=20)
def t_rules_tabs(a):
    a.send(b'.r\r', 2.0)
    tab_click(a, '🕘 Last used'); ok1 = cur_tab(a) == '🕘 Last used'
    tab_click(a, '🧩 Rules');     ok2 = cur_tab(a) == '🧩 Rules'
    return ok1 and ok2 and a.alive, 'rule book tabs: %s %s (now %r)' % (ok1, ok2, cur_tab(a))
case('.r: tap a tab -> that tab', t_rules_tabs, nfiles=20)
def t_upg_tabs(a):
    a.send(b'-u\r', 3.0)
    tab_click(a, '🧪 Tags (beta)'); ok1 = cur_tab(a) == '🧪 Tags (beta)'
    tab_click(a, '📦 Stable');      ok2 = cur_tab(a) == '📦 Stable'
    return ok1 and ok2 and a.alive, 'upgrade tabs: %s %s (now %r)' % (ok1, ok2, cur_tab(a))
case('-u: tap a tab -> that tab', t_upg_tabs, nfiles=20)
def t_tab_title_cur(a):
    a.send(b'sw\r', 2.0)
    r = a.row_of(r'SWITCH'); L = a.lines()[r - 1]
    a.click(r, col=dispw(L[:L.index('SWITCH')]) + 3, t=1.0)                      # the title: not a tab
    ok1 = cur_tab(a) == '📌 Bookmarks'
    tab_click(a, '📌 Bookmarks'); ok2 = cur_tab(a) == '📌 Bookmarks'               # the current tab: nothing
    return ok1 and ok2 and a.alive, 'title / current tab taps must change nothing'
case('sw: tapping the title or the current tab does nothing', t_tab_title_cur, nfiles=20)

# Cloud Surf and RBAM need a signed-in account to open, so they cannot be driven end to end here: their tab bars are checked with the
# real hit-test on the exact lines their headers print, and their files are checked for the label registration + the shared loop.
import subprocess
def hit(line, x, labels):
    sh = ('export LC_ALL=C.UTF-8; cd "%s/script/file/engine"; source ./bashbasicsbyvk_viewport.sh 2>/dev/null; source ./bashbasicsbyvk_mouse.sh 2>/dev/null; '
          '_bvk_tabs_register %s; _MS_X=%d; _bvk_mouse_tab_hit "$1" && echo "delta=$_MS_TABDELTA" || echo none') % (
          root, ' '.join('"%s"' % l for l in labels), x)
    return subprocess.run(['bash', '-c', sh, 'x', line], capture_output=True, text=True).stdout.strip()
def t_xui_tabs(a):
    src = open(os.path.join(root, 'script/file/loops/iloop/rbam/bashbasicsbyvk_csurf.sh')).read() + open(os.path.join(root, 'script/file/loops/iloop/rbam/bashbasicsbyvk_rbam.sh')).read()
    reg = '_bvk_tabs_register "📤 Given" "📥 Received"' in src and '_bvk_tabs_register "📤 Give access" "📥 Receive access"' in src
    cs0 = '☁️  Cloud Surf   [📤 Given]   📥 Received      (←/→ switch tab)'
    cs1 = '☁️  Cloud Surf    📤 Given   [📥 Received]     (←/→ switch tab)'
    rb0 = '🤝 RBAM   [📤 Give access]   📥 Receive access     (←/→ switch tab)'
    xs = [hit(cs0, 33, ['📤 Given', '📥 Received']) == 'delta=1',            # on "Received"
          hit(cs1, 20, ['📤 Given', '📥 Received']) == 'delta=-1',           # on "Given"
          hit(cs0, 3,  ['📤 Given', '📥 Received']) == 'none',               # on the title
          hit(rb0, 30, ['📤 Give access', '📥 Receive access']) == 'delta=1']
    return reg and all(xs) and a.alive, 'cs / rbam tab bars: registered=%s hits=%s' % (reg, xs)
case('cs / rbam: tab bar hit-test on their real header lines', t_xui_tabs, nfiles=20)

print('ALL OK' if all(results) else 'FAILED'); sys.exit(0 if all(results) else 1)
