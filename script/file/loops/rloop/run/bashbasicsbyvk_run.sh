_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffers"

copy_to_clipboard() {
    local content="$1"

    printf "%s" "$content" | bashbasicsbyvk_copy
}

handle_file() {
    local file="$1" lab_run lab_lock action

    while true; do
        lab_run="Run";       _arc_detect "$file" && lab_run="Extract"        # an archive is extracted, anything else is run
        lab_lock="Lock File"; _lk_file_locked "$file" && lab_lock="Unlock File"   # one row: it does whichever applies
        _mc_header "📄 File selected: $(basename "$file")" \
                   "What would you like to do with the file?"
        _mc_options 0 "$lab_run" "View" "Edit" "Copy Content" "Delete File" \
                      "Erase Content" "Replace With Clipboard Content" \
                      "Rename File" "Share" "$lab_lock" "Copy Name" \
                      "Copy File Path" "Go To Parent Folder" "Info"
        _mc_footer @file_menu

        read -e -p "Select: " action || return 1          # EOF (the terminal closed): leave, never spin on "invalid"

        case "$action" in
            0) run_file "$file"; return 1 ;;
            1) force_open "$file"; return 1 ;;
            2) _hf_tracked "$file" _hf_edit "$file"; return 1 ;;
            3) bashbasicsbyvk_copy "$file"; return 1 ;;
            4) bashbasicsbyvk_delete "$file"; return 1 ;;
            5) _hf_tracked "$file" bashbasicsbyvk_erase "$file"; return 1 ;;
            6) _hf_tracked "$file" bashbasicsbyvk_overwrite "$file"; return 1 ;;
            7) _RN_NEW_PATH=""; rename_item "$file"; [ -n "$_RN_NEW_PATH" ] && _rc_record "$_RN_NEW_PATH"; return 1 ;;
            8) force_share "$file"; return 1 ;;
            9) _lk_file_toggle "$file"; return 1 ;;
            10) copy_to_clipboard "${file##*/}"; return 1 ;;
            11) _file_abs_path "$file"; copy_to_clipboard "$_FILE_ABS"; return 1 ;;
            12) _file_goto_parent "$file"; return 1 ;;
            13) _hf_info "$file"; return 1 ;;
            u|U) return 1 ;;
            h|H) home_menu; return 1 ;;
            q|Q) _bvk_quit; return 1 ;;
            *)
                _bvk_invalid
                ;;
        esac
    done
}

# "Info": the same screen as the i- command (info printed, then save in Excel / copy it) for this one file.
_hf_info() {
    _file_abs_path "$1"
    _fi_show "$_FILE_ABS"
}

_hf_edit() { if command -v nano >/dev/null 2>&1; then nano "$1"; else "${EDITOR:-vi}" "$1"; fi; }

# _hf_tracked FILE cmd args...   run the action; when it really changed FILE (opening the editor and leaving again does not), FILE joins Recents.
# Used more than 5 times, it gets locked for good (bashbasicsbyvk_track.sh).
_hf_tracked() {
    local f="$1" before after; shift
    before=$(_fav_mtime "$f")
    "$@"
    after=$(_fav_mtime "$f")
    [ "$before" != "$after" ] && [ -e "$f" ] && _rc_record "$f"
    return 0
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

# _rf_mime <file>   the MIME type in _RF_MIME ("" when unknown); `file` is optional, so no tool = unknown
_rf_mime() {
    _RF_MIME=""
    if command -v file >/dev/null 2>&1; then _RF_MIME=$(file --mime-type -b -- "$1" 2>/dev/null); fi
    return 0
}

# _rf_is_text <file>   0 when the file is readable text (or empty): by its MIME type, else by looking for binary bytes (grep -I)
_rf_is_text() {
    _rf_mime "$1"
    case "$_RF_MIME" in
        text/*|inode/x-empty|application/x-empty|application/json|application/xml|application/javascript) return 0 ;;
        ?*) return 1 ;;
    esac
    [ ! -s "$1" ] || LC_ALL=C grep -qIm1 '' -- "$1" 2>/dev/null
}

# _rf_page <file>   shows a text file in $PAGER (default less); plain cat when no pager is installed
_rf_page() {
    local p="${PAGER:-less}"
    if command -v "${p%% *}" >/dev/null 2>&1; then $p "$1"; else cat -- "$1"; fi
}

# _rf_is_elf <file>   0 when the first four bytes are the ELF magic (a compiled program)
_rf_is_elf() {
    local _m=""    # builtin read, no head | od | tr (3 processes, ~75 ms on a phone); the magic has no NUL byte, so read keeps it whole
    [ -f "$1" ] && [ -r "$1" ] || return 1
    LC_ALL=C read -r -N4 _m < "$1" 2>/dev/null
    [ "$_m" = $'\x7fELF' ]
}

# _rf_shebang <file>   reads the first line (at most 256 bytes: a binary has no "line"; NUL and CR are dropped, so no bash warning and a CRLF script works)
# and splits "#!/usr/bin/env -S python3 -u" into _RF_EXE=python3 and _RF_ARGS=(-u).  Returns 1 when there is no usable shebang.
_rf_shebang() {
    local first tok
    local -a parts=()
    _RF_EXE=""; _RF_ARGS=()
    LC_ALL=C IFS= read -r -n 256 first < "$1" 2>/dev/null    # builtin: no head | head | tr (3 processes); stops at the first newline, drops NUL
    first="${first//$'\r'/}"
    [[ "$first" == '#!'* ]] || return 1
    read -r -a parts <<< "${first#\#!}"
    [ "${#parts[@]}" -gt 0 ] || return 1
    _RF_EXE="${parts[0]##*/}"
    parts=("${parts[@]:1}")
    if [ "$_RF_EXE" = env ]; then                   # "env" only looks the real program up: skip its options and NAME=value words
        _RF_EXE=""
        for tok in "${parts[@]}"; do
            if [ -z "$_RF_EXE" ]; then
                [[ "$tok" == -* || "$tok" == *=* ]] && continue
                _RF_EXE="$tok"
            else
                _RF_ARGS+=("$tok")
            fi
        done
    else
        _RF_ARGS=("${parts[@]}")
    fi
    [ -n "$_RF_EXE" ]
}

# _copy_to_shared <file>   copies it into the shared Download folder as <timestamp>_<name>; the copy's path is left in _SHARED_COPY.
# returns 1 (with a message) when the file is missing or the copy fails.  Used by force_open and force_share.
_copy_to_shared() {
    local src="$1" shared_dir base ts dest
    if [ ! -e "$src" ]; then
        echo "❌ File not found: $src"
        return 1
    fi
    shared_dir="$(determine_shared_dir)"
    if ! mkdir -p -- "$shared_dir" 2>/dev/null || [ ! -w "$shared_dir" ]; then
        echo "❌ Cannot write to $shared_dir (Termux: run termux-setup-storage)"
        return 1
    fi
    base=$(basename "$src")
    ts=$(date +%s)
    dest="$shared_dir/${ts}_$base"
    [ -e "$dest" ] && dest="$shared_dir/${ts}_${RANDOM}_$base"          # two copies in the same second must not overwrite each other
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
        _rf_mime "$dest"
        am start -a android.intent.action.VIEW -d "file://$dest" -t "${_RF_MIME:-application/octet-stream}" >/dev/null 2>&1 && return 0
        echo "🔴 Open via am failed"
        return 1
    fi
    echo "❌ No suitable open method available"
    return 1
}

force_share() {
    local dest
    _copy_to_shared "$1" || return 1
    dest="$_SHARED_COPY"
    if command -v termux-share >/dev/null 2>&1; then
        termux-share -a send "$dest" && return 0                         # one attempt: a second call would pop a second share sheet
        echo "🔴 Share via termux-share failed"
    fi
    if command -v am >/dev/null 2>&1; then
        _rf_mime "$dest"
        am start -a android.intent.action.SEND -t "${_RF_MIME:-application/octet-stream}" \
            --eu android.intent.extra.STREAM "file://$dest" \
            --es android.intent.extra.SUBJECT "${dest##*/}" \
            --grant-read-uri-permission >/dev/null 2>&1 && return 0
        echo "🔴 Share via am failed"
        return 1
    fi
    echo "❌ No suitable share method available"
    return 1
}

# Every program run_file starts (a script, a binary, a compiled file) goes through here.  It is not our app's environment: the loading bar covers only its
# start-up, up to its first write, and never draws over what the program shows (see _sl_launch in smartload.sh).
_rf_go() {
    if declare -F _sl_launch >/dev/null 2>&1; then _sl_launch "${_RF_NAME:-}" "$@"; else "$@"; fi
}

# _rf_build_run <source> <compiler and its options...>   builds  "<compiler...> -o <temp> <source>", runs the result through _rf_go, always removes it,
# and returns the program's status (a failed build returns the compiler's)
_rf_build_run() {
    local src="$1" tmp rc
    shift
    tmp=$(mktemp "${TMPDIR:-$HOME}/bvk_exec.XXXXXX") || { echo "❌ Cannot create a temporary file"; return 1; }
    if "$@" -o "$tmp" "$src"; then
        chmod +x "$tmp"
        _rf_go "$tmp"; rc=$?
    else
        rc=$?
    fi
    rm -f -- "$tmp"
    return $rc
}

run_file() {
    local file="$1" _RF_NAME="${1##*/}"          # _RF_NAME: the label of the start-up bar (_rf_go)
    local rc name ext classname out
    if [ ! -e "$file" ]; then
        echo "❌ File not found: $file"
        return 1
    fi
    [[ "$file" == */* ]] || file="./$file"       # a bare name would be looked up on PATH (and "-x.py" read as an option)
    if _arc_detect "$file"; then            # an archive is opened, never run: extracted next to itself
        local _ab="${file%/*}"; [ "$_ab" = "$file" ] && _ab="$PWD"; [ -n "$_ab" ] || _ab="/"
        _arc_dest_base="$_ab" _decompress_paths "$file"
        return $?
    fi
    # No questions: the person chose Run, so the file's own nature decides.
    # 1) a script with a shebang runs with that interpreter (same result as running it directly, and it also works on shared storage, which cannot execute files)
    if _rf_shebang "$file"; then
        if command -v "$_RF_EXE" >/dev/null 2>&1; then
            _rf_go "$_RF_EXE" "${_RF_ARGS[@]}" "$file"
            return $?
        fi
        echo "⚠️ The shebang names '$_RF_EXE', which is not installed: trying the file's extension instead"
    fi
    # 2) a compiled program (ELF) runs directly; without the executable bit it cannot run
    if _rf_is_elf "$file"; then
        if [ ! -x "$file" ]; then
            echo "❌ '${file##*/}' is a program but is not executable (chmod +x it first)"
            return 1
        fi
        _rf_go "$file"; rc=$?
        [ "$rc" = 126 ] && echo "❌ Cannot execute here (shared storage does not allow it): copy the file into your home folder first"
        return $rc
    fi
    name="${file##*/}"; ext=""
    [[ "$name" == *.* ]] && ext="${name##*.}"
    ext="${ext,,}"                             # .PY .SH .JPG ...
    case "$ext" in
        py)
            if command -v python3 >/dev/null 2>&1; then _rf_go python3 -u "$file"; elif command -v python >/dev/null 2>&1; then _rf_go python -u "$file"; elif _dep_need -c "Running a .py file" python3; then _rf_go python3 -u "$file"; fi
            ;;
        pyc)
            echo "❌ Cannot run .pyc directly in Termux without proper interpreter setup"
            ;;
        js|mjs|cjs)
            if command -v node >/dev/null 2>&1; then _rf_go node "$file"; elif command -v deno >/dev/null 2>&1; then _rf_go deno run "$file"; elif _dep_need -c "Running a JavaScript file" nodejs; then _rf_go node "$file"; fi
            ;;
        ts)
            if command -v deno >/dev/null 2>&1; then _rf_go deno run "$file"; elif command -v ts-node >/dev/null 2>&1; then _rf_go ts-node "$file"; else echo "❌ ts-node/deno not found"; fi
            ;;
        sh|bash)
            if command -v bash >/dev/null 2>&1; then _rf_go bash "$file"; else _rf_go sh "$file"; fi
            ;;
        zsh)
            if command -v zsh >/dev/null 2>&1 || _dep_need -c "Running a .zsh file" zsh; then _rf_go zsh "$file"; fi
            ;;
        php)
            if command -v php >/dev/null 2>&1 || _dep_need -c "Running a .php file" php; then _rf_go php "$file"; fi
            ;;
        pl)
            if command -v perl >/dev/null 2>&1 || _dep_need -c "Running a .pl file" perl; then _rf_go perl "$file"; fi
            ;;
        rb)
            if command -v ruby >/dev/null 2>&1 || _dep_need -c "Running a .rb file" ruby; then _rf_go ruby "$file"; fi
            ;;
        jar)
            if command -v java >/dev/null 2>&1; then _rf_go java -jar "$file"; else echo "❌ java not found"; fi
            ;;
        class)
            if command -v java >/dev/null 2>&1; then classname="$(basename "${file%.*}")"; _rf_go java -cp "$(dirname "$file")" "$classname"; else echo "❌ java not found"; fi
            ;;
        java)
            if command -v javac >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
                javac "$file" && classname="$(basename "${file%.*}")" && _rf_go java -cp "$(dirname "$file")" "$classname"
            else
                echo "❌ javac/java not found"
            fi
            ;;
        c)
            if command -v gcc >/dev/null 2>&1; then _rf_build_run "$file" gcc; else echo "❌ gcc not found"; fi
            ;;
        cpp|cc|cxx|c++)
            if command -v g++ >/dev/null 2>&1; then _rf_build_run "$file" g++; else echo "❌ g++ not found"; fi
            ;;
        go)
            if command -v go >/dev/null 2>&1; then _rf_go go run "$file"; else echo "❌ go not found"; fi
            ;;
        rs)
            if command -v rustc >/dev/null 2>&1; then
                _rf_build_run "$file" rustc
            elif command -v cargo >/dev/null 2>&1; then
                echo "📜 For cargo projects use cargo run inside the project"
            else
                echo "❌ rustc/cargo not found"
            fi
            ;;
        swift)
            if command -v swift >/dev/null 2>&1; then _rf_go swift "$file"; elif command -v swiftc >/dev/null 2>&1; then _rf_build_run "$file" swiftc; else echo "❌ swift not found"; fi
            ;;
        kts)
            if command -v kotlinc >/dev/null 2>&1; then _rf_go kotlinc -script "$file"; else echo "❌ kotlinc not found"; fi
            ;;
        kt|kotlin)
            if command -v kotlinc >/dev/null 2>&1 && command -v java >/dev/null 2>&1; then
                out=$(mktemp "${TMPDIR:-$HOME}/bvk_kt.XXXXXX.jar") || { echo "❌ Cannot create a temporary file"; return 1; }
                kotlinc "$file" -include-runtime -d "$out" && _rf_go java -jar "$out"
                rm -f -- "$out"
            else
                echo "❌ kotlinc/java not found"
            fi
            ;;
        r)
            if command -v Rscript >/dev/null 2>&1; then _rf_go Rscript "$file"; else echo "❌ Rscript not found"; fi
            ;;
        jl)
            if command -v julia >/dev/null 2>&1; then _rf_go julia "$file"; else echo "❌ julia not found"; fi
            ;;
        lua)
            if command -v lua >/dev/null 2>&1; then _rf_go lua "$file"; else echo "❌ lua not found"; fi
            ;;
        hs)
            if command -v runhaskell >/dev/null 2>&1; then _rf_go runhaskell "$file"; elif command -v ghc >/dev/null 2>&1; then _rf_build_run "$file" ghc; else echo "❌ runhaskell/ghc not found"; fi
            ;;
        coffee)
            if command -v coffee >/dev/null 2>&1; then _rf_go coffee "$file"; else echo "❌ coffee not found"; fi
            ;;
        dart)
            if command -v dart >/dev/null 2>&1; then _rf_go dart run "$file"; else echo "❌ dart not found"; fi
            ;;
        scala)
            if command -v scala >/dev/null 2>&1; then _rf_go scala "$file"; else echo "❌ scala not found"; fi
            ;;
        md|markdown)
            if command -v glow >/dev/null 2>&1; then glow "$file"; else _rf_page "$file"; fi
            ;;
        txt|log|cfg|conf)
            _rf_page "$file"
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
            if _rf_is_text "$file"; then
                if [ -x "$file" ]; then _rf_go bash "$file"; else _rf_page "$file"; fi      # an executable text file with no shebang and no known extension is a shell script
            else
                force_open "$file"
            fi
            ;;
    esac
}
