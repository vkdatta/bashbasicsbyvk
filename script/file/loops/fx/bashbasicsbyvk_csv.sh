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
# _file_picker <ext> <outvar> [start_path]
# The ONE picker behind open_csv_menu and open_zip_menu: navigate folders and
# select a single file of type .<ext> (case-insensitive).
#   success : sets the global named by <outvar> to the file → returns 0
#   cancel  : sets that global to ""                       → returns 1
#   quit    : exits the program
# ---------------------------------------------------------------------------
_file_picker() {
    local _fp_ext="$1" _fp_outname="$2"
    local _fp_EXT="${_fp_ext^^}"
    local -n _fp_out="$_fp_outname"
    local start_path="${3:-${nav_last_browsed_path:-${path:-$(pwd)}}}"
    _fp_out=""
    local _fp_nav_path="$start_path"

    # case-insensitive glob for the extension:  csv → [cC][sS][vV]
    local _fp_pat="" _fp_i _fp_c
    for (( _fp_i=0; _fp_i<${#_fp_ext}; _fp_i++ )); do
        _fp_c="${_fp_ext:_fp_i:1}"
        _fp_pat+="[${_fp_c,,}${_fp_c^^}]"
    done

    echo ""
    echo "📂 Navigate to select your ${_fp_EXT} file (folders and .${_fp_ext} files only)"

    while true; do
        echo ""
        echo "📂 ${_fp_EXT} SELECT — Location: $_fp_nav_path"

        # ── Build item list: dirs + matching files only ───────────────────
        # Pure-bash globbing: no find, no sort, no per-file loop, no forks.
        #   "*/"          -> directories only (one readdir)
        #   "*.[cC]..."   -> matching files via the glob itself
        local -a _fp_items=()
        local _e _sg
        _sg=$(shopt -p nullglob dotglob nocaseglob)
        shopt -s nullglob dotglob
        shopt -u nocaseglob
        local _dir="${_fp_nav_path%/}"
        for _e in "$_dir"/*/; do
            _fp_items+=("${_e%/}")
        done
        for _e in "$_dir"/*.$_fp_pat; do
            [ -d "$_e" ] || _fp_items+=("$_e")
        done
        eval "$_sg"

        # ── Render list (single rule at the bottom only — the fx menu above
        #    already ends with its own rule, so a top rule here doubled it) ──
        if [ ${#_fp_items[@]} -eq 0 ]; then
            echo "  🛑 No folders or ${_fp_EXT} files here."
        else
            local _i=1
            for _it in "${_fp_items[@]}"; do
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
        read -p "${_fp_EXT} Nav: " _fp_choice

        # strip surrounding whitespace
        _fp_choice="${_fp_choice#"${_fp_choice%%[![:space:]]*}"}"
        _fp_choice="${_fp_choice%"${_fp_choice##*[![:space:]]}"}"

        case "$_fp_choice" in
            q|Q) exit 0 ;;

            x|X)
                echo "🚫 ${_fp_EXT} selection cancelled."
                _fp_out=""
                return 1
                ;;

            u|U)
                if [ "$_fp_nav_path" != "/" ]; then
                    _fp_nav_path=$(dirname "$_fp_nav_path")
                else
                    echo "  ⚠️  Already at filesystem root."
                fi
                ;;

            "")
                echo "  ⚠️  No input — enter a number, u, x, or q."
                ;;

            *)
                if [[ "$_fp_choice" =~ ^[0-9]+$ ]] \
                   && [ "$_fp_choice" -ge 1 ] \
                   && [ "$_fp_choice" -le "${#_fp_items[@]}" ]; then
                    local _sel="${_fp_items[$((_fp_choice - 1))]}"
                    if [ -d "$_sel" ]; then
                        _fp_nav_path="$_sel"
                    else
                        _fp_out="$_sel"
                        echo "✅ Selected: $(basename "$_sel")"
                        return 0
                    fi
                else
                    echo "  ⚠️  Invalid — enter a number between 1 and ${#_fp_items[@]}."
                fi
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# open_csv_menu [start_path]
#   Navigate to and select a .csv file.
#   On success : sets global $csv_file  → returns 0
#   On cancel  : sets csv_file=""       → returns 1
#   On quit    : exits the program
# ---------------------------------------------------------------------------
open_csv_menu() { _file_picker csv csv_file "$@"; }

# ---------------------------------------------------------------------------
# open_zip_menu [start_path]
#   Same picker, for .zip files (used by UDF import).
#   On success : sets global $zip_file  → returns 0
#   On cancel  : sets zip_file=""       → returns 1
# ---------------------------------------------------------------------------
open_zip_menu() { _file_picker zip zip_file "$@"; }

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
#   - absolute path  (starts with /) -> existence test
#   - bare basename                  -> existence test of "$path/<name>"
#
# FAST: zero forks. No find, no per-name subshell, no directory scan --
# every name is a single [ -e ] test, so 10k names take milliseconds.
# SILENT: prints nothing per name. Results are returned in globals:
#
#   selected_items[]    deduplicated absolute paths that resolved
#   _csv_total          number of non-blank names read from the CSV
#   _csv_fail_names[]   names that did NOT resolve   (parallel arrays)
#   _csv_fail_reasons[] why each one failed
#
# Returns 1 only if the CSV is unusable (not set / no values at all).
# Does NOT modify the CSV file.
# ---------------------------------------------------------------------------
_csv_resolve_items() {
    selected_items=()
    _csv_fail_names=()
    _csv_fail_reasons=()
    _csv_total=0

    if [ -z "$csv_file" ] || [ ! -f "$csv_file" ]; then
        echo "❌ No CSV file set — call open_csv_menu first."
        return 1
    fi

    local -A _seen=()
    local _line _rest _cell _target _base="${path%/}"

    while IFS= read -r _line || [ -n "$_line" ]; do
        _line="${_line%$'\r'}"
        [ -z "$_line" ] && continue
        _rest="$_line,"
        while [ -n "$_rest" ]; do
            _cell="${_rest%%,*}"
            _rest="${_rest#*,}"
            _cell="${_cell#"${_cell%%[![:space:]]*}"}"
            _cell="${_cell%"${_cell##*[![:space:]]}"}"
            [ -z "$_cell" ] && continue
            _csv_total=$((_csv_total + 1))

            if [[ "$_cell" == /* ]]; then
                _target="$_cell"
                if [ ! -e "$_target" ] && [ ! -L "$_target" ]; then
                    _csv_fail_names+=("$_cell")
                    _csv_fail_reasons+=("absolute path does not exist")
                    continue
                fi
            elif [[ "$_cell" == */* ]]; then
                _csv_fail_names+=("$_cell")
                _csv_fail_reasons+=("relative sub-path not supported — use a bare name from the current folder or a full /absolute/path")
                continue
            elif [ "$_cell" = "." ] || [ "$_cell" = ".." ]; then
                _csv_fail_names+=("$_cell")
                _csv_fail_reasons+=("'.' and '..' are not valid item names")
                continue
            else
                _target="$_base/$_cell"
                if [ ! -e "$_target" ] && [ ! -L "$_target" ]; then
                    _csv_fail_names+=("$_cell")
                    _csv_fail_reasons+=("not found in $path")
                    continue
                fi
            fi

            if [ -n "${_seen["k:$_target"]+x}" ]; then
                _csv_fail_names+=("$_cell")
                _csv_fail_reasons+=("duplicate entry in CSV — already counted")
                continue
            fi
            _seen["k:$_target"]=1
            selected_items+=("$_target")
        done
    done < "$csv_file"

    if [ "$_csv_total" -eq 0 ]; then
        echo "❌ No values found in CSV."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _csv_print_failures
# Prints ONLY the failed names, one line each, with the reason.
# Prints nothing when everything succeeded.
# ---------------------------------------------------------------------------
_csv_print_failures() {
    local n="${#_csv_fail_names[@]}" i
    [ "$n" -eq 0 ] && return 0
    echo "⚠️  $n failed:"
    for i in "${!_csv_fail_names[@]}"; do
        printf '   ❌ %s — %s\n' "${_csv_fail_names[$i]}" "${_csv_fail_reasons[$i]}"
    done
}

# ---------------------------------------------------------------------------
# _csv_resolve_report <verb-label>
# Resolve + one summary line "x/n" + failed list. Used by map / upload.
# Returns 1 when nothing resolved (nothing to operate on).
# ---------------------------------------------------------------------------
_csv_resolve_report() {
    local label="${1:-Resolved}"
    _csv_resolve_items || return 1
    echo "📋 $label: ${#selected_items[@]}/${_csv_total} names"
    _csv_print_failures
    if [ ${#selected_items[@]} -eq 0 ]; then
        echo "❌ Nothing resolved — nothing to operate on."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# _csv_append_batch <buffer-file> <items...>
# Private, O(N) batch append used only by the CSV functions: one load, hash
# duplicate check, ONE append write.  (The shared staging _sp_append is left
# untouched.)  Sets:
#   _CSV_ADDED     count actually added
#   _CSV_DUPES[]   items that were already in the buffer
# ---------------------------------------------------------------------------
_csv_append_batch() {
    local file="$1"; shift
    local -a existing=() fresh=()
    _sp_load existing "$file"
    local -A _ab_seen=()
    local p
    for p in "${existing[@]}"; do _ab_seen["k:$p"]=1; done
    _CSV_DUPES=()
    for p in "$@"; do
        [ -z "$p" ] && continue
        if [ -n "${_ab_seen["k:$p"]+x}" ]; then
            _CSV_DUPES+=("$p")
        else
            _ab_seen["k:$p"]=1
            fresh+=("$p")
        fi
    done
    _CSV_ADDED=${#fresh[@]}
    [ "$_CSV_ADDED" -gt 0 ] && printf '%s\n' "${fresh[@]}" >> "$file"
    return 0
}

# ---------------------------------------------------------------------------
# _csv_stage_selected <buffer-file> <label>
# Resolve the CSV and stage every resolved item into a buffer with ONE
# file write. Prints "Staged for <label>: x/n names" + failed list only.
# ---------------------------------------------------------------------------
_csv_stage_selected() {
    local file="$1" label="$2"
    _csv_resolve_items || return 1
    _sp_ensure_store

    local staged=0 d
    if [ ${#selected_items[@]} -gt 0 ]; then
        _csv_append_batch "$file" "${selected_items[@]}"
        staged="$_CSV_ADDED"
        for d in "${_CSV_DUPES[@]}"; do
            _csv_fail_names+=("${d##*/}")
            _csv_fail_reasons+=("already staged in the $label buffer — skipped")
        done
    fi

    echo "📌 Staged for $label: ${staged}/${_csv_total} names"
    _csv_print_failures
    [ "$staged" -gt 0 ] && echo "➡️  Navigate to destination, then use d- to apply."
    return 0
}
