# Regression: a command run at a plain text prompt (print at the rename "New:" prompt) asks its own questions; the wait opened by
# the last answer must be closed when the prompt is drawn again (else a "Working..." bar sits on the prompt).
import sys, os
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + '/tests/paste_input')
from ptyapp import PtyApp
def pop(home, work):
    open(os.path.join(work, 'base.tar.gz'), 'w').write('x')
a = PtyApp(ROOT, 100, 40, pop, env=dict(VK_SMARTLOAD_GRACE_MS='300'))
a.send('r\r', until=lambda: 'Item numbers' in a.text())
a.send('1\r', until=lambda: 'New:' in a.text())
a.send('print\r', until=lambda: 'Copy to clipboard' in a.text())
a.send('u\r', until=lambda: 'Copy to clipboard' not in a.text().split('Old:')[-1])
a.wait(lambda: 'Working' in a.text(), 2.5)          # the bar (if the bug is back) shows after the 300 ms grace
t = a.text()
a.close()
if 'Working' in t.split('Copy to clipboard')[-1]:
    print('  FAIL a loading bar is left on the rename prompt after print + u'); sys.exit(1)
print('  ok   no loading bar on the rename prompt after print + u')
