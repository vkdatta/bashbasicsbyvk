#!/usr/bin/env bash
# bashbasicsbyvk_adf_selection.sh
# adf-staging='file_fx/selection/selection.view'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — selection.view   (the only entry in file_fx/selection/)
#
#  Shows the items chosen with the  .s  commands.  Every ACTION on those items
#  lives in its own folder as  <action>.selected.items , next to the CSV
#  variant  <action>.select.items.csv  — e.g.
#     file_fx/copy/copy.selected.items      file_fx/zip/zip.selected.items
#     file_fx/upload/upload.selected.items  file_fx/delete/delete.selected.items
#  (see bashbasicsbyvk_adf_selected.sh).  Clear the selection with  .s.clr
#
#  Also defines the helpers shared by the *.selected.items functions.
# ════════════════════════════════════════════════════════════════════════════

# Loads the live selection into the caller's local  sel[]  ; 1 if empty.
_fx_sel_need() {
  _sel_load_live sel
  if [ ${#sel[@]} -eq 0 ]; then
    echo "ℹ️  Nothing selected — use a .s command in the file view first"
    return 1
  fi
  [ "$_SEL_VANISHED" -gt 0 ] && echo "⚠️  $_SEL_VANISHED selected item(s) no longer exist — skipped"
  return 0
}

# Stage the selection into a once-buffer (copy / move / shortcut / bookmark).
_fx_sel_stage() {                   # _fx_sel_stage <buffer-file> <label>
  local -a sel=()
  _fx_sel_need || return
  _sp_ensure_store
  _csv_append_batch "$1" "${sel[@]}"
  local msg="📌 Staged for $2: $_CSV_ADDED/${#sel[@]} item(s)"
  [ "${#_CSV_DUPES[@]}" -gt 0 ] && msg="$msg (${#_CSV_DUPES[@]} already staged)"
  echo "$msg"
  [ "$_CSV_ADDED" -gt 0 ] && echo "➡️  Navigate to destination, then use d- to apply."
}

_fx_adf_sel_view() { _sel_cmd_show ""; }

_fx_adf_register "selection.view" "_fx_adf_sel_view" "file_fx/selection/selection.view"
