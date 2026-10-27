# The one-by-one rename screen: layout, Up fills the old name, the extension rule, the CSV hand-over, the wrapped suggestion rows.
import sys, os
ROOT = sys.argv[1]
sys.path.insert(0, ROOT + '/tests/paste_input')
from ptyapp import PtyApp
fail = 0
def check(c, msg):
    global fail
    print(('  ok   ' if c else '  FAIL ') + msg)
    if not c: fail = 1
def mk(names):
    def pop(home, work):
        for n in names: open(os.path.join(work, n), 'w').write('x')
    return pop
def run(cols, names, sel, keys, env=None, cfg=None):
    def pop(home, work):
        mk(names)(home, work)
        if cfg:
            d = os.path.join(home, '.config', 'bashbasicsbyvk'); os.makedirs(d, exist_ok=True)
            open(os.path.join(d, 'config'), 'w').write(cfg)
    a = PtyApp(ROOT, cols, 40, pop, env=env or {})
    a.send('r\r', until=lambda: '✏️ Rename' in a.text())
    a.send(sel + '\r', until=lambda: 'New:' in a.text() or 'CSV' in a.text())
    for k in keys: a.send(k); a.settle()
    t = a.text(); a.close()
    return t
t = run(50, ['base.tar.gz'], '1', [])
check('✏️ Rename' in t and 'u) Up   q) Close' in t and 'Old: base.tar.gz' in t and 'New:' in t, 'screen: title, rows, footer, Old / New')
check('Item numbers' not in t and 'RENAME (supports' not in t and 'Select: 1' in t, 'one screen: the picker is a plain "Select:" prompt, no old "Item numbers" header')
check(t.count('1) ') == 1 and t.count('Old:') == 1, 'the item list is drawn once; only Old / New is added under it')
check(t.index('u) Up   q) Close') < t.index('Select: 1') < t.index('Old: base.tar.gz') < t.index('New:'), 'order: footer, Select, Old, New')
t = run(50, ['base.tar.gz'], '1', ['\x1b[A'])
check('New: base.tar.gz' in t, 'Up arrow copies the old name into New:')
t = run(60, ['base.tar.gz'], '1', ['zzz\r'])
check('Use old extension' in t and 'zzz.tar.gz' in t, 'no extension + ask: the question offers .tar.gz')
t = run(60, ['base.tar.gz'], '1', ['zzz\r', '1\r'])
check('zzz.tar.gz' in t and 'Renamed' in t or '📦 zzz.tar.gz' in t, 'answer 1 renames to zzz.tar.gz')
t = run(60, ['base.tar.gz'], '1', ['zzz\r', '2\r'])
check('zzz' in t and 'zzz.tar.gz' not in t, 'answer 2 renames to zzz (no extension)')
t = run(60, ['base.tar.gz'], '1', ['x.txt\r'])
check('x.txt' in t and 'No extension' not in t, 'a typed extension is used as typed, no question')
t = run(60, ['base.tar.gz'], '1', ['zzz\r'], cfg='rename_noext_mode=old\n')
check('zzz.tar.gz' in t and 'No extension' not in t.split('Select:')[-1], 'setting "old": no question, old extension kept')
t = run(60, ['base.tar.gz'], '1', ['zzz\r'], cfg='rename_noext_mode=none\n')
check('📄 zzz' in t or ' zzz\n' in t, 'setting "none": created without extension')
t = run(60, ['a.txt','b.txt','c.txt'], '1-3', [], cfg='rename_csv_above=2\n')
check('rename.select.items.csv' in t, '3 selected, limit 2: handed to the CSV rename')
t = run(60, ['a.txt','b.txt','c.txt'], '1-3', [])
check('rename.select.items.csv' not in t and 'Old: a.txt' in t, '3 selected, default limit 5: one by one')
for k in ('u', 'q'):
    a = PtyApp(ROOT, 60, 40, mk(['a.txt']))
    a.send('r\r', until=lambda: '✏️ Rename' in a.text())
    a.send(k + '\r', until=lambda: 'Home' in a.text().split('Rename')[-1])
    tt = a.text().split('Select: ' + k)[-1]; a.close()
    check('Old:' not in tt and 'Quit' in tt, 'Select: %s leaves the rename screen, nothing is renamed' % k)
sys.exit(fail)
