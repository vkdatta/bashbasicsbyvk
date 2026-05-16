_get_nanorc_file() {
    local current_shell
    current_shell="$(basename "${SHELL:-bash}")"
    case "$current_shell" in
        fish) echo "$HOME/.config/fish/nanorc" ;;
        *)    echo "$HOME/.nanorc" ;;
    esac
}

import_nanorc_settings() {
    local nanorc_file
    nanorc_file="$(_get_nanorc_file)"

    mkdir -p "$(dirname "$nanorc_file")"
    touch "$nanorc_file"

    if grep -q "^# bashbasicsbyvk nano settings$" "$nanorc_file"; then
        return
    fi

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
}
