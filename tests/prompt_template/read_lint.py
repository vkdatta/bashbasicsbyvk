#!/usr/bin/env python3
"""ONE typed-line prompt (AGENTS.md rule 16).  Every place that waits for the person to TYPE goes through _bvk_read (in the app) or
bashbasicsbyvk_ask / its python door (in a tool that runs as its own process).  A bare `read -p`, `read -e`, `read VAR`, `input()`, `getpass` or
`sys.stdin.readline()` is the drift this test stops: it would miss every later change to the line editor (selection, Shift / Ctrl keys, cut / copy /
paste, undo, cursor, tap), which is made once, in the editor behind _bvk_read.

  1. LINT (static): no terminal read outside the key-loop files below, and none without a `# bvk-read-ok: <reason>` marker on its line.
     Inside the key-loop files only KEY reads are exempt (-n / -N / -t / -d / -u); a `read ... -p PROMPT` there is a typed line and is flagged too.
     A read that is FED (`< file`, `<<<`, a pipe, a `while read` loop) is data parsing, not a prompt: allowed.
  2. the allowlist is not stale (every file named in it exists) and every marker states a reason.
  3. _bvk_read exists once; the ask tool, its import file and its python door exist.
  4. BEHAVIOUR (pty): bashbasicsbyvk_ask returns what was typed, edits a starting text, and takes a piped answer when there is no terminal.
usage: python3 tests/prompt_template/read_lint.py"""
import re, os, sys

CMD_PRE = re.compile(r'(?:^|[;&|({]|\bthen\b|\bdo\b|\belse\b|\bin\b|!|\)\s*)\s*((?:[A-Za-z_]\w*=(?:\'[^\']*\'|"[^"]*"|\$\'[^\']*\'|\S*)\s+)*)((?:builtin\s+)?)(read)(?=\s)')

def parse_word(s, i):
    """Return end index of the shell word starting at s[i] (quotes / $() / ${} aware)."""
    n = len(s); j = i
    while j < n:
        c = s[j]
        if c in ' \t\n': break
        if c in ';|&<>' : break
        if c == '\\':
            j += 2; continue
        if c == "'":
            k = s.find("'", j+1); j = (k+1) if k >= 0 else n; continue
        if c == '$' and s[j+1:j+2] == "'":
            k = j+2
            while k < n and s[k] != "'":
                k += 2 if s[k] == '\\' else 1
            j = k+1; continue
        if c == '"':
            j = skip_dq(s, j); continue
        if c == '$' and s[j+1:j+2] == '(':
            j = skip_paren(s, j+1); continue
        if c == '$' and s[j+1:j+2] == '{':
            k = s.find('}', j); j = (k+1) if k >= 0 else n; continue
        if c == '`':
            k = s.find('`', j+1); j = (k+1) if k >= 0 else n; continue
        j += 1
    return j

def skip_dq(s, j):
    n = len(s); j += 1
    while j < n:
        c = s[j]
        if c == '\\': j += 2; continue
        if c == '"': return j+1
        if c == '$' and s[j+1:j+2] == '(': j = skip_paren(s, j+1); continue
        if c == '`':
            k = s.find('`', j+1); j = (k+1) if k >= 0 else n; continue
        j += 1
    return n

def skip_paren(s, j):
    n = len(s); depth = 0
    while j < n:
        c = s[j]
        if c == '\\': j += 2; continue
        if c == "'":
            k = s.find("'", j+1); j = (k+1) if k >= 0 else n; continue
        if c == '"': j = skip_dq(s, j); continue
        if c == '(': depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0: return j+1
        j += 1
    return n

def skip_ws(s, i):
    n = len(s)
    while i < n:
        if s[i] in ' \t': i += 1
        elif s[i] == '\\' and s[i+1:i+2] == '\n': i += 2
        else: break
    return i

def parse_read(s, rstart):
    """s[rstart:] begins at the word `read`. Returns dict(flags, prompt, init, var, end, other) or None."""
    i = rstart + 4
    flags = []; prompt = init = var = None; other = []
    while True:
        i = skip_ws(s, i)
        if i >= len(s) or s[i] in '\n;|&<>)': break
        e = parse_word(s, i)
        if e == i: break
        w = s[i:e]
        if w.startswith('-') and len(w) > 1 and re.fullmatch(r'-[A-Za-z0-9]+', w):
            letters = w[1:]; k = 0
            while k < len(letters):
                ch = letters[k]
                if ch in 'er': k += 1; continue
                if ch == 's': flags.append('s'); k += 1; continue
                if ch == 'n': flags.append('n' + letters[k+1:]); k = len(letters); continue
                if ch in 'pi':
                    arg_inline = letters[k+1:]
                    if arg_inline: val = arg_inline
                    else:
                        i = skip_ws(s, e); e2 = parse_word(s, i); val = s[i:e2]; e = e2
                    if ch == 'p': prompt = val
                    else: init = val
                    k = len(letters); continue
                other.append(ch); k += 1
        elif w == '--': pass
        else:
            if var is None: var = w
            else: other.append('extra:' + w)
            i = e; break
        i = e
    return dict(flags=flags, prompt=prompt, init=init, var=var, end=i, other=other)

def strip_comment(line):
    """Return line with a trailing ` # comment` (outside quotes) replaced by spaces (offsets stay)."""
    q = None; i = 0; n = len(line)
    while i < n:
        c = line[i]
        if q:
            if c == '\\' and q == '"': i += 2; continue
            if c == q: q = None
        else:
            if c in '"\'': q = c
            elif c == '\\': i += 2; continue
            elif c == '#' and (i == 0 or line[i-1] in ' \t;'):
                return line[:i] + ' ' * (n - i)
        i += 1
    return line

def iter_reads(text):
    """Yield (match_start_of_read, line_no, prefix_start, parsed, line_text) for command-position reads outside comments / heredoc-free code."""
    pos = 0
    for ln, line in enumerate(text.split('\n'), 1):
        lstart = pos; pos += len(line) + 1
        st = line.lstrip()
        if st.startswith('#') or not st: continue
        # strip a trailing comment for detection only (keep offsets)
        code = strip_comment(line)
        for m in CMD_PRE.finditer(code):
            yield lstart + m.start(3), ln, lstart + m.start(1), m, code


# Files that ARE the editors / key loops / process plumbing: a raw `read` is their job.  Nothing else may read the terminal itself.
ENGINE_ALLOW = (
    'engine/bashbasicsbyvk_viewport.sh', 'engine/bashbasicsbyvk_browse.sh', 'engine/bashbasicsbyvk_mouse.sh',
    'engine/bashbasicsbyvk_smartmenu.sh', 'engine/bashbasicsbyvk_cmdmap.sh', 'settings/bashbasicsbyvk_settings_ui.sh',
    'engine/bashbasicsbyvk_textedit.sh', 'engine/bashbasicsbyvk_smartload.sh', 'loadmap/bashbasicsbyvk_loadmap.sh',
)
def classify(line, m, parsed, lstart):
    """'data' (fed from a file / pipe / here-string / while condition) or 'terminal'."""
    before = line[:m.start(3)]
    after = line[max(0, parsed['end'] - lstart):] if parsed['end'] >= lstart else ''
    # a command that continues on the next physical line (backslash) keeps its redirects there
    if parsed['end'] - lstart > len(line): after = ''
    if re.search(r'<<<|<\(|<\s*(?!/dev/tty)[\"$/\w.~]', after): return 'data'
    if re.search(r'(^|[^|])\|\s*(\{\s*)?$', before.rstrip()) or re.search(r'\|\s*\{?\s*(IFS=\S*\s+)?$', before): return 'data'
    if re.search(r'\b(while|until)\b', before): return 'data'
    if re.search(r'-[A-Za-z]*[uN]\b', ' '.join('-' + f for f in parsed['other'])): pass
    if 'u' in parsed['other'] or 'N' in parsed['other'] or 't' in parsed['other'] or 'd' in parsed['other']:
        return 'terminal-raw'
    return 'terminal'


ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
SCRIPT = os.path.join(ROOT, 'script')
ok = True
def check(name, cond, detail=''):
    global ok; ok &= bool(cond); print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else '  ' + str(detail)[:600]))

def is_text(p):
    try:
        with open(p, 'rb') as fh: head = fh.read(300)
    except OSError: return None
    if b'\x00' in head: return None
    return head

def files():
    for dp, dn, fn in os.walk(SCRIPT):
        if 'bvk-' in dp or '__pycache__' in dp: continue
        for f in sorted(fn):
            p = os.path.join(dp, f); head = is_text(p)
            if head is None: continue
            rel = os.path.relpath(p, SCRIPT)
            first = head.split(b'\n', 1)[0]
            if f.endswith('.sh') or f == 'o' or (b'bash' in first and first.startswith(b'#!')): yield p, rel, 'sh'
            elif f.endswith('.py') or (b'python' in first and first.startswith(b'#!')): yield p, rel, 'py'
            elif '.' not in f and first.startswith(b'#!'): yield p, rel, 'sh'

MARK = 'bvk-read-ok:'
bad = []; markers = []; seen_allow = set()
for p, rel, kind in files():
    text = open(p, encoding='utf-8', errors='replace').read()
    lines = text.split('\n')
    for i, l in enumerate(lines, 1):
        if MARK in l:
            markers.append((rel, i, l.split(MARK, 1)[1].strip()))
    if kind == 'sh':
        for rstart, ln, pstart, m, line in iter_reads(text):
            parsed = parse_read(text, rstart)
            if classify(line, m, parsed, rstart - m.start(3)) == 'data': continue
            if any(rel.endswith(a) for a in ENGINE_ALLOW):
                seen_allow.add(next(a for a in ENGINE_ALLOW if rel.endswith(a)))
                # the key-loop files may read KEYS (-n1 / -N / -t / -d / -u / -s: raw) but never a typed LINE: a `read ... -p PROMPT` there is a
                # prompt hiding behind the file-wide exemption (found in browse.sh `goto` and settings_ui.sh `_st_ask`): use _bvk_read.
                has_p = parsed['prompt'] is not None or re.search(r'(?<![\w-])-[A-Za-z]*p(?=[\s"\'$])', line[m.start(3):])
                if not has_p or classify(line, m, parsed, rstart - m.start(3)) == 'terminal-raw': continue
                end_ln = text.count('\n', 0, parsed['end']) + 1
                if MARK in lines[ln - 1] or MARK in lines[end_ln - 1]: continue
                bad.append('%s:%d  [typed line in a key-loop file] %s' % (rel, ln, lines[ln - 1].strip()[:100])); continue
            if MARK in lines[ln - 1]: continue
            # a command split over several physical lines carries its marker on the last one
            end_ln = text.count('\n', 0, parsed['end']) + 1
            if MARK in lines[end_ln - 1]: continue
            bad.append('%s:%d  %s' % (rel, ln, lines[ln - 1].strip()[:110]))
    else:
        for i, l in enumerate(lines, 1):
            code = l.split('#', 1)[0] if '"' not in l and "'" not in l else l
            if l.lstrip().startswith('#') or MARK in l: continue
            if re.search(r'(?<![\w.])input\(|getpass\.getpass\(|sys\.stdin\.readline\(', code):
                bad.append('%s:%d  %s' % (rel, i, l.strip()[:110]))
check('1. no bare terminal read in script/ (use _bvk_read / bashbasicsbyvk_ask; AGENTS.md rule 16): %d offender(s)' % len(bad), not bad, '\n   ' + '\n   '.join(bad[:40]))

missing = [a for a in ENGINE_ALLOW if not os.path.isfile(os.path.join(SCRIPT, 'file', a))]
check('2a. every file of the key-loop allowlist exists', not missing, missing)
noreason = ['%s:%d' % (r, i) for r, i, why in markers if len(why) < 12]
check('2b. every bvk-read-ok marker states a reason (%d markers)' % len(markers), not noreason, noreason)

rd = sum(len(re.findall(r'^_bvk_read\(\)', open(p, encoding='utf-8', errors='replace').read(), re.M)) for p, rel, k in files() if k == 'sh')
check('3a. _bvk_read is defined exactly once', rd == 1, rd)
need = ['file/engine/bashbasicsbyvk_ask', 'file/engine/_3bvk_import_ask.sh', 'file/engine/bashbasicsbyvk_ask.py']
check('3b. the ask tool, its import file and its python door exist', all(os.path.isfile(os.path.join(SCRIPT, n)) for n in need), need)

# 4. behaviour: the tool runs the shared editor
import pty, select, time, tempfile
flat = tempfile.mkdtemp(prefix='ask_flat_')
for dp, _, fs in os.walk(SCRIPT):
    for f in fs:
        if not f.endswith('.pyc') and 'bvk-' not in dp and not os.path.exists(os.path.join(flat, f)): os.symlink(os.path.join(dp, f), os.path.join(flat, f))
TOOL = os.path.join(flat, 'bashbasicsbyvk_ask')
def run(args, keys, tty=True):
    env = dict(os.environ, PATH=flat + ':' + os.environ['PATH'], TERM='xterm-256color', LC_ALL='C.UTF-8', LANG='C.UTF-8')
    if not tty:
        import subprocess
        r = subprocess.run(['bash', TOOL] + args, input=keys, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=20)
        return r.returncode, r.stdout.decode(errors='replace'), ''
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update(env)
        os.execvp('bash', ['bash', '-c', 'out=$(bash "$0" "$@"); echo "[[RC=$? ANS=$out]]"', TOOL] + args)
    buf = b''
    def pump(t, stop=lambda: False):
        nonlocal buf
        end = time.time() + t
        while time.time() < end:
            if select.select([fd], [], [], 0.05)[0]:
                try: d = os.read(fd, 65536)
                except OSError: return
                if not d: return
                buf += d
            if stop(): return
    pump(10, lambda: len(buf) > 0)
    for k in keys:
        n = len(buf); os.write(fd, k)
        pump(3, lambda: len(buf) > n or b'[[RC=' in buf)
        last = len(buf); quiet_end = time.time() + 0.4        # settle: the editor may still be reading a burst of keys as one paste
        while time.time() < quiet_end:
            pump(0.1)
            if len(buf) != last: last = len(buf); quiet_end = time.time() + 0.4
    pump(8, lambda: b']]' in buf)
    try: os.kill(pid, 9)
    except OSError: pass
    try: os.waitpid(pid, 0)
    except ChildProcessError: pass
    t = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', buf).decode(errors='replace')
    m = re.search(r'\[\[RC=(\d+) ANS=(.*?)\]\]', t, re.S)
    return (int(m.group(1)), m.group(2), t) if m else (None, '', t)
rc, ans, t = run(['Port: '], [b'8080', b'\r'])
check('4a. typed text comes back on stdout (exit 0)', rc == 0 and ans == '8080', (rc, ans, t[-200:]))
rc, ans, t = run(['Name: ', '-i', 'abc'], [b'\x7f', b'XY', b'\r'])
check('4b. -i starts the line with that text and the editor edits it (Backspace, type)', rc == 0 and ans == 'abXY', (rc, ans, t[-200:]))
rc, ans, t = run(['P: '], [b'one two', b'\x1b[1;5D', b'ZZ', b'\r'])
check('4c. a Ctrl+Left word jump works (the shared textedit keys, not plain readline)', rc == 0 and ans == 'one ZZtwo', (rc, ans, t[-200:]))
rc, out, _ = run(['Q: '], b'piped answer\n', tty=False)
check('4d. no terminal at all: the piped answer is read', rc == 0 and out == 'piped answer', (rc, out))
print('ALL OK' if ok else 'FAILED'); sys.exit(0 if ok else 1)
