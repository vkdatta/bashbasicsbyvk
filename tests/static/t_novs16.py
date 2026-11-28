"""NO U+FE0F in script/ — the emoji variation selector makes a text-default emoji (⚙ ☁ 🗑 ⚠ ↩ ...) paint 1 cell on one terminal and 2 on another
(a gap between the icon and the text in a highlighted row, a caret one cell off).  Without it every terminal draws the emoji the way _vp_cpw counts it.
Write the bare character (⚙ not ⚙️).  Wide emoji (📁 🧩 ✅) never need it."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'lib')); import bvk
R = bvk.Report('novs16')
for p in bvk.all_files():
    t = bvk.read(p); R.check()
    if '\ufe0f' in t or '\\ufe0f' in t.lower():
        R.add('novs16:' + bvk.rel(p).replace('/', '_'), '%s: %d x U+FE0F (write the bare emoji)' % (bvk.rel(p), t.count('\ufe0f') + t.lower().count('\\ufe0f')))
sys.exit(R.finish())
