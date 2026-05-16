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

save_settings() {
    {
        echo "show_hidden_files=$show_hidden_files"
        echo "index_mode_threshold=$index_mode_threshold"
        echo "terminal_bg_color=$terminal_bg_color"
        echo "terminal_text_color=$terminal_text_color"
    } > "$SETTINGS_FILE"
}