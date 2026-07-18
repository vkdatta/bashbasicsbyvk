handle_file() {
    local file="$1"
    while true; do
        echo
        echo "📄 File selected: $(basename "$file")"
        echo "What would you like to do with the file?"
        echo "0) Run"
        echo "1) View"
        echo "2) Edit"
        echo "3) Copy Content"
        echo "4) Delete Content"
        echo "5) Erase Content"
        echo "6) Replace With Clipboard Content"
        echo "7) Rename File" 
        echo "8) Share"
        echo "u) Back to Previous Menu"
        echo "q/h) Back to Home/Exit"
        read -p "Enter choice: " action

        case "$action" in
            0)
                run_file "$file"
                return 1
                ;;
            1)
                force_open "$file"
                return 1
                ;;
            2)
                nano "$file"
                return 1
                ;;
            3)
                bashbasicsbyvk_copy "$file"
                return 1
                ;;
            4)
                bashbasicsbyvk_delete "$file"
                return 1
                ;;
            5)
                bashbasicsbyvk_erase "$file"
                return 1
                ;;
            6)
                bashbasicsbyvk_overwrite "$file"
                return 1
                ;;
            7)
                rename_item "$file"
                return 1
                ;;
            8)
                force_share "$file"
                return 1
                ;;
            u|U)
                return 1
                ;;
            q|Q|h|H)
                exit 0
                ;;
            *)
                echo "❌ Invalid option. Try again."
                ;;
        esac
    done
}

determine_shared_dir() {
    if [ -d "$HOME/storage/shared" ]; then
        echo "$HOME/storage/shared/Download"
    else
        echo "/sdcard/Download"
    fi
}

force_open() {
    local src="$1"
    if [ ! -e "$src" ]; then
        echo "❌ File not found: $src"
        return 1
    fi
    local shared_dir
    shared_dir="$(determine_shared_dir)"
    mkdir -p "$shared_dir"
    local base ts dest
    base=$(basename "$src")
    ts=$(date +%s)
    dest="$shared_dir/${ts}_$base"
    cp -f -- "$src" "$dest" || { echo "❌ Failed to copy to shared storage"; return 1; }
    if command -v termux-open >/dev/null 2>&1; then
        termux-open "$dest" && return 0
    fi
    if command -v am >/dev/null 2>&1; then
        local mime
        if command -v file >/dev/null 2>&1; then
            mime=$(file --mime-type -b "$dest" 2>/dev/null || echo "application/octet-stream")
        else
            mime="application/octet-stream"
        fi
        am start -a android.intent.action.VIEW -d "file://$dest" -t "$mime" >/dev/null 2>&1 || echo "⚠️ Open via am failed"
        return 0
    fi
    echo "❌ No suitable open method available"
    return 1
}

force_share() {
    local src="$1"
    if [ ! -e "$src" ]; then
        echo "❌ File not found: $src"
        return 1
    fi
    local shared_dir
    shared_dir="$(determine_shared_dir)"
    mkdir -p "$shared_dir"
    local base ts dest
    base=$(basename "$src")
    ts=$(date +%s)
    dest="$shared_dir/${ts}_$base"
    cp -f -- "$src" "$dest" || { echo "❌ Failed to copy to shared storage"; return 1; }
    if command -v termux-share >/dev/null 2>&1; then
        termux-share -a send -c file "$dest" 2>/dev/null || termux-share "$dest"
        return 0
    fi
    if command -v am >/dev/null 2>&1; then
        local mime
        if command -v file >/dev/null 2>&1; then
            mime=$(file --mime-type -b "$dest" 2>/dev/null || echo "application/octet-stream")
        else
            mime="application/octet-stream"
        fi
        am start -a android.intent.action.SEND -t "$mime" --es android.intent.extra.SUBJECT "$(basename "$dest")" --stream "file://$dest" >/dev/null 2>&1 2>/dev/null || {
            am start -a android.intent.action.SEND -t "$mime" --es android.intent.extra.STREAM "file://$dest" >/dev/null 2>&1 || echo "⚠️ Share via am failed"
        }
        return 0
    fi
    echo "❌ No suitable share method available"
    return 1
}



run_file() {
    local file="$1"
    if [ ! -e "$file" ]; then
        echo "❌ File not found: $file"
        return 1
    fi
    if [ -x "$file" ]; then
        read -p "⚙️ File is executable. Run directly? (y/N): " yn
        if [[ $yn =~ ^[Yy]$ ]]; then
            "$file"
            return $?
        fi
    fi
    local firstline interpreter exe
    firstline=$(head -n1 "$file" 2>/dev/null)
    if [[ "$firstline" =~ ^\#! ]]; then
        interpreter=$(echo "$firstline" | cut -c3- | awk '{print $1}')
        exe=$(basename "$interpreter")
        if command -v "$exe" >/dev/null 2>&1; then
            read -p "⚙️ Run with shebang interpreter ($exe)? (y/N): " yn2
            if [[ $yn2 =~ ^[Yy]$ ]]; then
                "$exe" "$file"
                return $?
            fi
        fi
    fi
    local ext
    ext="${file##*.}"
    case "$ext" in
        py)
            if command -v python3 >/dev/null 2>&1; then python3 "$file"; elif command -v python >/dev/null 2>&1; then python "$file"; else echo "❌ python not found"; fi
            ;;
        pyc)
            echo "❌ Cannot run .pyc directly in Termux without proper interpreter setup"
            ;;
        js|mjs)
            if command -v node >/dev/null 2>&1; then node "$file"; elif command -v deno >/dev/null 2>&1; then deno run "$file"; else echo "❌ node/deno not found"; fi
            ;;
        ts)
            if command -v deno >/dev/null 2>&1; then deno run "$file"; elif command -v ts-node >/dev/null 2>&1; then ts-node "$file"; else echo "❌ ts-node/deno not found"; fi
            ;;
        sh|bash)
            if command -v bash >/dev/null 2>&1; then bash "$file"; else sh "$file"; fi
            ;;
        zsh)
            if command -v zsh >/dev/null 2>&1; then zsh "$file"; else echo "❌ zsh not found"; fi
            ;;
        php)
            if command -v php >/dev/null 2>&1; then php "$file"; else echo "❌ php not found"; fi
            ;;
        pl)
            if command -v perl >/dev/null 2>&1; then perl "$file"; else echo "❌ perl not found"; fi
            ;;
        rb)
            if command -v ruby >/dev/null 2>&1; then ruby "$file"; else echo "❌ ruby not found"; fi
            ;;
        jar)
            if command -v java >/dev/null 2>&1; then java -jar "$file"; else echo "❌ java not found"; fi
            ;;
        class)
            if command -v java >/dev/null 2>&1; then classname="$(basename "${file%.*}")"; java -cp "$(dirname "$file")" "$classname"; else echo "❌ java not found"; fi
            ;;
        java)
            if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
                javac "$file" && classname="$(basename "${file%.*}")" && java -cp "$(dirname "$file")" "$classname"
            else
                echo "❌ javac/java not found"
            fi
            ;;
        c)
            if command -v gcc >/dev/null 2>&1; then
                tmp="$HOME/tmp_exec_$RANDOM"
                gcc "$file" -o "$tmp" && "$tmp"
                rm -f "$tmp"
            else
                echo "❌ gcc not found"
            fi
            ;;
        cpp|cc|cxx|c++|c\+\+)
            if command -v g++ >/dev/null 2>&1; then
                tmp="$HOME/tmp_exec_$RANDOM"
                g++ "$file" -o "$tmp" && "$tmp"
                rm -f "$tmp"
            else
                echo "❌ g++ not found"
            fi
            ;;
        go)
            if command -v go >/dev/null 2>&1; then go run "$file"; else echo "❌ go not found"; fi
            ;;
        rs)
            if command -v rustc >/dev/null 2>&1; then
                tmp="$HOME/tmp_exec_$RANDOM"
                rustc "$file" -o "$tmp" && "$tmp"
                rm -f "$tmp"
            elif command -v cargo >/dev/null 2>&1; then
                echo "ℹ️ For cargo projects use cargo run inside the project"
            else
                echo "❌ rustc/cargo not found"
            fi
            ;;
        swift)
            if command -v swift >/dev/null 2>&1; then swift "$file"; elif command -v swiftc >/dev/null 2>&1; then tmp="$HOME/tmp_exec_$RANDOM"; swiftc "$file" -o "$tmp" && "$tmp"; else echo "❌ swift not found"; fi
            ;;
        kt|kts|kotlin)
            if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
                out="$HOME/tmp_kt_$RANDOM.jar"
                kotlinc "$file" -include-runtime -d "$out" && java -jar "$out"
                rm -f "$out"
            else
                echo "❌ kotlinc/java not found"
            fi
            ;;
        r)
            if command -v Rscript >/dev/null 2>&1; then Rscript "$file"; else echo "❌ Rscript not found"; fi
            ;;
        jl)
            if command -v julia >/dev/null 2>&1; then julia "$file"; else echo "❌ julia not found"; fi
            ;;
        lua)
            if command -v lua >/dev/null 2>&1; then lua "$file"; else echo "❌ lua not found"; fi
            ;;
        hs)
            if command -v runhaskell >/dev/null 2>&1; then runhaskell "$file"; elif command -v ghc >/dev/null 2>&1; then tmp="$HOME/tmp_exec_$RANDOM"; ghc -o "$tmp" "$file" && "$tmp"; else echo "❌ runhaskell/ghc not found"; fi
            ;;
        coffee)
            if command -v coffee >/dev/null 2>&1; then coffee "$file"; else echo "❌ coffee not found"; fi
            ;;
        dart)
            if command -v dart >/dev/null 2>&1; then dart "$file" || dart run "$file"; else echo "❌ dart not found"; fi
            ;;
        scala)
            if command -v scala >/dev/null 2>&1; then scala "$file"; else echo "❌ scala not found"; fi
            ;;
        md|markdown)
            if command -v glow >/dev/null 2>&1; then glow "$file"; elif command -v less >/dev/null 2>&1; then less "$file"; else cat "$file"; fi
            ;;
        txt|log|cfg|conf)
            ${PAGER:-less} "$file"
            ;;
        zip|tar|gz|tgz|bz2|xz|7z)
            echo "📦 Archive file. Use appropriate extraction command (unzip, tar -xvf, 7z x ...) in shell."
            ;;
        pdf|epub|mobi|azw3)
            force_open "$file"
            ;;
        png|jpg|jpeg|gif|bmp|webp|svg)
            force_open "$file"
            ;;
        doc|docx|xls|xlsx|ppt|pptx)
            force_open "$file"
            ;;
        *)
            if command -v file >/dev/null 2>&1; then
                mimetype=$(file --mime-type -b "$file" 2>/dev/null || echo "")
            else
                mimetype=""
            fi
            if [ -n "$mimetype" ] && [[ "$mimetype" == text/* ]]; then
                ${PAGER:-less} "$file"
            else
                if command -v termux-open >/dev/null 2>&1; then
                    force_open "$file"
                else
                    echo "❓ Unknown extension and no viewer available"
                fi
            fi
            ;;
    esac
}

rename_item() {
  local target="$1"
  local dir newname
  if [ -d "$target" ]; then
    dir=$(dirname -- "$target")
    read -p "📝 Enter new folder name for '$(basename "$target")': " newname
    mv -v "$target" "$dir/$newname"
  elif [ -f "$target" ]; then
    dir=$(dirname -- "$target")
    read -p "📝 Enter new file name for '$(basename "$target")': " newname
    mv -v "$target" "$dir/$newname"
  else
    echo "❌ Cannot rename: '$target' not found." >&2
    return 1
  fi
}

handle_rename() {
  echo "Rename:"
  echo "1) Select item number to rename (files/folders in current path)"
  echo "2) Rename current path/folder"
  read -p "Choice [1-2]: " ren_choice
  case "$ren_choice" in
    1)
      if $imaginary_mode; then
        echo "Select group number to browse for rename:"
        read -p "Group number: " gnum
        if [[ $gnum =~ ^[0-9]+$ ]] && [ "$gnum" -ge 1 ] && [ "$gnum" -le "${#imaginary_map[@]}" ]; then
          ch="${imaginary_map[$((gnum-1))]}"
          ch_lower="${ch,,}"
          items=()
          while IFS= read -r -d '' _f; do
            _bn="${_f##*/}"
            [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
            ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
            _bn_lower="${_bn,,}"
            [[ "$_bn_lower" != "$group_prefix"* ]] && continue
            _next="${_bn_lower:${#group_prefix}:1}"
            if [ "$ch" == "#" ]; then
              [[ "$_next" =~ ^[a-z]$ ]] && continue
            else
              [[ "$_next" != "$ch_lower" ]] && continue
            fi
            items+=("$_f")
          done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
          idx=1
          for item in "${items[@]}"; do
            [ -d "$item" ] && icon="📁" || icon="📄"
            printf "%2d) %s %s\n" "$idx" "$icon" "$(basename "$item")"
            idx=$((idx+1))
          done
          read -p "Enter item number: " num
          if [[ $num =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#items[@]}" ]; then
            rename_item "${items[$((num-1))]}"
          else
            echo "❌ Invalid number"
          fi
        else
          echo "❌ Invalid group"
        fi
      elif [ ${#items[@]} -eq 0 ]; then
        echo "❌ No items to rename"
      else
        read -p "Enter item number: " num
        if [[ $num =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#items[@]}" ]; then
          rename_item "${items[$((num-1))]}"
        else
          echo "❌ Invalid number"
        fi
      fi
      ;;
    2)
      rename_item "$path"
      ;;
    *)
      echo "❌ Invalid choice"
      ;;
  esac
}
