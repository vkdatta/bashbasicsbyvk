#!/usr/bin/env bash
# tests/static/lib/load.sh — THE one way a test loads the command engine.  `source` it, then call bvk_load.
#   * the load order lives here and nowhere else (advert before cheatcode; cmdmap before every *commands.sh)
#   * a file that fails to source stops the test with ITS name — no `2>/dev/null`, no mass failure with a misleading message
#   * every handler a cmd_def names but this process does not define gets a no-op stub, so _cm_resolve judges the WIRING, not the app's state
BVK_ROOT="${BVK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
BVK_F="$BVK_ROOT/script/file"; SCRIPT_DIR="$BVK_F"
_bvk_src() { local f="$1"; [ -f "$f" ] || { echo "LOAD FAIL: missing $f" >&2; return 90; }
  # shellcheck disable=SC1090
  source "$f" || { echo "LOAD FAIL: $f returned $?" >&2; return 91; }; }
bvk_load() {   # [cc]  — "cc" also loads advert.sh + cheatcode.sh
  local d f want_cc="${1:-}"
  for d in "$BVK_F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
  [ "$want_cc" = cc ] && { declare -gA _MC_KEYLABEL=([u.up]="Up" [z]="Cancel"); _bvk_src "$BVK_F/engine/bashbasicsbyvk_advert.sh" || return $?; }
  _bvk_src "$BVK_F/engine/bashbasicsbyvk_cmdmap.sh" || return $?
  for f in "$BVK_F"/cmdmap/*/*commands.sh; do _bvk_src "$f" || return $?; done
  [ "$want_cc" = cc ] && { _bvk_src "$BVK_F/engine/bashbasicsbyvk_cheatcode.sh" || return $?; }
  _cm_boot
  local k h
  for k in "${!_CM_DEF[@]}"; do h="${_CM_DEF[$k]#*|}"; h="${h%%|*}"; case "$h" in -|back|"") ;; *) declare -F "$h" >/dev/null || eval "$h() { :; }" ;; esac; done
  return 0
}
