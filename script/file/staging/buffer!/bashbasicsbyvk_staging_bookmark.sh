source "bashbasicsbyvk_staging_helpers.sh"

# Stage / apply logic lives in _sp_stage_buffer / _sp_apply_buffer (helpers.sh).
staging_bookmark_stage() { _sp_stage_buffer bm "$1" "$2"; }

# Apply: create a .swlink file at $dest for every path in $file.
# _swlink_write is defined in bashbasicsbyvk_switch.sh and is always
# sourced before this is called.
staging_bookmark_apply() {
  local file="$1" dest="$2"

  local -a list=()
  _sp_load list "$file"
  [ ${#list[@]} -eq 0 ] && return 0

  local -a live=()
  local missing=0 p
  for p in "${list[@]}"; do
    if [ -e "$p" ]; then
      live+=("$p")
    else
      missing=$((missing+1))
      echo "  ⚠️  Skipping missing item (no longer exists): $p"
    fi
  done

  if [ ${#live[@]} -eq 0 ]; then
    echo "ℹ️  Bookmark buffer had no valid items to apply"
    return 0
  fi

  echo "⚙️  Creating bookmark links (${#live[@]} item(s)) → $dest"
  for p in "${live[@]}"; do
    local display_name
    display_name=$(basename "$p")
    _swlink_write "$dest" "$p" "$display_name" >/dev/null
    echo "  🔖 Bookmarked: $display_name  →  $p"
  done
}
