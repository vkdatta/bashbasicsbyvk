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
#    Reads EVERY comma-separated value from EVERY non-blank line of $csv_file.
#    Resolves each value as an absolute path (starts with /) or a basename
#    matched in $path (maxdepth 1).
#    On success : populates global selected_items[]  → returns 0
#    On failure : prints error, selected_items=()    → returns 1
#    Does NOT modify the CSV file.
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
        echo "   ─────────────────────────────"
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
        echo "   ─────────────────────────────"
        read -p "CSV Nav: " _csv_choice

        # strip surrounding whitespace
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
                    echo "  ⚠️  Invalid — enter a number between 1 and ${#_csv_items[@]}."
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
# Reads EVERY comma-separated value from EVERY non-blank line of $csv_file.
# Each value is resolved as:
#   - absolute path  (starts with /) → checked with -e
#   - basename       → matched against $path at maxdepth 1
#
# Populates selected_items[] with deduplicated absolute paths.
# Does NOT touch the CSV file.
# Returns 0 if at least one item resolved, 1 otherwise.
# ---------------------------------------------------------------------------
_csv_resolve_items() {
    selected_items=()

    if [ -z "$csv_file" ] || [ ! -f "$csv_file" ]; then
        echo "❌ No CSV file set — call open_csv_menu first."
        return 1
    fi

    echo ""
    echo "🔎 Resolving items from: $(basename "$csv_file")"
    echo "   Search path: $path"
    echo ""

    # ── Collect every non-blank cell from every row ───────────────────────
    local -a _raw_entries=()
    local _line
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line="${_line%$'\r'}"
        [ -z "$_line" ] && continue
        local _old_IFS="$IFS"
        IFS=',' read -ra _cells <<< "$_line"
        IFS="$_old_IFS"
        local _cell
        for _cell in "${_cells[@]}"; do
            _cell="${_cell#"${_cell%%[![:space:]]*}"}"
            _cell="${_cell%"${_cell##*[![:space:]]}"}"
            [ -z "$_cell" ] && continue
            _raw_entries+=("$_cell")
        done
    done < "$csv_file"

    if [ ${#_raw_entries[@]} -eq 0 ]; then
        echo "❌ No values found in CSV."
        return 1
    fi

    echo "📋 Found ${#_raw_entries[@]} value(s) to resolve."
    echo ""

    # ── Resolve each value ────────────────────────────────────────────────
    local -A _seen=()
    local _entry _abs

    for _entry in "${_raw_entries[@]}"; do
        if [[ "$_entry" == /* ]]; then
            # absolute path
            if [ -e "$_entry" ]; then
                if [ -z "${_seen[$_entry]+x}" ]; then
                    selected_items+=("$_entry")
                    _seen["$_entry"]=1
                fi
                echo "  ✅ $_entry"
            else
                echo "  ⚠️  Not found: $_entry"
            fi
        else
            # basename match in $path
            local -a _matched=()
            while IFS= read -r -d '' _f; do
                [ "${_f##*/}" = "$_entry" ] && _matched+=("$_f")
            done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

            if [ ${#_matched[@]} -eq 0 ]; then
                echo "  ⚠️  Not found: $_entry"
            else
                for _abs in "${_matched[@]}"; do
                    if [ -z "${_seen[$_abs]+x}" ]; then
                        selected_items+=("$_abs")
                        _seen["$_abs"]=1
                    fi
                done
                echo "  ✅ $_entry"
            fi
        fi
    done

    echo ""
    if [ ${#selected_items[@]} -eq 0 ]; then
        echo "❌ No items resolved — nothing to operate on."
        return 1
    fi

    echo "📌 Resolved ${#selected_items[@]} item(s)."
    echo ""
    return 0
}
