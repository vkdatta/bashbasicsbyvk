#!/usr/bin/env bash
# Shared CSV file browser
# Used by: bashbasicsbyvk_find.sh (options 3 & 4) and bashbasicsbyvk_rename.sh
#
# open_csv_menu [start_path]
#   Presents a folder/CSV-only navigator.
#   On success : sets global $csv_file to the chosen .csv path, returns 0.
#   On cancel  : sets csv_file="" and returns 1.
#   On quit    : exits the program.

open_csv_menu() {
    local start_path="${1:-${nav_last_browsed_path:-${path:-$(pwd)}}}"
    csv_file=""
    local _csv_nav_path="$start_path"

    echo ""
    echo "📂 Navigate to select your CSV file (folders and .csv files only)"

    while true; do
        echo ""
        echo "📂 CSV SELECT — Location: $_csv_nav_path"

        local -a _csv_items=()
        while IFS= read -r -d '' _e; do
            local _bn="${_e##*/}"
            [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
            if [ -d "$_e" ]; then
                _csv_items+=("$_e")
            elif [[ "${_bn,,}" == *.csv ]]; then
                _csv_items+=("$_e")
            fi
        done < <(find "$_csv_nav_path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)

        if [ ${#_csv_items[@]} -eq 0 ]; then
            echo "🛑 No folders or CSV files here."
        else
            local _i=1
            for _it in "${_csv_items[@]}"; do
                local _bn="${_it##*/}"
                if [ -d "$_it" ]; then
                    printf "%2d) 📁 %s\n" "$_i" "$_bn"
                else
                    printf "%2d) 📄 %s\n" "$_i" "$_bn"
                fi
                _i=$((_i + 1))
            done
        fi

        echo ""
        echo "u) Up   x) Cancel   q) Quit"
        read -p "CSV Nav: " _csv_choice

        case "$_csv_choice" in
            q|Q) exit 0 ;;
            x|X)
                echo "🚫 CSV selection cancelled."
                csv_file=""
                return 1
                ;;
            u|U)
                [ "$_csv_nav_path" != "/" ] && _csv_nav_path=$(dirname "$_csv_nav_path")
                ;;
            *)
                if [[ "$_csv_choice" =~ ^[0-9]+$ ]] &&
                   [ "$_csv_choice" -ge 1 ] &&
                   [ "$_csv_choice" -le "${#_csv_items[@]}" ]; then
                    local _sel="${_csv_items[$((_csv_choice - 1))]}"
                    if [ -d "$_sel" ]; then
                        _csv_nav_path="$_sel"
                    else
                        csv_file="$_sel"
                        echo "✅ Selected: $(basename "$csv_file")"
                        return 0
                    fi
                else
                    echo "⚠️  Invalid selection"
                fi
                ;;
        esac
    done
}
