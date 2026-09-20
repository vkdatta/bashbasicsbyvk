#!/usr/bin/env bash
# bashbasicsbyvk_adf_upload_csv.sh
# adf-route='upload/upload.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — upload.select.items.csv
#  CSV-driven upload: col1 = filename or absolute path, uploaded immediately.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_upload_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _up_do_multipart_upload "${selected_items[@]}"
}
_fx_adf_register "upload.select.items.csv" "_fx_adf_upload_select_csv" "upload/upload.select.items.csv"
