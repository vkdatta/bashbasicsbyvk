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
  builtin printf "Create:\n1) New folders\n2) New files\n"
  read -p "Choice: " cr
  [[ "$cr" == "1" ]] && create_dirs
  [[ "$cr" == "2" ]] && create_files
}