_get_nanorc_file() {
    local current_shell target_home
    current_shell="$(basename "${SHELL:-bash}")"
    
    if [ -n "$SUDO_USER" ]; then
        target_home="$(eval echo "~$SUDO_USER")"
    else
        target_home="$HOME"
    fi

    case "$current_shell" in
        fish) echo "$target_home/.config/fish/nanorc" ;;
        *)    echo "$target_home/.nanorc" ;;
    esac
}

import_nanorc_settings() {
    local nanorc_file target_dir
    nanorc_file="$(_get_nanorc_file)"
    target_dir="$(dirname "$nanorc_file")"

    mkdir -p "$target_dir"
    touch "$nanorc_file"

    if ! grep -q "^# bashbasicsbyvk nano settings$" "$nanorc_file"; then
        {
            echo ""
            echo "# bashbasicsbyvk nano settings"
            echo "set mouse"
            echo "set smarthome"
            echo "set wordbounds"
            echo "set indicator"
            echo "set linenumbers"
            echo "set zap"
        } >> "$nanorc_file"
    fi

    if [ -n "$SUDO_USER" ]; then
        chown -R "$SUDO_USER:$(id -gn "$SUDO_USER")" "$target_dir" 2>/dev/null
        chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$nanorc_file" 2>/dev/null
    fi

    bvk_nano_wrap_apply
}

# bvk_nano_wrap_apply [--if-present]
#   Writes the Settings choice (nano_wrap = wrap | nowrap) into nanorc as ONE managed block and replaces it on every call:
#     # bashbasicsbyvk nano wrap  ...  # end bashbasicsbyvk nano wrap
#   Nothing else in the file is touched. --if-present: do nothing unless the block is already there (used by Reset all).
bvk_nano_wrap_apply() {
    local nanorc_file target_dir tmp mode="${nano_wrap:-nowrap}"
    nanorc_file="$(_get_nanorc_file)"
    target_dir="$(dirname "$nanorc_file")"
    if [ "${1:-}" = "--if-present" ]; then
        grep -q "^# bashbasicsbyvk nano wrap$" "$nanorc_file" 2>/dev/null || return 0
    fi
    mkdir -p "$target_dir" && touch "$nanorc_file" || return 1
    tmp="$(mktemp)" || return 1
    # the file without our block and without trailing blank lines (so repeated calls never grow it)
    awk '/^# bashbasicsbyvk nano wrap$/{skip=1; next}
         /^# end bashbasicsbyvk nano wrap$/{skip=0; next}
         skip{next}
         /^$/{b=b "\n"; next}
         {printf "%s%s\n", b, $0; b=""}' "$nanorc_file" > "$tmp"
    {
        cat "$tmp"
        echo ""
        echo "# bashbasicsbyvk nano wrap"
        if [ "$mode" = wrap ]; then
            echo "set softwrap"
            echo "set atblanks"
        else
            echo "unset softwrap"
            echo "unset atblanks"
        fi
        echo "# end bashbasicsbyvk nano wrap"
    } > "$nanorc_file"
    rm -f "$tmp"
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$nanorc_file" 2>/dev/null
    fi
    return 0
}
