#!/usr/bin/env bash
# Archive handling — zip and unzip via item-index prefixes
# Requires: _sp_resolve_itemlist, parse_selection (from bashbasicbyvk_shortpath.sh)
#
# z-<list>   zip items by number  →  z-1,3,5   z-2-6
# uz-<list>  unzip items by number → uz-2       uz-1,4,7

# ---------------------------------------------------------------------------
# handle_zip_items  z-<itemlist>
# Zips the selected items together into one named archive inside $path.
# Prompts for the archive name; strips .zip suffix if user types it.
# Uses relative paths so the archive never embeds absolute filesystem paths.
# ---------------------------------------------------------------------------
handle_zip_items() {
  local raw="$1"
  local itemlist="${raw#z-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: z-1,3,5  or  z-1-4  (zip selected items into a named archive)"
    return
  fi

  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using z-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return

  if ! command -v zip &>/dev/null; then
    echo "❌ 'zip' not found — install it first (e.g. pkg install zip)."
    return 1
  fi

  echo ""
  read -p "📦 Name for the archive (without .zip): " zip_name
  zip_name="${zip_name%$'\r'}"
  [ -z "$zip_name" ] && echo "🚫 Cancelled — no name given." && return

  # Strip trailing .zip if user typed it
  zip_name="${zip_name%.zip}"

  local zip_path="$path/${zip_name}.zip"

  if [ -e "$zip_path" ]; then
    read -p "⚠️  '${zip_name}.zip' already exists. Overwrite? [y/N]: " ow
    [[ "$ow" =~ ^[Yy]$ ]] || { echo "🚫 Cancelled."; return; }
    rm -f "$zip_path"
  fi

  echo ""
  echo "🗜️  Zipping ${#sp_resolved[@]} item(s) → ${zip_name}.zip"

  # Build list of basenames so zip doesn't embed absolute paths
  local -a rel_items=()
  local p
  for p in "${sp_resolved[@]}"; do
    rel_items+=("$(basename "$p")")
  done

  ( cd "$path" && zip -r "$zip_path" "${rel_items[@]}" )
  local rc=$?

  if [ $rc -eq 0 ]; then
    echo "✅ Created: ${zip_name}.zip"
  else
    echo "❌ zip exited with code $rc."
  fi
}

# ---------------------------------------------------------------------------
# handle_unzip_items  uz-<itemlist>
# Unzips each selected .zip into its own named folder inside $path.
# uz-2       → creates  myarchive/  and extracts into it
# uz-1,4,7   → creates  a/  b/  c/  for each respectively
# If the destination folder already exists, appends _1, _2, … to avoid clobber.
# ---------------------------------------------------------------------------
handle_unzip_items() {
  local raw="$1"
  local itemlist="${raw#uz-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: uz-2  or  uz-1,4,7  (each zip gets its own folder)"
    return
  fi

  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using uz-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return

  if ! command -v unzip &>/dev/null; then
    echo "❌ 'unzip' not found — install it first (e.g. pkg install unzip)."
    return 1
  fi

  echo ""

  local p succeeded=0 skipped=0
  for p in "${sp_resolved[@]}"; do
    local bn="${p##*/}"

    if [[ "${bn,,}" != *.zip ]]; then
      echo "  ⚠️  Skipping '$bn' — not a .zip file"
      skipped=$((skipped + 1))
      continue
    fi

    # Strip .zip (case-insensitive) to derive the folder name
    local folder_name="${bn}"
    folder_name="${folder_name%.[Zz][Ii][Pp]}"
    # Handle .ZIP, .Zip, etc. via parameter expansion
    [[ "$folder_name" == "$bn" ]] && folder_name="${bn%.*}"

    local dest_dir="${path}/${folder_name}"

    # Avoid clobbering an existing folder
    if [ -e "$dest_dir" ]; then
      local counter=1
      while [ -e "${dest_dir}_${counter}" ]; do
        counter=$((counter + 1))
      done
      echo "  ℹ️  '${folder_name}' already exists — using '${folder_name}_${counter}' instead"
      dest_dir="${dest_dir}_${counter}"
    fi

    mkdir -p "$dest_dir"
    echo "  📂 Extracting '$bn' → $(basename "$dest_dir")/"
    unzip -q "$p" -d "$dest_dir"
    local rc=$?

    if [ $rc -eq 0 ]; then
      echo "  ✅ Done"
      succeeded=$((succeeded + 1))
    else
      echo "  ❌ unzip failed for '$bn' (exit code $rc)"
      rmdir "$dest_dir" 2>/dev/null   # clean up if empty
    fi
  done

  echo ""
  if [ $((succeeded + skipped)) -eq 0 ]; then
    echo "⚠️  No items processed."
  else
    echo "🎉 Unzip complete — $succeeded extracted$([ $skipped -gt 0 ] && echo ", $skipped skipped")."
  fi
}
