#!/usr/bin/env bash
# ADF registry drift: what an ADF file registers, what the import file loads, and what the functions are.   bash tests/adf_registry.sh
# (1) every file that registers an ADF function is loaded by an import file (no exceptions: a dead adf file is deleted, not listed)
# (2) every adf file an import file loads exists
# (3) a file_fx action is registered with _fx_adf_register_fx (its tree path comes from the label), never with a typed file_fx/ path
# (4) every registered function name is defined
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/script"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

loaded="$(grep -rhoE 'source +"?bashbasicsbyvk_[A-Za-z0-9_]+\.sh' "$S" --include='_3bvk_import_*.sh' | sed -E 's/source +"?//' | sort -u)"
miss=""
while IFS= read -r f; do
  b="${f##*/}"
  grep -qxF "$b" <<<"$loaded" || miss+="$b "
done < <(grep -rlE '^_fx_adf_register(_fx)? +"' "$S" --include='*.sh')
[ -z "$miss" ] && ok "every file that registers an ADF function is loaded by an import file" || bad "registers ADF functions but no import file loads it: $miss"

gone=""
for b in $(grep -hoE 'bashbasicsbyvk_adf_[A-Za-z0-9_]+\.sh' "$S"/file/loops/iloop/fx/_3bvk_import_fx.sh | sort -u); do
  [ -n "$(find "$S" -name "$b" -print -quit)" ] || gone+="$b "
done
[ -z "$gone" ] && ok "every adf file the fx import file loads exists" || bad "fx import file loads files that do not exist: $gone"

typed="$(grep -rnE '^_fx_adf_register +"[^"]+" +"[^"]+" +"file_fx/' "$S" --include='*.sh' | head -3)"
[ -z "$typed" ] && ok "no file_fx action types its own tree path (_fx_adf_register_fx derives it)" || bad "typed file_fx path, use _fx_adf_register_fx: $typed"

undef=""
while IFS= read -r fn; do
  grep -rqE "^[[:space:]]*(function +)?${fn}[[:space:]]*\(\)" "$S" --include='*.sh' || undef+="$fn "
done < <(grep -rhE '^_fx_adf_register(_fx)? ' "$S" --include='*.sh' | sed -E 's/^_fx_adf_register(_fx)? +"[^"]+" +"?([A-Za-z0-9_]+)"?.*/\2/' | sort -u)
[ -z "$undef" ] && ok "every registered function name is defined" || bad "registered but not defined: $undef"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
