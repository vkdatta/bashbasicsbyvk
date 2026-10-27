"""loadmap: the first paint of a folder with a .shortcut calls _shortcut_read_field (transfer.sh, a [bg] file): the stubs must already be there.
Runs `o` in a pty from such a folder; it must print no "command not found" and show the shortcut.   python3 tests/loadmap/shortcut_paint.py <repo root>"""
import os, pty, sys, select, time, tempfile, signal, shutil, fcntl, termios, struct
root = sys.argv[1]
T = tempfile.mkdtemp(); B = T + '/bin'; os.mkdir(B); H = T + '/home'; os.mkdir(H); W = T + '/work'; os.mkdir(W)
for dp, dn, fn in os.walk(root + '/script'):
    if 'bvk-' in dp: continue
    for f in fn:
        d = os.path.join(B, f)
        if not os.path.exists(d): os.symlink(os.path.join(dp, f), d)
open(W + '/link.shortcut', 'w').write('SHORTCUT_TYPE=folder\nSHORTCUT_NAME=mylink\nSHORTCUT_TARGET=/tmp\n')
open(W + '/a.txt', 'w').write('x')
env = dict(os.environ, HOME=H, TERM='xterm-256color', LANG='C.UTF-8', PATH=B + ':' + os.environ['PATH'], COLUMNS='80', LINES='30')
pid, fd = pty.fork()
if pid == 0:
    os.chdir(W); os.execvpe('bash', ['bash', B + '/o'], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 30, 80, 0, 0))
out = b''; end = time.time() + 12
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: d = os.read(fd, 65536)
        except OSError: break
        out += d
os.kill(pid, signal.SIGKILL)
t = out.decode('utf-8', 'replace')
shutil.rmtree(T, ignore_errors=True)
nf = t.count('command not found')
if nf == 0 and 'mylink' in t: print('  ok   first paint with a .shortcut: no "command not found", the shortcut is listed'); sys.exit(0)
print('  FAIL first paint with a .shortcut: %d x "command not found", shortcut listed: %s' % (nf, 'mylink' in t))
for l in t.split('\n'):
    if 'not found' in l: print('       ', l.strip()[:160])
sys.exit(1)
