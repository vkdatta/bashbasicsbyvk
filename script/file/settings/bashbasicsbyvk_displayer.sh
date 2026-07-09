# Used Directly in O

declare -gA item_size=()
declare -gA item_mtime=()
_meta_loaded=false
declare -g _hl_index=0

_bold() {
  printf '\033[1m%s\033[0m' "$1"
}

_needs_metadata() {
  [[ " ${display_suffix_set:-} " == *" size "* ]] && return 0
  [[ " ${display_suffix_set:-} " == *" time "* ]] && return 0
  case "${sort_mode:-az}" in new|old|big|small) return 0 ;; esac
  for lvl in "${group_view_levels[@]}"; do
    case "$lvl" in year|month|date) return 0 ;; esac
  done
  return 1
}

_needs_dir_size() {
  case "${sort_mode:-az}" in big|small) return 0 ;; esac
  [[ " ${display_suffix_set:-} " == *" size "* ]] && return 0
  return 1
}

_collect_metadata() {
  item_size=()
  item_mtime=()
  [ ${#items[@]} -eq 0 ] && { _meta_loaded=true; return; }

  local need_dir_size=false
  _needs_dir_size && need_dir_size=true

  local -a files=() dirs=()
  for f in "${items[@]}"; do
    [ -d "$f" ] && dirs+=("$f") || files+=("$f")
  done

  if [ ${#files[@]} -gt 0 ]; then
    while IFS='|' read -r fpath fsize fmtime; do
      item_size["$fpath"]="$fsize"
      item_mtime["$fpath"]="$fmtime"
    done < <(stat -c "%n|%s|%Y" "${files[@]}" 2>/dev/null)
  fi

  if [ ${#dirs[@]} -gt 0 ]; then
    while IFS='|' read -r fpath fmtime; do
      item_mtime["$fpath"]="$fmtime"
      item_size["$fpath"]=0
    done < <(stat -c "%n|%Y" "${dirs[@]}" 2>/dev/null)

    if $need_dir_size; then
      while IFS=$'\t' read -r sz fpath; do
        item_size["$fpath"]="$sz"
      done < <(du -sb "${dirs[@]}" 2>/dev/null)
    fi
  fi

  _meta_loaded=true
}

_ensure_meta() {
  $_meta_loaded && return
  _collect_metadata
}

_fmt_size() {
  local b="${1:-0}"
  if   (( b < 1024 ));       then printf "%dB"  "$b"
  elif (( b < 1048576 ));    then printf "%dK"  "$(( b / 1024 ))"
  elif (( b < 1073741824 )); then printf "%dM"  "$(( b / 1048576 ))"
  else                            printf "%dG"  "$(( b / 1073741824 ))"
  fi
}

_fmt_time() {
  local epoch="${1:-0}"
  case "${display_time_format:-full}" in
    year)      date -d "@$epoch" "+%Y" ;;
    month)     date -d "@$epoch" "+%b" ;;
    date)      date -d "@$epoch" "+%d" ;;
    datetime)  date -d "@$epoch" "+%d %H:%M" ;;
    monthdate) date -d "@$epoch" "+%b-%d %H:%M" ;;
    full|*)    date -d "@$epoch" "+%Y-%b-%d %H:%M" ;;
  esac
}

_build_suffix() {
  local fpath="$1" out=""
  for token in ${display_suffix_set:-}; do
    case "$token" in
      ext)
        local bn="${fpath##*/}"
        if [[ "$bn" == *.shortcut ]]; then
          out+=" | →shortcut"
        else
          [[ "$bn" == *.* ]] && out+=" | .${bn##*.}" || out+=" | (no ext)"
        fi
        ;;
      size)
        out+=" | $(_fmt_size "${item_size[$fpath]:-0}")"
        ;;
      time)
        out+=" | $(_fmt_time "${item_mtime[$fpath]:-0}")"
        ;;
    esac
  done
  printf '%s' "$out"
}

build_items_with_meta() {
  local p="$1"
  local pfx="${2:-}"
  items=()
  item_size=()
  item_mtime=()
  _meta_loaded=false

  if [ -n "$pfx" ] || $show_hidden_files; then
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ! $show_hidden_files && [[ "$bn" == .* ]] && continue
      [ -n "$pfx" ] && [[ "${bn,,}" != "${pfx,,}"* ]] && continue
      items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  else
    for f in "$p"/*; do
      [ -e "$f" ] || continue
      items+=("$f")
    done
  fi
}

apply_sort() {
  local mode="${sort_mode:-az}"
  [ ${#items[@]} -eq 0 ] && return

  case "$mode" in
    az|za)
      local flag; [ "$mode" = "za" ] && flag="-r" || flag=""
      local sorted_output
      sorted_output=$(for f in "${items[@]}"; do
                        local _sort_key
                        _sort_key="${f##*/}"
                        if [[ "$_sort_key" == *.shortcut ]]; then
                          _sort_key=$(_shortcut_read_field "$f" "SHORTCUT_NAME" 2>/dev/null)
                          [ -z "$_sort_key" ] && _sort_key="${f##*/}"
                        fi
                        printf '%s\t%s\n' "$_sort_key" "$f"
                      done | sort -f $flag -t$'\t' -k1,1 | cut -f2-)
      items=()
      while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done <<< "$sorted_output"
      return
      ;;
  esac

  _ensure_meta

  local -a records=()
  for f in "${items[@]}"; do
    case "$mode" in
      new|old)   records+=("${item_mtime[$f]:-0}"$'\t'"$f") ;;
      big|small) records+=("${item_size[$f]:-0}"$'\t'"$f") ;;
    esac
  done

  local flag
  case "$mode" in
    new|big)   flag="-k1,1nr" ;;
    old|small) flag="-k1,1n"  ;;
  esac

  items=()
  while IFS= read -r line; do
    [ -n "$line" ] && items+=("$line")
  done < <(printf '%s\n' "${records[@]}" | sort -t$'\t' $flag | cut -f2-)
}

_gk_ext() {
  local bn="${1##*/}"
  if [[ "$bn" == *.shortcut ]]; then
    printf '[shortcut]'
    return
  fi
  [ -d "$1" ] && { printf '[dir]'; return; }
  [[ "$bn" == *.* ]] && printf '.%s' "${bn##*.}" || printf '(no ext)'
}
_gk_year()  { date -d "@${item_mtime[$1]:-0}" "+%Y"       2>/dev/null || printf '?'; }
_gk_month() { date -d "@${item_mtime[$1]:-0}" "+%Y-%b"    2>/dev/null || printf '?'; }
_gk_date()  { date -d "@${item_mtime[$1]:-0}" "+%Y-%b-%d" 2>/dev/null || printf '?'; }

_composite_key() {
  local f="$1" key=""
  for lvl in "${group_view_levels[@]}"; do
    case "$lvl" in
      ext)   key+="$(_gk_ext   "$f")|" ;;
      year)  key+="$(_gk_year  "$f")|" ;;
      month) key+="$(_gk_month "$f")|" ;;
      date)  key+="$(_gk_date  "$f")|" ;;
    esac
  done
  printf '%s' "$key"
}


_shortcut_display_parts() {
  local sc_file="$1"
  local sc_type sc_name sc_target

  sc_type=$(_shortcut_read_field "$sc_file" "SHORTCUT_TYPE")
  sc_name=$(_shortcut_read_field "$sc_file" "SHORTCUT_NAME")
  sc_target=$(_shortcut_read_field "$sc_file" "SHORTCUT_TARGET")

  [ -z "$sc_name" ] && sc_name="${sc_file##*/}" && sc_name="${sc_name%.shortcut}"

  local _broken=""
  [ -n "$sc_target" ] && [ ! -e "$sc_target" ] && _broken=" ⚠️ (broken)"

  if [ "$sc_type" == "dir" ]; then
    _sc_icon="🔑"
  else
    _sc_icon="🗝️"
  fi
  _sc_display="${sc_name}${_broken}"
}

_display_items_flat() {
  local idx=1 f icon bn suffix line
  local _sc_icon _sc_display
  for f in "${items[@]}"; do
    bn="${f##*/}"
    if [[ "$bn" == *.shortcut ]]; then
      _shortcut_display_parts "$f"
      icon="$_sc_icon"
      bn="$_sc_display"
    else
      [ -d "$f" ] && icon="📁" || icon="📄"
    fi
    if [ -n "${display_suffix_set:-}" ]; then
      suffix=$(_build_suffix "$f")
    else
      suffix=""
    fi
    line=$(printf " %2d) %s %s%s" "$idx" "$icon" "$bn" "$suffix")
    if [ "$idx" -eq "${_hl_index:-0}" ]; then
      printf '%s\n' "$(_bold "$line")"
    else
      printf '%s\n' "$line"
    fi
    idx=$(( idx + 1 ))
  done
}

_display_grouped() {
  local depth="${#group_view_levels[@]}"
  [ "$depth" -eq 0 ] && { _display_items_flat; return; }

  local -a all_keys=()
  declare -A key_seen=()
  declare -A key_items=()

  for f in "${items[@]}"; do
    local ck; ck=$(_composite_key "$f")
    [ -z "${key_seen[$ck]+x}" ] && { all_keys+=("$ck"); key_seen["$ck"]=1; }
    key_items["$ck"]+="$f"$'\n'
  done

  local global_idx=1
  local ck f icon bn suffix indent indent_items lvl_idx lvl part
  local -a parts
  local _sc_icon _sc_display

  for ck in "${all_keys[@]}"; do
    IFS='|' read -ra parts <<< "$ck"
    lvl_idx=0
    for lvl in "${group_view_levels[@]}"; do
      indent=$(printf '%*s' "$(( lvl_idx * 2 ))" '')
      printf "%s── %s: %s\n" "$indent" "${lvl^^}" "${parts[$lvl_idx]:-?}"
      lvl_idx=$(( lvl_idx + 1 ))
    done
    indent_items=$(printf '%*s' "$(( depth * 2 ))" '')
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      bn="${f##*/}"
      if [[ "$bn" == *.shortcut ]]; then
        _shortcut_display_parts "$f"
        icon="$_sc_icon"
        bn="$_sc_display"
      else
        [ -d "$f" ] && icon="📁" || icon="📄"
      fi
      [ -n "${display_suffix_set:-}" ] && suffix=$(_build_suffix "$f") || suffix=""
      local line
      line=$(printf "%s%2d) %s %s%s" "$indent_items" "$global_idx" "$icon" "$bn" "$suffix")
      if [ "$global_idx" -eq "${_hl_index:-0}" ]; then
        printf '%s\n' "$(_bold "$line")"
      else
        printf '%s\n' "$line"
      fi
      global_idx=$(( global_idx + 1 ))
    done <<< "${key_items[$ck]}"
    echo
  done
}

display_items() {
  if [ ${#items[@]} -eq 0 ]; then
    echo "🛑 This directory is empty"
    return
  fi

  if _needs_metadata; then
    _ensure_meta
  fi

  local use_group=false
  [ "${#group_view_levels[@]}" -gt 0 ] && ! ${imaginary_mode:-false} && use_group=true

  if $use_group; then
    _display_grouped
  else
    _display_items_flat
  fi
}


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
  done
  printf '%s\n' "${out[@]}" | sort -n | tr '\n' ' '
}

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
}

_show_time_format_state() {
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
        read -ra _arr <<< "$display_suffix_set"
        display_suffix_set="${_arr[*]}"
        $changed && save_settings && echo "✅ Removed" || echo "Not present — no change"
        ;;

      t)
        _show_time_format_state
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
