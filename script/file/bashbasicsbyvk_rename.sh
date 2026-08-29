#!/usr/bin/env bash
# Rename handling — single mutation and multi mutation (CSV)
# Requires: bashbasicsbyvk_csv.sh (open_csv_menu)
#           select_items_common, _shortcut_read_field (from main / organise)

# ---------------------------------------------------------------------------
# rename_item <path>
# Low-level: prompts for a new name and mv's a single file or folder.
# Called by handle_file (run.sh option 7) as well as _rename_single_mutation.
# ---------------------------------------------------------------------------
rename_item() {
  local target="$1"
  local dir newname
  if [ -d "$target" ]; then
    dir=$(dirname -- "$target")
    read -p "📝 Enter new folder name for '$(basename "$target")': " newname
    mv -v "$target" "$dir/$newname"
  elif [ -f "$target" ]; then
    dir=$(dirname -- "$target")
    read -p "📝 Enter new file name for '$(basename "$target")': " newname
    mv -v "$target" "$dir/$newname"
  else
    echo "❌ Cannot rename: '$target' not found." >&2
    return 1
  fi
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
      [ "$new_sc_path" != "$item" ] && mv -- "$item" "$new_sc_path"
      echo "✅ Shortcut renamed: $cur_name → $new_name"
      continue
    fi

    echo "Current name: $bn"
    read -p "New name (blank = cancel): " new_name
    [ -z "$new_name" ] && echo "🚫 Skipped" && continue

    local new_path="$(dirname "$item")/$new_name"
    if [ -e "$new_path" ]; then
      echo "⚠️  '$new_name' already exists — skipped"
      continue
    fi
    mv -- "$item" "$new_path"
    echo "✅ Renamed: $bn → $new_name"
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

  echo ""
  echo "🔄 Processing renames from: $(basename "$csv_file")"

  local -a rn_old=() rn_new=() rn_counts=()

  # Parse CSV — col1=old_name, col2=new_name, skip blank/header rows
  while IFS=, read -r _old _new _rest || [ -n "$_old" ]; do
    _old="${_old#"${_old%%[![:space:]]*}"}"; _old="${_old%"${_old##*[![:space:]]}"}"
    _old="${_old%$'\r'}"
    _new="${_new#"${_new%%[![:space:]]*}"}"; _new="${_new%"${_new##*[![:space:]]}"}"
    _new="${_new%$'\r'}"
    [ -z "$_old" ] && continue
    rn_old+=("$_old")
    rn_new+=("$_new")
  done < "$csv_file"

  if [ ${#rn_old[@]} -eq 0 ]; then
    echo "❌ No valid rows found in CSV."
    return
  fi

  local abs_csv
  abs_csv=$(cd "$(dirname "$csv_file")" && pwd)/$(basename "$csv_file")

  echo "📋 Found ${#rn_old[@]} rename(s) to apply in: $path"
  echo ""

  for row_idx in "${!rn_old[@]}"; do
    local old_name="${rn_old[$row_idx]}"
    local new_name="${rn_new[$row_idx]}"

    # Find items in $path (maxdepth 1) whose basename matches exactly
    local -a matched=()
    while IFS= read -r -d '' _f; do
      [ "${_f##*/}" = "$old_name" ] && matched+=("$_f")
    done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

    if [ ${#matched[@]} -eq 0 ]; then
      echo "  Row $((row_idx+1)): \"$old_name\" → \"$new_name\"  ⚠️  Not found (0 matches)"
      rn_counts+=("0")
      continue
    fi

    local renamed=0
    for _f in "${matched[@]}"; do
      local _dir="${_f%/*}"
      local _new_path="$_dir/$new_name"
      if [ -e "$_new_path" ] && [ "$_new_path" != "$_f" ]; then
        echo "  Row $((row_idx+1)): \"$old_name\" → \"$new_name\"  ⚠️  Target already exists — skipped"
        continue
      fi
      mv -- "$_f" "$_new_path" && renamed=$((renamed + 1))
    done
    echo "  Row $((row_idx+1)): \"$old_name\" → \"$new_name\"  ✅ $renamed renamed"
    rn_counts+=("$renamed")
  done

  # Write counts back to col3 of the CSV
  echo ""
  echo "📝 Writing rename counts back to CSV..."
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

  echo "✅ CSV updated with rename counts: $(basename "$csv_file")"
  echo ""
  echo "🎉 Multi Mutation rename complete — ${#rn_old[@]} pattern(s) processed."
}

# ---------------------------------------------------------------------------
# handle_rename  (main menu: r)
# Top-level entry point — presents the Single / Multi Mutation choice,
# then delegates. Replaces the old handle_rename in both `o` and run.sh.
# ---------------------------------------------------------------------------
handle_rename() {
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items to rename"
    return
  fi

  echo ""
  echo "🔤 Rename"
  echo "1) Single Mutation"
  echo "2) Multi Mutation (CSV)"
  read -p "Mode [1-2]: " _ren_mode

  case "$_ren_mode" in
    1) _rename_single_mutation ;;
    2) _rename_multi_mutation  ;;
    *) echo "❌ Invalid mode." ;;
  esac
}
