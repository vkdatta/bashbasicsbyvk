#!/usr/bin/env bash
# bashbasicsbyvk_recovery.sh — the OFFLINE half of Backup and Snapshots, and the ONE "is this action destructive?" table.
# ════════════════════════════════════════════════════════════════════════════
#  1. THE TRIGGERING CAUSE.   Every action says once whether it is destructive (_ACT_DESTRUCTIVE).  Some are destructive only when something is in the way:
#     move / organise onto a name that already exists replaces that file — the caller asks _bk_clash_filter first (copy renames, rename refuses: both safe).  A destructive action
#     (delete, erase content, find & replace, replace with clipboard) goes through _bk_guard (bashbasicsbyvk_staging_backup.sh)
#     BEFORE it changes anything; a non-destructive one (move, copy, rename ...) never does.  A new action = one line in the table.
#
#  2. WHERE THE COPIES GO (Settings → File API → Backup type / Snapshot type).
#        No Backup · Offline · Both Offline and FileAPI (default) · FileAPI          (snapshots: no "No Backup")
#     A FREE user (no -auth user, or the Free plan) always gets the offline service, whatever was chosen (except No Backup).
#
#  3. THE FOLDERS (both under ~/.bashbasicsbyvk, shown in Home → Recovery Bin and Home → Offline Snapshots):
#        recovery_bin/<id>/    one folder per destructive action:  meta  +  data/<n>/<the copy of item n>
#        snapshots/<id>/       one folder per offline snapshot:    meta  +  data/1/<the copy>        (.state/ = what changed since)
#     <id> = YYYYMMDD-HHMMSS-NNN (sorts by time).  meta is DATA (key=value), never sourced.
#
#  4. NO DUPLICATES: a destructive action on something that is already INSIDE the recovery bin gets no offline copy (the FileAPI
#     backup is still made).  A snapshot of a snapshot file IS allowed (duplicates are fine there).
#
#  5. Deleting anything from the bin or from the offline snapshots asks for the 6-digit action confirmation key
#     (action_confirm_key).  Restore never overwrites: if the original is there, the copy comes back as  NAME.restored-<time>.
#
#  Needs: _bb_cfg_val (fileapi_lib), action_confirm_key, _bvk_yn / _bvk_menu, _st_run / _st_add (screens only).
# ════════════════════════════════════════════════════════════════════════════

_RB_HOME="${BVK_HOME_DIR:-$HOME/.bashbasicsbyvk}"
_RB_BIN="$_RB_HOME/recovery_bin"
_RB_SNAP="$_RB_HOME/snapshots"
_RB_ID_RE='^[0-9]{8}-[0-9]{6}-[0-9]+$'

# ── 1. the table: 1 = destructive (needs a backup first) · 0 = not
declare -gA _ACT_DESTRUCTIVE=(
  [delete]=1 [erase]=1 [findreplace]=1 [overwrite]=1
  [replace]=1       # a move / organise that would REPLACE a file already at the destination: that file is what is lost (see _bk_clash_filter)
  [move]=0 [copy]=0 [rename]=0 [create]=0 [extract]=0 [edit]=0 [share]=0 [lock]=0
)
_act_is_destructive() { [ "${_ACT_DESTRUCTIVE[${1:-}]:-0}" = 1 ]; }

# ── 2. which service runs
# 0 when the person has no paid account (no -auth user, or the Free plan).  The plan is read from the tiny cache the insanity meter keeps
# ("<epoch> <plan> <level> <user>"); an unknown plan counts as paid (a failed upload asks before going on).
_rb_user_is_free() {
  local act="" f at plan lv uid
  f="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/active"
  [ -r "$f" ] && IFS= read -r act < "$f"
  [ -n "$act" ] || return 0
  f="${XDG_STATE_HOME:-$HOME/.local/state}/bashbasicsbyvk/insanity"
  [ -r "$f" ] && read -r at plan lv uid < "$f"
  [ "$uid" = "$act" ] && [ "$plan" = free ]
}
# _rb_service backup|snapshot  → none | offline | both | fileapi   (what really runs, the free-user rule applied)
_rb_service() {
  local kind="$1" t
  if [ "$kind" = backup ]; then
    t=$(_bb_cfg_val backup_type both)
    [[ "$t" =~ ^(none|offline|both|fileapi)$ ]] || t=both
    [ "$t" = none ] && { printf none; return; }
  else
    t=$(_bb_cfg_val snapshot_type both)
    [[ "$t" =~ ^(offline|both|fileapi)$ ]] || t=both
  fi
  _rb_user_is_free && t=offline
  printf '%s' "$t"
}

# ── paths
_rb_abs() { readlink -f -- "$1" 2>/dev/null || realpath "$1" 2>/dev/null || printf '%s' "$1"; }
# _rb_inside PATH ROOT → 0 when PATH is ROOT or under it
_rb_inside() {
  local p r; p=$(_rb_abs "$1"); r=$(_rb_abs "$2")
  case "$p" in "$r"|"$r"/*) return 0 ;; esac
  return 1
}
# _rb_holds PATH ROOT → 0 when ROOT is strictly under PATH (PATH contains it)
_rb_holds() { local p r; p=$(_rb_abs "$1"); r=$(_rb_abs "$2"); [ "$p" != "$r" ] && case "$r" in "$p"/*) return 0 ;; esac; return 1; }
_rb_new_id() { printf '%s-%03d' "$(date +%Y%m%d-%H%M%S)" $(( RANDOM % 1000 )); }
_rb_mkroot() { mkdir -p "$1" 2>/dev/null && chmod 700 "$_RB_HOME" "$1" 2>/dev/null; }
_rb_kb() { local k; k=$(du -sk -- "$1" 2>/dev/null | cut -f1); printf '%s' "${k:-0}"; }
_rb_hsize() {   # KB → "12 KB" / "3.4 MB"
  local kb="${1:-0}"
  if   (( kb >= 1048576 )); then printf '%d.%d GB' $((kb/1048576)) $(( (kb%1048576)*10/1048576 ))
  elif (( kb >= 1024 ));    then printf '%d.%d MB' $((kb/1024)) $(( (kb%1024)*10/1024 ))
  else printf '%d KB' "$kb"; fi
}
# "DDMMYYYY HHMM" from an id (the same look as a FileAPI backup name)
_rb_title() { local d="${1%%-*}" r="${1#*-}"; printf '%s%s%s %s%s' "${d:6:2}" "${d:4:2}" "${d:0:4}" "${r:0:2}" "${r:2:2}"; }

# _rb_copy SRC DESTDIR → copies SRC into DESTDIR (cp -a).  When SRC holds the recovery folders (a parent of ~/.bashbasicsbyvk) they are LEFT OUT:
# copying them into themselves would never end, and they are copies already.
_rb_copy() {
  local src="$1" dst="$2" p parent base ex=()
  if _rb_holds "$src" "$_RB_BIN" || _rb_holds "$src" "$_RB_SNAP"; then
    command -v tar >/dev/null 2>&1 || return 1
    p=$(_rb_abs "$src"); parent="${p%/*}"; [ -n "$parent" ] || parent=/; base="${p##*/}"
    _rb_holds "$src" "$_RB_BIN"  && ex+=(--exclude="$base/${_RB_BIN#"$p"/}")
    _rb_holds "$src" "$_RB_SNAP" && ex+=(--exclude="$base/${_RB_SNAP#"$p"/}")
    ( cd "$parent" && tar -cf - "${ex[@]}" -- "$base" ) | tar -xf - -C "$dst" 2>/dev/null
    return $(( PIPESTATUS[0] | PIPESTATUS[1] ))
  fi
  cp -a --reflink=auto -- "$src" "$dst/" 2>/dev/null || cp -a -- "$src" "$dst/" 2>/dev/null
}

# _rb_entry_write ROOT ACTION TARGET ITEM... → makes one entry folder under ROOT; prints its id.  rc 0 ok · 1 failed (nothing left behind)
#   TARGET = the watched path of a snapshot ("" for a backup)
_rb_entry_write() {
  local root="$1" action="$2" target="$3"; shift 3
  local it id dir n=0 need=0 free kb nl=$'\n'
  _rb_mkroot "$root" || return 1
  for it in "$@"; do
    [[ "$it" == *"$nl"* ]] && { echo "🔴  A name with a line break cannot be kept offline: ${it//$nl/ }" >&2; return 1; }
    need=$(( need + $(_rb_kb "$it") ))
  done
  free=$(df -Pk "$root" 2>/dev/null | awk 'NR==2{print $4}')
  if [[ "$free" =~ ^[0-9]+$ ]] && (( free < need + need / 10 + 1024 )); then
    echo "🔴  Not enough free space for an offline copy (needs about $(_rb_hsize "$need"), $(_rb_hsize "$free") free)." >&2; return 1
  fi
  id=$(_rb_new_id); dir="$root/$id"
  while [ -e "$dir" ]; do id=$(_rb_new_id); dir="$root/$id"; done
  mkdir -p "$dir/data" || return 1
  {
    echo "action=$action"; echo "epoch=$(date +%s)"; echo "count=$#"
    [ -n "$target" ] && echo "target=$target"
  } > "$dir/meta"
  for it in "$@"; do
    n=$((n+1)); mkdir -p "$dir/data/$n"
    if ! _rb_copy "$it" "$dir/data/$n"; then rm -rf -- "$dir"; echo "🔴  Could not copy ${it##*/} offline." >&2; return 1; fi
    kb=$(_rb_kb "$dir/data/$n")
    { echo "src.$n=${_RB_SRC_AS:-$(_rb_abs "$it")}"; echo "name.$n=${it##*/}"; [ -d "$it" ] && echo "kind.$n=d" || echo "kind.$n=f"; echo "kb.$n=$kb"; } >> "$dir/meta"
  done
  printf '%s' "$id"
}

# ── the recovery bin (destructive actions)
# _rb_store ACTION ITEM... → rc 0 kept (or nothing to keep) · 1 failed.   Items already inside the bin are left out (no duplicate).
_rb_store() {
  local action="$1"; shift
  local it id; local -a keep=()
  for it in "$@"; do
    if _rb_inside "$it" "$_RB_BIN"; then echo "📜  ${it##*/} is already in the recovery bin — no offline copy (a duplicate)."; continue; fi
    keep+=("$it")
  done
  [ ${#keep[@]} -gt 0 ] || return 0
  id=$(_rb_entry_write "$_RB_BIN" "$action" "" "${keep[@]}") || return 1
  echo "📂 Kept offline: $(_rb_title "$id")  (Home → Recovery Bin)"
  return 0
}

# ── offline snapshots
# _rb_sig_triple PATH → "<signature> <bytes> <files>" from names, sizes and modification times (no node needed: a free user may not have it)
_rb_sig_triple() {
  local out sig
  out=$(find "$1" \( -type f -o -type d \) -printf '%P\t%y\t%s\t%T@\n' 2>/dev/null | LC_ALL=C sort)
  [ -n "$out" ] || return 1
  if command -v sha256sum >/dev/null 2>&1; then sig=$(sha256sum <<<"$out" | cut -c1-40); else sig=$(shasum -a 256 <<<"$out" | cut -c1-40); fi
  printf '%s %s' "$sig" "$(awk -F'\t' '$2=="f"{b+=$3;c++} END{print b+0, c+0}' <<<"$out")"
}
_rb_snap_sig() { local t; t=$(_rb_sig_triple "$1") && printf '%s' "${t%% *}"; }
_rb_snap_state() { printf '%s/.state/%s' "$_RB_SNAP" "$1"; }
# _rb_snap_take TGT PATH → rc 0 taken · 1 skipped / failed (logged by the caller)   (unchanged since the last one = skipped)
_rb_snap_take() {
  local tgt="$1" src="$2" sig last="" work id
  [ -e "$src" ] || return 1
  if [ "$(_rb_abs "$src")" = "$(_rb_abs "$_RB_SNAP")" ] || [ "$(_rb_abs "$src")" = "$(_rb_abs "$_RB_BIN")" ]; then
    return 1      # the whole store would copy itself every pass: snapshot ONE entry (or file) inside it instead
  fi
  sig=$(_rb_snap_sig "$src"); [ -n "$sig" ] || return 1
  [ -r "$(_rb_snap_state "$tgt")" ] && read -r last < "$(_rb_snap_state "$tgt")"
  [ "$sig" = "$last" ] && return 1
  # copy first to a work folder OUTSIDE the stores (a source that changes or sits next to the store cannot corrupt or recurse), then move it in
  work=$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/bashbasicsbyvk/offsnap.XXXXXX" 2>/dev/null) || work=$(mktemp -d) || return 1
  _rb_copy "$src" "$work" || { rm -rf -- "$work"; return 1; }
  id=$(_RB_SRC_AS="$(_rb_abs "$src")" _rb_entry_write "$_RB_SNAP" snapshot "$src" "$work/${src##*/}") || { rm -rf -- "$work"; return 1; }   # the entry remembers the real path, not the work folder
  rm -rf -- "$work"
  mkdir -p "$_RB_SNAP/.state" 2>/dev/null; printf '%s\n' "$sig" > "$(_rb_snap_state "$tgt")"
  printf '%s' "$id"
}

# ── reading an entry:  _rb_meta ROOT ID → _RBM_action _RBM_epoch _RBM_count _RBM_target  and  _RBM_src[] _RBM_name[] _RBM_kind[] _RBM_kb[]  (1-based)
declare -g _RBM_action="" _RBM_epoch="" _RBM_count=0 _RBM_target=""
declare -ga _RBM_src=() _RBM_name=() _RBM_kind=() _RBM_kb=()
_rb_meta() {
  local f="$1/$2/meta" k v line
  _RBM_action=""; _RBM_epoch=0; _RBM_count=0; _RBM_target=""; _RBM_src=(); _RBM_name=(); _RBM_kind=(); _RBM_kb=()
  [ -r "$f" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    k="${line%%=*}"; v="${line#*=}"
    case "$k" in
      action) _RBM_action="$v" ;; epoch) [[ "$v" =~ ^[0-9]+$ ]] && _RBM_epoch="$v" ;; count) [[ "$v" =~ ^[0-9]+$ ]] && _RBM_count="$v" ;;
      target) _RBM_target="$v" ;;
      src.*) _RBM_src[${k#src.}]="$v" ;; name.*) _RBM_name[${k#name.}]="$v" ;;
      kind.*) _RBM_kind[${k#kind.}]="$v" ;; kb.*) _RBM_kb[${k#kb.}]="$v" ;;
    esac
  done < "$f"
  return 0
}
_rb_ids() {   # _rb_ids ROOT → _RB_IDS[] newest first
  local d; _RB_IDS=()
  [ -d "$1" ] || return 0
  while IFS= read -r d; do [[ "$d" =~ $_RB_ID_RE ]] && _RB_IDS+=("$d"); done < <(ls -1 "$1" 2>/dev/null | LC_ALL=C sort -r)
}
declare -ga _RB_IDS=()
_rb_entry_label() {   # ROOT ID → "24112026 1530   report.txt, notes (2 items)"
  local names n i
  _rb_meta "$1" "$2" || { printf '%s   (unreadable)' "$(_rb_title "$2")"; return; }
  n=$(( ${#_RBM_name[@]} )); names=""
  for i in "${!_RBM_name[@]}"; do names+="${names:+, }${_RBM_name[$i]}"; [ "${#names}" -gt 40 ] && { names="${names:0:40}…"; break; }; done
  printf '%s   %s' "$(_rb_title "$2")" "${names:-(empty)}"
}

# ── restore / delete
# _rb_restore ROOT ID → puts every item back where it came from; an existing original is never touched: the copy comes back as NAME.restored-<time>
_rb_restore() {
  local root="$1" id="$2" i dest stamp ok=0 bad=0
  _rb_meta "$root" "$id" || { echo "🔴  That entry cannot be read."; return 1; }
  stamp=$(date +%d%m%Y-%H%M%S)
  for i in "${!_RBM_src[@]}"; do
    local copy="$root/$id/data/$i/${_RBM_name[$i]}"
    [ -e "$copy" ] || [ -L "$copy" ] || { echo "🔴  Missing in the entry: ${_RBM_name[$i]}"; bad=$((bad+1)); continue; }
    dest="${_RBM_src[$i]}"
    [ -e "$dest" ] || [ -L "$dest" ] && dest="${dest}.restored-$stamp"
    mkdir -p -- "${dest%/*}" 2>/dev/null
    if cp -a --reflink=auto -- "$copy" "$dest" 2>/dev/null || cp -a -- "$copy" "$dest" 2>/dev/null; then
      echo "💫 Restored: $dest"; ok=$((ok+1))
    else echo "🔴  Could not restore to $dest"; bad=$((bad+1)); fi
  done
  [ "$bad" = 0 ]
}
# _rb_delete ROOT ID LABEL → asks for the action confirmation key; rc 0 deleted · 1 u (back) · 3 not deleted
_rb_delete() {
  local root="$1" id="$2" label="$3" rc
  [[ "$id" =~ $_RB_ID_RE ]] && [ -n "$root" ] && [ -d "$root/$id" ] || { echo "🔴  Nothing to delete."; return 3; }
  action_confirm_key "DELETE FROM BACKUP — confirmation required" "This removes the offline copy for good:" "  $label"; rc=$?
  case "$rc" in 0) ;; 2) return 1 ;; *) echo "🚫 Not deleted."; return 3 ;; esac
  rm -rf -- "${root:?}/$id" && { echo "💥 Deleted: $label"; return 0; }
  echo "🔴  Could not delete it."; return 3
}

# ── 3. the Home screens (Home → Recovery Bin · Home → Offline Snapshots)
_RB_VIEW_ROOT=""; _RB_VIEW_WHAT=""
_rb_view_build() {
  local id; _st_reset
  _rb_ids "$_RB_VIEW_ROOT"
  _st_add h "Folder: $_RB_VIEW_ROOT"
  if [ ${#_RB_IDS[@]} -eq 0 ]; then _st_add h "Nothing here yet."; return 0; fi
  for id in "${_RB_IDS[@]}"; do
    _rb_meta "$_RB_VIEW_ROOT" "$id" && _st_add a "$(_rb_entry_label "$_RB_VIEW_ROOT" "$id")" 0 "$(_rb_hsize "$(_rb_entry_kb "$id")") · ${_RBM_action:-?}" "$id" \
      || _st_add a "$(_rb_title "$id")   (unreadable)" 0 "" "$id"
  done
}
_rb_entry_kb() { local i t=0; for i in "${!_RBM_kb[@]}"; do t=$(( t + ${_RBM_kb[$i]:-0} )); done; printf '%s' "$t"; }
_rb_view_act() {
  local id="${_st_tag[$1]}" what ans label i q
  [[ "$id" =~ $_RB_ID_RE ]] || return 0
  _rb_meta "$_RB_VIEW_ROOT" "$id"; label=$(_rb_entry_label "$_RB_VIEW_ROOT" "$id")
  q="$label"; [ -n "$_RBM_target" ] && q+=" · watched path: $_RBM_target"
  for i in "${!_RBM_src[@]}"; do q+=" · from ${_RBM_src[$i]} ($(_rb_hsize "${_RBM_kb[$i]:-0}"))"; done
  _bvk_menu ans -t "$_RB_VIEW_WHAT" -i "📂" -q "$q" "r:Restore" "x:Delete (needs the confirmation key)" || return 0
  case "$ans" in
    r) _rb_restore "$_RB_VIEW_ROOT" "$id" ;;
    x) _rb_delete "$_RB_VIEW_ROOT" "$id" "$label" ;;
  esac
  return 0
}
recovery_bin_screen()      { local _RB_VIEW_ROOT="$_RB_BIN"  _RB_VIEW_WHAT="Recovery Bin";      _st_run "Recovery Bin"      _rb_view_build _rb_view_act; }
offline_snapshots_screen() { local _RB_VIEW_ROOT="$_RB_SNAP" _RB_VIEW_WHAT="Offline Snapshots"; _st_run "Offline Snapshots" _rb_view_build _rb_view_act; }
