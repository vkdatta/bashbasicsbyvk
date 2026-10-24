#!/usr/bin/env bash
# The upgrade loop now reads releases / tags / commits through the helpers it shares with the GitHub screens (bashbasicsbyvk_ghlib.sh).
# Its output must be exactly what the code it replaced printed: fixtures/upgrade_golden.txt was produced by the ORIGINAL upgrade loop.
export LC_ALL=C.UTF-8   # declare -p prints non-ASCII differently per locale (AGENTS: tests force UTF-8)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; HERE="$ROOT/tests/github"
need() { find "$ROOT/script" -name "$1" -type f | head -n 1; }
UP="$(need bashbasicsbyvk_upgrade.sh)"; LIB="$(need bashbasicsbyvk_ghlib.sh)"; TOOL="$(need bashbasicsbyvk_github)"
[ -n "$UP" ] && [ -n "$LIB" ] && [ -n "$TOOL" ] || { echo "FAIL files not found"; exit 1; }
out="$(SCRIPT_DIR="$(dirname "$TOOL")" bash -c '
FIX="$1"; UP="$2"; LIB="$3"
_bvk_tabs_register(){ :; }; _vp_filter_header_line(){ :; }; _mc_footer(){ :; }; _lb_run(){ shift; "$@"; }; _bvk_yn(){ :; }
source "$LIB"; source "$UP"
_upg_http_get() { case "$1" in */releases*) cat "$FIX/fx_releases.json" ;; */commits/*) cat "$FIX/fx_commit.json" ;; *) return 1 ;; esac; }
_upg_ls_remote_tags() { cat "$FIX/fx_ls.txt"; }
_upg_load_stable; echo "stable rc=$? err=[$_UPG_S_ERR]"; declare -p _UPG_S_TAG _UPG_S_NAME _UPG_S_DATE _UPG_S_BODY
_upg_load_tags;   echo "tags rc=$? err=[$_UPG_T_ERR]";   declare -p _UPG_T_TAG
items=("${_UPG_S_TAG[@]}"); _upg_tab=stable; _upg_cmd_info 1; _upg_cmd_info 2
items=("${_UPG_T_TAG[@]}"); _upg_tab=tags; _upg_cmd_info 1
_upg_http_get() { return 1; }
_UPG_S_LOADED=0; _upg_load_stable; echo "offline stable rc=$? err=[$_UPG_S_ERR]"
' _ "$HERE/fixtures" "$UP" "$LIB" 2>&1)"
if [ "$out" == "$(cat "$HERE/fixtures/upgrade_golden.txt")" ]; then echo "PASS upgrade loop output is byte-identical to the original code's"; else
  echo "FAIL upgrade loop output changed:"; diff <(echo "$out") "$HERE/fixtures/upgrade_golden.txt" | head -20; exit 1; fi
