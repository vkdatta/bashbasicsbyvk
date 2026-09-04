#!/usr/bin/env bash
# bashbasicsbyvk_shortcut_registry.sh
#
# Central index for all .shortcut files — eliminates the recursive find
# in _sync_shortcuts_for_rename. The rename sync becomes an O(shortcuts)
# index lookup instead of an O(all files in $HOME) filesystem walk.
#
# Registry file: ~/.bashbasicsbyvk/shortcut.registry
# Format (pipe-delimited, one entry per line):
#   <abs_path_to_.shortcut_file>|<abs_target_path>
#
# Rules:
#   • Created  → _scr_add    (called from perform_shortcut or wherever
#                              .shortcut files are written)
#   • Deleted  → _scr_remove (called when a .shortcut file is removed)
#   • Renamed  → _scr_rename_sync  (replaces _sync_shortcuts_for_rename)
#   • Drift    → _scr_rebuild (on-demand full rescan, called by `scr-sync`)
#
# Requires: _shortcut_read_field  (defined in main / organise)
# ---------------------------------------------------------------------------

_SCR_DIR="${HOME}/.bashbasicsbyvk"
_SCR_FILE="${_SCR_DIR}/shortcut.registry"
_SCR_SEP="|"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_scr_ensure() {
  mkdir -p "$_SCR_DIR" 2>/dev/null
  [ -f "$_SCR_FILE" ] || : > "$_SCR_FILE"
}

# _scr_load <nameref-array>
# Reads the registry into an array of "sc_file|target" strings.
_scr_load() {
  local -n __scr_arr="$1"
  __scr_arr=()
  [ -f "$_SCR_FILE" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] && __scr_arr+=("$line")
  done < "$_SCR_FILE"
}

# _scr_save <nameref-array>
_scr_save() {
  local -n __scr_in="$1"
  : > "$_SCR_FILE"
  local entry
  for entry in "${__scr_in[@]}"; do
    [ -n "$entry" ] && printf '%s\n' "$entry" >> "$_SCR_FILE"
  done
}

# ---------------------------------------------------------------------------
# _scr_add <abs_shortcut_file_path>
# Register a newly created .shortcut file. Reads its SHORTCUT_TARGET field.
# Safe to call multiple times — deduplicates on sc_file path.
# ---------------------------------------------------------------------------
_scr_add() {
  local sc_file="$1"
  local target
  target=$(_shortcut_read_field "$sc_file" "SHORTCUT_TARGET")
  [ -z "$target" ] && return 0   # not a recognised shortcut file, skip

  _scr_ensure

  local -a entries=()
  _scr_load entries

  # Deduplicate: remove any stale entry for this sc_file first
  local -a fresh=()
  local e
  for e in "${entries[@]}"; do
    [[ "${e%%${_SCR_SEP}*}" != "$sc_file" ]] && fresh+=("$e")
  done

  fresh+=("${sc_file}${_SCR_SEP}${target}")
  _scr_save fresh
}

# ---------------------------------------------------------------------------
# _scr_remove <abs_shortcut_file_path>
# Unregister a .shortcut file (called on deletion).
# ---------------------------------------------------------------------------
_scr_remove() {
  local sc_file="$1"
  [ -f "$_SCR_FILE" ] || return 0

  local -a entries=() kept=()
  _scr_load entries
  local e
  for e in "${entries[@]}"; do
    [[ "${e%%${_SCR_SEP}*}" != "$sc_file" ]] && kept+=("$e")
  done
  _scr_save kept
}

# ---------------------------------------------------------------------------
# _scr_rename_sync <old_abs_path> <new_abs_path>
# Drop-in replacement for the old _sync_shortcuts_for_rename.
#
# Updates every registry entry whose SHORTCUT_TARGET equals old_abs_path
# (exact match) or starts with old_abs_path/ (sub-path inside a renamed dir).
# Also rewrites the SHORTCUT_TARGET field inside the .shortcut file itself,
# and updates the registry row — all without touching the filesystem beyond
# those specific files.
# ---------------------------------------------------------------------------
_scr_rename_sync() {
  local old_path="$1"
  local new_path="$2"

  [ -f "$_SCR_FILE" ] || return 0

  local -a entries=() updated_entries=()
  _scr_load entries

  local updated=0
  local e sc_file old_target new_target tmp_file
  for e in "${entries[@]}"; do
    sc_file="${e%%${_SCR_SEP}*}"
    old_target="${e#*${_SCR_SEP}}"

    new_target=""
    if [ "$old_target" = "$old_path" ]; then
      new_target="$new_path"
    elif [[ "$old_target" == "${old_path}/"* ]]; then
      new_target="${new_path}/${old_target#"${old_path}/"}"
    fi

    if [ -n "$new_target" ]; then
      if [ -f "$sc_file" ]; then
        tmp_file=$(mktemp) || { updated_entries+=("$e"); continue; }
        if sed "s|^SHORTCUT_TARGET=.*|SHORTCUT_TARGET=${new_target}|" \
               "$sc_file" > "$tmp_file" \
           && mv -- "$tmp_file" "$sc_file"; then
          updated=$((updated + 1))
          echo "  🔗 Shortcut synced: $(basename "$sc_file") → $new_target"
          updated_entries+=("${sc_file}${_SCR_SEP}${new_target}")
        else
          rm -f "$tmp_file"
          updated_entries+=("$e")   # keep old entry; rewrite failed
        fi
      else
        # .shortcut file is gone — drop this entry (lazy cleanup)
        : # intentionally omit from updated_entries
      fi
    else
      updated_entries+=("$e")
    fi
  done

  _scr_save updated_entries
  [ "$updated" -gt 0 ] && echo "  📎 $updated shortcut(s) updated to reflect new path."
  return 0
}

# ---------------------------------------------------------------------------
# _scr_rebuild
# Full rescan of $HOME for *.shortcut files — rebuilds the registry from
# scratch. Use when the index may have drifted (manual rm, external tools).
# Exposed as the `scr-sync` user command (see handle_scr_sync below).
# ---------------------------------------------------------------------------
_scr_rebuild() {
  _scr_ensure
  local -a fresh=()
  local sc_file target

  echo "🔍 Scanning for .shortcut files under $HOME …"
  while IFS= read -r -d '' sc_file; do
    target=$(_shortcut_read_field "$sc_file" "SHORTCUT_TARGET")
    [ -n "$target" ] && fresh+=("${sc_file}${_SCR_SEP}${target}")
  done < <(find "$HOME" -name "*.shortcut" -print0 2>/dev/null)

  _scr_save fresh
  echo "✅ Registry rebuilt — ${#fresh[@]} shortcut(s) indexed."
}

# ---------------------------------------------------------------------------
# _scr_validate
# Lazy-validate the registry: report and optionally prune entries whose
# .shortcut file no longer exists on disk.
# ---------------------------------------------------------------------------
_scr_validate() {
  [ -f "$_SCR_FILE" ] || { echo "ℹ️  Registry does not exist yet."; return 0; }

  local -a entries=() kept=() stale=()
  _scr_load entries

  local e sc_file
  for e in "${entries[@]}"; do
    sc_file="${e%%${_SCR_SEP}*}"
    if [ -f "$sc_file" ]; then
      kept+=("$e")
    else
      stale+=("$sc_file")
    fi
  done

  if [ ${#stale[@]} -eq 0 ]; then
    echo "✅ Registry is clean — ${#kept[@]} entry/entries, none stale."
    return 0
  fi

  echo "⚠️  ${#stale[@]} stale entry/entries found:"
  local sf
  for sf in "${stale[@]}"; do
    echo "   • $sf"
  done

  read -p "Remove stale entries from registry? (y/n): " confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    _scr_save kept
    echo "🗑️  Removed ${#stale[@]} stale entry/entries. Registry now holds ${#kept[@]}."
  else
    echo "🚫 No changes made."
  fi
}

# ---------------------------------------------------------------------------
# handle_scr_sync   (wire this to a menu option, e.g. "scr-sync" or option 9)
# User-facing entry point for registry maintenance.
# ---------------------------------------------------------------------------
handle_scr_sync() {
  echo ""
  echo "🗂️  Shortcut Registry"
  echo "  1) Show registry contents"
  echo "  2) Validate (find & remove stale entries)"
  echo "  3) Full rebuild (rescan \$HOME — slow, use when in doubt)"
  echo "  q) Back"
  read -p "Choice: " _scr_choice

  case "$_scr_choice" in
    1)
      _scr_ensure
      local -a entries=()
      _scr_load entries
      if [ ${#entries[@]} -eq 0 ]; then
        echo "ℹ️  Registry is empty."
      else
        echo ""
        echo "📋 ${#entries[@]} registered shortcut(s):"
        local i=1 e sc_file target
        for e in "${entries[@]}"; do
          sc_file="${e%%${_SCR_SEP}*}"
          target="${e#*${_SCR_SEP}}"
          local exists_tag=""
          [ ! -f "$sc_file" ] && exists_tag="  ⚠️ missing"
          printf "  %3d) %s%s\n       → %s\n" "$i" "$(basename "$sc_file")" "$exists_tag" "$target"
          i=$((i + 1))
        done
      fi
      ;;
    2) _scr_validate ;;
    3)
      read -p "Full rebuild will rescan all of \$HOME. Continue? (y/n): " confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] && _scr_rebuild || echo "🚫 Cancelled."
      ;;
    q|Q|"") return 0 ;;
    *) echo "⚠️  Invalid choice." ;;
  esac
}
