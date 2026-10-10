#!/usr/bin/env bash
# bashbasicsbyvk_xui.sh — a tiny shared "screen" toolkit for the rbam, notifications (nf) and cloud-surf (cs) loops.
# ════════════════════════════════════════════════════════════════════════════
#  Every one of those loops is drawn by the SAME viewport engine as `o`, fx, sw, api and -auth: header · rule ·
#  numbered rows · rule · footer · "Select:" prompt, arrow-key highlight, "=" live filter. This file only wraps
#  the bookkeeping that bashbasicsbyvk_auth.sh and bashbasicsbyvk_api.sh each do by hand:
#
#    _xui_enter / _xui_leave     borrow the shared list + viewport state, hand it back untouched (nestable)
#    _xui_screen <prefix>        a screen is four functions:  <prefix>_build  <prefix>_row N  <prefix>_header  <prefix>_footer
#    _xui_fresh                  rebuild the current screen and draw it from the top
#    _xui_slot N                 display row N (filtered or not) -> 0-based slot in the unfiltered data arrays ($_XUI_SLOT)
#    _xui_begin_items "${labels[@]}"   (call from <prefix>_build) the rows' filter text
#    _xui_select_rows PROMPT TITLE [typed]   "1,3-5 / a / a-2" redrawer, same as d / r in the outer loop -> $_XUI_SEL
#    _xui_ask "text" [default]   one line of input -> $_XUI_IN  (1 = blank / u / q)
#    _xui_yes "question"         y/N
#
#  Uses (from the main app): _vp_*, _read_choice_filtered, _filter_reset_state, _multi_prompt_loop, parse_selection,
#  _sp_parse_all_except, _print_input_line, _sm_reset, _vp_tab_repaint
# ════════════════════════════════════════════════════════════════════════════

_XUI_DEPTH=0
_XUI_PFX=""
_XUI_SLOT=0
declare -ga _XUI_SEL=()
_XUI_IN=""
_XUI_PICK_TITLE=""

# ── borrow / restore the shared viewport state ───────────────────────────────
_XUI_ARRS=(items _all_items _filter_src _filter_map)
_XUI_VARS=(_hl_index _vp_mode _vp_header_fn _vp_footer_fn _vp_rowtext_fn _vp_input_fn _vp_hl_fn _fx_in_mode
           imaginary_mode _filter_query _filter_map_active _sw_in_mode group_prefix force_show _XUI_PFX)

_xui_enter() {
  local d=$(( ++_XUI_DEPTH )) v
  for v in "${_XUI_ARRS[@]}"; do eval "_XUI_K${d}_${v}=(\"\${${v}[@]}\")"; done
  for v in "${_XUI_VARS[@]}"; do eval "_XUI_K${d}_${v}=\"\${${v}-}\""; done
  _fx_in_mode=1            # virtual list: never re-scan the folder for hidden files; inner-loop animation
  _sw_in_mode=1            # lets the ←/→ tab sentinels through (and keeps them from leaking out as text)
  imaginary_mode=false     # a big folder in grouped view must not hijack the = filter
  group_prefix=""; force_show=false
  _filter_reset_state
  shopt -s nullglob
}

_xui_leave() {
  local d=$_XUI_DEPTH v
  _filter_reset_state
  for v in "${_XUI_ARRS[@]}"; do eval "${v}=(\"\${_XUI_K${d}_${v}[@]}\")"; done
  for v in "${_XUI_VARS[@]}"; do eval "${v}=\"\${_XUI_K${d}_${v}-}\""; done
  for v in "${_XUI_ARRS[@]}"; do unset "_XUI_K${d}_${v}"; done
  for v in "${_XUI_VARS[@]}"; do unset "_XUI_K${d}_${v}"; done
  _XUI_DEPTH=$(( d - 1 ))
  [ "${_filter_map_active:-}" = true ] || _filter_map_active=false
  _vp_cache_reset
}

# ── screens ──────────────────────────────────────────────────────────────────
_xui_slot() {
  if $_filter_map_active; then _XUI_SLOT="${_filter_map[$(( $1 - 1 ))]:-0}"; else _XUI_SLOT=$(( $1 - 1 )); fi
}

_xui_begin_items() {                         # call first thing in <prefix>_build
  _filter_reset_state
  items=("$@")
  _all_items=("${items[@]}")
  _hl_index=0
}

_xui_set() {
  _XUI_PFX="$1"
  _vp_mode="items"
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  _vp_rowtext_fn="${1}_row"; _vp_header_fn="${1}_header"; _vp_footer_fn="${1}_footer"
  _vp_cache_reset
}
_xui_screen() { _XUI_PFX="$1"; }             # choose the screen; _xui_fresh draws it

_xui_fresh() {
  _buf=""; _pos=0
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  "${_XUI_PFX}_build" || return 1
  _xui_set "$_XUI_PFX"
  _vp_render_from_top
  return 0
}

# tab switch (←/→): rebuild + repaint in place, same as sw does
_xui_tab_redraw() {
  local _old_blk_h="${_blk_h:-0}"
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  "${_XUI_PFX}_build" || return 1
  _xui_set "$_XUI_PFX"
  _vp_tab_repaint "$_old_blk_h"
}

# resolve a typed row number against what is on screen -> $_XUI_SLOT ; 1 = invalid
_xui_row() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  local n=$(( 10#$1 ))
  [ "$n" -ge 1 ] && [ "$n" -le "${#items[@]}" ] || return 1
  _xui_slot "$n"
}

# ── multi-row selection ──────────────────────────────────────────────────────
_xui_pick_header() { echo; echo "$_XUI_PICK_TITLE"; }

_xui_parse_sel() {                           # "1,3-5 | a | a-2" -> _XUI_SEL (display rows)
  local s="${1// /}" n="${#items[@]}"
  _XUI_SEL=()
  if   [ "$s" = a ];            then _XUI_SEL=($(seq 1 "$n"))
  elif [[ "$s" =~ ^a-(.+)$ ]];  then _XUI_SEL=($(_sp_parse_all_except "${BASH_REMATCH[1]}" "$n"))
  else                               _XUI_SEL=($(parse_selection "$s" "$n")); fi
  [ "${#_XUI_SEL[@]}" -gt 0 ] || { echo "❌ No valid items selected"; return 1; }
}

# _xui_select_rows "PROMPT" "title line" [typed]     typed = "r-1,3" style shortcut (no redraw)
_xui_select_rows() {
  local prompt="$1" title="$2" typed="${3:-}"
  [ "${#items[@]}" -gt 0 ] || { echo "ℹ️  Nothing to choose from."; return 1; }
  if [[ "$typed" == *-* ]]; then _xui_parse_sel "${typed#*-}"; return; fi
  local _multi_allow_a=true _multi_header_hook=_xui_pick_header _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos
  _XUI_PICK_TITLE="$title"
  _vp_mode="items"
  _multi_prompt_loop
  _xui_parse_sel "$_buf"
}

# ── one-line questions ───────────────────────────────────────────────────────
_xui_ask() {                                 # _xui_ask "What to type" [default]
  local q="$1" def="${2:-}" a
  if [ -n "$def" ]; then builtin read -r -p "   $q [$def] (u = back): " a; a="${a:-$def}"
  else                   builtin read -r -p "   $q (u = back): " a; fi
  a="${a%$'\r'}"
  _XUI_IN="$a"
  case "${a,,}" in ""|u|q) return 1 ;; esac
  return 0
}

_xui_yes() {                                 # _xui_yes "Question?"  -> 0 on y
  local a; builtin read -r -p "   $1 (y/N): " a
  case "$a" in [yY]|[yY][eE][sS]) return 0 ;; esac
  echo "🚫 Cancelled"; return 1
}

# ── small formatters shared by the loops ─────────────────────────────────────
_xui_hsize() {                               # bytes -> "3.2 MB"
  awk -v b="${1:-0}" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i] }'
}
_xui_trunc() { local t="$1" m="$2"; if [ "${#t}" -gt "$m" ]; then printf '%s…' "${t:0:$((m-1))}"; else printf '%s' "$t"; fi; }
_xui_left() {                                # epoch-ms expiry -> "29d 23h left" / "expired"
  local ms="$1" now s
  printf -v now '%(%s)T' -1
  s=$(( ms / 1000 - now ))
  if [ "$s" -le 0 ]; then printf 'expired'; else printf '%s left' "$(_bb_fmt_duration "$s")"; fi
}

# ── the screen loop ──────────────────────────────────────────────────────────
# _xui_loop <handler>     draws the current screen (_xui_screen first) and reads commands until the handler says leave.
#   handler "<typed text>" returns:  0 = redraw   1 = nothing to redraw   2 = leave this loop   3 = redraw in place (tab switch)
#                                    9 = not mine: the loop deals with it (u back · q quit · fx/sw/api/.r/-u hop · ignores _*)
_xui_loop() {
  local h="$1" c rc
  shopt -s nullglob
  _xui_fresh || return 1
  while true; do
    _read_choice_filtered
    c="$choice"
    shopt -s nocasematch
    "$h" "$c"; rc=$?
    shopt -u nocasematch
    if [ "$rc" = 9 ]; then
      rc=1
      case "$c" in
        u) rc=2 ;;
        q) _fx_in_mode=0; _sw_in_mode=0; _bvk_quit ;;
        fx|sw|api|.r|-u)
          if [ "$_XUI_DEPTH" -le 1 ]; then
            case "$c" in .r) _inner_next=r ;; -u) _inner_next=upg ;; *) _inner_next="$c" ;; esac
            rc=2
          else echo "↩️  Go back with  u  first."; fi ;;
        _*|__sw_tab_*) ;;
        *) echo "⚠️  Invalid selection" ;;
      esac
    fi
    case "$rc" in
      0) _xui_fresh ;;
      2) return 0 ;;
      3) _xui_tab_redraw ;;
    esac
  done
}
