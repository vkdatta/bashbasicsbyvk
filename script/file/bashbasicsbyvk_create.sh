create_files() {
  read -p "📄 Enter filenames (separated by ,): " filelist
  IFS=',' read -ra files <<< "$filelist"

  for file in "${files[@]}"; do
    # Strip leading/trailing whitespace
    file="${file#"${file%%[![:space:]]*}"}"
    file="${file%"${file##*[![:space:]]}"}"

    [ -z "$file" ] && continue

    local base ext newname count
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
      count=$((count + 1))
    done

    touch "$path/$newname"
    echo "✅ Created file: $newname"
  done
}

create_dirs() {
  read -p "📂 Enter folder names (separated by ,): " dirlist
  IFS=',' read -ra dirs <<< "$dirlist"

  for dir in "${dirs[@]}"; do
    # Strip leading/trailing whitespace
    dir="${dir#"${dir%%[![:space:]]*}"}"
    dir="${dir%"${dir##*[![:space:]]}"}"

    [ -z "$dir" ] && continue

    mkdir -p "$path/$dir"
    echo "✅ Created folder: $dir"
  done
}

handle_create() {
  builtin printf "Create:\n1) New folders\n2) New files\n"
  read -p "Choice: " cr

  if [[ "$cr" == "1" ]]; then
    create_dirs

  elif [[ "$cr" == "2" ]]; then
    create_files

  else
    read -p "Enter names (separated by ,): " namelist
    IFS=',' read -ra names <<< "$namelist"

    for name in "${names[@]}"; do
      # Strip leading/trailing whitespace
      name="${name#"${name%%[![:space:]]*}"}"
      name="${name%"${name##*[![:space:]]}"}"

      [ -z "$name" ] && continue

      # Has extension → file, otherwise → directory
      if [[ "$name" == *.* && "$name" != .* ]]; then
        local base ext newname count

        base="${name%.*}"
        ext="${name##*.}"

        count=1
        newname="$name"

        while [ -e "$path/$newname" ]; do
          newname="${base} (${count}).${ext}"
          count=$((count + 1))
        done

        touch "$path/$newname"
        echo "✅ Created file: $newname"
      else
        mkdir -p "$path/$name"
        echo "✅ Created folder: $name"
      fi
    done
  fi
}