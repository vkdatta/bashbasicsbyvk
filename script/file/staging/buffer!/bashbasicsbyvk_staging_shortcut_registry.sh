#!/usr/bin/env bash
# bashbasicsbyvk_staging_shortcut_registry.sh
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
  local -a _po=("$1") _pn=("$2")
  _scr_sync_pairs _po _pn
}

# _scr_map <path> <old> <new>  → _scr_mp  (old→new for the path itself or anything below it; no forks)
_scr_mp=""
_scr_map() {
  _scr_mp="$1"
  if [ "$1" = "$2" ]; then _scr_mp="$3"
  elif [[ "$1" == "$2/"* ]]; then _scr_mp="$3/${1#"$2/"}"
  fi
}

# ---------------------------------------------------------------------------
# _scr_sync_pairs <olds-array> <news-array>
# THE shortcut carry engine. Replays path changes (old[i] → new[i], in order) over
# the whole registry in ONE pass. For every shortcut it carries BOTH
#   • its TARGET   (the item it points to moved/renamed → SHORTCUT_TARGET rewritten)
#   • its OWN PATH (the .shortcut file, or a folder holding it, moved/renamed →
#                   registry row follows)
# Used by rename, move, organise / unorganise, find-and-replace renames, ...
# ---------------------------------------------------------------------------
_scr_sync_pairs() {
  local -n _spo="$1" _spn="$2"
  [ "${#_spo[@]}" -gt 0 ] || return 0
  [ -f "$_SCR_FILE" ] || return 0

  local -a entries=() out=()
  _scr_load entries
  local e sc target new_sc new_t i tmp esc updated=0 dirty=0
  for e in "${entries[@]}"; do
    sc="${e%%${_SCR_SEP}*}"; target="${e#*${_SCR_SEP}}"
    new_sc="$sc"; new_t="$target"
    for i in "${!_spo[@]}"; do
      _scr_map "$new_sc" "${_spo[$i]}" "${_spn[$i]}"; new_sc="$_scr_mp"
      _scr_map "$new_t"  "${_spo[$i]}" "${_spn[$i]}"; new_t="$_scr_mp"
    done
    if [ "$new_sc" = "$sc" ] && [ "$new_t" = "$target" ]; then out+=("$e"); continue; fi
    dirty=1
    if [ ! -f "$new_sc" ]; then continue; fi          # shortcut file is gone — lazy cleanup
    if [ "$new_t" != "$target" ]; then
      esc="${new_t//\\/\\\\}"; esc="${esc//&/\\&}"; esc="${esc//|/\\|}"
      tmp=$(mktemp) || { out+=("${new_sc}${_SCR_SEP}${target}"); continue; }
      if sed "s|^SHORTCUT_TARGET=.*|SHORTCUT_TARGET=${esc}|" "$new_sc" > "$tmp" && mv -- "$tmp" "$new_sc"; then
        updated=$((updated + 1))
        [ "${#_spo[@]}" -eq 1 ] && echo "  🔗 Shortcut synced: ${new_sc##*/} → $new_t"
      else
        rm -f "$tmp"; new_t="$target"
      fi
    fi
    out+=("${new_sc}${_SCR_SEP}${new_t}")
  done
  [ "$dirty" -eq 1 ] && _scr_save out
  [ "$updated" -gt 0 ] && echo "  📎 $updated shortcut(s) updated to reflect the new path(s)."
  return 0
}

# _scr_forget_under <path> — drop registry rows of shortcut files at/below a deleted path
_scr_forget_under() {
  [ -f "$_SCR_FILE" ] || return 0
  local -a entries=() kept=(); _scr_load entries
  local e sc dirty=0
  for e in "${entries[@]}"; do
    sc="${e%%${_SCR_SEP}*}"
    if [ "$sc" = "$1" ] || [[ "$sc" == "$1/"* ]]; then dirty=1; else kept+=("$e"); fi
  done
  [ "$dirty" -eq 1 ] && _scr_save kept
  return 0
}

# _scr_add_tree <path> — register every .shortcut at/below path (a copy of a shortcut / of a folder of shortcuts)
_scr_add_tree() {
  local p="$1" sc t
  local -a fresh=() entries=() kept=() files=()
  if [ -f "$p" ] && [[ "$p" == *.shortcut ]]; then files=("$p")
  elif [ -d "$p" ]; then
    while IFS= read -r -d '' sc; do files+=("$sc"); done < <(find "$p" -type f -name '*.shortcut' -print0 2>/dev/null)
  fi
  [ "${#files[@]}" -gt 0 ] || return 0
  _scr_ensure; _scr_load entries
  local -A _is=(); for sc in "${files[@]}"; do _is["$sc"]=1; done
  local e
  for e in "${entries[@]}"; do [ -n "${_is[${e%%${_SCR_SEP}*}]+x}" ] || kept+=("$e"); done
  for sc in "${files[@]}"; do
    t=$(_shortcut_read_field "$sc" "SHORTCUT_TARGET"); [ -n "$t" ] && kept+=("${sc}${_SCR_SEP}${t}")
  done
  _scr_save kept
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

  read -e -p "Remove stale entries from registry? (y/n): " confirm
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
  _mc_menu "🗂️  Shortcut Registry" -- "Show registry contents" "Validate (find & remove stale entries)" \
    "Full rebuild (rescan \$HOME — slow, use when in doubt)" -- @back_quit
  read -e -p "Select: " _scr_choice

  case "$_scr_choice" in
  u|U) return ;;
  q|Q) _bvk_quit; return 1 ;;
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
      read -e -p "Full rebuild will rescan all of \$HOME. Continue? (y/n): " confirm
      [[ "$confirm" == "y" || "$confirm" == "Y" ]] && _scr_rebuild || echo "🚫 Cancelled."
      ;;
    q|Q|"") return 0 ;;
    *) _bvk_invalid ;;
  esac
}
