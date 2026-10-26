"""smartload: the loading bar that appears by itself (AGENTS rule 7).   python3 tests/smartload/pty_test.py <repo root>
Each scenario is a bash snippet run in a real pty (or in pipes); what the app wrote to the terminal is checked as raw bytes:
the bar is the glyph '░', drawn ON the cursor's own row (the cursor is hidden while it shows); a wipe is  ESC [ K ESC [ ? 25 h  (erase to the end of the row, show the cursor).
The sleeps inside the snippets ARE the behaviour under test (the grace timer), so they carry  # lint-wait-ok."""
import os, pty, sys, select, time, subprocess, signal, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'paste_input'))
from vt import Screen          # the shared VT emulator (tests/paste_input/vt.py): where on the screen did the bar land?
ROOT = sys.argv[1]
SL = f'{ROOT}/script/file/engine/bashbasicsbyvk_smartload.sh'
F = float(os.environ.get('TEST_TIME_FACTOR', '1') or 1)
GRACE_MS = 400
WIPE = '\x1b[K\x1b[?25h'
PRE = f'_lt_b(){{ :; }}; _lt_e(){{ :; }}; _lt_enter(){{ :; }}; _lt_ready(){{ :; }}; source "{SL}"; '
fail = 0
def ok(m):  print('  ok  ', m)
def bad(m):
    global fail; fail = 1; print('  FAIL', m)

def run_pty(snippet, env=None, deadline=40):
    e = dict(os.environ, VK_SMARTLOAD_GRACE_MS=str(GRACE_MS), TERM='xterm-256color'); e.update(env or {})
    e = {k: v for k, v in e.items() if v is not None}      # an env value of None = leave that variable out
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe('bash', ['bash', '-c', PRE + snippet], e)
    out = b''; end = time.time() + deadline * F
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
        else:
            done, _ = os.waitpid(pid, os.WNOHANG)
            if done: break
    else:
        os.kill(pid, signal.SIGKILL)
    try: os.waitpid(pid, 0)
    except ChildProcessError: pass
    return out.decode('utf-8', 'replace')

def check(cond, good, why):
    ok(good) if cond else bad(why)
def has_bar(s): return '░' in s

# 1) a long wait gets a bar by itself, and it is wiped before the next prompt
o = run_pty('_sl_ready; _sl_enter "" "" "Testing bar"; sleep 1.6; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
i, w, e = o.find('░'), o.find(WIPE), o.find('MARK_END')
if i >= 0 and 'Testing bar' in o and '█' in o: ok('a wait longer than the grace period shows the bar with its label')
else: bad(f'no bar for a long wait: {o[-200:]!r}')
if i >= 0 and w > i and e > w: ok('the bar is wiped (erase to the end of the row, cursor shown again) before the next output')
else: bad(f'no wipe between the bar and the next output (bar@{i} wipe@{w} end@{e})')
if '\x1b7' in o and '\x1b8' in o: ok('it is drawn with save / restore cursor: the typed text and the column are untouched')
else: bad('the bar does not use save / restore cursor')

# 1b) the bar takes the CURSOR's place: it is drawn on the cursor's own row, never on the row below it
o = run_pty("printf 'Select: 12\\n'; _sl_ready; _sl_enter '' '' 'Row check'; sleep 1.6; printf 'MARK'")   # lint-wait-ok: the wait is the behaviour under test
pre = o.split('MARK')[0]
scr = Screen(60, 10); scr.feed(pre.encode('utf-8')); rows = [i for i, l in enumerate(scr.lines()) if '░' in l]
check((rows == [scr.r] and scr.lines()[scr.r - 1].startswith('Select: 12')), 'the bar is on the cursor row (the row the person would type on), not below it', f'bar rows {rows}, cursor row {scr.r}: {scr.lines()[:5]!r}')
check(('\x1b[?25l' in pre and '\x1b[1B' not in pre and '\x1b[?7l' in pre), 'the cursor is hidden while the bar shows, the row below is never used, auto-wrap is off', f'wrong draw sequence: {pre[-160:]!r}')
o = run_pty("printf 'Select: 12\\n'; _sl_ready; _sl_enter '' '' 'Row check'; sleep 1.6; _sl_ready; printf 'MARK'")   # lint-wait-ok: the wait is the behaviour under test
scr = Screen(60, 10); scr.feed(o.split('MARK')[0].encode('utf-8'))
check(('░' not in ''.join(scr.lines()) and o.rfind('\x1b[?25h') > o.rfind('\x1b[?25l') >= 0), 'after the wait no bar is left on the screen and the cursor is shown again', f'bar or hidden cursor left behind: {scr.lines()[:4]!r}')

o2 = run_pty('_sl_ready; _sl_enter "" "" "Scroll"; sleep 1.6; _sl_pulse; echo MARK; _sl_ready')   # lint-wait-ok: the wait is the behaviour under test
check(('\x1bD' not in o2 and '\n\x1b[1A' not in o2 and '\x1bM' not in o2), 'drawing and wiping the bar never scrolls the screen (no ESC D / ESC M / newline)', f'a scrolling sequence is used: {o2[:200]!r}')

# 2) a short wait never flashes a bar
o = run_pty('_sl_ready; _sl_enter "" "" "Quick"; sleep 0.05; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
check((not has_bar(o) and 'MARK_END' in o), 'a short wait shows no bar', f'a short wait flashed a bar: {o[-160:]!r}')

# 3) the wait before the very first screen shows "Starting"
o = run_pty('sleep 1.6; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
check(('Starting' in o and has_bar(o)), 'the wait before the first screen is a "Starting" bar', f'no start-up bar: {o[-160:]!r}')

# 4) output keeps the clock fresh: a burst of output with short gaps never shows a bar
o = run_pty('_sl_ready; _sl_enter "" "" "Burst"; for i in 1 2 3 4 5 6 7 8; do sleep 0.1; _sl_pulse; done; _sl_ready; echo MARK_END')   # lint-wait-ok: the gaps are the behaviour under test
check((not has_bar(o) and 'MARK_END' in o), 'a burst of output (gaps shorter than the grace) shows no bar', f'a bar appeared during a burst: {o[-160:]!r}')

# 5) a write after a long silent stretch wipes the bar first
o = run_pty('_sl_ready; _sl_enter "" "" "Slow"; sleep 1.6; _sl_pulse; echo MARK_WRITE; _sl_ready')   # lint-wait-ok: the wait is the behaviour under test
i, w, e = o.find('░'), o.find(WIPE), o.find('MARK_WRITE')
check((i >= 0 and w > i and e > w), '_sl_pulse wipes a showing bar before the foreground writes', f'write not preceded by a wipe (bar@{i} wipe@{w} write@{e})')

# 6) code that draws its own progress holds the bar back; releasing brings it back
o = run_pty('_sl_ready; _sl_hold; _sl_enter "" "" "Held"; sleep 1.6; echo MARK_MID; _sl_release; sleep 1.6; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
m, i = o.find('MARK_MID'), o.find('░')
check((m >= 0 and i > m), '_sl_hold keeps the bar out of the way; _sl_release brings it back', f'hold/release wrong (mid@{m} bar@{i})')

# 7) VK_SMARTLOAD=0 and "no terminal" are no-ops
o = run_pty('_sl_ready; _sl_enter "" "" "Off"; sleep 1.2; _sl_ready; echo "ON=[${_SL_ON}]"', env={'VK_SMARTLOAD': '0'})   # lint-wait-ok: the wait is the behaviour under test
check((not has_bar(o) and 'ON=[]' in o), 'VK_SMARTLOAD=0 turns it off', f'VK_SMARTLOAD=0 still draws: {o[-160:]!r}')
p = subprocess.run(['bash', '-c', PRE + '_sl_enter x; _sl_ready; echo "ON=[${_SL_ON}] done"'], capture_output=True, text=True, env=dict(os.environ, VK_SMARTLOAD_GRACE_MS='50'), stdin=subprocess.DEVNULL, timeout=30 * F)
check((p.returncode == 0 and 'ON=[] done' in p.stdout and not has_bar(p.stdout)), 'no terminal (pipes, tests, cron): every call is a no-op', f'pipes: rc={p.returncode} {p.stdout!r} {p.stderr[-120:]!r}')

# 8) shutdown ends the animator and removes its pipes
o = run_pty('_sl_ready; p=$_SL_PID; b=$_SL_BASE; _sl_enter x; _sl_shutdown; for i in $(seq 1 80); do kill -0 $p 2>/dev/null || break; sleep 0.05; done; kill -0 $p 2>/dev/null && echo ANIM=ALIVE || echo ANIM=GONE; ls "$b".* >/dev/null 2>&1 && echo FILES=LEFT || echo FILES=GONE')   # lint-wait-ok: waiting for the process to exit
check(('ANIM=GONE' in o and 'FILES=GONE' in o), '_sl_shutdown ends the animator and removes its pipes', f'shutdown left something: {o[-160:]!r}')

# 9) a full-screen program (nano) is not a wait: no bar while it runs, the arguments and the exit code pass through, the bar comes back after it
fd_ = tempfile.mkdtemp(); fake = os.path.join(fd_, 'nano')
with open(fake, 'w') as f_: f_.write('#!/bin/sh\necho ARGS=$*\nsleep 1.6\necho NANO_DONE\nexit 7\n')   # lint-wait-ok: the fake editor keeps the terminal for a while
os.chmod(fake, 0o755)
penv = {'PATH': fd_ + os.pathsep + os.environ['PATH']}
o = run_pty('_sl_ready; _sl_enter "" "" "Edit"; nano a "b c"; echo RC=$?; sleep 1.6; _sl_ready; echo MARK_END', env=penv)   # lint-wait-ok: the wait is the behaviour under test
d, b = o.find('NANO_DONE'), o.find('░')
check((d >= 0 and (b < 0 or b > d)), 'no bar is drawn while nano is open (it is not a wait)', f'a bar was drawn over nano (done@{d} bar@{b})')
check(('ARGS=a b c' in o and 'RC=7' in o), 'nano gets its arguments and its exit code comes back unchanged', f'args / exit code lost: {o[-200:]!r}')
check((d >= 0 and b > d), 'after nano exits a real wait gets its bar again', f'no bar after nano (done@{d} bar@{b})')
o = run_pty('_sl_ready; _sl_enter "" "" "Edit"; command nano a; _sl_ready; echo MARK_END', env=dict(penv, VK_SMARTLOAD_AUTOHOLD='0'))   # lint-wait-ok: the control: without the guard the bar draws over the program
check(('░' in o and o.find('░') < o.find('NANO_DONE')), 'control: without the guard the bar would draw over the program', f'the control run drew no bar: {o[-200:]!r}')

# 9) smartload must never touch the app's stderr (exec ... 2>/dev/null once sent it to /dev/null for good: no prompts, no tool progress, a dead shell after cd)
o = run_pty('echo ERR_FD:$(readlink /proc/$$/fd/2)')
check('ERR_FD:/dev/pts' in o, 'stderr is still the terminal after smartload starts', f'stderr was redirected: {o[-120:]!r}')

# 10) a child program with its own prompt (gitpush ...) is not a wait: no bar over its prompt, and what the person types still reaches it
o = run_pty('_sl_ready; _sl_enter "" "" "Go"; bash -c \'printf "Commit message: "; read x; echo GOT:$x\' <<< hello; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
check(('GOT:hello' in o and not has_bar(o)), 'a child tool that owns the terminal gets no bar', f'bar over a child tool: {o[-200:]!r}')
o = run_pty('_sl_ready; _sl_enter "" "" "Go"; bash -c \'sleep 1.6\' >/dev/null 2>&1; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
check(has_bar(o), 'a child whose output is captured is still a wait: the bar shows', f'no bar for a silent child: {o[-200:]!r}')

# 11) the delay is 0.5 s by default (no VK_SMARTLOAD_GRACE_MS): a wait of about 0.3 s shows nothing, a longer one shows the bar
o = run_pty('_sl_ready; _sl_enter "" "" "Short"; sleep 0.3; _sl_ready; echo MARK_END', env={'VK_SMARTLOAD_GRACE_MS': None})   # lint-wait-ok: the wait is the behaviour under test
check((not has_bar(o) and 'MARK_END' in o), 'default delay: a wait shorter than 0.5 s never shows a bar', f'a bar for a 0.3 s wait: {o[-160:]!r}')
o = run_pty('_sl_ready; _sl_enter "" "" "Long"; sleep 1.2; _sl_ready; echo MARK_END', env={'VK_SMARTLOAD_GRACE_MS': None})   # lint-wait-ok: the wait is the behaviour under test
check(has_bar(o), 'default delay: a wait longer than 0.5 s shows the bar', f'no bar after 1.2 s: {o[-160:]!r}')

# 12) a transfer's PROGRESS bar always wins over the LOADING bar: begin wipes a bar that is already showing and keeps it away, end lets it come back.
#     The pair is taken from the real fileapi lib (never a copy of it in the test).
LIB = f'{ROOT}/script/file/staging/!buffer/fileapi/0 lib/bashbasicsbyvk_fileapi_lib.sh'
GET = f'eval "$(grep -E \'^_bb_progress_(begin|end)\\(\\)\' "{LIB}")"; '
o = run_pty(GET + '_sl_ready; _sl_enter "" "" "Prep"; sleep 1.0; _bb_progress_begin; echo MARK_P1; sleep 1.2; echo MARK_P2; _bb_progress_end; sleep 1.2; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
b1, w1, p1, p2 = o.find('░'), o.find(WIPE), o.find('MARK_P1'), o.find('MARK_P2')
check((b1 >= 0 and w1 > b1 and p1 > w1), 'progress begins: the loading bar that was showing is wiped before the progress bar draws', f'no wipe before the progress bar (bar@{b1} wipe@{w1} progress@{p1})')
check((p1 >= 0 and p2 > p1 and '░' not in o[p1:p2]), 'while the progress bar owns the screen no loading bar is drawn', f'a loading bar over the progress bar: {o[p1:p2]!r}')
check((p2 >= 0 and '░' in o[p2:]), 'after the progress bar has ended a real wait gets its loading bar again', f'no loading bar after the progress ended: {o[p2:][-160:]!r}')

# 14) a program the person chose to run (run_file) is not our app: the wait is its start-up only, up to its FIRST WRITE (_sl_launch)
#     (GRACE_MS=400 here: the start-up bar shows after the same 400 ms of silence as every other wait)
L0 = '_sl_ready; _sl_enter "" "" "Select"; '                  # what run.sh has just done: Enter on the Select: prompt opened a wait
o = run_pty(L0 + '_sl_launch myprog bash -c \'sleep 1.6\'; echo MARK_END')   # lint-wait-ok: a silent program: the start-up gap is the behaviour under test
i, w, e = o.find('░'), o.find(WIPE), o.find('MARK_END')
check((i >= 0 and 'Starting myprog' in o and w > i and e > w), 'a silent program gets a "Starting <name>" bar, wiped when it exits', f'no start-up bar / wipe for a silent program (bar@{i} wipe@{w} end@{e}): {o[-200:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'echo FIRST; sleep 1.6\'; echo MARK_END')   # lint-wait-ok: the program waits after its first paint
check((not has_bar(o) and 'FIRST' in o and 'MARK_END' in o), 'a program that paints at once never gets a bar (the old "bar over the script\'s prompt")', f'a bar over a program that had painted: {o[-200:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'printf "Enter the number: "; read x; echo GOT:$x\' <<< 5; echo MARK_END')
check((not has_bar(o) and 'GOT:5' in o), 'a program with its own prompt: no bar, and the typed answer still reaches it', f'bar over a prompt / answer lost: {o[-200:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'sleep 1.2; echo PAINT; sleep 1.6\'; echo MARK_END')   # lint-wait-ok: silent start-up, then a paint, then a long quiet stretch
b, pt = o.find('░'), o.find('PAINT')
check((b >= 0 and pt > b and '░' not in o[pt:]), 'the bar shows during the silent start-up and is gone at the first paint, for good (nothing drawn after it)', f'bar@{b} paint@{pt} bar-after-paint={"░" in o[pt:]}: {o[-240:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'sleep 1.2; echo PAINT; sleep 1.6\'; sleep 1.0; echo MARK_AFTER; _sl_ready', env={'VK_SMARTLOAD_NOCHILDREN': '1'})   # lint-wait-ok: the same without the kernel's children file
b, pt = o.find('░'), o.find('PAINT')
check((b >= 0 and pt > b and '░' not in o[pt:o.find('MARK_AFTER')]), 'without /proc/<pid>/task/<pid>/children (many Android kernels) the start-up bar works the same', f'no children file: bar@{b} paint@{pt}: {o[-240:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'echo FIRST; sleep 1.6\'; echo MARK_END', env={'VK_SMARTLOAD_NOCHILDREN': '1'})   # lint-wait-ok: the program waits after its first paint
check((not has_bar(o) and 'FIRST' in o), 'without the children file a program that paints at once still gets no bar', f'bar over a program (no children file): {o[-200:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'echo FIRST; sleep 1.6\'; echo MARK_END', env={'VK_SMARTLOAD_LAUNCH': '0'})   # lint-wait-ok: the program waits after its first paint
check(('FIRST' in o and 'MARK_END' in o), 'VK_SMARTLOAD_LAUNCH=0: the program still runs and its status comes back', f'launch off broke the run: {o[-160:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'exit 7\'; echo RC=$?')
check('RC=7' in o, '_sl_launch returns the program\'s exit status', f'status lost: {o[-120:]!r}')
o = run_pty(L0 + '_sl_launch myprog bash -c \'sleep 1.6\'; _sl_enter "" "" "Next"; sleep 1.2; _sl_ready; echo MARK_END')   # lint-wait-ok: after the program the app's own waits get their bar again
i1 = o.find('Starting myprog'); i2 = o.find('Next')
check((i1 >= 0 and i2 > i1), 'after the program has exited an app wait gets its bar again', f'no bar for the wait after the program: {o[-200:]!r}')

# 15) ONE delay for every kind of Enter: Left / Right / Space / click / Enter all behave the same (no "light" variant)
for k in ('left', 'right', 'space', 'click', 'enter'):
    o = run_pty(f'_sl_ready; _sl_enter {k} "Row"; sleep 0.2; _sl_ready; echo MARK_END')   # lint-wait-ok: shorter than the grace: no bar for any key
    check((not has_bar(o) and 'MARK_END' in o), f'{k}: a wait shorter than the delay shows no bar', f'a bar for a short {k}: {o[-160:]!r}')
    o = run_pty(f'_sl_ready; _sl_enter {k} "Row"; sleep 0.9; _sl_ready; echo MARK_END')   # lint-wait-ok: longer than the grace: a bar for any key, with the same delay
    check(has_bar(o), f'{k}: a wait longer than the delay shows the bar (same delay as every other key)', f'no bar for a slow {k}: {o[-160:]!r}')

# 16) what the person typed into a secret prompt is never printed in the bar
o = run_pty('_sl_ready; _sl_enter "hunter2" "" "Working"; sleep 1.2; _sl_ready; echo MARK_END')   # lint-wait-ok: the wait is the behaviour under test
check((has_bar(o) and 'hunter2' not in o), 'a label override wins over the typed text (read -s passes "Working")', f'typed text in the bar: {o[-160:]!r}')

# (inside the snippets a trailing  ; :  keeps  bash -c 'a; b'  from exec-ing its last command: the child must stay a bash, not become  sleep)
# 17) ownership is a POSITIVE test: a child counts only when its stdout / stderr is the terminal AND it has written.  A silent helper is a wait.
o = run_pty('_sl_ready; _sl_enter "" "" "Go"; python3 -c "import time; time.sleep(1.6)"; _sl_ready; echo MARK_END')   # lint-wait-ok: a silent python helper with the terminal as stderr
check(has_bar(o), 'a silent helper (python, tty on stderr, nothing written yet) is a wait: the bar shows', f'no bar for a silent python helper: {o[-200:]!r}')
o = run_pty('_sl_ready; _sl_enter "" "" "Go"; bash -c \'echo FIRST; sleep 1.6; :\'; _sl_ready; echo MARK_END')   # lint-wait-ok: a tool that prints at once and then works quietly
check((not has_bar(o) and 'FIRST' in o), 'a tool that has printed to the terminal owns it: no bar, even while it is quiet afterwards', f'bar over a tool that had printed: {o[-200:]!r}')
o = run_pty('_sl_ready; _sl_enter "" "" "Go"; bash -c \'sleep 0.9; echo LATE; sleep 1.2; :\'; _sl_ready; echo MARK_END')   # lint-wait-ok: silent first, prints later
b, lt = o.find('░'), o.find('LATE')
check((b >= 0 and lt > b and '░' not in o[lt:o.find('MARK_END')]), 'the bar shows while the helper is silent and is gone for good once it prints', f'bar@{b} late@{lt}: {o[-240:]!r}')

# 18) the label names what was picked: colours, the "3)" number and the [ ] mark are dropped
o = run_pty('_sl_ready; _sl_enter x "$(printf \'\\033[1m3) [ ] Delete files\\033[0m\')"; sleep 0.9; _sl_ready; echo MARK_END')   # lint-wait-ok: the label is what is checked
check(('Working on Delete files' in o and '[ ]' not in o.split('░')[-1][:60]), 'the label is the picked row\'s name, without colours, number and mark', f'label: {o[-200:]!r}')

# 19) VK_SMARTLOAD_DEBUG=1: one line per decision says why a bar showed or did not
with tempfile.TemporaryDirectory() as td:
    lg = os.path.join(td, 'sl.log')
    dbg = {'VK_SMARTLOAD_DEBUG': '1', 'VK_SMARTLOAD_DEBUG_FILE': lg}
    run_pty('_sl_ready; _sl_enter enter "Row"; sleep 0.9; _sl_ready; ( _sl_enter enter "Sub" ); echo MARK_END', env=dbg)   # lint-wait-ok: a wait that draws a bar, then an Enter in a subshell
    txt = open(lg, encoding='utf-8').read() if os.path.exists(lg) else ''
    check(('ENTER opens a wait' in txt and "label='Working on Row'" in txt), 'debug log: names the Enter that opened the wait and its label', f'log: {txt[-400:]!r}')
    check(('bar DRAWN' in txt and 'wait CLOSED' in txt), 'debug log: says when the bar was drawn and what closed the wait', f'log: {txt[-400:]!r}')
    check('Enter IGNORED' in txt and 'subshell' in txt, 'debug log: says why an Enter in a subshell opened no wait', f'log: {txt[-400:]!r}')
    run_pty('_sl_ready; _sl_enter enter "Row"; bash -c \'echo hi; sleep 1.2; :\'; _sl_ready', env=dbg)   # lint-wait-ok: a tool owns the terminal
    txt = open(lg, encoding='utf-8').read()
    check('terminal owned by' in txt, 'debug log: names the child that owned the terminal', f'log: {txt[-400:]!r}')
o = run_pty('_sl_ready; _sl_enter enter "Row"; sleep 0.9; _sl_ready; echo MARK_END', env={'VK_SMARTLOAD_DEBUG': None})   # lint-wait-ok: debug off: no log, bar as usual
check(has_bar(o), 'debug off (the default): nothing changes', f'bar lost with debug off: {o[-160:]!r}')

# 13) every call that lets a transfer tool draw its own bar sits between _bb_progress_begin and _bb_progress_end (a new call site that forgets it fails here)
import re
FA = f'{ROOT}/script/file/staging/!buffer/fileapi'
DRAWS = re.compile(r'_BVK_XFER_BIN"\s+(send|pack)\b|_pn_xfer\s+"\$pipe"|_crypto_fetch_archive\s+"\$link"|_ux_core\s+pack\b|\|\s*_crypto_stream_pack\b')
unwrapped = []
for dp, _, fns in os.walk(FA):
    for fn in fns:
        if not fn.endswith('.sh'): continue
        depth = 0
        for n, line in enumerate(open(os.path.join(dp, fn), encoding='utf-8'), 1):
            if line.lstrip().startswith('#'): continue
            for tok in re.finditer(r'_bb_progress_begin\b|_bb_progress_end\b|' + DRAWS.pattern, line):
                t = tok.group(0)
                if t == '_bb_progress_begin': depth += 1
                elif t == '_bb_progress_end': depth -= 1
                elif depth <= 0: unwrapped.append(f'{fn}:{n}')
        if depth != 0: unwrapped.append(f'{fn}: begin/end not balanced ({depth})')
check(not unwrapped, 'every transfer-bar call is wrapped in _bb_progress_begin / _bb_progress_end', f'unwrapped transfer calls: {unwrapped}')

sys.exit(fail)
