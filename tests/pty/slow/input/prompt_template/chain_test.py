#!/usr/bin/env python3
"""A stand-alone tool that chains questions: u = ONE QUESTION BACK, q = quit (AGENTS.md rule 17; STEPS-01 in bashbasicsbyvk_menuchrome.sh).
Runs the REAL commit questions of bashbasicsbyvk_gitpush (version -> message -> "Create this commit?") against a temp git repo, in a pty, with the real
doors (bashbasicsbyvk_ask / bashbasicsbyvk_yn) on PATH.  Cases: u walks back one question at a time, what was typed is kept, u on the first question leaves,
q quits, a plain answer commits, @u is the text "u"."""
import os, pty, re, select, shutil, subprocess, sys, tempfile, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', '..'))
FLAT = tempfile.mkdtemp(prefix='bvkflat')
for d, _, fs in os.walk(os.path.join(ROOT, 'script')):
    for f in fs:
        if f.startswith('bashbasicsbyvk_') or f.startswith('_3bvk_'):
            shutil.copy(os.path.join(d, f), os.path.join(FLAT, f)); os.chmod(os.path.join(FLAT, f), 0o755)
fails = 0
def drive(name, argv, steps, want, nowant=(), env_extra=None, cwd=None, bindir=None):
    """Run argv in a pty with the real doors on PATH; steps = [(text to wait for (a NEW occurrence), keys to send)]; the output must contain `want`, never `nowant`."""
    global fails
    env = dict(os.environ, PATH=(bindir + ':' if bindir else '') + FLAT + ':' + os.environ['PATH'], TERM='xterm-256color', COLUMNS='100', LINES='40')
    env.update(env_extra or {})
    pid, fd = pty.fork()
    if pid == 0:
        if cwd: os.chdir(cwd)
        os.execvpe(argv[0], argv, env)
    import fcntl, termios, struct
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 100, 0, 0))
    buf = b''
    def pump(t):
        nonlocal buf
        end = time.time() + t
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try: d = os.read(fd, 65536)
                except OSError: return False
                if not d: return False
                buf += d
        return True
    def clean(): return re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', buf).decode('utf8', 'replace')
    def settle():               # type only once the screen has gone quiet: a loaded machine draws slowly, a fixed pause is a race
        for _ in range(12):
            n = len(buf); pump(0.35)
            if len(buf) == n: return
    seen = {}
    def wait(text, t=20):       # a NEW occurrence: the same question asked again (after u) is already on the screen once
        end = time.time() + t
        while time.time() < end:
            if clean().count(text) > seen.get(text, 0): seen[text] = clean().count(text); return True
            if not pump(0.2): break
        if clean().count(text) > seen.get(text, 0): seen[text] = clean().count(text); return True
        return False
    ok = True
    for expect, send in steps:
        if not wait(expect): ok = False; print('FAIL %s   [never saw %r]' % (name, expect)); break
        settle(); os.write(fd, send.encode())
    end = time.time() + 12
    while time.time() < end and pump(0.3): pass                 # until the tool exits, not a fixed wait: a loaded machine is slower
    out = clean()
    try: os.kill(pid, 9)
    except Exception: pass
    if ok:
        for w in want:
            if w not in out: ok = False; print('FAIL %s   [missing %r]' % (name, w))
        for w in nowant:
            if w in out: ok = False; print('FAIL %s   [must not contain %r]' % (name, w))
    if ok: print('PASS ' + name)
    else: fails += 1; print('---- last output ----\n' + out[-700:])

# (bashbasicsbyvk_gitpush and bashbasicsbyvk_localhost are functions of the app now: tests/pty/slow/apps/infinity/infinity_test.py drives their questions in the real app)

# ---- bashbasicsbyvk_recover_creds.py (Python): token -> account, the questions are steps (bashbasicsbyvk_ask.steps).  The prompts and the API are faked.
sys.path[:0] = [os.path.join(ROOT, 'script/file/engine'), os.path.join(ROOT, 'script/file/loops/iloop/fx/cloudflare_fx/recover')]
import importlib
rc = importlib.import_module('bashbasicsbyvk_recover_creds'); ask_mod = importlib.import_module('bashbasicsbyvk_ask')
def py_case(name, resolved, accounts, answers, want):
    """answers: what each _ask() returns in order (a str, or 'BACK' = the person typed u); want: ('ok', token, account, [prompts asked]) or ('back', [prompts asked])"""
    global fails
    asked, it = [], iter(answers)
    def fake_ask(prompt, secret=False, back=False):
        asked.append(prompt.split(' - ')[0].split(':')[0])
        a = next(it)
        if a == 'BACK': raise ask_mod.Back
        return a
    rc._ask, rc.resolve, rc.get_json = fake_ask, (lambda nav: resolved), (lambda path, token: {'result': accounts})
    try: got = ('ok',) + tuple(rc.credentials('/x')) + (asked,)
    except ask_mod.Back: got = ('back', asked)
    except Exception as e: got = ('error', repr(e), asked)
    ok = got == want
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else '   [got %r, want %r]' % (got, want)))
    if not ok: fails += 1
A2 = [{'id': 'A0', 'name': 'zero'}, {'id': 'A1', 'name': 'one'}]
TQ, AQ = 'Cloudflare API token (hidden)', 'Choose account number'
py_case('creds: token and account typed', (None, None, None, None), A2, ['tok', '1'], ('ok', 'tok', 'A1', [TQ, AQ]))
py_case('creds: u at the account question asks the token again', (None, None, None, None), A2, ['tok', 'BACK', 'tok2', '0'], ('ok', 'tok2', 'A0', [TQ, AQ, TQ, AQ]))
py_case('creds: u on the first question leaves', (None, None, None, None), A2, ['BACK'], ('back', [TQ]))
py_case('creds: token found, u at the account question leaves (the token step asked nothing)', ('T', None, 'file', None), A2, ['BACK'], ('back', [AQ]))
py_case('creds: one account is auto-detected, nothing to ask', ('T', None, 'file', None), [{'id': 'ONLY', 'name': 'x'}], [], ('ok', 'T', 'ONLY', []))
py_case('creds: everything found, nothing asked', ('T', 'ACC', 'file', 'file'), [], [], ('ok', 'T', 'ACC', []))

# ---- the door's secret read (-s) has the same two words as the typed line
SK = ['bash', '-c', 'x=$(bash "%s" "Token: " -s -b); rc=$?; echo "RC=$rc LEN=${#x}"' % os.path.join(FLAT, 'bashbasicsbyvk_ask')]
drive('secret: u with -b exits 4', SK, [('Token: ', 'u\r')], ['RC=4', 'u) Back   q) Quit'])
drive('secret: q exits 2', SK, [('Token: ', 'q\r')], ['RC=2'])
drive('secret: a real secret is returned (exit 0), never echoed', SK, [('Token: ', 'abc123\r')], ['RC=0 LEN=6'], ['abc123'])

# ---- an answer is ONE line (a pasted line break comes back as a space) unless the caller asks for rows (-m)
PASTE = '\x1b[200~ab\ncd\x1b[201~'
ONE = ['bash', '-c', 'x=$(bash "%s" "Name: "); echo "RESULT=[${x//$\'\\n\'/<NL>}]"' % os.path.join(FLAT, 'bashbasicsbyvk_ask')]
MULTI = ['bash', '-c', 'x=$(bash "%s" "Name: " -m); echo "RESULT=[${x//$\'\\n\'/<NL>}]"' % os.path.join(FLAT, 'bashbasicsbyvk_ask')]
drive('a pasted line break returns as a space (one line)', ONE, [('Name: ', PASTE), ('Name: ab', '\r')], ['RESULT=[ab cd]'], ['<NL>'])
drive('-m keeps the line break (multi-line answer)', MULTI, [('Name: ', PASTE), ('Name: ab', '\r')], ['RESULT=[ab<NL>cd]'])
shutil.rmtree(FLAT, ignore_errors=True)
print('ALL OK' if not fails else 'FAILED')
sys.exit(1 if fails else 0)
