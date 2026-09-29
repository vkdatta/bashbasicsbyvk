delete_items() {
  local _ok=false
  if $imaginary_mode; then
    select_imaginary_items_common "$path" "$group_prefix" && _ok=true
  else
    select_items_common "DELETE" && _ok=true
  fi
  if $_ok; then
    local _has_shortcuts=false
    for _si in "${selected_items[@]}"; do
      [[ "${_si##*/}" == *.shortcut ]] && _has_shortcuts=true && break
    done
    if $_has_shortcuts; then
      echo "Note: shortcut(s) selected — only the shortcut pointer will be deleted, not the original file/folder."
    fi

    read -p "Are you really sure you want to delete the selected files? This action can't be undone. (y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
      echo "🚫 Deletion cancelled"
      return
    fi
    for item in "${selected_items[@]}"; do
      rm -rf -- "$item"
    done
    echo "✅ Selected items deleted. I can feel the space 🚀"
  fi
}
