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
#   One question of the Find & replace settings = the shared two-option template (menuchrome.sh, MC-01/02): numbered rows,
#   the standard footer, "Select:".  <key> stays accepted as a typed alias; Enter picks <default-value>.
#   rc 0 answered · 1 back (u) · 2 quit (q: the unwind flag is up) · 3 cancelled
_find_ask() {
  local out="$1" q="$2" def="$3"; shift 3
  local -a rows=()
  while [ $# -ge 3 ]; do rows+=("$2|$3|$1"); shift 3; done
  _mc_select -d "$def" "$out" "$q" "${rows[@]}"
}

# One Find & replace question = one step for _mc_steps (menuchrome.sh STEPS-01): rc 0 answered · 1 back (u) · 2 quit · 3 cancelled.
_find_step_depth() { _find_ask _fo_depth "📂 Where?" rec f flat "this folder only" r rec "all sub-folders too"; }
_find_step_case()  { _find_ask _fo_case "🔠 Match case?" exact e exact "exact case" a any "any case"; }
_find_step_regex() { _find_ask _fo_regex "🧩 Pattern type?" 0 t 0 "plain text" r 1 "regex"; }
_find_step_word()  { _find_ask _fo_word "🔤 Whole words only?" 0 n 0 "no" w 1 "yes"; }
# The typed questions are steps too, on the shared text prompt (it prints u) Back, so u reaches it as the menu's own key).
_find_step_pattern() {
  _fo_pat=""
  _mc_text _fo_pat "$(_find_what "$_fr_scope")" "$(_find_options_line)" || return $?
  [ -z "$_fo_pat" ] && { echo "Nothing entered."; return 3; }
  return 0
}
_find_step_replacement() { _fo_rep=""; _mc_text _fo_rep "Replace with: "; }

# _find_resolve_options <names|contents|both> [PRESTEP...] [-- STEP...]
#   Turns the Find & replace settings into this run's options (_fo_*), then runs ONE flow through _mc_steps:
#   PRESTEPs, the questions set to "ask every time" (settled ones are not steps), then the STEPs.  u = one question back.
#   rc 0 every step answered · 1 u on the first question · 2 quit (q was pressed: nothing may be drawn again) · 3 cancelled
_find_resolve_options() {
  local scope="$1" mb; shift
  local -a steps=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do steps+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  _fr_scope="$scope"
  case "$find_depth_mode" in
    flat) _fo_depth=flat ;;
    recursive) _fo_depth=rec ;;
    *) steps+=(_find_step_depth) ;;
  esac
  case "$find_case_mode" in
    exact|any) _fo_case="$find_case_mode" ;;
    *) steps+=(_find_step_case) ;;
  esac
  case "$find_regex_mode" in
    on) _fo_regex=1 ;;
    off) _fo_regex=0 ;;
    *) steps+=(_find_step_regex) ;;
  esac
  case "$find_word_mode" in
    on) _fo_word=1 ;;
    off) _fo_word=0 ;;
    *) steps+=(_find_step_word) ;;
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
  steps+=("$@")
  _mc_steps "${steps[@]}"
}

# _find_flow_rc <steps rc> → the rc of the flow functions below:  0 finished (leave Find) · 3 u = back to the menu above · 1 quit
_find_flow_rc() { case "$1" in 1) return 3 ;; 2) return 1 ;; *) return 0 ;; esac; }

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
  _find_resolve_options "$1" -- _find_step_pattern _find_step_results
  _find_flow_rc $?
}

# the last step of Find: run it and list the hits.  u = back to the question before (the text to find)
_find_step_results() {
  local pat="$_fo_pat" act target n
  _fr_finds=("$pat"); _fr_reps=("")
  echo "⏳ Searching…"
  _fr_exec find || return 0
  n="${_FRS[listed]:-0}"
  if [ "$n" -eq 0 ]; then echo "No results."; _fr_notes; return 0; fi
  if [ "$n" -gt "${#_FR_LIST[@]}" ]; then n="${#_FR_LIST[@]}"; fi
  echo "📋 Found ${_FRS[listed]} result(s):"
  _fr_show
  _fr_notes
  while true; do
    # rc != 0 = back / quit / the command layer cancelled this flow: leave at once
    _mc_text -x "#Enter item number to navigate" act "Select: "
    case $? in 1) return 1 ;; 2) return 2 ;; 3) return 0 ;; esac
    if [[ $act =~ ^[0-9]+$ ]] && (( act >= 1 && act <= ${#_FR_LIST[@]} )); then
      target="${_FR_LIST[$((act-1))]}"
      if [ -d "$target" ]; then path="$target"
      elif [ -f "$target" ]; then handle_file "$target"; fi
      return 0
    fi
    echo "Invalid. Use a number or q."
  done
}

# ── 4-6  Find & replace, one pattern ─────────────────────────────────────────
_find_replace_single() {
  _find_resolve_options "$1" -- _find_step_pattern _find_step_replacement _find_step_preview
  _find_flow_rc $?
}

# the last step of a single replace: preview, choose what to apply, apply.  u = back to "Replace with:"
_find_step_preview() {
  local pat="$_fo_pat" rep="$_fo_rep" act
  _fr_finds=("$pat"); _fr_reps=("$rep")
  if [ "$find_confirm_mode" != direct ]; then
    echo "⏳ Looking…"
    _fr_exec preview || return 0
    if [ "${_FRS[listed]:-0}" -eq 0 ]; then echo "No matches found."; _fr_notes; return 0; fi
    echo "📋 Preview — $(_find_preview_summary):"
    _fr_show
    _fr_notes
    # MC-06: the preview rows ARE the numbered choices; the footer adds a) Apply to ALL to the standard keys
    _mc_text -x "a:Apply to ALL" -x "#Enter a number to apply to just that item" act "Select: "
    case $? in 1) return 1 ;; 2) return 2 ;; 3) return 0 ;; esac
    case "$act" in
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
# Steps (in order): pick the CSV (z = back) · the questions set to "ask every time" · read + preview + "Apply all?" (u = back).
# They share the locals of _find_replace_csv (csv_finds, csv_reps, abs_csv_file).
_find_step_csvfile() {
  open_csv_menu && [ -n "$csv_file" ] && return 0
  _mc_unwind && return 2
  return 1                                       # z / nothing picked = back one menu (Single / Multi)
}
_find_step_csv_confirm() {
  local ok
  csv_finds=(); csv_reps=(); csv_counts=()
  echo ""
  echo "🔄 Reading rows from: $(basename "$csv_file")"
  _find_csv_read "$csv_file" csv_finds csv_reps
  if [ ${#csv_finds[@]} -eq 0 ]; then echo "❌ No valid rows found in CSV."; return 3; fi
  _find_options_line
  echo "📋 ${#csv_finds[@]} row(s), applied one after the other, in: $path"
  abs_csv_file="$(cd "$(dirname "$csv_file")" && pwd)/$(basename "$csv_file")"
  _fr_finds=("${csv_finds[@]}"); _fr_reps=("${csv_reps[@]}")
  _fr_excl=("$abs_csv_file")                  # the CSV itself is never edited or renamed
  echo "⏳ Looking…"
  _fr_exec preview || return 3
  _find_csv_rows preview
  echo ""
  if [ "${_FRS[names_planned]:-0}" -eq 0 ] && [ "${_FRS[files_matched]:-0}" -eq 0 ]; then
    echo "Nothing to change."
  elif [ "$find_confirm_mode" != direct ]; then
    echo "📋 Total — $(_find_preview_summary)"
    _fr_notes
    _bvk_yn ok "Apply all ${#csv_finds[@]} row(s)?" || { _mc_unwind && return 2; return 1; }   # u = back one question
    [[ "$ok" =~ ^[Yy]$ ]] || { echo "Aborted."; return 3; }
  fi
  return 0
}
_find_replace_csv() {
  local scope="$1" abs_csv_file rc
  local -a csv_finds=() csv_reps=() csv_counts=()
  _find_resolve_options "$scope" _find_step_csvfile -- _find_step_csv_confirm
  rc=$?
  [ "$rc" -eq 0 ] || { _find_flow_rc "$rc"; return $?; }
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
# u inside Single / Multi goes back to THIS question when the person was asked it (setting "ask"), else to the Find menu.
_find_replace() {
  local scope="$1" title how rc
  case "$scope" in names) title="🔤 Find & Replace in file/folder names" ;; contents) title="🔄 Find & Replace inside file contents" ;; *) title="🔁 Find & Replace in names and contents" ;; esac
  while true; do
    case "$find_input_mode" in
      single) how=1 ;;
      csv)    how=2 ;;
      *) _mc_select how "$title" "Single Mutation" "Multi Mutation (CSV)" || return $(( $? == 2 ? 1 : 3 )) ;;
    esac
    case "$how" in
      1) _find_replace_single "$scope" ;;
      2) _find_replace_csv "$scope" ;;
    esac
    rc=$?
    if [ "$rc" -eq 3 ] && [ "$find_input_mode" != single ] && [ "$find_input_mode" != csv ]; then continue; fi
    return "$rc"
  done
}

find_menu() {
  local ftype rc
  while true; do
    _mc_select ftype "🔍 Find mode in: $path" \
      "Find file/folder names" "Find inside file contents" "Find in names and contents" \
      "Find & replace in file/folder names" "Find & replace inside file contents" "Find & replace in names and contents"
    case $? in 0) ;; 2) return 1 ;; *) return 0 ;; esac          # u = back · q = quit (flag up) · cancelled
    case "$ftype" in
      1) _find_search names ;;
      2) _find_search contents ;;
      3) _find_search both ;;
      4) _find_replace names ;;
      5) _find_replace contents ;;
      6) _find_replace both ;;
    esac
    rc=$?
    _mc_unwind && { _fr_cleanup; return 1; }                      # q anywhere below: never draw the Find menu again
    [ "$rc" -eq 3 ] && continue          # u inside a flow: back to this menu
    _fr_cleanup
    return "$rc"
  done
}
