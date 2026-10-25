_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffers"

copy_to_clipboard() {
    local content="$1"

    printf "%s" "$content" | bashbasicsbyvk_copy
}

handle_file() {
    local file="$1" lab_run lab_lock

    while true; do
        lab_run="Run";       _arc_detect "$file" && lab_run="Extract"        # an archive is extracted, anything else is run
        lab_lock="Lock File"; _lk_file_locked "$file" && lab_lock="Unlock File"   # one row: it does whichever applies
        _mc_header "📄 File selected: $(basename "$file")" \
                   "What would you like to do with the file?"
        _mc_options 0 "$lab_run" "View" "Edit" "Copy Content" "Delete File" \
                      "Erase Content" "Replace With Clipboard Content" \
                      "Rename File" "Share" "$lab_lock" "Copy Name" \
                      "Copy File Path" "Go To Parent Folder"
        _mc_footer @file_menu

        read -e -p "Select: " action

        case "$action" in
            0) run_file "$file"; return 1 ;;
            1) force_open "$file"; return 1 ;;
            2) nano "$file"; return 1 ;;
            3) bashbasicsbyvk_copy "$file"; return 1 ;;
            4) bashbasicsbyvk_delete "$file"; return 1 ;;
            5) bashbasicsbyvk_erase "$file"; return 1 ;;
            6) bashbasicsbyvk_overwrite "$file"; return 1 ;;
            7) rename_item "$file"; return 1 ;;
            8) force_share "$file"; return 1 ;;
            9) _lk_file_toggle "$file"; return 1 ;;
            10) copy_to_clipboard "${file##*/}"; return 1 ;;
            11) _file_abs_path "$file"; copy_to_clipboard "$_FILE_ABS"; return 1 ;;
            12) _file_goto_parent "$file"; return 1 ;;
            u|U) return 1 ;;
            h|H) home_menu; return 1 ;;
            q|Q) _bvk_quit; return 1 ;;
            *)
                _bvk_invalid
                ;;
        esac
    done
}

# _file_abs_path <file> → _FILE_ABS  (absolute, no forks)
_file_abs_path() {
    _FILE_ABS="$1"
    [[ "$_FILE_ABS" == /* ]] || _FILE_ABS="$PWD/$_FILE_ABS"
}

# "Go To Parent Folder": the list moves to the folder that holds the file. From an inner loop (find, switch, fx) it also
# closes back to the main loop, which is where the list lives; `o <file>` carries on into the main loop instead of exiting.
_file_goto_parent() {
    local d
    _file_abs_path "$1"
    d="${_FILE_ABS%/*}"; [ -n "$d" ] || d="/"
    if [ ! -d "$d" ]; then echo "❌ Folder not found: $d"; return 1; fi
    path="$(get_abs_path "$d")" || return 1
    group_prefix=""; force_show=false
    _BVK_GO_PARENT=1
    _bvk_quit
}

determine_shared_dir() {
    if [ -d "$HOME/storage/shared" ]; then
        echo "$HOME/storage/shared/Download"
    else
        echo "/sdcard/Download"
    fi
}

# _copy_to_shared <file>   copies it into the shared Download folder as <timestamp>_<name>; the copy's path is left in _SHARED_COPY.
# returns 1 (with a message) when the file is missing or the copy fails.  Used by force_open and force_share.
_copy_to_shared() {
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
    _SHARED_COPY="$dest"
}

force_open() {
    local dest
    _copy_to_shared "$1" || return 1
    dest="$_SHARED_COPY"
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
        am start -a android.intent.action.VIEW -d "file://$dest" -t "$mime" >/dev/null 2>&1 || echo "🔴 Open via am failed"
        return 0
    fi
    echo "❌ No suitable open method available"
    return 1
}

force_share() {
    local dest
    _copy_to_shared "$1" || return 1
    dest="$_SHARED_COPY"
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
            am start -a android.intent.action.SEND -t "$mime" --es android.intent.extra.STREAM "file://$dest" >/dev/null 2>&1 || echo "🔴 Share via am failed"
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
    if _arc_detect "$file"; then            # an archive is opened, never run: extracted next to itself
        local _ab="${file%/*}"; [ "$_ab" = "$file" ] && _ab="$PWD"; [ -n "$_ab" ] || _ab="/"
        _arc_dest_base="$_ab" _decompress_paths "$file"
        return $?
    fi
    if [ -x "$file" ]; then
        _bvk_yn yn "File is executable. Run directly?" -d n
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
            _bvk_yn yn2 "Run with shebang interpreter ($exe)?" -d n
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
            if command -v python3 >/dev/null 2>&1; then python3 -u "$file"; elif command -v python >/dev/null 2>&1; then python -u "$file"; else echo "❌ python not found"; fi
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
                echo "📜 For cargo projects use cargo run inside the project"
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
        zip|tar|gz|tgz|bz2|xz|7z|zst|lz4|skill)
            echo "📦 '${file##*/}' is not a readable archive ($_ARC_WHY) — nothing to extract."
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