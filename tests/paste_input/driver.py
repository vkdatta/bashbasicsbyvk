"""Pastes a text into a real input loop of the app (in a pty) the way a terminal does: ONE write, optionally wrapped in the
bracketed-paste markers.  Reports how often the input row was redrawn, whether Enter was (wrongly) triggered, and the result.
python3 driver.py <repo-root> <editor> <bracketed 0|1> <textfile> [then-enter 0|1]"""
import os, pty, sys, time, select, re
root, ed, brk, tf = sys.argv[1], sys.argv[2], sys.argv[3] == '1', sys.argv[4]
enter = len(sys.argv) > 5 and sys.argv[5] == '1'
text = open(tf, encoding='utf-8').read()
here = os.path.dirname(os.path.abspath(__file__))
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8', COLUMNS='80', LINES='24')
    os.execvp('bash', ['bash', os.path.join(here, 'harness.sh'), root, ed])
import fcntl, termios, struct
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
out = b''
def pump(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 1 << 20)
            except OSError: return
            if not d: return
            out += d
pump(1.5)
mark = len(out)
data = text.encode('utf-8')
if brk: data = b'\x1b[200~' + data + b'\x1b[201~'
t0 = time.time()
# one write = what a terminal does with a paste (the pty buffer is 4 KB: feed in order as fast as it takes)
i = 0
while i < len(data):
    try: n = os.write(fd, data[i:i + 4096])
    except BlockingIOError: n = 0
    i += n
    pump(0.002)
pump(2.0 if len(data) < 20000 else 6.0)
after_paste = out[mark:]
finished = b'DONE' in out
redraws = after_paste.count(b'\r\x1b[K') + after_paste.count(b'\x1b[J')
if enter:
    os.write(fd, b'\r'); pump(2.0)
s = out.decode('utf-8', 'replace')
m = re.search(r'RESULT=\[(.*)\]\s*DONE', s, re.S)
print('FINISHED_BEFORE_ENTER=%d' % (1 if (finished and not enter) else 0))
print('REDRAWS=%d' % redraws)
print('SECS=%.2f' % (time.time() - t0))
print('RESULT_LEN=%s' % (len(m.group(1)) if m else -1))
if m: open(os.environ.get('RESULT_OUT', '/dev/null'), 'w').write(m.group(1))
