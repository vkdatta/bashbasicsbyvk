declare -gA item_size=()
declare -gA item_mtime=()

_fmt_size() {
  local b="$1"
  if   (( b < 1024 ));             then printf "%dB"    "$b"
  elif (( b < 1048576 ));          then printf "%.1fK"  "$(echo "scale=1;$b/1024"       | bc)"
  elif (( b < 1073741824 ));       then printf "%.1fM"  "$(echo "scale=1;$b/1048576"    | bc)"
  else                                  printf "%.1fG"  "$(echo "scale=1;$b/1073741824" | bc)"
  fi
}

_fmt_time() {
  local epoch="$1"
  local fmt="${display_time_format:-full}"
  case "$fmt" in
    year)      date -d "@$epoch" "+%Y" ;;
    month)     date -d "@$epoch" "+%b" ;;
    date)      date -d "@$epoch" "+%d" ;;
    datetime)  date -d "@$epoch" "+%d %H:%M" ;;
    monthdate) date -d "@$epoch" "+%b-%d %H:%M" ;;
    full)      date -d "@$epoch" "+%Y-%b-%d %H:%M" ;;
    *)         date -d "@$epoch" "+%Y-%b-%d %H:%M" ;;
  esac
}

_build_suffix() {
  local fpath="$1"
  local out=""
  local set="${display_suffix_set:-}"

  for token in $set; do
    case "$token" in
      ext)
        local bn="${fpath##*/}"
        local ext=""
        if [[ "$bn" == *.* ]]; then
          ext=".${bn##*.}"
        else
          ext="(none)"
        fi
        out+=" | $ext"
        ;;
      size)
        local raw_size="${item_size[$fpath]:-0}"
        out+=" | $(_fmt_size "$raw_size")"
        ;;
      time)
        local raw_mtime="${item_mtime[$fpath]:-0}"
        out+=" | $(_fmt_time "$raw_mtime")"
        ;;
    esac
  done
  echo "$out"
}

_collect_metadata() {
  item_size=()
  item_mtime=()
  for f in "${items[@]}"; do
    local mtime sz
    mtime=$(stat -c "%Y" "$f" 2>/dev/null || echo 0)
    if [ -d "$f" ]; then
      sz=$(du -sb "$f" 2>/dev/null | cut -f1)
      sz="${sz:-0}"
    else
      sz=$(stat -c "%s" "$f" 2>/dev/null || echo 0)
    fi
    item_size["$f"]="$sz"
    item_mtime["$f"]="$mtime"
  done
}

build_items_with_meta() {
  local p="$1"
  local pfx="${2:-}"
  items=()

  if $show_hidden_files; then
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      if [ -n "$pfx" ]; then
        [[ "${bn,,}" != "${pfx,,}"* ]] && continue
      fi
      items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  else
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      [[ "$bn" == .* ]] && continue
      if [ -n "$pfx" ]; then
        [[ "${bn,,}" != "${pfx,,}"* ]] && continue
      fi
      items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  fi

  _collect_metadata
}

apply_sort() {
  local mode="${sort_mode:-az}"
  [ ${#items[@]} -eq 0 ] && return

  local -a records=()
  for f in "${items[@]}"; do
    local bn="${f##*/}"
    case "$mode" in
      az|za)
        records+=("${bn,,}	$f")
        ;;
      new|old)
        records+=("${item_mtime[$f]:-0}	$f")
        ;;
      big|small)
        records+=("${item_size[$f]:-0}	$f")
        ;;
    esac
  done

  local sorted_output
  case "$mode" in
    az)    sorted_output=$(printf '%s\n' "${records[@]}" | sort -t$'\t' -k1,1) ;;
    za)    sorted_output=$(printf '%s\n' "${records[@]}" | sort -t$'\t' -k1,1r) ;;
    new)   sorted_output=$(printf '%s\n' "${records[@]}" | sort -t$'\t' -k1,1nr) ;;
    old)   sorted_output=$(printf '%s\n' "${records[@]}" | sort -t$'\t' -k1,1n) ;;
    big)   sorted_output=$(printf '%s\n' "${records[@]}" | sort -t$'\t' -k1,1nr) ;;
    small) sorted_output=$(printf '%s\n' "${records[@]}" | sort -t$'\t' -k1,1n) ;;
  esac

  items=()
  while IFS=$'\t' read -r _key fpath; do
    [ -n "$fpath" ] && items+=("$fpath")
  done <<< "$sorted_output"
}

_group_key_ext() {
  local f="$1"
  local bn="${f##*/}"
  if [ -d "$f" ]; then echo "[dir]"; return; fi
  if [[ "$bn" == *.* ]]; then echo ".${bn##*.}"; else echo "(no ext)"; fi
}

_group_key_year() {
  local f="$1"
  date -d "@${item_mtime[$f]:-0}" "+%Y" 2>/dev/null || echo "unknown"
}

_group_key_month() {
  local f="$1"
  date -d "@${item_mtime[$f]:-0}" "+%Y-%b" 2>/dev/null || echo "unknown"
}

_group_key_date() {
  local f="$1"
  date -d "@${item_mtime[$f]:-0}" "+%Y-%b-%d" 2>/dev/null || echo "unknown"
}

_get_level_key() {
  local level="$1"
  local f="$2"
  case "$level" in
    ext)   _group_key_ext   "$f" ;;
    year)  _group_key_year  "$f" ;;
    month) _group_key_month "$f" ;;
    date)  _group_key_date  "$f" ;;
    *)     echo "?" ;;
  esac
}

_composite_key() {
  local f="$1"
  local key=""
  for lvl in "${group_view_levels[@]}"; do
    local part
    part=$(_get_level_key "$lvl" "$f")
    key+="${part}|"
  done
  echo "$key"
}

_display_items_flat() {
  local idx=1
  for f in "${items[@]}"; do
    local icon bn suffix
    [ -d "$f" ] && icon="📁" || icon="📄"
    bn="$(basename "$f")"
    suffix=$(_build_suffix "$f")
    printf " %2d) %s %s%s\n" "$idx" "$icon" "$bn" "$suffix"
    idx=$((idx+1))
  done
}

_display_grouped() {
  local -a levels=("${group_view_levels[@]}")
  local depth="${#levels[@]}"
  [ "$depth" -eq 0 ] && { _display_items_flat; return; }

  # Build ordered unique composite keys while preserving item order
  local -a all_keys=()
  declare -A key_seen=()
  declare -A key_items=()   # composite_key -> newline-separated paths

  for f in "${items[@]}"; do
    local ck
    ck=$(_composite_key "$f")
    if [ -z "${key_seen[$ck]+x}" ]; then
      all_keys+=("$ck")
      key_seen["$ck"]=1
    fi
    key_items["$ck"]+="$f"$'\n'
  done

  local global_idx=1

  for ck in "${all_keys[@]}"; do
    # Print hierarchical header
    local header=""
    local -a parts
    IFS='|' read -ra parts <<< "$ck"
    local lvl_idx=0
    for lvl in "${levels[@]}"; do
      local part="${parts[$lvl_idx]:-?}"
      local indent
      indent=$(printf '%*s' "$((lvl_idx*2))" '')
      echo "${indent}── ${lvl^^}: ${part}"
      lvl_idx=$((lvl_idx+1))
    done

    # Print items under this group
    local indent_items
    indent_items=$(printf '%*s' "$((depth*2))" '')
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      local icon bn suffix
      [ -d "$f" ] && icon="📁" || icon="📄"
      bn="$(basename "$f")"
      suffix=$(_build_suffix "$f")
      printf "%s%2d) %s %s%s\n" "$indent_items" "$global_idx" "$icon" "$bn" "$suffix"
      global_idx=$((global_idx+1))
    done <<< "${key_items[$ck]}"
    echo
  done
}

display_items() {
  if [ ${#items[@]} -eq 0 ]; then
    echo "🛑 This directory is empty"
    return
  fi

  local use_group=false
  if [ "${#group_view_levels[@]}" -gt 0 ] && $force_show; then
    use_group=true
  elif [ "${#group_view_levels[@]}" -gt 0 ] && ! ${imaginary_mode:-false}; then
    use_group=true
  fi

  if $use_group; then
    _display_grouped
  else
    _display_items_flat
  fi
}
