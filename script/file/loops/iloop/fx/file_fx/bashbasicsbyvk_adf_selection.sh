#!/usr/bin/env bash
# bashbasicsbyvk_adf_selection.sh
# adf-staging='file_fx/selection/selection.view'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — selection.view   (the only entry in file_fx/selection/)
#
#  Shows the items chosen with the  .s  commands.  Every ACTION on those items
#  lives in its own folder as  <action>.selected.items , next to the CSV
#  variant  <action>.select.items.csv  — e.g.
#     file_fx/copy/copy.selected.items      file_fx/zip/zip.selected.items
#     file_fx/upload/upload.selected.items  file_fx/delete/delete.selected.items
#  (see bashbasicsbyvk_adf_selected.sh).  Clear the selection with  .s.clr
#
#  Also defines the helpers shared by the *.selected.items functions.
# ════════════════════════════════════════════════════════════════════════════

# Loads the items an action works on into the caller's local  sel[]  ; 1 if empty / cancelled.
#   no named select set (s- / s--)  → the .s selection, exactly as before
#   named sets exist                → _fx_sel_pick: a list "set1 > · set2 > · flat items >" to take whole sets or single items from
_fx_sel_need() {
  local -a _sets_f=() _sets_n=() _sets_t=()
  _fx_sel_entries _sets_f _sets_n _sets_t
  if [ ${#_sets_n[@]} -gt 0 ]; then
    _fx_sel_pick _sets_f _sets_n _sets_t || return 1
    return 0
  fi
  _sel_load_live sel
  if [ ${#sel[@]} -eq 0 ]; then
    echo "📜  Nothing selected — use a .s command in the file view first"
    return 1
  fi
  [ "$_SEL_VANISHED" -gt 0 ] && echo "🔴  $_SEL_VANISHED selected item(s) no longer exist — skipped"
  return 0
}

# _fx_sel_entries <files-arr> <names-arr> <tags-arr>   every named select set (persistent first, then once) and, last, the .s selection ("flat items")
# Returns nothing in the arrays when there is no named set.
_fx_sel_entries() {
  local -n _e_f="$1" _e_n="$2" _e_t="$3"
  local persistent nm f
  local -a nms=() _fl=() _un=()
  _e_f=(); _e_n=(); _e_t=(); _FX_SEL_HAS_UNNAMED=0
  _sp_ensure_store
  for persistent in true false; do
    f=$(_sp_file_for sl "$persistent")
    _sp_names nms "$f"
    for nm in "${nms[@]}"; do
      _e_f+=("$f"); _e_n+=("$nm"); _e_t+=("$([ "$persistent" = true ] && echo persistent || echo once)")
    done
    _sp_load_set _un "$f" ""
    [ ${#_un[@]} -gt 0 ] && _FX_SEL_HAS_UNNAMED=1
  done
  # flat items = the .s selection + the unnamed items of s-- / s-  (shown only when there is something in them; with no
  # named set and no unnamed s- item the .s selection is used directly, as before)
  _fx_sel_flat _fl
  if [ ${#_fl[@]} -gt 0 ] && { [ ${#_e_n[@]} -gt 0 ] || [ "${_FX_SEL_HAS_UNNAMED:-0}" = 1 ]; }; then
    _e_f+=("$_SEL_FILE"); _e_n+=(""); _e_t+=("flat")
  fi
}

# _fx_sel_flat <array>  the existing flat items: the .s selection, then the unnamed items of s-- and s- (each path once)
_fx_sel_flat() {
  local -n _fo="$1"
  local -a _a=() _b=()
  local -A _seen=()
  local p persistent
  _fo=()
  _sel_load_live _a
  for persistent in true false; do
    _sp_load_set _b "$(_sp_file_for sl "$persistent")" ""
    _a+=("${_b[@]}")
  done
  for p in "${_a[@]}"; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    [ -n "${_seen[$p]+x}" ] && continue
    _seen["$p"]=1; _fo+=("$p")
  done
}

# The picker.  Same convention as the transfer navigator (_nav_parse_select):
#     5     a set → open it · a folder → go inside · a file → select it
#     w5    select it as it is (a whole set, or a folder without going in)      w1,3 · 2-4 · wa   several / all
#     c) take what is chosen   v) review / remove   u) back   z) cancel
# Chosen items land in the caller's sel[].  Items taken from a ONCE set (s-) leave that set; s-- sets and the .s selection stay.
declare -ga _PK_CHOSEN=()
declare -gA _PK_HAVE=()
_fx_sel_pick_add() {                 # <paths...>  (already-chosen ones are skipped)
  local p added=0
  for p in "$@"; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    [ -n "${_PK_HAVE[$p]+x}" ] && continue
    _PK_HAVE["$p"]=1; _PK_CHOSEN+=("$p"); added=$((added+1))
  done
  echo "➕ Chosen +$added — ${#_PK_CHOSEN[@]} item(s) in total  (v to review, c to take them)"
}

# _fx_sel_rows <title> <items...>   0 = back · 2 = confirm · 1 = cancel
_fx_sel_browse() {
  local title="$1"; shift
  local -a its=("$@") rows=() kids=()
  local p ch is_select cleaned_input idx rc
  while true; do
    rows=()
    for p in "${its[@]}"; do
      if [ -d "$p" ] && [ ! -L "$p" ]; then rows+=("📁 $(_sel_short "$p")"); else rows+=("📄 $(_sel_short "$p")"); fi
    done
    _mc_header "🎯 $title (${#its[@]}):"
    if [ ${#its[@]} -eq 0 ]; then echo "  (empty)"; else _mc_options 1 "${rows[@]}"; fi
    _mc_footer "u" "v:Review chosen" "c:Take chosen" "z" "q" "#tip: use prefix 'w' to select a folder (w1,3 · 2-4 · wa)"
    read -e -p "Pick: " ch
    case "$ch" in
      u|U|"") return 0 ;;
      z|Z) echo "🚫 Cancelled"; return 1 ;;
      q|Q) _bvk_quit; return 1 ;;
      c|C) [ ${#_PK_CHOSEN[@]} -gt 0 ] && return 2; echo "🔴  Nothing chosen yet" ;;
      v|V) _view_selections_menu _PK_CHOSEN; rc=$?
           _PK_HAVE=(); for p in "${_PK_CHOSEN[@]}"; do _PK_HAVE["$p"]=1; done
           [ $rc -eq 0 ] && return 2 ;;
      wa|WA|a|A) _fx_sel_pick_add "${its[@]}" ;;
      *)
        _nav_parse_select "$ch"
        if [[ "$cleaned_input" =~ ^[0-9,\-]+$ ]]; then
          if $is_select; then
            local -a picked=()
            for idx in $(parse_selection "$cleaned_input" "${#its[@]}"); do picked+=("${its[$((idx-1))]}"); done
            [ ${#picked[@]} -eq 0 ] && _bvk_invalid || _fx_sel_pick_add "${picked[@]}"
          elif _nav_index_ok "$cleaned_input" "${#its[@]}"; then
            p="${its[$((cleaned_input-1))]}"
            if [ -d "$p" ] && [ ! -L "$p" ]; then
              kids=(); while IFS= read -r -d '' idx; do kids+=("$idx"); done < <(find "$p" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
              _fx_sel_browse "$(_sel_short "$p")" "${kids[@]}"; rc=$?
              [ $rc -ne 0 ] && return $rc
            else
              _fx_sel_pick_add "$p"
            fi
          else _bvk_invalid; fi
        else _bvk_invalid; fi ;;
    esac
  done
}

# _fx_sel_pick <files-arr> <names-arr> <tags-arr>   fills the caller's sel[]
_fx_sel_pick() {
  local -n _k_f="$1" _k_n="$2" _k_t="$3"
  local i ch is_select cleaned_input idx rc live p
  local -a rows=() part=()
  _PK_CHOSEN=(); _PK_HAVE=()
  while true; do
    rows=()
    for i in "${!_k_n[@]}"; do
      if [ "${_k_t[$i]}" = flat ]; then _fx_sel_flat part; rows+=("flat items >  (${#part[@]})")
      else _sp_load_set part "${_k_f[$i]}" "${_k_n[$i]}"; rows+=("${_k_n[$i]} >  (${#part[@]})  ${_k_t[$i]} $([ "${_k_t[$i]}" = once ] && echo 's-' || echo 's--')"); fi
    done
    _mc_header "🎯 Selected items — pick what this action works on:"
    _mc_options 1 "${rows[@]}"
    _mc_footer "v:Review chosen" "c:Take chosen" "z" "q" "#tip: N opens a set · use prefix 'w' to take a whole set (w1,2 · wa)"
    read -e -p "Selected items: " ch
    case "$ch" in
      z|Z|u|U|"") echo "🚫 Cancelled"; return 1 ;;
      q|Q) _bvk_quit; return 1 ;;
      c|C) [ ${#_PK_CHOSEN[@]} -gt 0 ] && break; echo "🔴  Nothing chosen yet" ;;
      v|V) _view_selections_menu _PK_CHOSEN; rc=$?
           _PK_HAVE=(); for p in "${_PK_CHOSEN[@]}"; do _PK_HAVE["$p"]=1; done
           [ $rc -eq 0 ] && break ;;
      *)
        [[ "$ch" == [aA] || "$ch" == [wW][aA] ]] && ch="w1-${#_k_n[@]}"
        _nav_parse_select "$ch"
        if [[ "$cleaned_input" =~ ^[0-9,\-]+$ ]]; then
          local -a idxs=($(parse_selection "$cleaned_input" "${#_k_n[@]}"))
          if [ ${#idxs[@]} -eq 0 ]; then _bvk_invalid
          elif $is_select; then
            for idx in "${idxs[@]}"; do
              i=$((idx-1)); _fx_sel_entry_items part "$i" "${_k_f[$i]}" "${_k_n[$i]}" "${_k_t[$i]}"
              _fx_sel_pick_add "${part[@]}"
            done
          else
            i=$((idxs[0]-1)); _fx_sel_entry_items part "$i" "${_k_f[$i]}" "${_k_n[$i]}" "${_k_t[$i]}"
            _fx_sel_browse "${_k_n[$i]:-flat items}" "${part[@]}"; rc=$?
            [ $rc -eq 2 ] && break
            [ $rc -eq 1 ] && return 1
          fi
        else _bvk_invalid; fi ;;
    esac
  done
  sel=("${_PK_CHOSEN[@]}")
  # items taken out of a once set (s-) leave it
  for i in "${!_k_n[@]}"; do
    [ "${_k_t[$i]}" = once ] && _sp_drop_paths "${_k_f[$i]}" "${sel[@]}"
  done
  _sp_drop_unnamed_paths "$(_sp_file_for sl false)" "${sel[@]}"      # taken flat items of the once buffer (s-) leave it; s-- stays
  echo "🎯 ${#sel[@]} item(s) chosen"
  return 0
}

_fx_sel_entry_items() {              # <array> <index> <file> <name> <tag>  → the existing items of one entry
  local -n _ei="$1"
  local -a raw=() p
  _ei=()
  if [ "$5" = flat ]; then _fx_sel_flat _ei; return 0; fi
  _sp_load_set raw "$3" "$4"
  for p in "${raw[@]}"; do [ -e "$p" ] || [ -L "$p" ] && _ei+=("$p"); done
}

# Stage the selection into a once-buffer (copy / move / shortcut / bookmark).
_fx_sel_stage() {                   # _fx_sel_stage <buffer-file> <label>
  local -a sel=()
  _fx_sel_need || return
  _sp_ensure_store
  _csv_append_batch "$1" "${sel[@]}"
  local msg="📌 Staged for $2: $_CSV_ADDED/${#sel[@]} item(s)"
  [ "${#_CSV_DUPES[@]}" -gt 0 ] && msg="$msg (${#_CSV_DUPES[@]} already staged)"
  echo "$msg"
  [ "$_CSV_ADDED" -gt 0 ] && echo "▶️  Navigate to destination, then use d- to apply."
}

_fx_adf_sel_view() {
  _sel_cmd_show ""
  local -a _v_f=() _v_n=() _v_t=() part=()
  local i
  _fx_sel_entries _v_f _v_n _v_t
  for i in "${!_v_n[@]}"; do
    [ "${_v_t[$i]}" = flat ] && continue
    _sp_load_set part "${_v_f[$i]}" "${_v_n[$i]}"
    echo "🎯 Set '${_v_n[$i]}' (${_v_t[$i]}) — ${#part[@]} item(s)"
    _sel_preview part
  done
}

_fx_adf_register_fx "selection.view" "_fx_adf_sel_view"
