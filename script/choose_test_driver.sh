#!/usr/bin/env bash

# THE LOAD MAPPER (AGENTS.md rule 13): the first file o loads. It reads bashbasicsbyvk_loadmap.list before anything else is loaded, and
# loads only what that list says: [fg] now (what the first paint needs), [bg] after the paint (_lm_idle, below), [no] only when called.
source "bashbasicsbyvk_loadmap.sh"
_lm_fg || exit 1

# Inner-loop driver: sw, fx, r (the .r rule book), upg (the -u upgrade loop), api (the link manager), pn (Pending uploads), bk (Backup), sv (Saved Surf), sn (Snapshots), rbam, nf (notifications) and cs (cloud surf) hand over to each other via _inner_next,
# while the outer main loop stays untouched.
_inner_next=""
_inner_run() {
  local _next="$1"
  while [ -n "$_next" ]; do
    _inner_next=""
    case "$_next" in
      sw) switch_menu ;;
      fx) functions_menu ;;
      r)  rules_menu ;;
      upg) upgrade_menu ;;
      api) api_menu ;;
      pn)  pending_menu ;;
      bk)  backup_menu ;;
      sv)  saved_menu ;;
      sn)  snapshot_menu ;;
      rbam) rbam_menu ;;
      nf)  notify_menu ;;
      cs)  csurf_menu ;;
      cs-recv) csurf_menu 1 ;;
      gdp) gdrive_profiles_menu ;;
    esac
    [ "${_BVK_TO_MAIN:-0}" = 1 ] && break      # q somewhere inside: close to the main loop (u only ever goes back one screen)
    _next="$_inner_next"
  done
}

_bvk_d="${BASH_SOURCE[0]}"; case "$_bvk_d" in */*) _bvk_d="${_bvk_d%/*}" ;; *) _bvk_d=. ;; esac   # no dirname process
SCRIPT_DIR="$(cd -- "$_bvk_d" && pwd)"; unset _bvk_d

_lt_b "start: dependencies"
command -v python3 >/dev/null 2>&1 || { _lm_need bashbasicsbyvk_deps.sh; _dep_need -c "Starting the app" app.core || exit 1; }   # python3: only when it is missing does the central registry (bashbasicsbyvk_deps.list) load and offer to install it
_lt_e
# the usage ping, the local daemon and the alien daemon start after the first paint: the @call lines of [bg] in bashbasicsbyvk_loadmap.list
_lt_b "start: terminal colours + screen setup"; _disp_startup; _lt_e
_lt_b "start: native engine probe"; _bvk_go_bin; _lt_e   # once, HERE in the main shell: inside a $(...) subshell its cache is lost and it would re-probe on every call
_lt_b "start: engines fit this machine?"; _bvk_engine_heal "$@"; _lt_e   # install made on another CPU / OS: offer a reinstall

trap '[ "${_GD_ACTIVE:-0}" = 1 ] && _gd_on_exit 2>/dev/null; _lt_cleanup; _bvk_paste_off 2>/dev/null; _bvk_mouse_off 2>/dev/null; stty "$_orig_stty" 2>/dev/null; \
      [ -n "$path" ] && printf "%s" "$path" > "$_BVK_LASTDIR_FILE"; \
      [ -n "${_BVK_DSIZE_TMP:-}" ] && rm -rf "$_BVK_DSIZE_TMP" 2>/dev/null; \
      true' EXIT

_orig_stty=$(stty -g 2>/dev/null)

# command map tooling:  o --map-show [menu] · o --map-lint · o --map-doc · o --map-gen
case "${1:-}" in
  --map-show) _lm_all; _cm_show "${2:-main}"; exit $? ;;
  --map-lint) _lm_all; _cm_lint; exit $? ;;
  --map-doc)  _lm_all; _cm_doc; exit $? ;;
  --map-gen)  _mg=$(_cm_find bashbasicsbyvk_mapgen) && exec python3 "$_mg" "${@:2}"; echo "mapgen not found"; exit 1 ;;
esac



echo READY
_bvk_yn a1 "Keep these?" -d n;                         builtin echo "R1 [$a1] rc=$?"
_bvk_yn a7 "Delete these?" -d n;                       builtin echo "R7 [$a7] rc=$?"
_bvk_yn a2 "Back up first?" -d y -c;                   builtin echo "R2 [$a2] rc=$?"
_bvk_yn a3 "Sure?" -d n;                               builtin echo "R3 [$a3] rc=$?"
_bvk_menu m1 -t "Pick" "a:Apple" "b:Banana" "c:Cherry"; builtin echo "R4 [$m1] rc=$?"
_bvk_menu m2 -m -t "Fruits" "a:Apple" "b:Banana" "c:Cherry"; builtin echo "R5 [$m2] rc=$?"
_bvk_yn a6 "Last one?" -c;                             builtin echo "R6 [$a6] rc=$? abort=$_CM_ABORT"
exit 0
