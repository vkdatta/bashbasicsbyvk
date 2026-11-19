"""TEMPLATE IDs — every menu is built on a TEMPLATE and each template has a 6-character ID (🧶 tidy prints it); screens on the same template share the ID, and the list names real things.
The rules live in script/file/engine/debug/tidy/bashbasicsbyvk_tidy_gen (problems()); this suite only runs them:
  every command map and every menus.list function is listed · IDs are 6 capital letters/digits with at least one of each · one ID per template, one template per ID, no key twice ·
  every fn: key is a defined function and every map: key a command map · the file column is current · the `tidy` word is in every map that has `print`."""
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
sys.exit(R.finish())
