#!/usr/bin/env bash
# bashbasicsbyvk_lock.sh — l-N / ul-N : lock files & folders against deletion
# ════════════════════════════════════════════════════════════════════════════
#  l-N    lock item(s) N      (N = 3 · 1,3,5 · 2-6 · a · a-1,2 — same grammar as z- / c-)
#  ul-N   unlock item(s) N
#
#  • A lock only stops deletion INSIDE this app (d, delete.* in fx, the file
#    menu's "Delete File", .r ...). It does not touch file permissions.
#  • Locked items show a 🔒 suffix in the listing. Unlock says "🔐 unlocked" in
#    the message only — the name never carries that icon.
#  • Locking a FOLDER locks that folder only; its children can still be deleted
#    freely. The other way round matters too: deleting a folder that CONTAINS a
#    locked item would destroy that item, so such a folder goes through the
#    locked-item confirmation as well.
#
#  Deleting a locked item:
#    one item     normal y/n → then a warning + the 6-digit action key
#    several      normal y/n (+ notice) → 1) don't delete locked items
#                                         2) delete locked items
#                 → y/n again → (choice 2 only) the 6-digit action key
#
#  Registry: ~/.bashbasicsbyvk/locks.list  (one absolute path per line)
#  Needs:    _sp_resolve_itemlist (staging helpers), bashbasicsbyvk_action_confirm_key.sh
# ════════════════════════════════════════════════════════════════════════════


_LK_DIR="${HOME}/.bashbasicsbyvk"
_LK_FILE="${_LK_DIR}/locks.list"
declare -gA _LK_SET=()
_lk_n=""            # result of _lk_norm
_lk_inside=0        # result of _lk_count_inside
_lk_suffix=""       # result of _lk_suffix_v

# ── registry ────────────────────────────────────────────────────────────────
_lk_load() {
  _LK_SET=()
  [ -r "$_LK_FILE" ] || return 0
  local p
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] && _LK_SET["$p"]=1
  done < "$_LK_FILE"
}

_lk_save() {
  mkdir -p "$_LK_DIR" 2>/dev/null || return 1
  local tmp="${_LK_FILE}.$$" k
  { for k in "${!_LK_SET[@]}"; do printf '%s\n' "$k"; done | LC_ALL=C sort; } > "$tmp" 2>/dev/null \
    && mv -f -- "$tmp" "$_LK_FILE" || { rm -f -- "$tmp"; return 1; }
}

# absolute path, no trailing slash, no "//"  (pure bash, no forks)
_lk_norm() {
  local p="$1"
  [[ "$p" != /* ]] && p="$PWD/$p"
  while [[ "$p" == *//* ]]; do p="${p//\/\//\/}"; done
  [ "$p" != "/" ] && p="${p%/}"
  _lk_n="$p"
}

_lk_is_locked() {            # the item itself is locked
  _lk_norm "$1"
  [ -n "${_LK_SET[$_lk_n]+x}" ]
}

_lk_count_inside() {         # number of locked items below folder $1  → _lk_inside
  _lk_inside=0
  [ -d "$1" ] || return 0
  _lk_norm "$1"
  local pre="$_lk_n/" k
  [ "$_lk_n" = "/" ] && pre="/"
  for k in "${!_LK_SET[@]}"; do
    [[ "$k" == "$pre"* && "$k" != "$_lk_n" ]] && _lk_inside=$((_lk_inside+1))
  done
  return 0
}

_lk_is_protected() {         # locked itself, or a folder holding a locked item
  _lk_is_locked "$1" && return 0
  _lk_count_inside "$1"
  [ "$_lk_inside" -gt 0 ]
}

# listing hook: " 🔒" for a locked item, "" otherwise (never 🔐)
_lk_suffix_v() {
  _lk_suffix=""
  [ "${#_LK_SET[@]}" -eq 0 ] && return 0
  _lk_is_locked "$1" && _lk_suffix=" 🔒"
  return 0
}

_lk_forget() {               # drop locks of a deleted item and everything below it
  _lk_norm "$1"
  local pre="$_lk_n/" k changed=false
  for k in "${!_LK_SET[@]}"; do
    if [ "$k" = "$_lk_n" ] || [[ "$k" == "$pre"* ]]; then unset "_LK_SET[$k]"; changed=true; fi
  done
  $changed && _lk_save
  return 0
}

_lk_move() {                 # keep locks when an item is renamed / moved
  [ "${#_LK_SET[@]}" -eq 0 ] && return 0
  _lk_norm "$1"; local old="$_lk_n"; _lk_norm "$2"; local new="$_lk_n"
  local pre="$old/" k changed=false
  local -a add=() del=()
  for k in "${!_LK_SET[@]}"; do
    if [ "$k" = "$old" ]; then del+=("$k"); add+=("$new")
    elif [[ "$k" == "$pre"* ]]; then del+=("$k"); add+=("$new/${k#"$pre"}"); fi
  done
  for k in "${del[@]}"; do unset "_LK_SET[$k]"; changed=true; done
  for k in "${add[@]}"; do _LK_SET["$k"]=1; done
  $changed && _lk_save
  return 0
}

# ── l-N / ul-N ──────────────────────────────────────────────────────────────
# _lk_cmd lock|unlock <l-N | ul-N>   — resolves N against items[] like z- / c-
_lk_cmd() {
  local mode="$1" raw="$2" itemlist="${2#*-}"
  local verb="l-N"; [ "$mode" = unlock ] && verb="ul-N"
  if [ -z "$itemlist" ] || [ "$itemlist" = "$raw" ]; then
    echo "🔴  Usage: $verb   e.g. ${verb/N/1}  ${verb/N/1,3}  ${verb/N/2-5}  ${verb/N/a}"
    return 1
  fi
  if ${imaginary_mode:-false}; then
    echo "🔴  Too many items to index directly — narrow the view before using $verb."
    return 1
  fi
  _sp_resolve_itemlist "$itemlist" || return 1
  _lk_load

  local p name changed=false
  local -a done_names=() skipped=()
  for p in "${sp_resolved[@]}"; do
    name="${p##*/}"
    _lk_norm "$p"
    if [ "$mode" = lock ]; then
      if [ -n "${_LK_SET[$_lk_n]+x}" ]; then skipped+=("$name")
      else _LK_SET["$_lk_n"]=1; done_names+=("$name"); changed=true; fi
    else
      if [ -n "${_LK_SET[$_lk_n]+x}" ]; then unset "_LK_SET[$_lk_n]"; done_names+=("$name"); changed=true
      else skipped+=("$name"); fi
    fi
  done
  if $changed && ! _lk_save; then
    echo "❌ Could not write $_LK_FILE"; _lk_load; return 1
  fi

  local n=${#done_names[@]} s=${#skipped[@]}
  if [ "$mode" = lock ]; then
    if   [ "$n" -eq 1 ]; then echo "🔒 Locked: ${done_names[0]}  (can't be deleted from this app until ul-N)"
    elif [ "$n" -gt 1 ]; then echo "🔒 Locked $n items: $(_lk_join "${done_names[@]}")"; fi
    [ "$s" -gt 0 ] && echo "📜  Already locked: $(_lk_join "${skipped[@]}")"
  else
    if   [ "$n" -eq 1 ]; then echo "🔐 unlocked: ${done_names[0]}"
    elif [ "$n" -gt 1 ]; then echo "🔐 unlocked $n items: $(_lk_join "${done_names[@]}")"; fi
    [ "$s" -gt 0 ] && echo "📜  Not locked: $(_lk_join "${skipped[@]}")"
  fi
  return 0
}
handle_lock_items()   { _lk_cmd lock   "$1"; }
handle_unlock_items() { _lk_cmd unlock "$1"; }

_lk_join() {                 # "a, b, c, … (+N more)"  (max 8 names)
  local max=8 out="" i=0 x
  for x in "$@"; do
    i=$((i+1))
    [ "$i" -gt "$max" ] && break
    out+="${out:+, }$x"
  done
  [ "$#" -gt "$max" ] && out+=", … (+$(($# - max)) more)"
  printf '%s' "$out"
}

# ── the delete gate ─────────────────────────────────────────────────────────
# _lk_confirm_delete "<normal first prompt, ending in (y/n): >"
#   Works on the global selected_items[].
#   0 → go ahead and delete selected_items (it may have been reduced)
#   1 → cancelled / nothing left   (message already printed)
# With no locked item in the selection this is exactly the old single y/n.
_lk_confirm_delete() {
  local prompt="$1" ans
  _lk_load

  local -a prot=() free=()
  local it
  for it in "${selected_items[@]}"; do
    if _lk_is_protected "$it"; then prot+=("$it"); else free+=("$it"); fi
  done

  if [ "${#prot[@]}" -eq 0 ]; then
    _bvk_yn ans "${prompt% (y/n): }" -d none -t "Confirm delete" -i "🗑️"
    [[ "$ans" == [yY] ]] || { echo "🚫 Deletion cancelled"; return 1; }
    return 0
  fi

  # ── exactly one item selected, and it is locked ──
  if [ "${#selected_items[@]}" -eq 1 ]; then
    it="${selected_items[0]}"
    _bvk_yn ans "${prompt% (y/n): }" -d none -t "Confirm delete" -i "🗑️"
    [[ "$ans" == [yY] ]] || { echo "🚫 Deletion cancelled"; return 1; }
    local -a detail=()
    if _lk_is_locked "$it"; then
      detail+=("🔒 You selected a LOCKED $( [ -d "$it" ] && echo folder || echo file ): ${it##*/}")
    else
      _lk_count_inside "$it"
      detail+=("🔒 This folder holds $_lk_inside locked item(s): ${it##*/}")
    fi
    detail+=("Deleting it will erase its content PERMANENTLY if a backup has not been taken.")
    action_confirm_key "LOCKED ITEM — confirmation required" "${detail[@]}" \
      || { echo "🚫 Deletion cancelled — locked item kept"; return 1; }
    return 0
  fi

  # ── several items, some of them locked ──
  echo "🔒 ${#prot[@]} of ${#selected_items[@]} selected item(s) are locked (or hold locked items) — this might not be what you intended:"
  for it in "${prot[@]}"; do
    if _lk_is_locked "$it"; then echo "   🔒 ${it##*/}"
    else _lk_count_inside "$it"; echo "   🔒 ${it##*/}  (contains $_lk_inside locked item(s))"; fi
  done
  _bvk_yn ans "${prompt% (y/n): }" -d none -t "Confirm delete" -i "🗑️"
  [[ "$ans" == [yY] ]] || { echo "🚫 Deletion cancelled"; return 1; }

  echo
  _bvk_menu ans -q "What should happen to the locked items?" -t "Locked items" -i "🔒" "1:Don't delete locked items" "2:Delete locked items"
  local choice
  case "$ans" in
    1) choice=skip ;;
    2) choice=all ;;
    *) echo "🚫 Deletion cancelled"; return 1 ;;
  esac

  local -a final=()
  if [ "$choice" = skip ]; then
    final=("${free[@]}")
    if [ "${#final[@]}" -eq 0 ]; then echo "📜  Everything selected is locked — nothing to delete"; return 1; fi
    _bvk_yn ans "Delete ${#final[@]} unlocked item(s), keeping ${#prot[@]} locked?" -d none
  else
    final=("${selected_items[@]}")
    _bvk_yn ans "Delete ALL ${#final[@]} item(s), including ${#prot[@]} locked?" -d none
  fi
  [[ "$ans" == [yY] ]] || { echo "🚫 Deletion cancelled"; return 1; }

  if [ "$choice" = all ]; then
    action_confirm_key "LOCKED ITEMS — confirmation required" \
      "🔒 ${#prot[@]} locked item(s) will be deleted: $(_lk_join "${prot[@]##*/}")" \
      "This will erase their content PERMANENTLY if a backup has not been taken." \
      || { echo "🚫 Deletion cancelled — nothing was deleted"; return 1; }
  fi
  selected_items=("${final[@]}")
  return 0
}

# lock / unlock ONE path (the rloop file menu: "Lock File" / "Unlock File")
_lk_file_cmd() {             # _lk_file_cmd lock|unlock <path>
  local mode="$1" f="$2" name="${2##*/}"
  [ -e "$f" ] || [ -L "$f" ] || { echo "❌ Not found: $f"; return 1; }
  _lk_load; _lk_norm "$f"
  if [ "$mode" = lock ]; then
    if [ -n "${_LK_SET[$_lk_n]+x}" ]; then echo "📜  Already locked: $name"; return 0; fi
    _LK_SET["$_lk_n"]=1
    _lk_save && echo "🔒 Locked: $name  (can't be deleted from this app until unlocked)" || echo "❌ Could not write $_LK_FILE"
  else
    if [ -z "${_LK_SET[$_lk_n]+x}" ]; then echo "📜  Not locked: $name"; return 0; fi
    unset "_LK_SET[$_lk_n]"
    _lk_save && echo "🔐 unlocked: $name" || echo "❌ Could not write $_LK_FILE"
  fi
}

# the file menu's single "Lock / Unlock" row: _lk_file_locked <path> says which one it is, _lk_file_toggle does it
_lk_file_locked() { _lk_load; _lk_is_locked "$1"; }
_lk_file_toggle() {
  if _lk_file_locked "$1"; then _lk_file_cmd unlock "$1"; else _lk_file_cmd lock "$1"; fi
}

# ── move / copy keep the lock (same rule as rename) ─────────────────────────
# Callers run _lk_load once first.

# _lk_copy <old> <new> — the copy is locked too (and so is every locked item inside it)
_lk_copy() {
  [ "${#_LK_SET[@]}" -eq 0 ] && return 0
  _lk_norm "$1"; local old="$_lk_n"; _lk_norm "$2"; local new="$_lk_n"
  local pre="$old/" k changed=false
  local -a add=()
  for k in "${!_LK_SET[@]}"; do
    if [ "$k" = "$old" ]; then add+=("$new")
    elif [[ "$k" == "$pre"* ]]; then add+=("$new/${k#"$pre"}"); fi
  done
  for k in "${add[@]}"; do _LK_SET["$k"]=1; changed=true; done
  $changed && _lk_save
  return 0
}

# _lk_move_batch <dest-dir> <src>... — after a bulk `mv`: every source that is gone
# and now sits in dest-dir takes its lock along.
_lk_move_batch() {
  local dest="$1" f; shift
  [ "${#_LK_SET[@]}" -eq 0 ] && return 0
  for f in "$@"; do
    [ -e "$f" ] || [ -L "$f" ] && continue
    [ -e "$dest/${f##*/}" ] || [ -L "$dest/${f##*/}" ] || continue
    _lk_move "$f" "$dest/${f##*/}"
  done
}

# _lk_keys_under <dir> — snapshot (→ _lk_keys[]) of locked paths below dir, taken BEFORE a bulk move
_lk_keys_under() {
  _lk_keys=()
  _lk_norm "$1"
  local pre="$_lk_n/" k
  [ "$_lk_n" = "/" ] && pre="/"
  for k in "${!_LK_SET[@]}"; do [[ "$k" == "$pre"* ]] && _lk_keys+=("$k"); done
  return 0
}

# _lk_apply_mv_log <file> — lines "old<TAB>new" written by a helper script that renamed files
_lk_apply_mv_log() {
  local a b
  [ -s "$1" ] || return 0
  _lk_load
  while IFS=$'\t' read -r a b; do
    [ -n "$a" ] && [ -n "$b" ] && _lk_move "$a" "$b"
  done < "$1"
  rm -f -- "$1"
}

# _lk_rmdir_empty <root> — like `find root -mindepth 1 -type d -empty -delete`,
# but a locked (empty) folder is kept.
_lk_rmdir_empty() {
  local root="$1" d changed=true
  _lk_load
  while $changed; do
    changed=false
    while IFS= read -r -d '' d; do
      _lk_is_protected "$d" && continue
      rmdir -- "$d" 2>/dev/null && { _lk_forget "$d"; changed=true; }
    done < <(find "$root" -mindepth 1 -type d -empty -print0 2>/dev/null)
  done
}
