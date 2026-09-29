#!/usr/bin/env bash
# bashbasicsbyvk_adf_move_csv.sh
# adf-staging='file_fx/move/move.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — move.select.items.csv
#  CSV-driven move: col1 = filename or absolute path to stage into move buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_move_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_stage_selected "$_SP_MV_ONCE_FILE" "move"
}
_fx_adf_register "move.select.items.csv" "_fx_adf_move_select_csv" "file_fx/move/move.select.items.csv"
