#!/usr/bin/env bash
# ============================================================
#  TIDY 🧶  —  "which template is this menu?"
#
#  Typed at any prompt that takes u or q:   tidy
#  prints the TEMPLATE ID of the screen you are on (6 letters / digits, e.g. K7M2QX) and asks what to do with it,
#  the same two options as  print  and  p- :   1) copy to clipboard   2) save as txt
#
#  A template ID names a LAYOUT TEMPLATE, not a screen: every screen built on the same template has the same ID
#  (Delete and Rename are both "step menu").  Why: to tell the agent "make every menu with template ID A look like template ID B"
#  without it hunting through the code.  The list is ONE file, bashbasicsbyvk_tidy.list  (ID | template | key | file);
#  bashbasicsbyvk_tidy_gen shows, moves (--set) and checks it.
#
#  How the screen is found (nothing is recorded while you navigate; this runs only when  tidy  is typed)
#  -----------------------------------------------------------------------------------------------------
#     1. the call stack: the innermost function on it that the list names is the screen: a picker inside a wizard is the picker,
#        and a question asked by ANY flow (_mc_steps, _mc_select, _bvk_menu ...) is a step menu, whichever flow asked it
#     2. else the command map of the menu that is up  (map:fx, map:transfer ...)
#     3. else map:main
# ============================================================

_BVK_TIDY_LIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/bashbasicsbyvk_tidy.list"

# _bvk_tidy_find  → sets _TIDY_ID _TIDY_KEY _TIDY_FILE  (empty when the list has no entry)
_bvk_tidy_find() {
  _TIDY_ID=""; _TIDY_KEY=""; _TIDY_FILE=""; _TIDY_TMPL=""
  [ -r "$_BVK_TIDY_LIST" ] || return 1
  local -A _ti_id=() _ti_file=() _ti_tmpl=()
  local l id tmpl key file
  while IFS='|' read -r id tmpl key file; do
    id="${id//[[:space:]]/}"; key="${key//[[:space:]]/}"; tmpl="${tmpl%"${tmpl##*[![:space:]]}"}"; tmpl="${tmpl#"${tmpl%%[![:space:]]*}"}"; file="${file#"${file%%[![:space:]]*}"}"; file="${file%"${file##*[![:space:]]}"}"
    [[ "$id" == "" || "$id" == "#"* ]] && continue
    _ti_id[$key]="$id"; _ti_file[$key]="$file"; _ti_tmpl[$key]="$tmpl"
  done < "$_BVK_TIDY_LIST"
  local fn
  for fn in "${FUNCNAME[@]}"; do
    if [ -n "${_ti_id[fn:$fn]:-}" ]; then _TIDY_KEY="fn:$fn"; break; fi
  done
  [ -n "$_TIDY_KEY" ] || { [ -n "${_ti_id[map:${_CM_MAP:-main}]:-}" ] && _TIDY_KEY="map:${_CM_MAP:-main}"; }
  [ -n "$_TIDY_KEY" ] || _TIDY_KEY="map:main"
  _TIDY_ID="${_ti_id[$_TIDY_KEY]:-}"; _TIDY_FILE="${_ti_file[$_TIDY_KEY]:-}"; _TIDY_TMPL="${_ti_tmpl[$_TIDY_KEY]:-}"
  [ -n "$_TIDY_ID" ]
}

# _bvk_tidy_show ID   the rows of the template file (comments left out), as the file has them
_bvk_tidy_show() {
  local f l; f="$(_tpl_file "$1" 2>/dev/null)"; [ -r "$f" ] || return 0
  builtin printf '\n'
  while IFS= read -r l || [ -n "$l" ]; do [[ "$l" == "#"* ]] && continue; builtin printf '   │ %s\n' "$l"; done < "$f"
  builtin printf '\n'
}

# `tidy` — show the template ID, then copy / save
bvk_tidy_cmd() {
  declare -F _lt_tool_begin >/dev/null 2>&1 && _lt_tool_begin
  if _bvk_tidy_find; then
    builtin printf '🧶 Template ID: %s  (%s)\n   screen: %s   %s\n   template: templates/bashbasicsbyvk_%s.sh.tpl\n' "$_TIDY_ID" "$_TIDY_TMPL" "${_TIDY_KEY#*:}" "$_TIDY_FILE" "$_TIDY_ID"
    _bvk_tidy_show "$_TIDY_ID"
    declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
    if declare -F _map_deliver >/dev/null 2>&1; then
      _map_deliver "$_TIDY_ID" "bvk-template-$_TIDY_ID.txt"
    fi
  else
    builtin printf '🧶 This screen has no template ID yet (run bashbasicsbyvk_tidy_gen --write).\n'
  fi
  declare -F _lt_tool_end >/dev/null 2>&1 && _lt_tool_end
  return 0
}
