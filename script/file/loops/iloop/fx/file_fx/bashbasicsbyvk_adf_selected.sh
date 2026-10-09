#!/usr/bin/env bash
# bashbasicsbyvk_adf_selected.sh
# ════════════════════════════════════════════════════════════════════════════
#  ADF — <action>.selected.items
#  Act on the items chosen with the  .s  commands.  One entry per action, each
#  living in the same folder as its CSV twin (<action>.select.items.csv):
#
#    copy / move / shortcut / bookmark   stage into the once-buffer, then d-
#    upload                              encrypted upload of files + folders (up-)
#    upload.text                         merge files into ONE text blob      (c2c-)
#    map                                 folder-tree text → clipboard / file (p-)
#    zip / unzip                         compress / extract                   (z- / uz-)
#    delete                              confirm, then remove
#
#  Reuses: _fx_sel_need / _fx_sel_stage (adf_selection.sh), _csv_append_batch,
#          _up_do_multipart_upload, _c2c_paths, _map_generate_for_paths,
#          _map_deliver, _compress_paths, _decompress_paths, _fxdel_run_selected.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_sel_copy()     { _fx_sel_stage "$_SP_CP_ONCE_FILE" "copy"; }
_fx_adf_sel_move()     { _fx_sel_stage "$_SP_MV_ONCE_FILE" "move"; }
_fx_adf_sel_shortcut() { _fx_sel_stage "$_SP_SC_ONCE_FILE" "shortcut"; }
_fx_adf_sel_bookmark() { _fx_sel_stage "$_SP_BM_ONCE_FILE" "bookmark"; }

_fx_adf_sel_upload() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "☁️  Uploading"
  _up_do_multipart_upload "${sel[@]}"
}

_fx_adf_sel_upload_text() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "📝 Uploading as one merged text blob"
  _c2c_paths "${sel[@]}"
}

_fx_adf_sel_map() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "🗺️  Mapping"
  _map_deliver "$(_map_generate_for_paths "${sel[@]}")"
}

_fx_adf_sel_zip() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "🗜️  Compressing"
  _compress_paths "${sel[@]}"
}

_fx_adf_sel_unzip() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "📂 Extracting"
  _decompress_paths "${sel[@]}"
}

_fx_adf_sel_delete() {
  local -a sel=()
  _fx_sel_need || return
  _sel_summary sel "🗑️  About to delete"
  _sel_preview sel
  selected_items=("${sel[@]}")
  _fxdel_run_selected
  _sel_prune
}

_fx_adf_register "copy.selected.items"        "_fx_adf_sel_copy"        "file_fx/copy/copy.selected.items"
_fx_adf_register "move.selected.items"        "_fx_adf_sel_move"        "file_fx/move/move.selected.items"
_fx_adf_register "shortcut.selected.items"    "_fx_adf_sel_shortcut"    "file_fx/shortcut/shortcut.selected.items"
_fx_adf_register "bookmark.selected.items"    "_fx_adf_sel_bookmark"    "file_fx/bookmark/bookmark.selected.items"
_fx_adf_register "upload.selected.items"      "_fx_adf_sel_upload"      "file_fx/upload/upload.selected.items"
_fx_adf_register "upload.text.selected.items" "_fx_adf_sel_upload_text" "file_fx/upload/upload.text.selected.items"
_fx_adf_register "map.selected.items"         "_fx_adf_sel_map"         "file_fx/map/map.selected.items"
_fx_adf_register "zip.selected.items"         "_fx_adf_sel_zip"         "file_fx/zip/zip.selected.items"
_fx_adf_register "unzip.selected.items"       "_fx_adf_sel_unzip"       "file_fx/unzip/unzip.selected.items"
_fx_adf_register "delete.selected.items"      "_fx_adf_sel_delete"      "file_fx/delete/delete.selected.items"
