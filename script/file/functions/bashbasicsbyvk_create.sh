create_files() {
  read -e -p "📄 Enter filenames (separated by ,): " filelist
  IFS=',' read -ra files <<< "$filelist"
  for file in "${files[@]}"; do
    file=$(echo "$file" | xargs)
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

    touch "$path/$newname"
    echo "✅ Created file: $newname"
  done
}

create_dirs() {
  read -e -p "📂 Enter folder names (separated by ,): " dirlist
  IFS=',' read -ra dirs <<< "$dirlist"
  for dir in "${dirs[@]}"; do
    mkdir -p "$path/$dir"
    echo "✅ Created folder: $dir"
  done
}

handle_create() {
  _mc_menu "Create:" -- "New folders" "New files" -- @back_quit
  read -e -r -p "Select: " cr

  case "$cr" in
  u|U) return ;;
  q|Q) _bvk_quit ;;
    1) create_dirs ;;
    2) create_files ;;
    *) echo "Invalid choice" ;;
  esac
}
