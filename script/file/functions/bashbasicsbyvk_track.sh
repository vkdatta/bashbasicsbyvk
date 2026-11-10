#!/usr/bin/env bash
# bashbasicsbyvk_track.sh — what the app remembers ABOUT a path: Bookmark pointers and Recents
# ════════════════════════════════════════════════════════════════════════════
#  BOOKMARKS  ~/.bashbasicsbyvk/switch/<name>.swlink     (the suffix is internal: it is never shown)
#      SWLINK_TARGET=/abs/path   what the bookmark points to (a folder OR a file)
#      SWLINK_NAME=name
#      SWLINK_CREATED=epoch
#      SWLINK_ID=dev:inode       lets the bookmark find its target again after a move the app did not see
#
#  RECENTS    ~/.bashbasicsbyvk/recents.tsv               newest first, one line  COUNT<TAB>/abs/path
#      A folder joins when it is entered with the in-app  cd  command.
#      A file joins when the run loop edits it (Edit, Erase, Replace, Rename).
#      Nothing else joins. Opened more than _RC_AUTOLOCK_AFTER times = important = locked automatically.
#
#  Moves, renames and deletes reach both through _trk_move / _trk_forget (called by the carry helpers, bashbasicsbyvk_carry.sh).
#  The local daemon does the same for changes made OUTSIDE the app (bashbasicsbyvk_track_lib.py is its twin: same formats).
#  Needs: bashbasicsbyvk_lock.sh (_lk_norm, _lk_load, _lk_save)
# ════════════════════════════════════════════════════════════════════════════

_TRK_HOME="${HOME}/.bashbasicsbyvk"
_SW_DIR="${_TRK_HOME}/switch"
_RC_FILE="${_TRK_HOME}/recents.tsv"
_RC_EXCLUDE_FILE="${_TRK_HOME}/recents_exclude.conf"
_TRK_LOCK="${_TRK_HOME}/track.lock"
_RC_MAX=100
_RC_AUTOLOCK_AFTER=5          # opened MORE than this many times → locked
declare -ga _RC_P=() _RC_N=() # recents: paths / counts (parallel arrays, newest first)
_SWL_T=""                     # result of _swlink_read_target_v
_SWL_ID=""

# ── the mkdir lock shared with the local daemon: planetary resources (owner pid inside; taken over only when its owner is dead or it is stale) ──
_TRK_LOCK_OWN=0
_trk_lock() {
  _pr_lock_take "$_TRK_LOCK" 40 15 && _TRK_LOCK_OWN=1 || _TRK_LOCK_OWN=0      # a live owner that keeps it too long: go on, but never drop what is not ours
  return 0
}
_trk_unlock() { [ "$_TRK_LOCK_OWN" = 1 ] && _pr_lock_drop "$_TRK_LOCK"; _TRK_LOCK_OWN=0; return 0; }

# ═════════════════════════ bookmarks (.swlink) ═════════════════════════

# _swlink_read_target_v FILE → _SWL_T / _SWL_ID   (pure bash: the viewport calls it once per bookmark row)
_swlink_read_target_v() {
  _SWL_T=""; _SWL_ID=""
  [ -f "$1" ] || return 1
  local l
  while IFS= read -r l || [ -n "$l" ]; do
    case "$l" in
      SWLINK_TARGET=*) [ -n "$_SWL_T" ] || _SWL_T="${l#SWLINK_TARGET=}" ;;
      SWLINK_ID=*)     [ -n "$_SWL_ID" ] || _SWL_ID="${l#SWLINK_ID=}" ;;
    esac
  done < "$1"
  [ -n "$_SWL_T" ]
}
_swlink_read_target() { _swlink_read_target_v "$1" && printf '%s' "$_SWL_T"; }

# the name a bookmark shows: the file name without the internal .swlink suffix
_swlink_name_v() { _SWL_NAME="${1##*/}"; _SWL_NAME="${_SWL_NAME%.swlink}"; }

_swlink_write() {
  local dest_dir="$1" target="$2" display_name="$3"
  mkdir -p "$dest_dir" 2>/dev/null
  local sc_path="${dest_dir}/${display_name}.swlink" count=1
  while [ -e "$sc_path" ]; do
    sc_path="${dest_dir}/${display_name}${count}.swlink"
    count=$(( count + 1 ))
  done
  {
    printf 'SWLINK_TARGET=%s\n' "$target"
    printf 'SWLINK_NAME=%s\n'   "$display_name"
    printf 'SWLINK_CREATED=%s\n' "$(date +%s)"
    printf 'SWLINK_ID=%s\n'     "$(_fav_id "$target")"
  } > "$sc_path"
  printf '%s' "$sc_path"
}

# _swlink_set FILE KEY VALUE   rewrite one line (add it when absent); pure bash
_swlink_set() {
  local f="$1" key="$2" val="$3" l found=false tmp="$1.$$.tmp"
  { while IFS= read -r l || [ -n "$l" ]; do
      if [[ "$l" == "$key="* ]]; then printf '%s=%s\n' "$key" "$val"; found=true; else printf '%s\n' "$l"; fi
    done < "$f"
    $found || printf '%s=%s\n' "$key" "$val"
  } > "$tmp" && mv -f -- "$tmp" "$f" || rm -f -- "$tmp"
}

# _swlink_retarget OLD NEW   every bookmark that points at OLD (or into it) follows it to NEW
_swlink_retarget() {
  local old="${1%/}" new="${2%/}" f n=0
  for f in "$_SW_DIR"/*.swlink; do
    [ -f "$f" ] || continue
    _swlink_read_target_v "$f" || continue
    if [ "$_SWL_T" = "$old" ]; then _swlink_set "$f" SWLINK_TARGET "$new"; n=$((n+1))
    elif [[ "$_SWL_T" == "$old/"* ]]; then _swlink_set "$f" SWLINK_TARGET "$new/${_SWL_T#"$old/"}"; n=$((n+1)); fi
  done
  return 0
}

# _swlink_heal FILE   the target is gone: look for the same inode under $HOME (5 s at most). rc 0 = found and re-pointed (_SWL_T holds it)
_swlink_heal() {
  local f="$1" ino hit
  _swlink_read_target_v "$f" || return 1
  [ -n "$_SWL_ID" ] || return 1
  ino="${_SWL_ID##*:}"
  [[ "$ino" =~ ^[0-9]+$ ]] || return 1
  hit=$(timeout 5 find "$HOME" -xdev -inum "$ino" -not -path '*/.*' -print -quit 2>/dev/null)
  [ -n "$hit" ] && [ "$(_fav_id "$hit")" = "$_SWL_ID" ] || return 1
  _swlink_set "$f" SWLINK_TARGET "$hit"
  _SWL_T="$hit"
  return 0
}

# ═════════════════════════ recents ═════════════════════════

_rc_load() {
  _RC_P=(); _RC_N=()
  [ -r "$_RC_FILE" ] || return 0
  local n p
  while IFS=$'\t' read -r n p || [ -n "$n" ]; do
    [ -n "$p" ] && [[ "$n" =~ ^[0-9]+$ ]] && { _RC_P+=("$p"); _RC_N+=("$n"); }
  done < "$_RC_FILE"
  return 0
}

_rc_save() {
  mkdir -p "$_TRK_HOME" 2>/dev/null
  local tmp="${_RC_FILE}.$$.tmp" i
  { for i in "${!_RC_P[@]}"; do printf '%s\t%s\n' "${_RC_N[$i]}" "${_RC_P[$i]}"; done; } > "$tmp" \
    && mv -f -- "$tmp" "$_RC_FILE" || rm -f -- "$tmp"
}

# the recents_exclude.conf rules (xe in the Recents tab): filename · foldername · filepath · dirpath
_rc_excluded() {                       # <abs path> → 0 when a rule hides it
  [ -r "$_RC_EXCLUDE_FILE" ] || return 1
  local p="$1" line kind val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    { [ -z "$line" ] || [ "${line:0:1}" = "#" ]; } && continue
    kind="${line%%[[:space:]]*}"; val="${line#"$kind"}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    [ -n "$val" ] || continue
    case "${kind,,}" in
      filename)   [ "${p##*/}" = "$val" ] && return 0 ;;
      foldername) [[ "$p/" == *"/$val/"* ]] && return 0 ;;
      filepath)   [ "$p" = "${val/#\~/$HOME}" ] && return 0 ;;
      dirpath)    val="${val/#\~/$HOME}"; [[ "$p/" == "${val%/}/"* ]] && return 0 ;;
    esac
  done < "$_RC_EXCLUDE_FILE"
  return 1
}

# _rc_record PATH   THE entry point: a folder entered with cd, a file edited in the run loop.
# Promotes it to the top, counts the use, and locks it for good once it is used more than _RC_AUTOLOCK_AFTER times.
_rc_record() {
  [ -e "$1" ] || return 0
  _lk_norm "$1"; local p="$_lk_n" i n=0
  _rc_excluded "$p" && return 0
  local -a np=("$p") nn=()
  _trk_lock
  _rc_load
  for i in "${!_RC_P[@]}"; do
    if [ "${_RC_P[$i]}" = "$p" ]; then n="${_RC_N[$i]}"; else np+=("${_RC_P[$i]}"); nn+=("${_RC_N[$i]}"); fi
  done
  n=$((n+1))
  _RC_P=("${np[@]:0:_RC_MAX}"); _RC_N=("$n" "${nn[@]}"); _RC_N=("${_RC_N[@]:0:_RC_MAX}")
  _rc_save
  _trk_unlock
  if [ "$n" -gt "$_RC_AUTOLOCK_AFTER" ]; then
    _lk_load
    if ! _lk_is_locked "$p"; then
      _LK_SET["$p"]=1
      _lk_save && echo "🔒 Locked automatically: ${p##*/}  (used $n times, so it counts as important)"
    fi
  fi
  return 0
}

# _rc_dedupe   after a move two rows may be the same path: keep the first, the larger count
_rc_dedupe() {
  local -A at=()
  local -a np=() nn=()
  local i
  for i in "${!_RC_P[@]}"; do
    if [ -n "${at[${_RC_P[$i]}]+x}" ]; then
      [ "${_RC_N[$i]}" -gt "${nn[${at[${_RC_P[$i]}]}]}" ] && nn[${at[${_RC_P[$i]}]}]="${_RC_N[$i]}"
    else
      at["${_RC_P[$i]}"]=${#np[@]}; np+=("${_RC_P[$i]}"); nn+=("${_RC_N[$i]}")
    fi
  done
  _RC_P=("${np[@]}"); _RC_N=("${nn[@]}")
}

_rc_move() {                           # <old> <new>   a recents row follows its item (and everything below a folder)
  [ -s "$_RC_FILE" ] || return 0
  _lk_norm "$1"; local old="$_lk_n" pre i changed=false
  _lk_norm "$2"; local new="$_lk_n"
  pre="$old/"
  _trk_lock
  _rc_load
  for i in "${!_RC_P[@]}"; do
    if [ "${_RC_P[$i]}" = "$old" ]; then _RC_P[$i]="$new"; changed=true
    elif [[ "${_RC_P[$i]}" == "$pre"* ]]; then _RC_P[$i]="$new/${_RC_P[$i]#"$pre"}"; changed=true; fi
  done
  $changed && { _rc_dedupe; _rc_save; }
  _trk_unlock
  return 0
}

_rc_forget() {                         # <deleted path>   its row (and the rows below a folder) go
  [ -s "$_RC_FILE" ] || return 0
  _lk_norm "$1"; local gone="$_lk_n" pre i changed=false
  pre="$gone/"
  _trk_lock
  _rc_load
  local -a np=() nn=()
  for i in "${!_RC_P[@]}"; do
    if [ "${_RC_P[$i]}" = "$gone" ] || [[ "${_RC_P[$i]}" == "$pre"* ]]; then changed=true
    else np+=("${_RC_P[$i]}"); nn+=("${_RC_N[$i]}"); fi
  done
  _RC_P=("${np[@]}"); _RC_N=("${nn[@]}")
  $changed && _rc_save
  _trk_unlock
  return 0
}

# _rc_build   the Recents tab: items[] = the rows whose item still exists and is not excluded, newest first
_rc_build() {
  items=()
  _rc_load
  local p
  for p in "${_RC_P[@]}"; do
    [ -e "$p" ] && ! _rc_excluded "$p" && items+=("$p")
  done
  return 0
}

# ═════════════════════════ the two calls the rest of the app makes ═════════════════════════

_trk_move()   { _swlink_retarget "$1" "$2"; _rc_move "$1" "$2"; }      # renamed / moved
_trk_forget() { _rc_forget "$1"; }                                      # deleted: bookmarks stay and show 🔴 until the item is back or the bookmark is removed
