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
}
