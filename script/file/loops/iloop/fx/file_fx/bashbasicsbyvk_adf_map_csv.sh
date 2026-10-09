#!/usr/bin/env bash
# bashbasicsbyvk_adf_map_csv.sh
# adf-staging='file_fx/map/map.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — map.select.items.csv
#  CSV-driven map: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_map_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_report "Mapping" || return
  _map_deliver "$(_map_generate_for_paths "${selected_items[@]}")"
}
_fx_adf_register "map.select.items.csv" "_fx_adf_map_select_csv" "file_fx/map/map.select.items.csv"
