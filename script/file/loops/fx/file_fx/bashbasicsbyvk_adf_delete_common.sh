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

  local confirm
  read -p "Are you really sure you want to delete $total item(s)? This action can't be undone. (y/n): " confirm
  if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo "🚫 Deletion cancelled"
    return
  fi

  local ok=0 item err
  local -a failed=()
  for item in "${selected_items[@]}"; do
    if err=$(rm -rf -- "$item" 2>&1); then
      ok=$((ok+1))
    else
      failed+=("${item##*/} — ${err:-rm failed}")
    fi
  done

  if [ ${#failed[@]} -eq 0 ]; then
    echo "✅ Deleted $ok out of $total item(s). I can feel the space 🚀"
  else
    echo "⚠️  Deleted $ok out of $total item(s)."
    echo "❌ Failed (${#failed[@]}):"
    for item in "${failed[@]}"; do echo "  • $item"; done
  fi
}
