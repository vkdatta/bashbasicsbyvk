delete_items() {
  local _ok _gate
  while :; do
    _ok=false
    if $imaginary_mode; then
      select_imaginary_items_common "$path" "$group_prefix" && _ok=true
    else
      select_items_common "DELETE" allow_a && _ok=true
    fi
    $_ok || return 0
    local _has_shortcuts=false
    for _si in "${selected_items[@]}"; do
      [[ "${_si##*/}" == *.shortcut ]] && _has_shortcuts=true && break
    done
    if $_has_shortcuts; then
      echo "Note: shortcut(s) selected — only the shortcut pointer will be deleted, not the original file/folder."
    fi

    # ONE gate: Confirm delete (lock gate l-N) → Back up before deleting (Settings → File API → Backup).
    # u = one question back: from Back up to Confirm delete, from Confirm delete to the selection.
    _lk_delete_gate "Are you really sure you want to delete the selected files? This action can't be undone. (y/n): "; _gate=$?
    case "$_gate" in
      0) break ;;
      1) continue ;;
      *) return "$_gate" ;;
    esac
  done
  for item in "${selected_items[@]}"; do
    rm -rf -- "$item" && _carry_forget "$item"
  done
  echo "💫 Selected items deleted. I can feel the space 🚀"
}
