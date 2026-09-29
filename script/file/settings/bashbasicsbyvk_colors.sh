_get_rc_file() {
    local current_shell
    current_shell="$(basename "${SHELL:-bash}")"
    case "$current_shell" in
        zsh)  echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.bashrc" ;;
    esac
}

_MARKER_BEGIN="# bashbasicsbyvk colors BEGIN"
_MARKER_END="# bashbasicsbyvk colors END"

_normalize_hex() {
    echo "${1#\#}" | tr '[:lower:]' '[:upper:]'
}

_valid_hex() {
    local hex
    hex="$(_normalize_hex "$1")"
    [[ "$hex" =~ ^[0-9A-F]{6}$ ]]
}

_hex_to_rgb() {
    local hex
    hex="$(_normalize_hex "$1")"
    printf "%d %d %d" \
        "$((16#${hex:0:2}))" \
        "$((16#${hex:2:2}))" \
        "$((16#${hex:4:2}))"
}

apply_colors() {
    if [ -n "$terminal_bg_color" ] && _valid_hex "$terminal_bg_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_bg_color")"
        printf "\e]11;#%s\a" "$hex"
    fi
    if [ -n "$terminal_text_color" ] && _valid_hex "$terminal_text_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_text_color")"
        printf "\e]10;#%s\a" "$hex"
    fi
    if [ -n "$terminal_bg_color" ] || [ -n "$terminal_text_color" ]; then
        printf "\e[2J\e[H"
    fi
}

_apply_bg_color() {
    local hex
    hex="$(_normalize_hex "$1")"
    terminal_bg_color="$hex"
    save_settings
    _persist_colors_to_rc
    apply_colors
}

_apply_text_color() {
    local hex
    hex="$(_normalize_hex "$1")"
    terminal_text_color="$hex"
    save_settings
    _persist_colors_to_rc
    apply_colors
}

_persist_colors_to_rc() {
    local rc_file
    rc_file="$(_get_rc_file)"
    touch "$rc_file"

    _remove_colors_from_rc

    local block=""
    block+="$_MARKER_BEGIN\n"

    if [ -n "$terminal_bg_color" ] && _valid_hex "$terminal_bg_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_bg_color")"
        block+="printf \"\\e]11;#${hex}\\a\"\n"
    fi

    if [ -n "$terminal_text_color" ] && _valid_hex "$terminal_text_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_text_color")"
        block+="printf \"\\e]10;#${hex}\\a\"\n"
    fi

    if [ -n "$terminal_bg_color" ] || [ -n "$terminal_text_color" ]; then
        block+="printf \"\\e[2J\\e[H\"\n"
    fi

    block+="$_MARKER_END"

    printf "\n%b\n" "$block" >> "$rc_file"
}

_remove_colors_from_rc() {
    local rc_file
    rc_file="$(_get_rc_file)"
    [ -f "$rc_file" ] || return

    local tmp_file="${rc_file}.bbvk_tmp"

    awk '
    /^# bashbasicsbyvk colors BEGIN$/ {skip=1}
    !skip {print}
    /^# bashbasicsbyvk colors END$/ {skip=0}
    ' "$rc_file" > "$tmp_file"

    mv "$tmp_file" "$rc_file"
}


terminal_bg_color_settings() {
    echo
    echo "Terminal background color"
    echo "Current: #${terminal_bg_color}"
    echo "Default: #${DEFAULT_TERMINAL_BG_COLOR}"
    echo
    echo "1) Set new color"
    echo "2) Restore default (#${DEFAULT_TERMINAL_BG_COLOR})"
    echo "0) Back"

    read -r -p "Enter choice [0-2]: " b_choice

    case "$b_choice" in
        1)
            read -r -p "Color (e.g. #1e1e2e or 1e1e2e): " input_color
            if _valid_hex "$input_color"; then
                _apply_bg_color "$input_color"
                echo "Background set to #$(_normalize_hex "$input_color")"
            else
                echo "Invalid hex — must be 6 digits"
            fi
            ;;
        2)
            _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"
            echo "Background restored to default (#${DEFAULT_TERMINAL_BG_COLOR})"
            ;;
        0) return ;;
        *) echo "Invalid choice" ;;
    esac
}

terminal_text_color_settings() {
    echo
    echo "Terminal text color"
    echo "Current: #${terminal_text_color}"
    echo
    echo "1) Set new color"
    echo "2) Restore default"
    echo "0) Back"

    read -r -p "Enter choice [0-2]: " c_choice

    case "$c_choice" in
        1)
            read -r -p "Color (e.g. #cdd6f4 or cdd6f4): " input_color
            if _valid_hex "$input_color"; then
                _apply_text_color "$input_color"
                echo "Text color set to #$(_normalize_hex "$input_color")"
            else
                echo "Invalid hex — must be 6 digits"
            fi
            ;;
        2)
            echo "Choose default:"
            echo "1) Normal mode (#FFFFFF - white)"
            echo "2) Coder mode  (#00D000 - green)"
            read -r -p "Enter choice [1-2]: " mode_choice
            case "$mode_choice" in
                2)
                    _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER"
                    echo "Text color restored to Coder mode (#${DEFAULT_TERMINAL_TEXT_COLOR_CODER})"
                    ;;
                *)
                    _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL"
                    echo "Text color restored to Normal mode (#${DEFAULT_TERMINAL_TEXT_COLOR_NORMAL})"
                    ;;
            esac
            ;;
        0) return ;;
        *) echo "Invalid choice" ;;
    esac
}

apply_colors
