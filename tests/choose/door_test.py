"""bashbasicsbyvk_choose: THE one-of-many question of every tool that runs as its own process (AGENTS.md rule 18).
 1. a number + Enter returns that row's key on stdout (exit 0); a bare Enter takes the -d default row
 2. u with -b exits 4, without -b exits 2; q exits 2; -m returns the ticked keys
 3. the python door (bashbasicsbyvk_choose.ask) returns the key / raises EOFError / Back
 4. gitpush's version question is the door (no hand-drawn rows left in the tool)
usage: python3 tests/choose/door_test.py"""
import os, pty, re, select, shutil, sys, tempfile, time
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SCRIPT = os.path.join(ROOT, 'script')
ok = True
def check(name, cond, detail=''):
    global ok; ok &= bool(cond); print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else '  ' + str(detail)[-300:]))

flat = tempfile.mkdtemp(prefix='choose_flat_')
for dp, _, fs in os.walk(SCRIPT):
    for f in fs:
        if not f.endswith('.pyc') and not os.path.exists(os.path.join(flat, f)): os.symlink(os.path.join(dp, f), os.path.join(flat, f))

def run(cmd, keys, wait_for='Select:'):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['PATH'] = flat + ':' + os.environ['PATH']; os.environ['TERM'] = 'xterm-256color'
        os.environ['PYTHONPATH'] = flat; os.execvp('bash', ['bash', '-c', cmd])
    out = b''; sent = 0; t = time.time()
    while time.time() - t < 15:
        if select.select([fd], [], [], 0.1)[0]:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
        elif sent < len(keys) and wait_for.encode() in out:
            os.write(fd, keys[sent].encode()); sent += 1; time.sleep(0.15)
    try: os.waitpid(pid, os.WNOHANG)
    except OSError: pass
    return re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', out.decode('utf-8', 'replace'))

ROWS = '"1:One" "2:Two" "3:Three"'
def door(flags, keys): return run(f'a=$(bashbasicsbyvk_choose "Pick" {flags} {ROWS}); echo "RC=$? ANS=[$a]"', keys)
o = door('', ['2\r']);            check('a number picks that row (key on stdout, exit 0)', 'RC=0 ANS=[2]' in o, o)
o = door('-d 3', ['\r']);         check('a bare Enter takes the -d default row', 'RC=0 ANS=[3]' in o, o)
o = door('-b', ['u\r']);          check('u with -b exits 4 (one question back)', 'RC=4' in o, o)
o = door('', ['u\r']);            check('u without -b exits 2', 'RC=2' in o, o)
o = door('', ['q\r']);            check('q exits 2', 'RC=2' in o, o)
o = run('a=$(bashbasicsbyvk_choose "Which?" -m "a:Alpha" "b:Beta" "c:Gamma"); echo "RC=$? ANS=[$a]"', ['1\r', '3\r', 'd\r'])
check('-m returns the ticked keys', 'RC=0 ANS=[a c]' in o, o)
R5 = '"1:A" "2:B" "3:C" "4:D" "5:E"'
for typed, want in (('a-2', '1 3 4 5'), ('a', '1 2 3 4 5'), ('2-4', '2 3 4'), ('1,3-4', '1 3 4')):
    o = run(f'a=$(bashbasicsbyvk_choose "Which?" -m {R5}); echo "RC=$? ANS=[$a]"', [typed + '\r', 'd\r'])
    check(f"-m takes the app's selection grammar: {typed}", f'RC=0 ANS=[{want}]' in o, o)
o = run('bashbasicsbyvk_choose "Only one" "1:Alone"; echo "RC=$?"', [], wait_for='RC=')
check('fewer than two rows is a usage error (exit 3)', 'RC=3' in o, o)
py = ('import bashbasicsbyvk_choose as c\n'
      'try:\n    print("PY", repr(c.ask("Pick", [("1","One"),("2","Two")], default="1")))\n'
      'except EOFError:\n    print("PY EOF")\n')
open(os.path.join(flat, 'pyprobe.py'), 'w').write(py)
o = run('python3 ' + os.path.join(flat, 'pyprobe.py'), ['2\r']); check('python door returns the key', "PY '2'" in o, o)
o = run('python3 ' + os.path.join(flat, 'pyprobe.py'), ['q\r']); check('python door raises EOFError on q', 'PY EOF' in o, o)
g = open(os.path.join(SCRIPT, 'file/infinity/tools/bashbasicsbyvk_gitpush')).read()
check('gitpush asks the version through the door', 'bashbasicsbyvk_choose' in g and 'echo "1) Patch' not in g)
shutil.rmtree(flat, ignore_errors=True)
print('ALL OK' if ok else 'FAILED'); sys.exit(0 if ok else 1)
