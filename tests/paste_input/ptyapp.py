"""Shared driver of the real-app pty tests (mouse/mouse_test.py, nav_back/nav_test.py, hints/hint_test.py, paste_input/ui_test.py).
One place for: the temp `bin/` of symlinks to every script (the install lays them out flat), the pty launch of `o`, pump / send / line.
A test subclasses PtyApp, sets its timings and builds its own HOME/work files in `populate`; everything else is shared.
(vt.py = the tiny terminal emulator that renders what the app prints.)"""
import os, pty, time, select, fcntl, termios, struct, tempfile, shutil, signal, shlex
from vt import Screen

# WAIT, DON'T SLEEP (the rule of every test, see AGENTS.md "Tests"):  the app is driven by what it SHOWS, not by a guessed time.
#   a.wait(lambda: cond, timeout)   poll the screen until cond() is true; on timeout it returns False and the test prints the screen
#   a.wait_text("Select:")          until the text is on the screen
#   a.send(keys)                    write, then wait for the app's reaction: first output, then `quiet` seconds of silence (the old
#                                   `t` is now only the CEILING, so a fast app costs milliseconds and a slow one is never cut short)
#   a.send(keys, until=cond)        write, then wait until cond() holds (preferred whenever the test asserts what must appear)
#   a.send(keys, t, hold=True)      write, then watch for exactly t seconds - ONLY for "nothing may happen" checks
#   a.settle()                      wait until the output has been silent for `quiet` seconds


def link_scripts(root, binp):
    """Symlink every file under <root>/script flat into binp (like setup.py installs them); bvk-ls (C sources) is skipped."""
    for dp, dn, fn in os.walk(os.path.join(root, 'script')):
        if 'bvk-ls' in dp: continue
        for f in fn:
            if not os.path.exists(os.path.join(binp, f)): os.symlink(os.path.join(dp, f), os.path.join(binp, f))


FACTOR = float(os.environ.get('TEST_TIME_FACTOR', '1') or 1)   # set by tests/run.sh on an oversubscribed machine: every wait / quiet window is stretched (costs nothing when the app answers)

def find_script(root, name):
    """path of a script file found BY NAME under root/script (files move between folders; a test must not hard-code where)"""
    for dp, dn, fn in os.walk(os.path.join(root, 'script')):
        if name in fn: return os.path.join(dp, name)
    raise FileNotFoundError('no script file named %s under %s/script' % (name, root))


class PtyApp:
    select_t = 0.02        # pump(): how long one select() waits for output
    send_t = 0.7           # send(): CEILING of the wait for the app's reaction (it returns as soon as the app went quiet)
    quiet = 0.15           # seconds of silence that mean "the app finished drawing"
    boot_timeout = 15      # the app must show its prompt within this time or the test fails (it does not sleep 4 s blindly)
    ready_text = 'Select:' # what the app shows when it waits for input
    entry = 'o'            # the script run with bash (found in the temp bin/)

    def __init__(self, root, cols, rows, populate, env=None, answer_dsr=False, boot=True):
        """populate(home, work) fills the temp HOME / work dir. env: extra environment for the app.
        answer_dsr: answer the cursor-position query ESC[6n the way a real terminal does."""
        self.tmp = tempfile.mkdtemp(); binp = os.path.join(self.tmp, 'bin'); os.makedirs(binp)
        link_scripts(root, binp)
        home = os.path.join(self.tmp, 'home'); work = os.path.join(home, 'work'); os.makedirs(work)
        self.work = work
        populate(home, work)
        self.seed_telemetry(home)
        self.answer_dsr = answer_dsr; self.raw = b''
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            e = dict(TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8', HOME=home, COLUMNS=str(cols), LINES=str(rows),
                     PATH=binp + ':' + os.environ['PATH'], BVK_BROWSER_TERM='0'); e.update(env or {})   # a value of None removes the variable
            [os.environ.pop(k, None) for k, v in e.items() if v is None]; os.environ.update({k: v for k, v in e.items() if v is not None}); os.chdir(work); os.execvp('bash', ['bash', os.path.join(binp, self.entry)])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
        self.scr = Screen(cols, rows); self.alive = True
        self.booted = self.wait_text(self.ready_text, self.boot_timeout) if boot else True
        if not self.booted:                          # fail loudly, with the screen, instead of letting every later check fail mysteriously
            raise AssertionError('the app did not show %r within %ss; screen:\n%s' % (self.ready_text, self.boot_timeout * FACTOR, '\n'.join(l for l in self.lines() if l.strip())))
        if boot: self.settle()

    @staticmethod
    def seed_telemetry(home):
        """The app pings its telemetry server once a day (no off switch, by design). The test marks today as already reported, exactly as a
        real first ping would, so no test ever waits on or talks to the network. (VK_TELEMETRY=0 does nothing: the app ignores it.)"""
        d = os.path.join(home, '.config', 'bashbasicsbyvk', 'telemetry'); os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'uuid'), 'w') as f: f.write('00000000-0000-4000-8000-000000000000\n')
        with open(os.path.join(d, 'daily'), 'w') as f: f.write('%s true\n' % time.strftime('%Y-%m-%d', time.gmtime()))

    def _drain(self, slice_t):
        """read what the app printed within slice_t seconds; returns the number of bytes (0 = silence)"""
        if not self.alive: return 0
        r, _, _ = select.select([self.fd], [], [], slice_t)
        if not r: return 0
        try: d = os.read(self.fd, 1 << 20)
        except OSError: self.alive = False; return 0
        if not d: self.alive = False; return 0
        self.raw += d; self.scr.feed(d)
        if self.answer_dsr and b'\x1b[6n' in d:                              # the terminal answers a cursor-position query
            row, col = self.scr.cursor
            try: os.write(self.fd, b'\x1b[%d;%dR' % (row + 1, col + 1))
            except OSError: pass
        return len(d)

    def busy(self):
        """True while any process of the app's session is running or in disk wait (Linux /proc): the app is computing, silence is not "done".
        A loaded machine makes the app slow, not wrong; without /proc this is False and only the quiet window counts."""
        sid = str(self.pid)
        try: names = os.listdir('/proc')
        except OSError: return False
        for d in names:
            if not d.isdigit(): continue
            try:
                with open('/proc/%s/stat' % d) as f: st = f.read()
                rest = st[st.rindex(')') + 2:].split()
            except (OSError, ValueError): continue
            if len(rest) > 3 and rest[3] == sid and rest[0] in ('R', 'D'): return True
        return False

    def _reap(self):
        try:
            p, _ = os.waitpid(self.pid, os.WNOHANG)
            if p: self.alive = False
        except ChildProcessError: self.alive = False

    def wait(self, cond, timeout=8.0):
        """poll cond() (looking at the screen) until it is true; False after `timeout` s (the test then prints the screen: a live failure)"""
        timeout *= FACTOR; end = time.time() + timeout; self.waited = 0.0; t0 = time.time()
        while True:
            try:
                if cond(): self.waited = time.time() - t0; return True
            except Exception: pass
            if time.time() >= end or not self.alive:
                try: return bool(cond())
                except Exception: return False
            if not self._drain(min(self.select_t, max(0.0, end - time.time()))): self._reap()

    def wait_text(self, text, timeout=8.0): return self.wait(lambda: text in self.text(), timeout)

    def settle(self, quiet=None, ceiling=None):
        """return once the app has printed nothing for `quiet` seconds (or the ceiling passed)"""
        q = (self.quiet if quiet is None else quiet) * FACTOR; end = time.time() + (ceiling if ceiling is not None else 10.0) * FACTOR; last = time.time()
        while time.time() < end and self.alive:
            if self._drain(self.select_t): last = time.time()
            elif time.time() - last >= q and not self.busy(): break
            else: self._reap()

    def react(self, ceiling, quiet=None):
        """wait for the app's reaction to what was just sent: its first output, then silence. Never longer than `ceiling`."""
        q = (self.quiet if quiet is None else quiet) * FACTOR
        end = time.time() + ceiling * FACTOR; got = False; last = time.time()
        while time.time() < end and self.alive:
            if self._drain(self.select_t): got = True; last = time.time()
            elif got and time.time() - last >= q and not self.busy(): return True
            else: self._reap()
        return got

    def pump(self, t):  # watch the app for exactly t seconds (a deliberate hold; prefer wait / settle / send(until=))
        end = time.time() + t
        while time.time() < end and self.alive: self._drain(min(self.select_t, max(0.0, end - time.time())))
        self._reap()

    def send(self, s, t=None, until=None, hold=False, timeout=8.0, quiet=None):
        """write s, then wait for the reaction (see the header). t = ceiling of that wait (default send_t)."""
        if isinstance(s, str): s = s.encode()
        try: os.write(self.fd, s)
        except OSError: self.alive = False; return False
        ceil = self.send_t if t is None else t
        if until is not None: return self.wait(until, timeout)
        if hold: self.pump(ceil); return True
        return self.react(ceil, quiet)

    def line(self, text, t=1.2, until=None): self.send(text, 0.15); return self.send(b'\r', t, until=until)
    def lines(self): return self.scr.lines()
    def text(self): return '\n'.join(self.lines())

    def close(self):
        try: os.kill(self.pid, signal.SIGKILL); os.waitpid(self.pid, 0)
        except Exception: pass
        # the app starts background helpers (recents daemon, watchers) that only stop when the app says goodbye; killing the app leaves them running
        # (hundreds of them ate all memory and made every later test time out), so everything started from this app's temp dir is stopped with it
        os.system('pkill -f %s >/dev/null 2>&1' % shlex.quote(self.tmp))
        shutil.rmtree(self.tmp, ignore_errors=True)
