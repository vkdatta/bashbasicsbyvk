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
  _csv_stage_selected "$_SP_CP_ONCE_FILE" "copy"
}
_fx_adf_register "copy.select.items.csv" "_fx_adf_copy_select_csv" "file_fx/copy/copy.select.items.csv"
