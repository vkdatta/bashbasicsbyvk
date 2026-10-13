#!/usr/bin/env bash
# bashbasicsbyvk_carry.sh — "carry" what is attached to a path when the path changes
# ════════════════════════════════════════════════════════════════════════════
#  Locks (l-N) and shortcuts both hang off a path, so EVERY feature that moves,
#  copies, renames or deletes an item must tell them. They all do it here, once:
#
#    _carry_move   old new     renamed / moved   → lock follows; shortcuts to it
#                                                  re-point; shortcut files that
#                                                  moved keep being tracked
#    _carry_copy   old new     copied            → the copy is locked too; copied
#                                                  .shortcut files are indexed
#    _carry_forget path        deleted           → lock + shortcut index rows dropped
#    _carry_begin / _carry_end bracket a loop of moves: shortcuts are re-synced in ONE pass
#    _carry_move_batch dest src...      after a bulk `mv`
#    _carry_apply_mv_log file           "old<TAB>new" lines from a helper script
#    _carry_flatten_into dest root N    unorganise (files below root → dest)
#
#  Used by: rename, c-/m-/transfer menu, organise (z), unorganise, find & replace
#  renames, .r rule rename, and every delete path.
#  Needs: bashbasicsbyvk_lock.sh, shortcut registry, rename.sh (_rn_* / _sync_shortcuts_for_rename)
# ════════════════════════════════════════════════════════════════════════════

_carry_begin() { _lk_load; _rn_defer_begin; }
_carry_end()   { _rn_flush_deferred; }

_carry_move() {                    # <old> <new>
  _lk_move "$1" "$2"
  _sync_shortcuts_for_rename "$1" "$2"
}

_carry_copy() {                    # <old> <new>
  _lk_copy "$1" "$2"
  _scr_add_tree "$2"
}

_carry_forget() {                  # <deleted path>
  _lk_forget "$1"
  _scr_forget_under "$1"
}

_carry_move_batch() {              # <dest-dir> <src>...
  local dest="$1" f; shift
  _carry_begin
  for f in "$@"; do
    [ -e "$f" ] || [ -L "$f" ] && continue
    [ -e "$dest/${f##*/}" ] || [ -L "$dest/${f##*/}" ] || continue
    _carry_move "$f" "$dest/${f##*/}"
  done
  _carry_end
}

_carry_apply_mv_log() {            # <file>
  local a b
  [ -s "$1" ] || { rm -f -- "$1"; return 0; }
  _carry_begin
  while IFS=$'\t' read -r a b; do
    [ -n "$a" ] && [ -n "$b" ] && _carry_move "$a" "$b"
  done < "$1"
  _carry_end
  rm -f -- "$1"
}

# _carry_flatten_into <dest> <root> <mindepth>
# Moves every file below <root> (depth >= mindepth) into <dest>, carrying locks and
# shortcuts, then removes the folders that became empty (a locked empty folder stays).
_carry_flatten_into() {
  local dest="$1" root="$2" mind="${3:-1}" f tgt
  local -a src=() move=()
  _carry_begin
  while IFS= read -r -d '' f; do src+=("$f"); done < <(find "$root" -mindepth "$mind" -type f -print0 2>/dev/null)
  for f in "${src[@]}"; do
    tgt="$dest/${f##*/}"
    if { [ -e "$tgt" ] || [ -L "$tgt" ]; } && _lk_is_protected "$tgt"; then
      echo "  🔒 Kept in place (a locked item of that name is in the destination): $f"
      continue
    fi
    move+=("$f")
  done
  if [ "${#move[@]}" -gt 0 ]; then
    printf '%s\0' "${move[@]}" | xargs -0 mv -t "$dest/" --
    for f in "${move[@]}"; do
      [ -e "$f" ] || [ -L "$f" ] || { [ -e "$dest/${f##*/}" ] && _carry_move "$f" "$dest/${f##*/}"; }
    done
  fi
  _carry_end
  _lk_rmdir_empty "$root"
  if [ "$root" != "$dest" ] && [ -d "$root" ] && ! _lk_is_protected "$root"; then rmdir -- "$root" 2>/dev/null && _carry_forget "$root"; fi
  return 0
}
