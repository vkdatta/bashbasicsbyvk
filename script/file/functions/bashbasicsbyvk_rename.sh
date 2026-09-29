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
  if [ "${#_RN_DEF_OLD[@]}" -eq 0 ] || [ ! -f "$_SCR_FILE" ]; then
    _RN_DEF_OLD=(); _RN_DEF_NEW=(); return 0
  fi
  local -A _pold=()
  local i
  for i in "${!_RN_DEF_OLD[@]}"; do _pold["k:${_RN_DEF_OLD[$i]}"]=1; done

  local -a entries=() out=()
  _scr_load entries
  local e sc_file old_target cur new_target o nw tmp_file hit updated=0 dirty=0
  for e in "${entries[@]}"; do
    sc_file="${e%%${_SCR_SEP}*}"
    old_target="${e#*${_SCR_SEP}}"
    hit=0; cur="$old_target"
    while [ -n "$cur" ]; do
      if [ -n "${_pold["k:$cur"]+x}" ]; then hit=1; break; fi
      [[ "$cur" == */* ]] || break
      cur="${cur%/*}"
    done
    if [ "$hit" -eq 0 ]; then out+=("$e"); continue; fi

    new_target="$old_target"
    for i in "${!_RN_DEF_OLD[@]}"; do
      o="${_RN_DEF_OLD[$i]}"; nw="${_RN_DEF_NEW[$i]}"
      if [ "$new_target" = "$o" ]; then new_target="$nw"
      elif [[ "$new_target" == "${o}/"* ]]; then new_target="${nw}/${new_target#"${o}/"}"
      fi
    done
    if [ "$new_target" = "$old_target" ]; then out+=("$e"); continue; fi

    dirty=1
    if [ -f "$sc_file" ]; then
      tmp_file=$(mktemp) || { out+=("$e"); continue; }
      if sed "s|^SHORTCUT_TARGET=.*|SHORTCUT_TARGET=${new_target}|" "$sc_file" > "$tmp_file" \
         && mv -- "$tmp_file" "$sc_file"; then
        updated=$((updated + 1)); out+=("${sc_file}${_SCR_SEP}${new_target}")
      else
        rm -f "$tmp_file"; out+=("$e")
      fi
    fi
  done
  [ "$dirty" -eq 1 ] && _scr_save out
  _RN_DEF_OLD=(); _RN_DEF_NEW=()
  [ "$updated" -gt 0 ] && echo "📎 $updated shortcut(s) updated to reflect new paths."
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
#   2  real conflict — caller should print "already exists"
# ---------------------------------------------------------------------------
_do_rename_mv() {
  local old_path="$1"
  local new_path="$2"

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
      _sync_shortcuts_for_rename "$old_path" "$new_path"
      return 0
    else
      echo "❌ Case rename failed" >&2
      [ -e "$_tmp" ] && mv -- "$_tmp" "$old_path"   # best-effort rollback
      return 1
    fi
  fi

  if mv -- "$old_path" "$new_path"; then
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
    read -p "📝 Enter new folder name for '$(basename "$target")': " newname
  elif [ -f "$target" ]; then
    dir=$(dirname -- "$target")
    read -p "📝 Enter new file name for '$(basename "$target")': " newname
  else
    echo "❌ Cannot rename: '$target' not found." >&2
    return 1
  fi

  new_path="$dir/$newname"
  _do_rename_mv "$target" "$new_path"
  local rc=$?
  case $rc in
    0) echo "✅ Renamed: $(basename "$target") → $newname" ;;
    2) echo "⚠️  '$newname' already exists — skipped" ;;
  esac
  return $rc
}

# ---------------------------------------------------------------------------
# _rename_single_mutation
# Select items via the viewport multi-picker, then ask for a new name for each.
# Shortcut files get special handling (name-only, not the .shortcut pointer).
# ---------------------------------------------------------------------------
_rename_single_mutation() {
  select_items_common "RENAME" || return

  for item in "${selected_items[@]}"; do
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
      read -p "New display name (blank = cancel): " new_name
      [ -z "$new_name" ] && echo "🚫 Skipped" && continue

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
fi
echo "✅ Shortcut renamed: $cur_name → $new_name"
      continue
    fi

    echo "Current name: $bn"
    read -p "New name (blank = cancel): " new_name
    [ -z "$new_name" ] && echo "🚫 Skipped" && continue

    local new_path
    new_path="$(dirname "$item")/$new_name"
    _do_rename_mv "$item" "$new_path"
    local rc=$?
    case $rc in
      0) echo "✅ Renamed: $bn → $new_name" ;;
      2) echo "⚠️  '$new_name' already exists — skipped" ;;
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

  echo "✅ Renamed: ${ok}/${total} names   (counts written to $(basename "$csv_file"))"
  local i
  if [ ${#fail_names[@]} -gt 0 ]; then
    echo "⚠️  ${#fail_names[@]} failed:"
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
