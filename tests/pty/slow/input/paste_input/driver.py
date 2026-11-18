"""Pastes a text into a real input loop of the app (in a pty) the way a terminal does: ONE write, optionally wrapped in the
bracketed-paste markers.  Reports how often the input row was redrawn, whether Enter was (wrongly) triggered, and the result.
python3 driver.py <repo-root> <editor> <bracketed 0|1> <textfile> [then-enter 0|1]"""
import os, pty, sys, time, select, re
F = float(os.environ.get('TEST_TIME_FACTOR', '1') or 1)   # stretches every wait on an oversubscribed machine (see tests/run.sh)
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
def pump(t, stop=None):
    """read for at most t seconds (stop() ends it early: a condition, not a guess). False = the app ended."""
    global out
    end = time.time() + t
    while True:
        left = end - time.time()
        if left <= 0: return True
        r, _, _ = select.select([fd], [], [], min(0.02, left))       # (the old 50 ms select made every 4 KB chunk of a paste cost 50 ms)
        if r:
            try: d = os.read(fd, 1 << 20)
            except OSError: return False
            if not d: return False
            out += d
        if stop and stop(): return True
def settle(quiet=0.4, ceiling=8.0):
    quiet *= F; ceiling *= F
    """until the app printed nothing for `quiet` seconds (it may compute silently for a moment, hence 0.4 s)"""
    global out
    last = len(out); since = time.time(); end = time.time() + ceiling
    while time.time() < end:
        pump(0.02)
        if len(out) != last: last = len(out); since = time.time()
        elif time.time() - since >= quiet: return
# ready = every editor switches bracketed paste on (ESC[?2004h) once it reads keys in raw mode
pump(15 * F, lambda: b'\x1b[?2004h' in out); settle(0.1, 2)
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
settle(0.4, 3.0 if len(data) < 20000 else 10.0)
after_paste = out[mark:]
finished = b'DONE' in out
redraws = after_paste.count(b'\r\x1b[K') + after_paste.count(b'\x1b[J')
if enter:
    # an Enter that lands inside the app's end-of-paste window is swallowed on purpose (events still in flight after a paste are never typed),
    # so Enter is repeated until the editor answers - the wait ends the moment DONE shows, and a missing DONE is reported below
    for _ in range(8):
        os.write(fd, b'\r'); pump(1.0 * F, lambda: b"DONE" in out)
        if b"DONE" in out: break
    settle(0.1, 1.0)
s = out.decode('utf-8', 'replace')
m = re.search(r'RESULT=\[(.*)\]\s*DONE', s, re.S)
print('FINISHED_BEFORE_ENTER=%d' % (1 if (finished and not enter) else 0))
print('REDRAWS=%d' % redraws)
print('SECS=%.2f' % (time.time() - t0))
print('RESULT_LEN=%s' % (len(m.group(1)) if m else -1))
if m: open(os.environ.get('RESULT_OUT', '/dev/null'), 'w').write(m.group(1))
elif enter: print('NO_RESULT: the editor never printed RESULT/DONE; last output: %r' % s[-400:])      # the failure is shown at once, not guessed from a timeout
