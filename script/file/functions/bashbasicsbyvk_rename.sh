#!/usr/bin/env bash
# Rename handling — single mutation (interactive per-item rename)
# Multi-mutation (CSV batch rename) lives in bashbasicsbyvk_functions.sh as ADF.
# Requires: bashbasicsbyvk_csv.sh (open_csv_menu)
#           select_items_common, _shortcut_read_field (from main / organise)

# ---------------------------------------------------------------------------
# _sync_shortcuts_for_rename <old_abs_path> <new_abs_path>
# Scans every .shortcut file under $HOME and rewrites SHORTCUT_PATH wherever
# it references old_abs_path (exact match for a file rename) or has it as a
# directory prefix (any item inside a renamed folder).
# Called automatically after every successful mv inside this script.
# ---------------------------------------------------------------------------
_sync_shortcuts_for_rename() {
  # Batch mode (CSV rename): just remember the pair; synced once afterwards.
  if [ "${_RN_DEFER:-0}" = "1" ]; then
    _RN_DEF_OLD+=("$1"); _RN_DEF_NEW+=("$2")
    return 0
  fi
  _scr_rename_sync "$1" "$2"
}

# ---------------------------------------------------------------------------
# Batch shortcut-registry sync for CSV rename.
# Applies ALL renames in ONE registry pass instead of load+rewrite per rename.
# Uses the registry's own _scr_load/_scr_save; registry code is unchanged.
# ---------------------------------------------------------------------------
_RN_DEFER=0; _RN_DEF_OLD=(); _RN_DEF_NEW=()

_rn_defer_begin() { _RN_DEFER=1; _RN_DEF_OLD=(); _RN_DEF_NEW=(); }

_rn_flush_deferred() {
  _RN_DEFER=0
  _scr_sync_pairs _RN_DEF_OLD _RN_DEF_NEW
  _RN_DEF_OLD=(); _RN_DEF_NEW=()
  return 0
}
# ---------------------------------------------------------------------------
# _do_rename_mv <old_path> <new_path>
# Central mv wrapper used by all rename paths.  Handles:
#   • Conflict detection   — blocks if a genuinely different item already exists
#   • Case-only renames    — detected via realpath so "mad → MAD" is allowed
#                            even on case-insensitive filesystems (two-step mv)
#   • Shortcut sync        — calls _sync_shortcuts_for_rename on success
#
# Return codes:
#   0  success
#   1  mv failed (OS error)
#   3  new name is over 255 bytes: caller prints the limit message (_bvk_name_refuse)
#   2  real conflict — caller should print "already exists"
# ---------------------------------------------------------------------------
_do_rename_mv() {
  local old_path="$1"
  local new_path="$2"

  # over 255 bytes: refuse (rc 3) - the caller says so
  _bvk_name_too_long "${new_path##*/}" && return 3

  if [ -e "$new_path" ]; then
    local real_old real_new
    real_old=$(realpath "$old_path" 2>/dev/null)
    real_new=$(realpath "$new_path" 2>/dev/null)
    if [ "$real_old" != "$real_new" ]; then
      # A genuinely different item already occupies the destination.
      return 2
    fi
    # Same inode — pure case change on a case-insensitive filesystem.
    # Two-step rename: old → temp → new  (avoids "same file" rejection).
    local _tmp="${old_path%/*}/.$$_caseswap"
    if mv -- "$old_path" "$_tmp" && mv -- "$_tmp" "$new_path"; then
      _lk_load; _lk_move "$old_path" "$new_path"
      _sync_shortcuts_for_rename "$old_path" "$new_path"
      return 0
    else
      echo "❌ Case rename failed" >&2
      [ -e "$_tmp" ] && mv -- "$_tmp" "$old_path"   # best-effort rollback
      return 1
    fi
  fi

  if mv -- "$old_path" "$new_path"; then
    _lk_load; _lk_move "$old_path" "$new_path"
    _sync_shortcuts_for_rename "$old_path" "$new_path"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# rename_item <path>
# Low-level: prompts for a new name and mv's a single file or folder.
# Called by handle_file (run.sh option 7) as well as _rename_single_mutation.
# ---------------------------------------------------------------------------
rename_item() {
  local target="$1"
  local dir newname new_path

  if [ -d "$target" ]; then
    dir=$(dirname -- "$target")
    read -e -p "Enter new folder name for '$(basename "$target")': " newname
  elif [ -f "$target" ]; then
    dir=$(dirname -- "$target")
    read -e -p "Enter new file name for '$(basename "$target")': " newname
  else
    echo "❌ Cannot rename: '$target' not found." >&2
    return 1
  fi

  new_path="$dir/$newname"
  _do_rename_mv "$target" "$new_path"
  local rc=$?
  case $rc in
    0) echo "💫 Renamed: $(basename "$target") → $newname" ;;
    2) echo "🔴  '$newname' already exists — skipped" ;;
    3) _bvk_name_refuse "$newname" "Name"; echo " Not renamed: names over 255 bytes are not accepted." ;;
  esac
  return $rc
}

# ---------------------------------------------------------------------------
# Extension rule of the one-by-one rename (the CSV rename uses names exactly as written).
#   the new name has an extension (the same or another one)  → it is used, instead of the old one
#   the new name has none                                      → Settings → Rename → No extension: old · none · ask
# _rn_ext_of NAME → _RN_EXT   (".txt", ".tar.gz"; "" for a name without one, a dotfile such as .bashrc, or a trailing dot)
# ---------------------------------------------------------------------------
_rn_ext_of() {
  local n="$1" last stem
  _RN_EXT=""
  [[ "$n" == *.* ]] || return 0
  last="${n##*.}"; stem="${n%.*}"
  [ -n "$last" ] && [ -n "$stem" ] || return 0
  _RN_EXT=".$last"
  [[ "${stem,,}" == *.tar && "${stem%.*}" != "" ]] && _RN_EXT=".${stem##*.}.$last"
  return 0
}

# _rn_finalize ITEM NEWNAME → _RN_FINAL.  rc 1 = the question was backed out (u / q): skip this item.
_rn_finalize() {
  local item="$1" new="$2" oext
  _RN_FINAL="$new"
  [ -d "$item" ] && return 0                                   # a folder has no extension to keep
  _rn_ext_of "$new"; [ -n "$_RN_EXT" ] && return 0              # it has one: used as typed
  _rn_ext_of "${item##*/}"; oext="$_RN_EXT"
  [ -n "$oext" ] || return 0                                    # the old name had none either: nothing to decide
  local mode="${rename_noext_mode:-ask}" ans
  if [ "$mode" = ask ]; then
    _bvk_menu ans -t "No extension" -i "✏️" -q "'${new}' has no extension. The old one is ${oext}" \
      old:"Use old extension  →  ${new%.}${oext}" none:"Create without extension  →  ${new}" || return 1
    mode="$ans"
  fi
  [ "$mode" = old ] && _RN_FINAL="${new%.}${oext}"
  return 0
}

# ---------------------------------------------------------------------------
# _rn_name_prompt ITEM N TOTAL → _RN_FINAL.  rc 1 = blank / cancelled.
#   ✏️ Rename · what it is (the Settings description) · the selected items · u) Up  q) Close · suggestions · Old: / New:
# ---------------------------------------------------------------------------
_rn_name_prompt() {
  local item="$1" cur="$2" total="$3" bn="${item##*/}"
  local rows cols; rows=$(_term_rows 2>/dev/null); cols=$(_term_cols 2>/dev/null)
  [ "${_vp_rows_now:-0}" -gt 0 ] 2>/dev/null && { rows=$_vp_rows_now; cols=$_vp_cols_now; }
  [[ "$rows" =~ ^[0-9]+$ ]] || rows=24; [[ "$cols" =~ ^[0-9]+$ ]] || cols=60
  local out="" nl=$'\n' rule="${_ST_RULE:-   ─────────────────────────────}" ln i
  out+="$nl✏️ Rename$nl$nl"
  # the description: the same table and the same wrapping as a Settings screen
  declare -F _st_desc_load >/dev/null 2>&1 && { [ -n "${_ST_DESC[Settings|*]:-}" ] || _st_desc_load; }
  if declare -F _st_desc_wrap >/dev/null 2>&1 && [ -n "${_ST_DESC[Rename item|*]:-}" ] && (( rows >= 18 )); then
    _st_desc_wrap "${_ST_DESC[Rename item|*]}" $(( cols - 2 ))
    local dmax=$(( rows / 4 )); (( dmax < 2 )) && dmax=2
    for (( i=0; i<${#_ST_DESC_ALL[@]} && i<dmax; i++ )); do out+=$'\033[2m'"${_ST_DESC_ALL[$i]}"$'\033[0m'"$nl"; done
    out+="$nl"
  fi
  # the selected items, a window that keeps the current one in view
  local vis=$(( rows - 17 )); (( vis < 1 )) && vis=1; (( vis > total )) && vis=$total
  local top=$(( cur - 1 - vis / 2 )); (( top > total - vis )) && top=$(( total - vis )); (( top < 0 )) && top=0
  if (( top > 0 )); then out+="   ▲ $top more above$nl"; else out+="$rule$nl"; fi
  local _rdp_icon _rdp_bn _sc_icon _sc_display
  for (( i=top; i<top+vis; i++ )); do
    _resolve_display_parts_v "${selected_items[$i]}"
    printf -v ln ' %2d) %s %s' "$(( i + 1 ))" "$_rdp_icon" "$_rdp_bn"
    if (( i + 1 == cur )); then out+=$'\033[1;7m'"$ln"$'\033[0m'"$nl"; else out+="$ln$nl"; fi
  done
  if (( top + vis < total )); then out+="   ▼ $(( total - top - vis )) more below$nl"; else out+="$rule$nl"; fi
  out+="${nl}u) Up   q) Close$nl$nl"
  # cheat-code suggestions: they expand onto more rows on a narrow screen, as everywhere
  local tip="↑ or a tap on Old  →  copy the old name here and edit it  ·  print  ·  cc  ·  u  ·  q"
  if declare -F _bvk_hint_wrap >/dev/null 2>&1; then _bvk_hint_wrap "$tip" 3 $(( cols - 2 )); for ln in "${_BVK_HINT_LN[@]}"; do out+=$'\033[2m'"$ln"$'\033[0m'"$nl"; done; fi
  out+="$nl"
  out+="Old: $bn$nl"
  builtin printf '%s' "$out"
  _BVK_SCR_RAW="$out"; _BVK_SCR_EXTRA=""; _BVK_SCR_PROMPT="New:"
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  local in
  _CE_FILL="$bn"
  read -e -p "New: " in; local rc=$?
  _CE_FILL=""
  (( rc == 0 )) && [ -n "$in" ] || return 1
  _rn_finalize "$item" "$in" || return 1
  return 0
}

# ---------------------------------------------------------------------------
# _rename_single_mutation
# Select items via the viewport multi-picker, then ask for a new name for each.
# Shortcut files get special handling (name-only, not the .shortcut pointer).
# ---------------------------------------------------------------------------
_rename_single_mutation() {
  select_items_common "RENAME" || return

  # a long selection is not asked item by item: it goes straight to the CSV rename (rename.select.items.csv)
  local _lim="${rename_csv_above:-5}"
  if [[ "$_lim" =~ ^[0-9]+$ ]] && (( _lim > 0 && ${#selected_items[@]} > _lim )); then
    echo "📑 ${#selected_items[@]} items selected (more than $_lim): continuing with the CSV rename (rename.select.items.csv)."
    echo "   The number is in Settings → Rename."
    _rename_multi_mutation
    return
  fi

  local idx
  for idx in "${!selected_items[@]}"; do
    local item="${selected_items[$idx]}"
    local bn="${item##*/}"

    if [[ "$bn" == *.shortcut ]]; then
      local cur_name sc_type_r
      cur_name=$(_shortcut_read_field "$item" "SHORTCUT_NAME")
      [ -z "$cur_name" ] && cur_name="${bn%.shortcut}"
      sc_type_r=$(_shortcut_read_field "$item" "SHORTCUT_TYPE")
      [ "$sc_type_r" == "dir" ] \
        && echo "🔑  Shortcut (dir): $cur_name" \
        || echo "🗝️  Shortcut (file): $cur_name"
      echo "Renaming a shortcut only changes the shortcut's name — the original is untouched."
      read -e -p "New display name (blank = cancel): " new_name
      [ -z "$new_name" ] && echo "🚫 Skipped" && continue
      if _bvk_name_too_long "${new_name}.shortcut"; then _bvk_name_refuse "$new_name" "Shortcut"; echo " Not renamed: names over 255 bytes are not accepted."; continue; fi

      local tmp_file
      tmp_file=$(mktemp)
      sed "s|^SHORTCUT_NAME=.*|SHORTCUT_NAME=${new_name}|" "$item" > "$tmp_file" \
        && mv "$tmp_file" "$item"

      local new_sc_path count=1
      new_sc_path="$(dirname "$item")/${new_name}.shortcut"
      while [ -e "$new_sc_path" ] && [ "$new_sc_path" != "$item" ]; do
        new_sc_path="$(dirname "$item")/${new_name}${count}.shortcut"
        count=$((count + 1))
      done
 if [ "$new_sc_path" != "$item" ]; then
  _scr_remove "$item"
  mv -- "$item" "$new_sc_path"
  _scr_add "$new_sc_path"
  _lk_load; _lk_move "$item" "$new_sc_path"      # a locked shortcut stays locked
fi
echo "💫 Shortcut renamed: $cur_name → $new_name"
      continue
    fi

    _rn_name_prompt "$item" "$((idx + 1))" "${#selected_items[@]}" || { echo "🚫 Skipped"; continue; }
    local new_name="$_RN_FINAL"
    local new_path
    new_path="$(dirname "$item")/$new_name"
    _do_rename_mv "$item" "$new_path"
    local rc=$?
    case $rc in
      0) echo "💫 Renamed: $bn → $new_name" ;;
      2) echo "🔴  '$new_name' already exists — skipped" ;;
      3) _bvk_name_refuse "$new_name" "Name"; echo " Not renamed: names over 255 bytes are not accepted." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# _rename_multi_mutation
# CSV-driven batch rename in the current path.
# CSV format: col1=exact_old_name, col2=exact_new_name
# Writes renamed count back to col3 of the CSV.
# ---------------------------------------------------------------------------
_rename_multi_mutation() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return

  local -a rn_old=() rn_new=() rn_counts=()

  # Parse CSV — col1=old_name, col2=new_name (no forks)
  while IFS=, read -r _old _new _rest || [ -n "$_old" ]; do
    _old="${_old#"${_old%%[![:space:]]*}"}"; _old="${_old%"${_old##*[![:space:]]}"}"
    _old="${_old%$'\r'}"
    _new="${_new#"${_new%%[![:space:]]*}"}"; _new="${_new%"${_new##*[![:space:]]}"}"
    _new="${_new%$'\r'}"
    [ -z "$_old" ] && continue
    rn_old+=("$_old")
    rn_new+=("$_new")
  done < "$csv_file"

  local total=${#rn_old[@]}
  if [ "$total" -eq 0 ]; then
    echo "❌ No valid rows found in CSV."
    return
  fi

  local -a fail_names=() fail_reasons=()
  local ok=0 row_idx old_name new_name tgt rc renamed errf errmsg
  local base="${path%/}"
  errf=$(mktemp)

  # Registry sync is deferred and done ONCE at the end (not per rename).
  _rn_defer_begin

  for row_idx in "${!rn_old[@]}"; do
    old_name="${rn_old[$row_idx]}"
    new_name="${rn_new[$row_idx]}"
    tgt="$base/$old_name"
    renamed=0

    if [[ "$old_name" == */* || "$old_name" == "." || "$old_name" == ".." ]]; then
      fail_names+=("$old_name"); fail_reasons+=("row $((row_idx+1)): old name must be a bare name in the current folder")
    elif [ ! -e "$tgt" ] && [ ! -L "$tgt" ]; then
      fail_names+=("$old_name"); fail_reasons+=("row $((row_idx+1)): not found in $path")
    elif [ -z "$new_name" ]; then
      fail_names+=("$old_name"); fail_reasons+=("row $((row_idx+1)): new name (column 2) is empty")
    else
      _do_rename_mv "$tgt" "$base/$new_name" 2>"$errf"
      rc=$?
      case $rc in
        0) renamed=1; ok=$((ok + 1)) ;;
        2) fail_names+=("$old_name"); fail_reasons+=("row $((row_idx+1)): target \"$new_name\" already exists") ;;
        3) fail_names+=("$old_name"); fail_reasons+=("row $((row_idx+1)): not renamed - the new name exceeds 255 bytes (the accepted standard)") ;;
        *) errmsg=""
           [ -s "$errf" ] && IFS= read -r errmsg < "$errf"
           fail_names+=("$old_name"); fail_reasons+=("row $((row_idx+1)): rename failed${errmsg:+ — $errmsg}") ;;
      esac
    fi
    rn_counts+=("$renamed")
  done
  rm -f "$errf"

  _rn_flush_deferred

  # Write counts back to col3 of the CSV (single pass, no forks)
  local tmp_csv="${csv_file}.tmp"
  local write_idx=0
  while IFS=, read -r _old _new _rest || [ -n "$_old" ]; do
    local raw_old="$_old" raw_new="$_new"
    local trimmed="${_old#"${_old%%[![:space:]]*}"}"; trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    trimmed="${trimmed%$'\r'}"
    if [ -z "$trimmed" ]; then
      printf "%s,%s,%s\n" "$raw_old" "$raw_new" "${_rest:-}"
      continue
    fi
    printf "%s,%s,%s renamed\n" "$raw_old" "$raw_new" "${rn_counts[$write_idx]:-0}"
    write_idx=$((write_idx + 1))
  done < "$csv_file" > "$tmp_csv"
  mv "$tmp_csv" "$csv_file"

  echo "💫 Renamed: ${ok}/${total} names   (counts written to $(basename "$csv_file"))"
  local i
  if [ ${#fail_names[@]} -gt 0 ]; then
    echo "🔴  ${#fail_names[@]} failed:"
    for i in "${!fail_names[@]}"; do
      printf '   ❌ %s — %s\n' "${fail_names[$i]}" "${fail_reasons[$i]}"
    done
  fi
}

# ---------------------------------------------------------------------------
# handle_rename  (main menu: r)
# Selects items interactively and renames each one individually.
# For CSV batch rename, use the fx tab → ADF → rename.select.items.csv
# ---------------------------------------------------------------------------
handle_rename() {
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items to rename"
    return
  fi
  _rename_single_mutation
}
