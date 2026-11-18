"""SCRIPTED REPLAY — the real app, stdin from a pipe (one line per prompt, EOF = q), no terminal, no sleeps. Every scenario runs in its own temp HOME, in parallel.
  replay-crash:<scenario>   the app printed a shell error (unbound variable, command not found, syntax error, bad substitution, stack-like 'line N:')
  replay-hang:<scenario>    the app did not finish within 8 s on a finite script (a loop that cannot leave on EOF)
  replay-rc:<scenario>      non-zero exit
  replay-expect:<scenario>  an expected / forbidden text is wrong"""
import os, re, sys, shutil, subprocess, tempfile, time, concurrent.futures as cf
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('replay')
tmp = tempfile.mkdtemp(prefix='bvk_replay_'); binp = os.path.join(tmp, 'bin'); os.makedirs(binp)
for dp, dn, fn in os.walk(bvk.SCRIPT):
    if 'bvk-ls' in dp or 'bvk-fr' in dp or 'bvk-xfer' in dp: continue
    for f in fn:
        if not os.path.exists(os.path.join(binp, f)): os.symlink(os.path.join(dp, f), os.path.join(binp, f))
ERR = re.compile(r'unbound variable|command not found|syntax error|bad substitution|bad array subscript|unexpected token|No such file or directory\s*$|: line \d+:|Traceback \(most recent', re.M)
SCREENS = ['s', 'h', 'sw', 'fx', 'f', 't', 'api', '-auth']
SC = []   # (name, script, must-contain, must-not-contain)
for w in SCREENS:
    SC.append(('screen:' + w, [w, 'cc', 'u', 'zzq-1', '9999', '1,,2', '=', 'u', 'u', 'q'], [], []))
SC += [('fs-accepted', ['fs', 'q'], [], ['Invalid command']), ('forceshow-gone', ['forceshow', 'q'], ['Invalid'], []),
       ('eof-at-main', [], [], []), ('eof-in-settings', ['s'], [], []), ('empty-enters', ['', '', '', 'q'], [], [])]
import hashlib, json
def tree_hash():
    h = hashlib.sha1()
    for dp, dn, fn in sorted(os.walk(bvk.SCRIPT)):
        for f in sorted(fn):
            st = os.stat(os.path.join(dp, f)); h.update(('%s/%s %d %d\n' % (dp, f, st.st_size, st.st_mtime_ns)).encode())
    return h.hexdigest()
CACHE = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'bvk_replay_cache.json'); TH = tree_hash()
try: cache = json.load(open(CACHE)); cache = cache if cache.get('tree') == TH else {'tree': TH, 'ok': []}
except Exception: cache = {'tree': TH, 'ok': []}
def run(sc):
    if sc[0] in cache['ok']: return sc[0], '', 0, False, 0.0, [], []     # passed on this exact tree: nothing changed, nothing to replay
    name, script, must, mustnot = sc
    home = tempfile.mkdtemp(dir=tmp); work = os.path.join(home, 'work'); os.makedirs(work)
    for n in ('alpha.txt', 'beta.txt'): open(os.path.join(work, n), 'w').write('x')
    d = os.path.join(home, '.config', 'bashbasicsbyvk', 'telemetry'); os.makedirs(d)
    open(os.path.join(d, 'uuid'), 'w').write('00000000-0000-4000-8000-000000000000\n'); open(os.path.join(d, 'daily'), 'w').write(time.strftime('%Y-%m-%d', time.gmtime()) + ' true\n')
    env = dict(os.environ, HOME=home, PATH=binp + ':' + os.environ['PATH'], TERM='xterm-256color', COLUMNS='100', LINES='40', BVK_BROWSER_TERM='0', LANG='C.UTF-8')
    t0 = time.time()
    try:
        p = subprocess.run(['bash', os.path.join(binp, 'o')], input=''.join(l + '\n' for l in script), capture_output=True, text=True, cwd=work, env=env, timeout=8)
        out, rc, hang = p.stdout + p.stderr, p.returncode, False
    except subprocess.TimeoutExpired as e:
        out, rc, hang = ((e.stdout or b'').decode(errors='ignore') + (e.stderr or b'').decode(errors='ignore')), 124, True
    shutil.rmtree(home, ignore_errors=True)
    return name, out, rc, hang, time.time() - t0, must, mustnot
try:
    with cf.ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as ex:
        for name, out, rc, hang, dt, must, mustnot in ex.map(run, SC):
            R.check(); n0 = len(R.items)
            if hang: R.add('replay-hang:%s' % name, 'no exit within 8 s on a finite script: some loop cannot leave on EOF')
            elif rc != 0: R.add('replay-rc:%s' % name, 'exit code %d' % rc)
            m = ERR.search(out)
            if m: R.add('replay-crash:%s' % name, 'shell error in output: %s' % out[max(0, m.start() - 60):m.end() + 40].replace('\n', ' ')[:140])
            for s in must:
                if s not in out: R.add('replay-expect:%s' % name, 'expected %r on screen' % s)
            for s in mustnot:
                if s in out: R.add('replay-expect:%s' % name, 'forbidden %r on screen' % s)
            if len(R.items) == n0 and name not in cache['ok']: cache['ok'].append(name)
    try: json.dump(cache, open(CACHE, 'w'))
    except OSError: pass
finally: shutil.rmtree(tmp, ignore_errors=True)
sys.exit(R.finish())
