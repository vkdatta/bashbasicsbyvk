"""A word typed into a yes/no or choice box (script/file/settings/bashbasicsbyvk_choose.sh, _bc_word) goes through the command layer like at every
prompt of the app: plain text is cleared, @word is text, a command runs and the question comes back, u leaves.  Before, _bc_cmd returned 0 for every
word, so the hint row said "h -> Home" and Enter dropped it.  Real terminal (pty + tests/paste_input/ptyapp.py).  usage: python3 typed_test.py"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp

BODY = r'''
echo READY
_bvk_yn a8 "Typed probe?" -d n; builtin echo "R8 [$a8] rc=$?"
_bvk_yn a9 "Second probe?" -d n; builtin echo "R9 [$a9] rc=$? abort=$_CM_ABORT"
exit 0
'''
o = open(os.path.join(root, 'script', 'o'), encoding='utf-8').read()
head = o.split('_lt_mark "startup finished')[0]
drv = os.path.join(root, 'script', 'typed_test_driver.sh')

class App(PtyApp):
    entry = 'typed_test_driver.sh'; ready_text = 'READY'

res = []
def check(name, cond, why=''):
    res.append(bool(cond)); print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else '   [' + why + ']'), flush=True)
def screen(a): return '\n'.join(l.rstrip() for l in a.lines() if l.strip())
def home_open(a): return 'Local Surf' in screen(a)

open(drv, 'w', encoding='utf-8').write(head + '\n' + BODY)
a = None
try:
    a = App(root, 90, 30, lambda home, work: open(os.path.join(work, 'a.txt'), 'w').write('x'), env={'BVK_BROWSER_TERM': '0'})
    a.wait_text('Typed probe?', 8); a.wait_text('y) Yes   n) No', 8)
    a.send('xyz'); a.send('\r'); a.settle()
    check('plain text is not an answer: cleared, the box stays', 'Typed probe?' in screen(a) and 'R8 [' not in a.text() and not home_open(a), screen(a)[-300:])
    a.send('@h'); a.send('\r'); a.settle()
    check('@h is text, never the Home command', not home_open(a) and 'R8 [' not in a.text(), screen(a)[-300:])
    a.send('h'); a.send('\r', until=lambda: home_open(a))
    check('h typed in a question opens Home (the hint row and Enter agree)', home_open(a), screen(a)[-300:])
    a.send('u'); a.send('\r', until=lambda: 'Typed probe?' in screen(a) and not home_open(a))
    check('u leaves Home and the same question is asked again', 'R8 [' not in a.text(), screen(a)[-300:])
    a.settle(); a.send('n'); a.send('\r', until=lambda: 'R8 [' in a.text())
    check('the question can still be answered afterwards', 'R8 [n] rc=0' in a.text(), a.text()[-200:])
    a.wait_text('Second probe?', 8); a.wait_text('y) Yes   n) No', 8)
    a.send('r'); a.send('\r'); a.settle()          # r is a main command that is BLOCKED inside a question: it cancels the whole flow, like at any prompt
    check('a blocked command cancels the flow (rc 1, abort)', 'R9 [] rc=1 abort=1' in a.text(), a.text()[-300:])
finally:
    if a: a.close()
    if os.path.exists(drv): os.remove(drv)
print('typed words in a choice box: ' + ('OK' if all(res) and res else 'FAILED')); sys.exit(0 if all(res) and res else 1)
