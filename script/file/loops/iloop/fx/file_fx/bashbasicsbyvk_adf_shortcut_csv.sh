#!/usr/bin/env bash
# bashbasicsbyvk_adf_shortcut_csv.sh
# adf-staging='file_fx/shortcut/shortcut.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — shortcut.select.items.csv
#  CSV-driven shortcut: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_shortcut_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_stage_selected "$_SP_SC_ONCE_FILE" "shortcut"
}
_fx_adf_register "shortcut.select.items.csv" "_fx_adf_shortcut_select_csv" "file_fx/shortcut/shortcut.select.items.csv"
