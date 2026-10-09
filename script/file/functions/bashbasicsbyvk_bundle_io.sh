#!/usr/bin/env bash
# bashbasicsbyvk_bundle_io.sh — ONE implementation of "export everything to a zip /
# import everything from a zip", shared by:
#     fx  UDF tab   ux / ui      (loops/fx/bashbasicsbyvk_udf_io.sh)
#     .r  rule book ux / ui      (select/bashbasicsbyvk_rules.sh)
# so the two can never drift apart again.
#
#  Zip format (fixed, version 1)
#    • paths are relative to the store folder, so files, sub-folders, empty folders and
#      exec bits all round-trip
#    • a manifest file at the zip root marks the zip as this kind of export:
#          <KEY>=<format>
#          CREATED=<UTC timestamp>
#    • import refuses zips without the manifest, zips with absolute / ".." paths, and
#      (when the caller gives an entry pattern) zips with files outside the expected
#      layout; nothing is ever deleted — you choose to keep or overwrite clashes
#
#  Uses: open_zip_menu → _file_picker (bashbasicsbyvk_csv.sh), _bvk_quit
# ════════════════════════════════════════════════════════════════════════════

_bz_need() {                       # _bz_need <command>
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "❌ '$1' not found — install it first (e.g. pkg install $1)."
  return 1
}

# _bz_dest <preferred-folder> [guard-folder…]  → prints where the zip should be written:
# the preferred folder, or $HOME when it is unset or lies inside a guarded store folder
# (an archive written into the store would end up archiving itself / being imported).
_bz_dest() {
  local dest="${1:-$HOME}" g; shift
  for g in "$@"; do
    case "${dest%/}/" in "${g%/}"/*) dest="$HOME" ;; esac
  done
  printf '%s' "$dest"
}

# _bz_export <store> <dest-folder> <file-prefix> <manifest> <KEY> <format> <noun-plural> [entry…]
#   entries = what to zip, relative to <store> (default ".": the whole store)
_bz_export() {
  local src="$1" dest="$2" prefix="$3" manifest="$4" key="$5" fmt="$6" pl="$7"; shift 7
  local -a ent=("$@"); [ ${#ent[@]} -gt 0 ] || ent=(.)
  _bz_need zip || return 1
  if [ -z "$(cd "$src" && find "${ent[@]}" -mindepth 1 -print -quit 2>/dev/null)" ]; then
    echo "ℹ️  No $pl to export"; return 1
  fi

  local base out n=1
  base="${dest%/}/${prefix}_$(date +%Y%m%d_%H%M%S)"
  out="$base.zip"
  while [ -e "$out" ]; do out="${base}_${n}.zip"; n=$((n+1)); done

  local tmp; tmp=$(mktemp -d) || { echo "❌ Cannot create a temp folder"; return 1; }
  {
    echo "$key=$fmt"
    echo "CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$tmp/$manifest"

  local nf nd
  nf=$(cd "$src" && find "${ent[@]}" -mindepth 1 -type f | wc -l)
  nd=$(cd "$src" && find "${ent[@]}" -mindepth 1 -type d | wc -l)

  if (cd "$src" && zip -q -r -y "$out" "${ent[@]}") \
     && (cd "$tmp" && zip -q "$out" "$manifest"); then
    echo "📦 Exported ${nf} file(s), ${nd} folder(s)"
    echo "   → $out"
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"; rm -f "$out"
  echo "❌ Export failed"
  return 1
}

# _bz_import <store> <picker-start-folder> <manifest> <KEY> <format> <noun> <noun-plural> [entry-regex]
#   entry-regex (ERE, optional): every zip entry except the manifest must match it
_bz_import() {
  local store="$1" from="$2" manifest="$3" key="$4" fmt="$5" sing="$6" pl="$7" re="${8:-}"
  _bz_need unzip || return 1

  # _BZ_PICKED: the caller already picked the zip (e.g. -auth lets you pick zip OR txt)
  local zf
  if [ -n "${_BZ_PICKED:-}" ]; then
    zf="$_BZ_PICKED"
  else
    zip_file=""
    open_zip_menu "$from" || return 1
    zf="$zip_file"
  fi

  local list
  if ! list=$(unzip -Z1 "$zf" 2>/dev/null); then
    echo "❌ Not a readable zip: ${zf##*/}"; return 1
  fi
  if ! grep -qxF "$manifest" <<<"$list"; then
    echo "❌ '${zf##*/}' is not a $sing export (no $manifest inside)"; return 1
  fi
  if grep -qE '(^/|(^|/)\.\.(/|$))' <<<"$list"; then
    echo "❌ Refusing '${zf##*/}': it contains absolute or '..' paths"; return 1
  fi
  if [ -n "$re" ]; then
    local bad
    while IFS= read -r bad; do
      [ -z "$bad" ] || [ "$bad" = "$manifest" ] && continue
      [[ "$bad" =~ $re ]] && continue
      echo "❌ Refusing '${zf##*/}': it contains files outside the expected layout ($bad)"; return 1
    done <<<"$list"
  fi
  local ver
  ver=$(unzip -p "$zf" "$manifest" 2>/dev/null | tr -d '\r' | sed -n "s/^${key}=//p" | head -n1)
  if ! [[ "$ver" =~ ^[0-9]+$ ]] || [ "$ver" -gt "$fmt" ]; then
    echo "❌ Unsupported $sing export format (${ver:-unknown}) — update the app first"; return 1
  fi

  local nf=0 nd=0 clash=0 e
  while IFS= read -r e; do
    [ -z "$e" ] || [ "$e" = "$manifest" ] && continue
    if [[ "$e" == */ ]]; then
      nd=$((nd+1))
    else
      nf=$((nf+1))
      [ -e "$store/$e" ] || [ -L "$store/$e" ] && clash=$((clash+1))
    fi
  done <<<"$list"
  if [ $((nf + nd)) -eq 0 ]; then
    echo "ℹ️  '${zf##*/}' contains no $pl"; return 1
  fi

  echo ""
  echo "📥 Import $pl from: ${zf##*/}"
  echo "   ${nf} file(s), ${nd} folder(s) — ${clash} already exist here"

  local mode="-n" ans
  if [ "$clash" -gt 0 ]; then
    echo "1) Keep existing   (skip the ${clash} file(s) that already exist)"
    echo "2) Overwrite       (replace the ${clash} file(s) that already exist)"
    echo "z) Cancel   u) Back"
    read -r -p "Choice [1/2/z]: " ans
    ans="${ans%$'\r'}"
    case "$ans" in
    u|U) return ;;
    q|Q) _bvk_quit ;;
      1) mode="-n" ;;
      2) mode="-o" ;;
      *) echo "🚫 Import cancelled"; return 1 ;;
    esac
  fi

  if unzip -q "$mode" "$zf" -x "$manifest" -d "$store"; then
    [ -n "${_BZ_QUIET:-}" ] || echo "✅ Imported into $store"
    return 0
  fi
  echo "⚠️  Import finished with errors (some entries may have been skipped)"
  return 1
}
