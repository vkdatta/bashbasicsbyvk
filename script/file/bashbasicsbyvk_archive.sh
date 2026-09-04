#!/usr/bin/env bash
# Archive handling — compress and decompress via item-index prefixes
# Requires: _sp_resolve_itemlist, parse_selection (from bashbasicbyvk_shortpath.sh)
#
# z-<list>   compress items by number  →  z-1,3,5   z-2-6
# uz-<list>  decompress items by number → uz-2       uz-1,4,7
#            uz- auto-detects format from extension (.zip / .tar.gz / .tgz)

# ---------------------------------------------------------------------------
# handle_compress_items  z-<itemlist>
# Compresses the selected items into one named archive inside $path.
# Format is determined by the compress_format setting (zip | targz | ask).
# Prompts for the archive name; strips known extensions if user types them.
# Uses relative paths so the archive never embeds absolute filesystem paths.
# ---------------------------------------------------------------------------
handle_compress_items() {
  local raw="$1"
  local itemlist="${raw#z-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: z-1,3,5  or  z-1-4  (compress selected items into a named archive)"
    return
  fi

  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using z-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return

  # ── Determine format ────────────────────────────────────────────────────
  local fmt="${compress_format:-ask}"

  if [ "$fmt" = "ask" ]; then
    echo ""
    echo "📦 Compress as:"
    echo "   1) zip"
    echo "   2) tar.gz"
    read -r -p "Choice [1-2]: " fmt_choice
    fmt_choice="${fmt_choice%$'\r'}"
    case "$fmt_choice" in
      1) fmt="zip" ;;
      2) fmt="targz" ;;
      *) echo "🚫 Cancelled — invalid choice." ; return ;;
    esac
  fi

  # ── Tool availability check ─────────────────────────────────────────────
  if [ "$fmt" = "zip" ] && ! command -v zip &>/dev/null; then
    echo "❌ 'zip' not found — install it first (e.g. pkg install zip)."
    return 1
  fi
  if [ "$fmt" = "targz" ] && ! command -v tar &>/dev/null; then
    echo "❌ 'tar' not found — install it first."
    return 1
  fi

  # ── Archive name prompt ─────────────────────────────────────────────────
  echo ""
  if [ "$fmt" = "zip" ]; then
    read -r -p "📦 Name for the archive (without .zip): " arc_name
  else
    read -r -p "📦 Name for the archive (without .tar.gz): " arc_name
  fi
  arc_name="${arc_name%$'\r'}"
  [ -z "$arc_name" ] && echo "🚫 Cancelled — no name given." && return

  # Strip known extensions if user typed them
  arc_name="${arc_name%.tar.gz}"
  arc_name="${arc_name%.tgz}"
  arc_name="${arc_name%.zip}"

  # ── Build archive path ───────────────────────────────────────────────────
  local arc_path
  if [ "$fmt" = "zip" ]; then
    arc_path="$path/${arc_name}.zip"
  else
    arc_path="$path/${arc_name}.tar.gz"
  fi

  # ── Overwrite check ──────────────────────────────────────────────────────
  if [ -e "$arc_path" ]; then
    local ext; ext="${arc_path##*/}"
    read -r -p "⚠️  '${ext}' already exists. Overwrite? [y/N]: " ow
    ow="${ow%$'\r'}"
    [[ "$ow" =~ ^[Yy]$ ]] || { echo "🚫 Cancelled."; return; }
    rm -f "$arc_path"
  fi

  # ── Build relative item list ─────────────────────────────────────────────
  local -a rel_items=()
  local p
  for p in "${sp_resolved[@]}"; do
    rel_items+=("$(basename "$p")")
  done

  echo ""

  # ── Compress ─────────────────────────────────────────────────────────────
  if [ "$fmt" = "zip" ]; then
    echo "🗜️  Zipping ${#sp_resolved[@]} item(s) → ${arc_name}.zip"
    ( cd "$path" && zip -r "$arc_path" "${rel_items[@]}" )
    local rc=$?
    if [ $rc -eq 0 ]; then
      echo "✅ Created: ${arc_name}.zip"
    else
      echo "❌ zip exited with code $rc."
    fi
  else
    echo "🗜️  Creating tar.gz of ${#sp_resolved[@]} item(s) → ${arc_name}.tar.gz"
    ( cd "$path" && tar -czf "$arc_path" "${rel_items[@]}" )
    local rc=$?
    if [ $rc -eq 0 ]; then
      echo "✅ Created: ${arc_name}.tar.gz"
    else
      echo "❌ tar exited with code $rc."
    fi
  fi
}

# ---------------------------------------------------------------------------
# handle_decompress_items  uz-<itemlist>
# Decompresses each selected archive into its own named folder inside $path.
# Format is auto-detected from the file extension — no prompt.
#
# Supported extensions:
#   .zip          → unzip
#   .tar.gz / .tgz → tar -xzf
#
# uz-2       → creates  myarchive/  and extracts into it
# uz-1,4,7   → creates  a/  b/  c/  for each respectively
# If the destination folder already exists, appends _1, _2, … to avoid clobber.
# ---------------------------------------------------------------------------
handle_decompress_items() {
  local raw="$1"
  local itemlist="${raw#uz-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: uz-2  or  uz-1,4,7  (each archive gets its own folder)"
    return
  fi

  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using uz-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return

  echo ""

  local p succeeded=0 skipped=0
  for p in "${sp_resolved[@]}"; do
    local bn="${p##*/}"
    local bn_lower="${bn,,}"

    # ── Detect format from extension ───────────────────────────────────────
    local fmt=""
    local folder_name=""

    if [[ "$bn_lower" == *.tar.gz ]]; then
      fmt="targz"
      folder_name="${bn%.*}"        # strip .gz  → name.tar
      folder_name="${folder_name%.*}"  # strip .tar → name
    elif [[ "$bn_lower" == *.tgz ]]; then
      fmt="targz"
      folder_name="${bn%.*}"        # strip .tgz → name
    elif [[ "$bn_lower" == *.zip ]]; then
      fmt="zip"
      folder_name="${bn%.*}"        # strip .zip → name
    else
      echo "  ⚠️  Skipping '$bn' — unrecognised extension (supported: .zip, .tar.gz, .tgz)"
      skipped=$((skipped + 1))
      continue
    fi

    # ── Tool availability check ────────────────────────────────────────────
    if [ "$fmt" = "zip" ] && ! command -v unzip &>/dev/null; then
      echo "❌ 'unzip' not found — install it first (e.g. pkg install unzip)."
      return 1
    fi
    if [ "$fmt" = "targz" ] && ! command -v tar &>/dev/null; then
      echo "❌ 'tar' not found — install it first."
      return 1
    fi

    # ── Avoid clobbering an existing folder ───────────────────────────────
    local dest_dir="${path}/${folder_name}"
    if [ -e "$dest_dir" ]; then
      local counter=1
      while [ -e "${dest_dir}_${counter}" ]; do
        counter=$((counter + 1))
      done
      echo "  ℹ️  '${folder_name}' already exists — using '${folder_name}_${counter}' instead"
      dest_dir="${dest_dir}_${counter}"
    fi

    mkdir -p "$dest_dir"

    # ── Decompress ─────────────────────────────────────────────────────────
    if [ "$fmt" = "zip" ]; then
      echo "  📂 Extracting '$bn' → $(basename "$dest_dir")/"
      unzip -q "$p" -d "$dest_dir"
    else
      echo "  📂 Extracting '$bn' → $(basename "$dest_dir")/"
      tar -xzf "$p" -C "$dest_dir"
    fi
    local rc=$?

    if [ $rc -eq 0 ]; then
      echo "  ✅ Done"
      succeeded=$((succeeded + 1))
    else
      echo "  ❌ Extraction failed for '$bn' (exit code $rc)"
      rmdir "$dest_dir" 2>/dev/null   # clean up if empty
    fi
  done

  echo ""
  if [ $((succeeded + skipped)) -eq 0 ]; then
    echo "⚠️  No items processed."
  else
    echo "🎉 Done — $succeeded extracted$([ $skipped -gt 0 ] && echo ", $skipped skipped")."
  fi
}
