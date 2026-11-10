#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_date.sh
# adf-staging='file/delete/delete.by.date'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.by.date
#  Group the current folder's files by day / month / year / decade (file
#  modified date — same basis as organise), then pick one or more groups
#  to delete. Uses organise's _batch_stat + _ts_to_ymd.
# ════════════════════════════════════════════════════════════════════════════

# Two questions, one step each (_mc_steps: u = one question back): the level, then the dates.  They fill _fx_adf_delete_by_date's locals.
_dd_s_level() {
  _mc_select lvl "🗑️  Delete by date in $path (file modified date):" "Day     (e.g. 2024-03-15)" \
    "Month   (e.g. 2024-03)" "Year    (e.g. 2024)" "Decade  (e.g. 2020s)" || return $(( $? == 2 ? 2 : 1 ))
  return 0
}
_dd_s_pick() {
  _batch_stat "$path"
  count=(); key_of=(); keys=()
  local f key i
  for f in "${files[@]}"; do
    _ts_to_ymd "${_FILE_TS[$f]:-0}"
    case "$lvl" in
      1) key=$(printf '%04d-%02d-%02d' "$_YMD_Y" "$_YMD_M" "$_YMD_D") ;;
      2) key=$(printf '%04d-%02d' "$_YMD_Y" "$_YMD_M") ;;
      3) key="$_YMD_Y" ;;
      4) key="$(( _YMD_Y / 10 * 10 ))s" ;;
    esac
    key_of["$f"]="$key"
    count["$key"]=$(( ${count[$key]:-0} + 1 ))
  done
  mapfile -t keys < <(printf '%s\n' "${!count[@]}" | sort)
  for i in "${!keys[@]}"; do
    printf '%d) %s  (%d file(s))\n' $((i+1)) "${keys[$i]}" "${count[${keys[$i]}]}"
  done
  _mc_text reply "Select: " "Pick one or more: numbers/ranges (1,3 or 2-4), or a = all"
  case $? in 0) ;; 1) return 1 ;; 2) return 2 ;; *) return 3 ;; esac       # u = back to the level question
  [ -z "$reply" ] && { echo "🚫 Cancelled"; return 3; }
  return 0
}

_fx_adf_delete_by_date() {
  local -a files=()
  _fxdel_list_files files
  [ ${#files[@]} -eq 0 ] && { echo "No files"; return; }

  local lvl reply f idx
  local -A count=() key_of=()
  local -a keys=()
  _mc_steps _dd_s_level _dd_s_pick
  case $? in 0) ;; 1) echo "↩️  Back"; return ;; 2) return 1 ;; *) return ;; esac

  local -A chosen=()
  for idx in $(_fxdel_pick_indices "$reply" "${#keys[@]}"); do
    chosen["${keys[$((idx-1))]}"]=1
  done
  [ ${#chosen[@]} -eq 0 ] && { echo "❌ No valid selection"; return; }

  selected_items=()
  for f in "${files[@]}"; do
    [ -n "${chosen[${key_of[$f]}]+x}" ] && selected_items+=("$f")
  done
  echo "Selected: $(printf '%s\n' "${!chosen[@]}" | sort | tr '\n' ' ')"
  _fxdel_run_selected
}
_fx_adf_register_fx "delete.by.date" "_fx_adf_delete_by_date"
