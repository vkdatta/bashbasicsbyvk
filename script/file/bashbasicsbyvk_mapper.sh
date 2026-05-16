map_directory() {
    local target_dir="${1:-$path}"

    generate_map() {
        (
            cd "$target_dir" || exit

            find . | sed \
                -e '1d' \
                -e 's|^\./||' \
                -e 's|[^/]*/|│   |g' \
                -e 's|│   \([^│]\)|├── \1|'
        )
    }

    copy_to_clipboard() {
        local content="$1"

        printf "%s" "$content" | bashbasicsbyvk_copy
    }

    save_to_file() {
        local content="$1"

        read -p "Enter file name: " filename

        printf "%s" "$content" > "$target_dir/$filename"

        echo "output saved as $target_dir/$filename"
    }

    local map_output
    local choice

    map_output=$(generate_map)

    echo
    echo "1) Copy to clipboard"
    echo "2) Save to txt file"
    echo

    read -p "Choose option [1-2]: " choice

    case "$choice" in
        1)
            copy_to_clipboard "$map_output"
            echo "output copied to clipboard"
            ;;

        2)
            save_to_file "$map_output"
            ;;

        *)
            echo "invalid option"
            ;;
    esac
}
