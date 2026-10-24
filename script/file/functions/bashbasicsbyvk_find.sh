# ── Multi Mutation (CSV): ONE reader and ONE writer for the "find,replace[,note]" file, used by all the multi-mutation screens ──
# _find_csv_read <csv-file> <finds-array> <reps-array>   fills both arrays (trimmed; rows with an empty find column are skipped)
_find_csv_read() {
  local -n _fr_finds="$2" _fr_reps="$3"
  local csv_find csv_rep _rest
  while IFS=, read -r csv_find csv_rep _rest || [ -n "$csv_find" ]; do
    csv_find="${csv_find#"${csv_find%%[![:space:]]*}"}"
    csv_find="${csv_find%"${csv_find##*[![:space:]]}"}"
    csv_find="${csv_find%$'\r'}"
    csv_rep="${csv_rep#"${csv_rep%%[![:space:]]*}"}"
    csv_rep="${csv_rep%"${csv_rep##*[![:space:]]}"}"
    csv_rep="${csv_rep%$'\r'}"
    [ -z "$csv_find" ] && continue
    _fr_finds+=("$csv_find")
    _fr_reps+=("$csv_rep")
  done < "$1"
}
# _find_csv_write_counts <csv-file> <counts-array> <word>   rewrites the file: every row with a find pattern gets "<count> <word>" as 3rd column
#   (the count may already be a whole phrase like "3 renamed, 5 instances": then <word> is empty)
_find_csv_write_counts() {
  local -n _fw_counts="$2"
  local csv_find csv_rep _rest tmp_csv="$1.tmp" write_idx=0 trimmed
  while IFS=, read -r csv_find csv_rep _rest || [ -n "$csv_find" ]; do
    trimmed="${csv_find#"${csv_find%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    trimmed="${trimmed%$'\r'}"
    [ -z "$trimmed" ] && { printf "%s,%s,%s\n" "$csv_find" "$csv_rep" "${_rest:-}"; continue; }
    printf "%s,%s,%s%s\n" "$csv_find" "$csv_rep" "${_fw_counts[$write_idx]:-0}" "${3:+ $3}"
    write_idx=$((write_idx + 1))
  done < "$1" > "$tmp_csv"
  mv "$tmp_csv" "$1"
}

# ════════════════════════════════════════════════════════════════════════════
#  Find menu  (f)
#     1 Find in names · 2 Find in contents · 3 Find in names and contents
#     4 Find & replace in names · 5 … in contents · 6 … in names and contents
#  All the work is done by the engine (bashbasicsbyvk_findrun.sh).  Every choice that can go more than one way is a SETTING
#  (Settings → Find & replace): match case, regex, flat / recursive, whole word, hidden files, … each one "ask every
#  time" or fixed.  Defaults: case = ask, regex = off, depth = ask.
# ════════════════════════════════════════════════════════════════════════════

# _find_ask <outvar> <question> <default-value> <key> <value> <label> [<key> <value> <label>]...
#   rc 0 answered · 1 back (u) · 2 quit (q)
_find_ask() {
  local out="$1" q="$2" def="$3" a i opts=""
  local -a ks=() vs=()
  shift 3
  while [ $# -ge 3 ]; do ks+=("$1"); vs+=("$2"); opts+="${opts:+ · }$1) $3"; shift 3; done
  while true; do
    echo "$q   $opts   (Enter = default · u) back   q) quit)"
    read -e -r -p "Choice: " a || return 1
    a="${a,,}"; a="${a%$'\r'}"
    case "$a" in
      u) return 1 ;;
      q) _bvk_quit; return 2 ;;
      "") printf -v "$out" '%s' "$def"; return 0 ;;
    esac
    for i in "${!ks[@]}"; do
      [ "$a" = "${ks[$i]}" ] && { printf -v "$out" '%s' "${vs[$i]}"; return 0; }
    done
    echo "🔴  Invalid answer"
  done
}

# _find_resolve_options <names|contents|both>
#   Turns the Find & replace settings into this run's options (_fo_*), asking only about the ones set to "ask every time".
#   rc 0 ready · 1 back / quit
_find_resolve_options() {
  local scope="$1" rc=0 mb
  _fr_scope="$scope"
  case "$find_depth_mode" in
    flat) _fo_depth=flat ;;
    recursive) _fo_depth=rec ;;
    *) _find_ask _fo_depth "📂 Where?" rec f flat "this folder only" r rec "all sub-folders too" || return 1 ;;
  esac
  case "$find_case_mode" in
    exact|any) _fo_case="$find_case_mode" ;;
    *) _find_ask _fo_case "🔠 Match case?" exact e exact "exact case" a any "any case" || return 1 ;;
  esac
  case "$find_regex_mode" in
    on) _fo_regex=1 ;;
    off) _fo_regex=0 ;;
    *) _find_ask _fo_regex "🧩 Pattern type?" 0 t 0 "plain text" r 1 "regex" || return 1 ;;
  esac
  case "$find_word_mode" in
    on) _fo_word=1 ;;
    off) _fo_word=0 ;;
    *) _find_ask _fo_word "🔤 Whole words only?" 0 n 0 "no" w 1 "yes" || return 1 ;;
  esac
  case "$find_hidden_mode" in
    include) _fo_hidden=1 ;;
    exclude) _fo_hidden=0 ;;
    *) [ "${show_hidden_files:-false}" = true ] && _fo_hidden=1 || _fo_hidden=0 ;;
  esac
  [ "$find_vcs_mode" = include ] && _fo_vcs=1 || _fo_vcs=0
  case "$find_target_mode" in files) _fo_target=files ;; folders) _fo_target=dirs ;; *) _fo_target=both ;; esac
  [ "$find_binary_mode" = include ] && _fo_binary=1 || _fo_binary=0
  mb="${find_maxsize_mb:-0}"; _fo_maxsize=$(( mb * 1048576 ))
  [ "$find_threads" = auto ] && _fo_threads=0 || _fo_threads="$find_threads"
  _fo_limit="${find_show_limit:-300}"
  _fr_root="$path"; _fr_only=""; _fr_excl=()
  return 0
}

# _find_options_line  — "recursive · exact case · plain text · hidden: no"
_find_options_line() {
  local d c r w h
  [ "$_fo_depth" = flat ] && d="this folder only" || d="all sub-folders"
  [ "$_fo_case" = any ] && c="any case" || c="exact case"
  [ "$_fo_regex" = 1 ] && r="regex" || r="plain text"
  [ "$_fo_word" = 1 ] && w=" · whole words" || w=""
  [ "$_fo_hidden" = 1 ] && h="yes" || h="no"
  echo "⚙️  $d · $c · $r$w · hidden files: $h"
}

# _find_pattern_prompt <names|contents|both> → "…" text for the question
_find_what() {
  local noun
  case "$1" in names) noun="file/folder names" ;; contents) noun="file contents" ;; *) noun="names and contents" ;; esac
  if [ "$_fo_regex" = 1 ]; then printf 'Regex to find in %s: ' "$noun"; else printf 'Text to find in %s: ' "$noun"; fi
}

# _find_numbers_summary → "3 name(s) to rename · 12 match(es) in 4 file(s)" for the current preview stats
_find_preview_summary() {
  local -a p=()
  [ "${_FRS[names_planned]:-0}" -gt 0 ] && p+=("${_FRS[names_planned]} name(s) to rename")
  [ "${_FRS[files_matched]:-0}" -gt 0 ] && p+=("${_FRS[occurrences]:-0} match(es) in ${_FRS[files_matched]} file(s)")
  [ "${_FRS[names_conflict]:-0}" -gt 0 ] && p+=("${_FRS[names_conflict]} name clash(es) (skipped)")
  [ "${_FRS[names_invalid]:-0}" -gt 0 ] && p+=("${_FRS[names_invalid]} unusable new name(s) (skipped)")
  local IFS=$'·'; printf '%s' "${p[*]//·/ · }"
}

# _find_apply_report — what an apply run did
_find_apply_report() {
  local n any=0
  n="${_FRS[names_renamed]:-0}";  if [ "$n" -gt 0 ]; then echo "💫 Renamed $n item(s)."; any=1; fi
  n="${_FRS[files_changed]:-0}";  if [ "$n" -gt 0 ]; then echo "💫 Replaced ${_FRS[occurrences]:-0} occurrence(s) in $n file(s)."; any=1; fi
  n="${_FRS[names_conflict]:-0}"; [ "$n" -gt 0 ] && echo "⚠️  $n rename(s) skipped: a file or folder with that name already exists (or two items wanted the same name)."
  n="${_FRS[names_invalid]:-0}";  [ "$n" -gt 0 ] && echo "⚠️  $n rename(s) skipped: the new name is empty, too long or contains a /."
  n="${_FRS[names_error]:-0}";    [ "$n" -gt 0 ] && echo "⚠️  $n rename(s) failed (see the lines above)."
  [ "$any" = 0 ] && echo "Nothing was changed."
  return 0
}

# ── 1-3  Find ────────────────────────────────────────────────────────────────
# rc 0 done (leave the menu) · 3 back to the Find menu · 1 quit
_find_search() {
  local scope="$1" pat act target n
  _find_resolve_options "$scope" || return 3
  _find_options_line
  read -e -r -p "$(_find_what "$scope")" pat || return 3
  [ -z "$pat" ] && { echo "Nothing entered."; return 0; }
  _fr_finds=("$pat"); _fr_reps=("")
  echo "⏳ Searching…"
  _fr_exec find || return 0
  n="${_FRS[listed]:-0}"
  if [ "$n" -eq 0 ]; then echo "No results."; _fr_notes; return 0; fi
  if [ "$n" -gt "${#_FR_LIST[@]}" ]; then n="${#_FR_LIST[@]}"; fi
  echo "📋 Found ${_FRS[listed]} result(s):"
  _fr_show
  _fr_notes
  echo "Enter item number to navigate"
  echo "u) Back   q) Quit"
  while true; do
    # rc!=0 = the command layer cancelled this flow (blocked command): leave at once
    read -e -p "Action: " act || return 0
    case "$act" in
      u|U) return 3 ;;
      q|Q) _bvk_quit; return 1 ;;
      [0-9]*)
        if [[ $act =~ ^[0-9]+$ ]] && (( act >= 1 && act <= ${#_FR_LIST[@]} )); then
          target="${_FR_LIST[$((act-1))]}"
          if [ -d "$target" ]; then path="$target"
          elif [ -f "$target" ]; then handle_file "$target"; fi
          return 0
        fi
        echo "Invalid. Use a number or q." ;;
      *) echo "Invalid. Use a number or q." ;;
    esac
  done
}

# ── 4-6  Find & replace, one pattern ─────────────────────────────────────────
_find_replace_single() {
  local scope="$1" pat rep act what="" idx
  _find_resolve_options "$scope" || return 3
  _find_options_line
  read -e -r -p "$(_find_what "$scope")" pat || return 3
  [ -z "$pat" ] && { echo "Nothing entered."; return 0; }
  read -e -r -p "Replace with: " rep || return 3
  _fr_finds=("$pat"); _fr_reps=("$rep")
  if [ "$find_confirm_mode" != direct ]; then
    echo "⏳ Looking…"
    _fr_exec preview || return 0
    if [ "${_FRS[listed]:-0}" -eq 0 ]; then echo "No matches found."; _fr_notes; return 0; fi
    echo "📋 Preview — $(_find_preview_summary):"
    _fr_show
    _fr_notes
    _mc_footer "a:Apply to ALL" "#Enter a number to apply to just that item" "u:Back" "q:Quit"
    read -e -r -p "Action: " act || return 0
    case "$act" in
      u|U) return 3 ;;
      q|Q) _bvk_quit; return 1 ;;
      a|A) ;;
      [0-9]*)
        if [[ $act =~ ^[0-9]+$ ]] && (( act >= 1 && act <= ${#_FR_LIST[@]} )); then
          _fr_only="${_FR_LIST[$((act-1))]}"
        else echo "Invalid number."; return 0; fi ;;
      *) _bvk_invalid; return 0 ;;
    esac
  fi
  echo "⏳ Applying…"
  _fr_exec apply || return 0
  _fr_changes_log                      # locks + shortcuts follow the renamed items
  _fr_show
  _find_apply_report
  _fr_notes
  return 0
}

# _find_csv_rows <preview|done>  — one line per CSV row; fills csv_counts[] with the text written back to the CSV
_find_csv_rows() {
  local mode="$1" i nn oc fl line verb_n verb_o
  csv_counts=()
  [ "$mode" = preview ] && { verb_n="to rename"; verb_o="would change"; } || { verb_n="renamed"; verb_o="replaced"; }
  for i in "${!csv_finds[@]}"; do
    nn="${_FRS[r${i}_names]:-0}"; oc="${_FRS[r${i}_occ]:-0}"; fl="${_FRS[r${i}_files]:-0}"
    local -a parts=() cnt=()
    parts=(); cnt=()
    if [ "$_fr_scope" != contents ]; then
      parts+=("$nn $verb_n"); cnt+=("$nn renamed")
    fi
    if [ "$_fr_scope" != names ]; then
      parts+=("$oc instance(s) in $fl file(s)"); cnt+=("$oc instances")
    fi
    local IFS=','; local joined="${parts[*]}"; local cjoined="${cnt[*]}"; unset IFS
    joined="${joined//,/, }"; cjoined="${cjoined//,/, }"
    if [ "$nn" -eq 0 ] && [ "$oc" -eq 0 ]; then
      echo "  Row $((i+1)): \"${csv_finds[$i]}\" → \"${csv_reps[$i]}\"  🔴  No matches"
      [ "$_fr_scope" = contents ] && csv_counts+=("0 instances") || { [ "$_fr_scope" = names ] && csv_counts+=("0 renamed") || csv_counts+=("0 renamed, 0 instances"); }
    else
      echo "  Row $((i+1)): \"${csv_finds[$i]}\" → \"${csv_reps[$i]}\"  💫 $joined"
      csv_counts+=("$cjoined")
    fi
  done
}

# ── 4-6  Find & replace, many rows from a CSV ───────────────────────────────
_find_replace_csv() {
  local scope="$1" abs_csv_file ok
  local -a csv_finds=() csv_reps=() csv_counts=()
  open_csv_menu || return 0
  [ -z "$csv_file" ] && return 0
  _find_resolve_options "$scope" || return 3
  echo ""
  echo "🔄 Reading rows from: $(basename "$csv_file")"
  _find_csv_read "$csv_file" csv_finds csv_reps
  if [ ${#csv_finds[@]} -eq 0 ]; then echo "❌ No valid rows found in CSV."; return 0; fi
  _find_options_line
  echo "📋 ${#csv_finds[@]} row(s), applied one after the other, in: $path"
  abs_csv_file="$(cd "$(dirname "$csv_file")" && pwd)/$(basename "$csv_file")"
  _fr_finds=("${csv_finds[@]}"); _fr_reps=("${csv_reps[@]}")
  _fr_excl=("$abs_csv_file")                  # the CSV itself is never edited or renamed
  echo "⏳ Looking…"
  _fr_exec preview || return 0
  _find_csv_rows preview
  echo ""
  if [ "${_FRS[names_planned]:-0}" -eq 0 ] && [ "${_FRS[files_matched]:-0}" -eq 0 ]; then
    echo "Nothing to change."
  elif [ "$find_confirm_mode" != direct ]; then
    echo "📋 Total — $(_find_preview_summary)"
    _fr_notes
    _bvk_yn ok "Apply all ${#csv_finds[@]} row(s)?" -d n || return 0
    [[ "$ok" =~ ^[Yy]$ ]] || { echo "Aborted."; return 0; }
  fi
  echo "⏳ Applying…"
  _fr_exec apply || return 0
  _fr_changes_log
  _find_csv_rows done
  echo ""
  echo "📝 Writing counts back to CSV..."
  _find_csv_write_counts "$csv_file" csv_counts ""
  echo "💫 CSV updated: $(basename "$csv_file")"
  _fr_show
  _find_apply_report
  _fr_notes
  echo "🎉 Multi Mutation complete — ${#csv_finds[@]} row(s) processed."
  return 0
}

# ── 4-6  Find & replace entry: Single or Multi ──────────────────────────────
_find_replace() {
  local scope="$1" title how
  case "$scope" in names) title="🔤 Find & Replace in file/folder names" ;; contents) title="🔄 Find & Replace inside file contents" ;; *) title="🔁 Find & Replace in names and contents" ;; esac
  case "$find_input_mode" in
    single) how=1 ;;
    csv)    how=2 ;;
    *)
      _mc_menu "$title" -- "Single Mutation" "Multi Mutation (CSV)" -- @back_quit
      read -e -p "Select: " how || return 0
      ;;
  esac
  case "$how" in
    u|U) return 3 ;;
    q|Q) _bvk_quit; return 1 ;;
    1) _find_replace_single "$scope" ;;
    2) _find_replace_csv "$scope" ;;
    *) echo "❌ Invalid mode."; return 0 ;;
  esac
}

find_menu() {
  local ftype rc
  while true; do
    _mc_menu "🔍 Find mode in: $path" -- \
      "Find file/folder names" "Find inside file contents" "Find in names and contents" \
      "Find & replace in file/folder names" "Find & replace inside file contents" "Find & replace in names and contents" \
      -- @back_quit
    read -e -p "Select: " ftype || return
    case "$ftype" in
      u|U) return ;;
      q|Q) _bvk_quit; return 1 ;;
      1) _find_search names ;;
      2) _find_search contents ;;
      3) _find_search both ;;
      4) _find_replace names ;;
      5) _find_replace contents ;;
      6) _find_replace both ;;
      *) return ;;
    esac
    rc=$?
    [ "$rc" -eq 3 ] && continue          # u inside a flow: back to this menu
    _fr_cleanup
    return "$rc"
  done
}
