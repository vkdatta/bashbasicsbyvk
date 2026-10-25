#!/usr/bin/env bash
# Archive handling — compress and decompress via item-index prefixes
# Requires: _sp_resolve_itemlist, parse_selection (from bashbasicbyvk_staging.sh)
#
# z-<list>   compress items by number  →  z-1,3,5   z-2-6
# uz-<list>  decompress items by number → uz-2       uz-1,4,7
#            uz- recognises the format from the name AND the content (see bashbasicsbyvk_archive_formats.sh):
#                .zip .tar .tar.gz/.tgz .tar.xz/.txz .tar.bz2/.tbz2 .7z .tar.zst/.tzst .tar.lz4 .skill — also copies such as hello.zip1, hello_tar.gz, hello- (2).zip

# ---------------------------------------------------------------------------
# handle_compress_items  z-<itemlist>
# Compresses the selected items into one named archive inside $path.
# Format is determined by the compress_format setting (an id from bashbasicsbyvk_archive_formats.sh, or ask).
# Prompts for the archive name; strips known extensions if user types them.
# Uses relative paths so the archive never embeds absolute filesystem paths.
# ---------------------------------------------------------------------------
handle_compress_items() {
  local raw="$1"
  local itemlist="${raw#z-}"

  if [ -z "$itemlist" ]; then
    echo "🔴  Usage: z-1,3,5  or  z-1-4  (compress selected items into a named archive)"
    return
  fi

  if $imaginary_mode; then
    echo "🔴  Too many items to index directly — narrow the view before using z-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return
  _compress_paths "${sp_resolved[@]}"
}

# ---------------------------------------------------------------------------
# _compress_paths <path...>
# Core of z-. Also used by the fx zip.* functions (CSV / .s selection).
# Items under $path are stored with their path relative to $path. If any item
# lives outside $path (CSV absolute paths, .s selections from elsewhere) every
# item is staged by name through a temp folder of symlinks, so the archive
# never embeds absolute filesystem paths.
# ---------------------------------------------------------------------------
_compress_paths() {
  local -a in_paths=("$@") paths=()
  local p
  for p in "${in_paths[@]}"; do
    if [ -e "$p" ] || [ -L "$p" ]; then paths+=("$p"); else echo "  🔴  Skipping missing item: $p"; fi
  done
  if [ ${#paths[@]} -eq 0 ]; then
    echo "❌ Nothing to compress"
    return 1
  fi

  # ── Determine format ────────────────────────────────────────────────────
  local fmt="${compress_format:-ask}"
  _arc_is_fmt "$fmt" || fmt="ask"

  if [ "$fmt" = "ask" ]; then
    local -a _rows=() 
    local _f _miss
    for _f in "${_ARC_FORMATS[@]}"; do
      _miss=""; _arc_have create "$_f" || _miss="   (needs ${_ARC_MISSING})"
      _rows+=("$_f:${_ARC_LABEL[$_f]}  —  ${_ARC_NOTE[$_f]}${_miss}")
    done
    _bvk_menu fmt -t "Compress as" -i "📦" "${_rows[@]}" || return
    [ -n "$fmt" ] || { echo "🚫 Cancelled — invalid choice."; return; }
  fi

  # ── Tool availability check ─────────────────────────────────────────────
  _arc_need create "$fmt" || return 1
  local ext="${_ARC_LABEL[$fmt]}"

  # ── Archive name prompt ─────────────────────────────────────────────────
  echo ""
  read -e -r -p "Name for the archive (without ${ext}): " arc_name
  arc_name="${arc_name%$'\r'}"
  [ -z "$arc_name" ] && echo "🚫 Cancelled — no name given." && return

  # Strip a known ending if user typed it
  _arc_strip_ext "$arc_name"; arc_name="$_ARC_STRIPPED"

  if _bvk_name_too_long "${arc_name}${ext}"; then _bvk_name_refuse "$arc_name" "Archive"; return; fi

  # ── Build archive path ───────────────────────────────────────────────────
  local arc_path="$path/${arc_name}${ext}"

  # ── Overwrite check ──────────────────────────────────────────────────────
  if [ -e "$arc_path" ]; then
    local shown; shown="${arc_path##*/}"
    _bvk_yn ow "'${shown}' already exists. Overwrite?" -d none
    ow="${ow%$'\r'}"
    [[ "$ow" =~ ^[Yy]$ ]] || { echo "🚫 Cancelled."; return; }
    rm -f "$arc_path"
  fi

  # ── Hidden files inside the chosen folders (Settings → Zip hidden) ───────
  _hidden_decide "${zip_hidden_mode:-follow}" "the archive" "${paths[@]}" || return
  local hid_inc="$_hid_inc"

  # ── Build the item list (relative to workdir) ────────────────────────────
  local base="${path%/}/" outside=false
  for p in "${paths[@]}"; do
    [[ "$p" == "$base"* ]] || { outside=true; break; }
  done

  local workdir="$path" stage_dir=""
  local -a rel_items=()
  if $outside; then
    stage_dir=$(mktemp -d) || { echo "❌ Could not create a temp folder."; return 1; }
    workdir="$stage_dir"
    local bn cand n
    for p in "${paths[@]}"; do
      bn="${p##*/}"; cand="$bn"; n=1
      while [ -e "$stage_dir/$cand" ] || [ -L "$stage_dir/$cand" ]; do n=$((n+1)); cand="${bn}_$n"; done
      ln -s "$p" "$stage_dir/$cand"
      rel_items+=("$cand")
    done
  else
    for p in "${paths[@]}"; do rel_items+=("${p#"$base"}"); done
  fi

  echo ""

  # ── Compress ─────────────────────────────────────────────────────────────
  local rc follow=false
  $outside && follow=true                                             # the staging symlinks must be followed, never stored
  echo "🗜️  Creating ${ext#.} of ${#paths[@]} item(s) → ${arc_name}${ext}"
  _arc_create "$fmt" "$arc_path" "$workdir" "$hid_inc" "$follow" "${rel_items[@]}"
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "💫 Created: ${arc_name}${ext}"
  else
    echo "❌ ${fmt} archiving exited with code $rc."
  fi

  [ -n "$stage_dir" ] && rm -rf "$stage_dir"     # removes only the symlinks, never their targets
  return $rc
}

# ---------------------------------------------------------------------------
# handle_decompress_items  uz-<itemlist>
# Decompresses each selected archive into its own named folder inside $path.
# Format is detected from the name AND the content — no prompt (see bashbasicsbyvk_archive_formats.sh).
#
# Supported: .zip .tar .tar.gz/.tgz .tar.xz/.txz .tar.bz2/.tbz2 .7z .tar.zst/.tzst .tar.lz4 .skill
# (and copies of them: hello.zip1, hello_tar.gz, hello.tar-1.gz, hello- (2).zip)
#
# uz-2       → creates  myarchive/  and extracts into it
# uz-1,4,7   → creates  a/  b/  c/  for each respectively
# If the destination folder already exists, appends _1, _2, … to avoid clobber.
# ---------------------------------------------------------------------------
handle_decompress_items() {
  local raw="$1"
  local itemlist="${raw#uz-}"

  if [ -z "$itemlist" ]; then
    echo "🔴  Usage: uz-2  or  uz-1,4,7  (each archive gets its own folder)"
    return
  fi

  if $imaginary_mode; then
    echo "🔴  Too many items to index directly — narrow the view before using uz-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return
  _decompress_paths "${sp_resolved[@]}"
}

# ---------------------------------------------------------------------------
# _decompress_paths <archive...>
# Core of uz-. Also used by the fx unzip.* functions (CSV / .s selection) and the file menu's Extract.
# Each archive is extracted into its own folder inside $_arc_dest_base (default: $path).
# The format comes from the name AND the content (_arc_detect), so copies like hello.zip1 / hello_tar.gz open too.
# ---------------------------------------------------------------------------
_decompress_paths() {
  local -a paths=("$@")
  local dest_base="${_arc_dest_base:-$path}"
  echo ""

  local p succeeded=0 skipped=0
  for p in "${paths[@]}"; do
    if [ ! -f "$p" ]; then
      echo "  🔴  Skipping '${p##*/}' — not an existing file"
      skipped=$((skipped + 1))
      continue
    fi
    local bn="${p##*/}"

    # ── Detect format: name says "maybe", content decides ──────────────────
    if ! _arc_detect "$p"; then
      echo "  🔴  Skipping '$bn' — $_ARC_WHY"
      skipped=$((skipped + 1))
      continue
    fi
    local fmt="$_ARC_FMT" folder_name="$_ARC_STEM"
    [ -n "$folder_name" ] || folder_name="extracted"

    # ── Tool availability check ────────────────────────────────────────────
    _arc_need extract "$fmt" || return 1

    # ── Avoid clobbering an existing folder ───────────────────────────────
    local dest_dir="${dest_base}/${folder_name}"
    if [ -e "$dest_dir" ]; then
      local counter=1
      while [ -e "${dest_dir}_${counter}" ]; do
        counter=$((counter + 1))
      done
      echo "  📜  '${folder_name}' already exists — using '${folder_name}_${counter}' instead"
      dest_dir="${dest_dir}_${counter}"
    fi

    mkdir -p "$dest_dir"

    # ── Decompress ─────────────────────────────────────────────────────────
    echo "  📂 Extracting '$bn' → $(basename "$dest_dir")/"
    _arc_extract "$fmt" "$p" "$dest_dir"
    local rc=$?

    if [ $rc -eq 0 ]; then
      echo "  💫 Done"
      succeeded=$((succeeded + 1))
    else
      echo "  ❌ Extraction failed for '$bn' (exit code $rc)"
      rmdir "$dest_dir" 2>/dev/null   # clean up if empty
    fi
  done

  echo ""
  if [ $((succeeded + skipped)) -eq 0 ]; then
    echo "🔴  No items processed."
  else
    echo "🎉 Done — $succeeded extracted$([ $skipped -gt 0 ] && echo ", $skipped skipped")."
  fi
}
