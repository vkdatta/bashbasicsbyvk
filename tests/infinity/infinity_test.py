"""The Infinity Stones tools are part of the app: a question inside any of them has the app's hint row, cc and u / q.
Git Push (bash function), Localhost (bash function) and Generate SQL (python worker whose questions the app asks) are driven in the real app.
usage: python3 infinity_test.py [only-substring]"""
import os, sys, subprocess
here = os.path.dirname(os.path.abspath(__file__)); root = os.path.abspath(os.path.join(here, '..', '..'))
sys.path.insert(0, os.path.join(root, 'tests', 'paste_input')); from ptyapp import PtyApp
only = sys.argv[1] if len(sys.argv) > 1 else ''
FAKE_GH = r"""#!/bin/sh
case "$1 $2" in
  "auth status"|"auth setup-git") exit 0;;
  "api user") echo tester; exit 0;;
  "repo view") case "$*" in *isEmpty*) printf 'false\tmain\thttps://github.com/tester/work\n';; *) echo work;; esac; exit 0;;
esac
exit 0
"""

def populate(home, work):
    binp = os.path.join(os.path.dirname(home), 'bin')
    open(os.path.join(binp, 'gh'), 'w').write(FAKE_GH); os.chmod(os.path.join(binp, 'gh'), 0o755)
    bare = os.path.join(home, 'remote.git')
    g = lambda *a, cwd=work: subprocess.run(['git', *a], cwd=cwd, check=True, capture_output=True)
    g('init', '--bare', bare, cwd=home); g('init', '-b', 'main'); g('config', 'user.email', 't@t'); g('config', 'user.name', 't')
    open(os.path.join(work, 'a.txt'), 'w').write('x'); g('add', '.'); g('commit', '-m', 'first'); g('remote', 'add', 'origin', bare); g('push', '-u', 'origin', 'main')
    open(os.path.join(work, 'a.txt'), 'w').write('changed')

fails = 0
def check(name, fn):
    global fails
    if only and only not in name: return
    a = PtyApp(root, 100, 45, populate)
    try:
        a.line('i', until=lambda: 'Infinity Stones' in a.text()); a.settle(0.5)
        ok, why = fn(a)
    except Exception as e: ok, why = False, repr(e)
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '   [' + why + ']'))
    if not ok: fails += 1; print('   ' + '\n   '.join(l for l in a.lines() if l.strip())[-1500:])
    a.close()

def last(a, n): return '\n'.join(l for l in a.lines() if l.strip())[-n:]

def t_localhost(a):
    a.line('6'); a.wait_text('Enter localhost port', 12); a.settle(0.5)
    if 'cc) Cheat codes' not in a.text(): return False, 'no hint row with cc) at the port question'
    if 'Working on' in a.text(): return False, 'the loading bar stayed on the screen'
    a.line('cc'); a.wait_text('Cheat codes', 8)
    if 'Cheat codes' not in a.text(): return False, 'cc did nothing at the port question'
    a.line('u'); a.settle(0.8)
    if not a.text().rstrip().endswith('Enter localhost port:') and 'Enter localhost port' not in last(a, 300): return False, 'u from the cc list did not come back to the question'
    a.line('u'); a.settle(1.0)
    t = last(a, 700)                        # the tool ended (as before, the menu closes after a tool): the main list is back, no question is pending
    return ('Operation cancelled' in t and t.rstrip().endswith('Select:')), 'u at the first question did not leave the tool'

def t_gen_sql(a):
    a.line('5'); a.wait_text('Enter file name', 12); a.settle(0.5)
    if 'cc) Cheat codes' not in a.text(): return False, 'a python question has no hint row with cc)'
    a.line('cc'); a.wait_text('Cheat codes', 8)
    if 'Cheat codes' not in a.text(): return False, 'cc did nothing at a python question'
    a.line('u'); a.settle(0.8)
    return 'Enter file name' in last(a, 300), 'u from the cc list did not come back to the python question'

def t_gitpush(a):
    a.line('4'); a.wait_text('Select version bump type', 20); a.settle(0.6)
    if 'Patch' not in a.text(): return False, 'the version menu did not open'
    a.line('cc'); a.wait_text('Cheat codes', 8)
    if 'Cheat codes' not in a.text(): return False, 'cc did nothing in the version menu'
    a.line('u'); a.settle(0.8)
    if 'Patch' not in last(a, 400): return False, 'u from the cc list did not come back to the version menu'
    a.line('1'); a.wait_text('Enter commit message', 10); a.settle(0.6)
    if 'cc) Cheat codes' not in last(a, 400): return False, 'the commit-message question has no hint row with cc)'
    a.line('cc'); a.wait_text('Cheat codes', 8)
    if 'Cheat codes' not in last(a, 1500): return False, 'cc did nothing at the commit-message question'
    a.line('u'); a.settle(0.8); a.line('u'); a.settle(1.0)      # u: back to the message question, u: back to the version question
    return 'Select version bump type' in last(a, 700), 'u at the message question did not go back one question'

def t_localhost_q(a):
    a.line('6'); a.wait_text('Enter localhost port', 12); a.settle(0.5)
    a.line('q'); a.settle(1.0)
    t = last(a, 700)                        # q closes up to the main loop: the main list is back, no question and no Infinity menu is pending
    return (t.rstrip().endswith('Select:') and 'Enter localhost port: q' not in t.splitlines()[-1]), 'q at the port question did not close to the main list'

def t_localhost_badport(a):
    a.line('6'); a.wait_text('Enter localhost port', 12); a.settle(0.5)
    a.line('abc'); a.settle(1.0)
    return 'Invalid port' in last(a, 700), 'a non-numeric port was not refused'

def t_gitpush_q(a):
    a.line('4'); a.wait_text('Select version bump type', 20); a.settle(0.6)
    a.line('1'); a.wait_text('Enter commit message', 10); a.settle(0.6)
    a.line('q'); a.settle(1.2)
    t = last(a, 700)
    return (t.rstrip().endswith('Select:') and 'Enter commit message' not in t.splitlines()[-1]), 'q at the commit message did not close to the main list (or was committed as text)'

check('Localhost: hint row, cc, u', t_localhost)
check('Localhost: q closes to the main list', t_localhost_q)
check('Localhost: a bad port is refused', t_localhost_badport)
check('Git Push: q at the commit message closes, is not text', t_gitpush_q)
check('Generate SQL (python): hint row, cc, u', t_gen_sql)
check('Git Push: cc and u at every question', t_gitpush)
print('ALL OK' if not fails else '%d FAILED' % fails); sys.exit(1 if fails else 0)
