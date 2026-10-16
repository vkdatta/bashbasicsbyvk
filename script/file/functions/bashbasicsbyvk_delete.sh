delete_items() {
  local _ok=false
  if $imaginary_mode; then
    select_imaginary_items_common "$path" "$group_prefix" && _ok=true
  else
    select_items_common "DELETE" allow_a && _ok=true
  fi
  if $_ok; then
    local _has_shortcuts=false
    for _si in "${selected_items[@]}"; do
      [[ "${_si##*/}" == *.shortcut ]] && _has_shortcuts=true && break
    done
    if $_has_shortcuts; then
      echo "Note: shortcut(s) selected — only the shortcut pointer will be deleted, not the original file/folder."
    fi

    # lock gate (l-N): plain y/n when nothing is locked; extra confirmations otherwise
    _lk_confirm_delete "Are you really sure you want to delete the selected files? This action can't be undone. (y/n): " || return
    # Backup service: a copy goes to the cloud first (Settings → File API → Backup); a failed backup asks before deleting
    _bk_before_delete "${selected_items[@]}" || return
    for item in "${selected_items[@]}"; do
      rm -rf -- "$item" && _carry_forget "$item"
    done
    echo "✅ Selected items deleted. I can feel the space 🚀"
  fi
}
