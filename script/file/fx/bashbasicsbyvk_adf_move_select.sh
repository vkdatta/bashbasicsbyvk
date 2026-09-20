#!/usr/bin/env bash
# bashbasicsbyvk_adf_move_select.sh
# adf-route='move/move.select.items'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — move.select.items
#  Pick items interactively via viewport multi-picker, stage into move buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_move_select() {
  select_items_common "MOVE" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_MV_ONCE_FILE" "$item"
    echo "📌 Staged for move: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "move.select.items" "_fx_adf_move_select" "move/move.select.items"
