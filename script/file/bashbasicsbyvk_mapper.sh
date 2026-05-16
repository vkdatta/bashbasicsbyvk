map_directory() {

    local target_dir="${1:-$path}"

    generate_map() {

        find "$target_dir" -print | \
        sed -e 's;[^/]*/;│   ;g' \
            -e 's;│   \([^│]\);├── \1;'
    }

    copy_to_clipboard() {

        local content="$1"

        printf "%s" "$content" | bashbasicsbyvk_copy
    }

    save_to_file() {

        local content="$1"

        read -p "Enter file name: " filename

        printf "%s" "$content" > "$filename"

        echo "output saved as $filename"
    }

    local map_output

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
