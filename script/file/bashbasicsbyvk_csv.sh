#!/usr/bin/env bash
# Shared CSV file browser + CSV-driven item resolver
#
# ── Public API ────────────────────────────────────────────────────────────────
#
#  open_csv_menu [start_path]
#    Navigate to and select a .csv file.
#    On success : sets global $csv_file  → returns 0
#    On cancel  : sets csv_file=""       → returns 1
#    On quit    : exits the program
#
#  _csv_trim <var>
#    Trim leading/trailing whitespace and CR from a string (in-place via nameref).
#
#  _csv_resolve_items
#    Reads col1 of $csv_file as filenames or absolute paths.
#    Resolves each against $path (basename match) or directly (absolute).
#    On success : populates global selected_items[]  → returns 0
#    On failure : prints error, selected_items=()    → returns 1
#    Writes a result column back to the CSV (✅ / ⚠️  not found).
#
# ─────────────────────────────────────────────────────────────────────────────

# ---------------------------------------------------------------------------
# open_csv_menu [start_path]
# ---------------------------------------------------------------------------
open_csv_menu() {
    local start_path="${1:-${nav_last_browsed_path:-${path:-$(pwd)}}}"
    csv_file=""
    local _csv_nav_path="$start_path"

    echo ""
    echo "📂 Navigate to select your CSV file (folders and .csv files only)"

    while true; do
        echo ""
        echo "📂 CSV SELECT — Location: $_csv_nav_path"

        # ── Build item list: dirs + .csv files only ───────────────────────
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

        # ── Render list ───────────────────────────────────────────────────
        if [ ${#_csv_items[@]} -eq 0 ]; then
            echo "  🛑 No folders or CSV files here."
        else
            local _i=1
            for _it in "${_csv_items[@]}"; do
                local _bn="${_it##*/}"
                if [ -d "$_it" ]; then
                    printf "  %3d) 📁 %s\n" "$_i" "$_bn"
                else
                    printf "  %3d) 📄 %s\n" "$_i" "$_bn"
                fi
                _i=$((_i + 1))
            done
        fi

        echo ""
        echo "  u) Up parent   x) Cancel   q) Quit"
        read -p "CSV Nav: " _csv_choice

        # ── Strip surrounding whitespace from input ────────────────────────
        _csv_choice="${_csv_choice#"${_csv_choice%%[![:space:]]*}"}"
        _csv_choice="${_csv_choice%"${_csv_choice##*[![:space:]]}"}"

        case "$_csv_choice" in
            q|Q) exit 0 ;;

            x|X)
                echo "🚫 CSV selection cancelled."
                csv_file=""
                return 1
                ;;

            u|U)
                if [ "$_csv_nav_path" != "/" ]; then
                    _csv_nav_path=$(dirname "$_csv_nav_path")
                else
                    echo "  ⚠️  Already at filesystem root."
                fi
                ;;

            "")
                echo "  ⚠️  No input — enter a number, u, x, or q."
                ;;

            *)
                if [[ "$_csv_choice" =~ ^[0-9]+$ ]] \
                   && [ "$_csv_choice" -ge 1 ] \
                   && [ "$_csv_choice" -le "${#_csv_items[@]}" ]; then
                    local _sel="${_csv_items[$((_csv_choice - 1))]}"
                    if [ -d "$_sel" ]; then
                        _csv_nav_path="$_sel"
                    else
                        csv_file="$_sel"
                        echo "✅ Selected: $(basename "$csv_file")"
                        return 0
                    fi
                else
                    echo "  ⚠️  Invalid selection — enter a number between 1 and ${#_csv_items[@]}."
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# _csv_trim <nameref-var>
# Strips leading/trailing whitespace + CR from the named variable in-place.
# ---------------------------------------------------------------------------
_csv_trim() {
    local -n _ct_ref="$1"
    _ct_ref="${_ct_ref#"${_ct_ref%%[![:space:]]*}"}"
    _ct_ref="${_ct_ref%"${_ct_ref##*[![:space:]]}"}"
    _ct_ref="${_ct_ref%$'\r'}"
}

# ---------------------------------------------------------------------------
# _csv_resolve_items
#
# Reads col1 of $csv_file.  Each non-blank, non-header row is treated as
# either an absolute path (starts with /) or a basename to find in $path.
#
# Populates:  selected_items[]   — resolved absolute paths, deduplicated
# Side-effect: rewrites col2 of the CSV with ✅ resolved / ⚠️  not found
#
# Returns 0 if at least one item resolved, 1 otherwise.
# ---------------------------------------------------------------------------
_csv_resolve_items() {
    selected_items=()

    # ── Validate state ────────────────────────────────────────────────────
    if [ -z "$csv_file" ] || [ ! -f "$csv_file" ]; then
        echo "❌ No CSV file set — call open_csv_menu first."
        return 1
    fi

    echo ""
    echo "🔎 Resolving items from: $(basename "$csv_file")"
    echo "   Search path: $path"
    echo ""

    # ── Parse col1 (name or absolute path), skip blank rows ───────────────
    local -a _raw_entries=()
    local _col1 _rest
    while IFS=, read -r _col1 _rest || [ -n "$_col1" ]; do
        _csv_trim _col1
        [ -z "$_col1" ] && continue
        _raw_entries+=("$_col1")
    done < "$csv_file"

    if [ ${#_raw_entries[@]} -eq 0 ]; then
        echo "❌ No valid rows found in CSV."
        return 1
    fi

    echo "📋 Found ${#_raw_entries[@]} row(s) to resolve."
    echo ""

    # ── Resolve each entry ────────────────────────────────────────────────
    local -a _result_tags=()   # parallel to _raw_entries: "ok" or "miss"
    local -A _seen=()
    local _entry _abs

    for _entry in "${_raw_entries[@]}"; do
        if [[ "$_entry" == /* ]]; then
            # ── Absolute path ─────────────────────────────────────────────
            if [ -e "$_entry" ]; then
                _abs="$_entry"
                if [ -z "${_seen[$_abs]+x}" ]; then
                    selected_items+=("$_abs")
                    _seen["$_abs"]=1
                fi
                echo "  ✅ $_entry"
                _result_tags+=("ok")
            else
                echo "  ⚠️  Not found (absolute): $_entry"
                _result_tags+=("miss")
            fi
        else
            # ── Basename match in $path (maxdepth 1) ──────────────────────
            local -a _matched=()
            while IFS= read -r -d '' _f; do
                [ "${_f##*/}" = "$_entry" ] && _matched+=("$_f")
            done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

            if [ ${#_matched[@]} -eq 0 ]; then
                echo "  ⚠️  Not found in $path: $_entry"
                _result_tags+=("miss")
            else
                for _abs in "${_matched[@]}"; do
                    if [ -z "${_seen[$_abs]+x}" ]; then
                        selected_items+=("$_abs")
                        _seen["$_abs"]=1
                    fi
                done
                local _mc="${#_matched[@]}"
                local _mc_suffix=""; [ "$_mc" -gt 1 ] && _mc_suffix="  ($_mc matches)"
                echo "  ✅ $_entry → ${_matched[0]##*/}${_mc_suffix}"
                _result_tags+=("ok")
            fi
        fi
    done

    # ── Write result column back to CSV ───────────────────────────────────
    local _tmp_csv="${csv_file}.tmp"
    local _write_idx=0
    local _col1_raw _csv_rest

    while IFS=, read -r _col1_raw _csv_rest || [ -n "$_col1_raw" ]; do
        local _trimmed="$_col1_raw"
        _csv_trim _trimmed
        if [ -z "$_trimmed" ]; then
            # Blank / header row — preserve as-is (strip old result col if present)
            local _c1="$_col1_raw"
            local _c2="${_csv_rest%%,*}"
            # If it looks like a previous result tag, drop it; otherwise keep
            local _tag_pat="^(✅|⚠️)"
            if [[ "$_c2" =~ $_tag_pat ]]; then
                printf '%s\n' "$_c1" >> "$_tmp_csv"
            else
                printf '%s\n' "${_col1_raw}${_csv_rest:+,$_csv_rest}" >> "$_tmp_csv"
            fi
            continue
        fi
        local _tag="${_result_tags[$_write_idx]:-miss}"
        local _label
        if [ "$_tag" = "ok" ]; then _label="✅ resolved"; else _label="⚠️  not found"; fi
        printf '%s,%s\n' "$_col1_raw" "$_label" >> "$_tmp_csv"
        _write_idx=$((_write_idx + 1))
    done < "$csv_file"

    mv "$_tmp_csv" "$csv_file"

    # ── Summary ───────────────────────────────────────────────────────────
    echo ""
    if [ ${#selected_items[@]} -eq 0 ]; then
        echo "❌ No items resolved — nothing to operate on."
        echo "   (CSV result column updated in: $(basename "$csv_file"))"
        return 1
    fi

    local _miss=$(( ${#_raw_entries[@]} - ${#selected_items[@]} ))
    echo "📌 Resolved ${#selected_items[@]} item(s)${_miss:+ ($__miss not found)}."
    echo "   CSV updated: $(basename "$csv_file")"
    echo ""
    return 0
}
