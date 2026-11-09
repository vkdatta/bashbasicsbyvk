"""Every yes/no question is the app's NATIVE menu - also in the tools that run as their own process (bash or python).
 1. bashbasicsbyvk_yn: Yes -> 0, No -> 1, a bare Enter is not an answer, q -> 2 (no answer, never silently "no" for git push).
 2. the converted tools (erase, delete, git push's ask_yn) show the menu and act on the answer.
 3. LINT: a plain y/n prompt (read -p "... (y/n)", input("... (y/n)"), "Type 'yes'") may exist only in a file that also asks the native menu
    (that plain line is the fallback of a broken install).  A new bare prompt anywhere else fails here.
usage: python3 tests/yn/yn_test.py"""
import os, re, sys, pty, time, select, tempfile, shutil, glob
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SCRIPT = os.path.join(ROOT, 'script')
ok = True
def check(name, cond, detail=''):
    global ok; ok &= bool(cond); print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else '  ' + str(detail)[:300]))

flat = tempfile.mkdtemp(prefix='yn_flat_'); work = tempfile.mkdtemp(prefix='yn_work_')
for dp, _, fs in os.walk(SCRIPT):                                  # the flat install: every script next to each other on PATH
    for f in fs:
        if not f.endswith('.pyc'): os.symlink(os.path.join(dp, f), os.path.join(flat, f)) if not os.path.exists(os.path.join(flat, f)) else None
def run(args, keys):
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(work); os.environ['PATH'] = flat + ':' + os.environ['PATH']; os.environ['TERM'] = 'xterm-256color'
        os.execvp('bash', ['bash'] + args)
    out = b''
    def pump(t, stop):                                  # t = ceiling; returns as soon as stop() holds (never a blind sleep)
        nonlocal out, eof
        end = time.time() + t
        while time.time() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try: out += os.read(fd, 65536)
                except OSError: eof = True; return
            if stop(): return
    def exited():
        nonlocal done
        if done is None:
            r, st = os.waitpid(pid, os.WNOHANG)
            if r: done = os.waitstatus_to_exitcode(st)
        return done is not None
    done = None; eof = False
    pump(8, lambda: b'Select:' in out or exited())      # the menu is drawn
    for k in keys:
        n = len(out); os.write(fd, k)
        pump(4, lambda: len(out) > n or exited())       # the key was answered with output (or the tool ended)
    pump(4, stop=exited)
    if done is None and eof: _, st = os.waitpid(pid, 0); done = os.waitstatus_to_exitcode(st)       # the pty closed: the tool is ending
    rc = done
    if rc is None: os.kill(pid, 9); os.waitpid(pid, 0); rc = 'HUNG'
    return rc, re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', out).decode(errors='replace')
YN = os.path.join(flat, 'bashbasicsbyvk_yn')
for keys, want, what in (([b'y', b'\r'], 0, 'Yes'), ([b'n', b'\r'], 1, 'No'), ([b'\r', b'n', b'\r'], 1, 'a bare Enter is not an answer (then No)'), ([b'q', b'\r'], 2, 'q = no answer')):
    rc, o = run([YN, 'Make repository private?', '-t', 'Git push', '-i', '🚀'], keys)
    check('bashbasicsbyvk_yn: ' + what, rc == want and 'Select:' in o and 'Yes' in o and 'No' in o, (rc, o[-200:]))
f = os.path.join(work, 'f.txt')
for ans, left in ((b'n', 'data'), (b'y', '')):
    open(f, 'w').write('data'); rc, o = run([os.path.join(flat, 'bashbasicsbyvk_erase'), 'f.txt'], [ans, b'\r'])
    check('erase answers ' + ans.decode() + ' through the native menu', open(f).read() == left and 'Select:' in o and '(yes/no)' not in o, (rc, o[-200:]))
for ans, exists in ((b'n', True), (b'y', False)):
    open(f, 'w').write('x'); rc, o = run([os.path.join(flat, 'bashbasicsbyvk_delete'), 'f.txt'], [ans, b'\r'])
    check('delete answers ' + ans.decode() + ' through the native menu', os.path.exists(f) == exists and 'Select:' in o and "Type 'yes'" not in o, (rc, o[-200:]))
src = open(os.path.join(SCRIPT, 'file/infinity/tools/bashbasicsbyvk_gitpush')).read()
a, b = src.index('ask_yn() {'), src.index('ask_repo_visibility()')
open(os.path.join(work, 'ask.sh'), 'w').write('set -Eeuo pipefail\ndie(){ echo "DIE: $*" >&2; exit 1; }\n' + src[a:b] + '\nask_yn "Make repository private?"; echo "ANS=$ANS"\n')
for ans, want in ((b'y', 'ANS=y'), (b'n', 'ANS=n'), (b'q', 'DIE: No answer')):
    rc, o = run([os.path.join(work, 'ask.sh')], [ans, b'\r'])
    check('git push ask_yn ' + ans.decode() + ' -> ' + want + ' (quitting never answers "public")', want in o and '[y/n]' not in o, (rc, o[-200:]))
# 3. lint: a plain y/n prompt only next to the native menu
PLAIN = re.compile(r"""(read\b[^\n]*(\(y/n\)|\[y/n\]|\(Y/N\)|\[yes/no\]|\(yes/no\)|Type 'yes'))|(input\([^\n]*\(y/n\))|(echo -n [^\n]*\(yes/no\))|(tty\.write\([^\n]*\(y/n\))""", re.I)
bad = []
for dp, _, fs in os.walk(SCRIPT):
    for fn in fs:
        p = os.path.join(dp, fn)
        if fn.endswith(('.pyc', '.png', '.zip')) or 'loadmap_stubs' in fn: continue
        try: t = open(p, encoding='utf-8').read()
        except (UnicodeDecodeError, OSError): continue
        if PLAIN.search(t) and not re.search(r'bashbasicsbyvk_yn|_bvk_yn', t): bad.append(os.path.relpath(p, SCRIPT))
check('lint: no bare y/n prompt without the native menu beside it', not bad, bad)
shutil.rmtree(flat, ignore_errors=True); shutil.rmtree(work, ignore_errors=True)
sys.exit(0 if ok else 1)
