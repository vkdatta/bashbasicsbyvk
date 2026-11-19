#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_common.sh
# Shared helpers for the file/delete/* ADF functions.
# (No registration here — this file only defines helpers.)
#
# Reuses from organise: _batch_stat, _ts_to_ymd
# Reuses from browse: _pick_groups (the by-extension / by-date pick screen)

# Non-hidden plain files in the current folder (same scope organise uses).
_fxdel_list_files() {
  local -n _out="$1"
  _out=()
  local f
  for f in "$path"/*; do [ -f "$f" ] && _out+=("$f"); done
}

# Confirm, then remove everything in $selected_items.
# Prints "Deleted x out of n item(s)" and lists failed items only.
# Returns 1 when u was typed at Confirm delete (the caller goes back to the question before it), 2 for q, 3 when cancelled, else 0.
_fxdel_run_selected() {
  local total=${#selected_items[@]}
  [ "$total" -eq 0 ] && { echo "❌ Nothing to delete"; return; }

  # ONE gate: Confirm delete (lock gate l-N) → Back up before deleting (Settings → File API → Backup); u = one question back
  _lk_delete_gate "Are you really sure you want to delete $total item(s)? This action can't be undone. (y/n): " || return $?
  total=${#selected_items[@]}

  local ok=0 item err
  local -a failed=()
  for item in "${selected_items[@]}"; do
    if err=$(rm -rf -- "$item" 2>&1); then
      ok=$((ok+1)); _carry_forget "$item"
    else
      failed+=("${item##*/} — ${err:-rm failed}")
    fi
  done

  if [ ${#failed[@]} -eq 0 ]; then
    echo "💫 Deleted $ok out of $total item(s). I can feel the space 🚀"
  else
    echo "🔴  Deleted $ok out of $total item(s)."
    echo "❌ Failed (${#failed[@]}):"
    for item in "${failed[@]}"; do echo "  • $item"; done
  fi
}
