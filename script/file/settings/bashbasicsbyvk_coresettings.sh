CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk"
SETTINGS_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"

# ─── defaults ────────────────────────────────────────────────────────────────
DEFAULT_SHOW_HIDDEN_FILES=false
DEFAULT_INDEX_MODE_THRESHOLD=200
DEFAULT_TERMINAL_BG_COLOR="000000"
DEFAULT_TERMINAL_TEXT_COLOR_NORMAL="FFFFFF"
DEFAULT_TERMINAL_TEXT_COLOR_CODER="00D000"

DEFAULT_SORT_MODE="az"
DEFAULT_DISPLAY_SUFFIX_SET=""          # space-separated: ext size time
DEFAULT_DISPLAY_TIME_FORMAT="full"     # year|month|date|datetime|monthdate|full
DEFAULT_GROUP_VIEW_LEVELS=""           # space-separated ordered levels: ext year month date

# ─── unset then source saved config ──────────────────────────────────────────
unset show_hidden_files
unset index_mode_threshold
unset terminal_bg_color
unset terminal_text_color
unset sort_mode
unset display_suffix_set
unset display_time_format
unset group_view_levels_str

[ -f "$SETTINGS_FILE" ] && source "$SETTINGS_FILE"

: "${show_hidden_files:=$DEFAULT_SHOW_HIDDEN_FILES}"
: "${index_mode_threshold:=$DEFAULT_INDEX_MODE_THRESHOLD}"
: "${terminal_bg_color:=$DEFAULT_TERMINAL_BG_COLOR}"
: "${terminal_text_color:=$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL}"
: "${sort_mode:=$DEFAULT_SORT_MODE}"
: "${display_suffix_set:=$DEFAULT_DISPLAY_SUFFIX_SET}"
: "${display_time_format:=$DEFAULT_DISPLAY_TIME_FORMAT}"
: "${group_view_levels_str:=$DEFAULT_GROUP_VIEW_LEVELS}"

# Reconstruct array from saved string
declare -ga group_view_levels=()
if [ -n "$group_view_levels_str" ]; then
  read -ra group_view_levels <<< "$group_view_levels_str"
fi

# ─── save ─────────────────────────────────────────────────────────────────────
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
  } > "$SETTINGS_FILE"
}

# ─── color helpers (pre-existing) ────────────────────────────────────────────
_apply_bg_color()   { terminal_bg_color="$1"; }
_apply_text_color() { terminal_text_color="$1"; }

# ─── ANSI helpers ─────────────────────────────────────────────────────────────
_GREEN='\033[0;32m'
_RESET='\033[0m'
_BOLD='\033[1m'

_green()  { printf "${_GREEN}%s${_RESET}" "$1"; }
_bold()   { printf "${_BOLD}%s${_RESET}" "$1"; }

# ─── parse_selection (shared utility, also used in suffix/group pickers) ──────
# Returns deduplicated sorted indices from a comma/dash input string.
# Args: "$input" "$max"
_parse_multi_select() {
  local input="$1"
  local max="$2"
  local -A seen=()
  local -a out=()
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    part="${part// /}"
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local s="${BASH_REMATCH[1]}" e="${BASH_REMATCH[2]}"
      (( s > e )) && { local tmp=$s; s=$e; e=$tmp; }
      for (( i=s; i<=e && i<=max; i++ )); do
        [ -z "${seen[$i]+x}" ] && out+=("$i") && seen[$i]=1
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      (( part >= 1 && part <= max )) && [ -z "${seen[$part]+x}" ] && out+=("$part") && seen[$part]=1
    fi
    # invalid/zero/beyond-max: silently skip
  done
  # sort numerically
  printf '%s\n' "${out[@]}" | sort -n | tr '\n' ' '
}

# ─── 1. Hidden file settings ──────────────────────────────────────────────────
hidden_file_settings() {
  echo "Hidden files: currently $([ "$show_hidden_files" = true ] && echo ON || echo OFF)"
  echo "1) Show hidden files"
  echo "2) Hide hidden files"
  read -r -p "Choice: " c
  case "$c" in
    1) show_hidden_files=true  ;;
    2) show_hidden_files=false ;;
    *) echo "No change" ;;
  esac
  save_settings
}

# ─── 2. Index mode threshold ──────────────────────────────────────────────────
index_mode_threshold_settings() {
  echo "Current threshold: $index_mode_threshold"
  read -r -p "New threshold (blank = no change): " v
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    index_mode_threshold="$v"
    save_settings
    echo "✅ Threshold set to $v"
  else
    echo "No change"
  fi
}

# ─── 3. Terminal BG color ─────────────────────────────────────────────────────
terminal_bg_color_settings() {
  echo "Current BG color: #${terminal_bg_color}"
  read -r -p "New hex color (without #, blank = no change): " v
  if [[ "$v" =~ ^[0-9a-fA-F]{6}$ ]]; then
    _apply_bg_color "$v"
    save_settings
    echo "✅ BG color set to #$v"
  else
    echo "No change"
  fi
}

# ─── 4. Terminal text color ───────────────────────────────────────────────────
terminal_text_color_settings() {
  echo "Current text color: #${terminal_text_color}"
  echo "1) Normal (#FFFFFF)"
  echo "2) Coder  (#00D000)"
  echo "3) Custom hex"
  read -r -p "Choice: " c
  case "$c" in
    1) _apply_text_color "FFFFFF" ;;
    2) _apply_text_color "00D000" ;;
    3)
      read -r -p "Hex (without #): " v
      if [[ "$v" =~ ^[0-9a-fA-F]{6}$ ]]; then
        _apply_text_color "$v"
      else
        echo "Invalid hex. No change."
        return
      fi
      ;;
    *) echo "No change"; return ;;
  esac
  save_settings
  echo "✅ Text color updated"
}

# ─── 5. Restore all defaults ──────────────────────────────────────────────────
restore_all_defaults() {
  echo
  echo "Choose default text color mode:"
  echo "1) Normal (#FFFFFF)"
  echo "2) Coder  (#00D000)"
  read -r -p "Choice [1-2]: " mode_choice
  show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES
  index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD
  sort_mode=$DEFAULT_SORT_MODE
  display_suffix_set=$DEFAULT_DISPLAY_SUFFIX_SET
  display_time_format=$DEFAULT_DISPLAY_TIME_FORMAT
  group_view_levels=()
  group_view_levels_str=""
  _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"
  case "$mode_choice" in
    2) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
    *) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
  esac
  save_settings
  echo "✅ All settings restored to defaults"
}

# ─── 6. Import nano settings ──────────────────────────────────────────────────
import_nanorc_settings() {
  # pre-existing stub — implement as needed
  echo "Import nano settings: not yet implemented"
}

# ─── 7. Sort order ────────────────────────────────────────────────────────────
sort_order_settings() {
  local modes=("az" "za" "new" "old" "big" "small")
  local labels=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")
  echo
  echo "Sort order (current: ${sort_mode}):"
  for i in "${!modes[@]}"; do
    local num=$((i+1))
    if [ "${modes[$i]}" = "$sort_mode" ]; then
      printf " %d) $(_green "${labels[$i]} ✓")\n" "$num"
    else
      printf " %d) %s\n" "$num" "${labels[$i]}"
    fi
  done
  read -r -p "Choice [1-6] (blank = no change): " c
  if [[ "$c" =~ ^[1-6]$ ]]; then
    sort_mode="${modes[$((c-1))]}"
    save_settings
    echo "✅ Sort mode set to: ${labels[$((c-1))]}"
  else
    echo "No change"
  fi
}

# ─── 8. Display suffix ────────────────────────────────────────────────────────
# Manages display_suffix_set (space-separated: ext size time)
# and display_time_format when time is enabled.
_show_suffix_state() {
  local tokens=("ext" "size" "time")
  local labels=("Extension (.sh)" "File size (4.2K)" "Modified time")
  echo
  echo "Display suffix components:"
  for i in "${!tokens[@]}"; do
    local num=$((i+1))
    local tok="${tokens[$i]}"
    if [[ " $display_suffix_set " == *" $tok "* ]]; then
      printf " %d) $(_green "${labels[$i]} ✓")\n" "$num"
    else
      printf " %d) %s\n" "$num" "${labels[$i]}"
    fi
  done
  echo
  echo "Time format (used when time is enabled):"
  local tfmts=("year" "month" "date" "datetime" "monthdate" "full")
  local tlabels=("Year only (2023)" "Month only (Mar)" "Date only (15)" "Date+Time (15 14:32)" "Month+Date+Time (Mar-15 14:32)" "Full (2023-Mar-15 14:32)")
  for i in "${!tfmts[@]}"; do
    local num=$((i+1))
    if [ "${tfmts[$i]}" = "$display_time_format" ]; then
      printf "  %d) $(_green "${tlabels[$i]} ✓")\n" "$num"
    else
      printf "  %d) %s\n" "$num" "${tlabels[$i]}"
    fi
  done
}

display_suffix_settings() {
  local tokens=("ext" "size" "time")
  local tfmts=("year" "month" "date" "datetime" "monthdate" "full")

  while true; do
    _show_suffix_state
    echo
    echo "a) Add components   r) Remove components   t) Set time format"
    echo "n) Clear all (none)   q) Done"
    read -r -p "Action: " action
    action="${action,,}"

    case "$action" in
      q) break ;;

      n)
        display_suffix_set=""
        save_settings
        echo "✅ All suffixes cleared"
        ;;

      a)
        echo "Add by number (comma/range, e.g. 1,3 or 1-2):"
        read -r -p "Numbers: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel
        sel=$(_parse_multi_select "$inp" 3)
        local changed=false
        for n in $sel; do
          local tok="${tokens[$((n-1))]}"
          if [[ " $display_suffix_set " != *" $tok "* ]]; then
            display_suffix_set="${display_suffix_set:+$display_suffix_set }$tok"
            changed=true
          fi
        done
        # trim leading/trailing spaces
        display_suffix_set="${display_suffix_set## }"
        display_suffix_set="${display_suffix_set%% }"
        $changed && save_settings && echo "✅ Added" || echo "Already set — no change"
        ;;

      r)
        if [ -z "$display_suffix_set" ]; then
          echo "Nothing to remove"
          continue
        fi
        echo "Remove by number (comma/range):"
        read -r -p "Numbers: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel
        sel=$(_parse_multi_select "$inp" 3)
        local changed=false
        for n in $sel; do
          local tok="${tokens[$((n-1))]}"
          if [[ " $display_suffix_set " == *" $tok "* ]]; then
            display_suffix_set="${display_suffix_set//$tok/}"
            changed=true
          fi
        done
        # collapse whitespace
        read -ra _arr <<< "$display_suffix_set"
        display_suffix_set="${_arr[*]}"
        $changed && save_settings && echo "✅ Removed" || echo "Not present — no change"
        ;;

      t)
        echo "Set time format [1-6] (blank = no change):"
        read -r -p "Choice: " tc
        if [[ "$tc" =~ ^[1-6]$ ]]; then
          display_time_format="${tfmts[$((tc-1))]}"
          save_settings
          echo "✅ Time format set"
        else
          echo "No change"
        fi
        ;;

      *)
        echo "⚠️  Invalid action. Use a/r/t/n/q"
        ;;
    esac
  done
}

# ─── 9. Group view ────────────────────────────────────────────────────────────
# group_view_levels is an ordered array of levels: ext year month date
# Users build a chain. Levels within the chain: ext can appear at any position,
# but time levels always respect year → month → date order within themselves.

_valid_level() {
  case "$1" in ext|year|month|date) return 0 ;; *) return 1 ;; esac
}

_show_group_state() {
  local all_levels=("ext" "year" "month" "date")
  local all_labels=("Extension" "Year" "Month" "Date")
  echo
  if [ ${#group_view_levels[@]} -eq 0 ]; then
    echo "Group view: OFF"
  else
    echo "Group view chain: ${group_view_levels[*]}"
  fi
  echo
  echo "Available levels:"
  for i in "${!all_levels[@]}"; do
    local num=$((i+1))
    local lvl="${all_levels[$i]}"
    local in_chain=false
    for gl in "${group_view_levels[@]}"; do
      [ "$gl" = "$lvl" ] && in_chain=true && break
    done
    if $in_chain; then
      local pos=0
      for j in "${!group_view_levels[@]}"; do
        [ "${group_view_levels[$j]}" = "$lvl" ] && pos=$((j+1))
      done
      printf " %d) $(_green "${all_labels[$i]} ✓ (position $pos)")\n" "$num"
    else
      printf " %d) %s\n" "$num" "${all_labels[$i]}"
    fi
  done
}

group_view_settings() {
  local all_levels=("ext" "year" "month" "date")

  while true; do
    _show_group_state

    # Determine ungroup vs group wording
    if [ ${#group_view_levels[@]} -gt 0 ]; then
      echo
      echo "u) Ungroup (turn off all grouping)"
    fi
    echo "a) Add level to chain   r) Remove level from chain"
    echo "o) Reorder chain   q) Done"
    read -r -p "Action: " action
    action="${action,,}"

    case "$action" in
      q) break ;;

      u)
        group_view_levels=()
        group_view_levels_str=""
        save_settings
        echo "✅ Grouping turned off"
        ;;

      a)
        echo "Add level(s) by number (comma/range):"
        read -r -p "Numbers [1-4]: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel
        sel=$(_parse_multi_select "$inp" 4)
        local changed=false
        for n in $sel; do
          local lvl="${all_levels[$((n-1))]}"
          local already=false
          for gl in "${group_view_levels[@]}"; do
            [ "$gl" = "$lvl" ] && already=true && break
          done
          if ! $already; then
            group_view_levels+=("$lvl")
            changed=true
          fi
        done
        $changed || echo "All already in chain — no change"
        $changed && group_view_levels_str="${group_view_levels[*]}" && save_settings && echo "✅ Level(s) added"
        ;;

      r)
        if [ ${#group_view_levels[@]} -eq 0 ]; then
          echo "Chain is empty"
          continue
        fi
        echo "Remove level(s) by number (comma/range) [based on available levels list above]:"
        read -r -p "Numbers [1-4]: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel
        sel=$(_parse_multi_select "$inp" 4)
        local changed=false
        local -a new_chain=()
        # Mark which levels to remove
        declare -A to_remove=()
        for n in $sel; do
          to_remove["${all_levels[$((n-1))]}"]="1"
        done
        for gl in "${group_view_levels[@]}"; do
          if [ -z "${to_remove[$gl]+x}" ]; then
            new_chain+=("$gl")
          else
            changed=true
          fi
        done
        if $changed; then
          group_view_levels=("${new_chain[@]}")
          group_view_levels_str="${group_view_levels[*]}"
          save_settings
          echo "✅ Level(s) removed"
        else
          echo "None of those were in the chain — no change"
        fi
        ;;

      o)
        if [ ${#group_view_levels[@]} -le 1 ]; then
          echo "Need at least 2 levels in chain to reorder"
          continue
        fi
        echo "Current chain:"
        for i in "${!group_view_levels[@]}"; do
          printf "  %d) %s\n" "$((i+1))" "${group_view_levels[$i]}"
        done
        echo "Enter new order as position numbers (e.g. 2,1,3):"
        read -r -p "Order: " inp
        IFS=',' read -ra order_parts <<< "$inp"
        local -a new_chain=()
        local -A used_pos=()
        local valid=true
        for p in "${order_parts[@]}"; do
          p="${p// /}"
          if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#group_view_levels[@]} )); then
            if [ -z "${used_pos[$p]+x}" ]; then
              new_chain+=("${group_view_levels[$((p-1))]}")
              used_pos[$p]=1
            fi
          else
            valid=false
          fi
        done
        if [ "${#new_chain[@]}" -ne "${#group_view_levels[@]}" ]; then
          echo "⚠️  Incomplete order — no change"
        else
          group_view_levels=("${new_chain[@]}")
          group_view_levels_str="${group_view_levels[*]}"
          save_settings
          echo "✅ Chain reordered: ${group_view_levels[*]}"
        fi
        ;;

      *)
        echo "⚠️  Invalid action. Use a/r/o/u/q"
        ;;
    esac
  done
}

# ─── main settings menu ───────────────────────────────────────────────────────
settings_menu() {
  # Build group view label dynamically
  local gv_label
  if [ ${#group_view_levels[@]} -gt 0 ]; then
    gv_label="Group view [${group_view_levels[*]}] (tap to Ungroup/edit)"
  else
    gv_label="Group view: OFF"
  fi

  # Build suffix label
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

  read -r -p "Enter choice [1-9]: " main_choice

  case "$main_choice" in
    1) hidden_file_settings ;;
    2) index_mode_threshold_settings ;;
    3) terminal_bg_color_settings ;;
    4) terminal_text_color_settings ;;
    5) restore_all_defaults ;;
    6) import_nanorc_settings ;;
    7) sort_order_settings ;;
    8) display_suffix_settings ;;
    9) group_view_settings ;;
    *) echo "Invalid choice" ;;
  esac
}
