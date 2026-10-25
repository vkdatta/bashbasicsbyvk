"""The Installer of a tool run on its own (bashbasicsbyvk_deps.sh as its own process): it must show the SHARED choice menu (_bvk_yn: box, rows,
Yes / No), not a one-line prompt.  Real terminal via tests/paste_input/ptyapp.py; a fake registry and a fake package manager, nothing real is installed.
usage: python3 tests/deps/standalone_test.py"""
import os, sys, stat
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp

class App(PtyApp):
    entry = 'dep_driver.sh'

res = []
def check(name, cond, why=''):
    res.append(bool(cond)); print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else '   [' + why + ']'))

# the registry / fake dir paths depend on the temp HOME, so the driver exports them itself
def driver_body():
    return ('export BVK_DEPS_REGISTRY="$HOME/reg.list" BVK_DEPS_MANAGER=apt BVK_DEPS_STATE="$HOME/state" BVK_DEPS_LOG="$HOME/log"; export PATH="$HOME/fakebin:$PATH"\n'
            'bash bashbasicsbyvk_deps.sh -c "Fake feature" fake.feature; echo "RC=$?"; command -v bvkfakedep >/dev/null && echo FOUND || echo NOTFOUND\n')

def make2(home, work):
    binp = os.path.join(os.path.dirname(home), 'bin'); fake = os.path.join(home, 'fakebin'); os.makedirs(fake)
    open(os.path.join(home, 'reg.list'), 'w').write('D|bvkfakedep|cmd|bvkfakedep|*=bvkfakedep|Fake tool|for the test|||\nF|fake.feature|Fake feature|bvkfakedep|\n')
    ap = os.path.join(fake, 'apt-get')
    open(ap, 'w').write('#!/bin/sh\necho "apt-get $*" >> "%s/apt.log"\nprintf "#!/bin/sh\\n" > "%s/bvkfakedep"; chmod +x "%s/bvkfakedep"\n' % (home, fake, fake)); os.chmod(ap, 0o755)
    open(os.path.join(binp, 'dep_driver.sh'), 'w').write(driver_body())

for answer, key, rc, found in (('yes', b'y\r', 'RC=0', 'FOUND'), ('no', b'n\r', 'RC=1', 'NOTFOUND')):
    a = App(root, 100, 30, make2, boot=True)
    t = a.text()
    check(f'[{answer}] the box is the shared choice menu (title, Yes/No rows, Select:)', 'Installer' in t and 'Yes' in t and 'No' in t and 'Select:' in t and 'Do you want to install them?' in t, t)
    check(f'[{answer}] the list names the dependency and the command', 'Fake tool' in t and 'apt-get install -y bvkfakedep' in t, t)
    a.send(key, until=lambda: 'FOUND' in a.text())
    t = a.text()
    check(f'[{answer}] answer -> {rc} / {found}', rc in t and found in t.replace('NOTFOUND', 'NOT_FOUND') if found == 'FOUND' else (rc in t and 'NOTFOUND' in t), t)
    a.close()
sys.exit(0 if all(res) else 1)
