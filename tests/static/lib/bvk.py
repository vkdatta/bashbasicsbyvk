"""tests/static/lib/bvk.py — shared helpers of the static suites.  No terminal, no app start, no sleeps.
Run tests with  python3 -I tests/static/t_x.py  (isolated mode: nothing next to the script is imported by accident)."""
import os, re, sys, hashlib, subprocess
ROOT = os.environ.get('BVK_ROOT') or os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
SCRIPT = os.path.join(ROOT, 'script'); F = os.path.join(SCRIPT, 'file'); TESTS = os.path.join(ROOT, 'tests', 'static')      # TESTS = the NEW static suites' directory
CMAP = os.path.join(F, 'cmdmap')

def read(p):
    try:
        with open(p, encoding='utf-8', errors='replace') as f: return f.read()
    except OSError: return ''

def rel(p): return os.path.relpath(p, SCRIPT)

_files = None
def all_files():
    """every file under script/ (bvk-ls holds the C sources: skipped)"""
    global _files
    if _files is None:
        _files = []
        for dp, dn, fn in os.walk(SCRIPT):
            dn[:] = sorted(d for d in dn if d != 'bvk-ls')
            for f in sorted(fn): _files.append(os.path.join(dp, f))
    return _files

def is_bash(p):
    b = os.path.basename(p)
    if b.endswith(('.py', '.mjs', '.js', '.c', '.h', '.txt', '.xlsx', '.list', '.map', '.json', '.md', '.pyc')): return False
    try:
        with open(p, 'rb') as f: head = f.read(200)
    except OSError: return False
    if b == 'o' or b.endswith('.sh'): return b'\0' not in head
    first = head.split(b'\n', 1)[0]
    return first.startswith(b'#!') and (b'bash' in first or first.rstrip().endswith(b'/sh'))

def bash_files(): return [p for p in all_files() if is_bash(p)]

class Report:
    """findings with STABLE ids.  An id listed in tests/static/baseline/<suite>.txt is KNOWN debt (counted, not failed); anything else fails.
    A baseline entry that no longer occurs is reported as fixed.   `--write-baseline` (owner only) rewrites the file from the current findings."""
    def __init__(self, suite): self.suite = suite; self.items = []; self.checks = 0
    def check(self, n=1): self.checks += n
    def add(self, id_, msg): self.items.append((id_, msg))
    def finish(self, show=12):
        bf = os.path.join(TESTS, 'baseline', self.suite + '.txt')
        ids = sorted({i for i, _ in self.items})
        if '--write-baseline' in sys.argv:
            os.makedirs(os.path.dirname(bf), exist_ok=True)
            with open(bf, 'w') as f: f.write('# KNOWN drift of suite %s: one stable id per line. Owner-only file. A finding listed here does not fail the run; a new one does.\n' % self.suite + ''.join(i + '\n' for i in ids))
            print('%s: baseline written (%d ids)' % (self.suite, len(ids))); return 0
        base = {l.strip() for l in read(bf).splitlines() if l.strip() and not l.startswith('#')}
        new = [(i, m) for i, m in self.items if i not in base]; known = len(self.items) - len(new)
        fixed = sorted(base - set(ids))
        print('%s: %d checks, %d new, %d known%s' % (self.suite, self.checks, len(new), known, (', %d baseline entries fixed (drop them)' % len(fixed)) if fixed else ''))
        # one line per (kind, last segment): "gap:*:newthing x18 (api auth fx ...)"
        groups = {}
        for i, m in new:
            p = i.split(':'); groups.setdefault((p[0], p[-1]) if len(p) >= 3 else (i, ''), []).append((i, m))
        lines = []
        for (kind, tail), g in groups.items():
            if len(g) >= 3 and tail: lines.append('  NEW  %s:*:%s  x%d  e.g. %s  (%s)' % (kind, tail, len(g), g[0][1], ' '.join(x[0].split(':')[1] for x in g[:8]) + (' ...' if len(g) > 8 else '')))
            else: lines += ['  NEW  %s  %s' % (i, m) for i, m in g]
        for l in lines[:show]: print(l)
        if len(lines) > show: print('  ... and %d more lines (%d findings)' % (len(lines) - show, len(new)))
        return 1 if new else 0

# ---- parsing the command map (static: the files themselves, no bash)
def parse_menus_list():
    out = []
    for l in read(os.path.join(CMAP, 'bashbasicsbyvk_menus.list')).splitlines():
        if l.startswith('#') or '|' not in l: continue
        p = [x.strip() for x in l.split('|')]; out.append(dict(zip(('map', 'func', 'kind', 'back'), p)))
    return out

CMD_DEF = re.compile(r'^cmd_def\s+(\S+)\s+(exact|prefix|word)\s+(\S+)\s+(\S+)\s*(.*)$')
def parse_cmd_defs():
    """{(basename, id): dict(kind, handler, class, desc, ex, line)}   for every *commands.sh"""
    defs = {}; dups = []
    for dp, dn, fn in os.walk(CMAP):
        for f in sorted(fn):
            if not f.endswith('commands.sh'): continue
            for n, l in enumerate(read(os.path.join(dp, f)).splitlines(), 1):
                m = CMD_DEF.match(l)
                if not m: continue
                k = (f, m.group(1))
                if k in defs: dups.append(k)
                q = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(5))
                defs[k] = dict(kind=m.group(2), handler=m.group(3), cls=m.group(4), desc=q[0] if q else '', ex=q[1] if len(q) > 1 else '', line=n)
    return defs, dups

WIRE = re.compile(r'^(\S+)\s+\.mapto\(\)\s+(block\(\)|back\(\)|(\S+)\s+from\s+(\S+))')
def parse_maps():
    """{map: dict(head={@menu..}, wires=[(key, target)], file)}   target = 'block' | 'back' | (id, file)"""
    maps = {}
    for dp, dn, fn in os.walk(CMAP):
        for f in sorted(fn):
            if not f.endswith('.map'): continue
            head = {}; wires = []
            for l in read(os.path.join(dp, f)).splitlines():
                if l.startswith('@'):
                    p = l.split(None, 1); head[p[0][1:]] = (p[1].split('#')[0].strip() if len(p) > 1 else '')
                    continue
                m = WIRE.match(l)
                if m:
                    t = 'block' if m.group(2) == 'block()' else 'back' if m.group(2) == 'back()' else (m.group(3), m.group(4))
                    wires.append((m.group(1), t))
            maps[f[len('bashbasicsbyvk_'):-4]] = dict(head=head, wires=wires, file=os.path.join(dp, f))
    return maps

FUNC_DEF = re.compile(r'(?:^|[;&{(]\s*|^\s*)(?:function\s+)?([A-Za-z_][\w.:-]*)\s*\(\)\s*(?:\{|\()')
def is_stub_file(p): return os.path.basename(p) == 'bashbasicsbyvk_loadmap_stubs.sh'     # one-line lazy-load stubs: they NAME every function, they are not the function

def defined_functions():
    """{name: [files]} over every bash file except the loader stubs (a stub is not a definition, and its mention is not a use)"""
    d = {}
    for p in bash_files():
        if is_stub_file(p): continue
        for l in read(p).splitlines():
            if l.lstrip().startswith('#'): continue
            for m in FUNC_DEF.finditer(l): d.setdefault(m.group(1), []).append(p)
    return d

# ---- one bash process per map, in parallel; cached PER MAP by a hash of what that map's answer depends on
#      (engine + every *commands.sh + this map's .map file + tests/static/lib/*.sh).  Editing one .map re-dumps one map (~1 s); everything else is read from the cache.
def _global_hash():
    h = hashlib.sha1()
    paths = [os.path.join(F, 'engine', n) for n in ('bashbasicsbyvk_cmdmap.sh', 'bashbasicsbyvk_advert.sh', 'bashbasicsbyvk_cheatcode.sh')]
    for dp, dn, fn in os.walk(CMAP):
        for f in fn:
            if f.endswith('commands.sh'): paths.append(os.path.join(dp, f))
    for f in os.listdir(os.path.join(TESTS, 'lib')):
        if f.endswith('.sh'): paths.append(os.path.join(TESTS, 'lib', f))
    for p in sorted(paths): h.update(p.encode()); h.update(read(p).encode())
    return h.hexdigest()[:12]

def _cache_dir():
    d = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'bvk_dump_' + hashlib.sha1(ROOT.encode()).hexdigest()[:8]); os.makedirs(d, exist_ok=True); return d

def dump_all(maps, mapfiles):
    """-> list of rows (tuples of str): tests/static/lib/dump_resolve.sh over every map, per-map cache.  A lock makes two suites that start together share ONE dump."""
    import fcntl
    with open(os.path.join(_cache_dir(), '.lock'), 'w') as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        return _dump_all(maps, mapfiles)

def _dump_all(maps, mapfiles):
    g = _global_hash(); cd = _cache_dir(); rows = []; todo = []; key = {}
    for m in maps:
        key[m] = os.path.join(cd, '%s_%s_%s.tsv' % (m, g, hashlib.sha1(read(mapfiles[m]).encode()).hexdigest()[:10]))
        if os.path.exists(key[m]) and '--no-cache' not in sys.argv: rows += [l for l in read(key[m]).split('\n') if l]
        else: todo.append(m)
    if todo:
        n = max(2, min(8, os.cpu_count() or 2)); chunks = [todo[i::n] for i in range(n)]
        procs = [subprocess.Popen(['bash', os.path.join(TESTS, 'lib', 'dump_resolve.sh')] + c, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=dict(os.environ, BVK_ROOT=ROOT)) for c in chunks if c]
        got = {}
        for p in procs:
            o, e = p.communicate(timeout=90)
            if p.returncode: raise SystemExit('dump_resolve.sh failed (%d): %s' % (p.returncode, e[:400]))
            for l in o.split('\n'):
                if l: got.setdefault(l.split('\t')[1], []).append(l)
        for m in todo:
            rows += got.get(m, [])
            try:
                with open(key[m], 'w') as f: f.write('\n'.join(got.get(m, [])) + '\n')
            except OSError: pass
    return [tuple(l.split('\t')) for l in rows]
