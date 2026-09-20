#!/usr/bin/env bash
# bashbasicsbyvk_adf_copy_select.sh
# adf-route='copy/copy.select.items'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — copy.select.items
#  Pick items interactively, stage into copy buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_copy_select() {
  select_items_common "COPY" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_CP_ONCE_FILE" "$item"
    echo "📌 Staged for copy: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "copy.select.items" "_fx_adf_copy_select" "copy/copy.select.items"
