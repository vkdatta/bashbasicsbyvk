#!/usr/bin/env bash
# bashbasicsbyvk_adf_selection.sh
# adf-staging='file_fx/selection/*'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — selection.*   act on the items chosen with the  .s  commands
#  (selection.list).  copy / move / shortcut / bookmark stage into the once-
#  buffers like the CSV functions do; go to the destination and use d-.
#  Reuses: _csv_append_batch, _sp_ensure_store, _fxdel_run_selected.
# ════════════════════════════════════════════════════════════════════════════

_fx_sel_need() {                    # loads live selection into sel[]; 1 if empty
  _sel_load_live sel
  if [ ${#sel[@]} -eq 0 ]; then
    echo "ℹ️  Nothing selected — use a .s command in the file view first"
    return 1
  fi
  [ "$_SEL_VANISHED" -gt 0 ] && echo "⚠️  $_SEL_VANISHED selected item(s) no longer exist — skipped"
  return 0
}

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

_fx_adf_sel_view()     { _sel_cmd_show ""; }
_fx_adf_sel_copy()     { _fx_sel_stage "$_SP_CP_ONCE_FILE" "copy"; }
_fx_adf_sel_move()     { _fx_sel_stage "$_SP_MV_ONCE_FILE" "move"; }
_fx_adf_sel_shortcut() { _fx_sel_stage "$_SP_SC_ONCE_FILE" "shortcut"; }
_fx_adf_sel_bookmark() { _fx_sel_stage "$_SP_BM_ONCE_FILE" "bookmark"; }
_fx_adf_sel_clear()    { : > "$_SEL_FILE"; _sel_bump; echo "🧹 Selection cleared"; }

_fx_adf_sel_delete() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "🗑️  About to delete"
  _sel_preview sel
  selected_items=("${sel[@]}")
  _fxdel_run_selected
  _sel_prune
}

_fx_adf_register "selection.view"     "_fx_adf_sel_view"     "file_fx/selection/selection.view"
_fx_adf_register "selection.copy"     "_fx_adf_sel_copy"     "file_fx/selection/selection.copy"
_fx_adf_register "selection.move"     "_fx_adf_sel_move"     "file_fx/selection/selection.move"
_fx_adf_register "selection.shortcut" "_fx_adf_sel_shortcut" "file_fx/selection/selection.shortcut"
_fx_adf_register "selection.bookmark" "_fx_adf_sel_bookmark" "file_fx/selection/selection.bookmark"
_fx_adf_register "selection.delete"   "_fx_adf_sel_delete"   "file_fx/selection/selection.delete"
_fx_adf_register "selection.clear"    "_fx_adf_sel_clear"    "file_fx/selection/selection.clear"
