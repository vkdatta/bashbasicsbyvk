#!/usr/bin/env bash
# bashbasicsbyvk_adf_zip_csv.sh
# adf-staging='file_fx/zip/zip.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — zip.select.items.csv
#  CSV-driven compress (same as z-): col1 = filename or absolute path.
#  Format follows the compress_format setting (zip | targz | ask).
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_zip_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_report "Compressing" || return
  _compress_paths "${selected_items[@]}"
}
_fx_adf_register "zip.select.items.csv" "_fx_adf_zip_select_csv" "file_fx/zip/zip.select.items.csv"
