#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_date.sh
# adf-staging='file/delete/delete.by.date'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.by.date
#  Group the current folder's files by day / month / year / decade (file
#  modified date — same basis as organise), then pick one or more groups
#  on the ONE pick screen (_pick_groups, template MG2374): s-N takes whole
#  dates, N goes inside a date and lists its files one by one.
#  Uses organise's _batch_stat + _ts_to_ymd.
# ════════════════════════════════════════════════════════════════════════════

# Three steps (_mc_steps: u = one question back): the level, the dates (the pick screen, MG2374), then Confirm delete / Back up.
# They fill _fx_adf_delete_by_date's locals (files lvl keys label key_of); selected_items is the global every delete flow fills.
_dd_s_level() {
  _mc_select lvl "🚮 Delete by date in $path (file modified date):" "Day     (e.g. 2024-03-15)" \
    "Month   (e.g. 2024-03)" "Year    (e.g. 2024)" "Decade  (e.g. 2020s)" || return $(( $? == 2 ? 2 : 1 ))
  return 0
}
_dd_s_pick() {
  _batch_stat "$path"
  local -A count=()
  key_of=(); label=(); keys=()
  local f key k
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
  for k in "${keys[@]}"; do label["$k"]="$k  (${count[$k]} file(s))"; done
  _pick_groups -i 🚮 -w to "dates" "delete" "dates" "$path" files keys label key_of selected_items
  case $? in 0) return 0 ;; 1) return 1 ;; 2) return 2 ;; *) return 3 ;; esac       # u = back to the level question
}
_dd_s_confirm() {
  local rc
  _sel_summary selected_items "🚮 About to delete"
  _sel_preview selected_items
  _fxdel_run_selected; rc=$?
  case "$rc" in 1|2) return "$rc" ;; esac
  return 0
}

_fx_adf_delete_by_date() {
  local -a files=()
  _fxdel_list_files files
  [ ${#files[@]} -eq 0 ] && { echo "No files"; return; }

  local lvl
  local -A label=() key_of=()
  local -a keys=()
  _mc_steps _dd_s_level _dd_s_pick _dd_s_confirm
  case $? in 0) ;; 1) echo "🔙 Back"; return ;; 2) return 1 ;; *) return ;; esac
}
_fx_adf_register_fx "delete.by.date" "_fx_adf_delete_by_date"
