# bashbasicsbyvk_findsettings.sh — Settings → Find & replace  (used by the Find menu f: bashbasicsbyvk_find.sh)
# ════════════════════════════════════════════════════════════════════════════
#  Every choice the Find menu can make in more than one way lives here, so the person decides once (or says "ask every time").
#     Match case · Regex · Flat / recursive · Whole words · Hidden files · What to look at (files / folders) ·
#     Binary files · Big files · .git / .hg / .svn · Preview before replacing · Single / CSV · Result limit · Threads
#  Needs: bashbasicsbyvk_settings_groups.sh (_st_choice_open _st_run _st_add), bashbasicsbyvk_settings.sh (save_settings).
# ════════════════════════════════════════════════════════════════════════════

_find_lbl() {   # _find_lbl <value> <value> <label> ...  → the label of the current value
  local cur="$1"; shift
  while [ $# -ge 2 ]; do [ "$1" = "$cur" ] && { printf '%s' "$2"; return; }; shift 2; done
  printf '%s' "$cur"
}

_st_fnd_build() {
  _st_reset
  _st_add h "Asked or fixed"
  _st_add a "Match case"        0 "$(_find_lbl "$find_case_mode" ask "ask every time" exact "exact case" any "any case")"       case
  _st_add a "Regex"             0 "$(_find_lbl "$find_regex_mode" ask "ask every time" on "on" off "off")"                      regex
  _st_add a "Flat / recursive"  0 "$(_find_lbl "$find_depth_mode" ask "ask every time" flat "this folder only" recursive "all sub-folders")" depth
  _st_add a "Whole words only"  0 "$(_find_lbl "$find_word_mode" ask "ask every time" on "on" off "off")"                       word
  _st_add a "Single / CSV"      0 "$(_find_lbl "$find_input_mode" ask "ask every time" single "single mutation" csv "multi (CSV)")" input
  _st_add h "What is searched"
  _st_add a "Hidden files"      0 "$(_find_lbl "$find_hidden_mode" follow "follow Display setting" include "include" exclude "skip")" hidden
  _st_add a "Files / folders"   0 "$(_find_lbl "$find_target_mode" both "both" files "files only" folders "folders only")"    target
  _st_add a "Binary files"      0 "$(_find_lbl "$find_binary_mode" skip "skip" include "include")"                              binary
  _st_add a "Big files"         0 "$([ "$find_maxsize_mb" = 0 ] && echo 'no limit' || echo "skip over ${find_maxsize_mb} MB")"  maxsize
  _st_add a ".git / .hg / .svn" 0 "$(_find_lbl "$find_vcs_mode" skip "skip" include "include")"                                  vcs
  _st_add h "Replacing and showing"
  _st_add a "Preview first"     0 "$(_find_lbl "$find_confirm_mode" preview "preview, then confirm" direct "replace straight away")" confirm
  _st_add a "Results shown"     0 "$([ "$find_show_limit" = 0 ] && echo all || echo "first $find_show_limit")"                  limit
  _st_add a "CPU threads"       0 "$find_threads"                                                                               threads
}
_st_fnd_act() {
  case "${_st_tag[$1]}" in
    case)  _st_choice_open "Match case" find_case_mode "Find & replace: match case" "💫 Saved" ask "Ask every time (default)" exact "Exact case" any "Any case" ;;
    regex) _st_choice_open "Regex" find_regex_mode "Find & replace: regex" "💫 Saved" off "Off — plain text (default)" on "On — always a regex" ask "Ask every time" ;;
    depth) _st_choice_open "Flat / recursive" find_depth_mode "Find & replace: where" "💫 Saved" ask "Ask every time (default)" flat "Flat — this folder only" recursive "Recursive — all sub-folders" ;;
    word)  _st_choice_open "Whole words" find_word_mode "Find & replace: whole words" "💫 Saved" off "Off (default)" on "On" ask "Ask every time" ;;
    input) _st_choice_open "Single / CSV" find_input_mode "Find & replace: how many patterns" "💫 Saved" ask "Ask every time (default)" single "Single mutation" csv "Multi mutation (CSV)" ;;
    hidden) _st_choice_open "Hidden files" find_hidden_mode "Find & replace: hidden files" "💫 Saved" follow "Follow the Display setting (default)" include "Always include" exclude "Always skip" ;;
    target) _st_choice_open "Files / folders" find_target_mode "Find & replace: look at" "💫 Saved" both "Files and folders (default)" files "Files only" folders "Folders only" ;;
    binary) _st_choice_open "Binary files" find_binary_mode "Find & replace: binary files (contents)" "💫 Saved" skip "Skip (default, safe)" include "Include" ;;
    maxsize) _st_choice_open "Big files" find_maxsize_mb "Find & replace: skip files bigger than" "💫 Saved" 50 "50 MB" 200 "200 MB (default)" 1000 "1 GB" 0 "No limit" ;;
    vcs)   _st_choice_open ".git / .hg / .svn" find_vcs_mode "Find & replace: version-control folders" "💫 Saved" skip "Skip (default, safe)" include "Include" ;;
    confirm) _st_choice_open "Preview first" find_confirm_mode "Find & replace: before changing anything" "💫 Saved" preview "Show a preview, then confirm (default)" direct "Replace straight away" ;;
    limit) _st_choice_open "Results shown" find_show_limit "Find & replace: how many results to print" "💫 Saved" 100 "First 100" 300 "First 300 (default)" 1000 "First 1000" 0 "All" ;;
    threads) _st_choice_open "CPU threads" find_threads "Find & replace: worker threads" "💫 Saved" auto "Auto (default)" 1 "1" 2 "2" 4 "4" 8 "8" ;;
  esac
}
find_group_settings() { _st_run "Find & replace" _st_fnd_build _st_fnd_act; }
