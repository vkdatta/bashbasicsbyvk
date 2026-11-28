#!/usr/bin/env bash
# bashbasicsbyvk_staging_backup.sh — Service 2: a copy is kept BEFORE anything destructive happens (delete, erase, find & replace, replace with clipboard).
#
#   _bk_guard <action> <item>...    call it right before the change.   return 0 = go ahead · 1 = do NOT go on · 6 = u at the first question (go back one step)
#                                   <action> is a key of _ACT_DESTRUCTIVE (bashbasicsbyvk_recovery.sh): a non-destructive action returns 0 at once.
#   _bk_before_delete <item>...     = _bk_guard delete   (the old name; the lock gate still calls it)
#
# Settings → File API → Backup:
#   Backup type            No Backup · Offline · Both Offline and FileAPI (default) · FileAPI.   A free user always gets Offline (except No Backup).
#   Ask before cloud backup  no (default: the name is asked, then it goes) · ask every time
#   Default nuke time      30 days (default) — how long a FileAPI backup is kept (the offline copies stay until you delete them: Home → Recovery Bin)
# FileAPI copies are listed in Home → Backup (bk): rename, extend / shorten, restore (r-N), nuke (needs the confirmation key).
# Offline copies are listed in Home → Recovery Bin: restore, delete (needs the confirmation key).
# A FileAPI backup is named   DDMMYYYY HHMM NAME   (or just   DDMMYYYY HHMM   when you give no name).
#
# Safe by design: if a backup was wanted but could not be made (offline, not enough credits, you said stop),
# you are asked whether to go on anyway — a failed backup never turns into a silent change.  When the cloud half cannot even start
# (no node) and FileAPI was the only service chosen, the offline copy is made instead.
# Not backed up on purpose: symlinks (deleting one removes only the link), Google Drive placeholders (they are empty).
# Already inside the recovery bin: no OFFLINE copy (it would be a duplicate); the FileAPI backup is still made.

declare -gA _BKD_VERB=([delete]=deleting [erase]="erasing its content" [findreplace]="the find & replace" [overwrite]="replacing the content" [replace]="they are replaced")
_bk_before_delete() { _bk_guard delete "$@"; }

# _bk_clash_filter DEST ITEM...   a move that would REPLACE a file already at DEST/<name> destroys that file: back those files up first (a "replace" action).
#   Fills _BK_PASS with the items that may go on: no name clash, or the clashing file was backed up.  rc 0 all pass · 1 some are held back (said).
#   Folders never clash here (mv puts an item INSIDE an existing folder, or refuses); the same file (item -ef target) is not a clash.
_BK_PASS=()
_bk_clash_filter() {
  local dest="$1"; shift
  local it t; local -a clash=() hold=()
  _BK_PASS=()
  for it in "$@"; do
    t="${dest%/}/${it##*/}"
    { [ -f "$t" ] || [ -L "$t" ]; } && ! [ "$it" -ef "$t" ] && [ ! -d "$it" ] && clash+=("$t")
  done
  if [ ${#clash[@]} -eq 0 ]; then _BK_PASS=("$@"); return 0; fi
  echo "❗ ${#clash[@]} file(s) at the destination have the same name and would be REPLACED: ${clash[0]##*/}$([ ${#clash[@]} -gt 1 ] && echo " …")"
  if _bk_guard replace "${clash[@]}"; then _BK_PASS=("$@"); return 0; fi
  local -A held=(); for t in "${clash[@]}"; do held["$t"]=1; done
  for it in "$@"; do
    t="${dest%/}/${it##*/}"
    if [ -n "${held[$t]:-}" ]; then echo "🚫 Not moved (it would replace $t, no backup was made): ${it##*/}"; else _BK_PASS+=("$it"); fi
  done
  return 1
}

_bk_guard() {
  local action="$1"; shift
  _act_is_destructive "$action" || return 0
  local svc; svc=$(_rb_service backup)
  [ "$svc" = none ] && return 0
  [ "${_GD_ACTIVE:-0}" = 1 ] && return 0

  local -a real=()
  local it
  for it in "$@"; do
    [ -L "$it" ] && continue
    [ -e "$it" ] && real+=("$it")
  done
  [ ${#real[@]} -eq 0 ] && return 0

  local rc=0 a=""
  _BKD_NOTAKEN=0
  case "$svc" in
    fileapi|both)
      _bk_fileapi_backup "$action" "${real[@]}"; rc=$?
      (( rc == 0 )) || return "$rc" ;;
  esac
  if [ "$svc" = offline ] || [ "$svc" = both ] || { [ "$svc" = fileapi ] && [ "$_BKD_NOTAKEN" = 1 ]; }; then
    if ! _rb_store "$action" "${real[@]}"; then
      _bkd_q a "The offline backup FAILED. Go on without it?" -t "No backup" -i "💾" || { echo "🚫 Nothing changed."; return 1; }
      [ "$a" = y ] || { echo "🚫 Nothing changed."; return 1; }
    fi
  fi
  return 0
}

# the cloud half.  0 go ahead · 1 stop · 6 u at the first question.   Sets _BKD_NOTAKEN=1 when it had to skip itself without asking.
_bk_fileapi_backup() {
  local action="$1"; shift
  local mode; mode=$(_bb_cfg_val backup_mode yes)
  local -a real=("$@")

  # no account → no backend; the offline half (if any) still runs
  if ! _bb_get_credentials >/dev/null 2>&1; then
    echo "📜  No cloud backup was taken — there is no active user (-auth)."; _BKD_NOTAKEN=1
    return 0
  fi
  _crypto_check >/dev/null 2>&1 || { echo "📜  No cloud backup was taken — node is missing."; _BKD_NOTAKEN=1; return 0; }

  # three questions, so u = ONE QUESTION BACK (_mc_steps), never a way out of the whole action:
  #   ask (mode "ask" only) → name → upload (a failed upload ends in "Go on anyway?").   u on the first one = 6.
  local a="" nm="" alias="" _bkd_skip=0 _bkd_rc
  _mc_steps _bkd_ask _bkd_name _bkd_upload; _bkd_rc=$?
  case "$_bkd_rc" in
    0) return 0 ;;
    1) return 6 ;;
    *) return 1 ;;
  esac
}

# ── the questions: the app's own menus (u = one question back inside _mc_steps)
# _bkd_q VAR "question" [-c] [-t title] [-i icon] → 0 answered (VAR = y | n | c) · 1 u (back) · 3 cancelled
_bkd_q() {
  local _v="$1" _q="$2"; shift 2
  printf -v "$_v" ''
  _bvk_yn "$_v" "$_q" -d none "$@" && { [ "${_CM_ABORT:-0}" = 1 ] && return 3; return 0; }
  _bvk_back && return 1
  return 3
}
# _bkd_line VAR "prompt" → 0 answered · 1 u · 3 EOF / cancelled
_bkd_line() {
  local _v="$1" _p="$2"
  _CM_BACKED=0
  _bvk_read "$_v" "$_p" || { [ "${_CM_BACKED:-0}" = 1 ] && { _CM_BACKED=0; return 1; }; return 3; }
  [ "${_CM_ABORT:-0}" = 1 ] && return 3
  return 0
}

# the steps of _bk_fileapi_backup (they share its locals action mode real a nm alias _bkd_skip): 0 answered · 1 u (back) · 3 cancelled · 5 not asked
_bkd_ask() {
  [ "$mode" = ask ] || return 5
  # A menu that was cancelled (u = go back, or a command that is not allowed here) returns 1 / 3: the whole flow stops RIGHT HERE —
  # nothing is packed, uploaded or changed.
  _bkd_q a "Back up ${#real[@]} item(s) to the cloud before ${_BKD_VERB[$action]:-changing them}?" -c -t "Back up first" -i "💾" || return $?
  case "$a" in
    c) echo "🚫 Nothing changed."; return 3 ;;
    n) _bkd_skip=1 ;;
  esac
  return 0
}

# one name prompt: 0 answered (nm) · 1 u · 3 EOF / flow cancelled
_bkd_read_name() { _bkd_line nm "Name this backup (Enter = just the date and time): "; }
_bkd_name() {
  [ "$_bkd_skip" = 1 ] && return 0
  local rc
  _bkd_read_name; rc=$?; (( rc )) && return "$rc"
  while ! alias=$(_bb_svc_alias "$nm"); do
    echo "   🔴  A name may use letters, digits, spaces and . _ @ + -  (up to ~34 characters after the date)."
    _bkd_read_name; rc=$?; (( rc )) && return "$rc"
  done
  return 0
}
_bkd_upload() {
  [ "$_bkd_skip" = 1 ] && return 0
  _svc_upload backup "$alias" "${real[@]}"
  case $? in
    0)
      _bb_done_head "Backup"; echo; echo "💾 $alias"
      [ -n "$_SVC_DEDUCTED" ] && _bb_credits "$_SVC_DEDUCTED" "$_SVC_BALANCE"
      echo "🕐 Nuke time: $(_bb_fmt_duration "$_SVC_TTL")"; _bb_goto "Home → Backup (bk)"
      return 0 ;;
    2) echo "🔴  No backup was made (you stopped it)." ;;
    4) echo "⏳ The backup was interrupted. It is KEPT — finish it from Pending (pn). Nothing was changed yet." ;;
    *) echo "🔴  The backup FAILED — nothing was saved to the cloud." ;;
  esac
  _bkd_q a "Go on anyway, without a cloud backup?" || {
    [ "$?" = 1 ] && return 1                  # u = the name question again
    echo "🚫 Nothing changed."; return 3; }
  [ "$a" = y ] && return 0
  echo "🚫 Nothing changed."; return 3
}
