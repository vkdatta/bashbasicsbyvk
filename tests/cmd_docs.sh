#!/usr/bin/env bash
# The command reference in llms-full.txt is generated from cmd_def (o --map-doc).   bash tests/cmd_docs.sh [--write]
# (1) the pasted table equals what the code generates now   (2) every main command id is in it
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; F="$ROOT/script/file"; DOC="$ROOT/llms-full.txt"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

gen() ( SCRIPT_DIR="$F"; for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
        source "$F/engine/bashbasicsbyvk_cmdmap.sh"; for f in "$F"/cmdmap/*/*commands.sh; do source "$f"; done; _cm_doc )
cur() { sed -n '/<!-- cmd-ref:start -->/,/<!-- cmd-ref:end -->/p' "$DOC" | sed '1d;$d'; }

new="$(gen)"
if [ "${1:-}" = "--write" ]; then
  python3 - "$DOC" "$new" <<'PY'
import sys,re
p,new=sys.argv[1],sys.argv[2]
s=open(p,encoding='utf-8').read()
s2=re.sub(r'(<!-- cmd-ref:start -->\n).*?(\n<!-- cmd-ref:end -->)',lambda m:m.group(1)+new+m.group(2),s,flags=re.S)
open(p,'w',encoding='utf-8').write(s2)
PY
  echo "refreshed $DOC"
fi
grep -q 'cmd-ref:start' "$DOC" && grep -q 'cmd-ref:end' "$DOC" && ok "llms-full.txt has the generated command block" || bad "llms-full.txt lost its cmd-ref markers"
n="$(grep -c '^| `' <<<"$new")"; [ "$n" -ge 60 ] && ok "generator printed $n commands" || bad "generator printed only $n commands (cmd_def loading broke?)"
if [ "$(cur)" = "$new" ]; then ok "pasted command table is up to date"; else bad "command table in llms-full.txt is stale: run  bash tests/cmd_docs.sh --write"; diff <(cur) <(echo "$new") | head -6; fi
miss=""; while IFS= read -r id; do grep -qF "| \`$id\` |" <(cur) || miss+="$id "; done < <(grep -oE '^\| `[^`]+`' <<<"$new" | sed -E 's/^\| `//; s/`$//')
[ -z "$miss" ] && ok "every main command is in the docs" || bad "missing from the docs: $miss"
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
