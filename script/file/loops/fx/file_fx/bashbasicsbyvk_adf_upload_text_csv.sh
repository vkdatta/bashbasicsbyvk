#!/usr/bin/env bash
# bashbasicsbyvk_adf_upload_text_csv.sh
# adf-staging='file_fx/upload/upload.text.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — upload.text.select.items.csv
#  CSV-driven merged-text upload (same as ups-): the listed files are merged
#  into ONE encrypted text blob. Folders are not supported (use upload.*).
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_upload_text_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_report "Uploading (text)" || return
  _ups_upload_paths "${selected_items[@]}"
}
_fx_adf_register "upload.text.select.items.csv" "_fx_adf_upload_text_select_csv" "file_fx/upload/upload.text.select.items.csv"
