# The results screen (_results_view): Find hits and Find & replace previews are shown the way the recursive "==" filter shows its hits.
import sys, os
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + '/tests/paste_input')
from ptyapp import PtyApp
fail = 0
def check(c, msg):
    global fail
    print(('  ok   ' if c else '  FAIL ') + msg)
    if not c: fail = 1
CFG = 'find_case_mode=exact\nfind_depth_mode=recursive\nfind_input_mode=single\n'
def pop(names, dirs=()):
    def f(home, work):
        d = os.path.join(home, '.config', 'bashbasicsbyvk'); os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'config'), 'w').write(CFG)
        for n in names: open(os.path.join(work, n), 'w').write('x')
        for n in dirs: os.makedirs(os.path.join(work, n, 'in'), exist_ok=True)
    return f
def start(names, dirs=(), menu='1', rows=200):      # tall: the whole history of the screen stays visible to the checks
    a = PtyApp(ROOT, 200, rows, pop(names, dirs))      # wide: the runner's temp paths are long and a wrapped header would hide the text
    a.send('f\r', until=lambda: 'Find mode in' in a.text())
    a.send(menu + '\r', until=lambda: 'Text to find' in a.text())
    return a
many = ['IMG-20261116-WA%04d.jpg' % i for i in range(1, 121)] + ['other.txt']

# 1. layout = the "==" screen (a phone-sized terminal: the list scrolls)
a = start(many, rows=40)
a.send('2026111\r', until=lambda: 'result(s)' in a.text()); a.settle()
t = a.text()
check('🔍 find: 2026111  (120 result(s))' in t and '☁️ nav path:' in t and '📂 cd path:' in t, 'header: cd path, nav path + find text and count (like "🔍 filter: … (N matches)")')
check('  1) 🌄 IMG-20261116-WA0001.jpg' in t, 'rows start at 1 with the folder view\'s icon and name')
check('more below' in t and 'not shown' not in t, '"▼ N more below" - nothing is cut off')
check('u) Up   cd) Change directory   q) Quit' in t and 'h) Home   s) Settings   -h) Help   -u) Upgrade' in t, 'footer is the "==" footer')
check('Enter item number' not in t, 'no old "Enter item number" prompt')
# 3. every hit is reachable by scrolling (End = last row)
a.send('\x1b[F'); a.settle(); a.settle()
t2 = a.text()
check('120) 🌄 IMG-20261116-WA0120.jpg' in t2 and '▲' in t2, 'scrolling reaches the 120th hit ("▲ N more above" appears)')
a.close()

# 2. a wrong word / number stays on the screen, with the results still there
a = start(many)
a.send('2026111\r', until=lambda: 'result(s)' in a.text()); a.settle()
a.send('\x15zzz\r'); a.settle()
t3 = a.text().split('Select: zzz')[-1]
check('Invalid' in t3 and '🔍 find: 2026111' in t3, 'a wrong word says Invalid and the results stay')
a.send('\x15999\r'); a.settle()
check('Invalid' in a.text().split('Select: 999')[-1], 'a number past the last hit is Invalid')
# 4. u = back to the question before
a.send('\x15u\r', until=lambda: 'Text to find' in a.text().split('Select: u')[-1])
check('Text to find' in a.text().split('Select: u')[-1], 'u goes back one step: the text to find')
a.close()

# 5. q leaves Find
a = start(many)
a.send('2026111\r', until=lambda: 'result(s)' in a.text()); a.settle()
a.send('q\r'); a.settle(); tq = a.text().split('Select: q')[-1]
check('🔍 find:' not in tq and 'Text to find' not in tq, 'q leaves Find and the results')
a.close()

# 6. a folder hit opens that folder
a = start(['a.txt'], dirs=['d2026111'])
a.send('2026111\r', until=lambda: 'result(s)' in a.text()); a.settle()
a.send('1\r'); a.settle(); a.settle()
tf = a.text().split('Select: 1')[-1]
check('cd path:' in tf and 'd2026111' in tf and '🔍 find:' not in tf, 'a number on a folder hit goes into that folder')
a.close()

# 7. preview: same screen, a) Apply to ALL, a number applies one
a = start(['aa2026.txt', 'bb2026.txt', 'cc.txt'], menu='4')
a.send('2026\r', until=lambda: 'Replace with' in a.text())
a.send('ZZ\r', until=lambda: 'Apply to ALL' in a.text()); a.settle()
t = a.text()
check('🔍 find: 2026 → ZZ' in t and '  1) 📄 aa2026.txt' in t and '→' in t, 'preview: the same rows with the new name after the arrow')
check('a) Apply to ALL' in t and 'u) Up   cd) Change directory   q) Quit' in t, 'preview footer: a) Apply to ALL + the "==" keys')
a.send('2\r'); a.settle(); a.settle()
n = sorted(os.listdir(a.work))
check(n == ['aa2026.txt', 'bbZZ.txt', 'cc.txt'], 'a row number applies just that item: %s' % n)
a.close()
a = start(['aa2026.txt', 'bb2026.txt', 'cc.txt'], menu='4')
a.send('2026\r', until=lambda: 'Replace with' in a.text())
a.send('ZZ\r', until=lambda: 'Apply to ALL' in a.text()); a.settle()
a.send('a\r'); a.settle(); a.settle()
n = sorted(os.listdir(a.work))
check(n == ['aaZZ.txt', 'bbZZ.txt', 'cc.txt'], 'a applies to ALL: %s' % n)
a.close()
# a is not a key of a plain find screen
a = start(many)
a.send('2026111\r', until=lambda: 'result(s)' in a.text()); a.settle()
a.send('\x15a\r'); a.settle()
check('Invalid' in a.text().split('Select: a')[-1], 'a means nothing on a plain find screen')
a.close()

# 8. cc and the footer advertise only what the screen takes (ADVERT): a is a preview-only key
a = start(many)
a.send('2026111\r', until=lambda: 'result(s)' in a.text()); a.settle()
a.send('cc\r', until=lambda: 'Cheat codes' in a.text() or 'Go back' in a.text()); a.settle(); a.settle()
tc = a.text()
check('Go back' in tc and 'Apply the change to ALL' not in tc, 'cc on a plain find screen does not list a')
a.close()
a = start(['aa2026.txt', 'bb2026.txt', 'cc.txt'], menu='4')
a.send('2026\r', until=lambda: 'Replace with' in a.text())
a.send('ZZ\r', until=lambda: 'Apply to ALL' in a.text()); a.settle()
a.send('cc\r', until=lambda: 'Go back' in a.text()); a.settle(); a.settle()
check('Apply the change to ALL' in a.text(), 'cc on a preview lists a')
a.close()
sys.exit(fail)
