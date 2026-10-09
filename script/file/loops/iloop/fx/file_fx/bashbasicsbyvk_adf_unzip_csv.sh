#!/usr/bin/env bash
# bashbasicsbyvk_adf_unzip_csv.sh
# adf-staging='file_fx/unzip/unzip.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — unzip.select.items.csv
#  CSV-driven extract (same as uz-): col1 = archive name or absolute path
#  (.zip / .tar.gz / .tgz). Each archive gets its own folder in the current path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_unzip_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_report "Extracting" || return
  _decompress_paths "${selected_items[@]}"
}
_fx_adf_register "unzip.select.items.csv" "_fx_adf_unzip_select_csv" "file_fx/unzip/unzip.select.items.csv"
