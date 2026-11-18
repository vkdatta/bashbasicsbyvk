"""READ LOOPS — a prompt inside an endless loop must give up on end-of-input / cancel, or the app spins at 100% CPU (the bug found in `o` when stdin is a pipe, and the "13 s loading bar").
  readrc:<file>:<fn>:<n>   a read (read / _mc_read / _bvk_read) inside `while true` whose return code is never looked at
  retry:<file>:<fn>        a retry loop with a read and no break/return anywhere (cannot be left)"""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('readloop')
READ = re.compile(r'(?:^\s*|[;&|]\s*|\b(?:then|do|else)\s+|\bif\s+!?\s*)(_mc_read|_bvk_read|read)\s+(?!-t\b)(-\w+\s+)*[A-Za-z_]')
INF = re.compile(r'^\s*(while\s+(true|:|\[\s*1\s*\]|\(\(\s*1\s*\)\))\s*;?\s*do|until\s+false\s*;?\s*do)')
OPEN = re.compile(r'^\s*(while|until|for)\b.*;\s*do\s*(#.*)?$|^\s*(while|until|for)\b[^;]*$')
for f in bvk.bash_files():
    L = bvk.read(f).splitlines(); fn = '-'
    stack = []      # (is_infinite, start_line, [reads])
    for i, raw in enumerate(L):
        l = raw.split('#')[0] if '#' in raw and not re.search(r'["\'].*#', raw) else raw
        m = re.match(r'^(\w[\w.:-]*)\(\)\s*\{', raw)
        if m: fn = m.group(1)
        if INF.match(l): stack.append([True, i, []]); continue
        if re.match(r'^\s*(while|until|for|select)\b', l) and re.search(r';\s*do\b|\bdo\s*$', l): stack.append([False, i, []]); continue
        if re.match(r'^\s*done\b', l):
            if stack:
                inf, s, reads = stack.pop()
                if inf:
                    body = '\n'.join(L[s:i + 1])
                    if any(c for _, c in reads): reads = []     # another prompt of the loop honours EOF / cancel: the loop can be left
                    for (ln, checked) in reads:
                        if not checked: R.add('readrc:%s:%s:%d' % (bvk.rel(f), fn, ln + 1), 'read at line %d in an endless loop ignores its return code (EOF → spin)' % (ln + 1))
                    R.check()
                    if reads and not re.search(r'\b(break|return|exit)\b|_bvk_quit|_mc_unwind', body): R.add('retry:%s:%s' % (bvk.rel(f), fn), 'endless loop with a read at line %d has no break / return / exit' % (s + 1))
            continue
        if stack and READ.search(l) and not re.search(r'<\s*["$\w/]|<<<', l) and not re.match(r'^\s*(local|declare|echo|printf)\b', l):
            nxt = ' '.join(L[i + 1:i + 3])
            checked = bool(re.search(r'(\|\||&&|\bthen\b)', l) or re.match(r'^\s*(if|while|until)\b', l) or re.search(r'\$\?|\brc=|\(\(\s*\$?\w*rc', nxt) or '!' in l.split('read')[0])
            for ent in stack:
                if ent[0]: ent[2].append((i, checked))
sys.exit(R.finish())
