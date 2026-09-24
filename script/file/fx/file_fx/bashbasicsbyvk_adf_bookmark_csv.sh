#!/usr/bin/env bash
# bashbasicsbyvk_adf_bookmark_csv.sh
# adf-route='file_fx/bookmark/bookmark.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — bookmark.select.items.csv
#  CSV-driven bookmark: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_bookmark_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_BM_ONCE_FILE" "$item"
    echo "📌 Staged for bookmark: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "bookmark.select.items.csv" "_fx_adf_bookmark_select_csv" "bookmark/bookmark.select.items.csv"
