#!/usr/bin/env bash
# bashbasicsbyvk_adf_shortcut_select.sh
# adf-route='shortcut/shortcut.select.items'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — shortcut.select.items
#  Pick items interactively, stage into shortcut buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_shortcut_select() {
  select_items_common "SHORTCUT" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_SC_ONCE_FILE" "$item"
    echo "📌 Staged for shortcut: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "shortcut.select.items" "_fx_adf_shortcut_select" "shortcut/shortcut.select.items"
