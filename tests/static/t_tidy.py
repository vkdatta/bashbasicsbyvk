"""TEMPLATE IDs — every menu is built on a TEMPLATE and each template has a 6-character ID (🧶 tidy prints it); screens on the same template share the ID, and the list names real things.
The rules live in script/file/engine/debug/tidy/bashbasicsbyvk_tidy_gen (problems()); this suite only runs them:
  every command map and every menus.list function is listed · IDs are 6 capital letters/digits with at least one of each · one ID per template, one template per ID, no key twice ·
  every fn: key is a defined function and every map: key a command map · the file column is current · every template ID has its templates/bashbasicsbyvk_<ID>.sh.tpl, uses only sections / placeholders the global definer defines, defines nothing itself, and every definer name is used · the processor loads each template and passes _tpl_check · the `tidy` word is in every map that has `print`."""
import os, re, sys
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('tidy')
p = os.path.join(bvk.F, 'engine', 'debug', 'tidy', 'bashbasicsbyvk_tidy_gen')
spec = spec_from_loader('tidy_gen', SourceFileLoader('tidy_gen', p)); g = module_from_spec(spec); spec.loader.exec_module(g)
rs = g.rows(); R.check(len(rs) + 3)
for b in g.problems(rs, g.functions(), g.maps()): R.add('tidy:list:' + re.sub(r'\W+', '_', b)[:60], b)
for m, v in sorted(bvk.parse_maps().items()):                       # a map that answers print answers tidy
    txt = bvk.read(v['file']); R.check()
    if re.search(r'^print\s+\.mapto\(\)', txt, re.M) and not re.search(r'^tidy\s+\.mapto\(\)', txt, re.M): R.add('tidy:map:' + m, 'map %s answers print but not tidy' % m)
# the processor itself: every template loads and passes its own check (bash, no app start: the definer + the processor only)
import subprocess
T = os.path.join(bvk.F, 'templates')
ids = sorted({r[0] for r in rs}); R.check(len(ids))
cmd = 'source "%s/bashbasicsbyvk_tpl_defs.sh"; source "%s/bashbasicsbyvk_tpl.sh"; rc=0; for i in %s; do _tpl_check "$i" || rc=1; done; exit $rc' % (T, T, ' '.join(ids))
r = subprocess.run(['bash', '-c', cmd], capture_output=True, text=True)
for l in (r.stdout + r.stderr).splitlines(): R.add('tidy:tpl:' + re.sub(r'\W+', '_', l)[:60], l)
sys.exit(R.finish())
