#!/usr/bin/env bash
# bashbasicsbyvk_backup.sh — Service 2: a copy goes to the backend BEFORE anything is deleted.
#
#   _bk_before_delete <item>...     call it right before rm.   return 0 = go ahead · 1 = do NOT delete
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

source "bashbasicsbyvk_svc_core.sh"

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
    echo "ℹ️  No backup was taken — there is no active user (-auth). Deleting without one."
    return 0
  fi
  _crypto_check >/dev/null 2>&1 || { echo "ℹ️  No backup was taken — node is missing. Deleting without one."; return 0; }

  local a nm alias
  if [ "$mode" = ask ]; then
    read -e -r -p "🗄️  Back up ${#real[@]} item(s) to the cloud before deleting? [Y/n, c = cancel the delete]: " a
    case "${a,,}" in
      c|cancel) echo "🚫 Nothing deleted."; return 1 ;;
      n|no)     return 0 ;;
    esac
  fi

  read -e -r -p "🗄️  Name this backup (Enter = just the date and time): " nm
  while ! alias=$(_bb_svc_alias "$nm"); do
    echo "   ⚠️  A name may use letters, digits, spaces and . _ @ + -  (up to ~34 characters after the date)."
    read -e -r -p "🗄️  Name this backup (Enter = just the date and time): " nm
  done

  _svc_upload backup "$alias" "${real[@]}"
  case $? in
    0)
      echo "🗄️  Backed up as '$alias' — kept $(_bb_fmt_duration "$_SVC_TTL")  ·  Home → Backup (bk) to restore."
      [ -n "$_SVC_DEDUCTED" ] && echo "💳 Credits deducted: $_SVC_DEDUCTED   |   Balance: $_SVC_BALANCE"
      return 0 ;;
    2) echo "⚠️  No backup was made (you stopped it)." ;;
    *) echo "⚠️  The backup FAILED — nothing was saved to the cloud." ;;
  esac
  read -e -r -p "   Delete anyway, without a backup? (y/N): " a
  case "${a,,}" in
    y|yes) return 0 ;;
    *)     echo "🚫 Nothing deleted."; return 1 ;;
  esac
}
