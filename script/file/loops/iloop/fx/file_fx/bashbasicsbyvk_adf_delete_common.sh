#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_common.sh
# Shared helpers for the file_fx/delete/* ADF functions.
# (No registration here — this file only defines helpers.)
#
# Reuses from organise: _batch_stat, _ts_to_ymd
# Reuses from viewport: parse_selection

# Non-hidden plain files in the current folder (same scope organise uses).
_fxdel_list_files() {
  local -n _out="$1"
  _out=()
  local f
  for f in "$path"/*; do [ -f "$f" ] && _out+=("$f"); done
}

# Parse a multi-pick reply ("1,3", "2-4", "a" = everything) against a list size.
# Prints space-separated 1-based indices.
_fxdel_pick_indices() {
  local input="${1// /}" max="$2"
  if [[ "${input,,}" == "a" ]]; then
    seq 1 "$max"
  else
    parse_selection "$input" "$max"
  fi
}

# Confirm, then remove everything in $selected_items.
# Prints "Deleted x out of n item(s)" and lists failed items only.
_fxdel_run_selected() {
  local total=${#selected_items[@]}
  [ "$total" -eq 0 ] && { echo "❌ Nothing to delete"; return; }

  # lock gate (l-N): plain y/n when nothing is locked; extra confirmations otherwise
  _lk_confirm_delete "Are you really sure you want to delete $total item(s)? This action can't be undone. (y/n): " || return
  total=${#selected_items[@]}
  # Backup service: a copy goes to the cloud first (Settings → File API → Backup); a failed backup asks before deleting
  _bk_before_delete "${selected_items[@]}" || return

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
