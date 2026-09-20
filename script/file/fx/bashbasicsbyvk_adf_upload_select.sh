#!/usr/bin/env bash
# bashbasicsbyvk_adf_upload_select.sh
# adf-route='upload/upload.select.items'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — upload.select.items
#  Pick items interactively, upload immediately via fileapi.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_upload_select() {
  select_items_common "UPLOAD" || return
  _up_do_multipart_upload "${selected_items[@]}"
}
_fx_adf_register "upload.select.items" "_fx_adf_upload_select" "upload/upload.select.items"
