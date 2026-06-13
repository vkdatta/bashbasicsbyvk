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
            echo ""
            echo "🔄 Find & Replace inside file contents"
            echo "1) Single Mutation"
            echo "2) Multi Mutation (CSV)"
            read -p "Mode [1-2]: " fr_mode

            case "$fr_mode" in
                1)
                    # ── Single Mutation ─────────────────────────────────────────
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

                2)
                    # ── Multi Mutation (CSV) ────────────────────────────────────
                    echo ""
                    echo "📂 Navigate to select your CSV file (showing CSV files and folders only)"

                    local csv_file=""
                    local csv_nav_path="${nav_last_browsed_path:-$path}"

                    # CSV-only navigator loop
                    while true; do
                        echo ""
                        echo "📂 CSV SELECT — Location: $csv_nav_path"

                        local -a csv_nav_items=()
                        # collect folders and .csv files only
                        while IFS= read -r -d '' _entry; do
                            local _bn="${_entry##*/}"
                            [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
                            if [ -d "$_entry" ]; then
                                csv_nav_items+=("$_entry")
                            elif [[ "${_bn,,}" == *.csv ]]; then
                                csv_nav_items+=("$_entry")
                            fi
                        done < <(find "$csv_nav_path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)

                        if [ ${#csv_nav_items[@]} -eq 0 ]; then
                            echo "🛑 No folders or CSV files here."
                        else
                            local idx=1
                            for item in "${csv_nav_items[@]}"; do
                                local _bn="${item##*/}"
                                if [ -d "$item" ]; then
                                    printf "%2d) 📁 %s\n" "$idx" "$_bn"
                                else
                                    printf "%2d) 📄 %s\n" "$idx" "$_bn"
                                fi
                                idx=$((idx+1))
                            done
                        fi

                        echo ""
                        echo "u) Up   x) Cancel   q) Quit"
                        read -p "CSV Nav: " csv_choice

                        case "$csv_choice" in
                            q|Q) exit 0 ;;
                            x|X)
                                echo "🚫 CSV selection cancelled."
                                return
                                ;;
                            u|U)
                                [ "$csv_nav_path" != "/" ] && csv_nav_path=$(dirname "$csv_nav_path")
                                ;;
                            *)
                                if [[ "$csv_choice" =~ ^[0-9]+$ ]] && \
                                   [ "$csv_choice" -ge 1 ] && \
                                   [ "$csv_choice" -le "${#csv_nav_items[@]}" ]; then
                                    local csv_sel="${csv_nav_items[$((csv_choice-1))]}"
                                    if [ -d "$csv_sel" ]; then
                                        csv_nav_path="$csv_sel"
                                    else
                                        # It's a .csv file — selected!
                                        csv_file="$csv_sel"
                                        echo "✅ Selected: $(basename "$csv_file")"
                                        break
                                    fi
                                else
                                    echo "⚠️  Invalid selection"
                                fi
                                ;;
                        esac
                    done

                    [ -z "$csv_file" ] && return

                    # ── Read CSV and run each mutation row by row ───────────────
                    echo ""
                    echo "🔄 Processing mutations from: $(basename "$csv_file")"

                    local -a csv_rows=()
                    local -a csv_finds=()
                    local -a csv_reps=()
                    local -a csv_counts=()

                    # Parse CSV (col1 = find, col2 = replace), skip empty lines
                    while IFS=, read -r csv_find csv_rep _rest || [ -n "$csv_find" ]; do
                        # Strip leading/trailing whitespace and CR
                        csv_find="${csv_find#"${csv_find%%[![:space:]]*}"}"
                        csv_find="${csv_find%"${csv_find##*[![:space:]]}"}"
                        csv_find="${csv_find%$'\r'}"
                        csv_rep="${csv_rep#"${csv_rep%%[![:space:]]*}"}"
                        csv_rep="${csv_rep%"${csv_rep##*[![:space:]]}"}"
                        csv_rep="${csv_rep%$'\r'}"
                        [ -z "$csv_find" ] && continue
                        csv_finds+=("$csv_find")
                        csv_reps+=("$csv_rep")
                    done < "$csv_file"

                    if [ ${#csv_finds[@]} -eq 0 ]; then
                        echo "❌ No valid rows found in CSV."
                        return
                    fi

                    echo "📋 Found ${#csv_finds[@]} mutation(s) to apply across: $path"
                    echo ""

                    for row_idx in "${!csv_finds[@]}"; do
                        local row_find="${csv_finds[$row_idx]}"
                        local row_rep="${csv_reps[$row_idx]}"

                        # Count total instances across all matching files
                        mapfile -t row_files < <(grep -rl "$row_find" "$path" 2>/dev/null)
                        local total_instances=0
                        for rf in "${row_files[@]}"; do
                            local file_hits
                            file_hits=$(grep -o "$row_find" "$rf" 2>/dev/null | wc -l)
                            total_instances=$(( total_instances + file_hits ))
                        done

                        if [ ${#row_files[@]} -eq 0 ]; then
                            echo "  Row $((row_idx+1)): \"$row_find\" → \"$row_rep\"  ⚠️  No matches found (0 instances)"
                            csv_counts+=("0")
                        else
                            # Apply replacement
                            for rf in "${row_files[@]}"; do
                                sed -i "s|$row_find|$row_rep|g" "$rf"
                            done
                            echo "  Row $((row_idx+1)): \"$row_find\" → \"$row_rep\"  ✅ $total_instances instance(s) in ${#row_files[@]} file(s)"
                            csv_counts+=("$total_instances")
                        fi
                    done

                    # ── Write 3rd column (instance count) back into the CSV ─────
                    echo ""
                    echo "📝 Writing instance counts back to CSV..."

                    local tmp_csv="${csv_file}.tmp"
                    local write_idx=0
                    while IFS=, read -r csv_find csv_rep _rest || [ -n "$csv_find" ]; do
                        local raw_find="$csv_find"
                        local raw_rep="$csv_rep"
                        local trimmed_find="${csv_find#"${csv_find%%[![:space:]]*}"}"
                        trimmed_find="${trimmed_find%"${trimmed_find##*[![:space:]]}"}"
                        trimmed_find="${trimmed_find%$'\r'}"
                        [ -z "$trimmed_find" ] && { printf "%s,%s,%s\n" "$raw_find" "$raw_rep" "${_rest:-}"; continue; }
                        local inst="${csv_counts[$write_idx]:-0}"
                        printf "%s,%s,%s instances\n" "$raw_find" "$raw_rep" "$inst"
                        write_idx=$(( write_idx + 1 ))
                    done < "$csv_file" > "$tmp_csv"

                    mv "$tmp_csv" "$csv_file"
                    echo "✅ CSV updated with instance counts: $(basename "$csv_file")"
                    echo ""
                    echo "🎉 Multi Mutation complete — ${#csv_finds[@]} pattern(s) processed."
                    return
                    ;;

                *)
                    echo "❌ Invalid mode."
                    return
                    ;;
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
