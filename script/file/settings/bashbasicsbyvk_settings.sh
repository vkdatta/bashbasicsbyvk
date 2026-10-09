CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk"
SETTINGS_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"

DEFAULT_SHOW_HIDDEN_FILES=false
DEFAULT_INDEX_MODE_THRESHOLD=200
DEFAULT_TERMINAL_BG_COLOR="000000"
DEFAULT_TERMINAL_TEXT_COLOR_NORMAL="FFFFFF"
DEFAULT_TERMINAL_TEXT_COLOR_CODER="00D000"

DEFAULT_SORT_MODE="az"
DEFAULT_DISPLAY_SUFFIX_SET=""
DEFAULT_DISPLAY_TIME_FORMAT="full"
DEFAULT_GROUP_VIEW_LEVELS=""
DEFAULT_COMPRESS_FORMAT="ask"
DEFAULT_UPLOAD_HIDDEN_MODE="follow"   # up- : follow | always | never | ask
DEFAULT_ZIP_HIDDEN_MODE="follow"      # z-  : follow | always | never | ask
DEFAULT_FILTER_MODE="partial"
DEFAULT_FILTER_HIDDEN_MODE="respect"
DEFAULT_FILTER_RECURSIVE=false      # = filter looks only in the folder you are viewing
DEFAULT_DISPLAY_FILTER_PERSIST=false
DEFAULT_ANIM_OUTER="pop"       # outer loop: whole screen appears at once
DEFAULT_ANIM_INNER="carpet"    # inner loops (fx / sw): rows roll in top to bottom

unset show_hidden_files
unset index_mode_threshold
unset terminal_bg_color
unset terminal_text_color
unset sort_mode
unset display_suffix_set
unset display_time_format
unset group_view_levels_str
unset compress_format
unset upload_hidden_mode
unset zip_hidden_mode
unset filter_mode
unset filter_hidden_mode
unset filter_recursive
unset display_filter_persist
unset anim_outer
unset anim_inner

[ -f "$SETTINGS_FILE" ] && source "$SETTINGS_FILE"

: "${show_hidden_files:=$DEFAULT_SHOW_HIDDEN_FILES}"
: "${index_mode_threshold:=$DEFAULT_INDEX_MODE_THRESHOLD}"
: "${terminal_bg_color:=$DEFAULT_TERMINAL_BG_COLOR}"
: "${terminal_text_color:=$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL}"
: "${sort_mode:=$DEFAULT_SORT_MODE}"
: "${display_suffix_set:=$DEFAULT_DISPLAY_SUFFIX_SET}"
: "${display_time_format:=$DEFAULT_DISPLAY_TIME_FORMAT}"
: "${group_view_levels_str:=$DEFAULT_GROUP_VIEW_LEVELS}"
: "${compress_format:=$DEFAULT_COMPRESS_FORMAT}"
: "${upload_hidden_mode:=$DEFAULT_UPLOAD_HIDDEN_MODE}"
: "${zip_hidden_mode:=$DEFAULT_ZIP_HIDDEN_MODE}"
[[ "$upload_hidden_mode" =~ ^(follow|always|never|ask)$ ]] || upload_hidden_mode=$DEFAULT_UPLOAD_HIDDEN_MODE
[[ "$zip_hidden_mode" =~ ^(follow|always|never|ask)$ ]] || zip_hidden_mode=$DEFAULT_ZIP_HIDDEN_MODE
: "${filter_mode:=$DEFAULT_FILTER_MODE}"
: "${filter_hidden_mode:=$DEFAULT_FILTER_HIDDEN_MODE}"
: "${filter_recursive:=$DEFAULT_FILTER_RECURSIVE}"
[[ "$filter_recursive" == true || "$filter_recursive" == false ]] || filter_recursive=$DEFAULT_FILTER_RECURSIVE
: "${display_filter_persist:=$DEFAULT_DISPLAY_FILTER_PERSIST}"
: "${anim_outer:=$DEFAULT_ANIM_OUTER}"
: "${anim_inner:=$DEFAULT_ANIM_INNER}"
[[ "$anim_outer" == pop || "$anim_outer" == carpet ]] || anim_outer=$DEFAULT_ANIM_OUTER
[[ "$anim_inner" == pop || "$anim_inner" == carpet ]] || anim_inner=$DEFAULT_ANIM_INNER

declare -ga group_view_levels=()
if [ -n "$group_view_levels_str" ]; then
  read -ra group_view_levels <<< "$group_view_levels_str"
fi

save_settings() {
  {
    echo "show_hidden_files=$show_hidden_files"
    echo "index_mode_threshold=$index_mode_threshold"
    echo "terminal_bg_color=$terminal_bg_color"
    echo "terminal_text_color=$terminal_text_color"
    echo "sort_mode=$sort_mode"
    echo "display_suffix_set=\"$display_suffix_set\""
    echo "display_time_format=$display_time_format"
    echo "group_view_levels_str=\"${group_view_levels[*]}\""
    echo "compress_format=$compress_format"
    echo "upload_hidden_mode=$upload_hidden_mode"
    echo "zip_hidden_mode=$zip_hidden_mode"
    echo "filter_mode=$filter_mode"
    echo "filter_hidden_mode=$filter_hidden_mode"
    echo "filter_recursive=$filter_recursive"
    echo "display_filter_persist=$display_filter_persist"
    echo "anim_outer=$anim_outer"
    echo "anim_inner=$anim_inner"
  } > "$SETTINGS_FILE"
}

_GREEN='\033[0;32m'
_RESET='\033[0m'
_BOLD='\033[1m'


# ════════════════════════════════════════════════════════════════════════════
#  Settings menu  (s)
#     type a number to choose · ↑↓ move · space/enter change · u back · q close
#  Every screen below is a  build  function (rows) + an  act  function (what a
#  row does) run by _st_run in bashbasicsbyvk_settings_ui.sh.
# ════════════════════════════════════════════════════════════════════════════

# ── top level ────────────────────────────────────────────────────────────────
_ST_SORT_MODES=(az za new old big small)
_ST_SORT_LABELS=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")

_st_top_build() {
  local i sl="$sort_mode" gv="off" dv="off" sx="${display_suffix_set:-none}"
  for i in "${!_ST_SORT_MODES[@]}"; do
    [ "${_ST_SORT_MODES[$i]}" = "$sort_mode" ] && sl="${_ST_SORT_LABELS[$i]}"
  done
  (( ${#group_view_levels[@]} > 0 )) && gv="${group_view_levels[*]}"
  if declare -F _disp_load >/dev/null 2>&1 && _disp_load; then dv="on"; fi
  _st_reset
  local hf="hide"; [ "$show_hidden_files" = true ] && hf="show"
  _st_add a "Hidden files"        0 "$hf"                               hidden
  _st_add a "Sort order"          0 "$sl"                               sort
  _st_add a "File details"        0 "$sx"                               details
  _st_add a "Group by"            0 "$gv"                               group
  _st_add a "Display filter (.d)" 0 "$dv"                               dfilter
  local fv="$filter_mode"; [ "$filter_recursive" = true ] && fv="$filter_mode · recursive"
  _st_add a "Search filter (=)"   0 "$fv"                               filter
  _st_add a "Compress format"     0 "$compress_format"                  compress
  _st_add a "Upload hidden (up-)" 0 "$(_hidden_mode_label "$upload_hidden_mode")" uphidden
  _st_add a "Zip hidden (z-)"     0 "$(_hidden_mode_label "$zip_hidden_mode")"    ziphidden
  _st_add a "Animation"           0 "$anim_outer / $anim_inner"         anim
  _st_add a "Big-folder limit"    0 "$index_mode_threshold"             index
  _st_add a "Background color"    0 "#$terminal_bg_color"               bg
  _st_add a "Text color"          0 "#$terminal_text_color"             fg
  _st_add a "Import nano settings" 0 ""                                 nano
  _st_add a "Reset all settings"  0 ""                                  reset
}

_st_top_act() {
  case "${_st_tag[$1]}" in
    hidden)   hidden_file_settings ;;
    sort)     sort_order_settings ;;
    details)  display_suffix_settings ;;
    group)    group_view_settings ;;
    dfilter)  display_filter_settings ;;
    filter)   filter_mode_settings ;;
    compress) compress_format_settings ;;
    uphidden) upload_hidden_settings ;;
    ziphidden) zip_hidden_settings ;;
    anim)     animation_settings ;;
    index)    index_mode_threshold_settings ;;
    bg)       terminal_bg_color_settings ;;
    fg)       terminal_text_color_settings ;;
    nano)     import_nanorc_settings; _st_note "✅ nano settings added" ;;
    reset)    restore_all_defaults ;;
  esac
}

settings_menu() {
  builtin printf '\n'          # breathing space between the main menu and Settings
  _st_run "Settings" _st_top_build _st_top_act
  _st_quit=0
  builtin printf '\n'
}

# ── sort order ───────────────────────────────────────────────────────────────
_st_sort_build() {
  local i
  _st_reset
  for i in "${!_ST_SORT_MODES[@]}"; do
    _st_eq "${_ST_SORT_MODES[$i]}" "$sort_mode"
    _st_add r "${_ST_SORT_LABELS[$i]}" "$_o" "" "${_ST_SORT_MODES[$i]}"
  done
}
_st_sort_act() {
  sort_mode="${_st_tag[$1]}"
  _items_presorted=false
  save_settings
}
sort_order_settings() { _st_run "Sort order" _st_sort_build _st_sort_act; }

# ── file details (what is shown after each name) + time format ───────────────
_ST_SFX_TOKENS=(ext size time children)
_ST_SFX_LABELS=("Extension" "Size" "Modified time" "Item count (folders)")
_ST_TF_KEYS=(year month date datetime monthdate full)
_ST_TF_LABELS=("Year" "Month" "Day" "Day + time" "Month-day + time" "Full date + time")
_ST_TF_EXAMPLES=("2023" "Mar" "15" "15 14:32" "Mar-15 14:32" "2023-Mar-15 14:32")

_st_sfx_build() {
  local i
  _st_reset
  _st_add h "Show after each name"
  for i in "${!_ST_SFX_TOKENS[@]}"; do
    [[ " $display_suffix_set " == *" ${_ST_SFX_TOKENS[$i]} "* ]] && _o=1 || _o=0
    _st_add t "${_ST_SFX_LABELS[$i]}" "$_o" "" "sfx:${_ST_SFX_TOKENS[$i]}"
  done
  _st_add h "Time format"
  for i in "${!_ST_TF_KEYS[@]}"; do
    _st_eq "${_ST_TF_KEYS[$i]}" "$display_time_format"
    _st_add r "${_ST_TF_LABELS[$i]}" "$_o" "${_ST_TF_EXAMPLES[$i]}" "tf:${_ST_TF_KEYS[$i]}"
  done
}
_st_sfx_act() {
  local tag="${_st_tag[$1]}" tok new="" t
  case "$tag" in
    tf:*) display_time_format="${tag#tf:}" ;;
    sfx:*)
      tok="${tag#sfx:}"
      if [[ " $display_suffix_set " == *" $tok "* ]]; then
        for t in $display_suffix_set; do [ "$t" = "$tok" ] || new+="${new:+ }$t"; done
      else
        new="${display_suffix_set:+$display_suffix_set }$tok"
      fi
      display_suffix_set="$new" ;;
  esac
  save_settings
}
display_suffix_settings() { _st_run "File details" _st_sfx_build _st_sfx_act; }

# ── group view (check = level is used; ←/→ changes its position) ─────────────
_ST_GV_LEVELS=(ext year month date)
_ST_GV_LABELS=("Extension" "Year" "Month" "Date")
_ST_ORD=(1st 2nd 3rd 4th)

_st_gv_build() {
  local i j pos
  _st_reset
  for i in "${!_ST_GV_LEVELS[@]}"; do
    pos=""
    for j in "${!group_view_levels[@]}"; do
      [ "${group_view_levels[$j]}" = "${_ST_GV_LEVELS[$i]}" ] && pos="${_ST_ORD[$j]}"
    done
    [ -n "$pos" ] && _o=1 || _o=0
    _st_add t "${_ST_GV_LABELS[$i]}" "$_o" "$pos" "${_ST_GV_LEVELS[$i]}"
  done
}
_st_gv_act() {
  local lvl="${_st_tag[$1]}" key="$2" j pos=-1 other
  local -a new=()
  for j in "${!group_view_levels[@]}"; do
    [ "${group_view_levels[$j]}" = "$lvl" ] && pos=$j
  done
  case "$key" in
    toggle)
      if (( pos >= 0 )); then
        for j in "${!group_view_levels[@]}"; do (( j == pos )) || new+=("${group_view_levels[$j]}"); done
        group_view_levels=("${new[@]}")
      else
        group_view_levels+=("$lvl")
      fi ;;
    left|right)
      (( pos < 0 )) && return
      [ "$key" = left ] && other=$(( pos - 1 )) || other=$(( pos + 1 ))
      (( other < 0 || other >= ${#group_view_levels[@]} )) && return
      new=("${group_view_levels[@]}")
      new[$pos]="${group_view_levels[$other]}"; new[$other]="$lvl"
      group_view_levels=("${new[@]}") ;;
  esac
  group_view_levels_str="${group_view_levels[*]}"
  save_settings
}
group_view_settings() {
  _st_run "Group by" _st_gv_build _st_gv_act "←/→ change order"
}

# ── animation ────────────────────────────────────────────────────────────────
_st_anim_build() {
  _st_reset
  _st_add h "Main screens"
  _st_eq "$anim_outer" pop;    _st_add r "pop      (appears at once)"   "$_o" "" o:pop
  _st_eq "$anim_outer" carpet; _st_add r "carpet   (rows roll in)"      "$_o" "" o:carpet
  _st_add h "Inner loops  (fx / sw)"
  _st_eq "$anim_inner" pop;    _st_add r "pop      (appears at once)"   "$_o" "" i:pop
  _st_eq "$anim_inner" carpet; _st_add r "carpet   (rows roll in)"      "$_o" "" i:carpet
}
_st_anim_act() {
  case "${_st_tag[$1]}" in
    o:*) anim_outer="${_st_tag[$1]#o:}" ;;
    i:*) anim_inner="${_st_tag[$1]#i:}" ;;
  esac
  save_settings
  declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
}
animation_settings() { _st_run "Animation" _st_anim_build _st_anim_act; }

# ── reset ────────────────────────────────────────────────────────────────────
_st_reset_build() {
  _st_reset
  _st_add h "Reset every setting to its default"
  _st_add a "Reset  ·  white text"         0 "" normal
  _st_add a "Reset  ·  green (coder) text" 0 "" coder
}
_st_reset_act() {
  show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES
  index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD
  sort_mode=$DEFAULT_SORT_MODE
  display_suffix_set=$DEFAULT_DISPLAY_SUFFIX_SET
  display_time_format=$DEFAULT_DISPLAY_TIME_FORMAT
  group_view_levels=(); group_view_levels_str=""
  compress_format=$DEFAULT_COMPRESS_FORMAT
  upload_hidden_mode=$DEFAULT_UPLOAD_HIDDEN_MODE
  zip_hidden_mode=$DEFAULT_ZIP_HIDDEN_MODE
  filter_mode=$DEFAULT_FILTER_MODE
  filter_hidden_mode=$DEFAULT_FILTER_HIDDEN_MODE
  filter_recursive=$DEFAULT_FILTER_RECURSIVE
  display_filter_persist=$DEFAULT_DISPLAY_FILTER_PERSIST
  anim_outer=$DEFAULT_ANIM_OUTER
  anim_inner=$DEFAULT_ANIM_INNER
  _items_presorted=false
  _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"
  case "${_st_tag[$1]}" in
    coder) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
    *)     _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
  esac
  save_settings
  _st_note "✅ All settings reset"
  _st_back=1
}
restore_all_defaults() { _st_run "Reset all settings" _st_reset_build _st_reset_act; }

# warm up the carpet writer in the background (no cost when both loops use pop)
declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
