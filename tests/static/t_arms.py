"""LOOP vs MENU — what a screen's loop really handles (its `case` arms, read by mapgen's harvester) against what the menu declares (cc) and its footer prints.
  arm-undeclared:<map>:<key>   the loop handles it, cc does not list it          arm-phantom:<map>:<key>   cc lists it, no loop arm anywhere takes it
  arm-footer:<map>:<key>       the footer prints a key the menu does not declare"""
import os, re, sys, subprocess
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('arms')
out = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib', 'arms_core.py')], capture_output=True, text=True, timeout=25).stdout
cur = None; n = 0
for l in out.splitlines():
    m = re.match(r'^(\S+)\s+coverage', l)
    if m: cur = m.group(1); R.check(); n += 1; continue
    for tag, pre in (('loop handles but not declared', 'arm-undeclared'), ('declared (cc) but the loop does not handle:', 'arm-phantom'), ('footer prints but not declared:', 'arm-footer')):
        if tag in l and cur:
            for k in l.split(':', 1)[1].split(): R.add('%s:%s:%s' % (pre, cur, k), '%s: %s' % (cur, l.strip()[:90]))
if n < 15: R.add('arms:core:empty', 'the loop scanner saw only %d menus: the scan itself is broken' % n)
sys.exit(R.finish())
