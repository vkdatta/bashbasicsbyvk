#!/usr/bin/env bash
# bashbasicsbyvk_staging_backup.sh — Service 2: a copy goes to the backend BEFORE anything is deleted.
#
#   _bk_before_delete <item>...     call it right before rm.   return 0 = go ahead · 1 = do NOT delete · 6 = u at the first question (go back one step)
#
# Settings → File API → Backup:
#   Backup before delete   yes (default) · no · ask every time
#   Default nuke time      30 days (default) — how long a backup is kept
# The copies are listed in Home → Backup (bk): rename, extend / shorten, restore (r-N), nuke — the same list manager as Links.
# A backup is named   DDMMYYYY HHMM NAME   (or just   DDMMYYYY HHMM   when you give no name).
#
# Safe by design: if a backup was wanted but could not be made (offline, not enough credits, you said stop),
# you are asked whether to delete anyway — a failed backup never turns into a silent delete.
# Not backed up on purpose: symlinks (deleting one removes only the link), Google Drive placeholders (they are empty).

_bk_before_delete() {
  local mode; mode=$(_bb_cfg_val backup_mode yes)
  case "$mode" in no) return 0 ;; esac
  [ "${_GD_ACTIVE:-0}" = 1 ] && return 0

  local -a real=()
  local it
  for it in "$@"; do
    [ -L "$it" ] && continue
    [ -e "$it" ] && real+=("$it")
  done
  [ ${#real[@]} -eq 0 ] && return 0

  # no account → no backend: one line, then carry on (the delete was already confirmed)
  if ! _bb_get_credentials >/dev/null 2>&1; then
    echo "📜  No backup was taken — there is no active user (-auth). Deleting without one."
    return 0
  fi
  _crypto_check >/dev/null 2>&1 || { echo "📜  No backup was taken — node is missing. Deleting without one."; return 0; }

  # three questions, so u = ONE QUESTION BACK (_mc_steps), never a way out of the whole delete:
  #   ask (mode "ask" only) → name → upload (a failed upload ends in "Delete anyway?").   u on the first one = 6.
  local a="" nm="" alias="" _bkd_skip=0 _bkd_rc
  _mc_steps _bkd_ask _bkd_name _bkd_upload; _bkd_rc=$?
  case "$_bkd_rc" in
    0) return 0 ;;
    1) return 6 ;;
    *) return 1 ;;
  esac
}

# the steps of _bk_before_delete (they share its locals mode real a nm alias _bkd_skip): 0 answered · 1 u (back) · 3 cancelled · 5 not asked
_bkd_ask() {
  [ "$mode" = ask ] || return 5
  # A menu that was cancelled (u = go back, or a command that is not allowed here) returns 1 and
  # raises _CM_ABORT: the whole flow stops RIGHT HERE — nothing is packed, uploaded or deleted.
  _bvk_yn a "Back up ${#real[@]} item(s) to the cloud before deleting?" -d none -c -t "Back up before deleting" -i "🗄️" || {
    _bvk_back && return 1
    return 3; }
  [ "${_CM_ABORT:-0}" = 1 ] && return 3
  case "$a" in
    c) echo "🚫 Nothing deleted."; return 3 ;;
    n) _bkd_skip=1 ;;
  esac
  return 0
}

# one name prompt: 0 answered (nm) · 1 u · 3 EOF / flow cancelled
_bkd_read_name() {
  _CM_BACKED=0
  read -e -r -p "Name this backup (Enter = just the date and time): " nm || { [ "${_CM_BACKED:-0}" = 1 ] && { _CM_BACKED=0; return 1; }; return 3; }
  [ "${_CM_ABORT:-0}" = 1 ] && return 3
  return 0
}
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
      _bb_done_head "Backup"; echo; echo "🗄️  $alias"
      [ -n "$_SVC_DEDUCTED" ] && _bb_credits "$_SVC_DEDUCTED" "$_SVC_BALANCE"
      echo "🕐 Nuke time: $(_bb_fmt_duration "$_SVC_TTL")"; _bb_goto "Home → Backup (bk)"
      return 0 ;;
    2) echo "🔴  No backup was made (you stopped it)." ;;
    4) echo "⏸  The backup was interrupted. It is KEPT — finish it from Pending (pn). Nothing is deleted yet." ;;
    *) echo "🔴  The backup FAILED — nothing was saved to the cloud." ;;
  esac
  _bvk_yn a "Delete anyway, without a backup?" -d none || {
    _bvk_back && return 1                     # u = the name question again
    echo "🚫 Nothing deleted."; return 3; }
  case "${a,,}" in
    y|yes) return 0 ;;
    *)     echo "🚫 Nothing deleted."; return 3 ;;
  esac
}
