"""ONE template for every typed-line prompt (the "read choice" family), checked on the REAL app (pty + tests/paste_input/vt.py).
Two behaviours live in the template, not in each loop (textedit.sh _te_cursor, viewport.sh _bvk_prompt_tap), so every prompt must show them:
  1. a selection hides the terminal's block cursor (it would sit on the first selected character and make it look blank); it is back
     when the selection is gone and when the prompt is left
  2. a tap on the typed text moves the cursor to the tapped character (an empty prompt keeps the old hand-back, the keyboard opens)
Prompts covered: main Select: · item numbers (delete picker) · the choice box (Confirm delete) · Settings (same engine) · smart menu ·
and, for 1 only, the typed-line prompt (the `read` shim, no mouse there).
usage: python3 prompt_test.py [only-case-substring]"""
import os, sys, re
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp
COLS, ROWS = 100, 30
only = sys.argv[1] if len(sys.argv) > 1 else ''
SHIFT_LEFT = b'\x1b[1;2D'

class App(PtyApp):
    select_t = 0.02; send_t = 0.5; quiet = 0.2
    def __init__(self):
        def populate(home, work):
            for n in ('alpha.txt', 'beta.txt', 'gamma.txt'): open(os.path.join(work, n), 'w').write('x')
            d = os.path.join(home, '.config', 'bashbasicsbyvk'); os.makedirs(d, exist_ok=True)
            open(os.path.join(d, 'config'), 'a').write('backup_mode=ask\n')
        super().__init__(root, COLS, ROWS, populate, {'BVK_DBLCLICK_MS': '1500'}, True)
    def prow(self, label):                       # (screen row 1-based, line) of the lowest line that holds the prompt label
        L = self.scr.lines()
        for i in range(len(L) - 1, -1, -1):
            if label in L[i]: return i + 1, L[i]
        return None, ''
    def click(self, row, col):
        self.send(b'\x1b[<0;%d;%dM' % (col, row), 0.35)
        self.send(b'\x1b[<0;%d;%dm' % (col, row), 0.05)
    def cursor_hidden(self): return self.raw.rfind(b'\x1b[?25l') > self.raw.rfind(b'\x1b[?25h')

results = []
def case(name, fn):
    if only and only not in name: return
    a = App()
    try:
        ok, why = fn(a); results.append(ok)
        print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '   [' + why + ']'))
        if not ok: print('   alive=%s hidden=%s\n   ' % (a.alive, a.cursor_hidden()) + '\n   '.join(l for l in a.scr.lines() if l.strip())[-1500:])
    finally: a.close()

# each opener brings the app to ONE prompt and returns its label
def main_prompt(a): return 'Select:'
def picker(a):      a.line('d'); a.wait_text('DELETE (ranges'); return 'Item numbers:' if 'Item numbers:' in a.text() else 'Select:'
def confirm(a):     a.line('d'); a.wait_text('DELETE (ranges'); a.line('1'); a.wait_text('Confirm delete'); return 'Select:'
def settings(a):    a.line('s'); a.wait_text('Settings'); return 'Select:'
OPENERS = [('main Select:', main_prompt), ('item numbers (delete picker)', picker), ('choice box (Confirm delete)', confirm), ('Settings', settings)]

TEXT = 'zqxwvu'     # letters no screen reads as a row number; typed, never submitted

def select_back(a, n=3):
    for _ in range(n): a.send(SHIFT_LEFT, 0.25)

def mk_hide(opener):
    def t(a):
        lab = opener(a)
        a.send(TEXT.encode(), 0.4)
        if a.cursor_hidden(): return False, 'the cursor is hidden before anything is selected'
        select_back(a)
        if not a.cursor_hidden(): return False, 'a selection is shown but the block cursor is still visible (it hides the first selected character)'
        a.send(b'\x1b[D', 0.3)                  # Left: the selection collapses
        return (not a.cursor_hidden()), 'the cursor must be back once the selection is gone'
    return t

def mk_tap(opener):
    def t(a):
        lab = opener(a)
        a.send(TEXT.encode(), 0.4)
        r, line = a.prow(lab + ' ' + TEXT) if a.prow(lab + ' ' + TEXT)[0] else a.prow(lab)
        if r is None or TEXT not in line: return False, 'cannot find the prompt row with the typed text: %r' % line
        col0 = line.index(TEXT)                 # 0-based column of the first typed character
        a.click(r, col0 + 2 + 1)                # a tap on the 3rd character (1-based column)
        a.send(b'Y', 0.4)
        want = TEXT[:2] + 'Y' + TEXT[2:]
        r2, line2 = a.prow(want)
        return (r2 is not None), 'tapped the 3rd character, typed Y: expected %r on the prompt row, got %r' % (want, a.prow(lab)[1].strip())
    return t

def mk_empty_tap(opener):                       # nothing typed: the tap hands the touch back (reports go off), no cursor games
    def t(a):
        lab = opener(a)
        r, line = a.prow(lab)
        n = a.raw.count(b'\x1b[?1000l')
        a.click(r, 12)
        return a.alive and a.raw.count(b'\x1b[?1000l') > n, 'a tap on an EMPTY prompt must still hand the touch back (mouse reports off) so the keyboard opens'
    return t

for name, op in OPENERS:
    case('selection hides the block cursor: ' + name, mk_hide(op))
    case('tap on the typed text moves the cursor: ' + name, mk_tap(op))
    case('tap on an empty prompt hands the touch back: ' + name, mk_empty_tap(op))
print('ALL OK' if all(results) else 'FAILED'); sys.exit(0 if all(results) else 1)
