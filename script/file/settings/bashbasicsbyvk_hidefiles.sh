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
