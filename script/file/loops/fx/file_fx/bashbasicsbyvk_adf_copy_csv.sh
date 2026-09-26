#!/usr/bin/env bash
# bashbasicsbyvk_adf_copy_csv.sh
# adf-staging='file_fx/copy/copy.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — copy.select.items.csv
#  CSV-driven copy: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_copy_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_CP_ONCE_FILE" "$item"
    echo "📌 Staged for copy: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "copy.select.items.csv" "_fx_adf_copy_select_csv" "file_fx/copy/copy.select.items.csv"
