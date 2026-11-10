#!/usr/bin/env bash
# Every screen that runs _xui_loop is WIRED: it has its own map (cmdmap/xui_<prefix>/), and every key its handler accepts or its footer prints
# resolves to the screen itself (local, or plain text that reaches the handler) - never to a blocked / main command of the generic xui map.
# This is the bug that hid cfw / gdp / cs_pp / ct / ru: no map -> silent fallback to `xui` -> "Invalid command: r - not available in xui", and
# `rf` swallowed by the main redraw.  o --map-lint cannot see a screen that has no map; this test can.   bash tests/xui_wiring.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; F="$ROOT/script/file"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

# 1. what the code says: screens (prefix, handler) and the keys they use, straight from the sources
SCAN=$(python3 -I - "$ROOT/script" <<'PY'
import os, re, sys
sd = sys.argv[1]; files = {}
for dp, dn, fn in os.walk(sd):
    if '/tools/' in dp or 'bvk-' in dp: continue
    for f in fn:
        if f.endswith(('.py', '.c', '.h', '.txt', '.md', '.list', '.map', '.mjs', '.json', '.go')) or 'stubs' in f: continue
        try: files[os.path.join(dp, f)] = open(os.path.join(dp, f), errors='replace').read().split('\n')
        except OSError: pass
def body(name):
    for p, L in files.items():
        for i, l in enumerate(L):
            if re.match(r'^' + re.escape(name) + r'\(\)\s*\{', l):
                if l.rstrip().endswith('}'): return l
                out = [l]; j = i + 1
                while j < len(L) and not L[j].startswith('}'): out.append(L[j]); j += 1
                return '\n'.join(out)
    return ''
screens = {}
for p, L in files.items():
    for i, l in enumerate(L):
        m = re.search(r'(?<![A-Za-z_])_xui_screen\s+([a-z][a-z_0-9]*)\s*($|[;#&|])', l)
        if not m or l.lstrip().startswith('#'): continue
        for j in range(i, min(i + 14, len(L))):
            h = re.search(r'(?<![A-Za-z_])_xui_loop\s+([A-Za-z_0-9]+)', L[j])
            if h: screens[m.group(1)] = h.group(1); break
            if j > i and re.match(r'^\}', L[j]): break
def norm(k):
    k = k.strip().strip('"\'')
    if not k or k == '*' or '\\' in k or k[0] in '[$_@#' or k[0].isdigit() or '"' in k or ' ' in k: return None
    k = re.sub(r'-?N$', lambda m: '-1' if m.group(0).startswith('-') else '', k).replace('*', '1')
    if k in ('u', 'a', 'a-1', 'N') or not re.match(r'^[a-z][a-z.0-9-]*$', k): return None
    return k
for pfx, h in sorted(screens.items()):
    print('SCREEN', pfx, h)
    keys = set()
    b = body(h)
    for l in b.split('\n'):
        am = re.match(r'^\s{2,8}([^\s#()][^)]*)\)\s', l + ' ')
        if am and not l.strip().startswith(('case', 'if', 'echo', 'local', 'for', 'while', 'return', '[[')):
            for k in am.group(1).split('|'):
                k = norm(k)
                if k: keys.add(k)
    for tok in re.findall(r'"([a-z][a-z.0-9-]*(?:-N)?)(?::[^"]*)?"', body(pfx + '_footer')):
        k = norm(tok)
        if k: keys.add(k)
    for k in sorted(keys): print('KEY', pfx, k)
PY
)
[ -n "$SCAN" ] || { bad "found no _xui_loop screen at all - the scanner is broken"; exit 1; }

# 2. what the command map says
SCRIPT_DIR="$F"
for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
source "$F/engine/bashbasicsbyvk_cmdmap.sh"
for f in "$F"/cmdmap/*/*commands.sh; do source "$f"; done
_cm_boot; _cm_ensure_all
nscreens=0 nkeys=0
while read -r kind a b c; do
  if [ "$kind" = SCREEN ]; then
    nscreens=$((nscreens + 1))
    if [ -f "$(find "$F/cmdmap" -name "bashbasicsbyvk_xui_$a.map" | head -1)" ] && [ -n "${_CM_MAP_KIND[xui_$a]+x}" ]; then ok "screen $a (loop $b) has its own map xui_$a"
    else bad "screen $a (loop $b) has NO map: add script/file/cmdmap/xui_$a/ (a .map + a menucommands.sh, copy xui_ghr) and the loadmap lines; until then the generic xui map blocks its own keys"; fi
  else
    nkeys=$((nkeys + 1)); m="xui_$a"; [ -n "${_CM_MAP_KIND[$m]+x}" ] || m=xui
    _CM_MAP="$m"; _cm_table_build "$m"; _cm_resolve menu "$b"
    case "$_CM_ACT" in
      local|none) ok "$a: $b reaches the screen ($_CM_ACT, map $m)" ;;
      *)          bad "$a: its own key '$b' resolves to '$_CM_ACT' in map $m (it must be local in xui_$a)" ;;
    esac
  fi
done <<<"$SCAN"
[ "$nscreens" -ge 10 ] && ok "scanned $nscreens xui loop screens, $nkeys keys" || bad "only $nscreens screens found - the scanner lost some"
[ "$fail" = 0 ] && echo "xui wiring: OK" || echo "xui wiring: FAILED"; exit "$fail"
