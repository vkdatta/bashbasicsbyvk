#!/usr/bin/env bash
# bashbasicsbyvk_udf_io.sh — UDF tab extras (sourced by bashbasicsbyvk_functions.sh)
# ════════════════════════════════════════════════════════════════════════════
#  e-N    edit item N  → opens the same "What would you like to do with the
#         file?" menu (run / view / edit / copy / rename ...) used in the
#         outer loop.  Bare N still runs the script, as before.
#  ux     export ALL udfs to one zip   (also: udf.export)
#  ui     import ALL udfs from a zip   (also: udf.import)  — opens the zip picker
#
#  Zip format (fixed, version 1)
#    • paths are relative to the execute folder (~/.bashbasicsbyvk/execute),
#      so files, sub-folders, empty folders and exec bits all round-trip
#    • bvk_udf_manifest.txt at the zip root marks it as a UDF export:
#          BVK_UDF_EXPORT=1
#          CREATED=<UTC timestamp>
#    • import refuses zips without the manifest and zips with absolute / ".."
#      paths; nothing is ever deleted — you choose to keep or overwrite clashes
#
#  Uses:  _FX_EXEC_DIR, _fx_ensure_store, _fx_outer_path (functions.sh)
#         open_zip_menu → _file_picker (bashbasicsbyvk_csv.sh) — same picker
#         as the CSV one, handle_file (bashbasicsbyvk_run.sh)
# ════════════════════════════════════════════════════════════════════════════

_UDF_MANIFEST="bvk_udf_manifest.txt"
_UDF_FORMAT=1

_udf_need() {                      # _udf_need <command>
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "❌ '$1' not found — install it first (e.g. pkg install $1)."
  return 1
}

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
  _udf_need zip || return 1
  _fx_ensure_store
  if [ -z "$(find "$_FX_EXEC_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "ℹ️  No UDFs to export"; return 1
  fi

  # the archive goes to the folder fx was opened from — never into the UDF
  # folder itself (it would end up archiving itself)
  local dest="${_fx_outer_path:-$HOME}"
  case "${dest%/}/" in "${_FX_EXEC_DIR%/}"/*) dest="$HOME" ;; esac

  local base out n=1
  base="${dest%/}/udf_export_$(date +%Y%m%d_%H%M%S)"
  out="$base.zip"
  while [ -e "$out" ]; do out="${base}_${n}.zip"; n=$((n+1)); done

  local tmp; tmp=$(mktemp -d) || { echo "❌ Cannot create a temp folder"; return 1; }
  {
    echo "BVK_UDF_EXPORT=$_UDF_FORMAT"
    echo "CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp/$_UDF_MANIFEST"

  local nf nd
  nf=$(find "$_FX_EXEC_DIR" -mindepth 1 -type f | wc -l)
  nd=$(find "$_FX_EXEC_DIR" -mindepth 1 -type d | wc -l)

  if (cd "$_FX_EXEC_DIR" && zip -q -r -y "$out" .) \
     && (cd "$tmp" && zip -q "$out" "$_UDF_MANIFEST"); then
    echo "📦 Exported ${nf} file(s), ${nd} folder(s)"
    echo "   → $out"
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"; rm -f "$out"
  echo "❌ Export failed"
  return 1
}

# ── ui : import ──────────────────────────────────────────────────────────────
_fx_udf_import() {
  _udf_need unzip || return 1
  _fx_ensure_store

  zip_file=""
  open_zip_menu "${_fx_outer_path:-$PWD}" || return 1
  local zf="$zip_file"

  local list
  if ! list=$(unzip -Z1 "$zf" 2>/dev/null); then
    echo "❌ Not a readable zip: ${zf##*/}"; return 1
  fi
  if ! grep -qxF "$_UDF_MANIFEST" <<<"$list"; then
    echo "❌ '${zf##*/}' is not a UDF export (no $_UDF_MANIFEST inside)"; return 1
  fi
  if grep -qE '(^/|(^|/)\.\.(/|$))' <<<"$list"; then
    echo "❌ Refusing '${zf##*/}': it contains absolute or '..' paths"; return 1
  fi
  local ver
  ver=$(unzip -p "$zf" "$_UDF_MANIFEST" 2>/dev/null | tr -d '\r' | sed -n 's/^BVK_UDF_EXPORT=//p' | head -n1)
  if ! [[ "$ver" =~ ^[0-9]+$ ]] || [ "$ver" -gt "$_UDF_FORMAT" ]; then
    echo "❌ Unsupported UDF export format (${ver:-unknown}) — update the app first"; return 1
  fi

  local nf=0 nd=0 clash=0 e
  while IFS= read -r e; do
    [ -z "$e" ] || [ "$e" = "$_UDF_MANIFEST" ] && continue
    if [[ "$e" == */ ]]; then
      nd=$((nd+1))
    else
      nf=$((nf+1))
      [ -e "$_FX_EXEC_DIR/$e" ] || [ -L "$_FX_EXEC_DIR/$e" ] && clash=$((clash+1))
    fi
  done <<<"$list"
  if [ $((nf + nd)) -eq 0 ]; then
    echo "ℹ️  '${zf##*/}' contains no UDFs"; return 1
  fi

  echo ""
  echo "📥 Import UDFs from: ${zf##*/}"
  echo "   ${nf} file(s), ${nd} folder(s) — ${clash} already exist here"

  local mode="-n" ans
  if [ "$clash" -gt 0 ]; then
    echo "1) Keep existing   (skip the ${clash} file(s) that already exist)"
    echo "2) Overwrite       (replace the ${clash} file(s) that already exist)"
    echo "x) Cancel"
    read -r -p "Choice [1/2/x]: " ans
    ans="${ans%$'\r'}"
    case "$ans" in
      1) mode="-n" ;;
      2) mode="-o" ;;
      *) echo "🚫 Import cancelled"; return 1 ;;
    esac
  fi

  if unzip -q "$mode" "$zf" -x "$_UDF_MANIFEST" -d "$_FX_EXEC_DIR"; then
    echo "✅ Imported into $_FX_EXEC_DIR"
    return 0
  fi
  echo "⚠️  Import finished with errors (some entries may have been skipped)"
  return 1
}
