create_files() {
  _bvk_read filelist "Enter filenames (separated by ,): " || return 3     # u = back to Create:
  IFS=',' read -ra files <<< "$filelist"
  local skipped=0
  for file in "${files[@]}"; do
    file="${file#"${file%%[![:space:]]*}"}"; file="${file%"${file##*[![:space:]]}"}"
    [ -z "$file" ] && continue

    local newname
    _bvk_unique_name "$path" "$file"; newname="$_BVK_UQ"      # one naming rule for Create and Copy

    if _bvk_name_too_long "$newname"; then _bvk_name_refuse "$newname" "File"; skipped=$((skipped+1)); continue; fi
    if touch -- "$path/$newname" 2>/dev/null; then
      echo "💫 Created file: $newname"
    else
      echo "🔴 Could not create file: $newname (no permission, or the folder is read-only)"
    fi
  done
  _dsize_invalidate 2>/dev/null
  [ "$skipped" -gt 0 ] && echo " $skipped file(s) not created because their names exceed 255 bytes (the accepted standard)."
  return 0
}

create_dirs() {
  _bvk_read dirlist "Enter folder names (separated by ,): " || return 3   # u = back to Create:
  IFS=',' read -ra dirs <<< "$dirlist"
  local skipped=0 dir newname
  for dir in "${dirs[@]}"; do
    dir="${dir#"${dir%%[![:space:]]*}"}"; dir="${dir%"${dir##*[![:space:]]}"}"      # "a, b" makes "a" and "b", not "a" and " b"
    [ -z "$dir" ] && continue
    _bvk_unique_name "$path" "$dir" dir; newname="$_BVK_UQ"     # an existing folder is never silently "created" again
    if _bvk_name_too_long "$newname"; then _bvk_name_refuse "$newname" "Folder"; skipped=$((skipped+1)); continue; fi
    if mkdir -p -- "$path/$newname" 2>/dev/null; then
      echo "💫 Created folder: $newname"
    else
      echo "🔴 Could not create folder: $newname (no permission, or the folder is read-only)"
    fi
  done
  _dsize_invalidate 2>/dev/null
  [ "$skipped" -gt 0 ] && echo " $skipped folder(s) not created because their names exceed 255 bytes (the accepted standard)."
  return 0
}

handle_create() {
  local rc
  while true; do
    _mc_select cr "Create:" "New folders" "New files" || return $(( $? == 2 ? 1 : 0 ))
    case "$cr" in
      1) create_dirs ;;
      2) create_files ;;
      *) _bvk_invalid ;;
    esac
    rc=$?
    _mc_unwind && return 1
    [ "$rc" -eq 3 ] && continue                  # u at the name prompt: the Create: menu again
    return "$rc"
  done
}
