"""SHELL HAZARDS — patterns that break on a name with a space, an empty variable or a leading dash. Static, whole app, milliseconds.
  rmvar:<file>:<fn>   rm / mv / cp on an unquoted variable        cdvar:   `cd $var` unquoted (and no || guard)      lsfor:   `for x in $(ls …)` (word-splits names)
  testvar:  `[ $var = x ]` unquoted inside single brackets (empty var → syntax error)       evalvar:  eval on a variable (injection; informational)
  unsetref: `${arr[$i]}`-style subscript with an unset-able name under `set -u` is not detectable here: covered by the replay suite."""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('shell')
# testvar skips $rc / $ok: copies of $? are always set
PATS = [
 ('rmvar',   re.compile(r'(?:^|[;&|]\s*|\bdo\s+|\bthen\s+)(rm|mv|cp)\s+(-[a-zA-Z]+\s+)*(--\s+)?[^|;&\n]*?(?<![\"\'\w])\$\{?[A-Za-z_]\w*\}?(?![\w\"\'}\]/])')),
 ('cdvar',   re.compile(r'(?:^|[;&|]\s*|\bdo\s+|\bthen\s+)cd\s+\$\{?[A-Za-z_]\w*\}?\s*(?:$|;|&&)(?!.*\|\|)')),
 ('lsfor',   re.compile(r'\bfor\s+\w+\s+in\s+\$\(\s*ls\b')),
 ('testvar', re.compile(r'(?:^|[;&|(]\s*|\bif\s+|\bwhile\s+|\bthen\s+)\[\s+(?!-[a-zA-Z]\s+\")(\$\{?(?!\w*rc\b|\w*_ok\b|ok\b)[A-Za-z_]\w*\}?)\s+(=|==|!=|-eq|-ne|-lt|-gt)\s')),
]
for f in bvk.bash_files():
    if f.endswith('.map'): continue
    fn = '-'; inhere = None
    for n, raw in enumerate(bvk.read(f).splitlines(), 1):
        m = re.match(r'^(\w[\w.:-]*)\(\)\s*\{', raw)
        if m: fn = m.group(1)
        if inhere:
            if raw.strip() == inhere: inhere = None
            continue
        h = re.search(r'<<-?\s*[\'"]?(\w+)[\'"]?', raw)
        if h and not raw.lstrip().startswith('#'): inhere = h.group(1)
        l = raw.split(' #')[0]
        if l.lstrip().startswith('#'): continue
        for kind, rx in PATS:
            R.check()
            if rx.search(l): R.add('%s:%s:%s:%d' % (kind, bvk.rel(f), fn, n), '%s' % l.strip()[:110])
sys.exit(R.finish())
