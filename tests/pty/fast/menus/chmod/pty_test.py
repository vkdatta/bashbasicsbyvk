# chmod-N: the Change Mode screen (tabs, cell cursor 1 -> 1-RA, Enter switches, real chmod on the files)
import sys, os, stat
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + '/tests/pty/lib')
from ptyapp import PtyApp
fail = 0
def check(c, msg):
    global fail
    print(('  ok   ' if c else '  FAIL ') + msg)
    if not c: fail = 1
W = {}
def pop(home, work):
    W['dir'] = work
    for n in ('a.txt', 'b.txt'): open(os.path.join(work, n), 'w').write('x')
    os.chmod(os.path.join(work, 'a.txt'), 0o640)
    os.chmod(os.path.join(work, 'b.txt'), 0o644)
def mode(n): return stat.S_IMODE(os.stat(os.path.join(W['dir'], n)).st_mode)
RIGHT, DOWN, LEFT = b'\x1b[C', b'\x1b[B', b'\x1b[D'
a = PtyApp(ROOT, 100, 40, pop)
a.send('chmod-1,2\r', until=lambda: 'Change Mode' in a.text()); a.settle()
t = a.text()
check('Change Mode' in t and 'Owner' in t and 'Group' in t and 'Others' in t, 'screen shows the title and the three tabs')
check('a.txt' in t and '[R]' in t and '[ ]' in t, 'rows show the name and the R W X boxes')
a.send(RIGHT); a.settle()                                   # empty line: next tab
check(mode('a.txt') == 0o640, 'plain → on an empty line changes nothing on disk')
a.send(LEFT); a.settle()
a.send('1'); a.send(RIGHT); a.settle()
check('Select: 1-RA' in a.text().split('Select: 1-RA')[0] + 'Select: 1-RA' and 'Select: 1-RA' in a.text(), '1 then → makes the line 1-RA')
a.send(b'\r'); a.settle()
check(mode('a.txt') == 0o240, 'Enter on 1-RA switched the owner read off (0640 -> 0240)')
check('Select: 1-RD' in a.text(), 'the line is now 1-RD')
a.send(b'\r'); a.settle()
check(mode('a.txt') == 0o640, 'Enter on 1-RD switched it back on')
a.send(RIGHT); a.settle(); a.send(b'\r'); a.settle()
check(mode('a.txt') & 0o200 == 0, '→ moved to W and Enter switched write off')
a.send(DOWN); a.settle()
check('Select: 2-W' in a.text(), '↓ on a cell keeps the column (2-W..)')
a.close()
sys.exit(fail)
