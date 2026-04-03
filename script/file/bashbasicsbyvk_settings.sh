#!/usr/bin/env bash

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk"
SETTINGS_FILE="$CONFIG_DIR/config"

mkdir -p "$CONFIG_DIR"

DEFAULT_SHOW_HIDDEN_FILES=false
DEFAULT_INDEX_MODE_THRESHOLD=200
DEFAULT_TERMINAL_BG_COLOR="000000"
DEFAULT_TERMINAL_TEXT_COLOR_NORMAL="FFFFFF"
DEFAULT_TERMINAL_TEXT_COLOR_CODER="00D000"

unset show_hidden_files
unset index_mode_threshold
unset terminal_bg_color
unset terminal_text_color

[ -f "$SETTINGS_FILE" ] && source "$SETTINGS_FILE"

: "${show_hidden_files:=$DEFAULT_SHOW_HIDDEN_FILES}"
: "${index_mode_threshold:=$DEFAULT_INDEX_MODE_THRESHOLD}"
: "${terminal_bg_color:=$DEFAULT_TERMINAL_BG_COLOR}"
: "${terminal_text_color:=$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL}"

# ─────────────────────────────────────────────────────────────────────────────

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

# Works perfectly — do not touch
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

# ─────────────────────────────────────────────────────────────────────────────

get_nanorc() {
    if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
        echo "$HOME/.termux/nanorc"
        return
    fi

    if [ -n "$XDG_CONFIG_HOME" ]; then
        echo "$XDG_CONFIG_HOME/nano/nanorc"
        return
    fi

    echo "$HOME/.config/nano/nanorc"
}

import_nanorc_settings() {
    local nanorc_file
    nanorc_file="$(get_nanorc)"

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

# ─────────────────────────────────────────────────────────────────────────────

settings_menu() {
    echo "Settings:"
    echo "1) Hidden file settings ($show_hidden_files)"
    echo "2) Index mode threshold ($index_mode_threshold)"
    echo "3) Terminal background color (#${terminal_bg_color})"
    echo "4) Terminal text color (#${terminal_text_color})"
    echo "5) Restore ALL settings to default"
    echo "6) Import nano settings"

    read -r -p "Enter choice [1-6]: " main_choice

    case "$main_choice" in
        1) hidden_file_settings ;;
        2) index_mode_threshold_settings ;;
        3) terminal_bg_color_settings ;;
        4) terminal_text_color_settings ;;
        5) restore_all_defaults ;;
        6) import_nanorc_settings ;;
        *) echo "Invalid choice" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────

hidden_file_settings() {
    echo
    echo "Hidden file settings"
    echo "Current: $show_hidden_files"
    echo "Default: $DEFAULT_SHOW_HIDDEN_FILES"
    echo
    echo "1) Show normal files only"
    echo "2) Show all files including hidden"
    echo "3) Restore default"
    echo "0) Back"

    read -r -p "Enter choice [0-3]: " s_choice

    case "$s_choice" in
        1) show_hidden_files=false;                      save_settings ;;
        2) show_hidden_files=true;                       save_settings ;;
        3) show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES; save_settings ;;
        0) return ;;
        *) echo "Invalid choice" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────

index_mode_threshold_settings() {
    echo
    echo "Index mode threshold"
    echo "Current: $index_mode_threshold"
    echo "Default: $DEFAULT_INDEX_MODE_THRESHOLD"
    echo
    echo "1) Set new threshold"
    echo "2) Restore default"
    echo "0) Back"

    read -r -p "Enter choice [0-2]: " t_choice

    case "$t_choice" in
        1)
            read -r -p "Enter new threshold: " new_threshold
            if [[ "$new_threshold" =~ ^[0-9]+$ ]] && [ "$new_threshold" -gt 0 ]; then
                index_mode_threshold=$new_threshold
                save_settings
            else
                echo "Invalid number"
            fi
            ;;
        2) index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD; save_settings ;;
        0) return ;;
        *) echo "Invalid choice" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────

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

# ─────────────────────────────────────────────────────────────────────────────

restore_all_defaults() {
    echo
    echo "Choose default text color mode:"
    echo "1) Normal mode (#FFFFFF - white)"
    echo "2) Coder mode  (#00D000 - green)"
    read -r -p "Enter choice [1-2]: " mode_choice

    show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES
    index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD

    _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"

    case "$mode_choice" in
        2) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
        *) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
    esac

    save_settings
    echo "All settings restored to defaults"
}

# ─────────────────────────────────────────────────────────────────────────────

save_settings() {
    {
        echo "show_hidden_files=$show_hidden_files"
        echo "index_mode_threshold=$index_mode_threshold"
        echo "terminal_bg_color=$terminal_bg_color"
        echo "terminal_text_color=$terminal_text_color"
    } > "$SETTINGS_FILE"
}

apply_colors
