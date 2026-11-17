#!/usr/bin/env bash
# bashbasicsbyvk_results.sh — ONE screen for "here is a list of paths": it shows them exactly the way the recursive  ==  filter shows its hits.
# ════════════════════════════════════════════════════════════════════════════
#  Nothing here draws a row. The screen borrows the main folder view (xui_enter / xui_leave) and fills the SAME three things  ==  fills:
#     items[]        the paths, numbered from 1, scrolled by the viewport ("▼ N more below"): every hit is reachable
#     _REC_LABEL     the text shown for a path (its name relative to the search folder, plus the engine's extra text)
#     the header     _menu_header_flat (status row, cd path, nav path + $_RES_HDR) and the footer _menu_footer_lines
#  Keys are read by _read_choice_filtered, so the arrows, tap / click, scrolling, the hint row, cc, h, s, -h and the "=" filter are the main list's own.
#
#  in :  _RES_LIST[]     the paths, in order                    _RES_NOTE[path]   text after the name ("→ new name", "(3 matches)")  (optional)
#        _RES_ROOT       the folder the names are shown relative to (default $path)
#        _RES_HDR        what the nav-path row says after the path, e.g.  "🔍 find: abc  (861 results)"
#        _RES_APPLY      1 = a preview: the key  a  (apply to ALL) is accepted and the footer prints it
#  call: _results_view [-p HANDLER]     HANDLER "N" runs INSIDE the screen when a row number is entered (Find passes handle_selection: open it)
#  out:  rc 0 a row (or  a)  was chosen:  _RES_CHOICE = the typed word,  _RES_PICK = that row's path     1 = u (back one step)     2 = q (the unwind flag is up)
#  Wiring: the typed words are the map  results  (cmdmap/results/); a new key of this screen is a line there.
# ════════════════════════════════════════════════════════════════════════════

declare -ga _RES_LIST=()
declare -gA _RES_NOTE=()
declare -g  _RES_ROOT="" _RES_HDR="" _RES_APPLY=0 _RES_CHOICE="" _RES_PICK=""

# a preview adds  a) Apply to ALL  to the main footer; a plain results screen has exactly the main footer
_mc_footer_register results_apply a:Apply_to_ALL u.up cd:Change_directory q '|' h:Home s:Settings -h:Help -u:Upgrade
# the key  a  exists only in a preview: cc and the footer (ADVERT, engine/bashbasicsbyvk_advert.sh) advertise it only while this is true
_results_is_preview() { [ "${_RES_APPLY:-0}" = 1 ]; }
_dp_when results _results_is_preview a

_results_footer() { if [ "${_RES_APPLY:-0}" = 1 ]; then _mc_footer @results_apply; else _menu_footer_lines; fi; }

_results_view() {
  local handler="" c rc=0 n p root="${_RES_ROOT:-$path}"
  [ "${1:-}" = -p ] && handler="${2:-}"
  local _has_group_view=false                     # the folder view's group banner does not belong here
  _RES_CHOICE=""; _RES_PICK=""
  _xui_enter
  items=("${_RES_LIST[@]}"); _all_items=(); _filter_src=()
  _REC_LABEL=()
  for p in "${items[@]}"; do _REC_LABEL["$p"]="${p#"${root%/}"/}${_RES_NOTE[$p]:+  ${_RES_NOTE[$p]}}"; done
  _filter_rec_active=true
  _hl_index=0; _win_lo=0; _win_hi=0; _meta_loaded=false
  _vp_mode="items"; _vp_header_fn=_menu_header_flat; _vp_footer_fn=_results_footer
  _vp_hl_fn=_vp_is_hl_single; _msel_set=(); _vp_input_fn=_print_input_line; _vp_rowtext_fn=""
  _buf=""; _pos=0
  _vp_render_from_top
  shopt -s nullglob
  while true; do
    _read_choice_filtered
    c="$choice"
    shopt -s nocasematch
    case "$c" in
      u)  rc=1; break ;;
      q)  _bvk_quit; rc=2; break ;;
      cd) _bvk_cd_shell; _vp_render_from_top ;;
      -u) _inner_run upg
          if [ "${_BVK_TO_MAIN:-0}" = 1 ]; then rc=2; break; fi
          _vp_render_from_top ;;
      a)  if [ "${_RES_APPLY:-0}" = 1 ]; then _RES_CHOICE=a; rc=0; break; fi
          _bvk_invalid; _vp_render_from_top ;;
      __*) ;;
      *)  if [[ "$c" =~ ^[0-9]+$ ]] && (( 10#$c >= 1 && 10#$c <= ${#items[@]} )); then
            n=$(( 10#$c )); _RES_CHOICE="$c"; _RES_PICK="${items[n-1]}"
            [ -n "$handler" ] && "$handler" "$c"
            rc=0; break
          fi
          _bvk_invalid; _vp_render_from_top ;;
    esac
    shopt -u nocasematch
    [ "${_BVK_TO_MAIN:-0}" = 1 ] && { rc=2; break; }
  done
  shopt -u nocasematch
  _xui_leave
  _RES_LIST=(); _RES_NOTE=(); _RES_HDR=""; _RES_APPLY=0; _RES_ROOT=""
  return "$rc"
}
