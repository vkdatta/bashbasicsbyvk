delete_items() {
  local _ok _gate
  while :; do
    _ok=false
    if $imaginary_mode; then
      select_imaginary_items_common "$path" "$group_prefix" "🚮 Delete" && _ok=true
    else
      select_items_common "🚮 Delete" allow_a && _ok=true
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
  # rm can fail part-way (a read-only folder, a permission, a busy mount): what is still there is reported, never called deleted
  local _del_ok=0 _del_err
  local -a _del_bad=()
  for item in "${selected_items[@]}"; do
    _del_err="$(rm -rf -- "$item" 2>&1)"
    if [ -e "$item" ] || [ -L "$item" ]; then
      _del_bad+=("${item##*/} — ${_del_err:-could not be removed}")
    else
      _del_ok=$((_del_ok+1))
      _carry_forget "$item"
    fi
  done
  _dsize_invalidate 2>/dev/null                 # folder sizes (this folder and every one above it) are no longer true
  if [ "${#_del_bad[@]}" -eq 0 ]; then
    echo "💫 Selected items deleted. I can feel the space 🚀"
  else
    echo "🔴 Deleted $_del_ok out of ${#selected_items[@]} item(s). Not deleted (${#_del_bad[@]}):"
    for _del_err in "${_del_bad[@]}"; do echo "  • $_del_err"; done
  fi
}
