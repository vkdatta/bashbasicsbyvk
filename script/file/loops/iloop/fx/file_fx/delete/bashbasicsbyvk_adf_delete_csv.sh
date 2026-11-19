#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_csv.sh
# adf-staging='file/delete/delete.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.select.items.csv
#  CSV-driven delete: col1 = filename or absolute path. Shows a count + preview,
#  then asks for confirmation before removing anything.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_delete_select_csv() {
  local _rc
  while :; do                                   # u at Confirm delete / Back up = the CSV picker again
    open_csv_menu || return
    [ -z "$csv_file" ] && return
    _csv_resolve_report "Deleting" || return
    _sel_summary selected_items "🗑️  About to delete"
    _sel_preview selected_items
    _fxdel_run_selected; _rc=$?
    [ "$_rc" = 1 ] || return "$_rc"
  done
}
_fx_adf_register_fx "delete.select.items.csv" "_fx_adf_delete_select_csv"
