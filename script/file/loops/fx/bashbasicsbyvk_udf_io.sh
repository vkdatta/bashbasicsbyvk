#!/usr/bin/env bash
# bashbasicsbyvk_udf_io.sh — UDF tab extras (sourced by bashbasicsbyvk_functions.sh)
# ════════════════════════════════════════════════════════════════════════════
#  e-N    edit item N  → opens the same "What would you like to do with the
#         file?" menu (run / view / edit / copy / rename ...) used in the
#         outer loop.  Bare N still runs the script, as before.
#  ux     export ALL udfs to one zip   (also: udf.export)
#  ui     import ALL udfs from a zip   (also: udf.import)  — opens the zip picker
#
#  Zip format (fixed, version 1; paths relative to ~/.bashbasicsbyvk/execute,
#  manifest bvk_udf_manifest.txt marks it) — implemented ONCE in
#  functions/bashbasicsbyvk_bundle_io.sh, shared with the .r rule book's ux / ui.
#
#  Uses:  _FX_EXEC_DIR, _fx_ensure_store, _fx_outer_path (functions.sh)
#         _bz_export / _bz_import (bashbasicsbyvk_bundle_io.sh)
#         handle_file (bashbasicsbyvk_run.sh)
# ════════════════════════════════════════════════════════════════════════════

_UDF_MANIFEST="bvk_udf_manifest.txt"
_UDF_FORMAT=1

# ── e-N : edit item N ────────────────────────────────────────────────────────
_fx_udf_edit_item() {              # _fx_udf_edit_item <e-N>
  local arg="${1#[eE]-}"
  if [ "$_fx_tab" != "udf" ]; then
    echo "⚠️  Not available in ADF tab"; return 1
  fi
  if ! [[ "$arg" =~ ^[0-9]+$ ]]; then
    echo "⚠️  Usage: e-N   (e.g. e-1 opens the file actions for item 1; plain 1 runs it)"
    return 1
  fi
  if $imaginary_mode; then
    echo "⚠️  Navigate into a group first, then use e-N"; return 1
  fi
  if [ "$arg" -lt 1 ] || [ "$arg" -gt "${#items[@]}" ]; then
    echo "⚠️  Invalid: $1"; return 1
  fi
  local t="${items[$((arg-1))]}"
  if [ -d "$t" ]; then
    echo "⚠️  Item $arg is a folder — type $arg to open it"; return 1
  fi
  if [ ! -f "$t" ]; then
    echo "⚠️  Item $arg no longer exists"; return 1
  fi
  # file actions → "Run" behaves like a plain run (from the outer folder)
  pushd "${_fx_outer_path:-$PWD}" >/dev/null 2>&1 || true
  handle_file "$t"
  popd >/dev/null 2>&1 || true
  return 0
}

# ── ux : export ──────────────────────────────────────────────────────────────
_fx_udf_export() {
  _bz_need zip || return 1
  _fx_ensure_store
  # the archive goes to the folder fx was opened from — never into the UDF folder itself
  _bz_export "$_FX_EXEC_DIR" "$(_bz_dest "${_fx_outer_path:-}" "$_FX_EXEC_DIR")" \
    udf_export "$_UDF_MANIFEST" BVK_UDF_EXPORT "$_UDF_FORMAT" UDFs
}

# ── ui : import ──────────────────────────────────────────────────────────────
_fx_udf_import() {
  _bz_need unzip || return 1
  _fx_ensure_store
  _bz_import "$_FX_EXEC_DIR" "${_fx_outer_path:-$PWD}" \
    "$_UDF_MANIFEST" BVK_UDF_EXPORT "$_UDF_FORMAT" UDF UDFs
}
