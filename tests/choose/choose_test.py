"""The choice menu (script/file/settings/bashbasicsbyvk_choose.sh): yes/no/cancel, radio [o], checkbox [x], action menus.
Real terminal (pty + tests/paste_input/ptyapp.py) around a tiny driver made from the real startup of script/o, so the menu runs with the
whole command layer loaded.  usage: python3 choose_test.py"""
import os, sys, re
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp

BODY = r'''
echo READY
_bvk_yn a1 "Keep these?" -d n;                         builtin echo "R1 [$a1] rc=$?"
_bvk_yn a7 "Delete these?" -d n;                       builtin echo "R7 [$a7] rc=$?"
_bvk_yn a2 "Back up first?" -d y -c;                   builtin echo "R2 [$a2] rc=$?"
_bvk_yn a3 "Sure?" -d n;                               builtin echo "R3 [$a3] rc=$?"
_bvk_menu m1 -t "Pick" "a:Apple" "b:Banana" "c:Cherry"; builtin echo "R4 [$m1] rc=$?"
_bvk_menu m2 -m -t "Fruits" "a:Apple" "b:Banana" "c:Cherry"; builtin echo "R5 [$m2] rc=$?"
_bvk_yn a6 "Last one?" -c;                             builtin echo "R6 [$a6] rc=$? abort=$_CM_ABORT"
exit 0
'''
o = open(os.path.join(root, 'script', 'o'), encoding='utf-8').read()
head = o.split('_lt_mark "startup finished')[0]
drv = os.path.join(root, 'script', 'choose_test_driver.sh')

class App(PtyApp):
    entry = 'choose_test_driver.sh'; ready_text = 'READY'

res = []
def check(name, cond, why=''):
    res.append(bool(cond)); print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else '   [' + why + ']'))
def screen(a): return '\n'.join(l.rstrip() for l in a.lines() if l.strip())

open(drv, 'w', encoding='utf-8').write(head + '\n' + BODY)
a = None
try:
    a = App(root, 80, 30, lambda home, work: open(os.path.join(work, 'a.txt'), 'w').write('x'), env={'BVK_BROWSER_TERM': '0'})
    a.wait_text('Keep these?', 8)
    s = screen(a)
    check('yes/no: header, rules, rows', '1) [o] No' not in s and '2) [o] No' in s and '1) [ ] Yes' in s, s[-300:])
    check('yes/no: footer lists u/q and the answer keys', 'u) Back   q) Close' in s and 'y) Yes   n) No' in s, s[-300:])
    a.send('\r', until=lambda: 'R1 [' in a.text())
    check('Enter takes the default (n)', 'R1 [n] rc=0' in a.text(), a.text()[-200:])
    # a question that names a destructive action has NO default whatever -d says: nothing is highlighted, a bare Enter does not answer it
    a.wait_text('Delete these?', 8); a.wait(lambda: '2) [ ] No' in screen(a) or '2) [o] No' in screen(a), 8); s = screen(a)    # the rows are drawn after the title
    check('a destructive question highlights nothing', '[o]' not in s and '1) [ ] Yes' in s and '2) [ ] No' in s, s[-300:])
    a.send('\r'); a.settle()
    check('a bare Enter does not answer a destructive question', 'R7 [' not in a.text(), a.text()[-200:])
    a.send('n'); a.send('\r', until=lambda: 'R7 [' in a.text())
    check('the person must answer it (n)', 'R7 [n] rc=0' in a.text(), a.text()[-200:])
    a.wait_text('Back up first?', 8); a.wait_text('c/x) Cancel', 8); s = screen(a)
    check('yes/no/cancel: three rows and the c/x key', '3) [ ] Cancel' in s and 'c/x) Cancel' in s and '1) [o] Yes' in s, s[-300:])
    a.send('x'); a.send('\r', until=lambda: 'R2 [' in a.text())
    check('x answers Cancel (c)', 'R2 [c] rc=0' in a.text(), a.text()[-200:])
    a.wait_text('Sure?', 8); a.send('1'); a.send('\r', until=lambda: 'R3 [' in a.text())
    check('a row number answers', 'R3 [y] rc=0' in a.text(), a.text()[-200:])
    a.wait_text('Pick', 8); a.wait_text('3) [ ] Cherry', 8); a.send('\x1b[B'); a.send('\x1b[B'); a.wait_text('2) [o] Banana', 8)
    s = screen(a)
    check('radio: [o] follows the highlight, only one is on', s.count('[o]') == 1 and '2) [o] Banana' in s, s[-300:])
    a.send('\r', until=lambda: 'R4 [' in a.text())
    check('radio: Enter on the highlighted row answers', 'R4 [b] rc=0' in a.text(), a.text()[-200:])
    a.wait_text('Fruits', 8); a.send('1'); a.send('\r'); a.send('3'); a.send('\r')
    s = screen(a)
    check('checkbox: [x] marks, several can be on', '1) [x] Apple' in s and '3) [x] Cherry' in s and '2) [ ] Banana' in s and '[o]' not in s, s[-400:])
    a.send('d'); a.send('\r', until=lambda: 'R5 [' in a.text())
    check('checkbox: Done returns every ticked key', 'R5 [a c] rc=0' in a.text(), a.text()[-200:])
    a.wait_text('Last one?', 8); a.send('u'); a.send('\r', until=lambda: 'R6 [' in a.text())
    check('u backs out: rc 1, empty answer, the flow is cancelled', 'R6 [] rc=1 abort=1' in a.text(), a.text()[-200:])
finally:
    if a: a.close()
    if os.path.exists(drv): os.remove(drv)
print('choose menu: ' + ('OK' if all(res) and res else 'FAILED')); sys.exit(0 if all(res) and res else 1)
