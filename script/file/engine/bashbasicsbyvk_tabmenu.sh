# ============================================================
#  bashbasicsbyvk_tabmenu.sh — THE master template of every menu that has tabs
#
#  fx (Functions) is the reference: its spacing was etched by hand, and this file is that layout, moved here ONCE.
#  Every tabbed screen (fx, sw, .r rule book, -u upgrade, rbam, cs, a GitHub repo) builds its header, footer and
#  tab switching from these helpers, so a change to the look of tabbed menus is a change in THIS file only.
#
#  What the screen looks like (the viewport draws the rules and the blank rows around header / footer, see _vp_build_chrome):
#
#      <blank>
#      🎨 Title                                  _TM_TITLE        (a screen may pass its own, e.g. the repo name)
#      <blank>
#      [🪄 ADF] 🎃 UDF                           tab bar: the current tab in [ ], tappable (bashbasicsbyvk_mouse.sh)
#      <blank>
#      One plain-words line about this tab.      from the Settings description table, ONE row, cut with …
#      X out of N here                           _tm_count_line   (a screen adds its own context lines after it:
#      📂 Path: …                                a path, an error, "installed: …", the filter line)
#      ─────────────────────────────
#      rows
#      ─────────────────────────────
#      <blank>
#      u) Up   q) Quit   h) Home   cc) Cheat codes        _tm_footer  (every other key is listed by cc)
#      <suggestion row>                          the live hint of the typed word (the viewport draws it)
#      Select:
#
#  A tabbed screen is five small pieces:
#
#    1. DEFINE (once, at load):   _tm_define NAME STATEVAR "📚 Title" "Desc screen" key:"🧩 Label" key:"🕘 Label" …
#         NAME      this screen's handle for every call below            (rules, sw, upg, rb, cs, ghr, fx …)
#         STATEVAR  the variable that holds the CURRENT tab's key        (_rl_tab, _sw_tab, _RB_TAB …) — the screen keeps owning it
#         Desc screen   the first half of the description keys:          "<Desc screen>|<tab key>"  or  "<Desc screen>|<tab key>:<folder>"
#         key:Label     one per tab, left to right; the label is exactly what the bar prints and what a tap hits
#    2. HEADER:  _tm_header NAME [title] [folder]   then the screen's own context lines, then  _vp_filter_header_line
#    3. FOOTER:  _tm_footer [-b] [extra items…]     -b = the screen has no folders: u reads "Back", not "Up"
#    4. KEYS:    _tm_key NAME "$choice" [nowrap]    in the loop, for  __sw_tab_right__ | __sw_tab_left__  (moves the state variable)
#    5. REDRAW:  _tm_tab_redraw BUILD_FN SET_FN     in-place repaint after a tab change;   _tm_viewport HDR FTR [ROWTEXT]  sets the viewport
#
#  A new description line:  add  "<Desc screen>|<tab key>"  to bashbasicsbyvk_settings_desc.sh (nothing breaks without one).
# ============================================================

declare -gA _TM_VAR=() _TM_N=() _TM_KEY=() _TM_LAB=() _TM_TITLE=() _TM_SCREEN=()
declare -g  _TM_I=0                         # _tm_idx result: the 0-based position of the current tab
_TM_TAB_SEP=" "                             # what sits between two tab labels (the tap hit-test measures it, so it can be changed here)

# the ONE footer every tabbed menu shows (generic keys take their label from _MC_KEYLABEL in menuchrome.sh)
_mc_footer_register tabmenu      "${_MC_FOOTERS[std_nav]}"          # = the standard footer of menuchrome.sh (FOOTER-01): one copy
_mc_footer_register tabmenu_back "${_MC_FOOTERS[std_nav_back]}"

# _tm_define NAME STATEVAR TITLE DESC_SCREEN key:Label...      (see the header of this file)
_tm_define() {
  local name="$1" var="$2" it i=0
  _TM_VAR[$name]="$var"; _TM_TITLE[$name]="$3"; _TM_SCREEN[$name]="$4"
  shift 4
  local -a labs=()
  for it in "$@"; do
    _TM_KEY["$name:$i"]="${it%%:*}"; _TM_LAB["$name:$i"]="${it#*:}"; labs+=("${it#*:}")
    i=$(( i + 1 ))
  done
  _TM_N[$name]=$i
  _bvk_tabs_register "${labs[@]}"          # the bar is tappable
}

# _tm_idx NAME  ->  _TM_I = position of the current tab (0 when the state variable holds something unknown)
_tm_idx() {
  local _tm_name="$1" _tm_v="${_TM_VAR[$1]}" _tm_i _tm_n="${_TM_N[$1]:-0}"
  _TM_I=0
  for (( _tm_i = 0; _tm_i < _tm_n; _tm_i++ )); do
    [ "${_TM_KEY[$_tm_name:$_tm_i]}" = "${!_tm_v-}" ] && { _TM_I=$_tm_i; return 0; }
  done
  return 0
}

# _tm_step NAME +1|-1 [nowrap]   move the state variable to the next / previous tab (wraps round; "nowrap" stops at the ends and returns 1)
_tm_step() {
  local _tm_name="$1" _tm_d="$2" _tm_n="${_TM_N[$1]:-0}" _tm_t     # _tm_ locals: the state variable of a screen may have ANY name
  (( _tm_n > 1 )) || return 1
  _tm_idx "$_tm_name"
  _tm_t=$(( _TM_I + _tm_d ))
  if (( _tm_t < 0 || _tm_t >= _tm_n )); then
    [ "${3:-}" = nowrap ] && return 1
    _tm_t=$(( (_tm_t + _tm_n) % _tm_n ))
  fi
  printf -v "${_TM_VAR[$_tm_name]}" '%s' "${_TM_KEY[$_tm_name:$_tm_t]}"
}
_tm_next() { _tm_step "$1" 1 "${2:-}"; }
_tm_prev() { _tm_step "$1" -1 "${2:-}"; }

# _tm_key NAME CHOICE [nowrap]   the loop's tab-key gate: 0 = CHOICE was a tab key and the tab moved (redraw now), 1 = anything else / at an end
_tm_key() {
  case "$2" in
    __sw_tab_right__) _tm_step "$1" 1  "${3:-}" ;;
    __sw_tab_left__)  _tm_step "$1" -1 "${3:-}" ;;
    *) return 1 ;;
  esac
}

# _tm_bar_v VAR NAME   the tab bar text into VAR:  "[A] B C"  /  "A [B] C"
_tm_bar_v() {
  local _tm_name="$2" _tm_i _tm_n="${_TM_N[$2]:-0}" _tm_out="" _tm_cell
  _tm_idx "$_tm_name"
  for (( _tm_i = 0; _tm_i < _tm_n; _tm_i++ )); do
    _tm_cell="${_TM_LAB[$_tm_name:$_tm_i]}"
    (( _tm_i == _TM_I )) && _tm_cell="[$_tm_cell]"
    _tm_out+="${_tm_out:+$_TM_TAB_SEP}$_tm_cell"
  done
  printf -v "$1" '%s' "$_tm_out"
}
_tm_bar() { local _b; _tm_bar_v _b "$1"; printf '%s' "$_b"; }

# _tm_desc_line NAME [folder]   the plain-words line under the tab bar: ONE row, cut with …
#   key  "<Desc screen>|<tab key>:<folder>"  — the nearest parent folder wins —  else  "<Desc screen>|<tab key>"
_tm_desc_line() {
  local _tm_cur="${2:-}" _tm_v="${_TM_VAR[$1]}" _tm_scr="${_TM_SCREEN[$1]}" _tm_txt="" _tm_k
  _st_desc_load 2>/dev/null
  while [ -n "$_tm_cur" ]; do
    _tm_k="$_tm_scr|${!_tm_v-}:$_tm_cur"
    [ -n "${_ST_DESC[$_tm_k]+x}" ] && { _tm_txt="${_ST_DESC[$_tm_k]}"; break; }
    [[ "$_tm_cur" == */* ]] && _tm_cur="${_tm_cur%/*}" || _tm_cur=""
  done
  [ -z "$_tm_txt" ] && _tm_txt="${_ST_DESC[$_tm_scr|${!_tm_v-}]:-}"
  _vp_usable
  (( ${#_tm_txt} > _vp_usable_w )) && _tm_txt="${_tm_txt:0:_vp_usable_w-1}…"
  printf '%s\n' "$_tm_txt"
}

# _tm_count_line [TOTAL]   "X out of N here"  (+ " · T total" when the screen knows a total)
#   X = rows shown now (after a filter), N = rows before the filter; reads items[] and _all_items[] of the viewport
_tm_count_line() {
  local _tm_x="${#items[@]}" _tm_n="${#_all_items[@]}"
  (( _tm_n < _tm_x )) && _tm_n=$_tm_x
  printf '%s out of %s here%s\n' "$_tm_x" "$_tm_n" "${1:+ · $1 total}"
}

# _tm_header NAME [title] [folder]
#   blank · title · blank · tab bar · blank · description.  The caller prints its context lines after it.
_tm_header() {
  local _tm_title="${2:-${_TM_TITLE[$1]}}"
  echo
  printf '%s\n\n' "$_tm_title"
  printf '%s\n\n' "$(_tm_bar "$1")"
  _tm_desc_line "$1" "${3:-}"
}

# _tm_footer [-b] [extra footer items…]   u/q/h/cc, then whatever the screen adds (a "|" starts a new line)
_tm_footer() {
  local _tm_u=tabmenu _tm_it
  [ "${1:-}" = -b ] && { _tm_u=tabmenu_back; shift; }
  (( $# )) || { _mc_footer "@$_tm_u"; return; }
  local -a _f=()
  for _tm_it in ${_MC_FOOTERS[$_tm_u]}; do _f+=("${_tm_it//_/ }"); done      # the registered items above are the ONE copy of the standard keys
  _mc_footer "${_f[@]}" "$@"
}

# _tm_viewport HEADER_FN FOOTER_FN [ROWTEXT_FN]   the viewport state every tabbed list screen sets (one call instead of seven lines)
_tm_viewport() {
  _vp_mode="items"
  _vp_rowtext_fn="${3:-}"
  _vp_header_fn="$1"
  _vp_footer_fn="$2"
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  _vp_cache_reset                          # _vp_rowtext_fn may just have changed: rows cached for the old one must not survive
}

# _tm_tab_redraw BUILD_FN SET_FN   in-place tab repaint: snapshot the old block height BEFORE the new tab's chrome changes the geometry,
#   rebuild the rows, set the viewport, then repaint inside the existing block (no scroll, no new container)
_tm_tab_redraw() {
  local _old_blk_h="${_blk_h:-0}"
  "$1"
  "$2"
  _vp_tab_repaint "$_old_blk_h"
}
