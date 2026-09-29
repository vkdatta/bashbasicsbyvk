create_files() {
  read -p "📄 Enter filenames (separated by ,): " filelist
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
  read -p "📂 Enter folder names (separated by ,): " dirlist
  IFS=',' read -ra dirs <<< "$dirlist"
  for dir in "${dirs[@]}"; do
    mkdir -p "$path/$dir"
    echo "✅ Created folder: $dir"
  done
}

handle_create() {
  echo
  echo "Create:"
  echo "1) New folders"
  echo "2) New files"
  echo
  read -r -p "Choice [1-2]: " cr

  case "$cr" in
    1) create_dirs ;;
    2) create_files ;;
    *) echo "Invalid choice" ;;
  esac
}
