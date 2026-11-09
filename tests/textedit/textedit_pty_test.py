"""Real-app pty test of the shared text-edit template (script/.../bashbasicsbyvk_textedit.sh) on the MAIN "Select:" prompt:
selection with Shift+arrows, select all, replace by typing, cut / copy / paste, word delete, Delete, undo, Home / End.
usage: python3 textedit_pty_test.py"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(here, '..', 'paste_input')); from ptyapp import PtyApp
def populate(home, work):
    for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
# no system clipboard tool may be found: the app's own clipboard is what is under test
a = PtyApp(root, 80, 30, populate, env={'BVK_BROWSER_TERM': None, 'DISPLAY': None, 'WAYLAND_DISPLAY': None})
ok = True
def line():
    L = a.lines()
    for r in range(len(L) - 1, -1, -1):
        if L[r].startswith('Select:'): return L[r][len('Select:'):].strip('\n').lstrip(' ').rstrip()
    return None
def keys(b, want, name):
    global ok
    a.send(b, until=lambda: line() == want.rstrip())
    a.settle(0.3)                                   # the key is processed whatever the line shows (a no-op key changes nothing)
    got = line(); good = got == want.rstrip(); ok &= good
    print(('PASS ' if good else 'FAIL ') + name + ('' if good else ' got %r want %r' % (got, want)))
SL, SR, CL, CR = b'\x1b[1;2D', b'\x1b[1;2C', b'\x1b[1;5D', b'\x1b[1;5C'
keys(b'hello world', 'hello world', 'typing')
keys(SL * 5, 'hello world', 'shift-left keeps the text')
keys(b'X', 'hello X', 'typing replaces the selection')
keys(b'\x1b[1;2H' , 'hello X', 'shift-home selects')
keys(b'\x1b[3~', '', 'delete removes the selection')
keys(b'\x1a', 'hello X', 'ctrl-z undoes the delete')
keys(b'\x01', 'hello X', 'ctrl-a selects all')
keys(b'\x03', 'hello X', 'ctrl-c copies, text stays')
keys(b'\x1b[D' , 'hello X', 'left collapses the selection')
keys(b'\x1b[1;5F', 'hello X', 'ctrl-end moves to the end of the text (a plain End stays the list\'s)')
keys(b'\x16', 'hello Xhello X', 'ctrl-v pastes the copied text')
keys(b'\x17', 'hello Xhello ', 'ctrl-w deletes the word before the cursor')
keys(b'\x1b[3;5~', 'hello Xhello ', 'ctrl-delete at the end of the text does nothing')
keys(b'\x1b[1;5H' + CR, 'hello Xhello ', 'ctrl-home then ctrl-right moves')
keys(b'\x18', 'hello Xhello ', 'ctrl-x with nothing selected does nothing')
keys(b'\x1b[1;6C', 'hello Xhello ', 'ctrl-shift-right selects a word')
keys(b'\x18', 'hello ', 'ctrl-x cuts it')
keys(b'\x0b', 'hello ', 'ctrl-k at the end does nothing')
keys(b'\x15', '', 'ctrl-u deletes to the line start')
a.close()
sys.exit(0 if ok else 1)
