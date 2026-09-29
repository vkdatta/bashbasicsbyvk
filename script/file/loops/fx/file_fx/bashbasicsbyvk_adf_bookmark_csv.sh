#!/usr/bin/env bash
# bashbasicsbyvk_adf_bookmark_csv.sh
# adf-staging='file_fx/bookmark/bookmark.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — bookmark.select.items.csv
#  CSV-driven bookmark: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_bookmark_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_stage_selected "$_SP_BM_ONCE_FILE" "bookmark"
}
_fx_adf_register "bookmark.select.items.csv" "_fx_adf_bookmark_select_csv" "file_fx/bookmark/bookmark.select.items.csv"
