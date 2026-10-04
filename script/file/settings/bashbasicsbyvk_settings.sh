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


restore_all_defaults() {
  echo
  echo "Choose default text color mode:"
  echo "1) Normal (#FFFFFF)"
  echo "2) Coder  (#00D000)"
  read -r -p "Choice [1-2] (u = back): " mode_choice
  case "$mode_choice" in
    u|U) echo "↩️  Back"; return ;;
    q|Q) _bvk_quit ;;
  esac
  show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES
  index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD
  sort_mode=$DEFAULT_SORT_MODE
  display_suffix_set=$DEFAULT_DISPLAY_SUFFIX_SET
  display_time_format=$DEFAULT_DISPLAY_TIME_FORMAT
  group_view_levels=()
  group_view_levels_str=""
  compress_format=$DEFAULT_COMPRESS_FORMAT
  display_filter_persist=$DEFAULT_DISPLAY_FILTER_PERSIST
  anim_outer=$DEFAULT_ANIM_OUTER
  anim_inner=$DEFAULT_ANIM_INNER
  _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"
  case "$mode_choice" in
    2) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
    *) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
  esac
  save_settings
  echo "✅ All settings restored to defaults"
}

# Screen animation: how a screen is drawn when it opens / changes folder.
#   pop    — the whole screen appears at once
#   carpet — rows roll in from top to bottom
# Arrow-key scrolling inside a list is always instant.
animation_settings() {
  local ch v
  echo
  echo "Animation (how a screen is drawn):"
  echo "1) Outer loop    now: $anim_outer     (default: $DEFAULT_ANIM_OUTER)"
  echo "2) Inner loops   now: $anim_inner     (default: $DEFAULT_ANIM_INNER)   [fx / sw]"
  echo "3) Restore animation defaults"
  read -r -p "Choice [1-3]: " ch
  ch="${ch%$'\r'}"
  case "$ch" in
    u|U) return ;;
    q|Q) _bvk_quit ;;
    1|2)
      echo "1) pop     — whole screen appears at once"
      echo "2) carpet  — rows roll in top to bottom"
      read -r -p "Choice [1-2]: " v
      v="${v%$'\r'}"
      case "$v" in
        u|U) return ;;
        q|Q) _bvk_quit ;;
        1) v=pop ;;
        2) v=carpet ;;
        *) echo "Invalid choice — no changes made."; return ;;
      esac
      if [ "$ch" = 1 ]; then anim_outer=$v; else anim_inner=$v; fi
      save_settings
      echo "✅ Animation — outer loop: $anim_outer, inner loops: $anim_inner" ;;
    3) anim_outer=$DEFAULT_ANIM_OUTER; anim_inner=$DEFAULT_ANIM_INNER; save_settings
       echo "✅ Animation restored — outer loop: $anim_outer, inner loops: $anim_inner" ;;
    *) echo "Invalid choice" ;;
  esac
}

settings_menu() {
 local gv_label
  if [ ${#group_view_levels[@]} -gt 0 ]; then
    gv_label="Group view [${group_view_levels[*]}] (tap to Ungroup/edit)"
  else
    gv_label="Group view: OFF"
  fi
 local sfx_label="${display_suffix_set:-none}"

  echo
  echo "Settings:"
  echo "1) Hidden files          ($show_hidden_files)"
  echo "2) Index mode threshold  ($index_mode_threshold)"
  echo "3) Terminal BG color     (#${terminal_bg_color})"
  echo "4) Terminal text color   (#${terminal_text_color})"
  echo "5) Restore ALL defaults"
  echo "6) Import nano settings"
  echo "7) Sort order            ($sort_mode)"
  echo "8) Display suffix        (${sfx_label:-none})"
  echo "9) $gv_label"
  echo "10) Compress format      ($compress_format)"
  echo "11) Filter mode          ($filter_mode, hidden: $filter_hidden_mode)"
  echo "12) Display filter       (.d — presets, keep between sessions: $display_filter_persist)"
  echo "13) Animation            (outer loop: $anim_outer, inner loops: $anim_inner)"

  read -r -p "Enter choice [1-13]: " main_choice

case "$main_choice" in
u|U) return ;;
q|Q) _bvk_quit ;;
    1) hidden_file_settings ;; # bashbasicsbyvk_hidefiles.sh
    2) index_mode_threshold_settings ;; # bashbasicsbyvk_indexmode.sh
    3) terminal_bg_color_settings ;; # bashbasicsbyvk_colors.sh
    4) terminal_text_color_settings ;; # bashbasicsbyvk_colors.sh
    5) restore_all_defaults ;; # Current
    6) import_nanorc_settings ;; # bashbasicsbyvk_importnano.sh
    7) sort_order_settings ;; # bashbasicsbyvk_displayer.sh
    8) display_suffix_settings ;; # bashbasicsbyvk_displayer.sh
    9) group_view_settings ;; # bashbasicsbyvk_displayer.sh
    10) compress_format_settings ;; # Current
    11) filter_mode_settings ;;    # bashbasicsbyvk_filter.sh
    12) display_filter_settings ;; # bashbasicsbyvk_display_filter.sh
    13) animation_settings ;;      # Current
    *) echo "Invalid choice" ;;
esac
}