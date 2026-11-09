#!/usr/bin/env bash
# bashbasicsbyvk_action_confirm_key.sh — the ONE "type this 6-digit number to continue" gate.
# ════════════════════════════════════════════════════════════════════════════
#  Shared by every action that must not happen by accident:
#    • Git Push           (bashbasicsbyvk_gitpush — every confirm + the force-push gate)
#    • Deleting locked items (bashbasicsbyvk_lock.sh, l-n / ul-n)
#
#  Usage (sourced):
#      action_confirm_key "<heading>" ["<detail line>" ...]   → 0 = number typed
#                                                                 correctly, 1 = not
#  Usage (run as a command, e.g. from another process):
#      bash bashbasicsbyvk_action_confirm_key.sh "<heading>" ["<detail line>" ...]; echo $?
#
#  The function never exits the shell and never calls die — the caller decides
#  what a wrong / empty answer means (cancel, abort, ...).
# ════════════════════════════════════════════════════════════════════════════

# Prints a fresh 6-digit number (100000-999999, never a leading zero).
_ack_new_key() {
  local k=""
  if command -v shuf >/dev/null 2>&1; then
    k="$(shuf -i 100000-999999 -n 1 2>/dev/null)"
  fi
  if ! [[ "$k" =~ ^[1-9][0-9]{5}$ ]]; then
    k="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')"
    k=$(( 100000 + ${k:-$RANDOM$RANDOM} % 900000 ))
  fi
  printf '%s' "$k"
}

action_confirm_key() {
  local heading="${1:-This action cannot be undone.}"; shift 2>/dev/null
  local key typed line
  key="$(_ack_new_key)"

  echo
  echo "============================================================"
  echo "🔴  $heading"
  for line in "$@"; do echo "$line"; done
  echo "============================================================"
  echo
  echo "Type this number exactly to continue:"
  echo
  echo "  $key"
  echo
  read -e -r -p "Confirmation number: " typed || return 1

  if [[ "$typed" == "$key" ]]; then
    echo "OK: Confirmation accepted."
    return 0
  fi
  echo "🚫 Confirmation failed."
  return 1
}

# Run directly (not sourced): behave as a command.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  action_confirm_key "$@"
  exit $?
fi
