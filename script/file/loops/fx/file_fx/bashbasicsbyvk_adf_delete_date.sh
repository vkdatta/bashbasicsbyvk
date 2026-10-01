#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_date.sh
# adf-staging='file_fx/delete/delete.by.date'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.by.date
#  Group the current folder's files by day / month / year / decade (file
#  modified date — same basis as organise), then pick one or more groups
#  to delete. Uses organise's _batch_stat + _ts_to_ymd.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_delete_by_date() {
  local -a files=()
  _fxdel_list_files files
  [ ${#files[@]} -eq 0 ] && { echo "No files"; return; }

  echo "🗑️  Delete by date in $path (file modified date):"
  echo "1) Day     (e.g. 2024-03-15)"
  echo "2) Month   (e.g. 2024-03)"
  echo "3) Year    (e.g. 2024)"
  echo "4) Decade  (e.g. 2020s)"
  local lvl
  read -p "Choice [1-4]: " lvl
  case "$lvl" in 1|2|3|4) ;; *) echo "❌ Invalid choice"; return ;; esac

  _batch_stat "$path"
  local -A count=() key_of=()
  local f key
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

  local -a keys=()
  mapfile -t keys < <(printf '%s\n' "${!count[@]}" | sort)

  local i
  for i in "${!keys[@]}"; do
    printf '%d) %s  (%d file(s))\n' $((i+1)) "${keys[$i]}" "${count[${keys[$i]}]}"
  done
  echo "Pick one or more: numbers/ranges (1,3 or 2-4), or a = all"
  local reply
  read -p "Choice: " reply
  [ -z "$reply" ] && { echo "🚫 Cancelled"; return; }

  local -A chosen=()
  local idx
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
_fx_adf_register "delete.by.date" "_fx_adf_delete_by_date" "file_fx/delete/delete.by.date"
