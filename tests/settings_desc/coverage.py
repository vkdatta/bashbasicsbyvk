"""Every Settings screen and every literal row has a plain-words description (AGENTS rule 8).   python3 -I tests/settings_desc/coverage.py <script/file dir>
Screens: every  _st_run "Title" builder  with a literal title needs  "Title|*"  (or  "<parent>›Title|*").
Rows:    every  _st_add TYPE "label" VALUE "hint" TAG  in that screen's builder function with a literal TAG needs  "Title|TAG"  (or a parent-qualified key).
Titles and tags built at run time (a "$var" in them) cannot be checked here and are skipped; the table test checks the table itself."""
import re, glob, sys
root = sys.argv[1]
src = open(f'{root}/settings/bashbasicsbyvk_settings_desc.sh', encoding='utf-8').read()
body = src.split("<<'BVK_DESC_EOF'\n")[1].split('\nBVK_DESC_EOF')[0]
keys = set(l.split('\t')[0] for l in body.split('\n') if l)
files = {f: open(f, encoding='utf-8').read() for f in glob.glob(root + '/**/*.sh', recursive=True) if 'settings_desc' not in f}
alltext = '\n'.join(files.values())
def has(t, tag):
    return any(k == f'{t}|{tag}' or k.endswith(f'›{t}|{tag}') or k.endswith(f'› {t}|{tag}') for k in keys)
miss, screens, rows = set(), 0, 0
for f, txt in files.items():
    for m in re.finditer(r'^[^#\n]*_st_run +"([^"$]+)" +([A-Za-z_][A-Za-z0-9_]*)', txt, re.M):
        t, fn = m.group(1), m.group(2)
        if t == 'Title' or not fn.startswith(('_', 'a', 'b')) and False: continue
        screens += 1
        if not has(t, '*'): miss.add(f'screen "{t}"  (needs the key  {t}|*)')
        b = re.search(r'^' + re.escape(fn) + r'\(\) *\{\n(.*?)^\}', alltext, re.S | re.M)
        if not b: continue
        for l in b.group(1).split('\n'):
            if l.strip().startswith('#'): continue
            mm = re.match(r'\s*_st_add +[a-z] +"[^"]*" +\S+ +.*?\s([A-Za-z0-9_.-]+:?) *(#.*)?$', l)
            if not mm: continue
            tag = mm.group(1)
            if tag.endswith(':'): continue
            rows += 1
            if not has(t, tag): miss.add(f'row "{t}" tag "{tag}"  (needs the key  {t}|{tag})')
print(f'  checked {screens} screens, {rows} literal rows')
if miss:
    for x in sorted(miss): print('  FAIL no description for', x)
    sys.exit(1)
print('  ok   every Settings screen and literal row has a description')
