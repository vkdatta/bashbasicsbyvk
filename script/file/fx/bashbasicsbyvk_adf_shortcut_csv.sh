#!/usr/bin/env bash
# bashbasicsbyvk_adf_shortcut_csv.sh
# adf-route='shortcut/shortcut.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — shortcut.select.items.csv
#  CSV-driven shortcut: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_shortcut_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_SC_ONCE_FILE" "$item"
    echo "📌 Staged for shortcut: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "shortcut.select.items.csv" "_fx_adf_shortcut_select_csv" "shortcut/shortcut.select.items.csv"
