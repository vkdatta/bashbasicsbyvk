index_mode_threshold_settings() {
    echo
    echo "Index mode threshold"
    echo "Current: $index_mode_threshold"
    echo "Default: $DEFAULT_INDEX_MODE_THRESHOLD"
    echo
    echo "1) Set new threshold"
    echo "2) Restore default"

    echo
    echo "u) Back   q) Close settings"
    read -r -p "Select: " t_choice

    case "$t_choice" in
    u|U) return ;;
    q|Q) _st_quit=1; return ;;
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
        *) echo "Invalid choice" ;;
    esac
}
