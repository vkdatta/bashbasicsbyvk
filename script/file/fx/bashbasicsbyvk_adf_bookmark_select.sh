#!/usr/bin/env bash
# bashbasicsbyvk_adf_bookmark_select.sh
# adf-route='bookmark/bookmark.select.items'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — bookmark.select.items
#  Pick items interactively, stage into bookmark buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_bookmark_select() {
  select_items_common "BOOKMARK" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_BM_ONCE_FILE" "$item"
    echo "📌 Staged for bookmark: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "bookmark.select.items" "_fx_adf_bookmark_select" "bookmark/bookmark.select.items"
