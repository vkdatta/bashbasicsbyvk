#!/usr/bin/env bash
# bashbasicsbyvk_adf_move_csv.sh
# adf-staging='file_fx/move/move.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — move.select.items.csv
#  CSV-driven move: col1 = filename or absolute path to stage into move buffer.
#  Result column written back to col2 of the CSV.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_move_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_MV_ONCE_FILE" "$item"
    echo "📌 Staged for move: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "move.select.items.csv" "_fx_adf_move_select_csv" "file_fx/move/move.select.items.csv"
