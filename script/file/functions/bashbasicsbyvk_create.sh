create_files() {
  read -e -p "Enter filenames (separated by ,): " filelist || return 3     # u = back to Create:
  IFS=',' read -ra files <<< "$filelist"
  local skipped=0
  for file in "${files[@]}"; do
    file="${file#"${file%%[![:space:]]*}"}"; file="${file%"${file##*[![:space:]]}"}"
    [ -z "$file" ] && continue

    local base ext newname count target
    base="${file%.*}"
    ext="${file##*.}"
    [[ "$file" == "$ext" ]] && ext=""

    count=1
    newname="$file"
    while [ -e "$path/$newname" ]; do
      if [ -n "$ext" ]; then
        newname="${base} (${count}).${ext}"
      else
        newname="${base} (${count})"
      fi
      count=$((count+1))
    done

    if _bvk_name_too_long "$newname"; then _bvk_name_refuse "$newname" "File"; skipped=$((skipped+1)); continue; fi
    touch "$path/$newname"
    echo "💫 Created file: $newname"
  done
  [ "$skipped" -gt 0 ] && echo " $skipped file(s) not created because their names exceed 255 bytes (the accepted standard)."
  return 0
}

create_dirs() {
  read -e -p "Enter folder names (separated by ,): " dirlist || return 3   # u = back to Create:
  IFS=',' read -ra dirs <<< "$dirlist"
  local skipped=0
  for dir in "${dirs[@]}"; do
    if _bvk_name_too_long "$dir"; then _bvk_name_refuse "$dir" "Folder"; skipped=$((skipped+1)); continue; fi
    mkdir -p "$path/$dir"
    echo "💫 Created folder: $dir"
  done
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
