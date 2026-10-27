#!/usr/bin/env bash
# The load mapper (AGENTS.md rule 13).   bash tests/loadmap.sh
# (1) the checker: every file is mapped once, no fg file needs a later / non-fg file, the generated stubs file is current
# (2) the app paints with only the [fg] files loaded, and its stubs are there
# (3) a stub loads its file (and the files it needs) on the first call, and runs the real function
# (4) after everything loaded, the app has the same functions as the old "load everything first" (BVK_LOADMAP=all)
# (5) o never sources anything itself except the loader (rule 3: the loader is the one place)
set -u
source "$(dirname "${BASH_SOURCE[0]}")/wait_lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/script"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
GEN="$(bvk_need bashbasicsbyvk_loadmap_gen)"

# ---- (1) -------------------------------------------------------------------------------
out="$(python3 -W ignore -I "$GEN" --root "$ROOT" --check 2>&1)"; rc=$?
[ $rc = 0 ] && ok "$(tail -1 <<<"$out")" || { bad "loadmap_gen --check"; printf '%s\n' "$out" | cut -c1-260 | head -12; }

# a flat bin/ like the install makes
B="$T/bin"; mkdir "$B"; python3 -I - "$ROOT" "$B" <<'PY'
import os, sys
r, b = sys.argv[1:3]
for dp, dn, fn in os.walk(os.path.join(r, 'script')):
    if 'bvk-' in dp: continue
    for f in fn:
        d = os.path.join(b, f)
        if not os.path.exists(d): os.symlink(os.path.join(dp, f), d)
PY
export HOME="$T/home" TERM=xterm LANG=C.UTF-8 PATH="$B:$PATH"; mkdir -p "$HOME"

# ---- (2) + (3) -------------------------------------------------------------------------
(cd "$T" && bash -c '
  source bashbasicsbyvk_loadmap.sh; _lm_fg || exit 9
  declare -F _vp_render_fresh >/dev/null && echo "fg:render" >&3
  declare -F _shortcut_read_field >/dev/null && echo "fg:stub_ready_before_paint" >&3
  [ -z "${_LM_DONE[bashbasicsbyvk_transfer.sh]:-}" ] && echo "fg:transfer_not_loaded" >&3
  _lm_ensure_stubs
  [ "$(declare -f transfer_menu | grep -c _lm_stub)" = 1 ] && echo "stub:transfer_menu" >&3
  _lm_load bashbasicsbyvk_transfer.sh
  [ "$(declare -f transfer_menu | grep -c _lm_stub)" = 0 ] && echo "real:transfer_menu" >&3
  echo "type:$(type -t _bvk_yn)" >&3
' >/dev/null 2>&1 3>"$T/res"); res="$(cat "$T/res")"
for w in "fg:render" "fg:transfer_not_loaded" "stub:transfer_menu" "real:transfer_menu"; do
  grep -qx "$w" <<<"$res" && ok "$w" || { bad "$w"; echo "$res" | head -5; }
done
grep -qx 'fg:stub_ready_before_paint' <<<"$res" && ok "the stubs are there before the first paint (an [fg] function calling _shortcut_read_field of transfer.sh must not get 'command not found')" || bad "no stub for a [bg] function right after _lm_fg: a first paint that calls it fails with 'command not found'"
grep -qx 'type:function' <<<"$res" && ok "a stub shows as a function (declare -F keeps working)" || bad "type -t of a stubbed function: $(grep '^type:' <<<"$res")"

[ -f "$ROOT/tests/loadmap/shortcut_paint.py" ] && { python3 -I "$ROOT/tests/loadmap/shortcut_paint.py" "$ROOT" || fail=1; }   # the real first paint, in a pty

# ---- (4) -------------------------------------------------------------------------------
fns() { (cd "$T" && bash -c "$1" 2>"$T/err.$2" | sort); }
new="$(fns 'source bashbasicsbyvk_loadmap.sh; _lm_fg; _lm_all; declare -F | sed "s/declare -f //"' new)"
old_all="$(cd "$T" && BVK_LOADMAP=all bash -c 'source bashbasicsbyvk_loadmap.sh; _lm_fg; declare -F | sed "s/declare -f //"' 2>/dev/null | sort)"
[ "$new" = "$old_all" ] && ok "map mode and BVK_LOADMAP=all end with the same $(wc -l <<<"$new") functions" || { bad "function sets differ"; diff <(echo "$new") <(echo "$old_all") | head -8; }
[ ! -s "$T/err.new" ] && ok "loading every file prints nothing on stderr" || { bad "stderr while loading everything"; head -5 "$T/err.new"; }
(cd "$T" && bash -c 'source bashbasicsbyvk_loadmap.sh; _lm_fg; _lm_all; for f in $(declare -F | sed "s/declare -f //"); do declare -f $f | grep -q "_lm_stub " && [ "${f:0:4}" != _lm_ ] && echo "$f" >&3; done' >/dev/null 2>&1 3>"$T/nd"); nd="$(cat "$T/nd")"
[ -z "$nd" ] && ok "after everything loaded, no function is still a stub" || { bad "still a stub (defined by no file that loaded?): $(echo $nd | cut -c1-200)"; }

# ---- (5) -------------------------------------------------------------------------------
n="$(grep -cE '(^|[;&|({]|[[:space:]])(source|\.)[[:space:]]+["$]' "$S/o")"
[ "$n" = 1 ] && ok "o has exactly one source line (the loader)" || bad "o sources $n things: only bashbasicsbyvk_loadmap.sh may be sourced by o"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
