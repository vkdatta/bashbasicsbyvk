find_menu() {
    echo "🔍 Find mode in: $path"
    echo "1) Find file/folder names"
    echo "2) Find inside file contents"
    echo "3) Find & replace in file/folder names"
    echo "4) Find & replace inside file contents"
    read -p "Choice: " ftype

    local -a results=()
    case "$ftype" in
        1)
            read -p "Name pattern (e.g. report): " pat
            mapfile -t results < <(find "$path" -name "*$pat*" 2>/dev/null | head -100)
            ;;
        2)
            read -p "Text to search inside files: " pat
            mapfile -t results < <(grep -rl "$pat" "$path" 2>/dev/null | head -100)
            ;;
        3)
            read -p "Name pattern to find: " pat
            read -p "Replace with: " rep
            mapfile -t results < <(find "$path" -name "*$pat*" 2>/dev/null | head -100)

            if [ ${#results[@]} -eq 0 ]; then
                echo "No matches found."
                return
            fi

            echo "📋 Preview of renames (${#results[@]} items):"
            for f in "${results[@]}"; do
                local base=$(basename "$f")
                local dir=$(dirname "$f")
                local newname="${base//$pat/$rep}"
                printf "  %s  →  %s\n" "$base" "$newname"
            done

            read -p "Apply all renames? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                local count=0
                for f in "${results[@]}"; do
                    local base=$(basename "$f")
                    local dir=$(dirname "$f")
                    local newname="${base//$pat/$rep}"
                    if [ "$base" != "$newname" ]; then
                        mv -- "$f" "$dir/$newname" && (( count++ ))
                    fi
                done
                echo "✅ Renamed $count item(s)."
            else
                echo "Aborted."
            fi
            return
            ;;
        4)
            read -p "Text to find inside files: " pat
            read -p "Replace with: " rep
            mapfile -t results < <(grep -rl "$pat" "$path" 2>/dev/null | head -100)

            if [ ${#results[@]} -eq 0 ]; then
                echo "No matches found."
                return
            fi

            echo "📋 Files containing \"$pat\" (${#results[@]} files):"
            for i in "${!results[@]}"; do
                local rel=$(realpath --relative-to="$path" "${results[$i]}" 2>/dev/null || basename "${results[$i]}")
                local hits=$(grep -c "$pat" "${results[$i]}" 2>/dev/null)
                printf "  %3d) %s  (%s match(es))\n" $((i+1)) "$rel" "$hits"
            done

            echo ""
            echo "a) Apply to ALL files"
            echo "Enter number to apply to a single file"
            echo "q) Cancel"
            read -p "Action: " act

            case "$act" in
                q|Q) return ;;
                a|A)
                    local count=0
                    for f in "${results[@]}"; do
                        sed -i "s|$pat|$rep|g" "$f" && (( count++ ))
                    done
                    echo "✅ Replaced in $count file(s)."
                    ;;
                [0-9]*)
                    if (( act >= 1 && act <= ${#results[@]} )); then
                        local target="${results[$((act-1))]}"
                        sed -i "s|$pat|$rep|g" "$target"
                        echo "✅ Replaced in: $(basename "$target")"
                    else
                        echo "Invalid number."
                    fi
                    ;;
                *) echo "Invalid choice." ;;
            esac
            return
            ;;
        *) return ;;
    esac

    if [ ${#results[@]} -eq 0 ]; then
        echo "No results."
        return
    fi

    echo "📋 Found ${#results[@]} results:"
    for i in "${!results[@]}"; do
        local rel=$(realpath --relative-to="$path" "${results[$i]}" 2>/dev/null || basename "${results[$i]}")
        printf "%3d) %s\n" $((i+1)) "$rel"
    done

    echo "Enter item number to navigate | q) exit"
    while true; do
        read -p "Action: " act
        case "$act" in
            q|Q|h|H) return ;;
            [0-9]*)
                if [[ $act =~ ^[0-9]+$ ]] && (( act >= 1 && act <= ${#results[@]} )); then
                    local target="${results[$((act-1))]}"
                    if [ -d "$target" ]; then
                        path="$target"
                    elif [ -f "$target" ]; then
                        handle_file "$target"
                    fi
                    return
                fi
                ;;
            *) echo "Invalid. Use a number or q." ;;
        esac
    done
}
