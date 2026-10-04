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
DEFAULT_FILTER_MODE="partial"
DEFAULT_FILTER_HIDDEN_MODE="respect"
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
unset filter_mode
unset filter_hidden_mode
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
: "${filter_mode:=$DEFAULT_FILTER_MODE}"
: "${filter_hidden_mode:=$DEFAULT_FILTER_HIDDEN_MODE}"
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
    echo "filter_mode=$filter_mode"
    echo "filter_hidden_mode=$filter_hidden_mode"
    echo "display_filter_persist=$display_filter_persist"
    echo "anim_outer=$anim_outer"
    echo "anim_inner=$anim_inner"
  } > "$SETTINGS_FILE"
}

_GREEN='\033[0;32m'
_RESET='\033[0m'
_BOLD='\033[1m'

_green()  { printf "${_GREEN}%s${_RESET}" "$1"; }
_bold()   { printf "${_BOLD}%s${_RESET}" "$1"; }


# ── Settings navigation ──────────────────────────────────────────────────────
#   u  back one level      (sub-screen → Settings → main menu)
#   q  close Settings      (from anywhere, straight to the main menu)
# A screen that sees q sets _st_quit=1 and returns; every caller up the chain
# checks it and returns too, until settings_menu hands control to the main menu.
_st_quit=0
_sm_start_row=0     # smart menu: row to highlight when the menu is drawn
_sm_space_pick=0    # smart menu: 1 = Space picks the highlighted row (switch rows)

# _st_read VAR [start_row] [space_picks]   — the "Select:" prompt of every settings screen
_st_read() {
  _sm_start_row="${2:-0}"; _sm_space_pick="${3:-0}"
  VK_MENU_MODE=single read -r -p "Select: " "$1"
  _sm_start_row=0; _sm_space_pick=0
  printf -v "$1" '%s' "${!1%$'\r'}"
}

restore_all_defaults() {
  local mode_choice
  echo
  echo "Reset all settings. Default text color:"
  echo "1) Normal (#FFFFFF)"
  echo "2) Coder  (#00D000)"
  echo
  echo "u) Back   q) Close settings"
  _st_read mode_choice
  case "$mode_choice" in
    u|U) return ;;
    q|Q) _st_quit=1; return ;;
    1|2) ;;
    *) echo "No change"; return ;;
  esac
  show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES
  index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD
  sort_mode=$DEFAULT_SORT_MODE
  display_suffix_set=$DEFAULT_DISPLAY_SUFFIX_SET
  display_time_format=$DEFAULT_DISPLAY_TIME_FORMAT
  group_view_levels=()
  group_view_levels_str=""
  compress_format=$DEFAULT_COMPRESS_FORMAT
  filter_mode=$DEFAULT_FILTER_MODE
  filter_hidden_mode=$DEFAULT_FILTER_HIDDEN_MODE
  display_filter_persist=$DEFAULT_DISPLAY_FILTER_PERSIST
  anim_outer=$DEFAULT_ANIM_OUTER
  anim_inner=$DEFAULT_ANIM_INNER
  _items_presorted=false
  _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"
  case "$mode_choice" in
    2) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
    *) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
  esac
  save_settings
  echo "✅ All settings reset"
}

# Screen animation: how a screen is drawn when it opens / changes folder.
#   pop    — the whole screen appears at once
#   carpet — rows roll in from top to bottom
# Arrow-key scrolling inside a list is always instant.
animation_settings() {
  local ch v
  echo
  echo "Animation (how a screen is drawn)"
  echo "1) Main screens    $anim_outer"
  echo "2) Inner screens   $anim_inner   (fx / sw)"
  echo "3) Reset to defaults"
  echo
  echo "u) Back   q) Close settings"
  _st_read ch
  case "$ch" in
    u|U) return ;;
    q|Q) _st_quit=1; return ;;
    1|2)
      echo
      echo "1) pop     — whole screen appears at once"
      echo "2) carpet  — rows roll in top to bottom"
      echo
      echo "u) Back   q) Close settings"
      _st_read v
      case "$v" in
        u|U) return ;;
        q|Q) _st_quit=1; return ;;
        1) v=pop ;;
        2) v=carpet ;;
        *) echo "No change"; return ;;
      esac
      if [ "$ch" = 1 ]; then anim_outer=$v; else anim_inner=$v; fi
      save_settings
      declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
      echo "✅ Animation — main: $anim_outer, inner: $anim_inner" ;;
    3) anim_outer=$DEFAULT_ANIM_OUTER; anim_inner=$DEFAULT_ANIM_INNER; save_settings
       declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
       echo "✅ Animation reset — main: $anim_outer, inner: $anim_inner" ;;
    *) echo "No change" ;;
  esac
}

# ── Main Settings menu: loops until u / q, so every sub-screen's  u  lands here ──
settings_menu() {
  local main_choice mark gv sfx last=0 sl i
  local _modes=(az za new old big small)
  local _labels=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")
  _st_quit=0

  while :; do
    mark="[ ]"; [ "$show_hidden_files" = true ] && mark="[x]"
    gv="off"; [ ${#group_view_levels[@]} -gt 0 ] && gv="${group_view_levels[*]// / → }"
    sfx="${display_suffix_set:-none}"
    sl="$sort_mode"
    for i in "${!_modes[@]}"; do [ "${_modes[$i]}" = "$sort_mode" ] && sl="${_labels[$i]}"; done
    local dv="off"
    if declare -F _disp_load >/dev/null 2>&1 && _disp_load; then dv="on"; fi

    echo
    echo "Settings"
    echo " 1) $mark Hidden files"
    echo " 2) Index mode threshold    $index_mode_threshold"
    echo " 3) Terminal background     #${terminal_bg_color}"
    echo " 4) Terminal text color     #${terminal_text_color}"
    echo " 5) Reset all settings"
    echo " 6) Import nano settings"
    echo " 7) Sort order              $sl"
    echo " 8) File details            $sfx"
    echo " 9) Group by                $gv"
    echo "10) Compress format         $compress_format"
    echo "11) Search filter (=)       $filter_mode"
    echo "12) Display filter (.d)     $dv"
    echo "13) Animation               $anim_outer / $anim_inner"
    echo
    echo "u) Back to main menu   q) Close settings"

    _st_read main_choice "$last" 1

    case "$main_choice" in
      u|U|q|Q) return ;;
      1)  if [ "$show_hidden_files" = true ]; then show_hidden_files=false; else show_hidden_files=true; fi
          save_settings ;;                                   # bashbasicsbyvk_hidefiles.sh
      2)  index_mode_threshold_settings ;; # bashbasicsbyvk_indexmode.sh
      3)  terminal_bg_color_settings ;;    # bashbasicsbyvk_colors.sh
      4)  terminal_text_color_settings ;;  # bashbasicsbyvk_colors.sh
      5)  restore_all_defaults ;;          # Current
      6)  import_nanorc_settings; echo "✅ nano settings added" ;; # bashbasicsbyvk_importnano.sh
      7)  sort_order_settings ;;           # bashbasicsbyvk_displayer.sh
      8)  display_suffix_settings ;;       # bashbasicsbyvk_displayer.sh
      9)  group_view_settings ;;           # bashbasicsbyvk_displayer.sh
      10) compress_format_settings ;;      # bashbasicsbyvk_compress.sh
      11) filter_mode_settings ;;          # bashbasicsbyvk_filter.sh
      12) display_filter_settings ;;       # bashbasicsbyvk_display_filter.sh
      13) animation_settings ;;            # Current
      "") continue ;;
      *)  echo "Invalid choice" ;;
    esac
    [[ "$main_choice" =~ ^[0-9]+$ ]] && last=$main_choice
    if (( _st_quit )); then _st_quit=0; return; fi
  done
}

# warm up the carpet writer in the background (no cost when both loops use pop)
declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
