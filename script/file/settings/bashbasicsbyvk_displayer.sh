declare -gA item_size=()
declare -gA item_mtime=()
_meta_loaded=false

# ─── need-metadata predicates ────────────────────────────────────────────────
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

# ─── batch stat (one subprocess for all items) ───────────────────────────────
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

  # All files in one stat call
  if [ ${#files[@]} -gt 0 ]; then
    while IFS='|' read -r fpath fsize fmtime; do
      item_size["$fpath"]="$fsize"
      item_mtime["$fpath"]="$fmtime"
    done < <(stat -c "%n|%s|%Y" "${files[@]}" 2>/dev/null)
  fi

  # All dirs in one stat call (size=0 placeholder)
  if [ ${#dirs[@]} -gt 0 ]; then
    while IFS='|' read -r fpath fmtime; do
      item_mtime["$fpath"]="$fmtime"
      item_size["$fpath"]=0
    done < <(stat -c "%n|%Y" "${dirs[@]}" 2>/dev/null)

    # du only when size sorting or size suffix is active — all dirs at once
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

# ─── human-readable size (pure bash, no bc subshell) ─────────────────────────
_fmt_size() {
  local b="${1:-0}"
  if   (( b < 1024 ));       then printf "%dB"  "$b"
  elif (( b < 1048576 ));    then printf "%dK"  "$(( b / 1024 ))"
  elif (( b < 1073741824 )); then printf "%dM"  "$(( b / 1048576 ))"
  else                            printf "%dG"  "$(( b / 1073741824 ))"
  fi
}

# ─── time formatter ───────────────────────────────────────────────────────────
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

# ─── suffix builder ───────────────────────────────────────────────────────────
_build_suffix() {
  local fpath="$1" out=""
  for token in ${display_suffix_set:-}; do
    case "$token" in
      ext)
        local bn="${fpath##*/}"
        [[ "$bn" == *.* ]] && out+=" | .${bn##*.}" || out+=" | (no ext)"
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

# ─── build items ──────────────────────────────────────────────────────────────
# Fast path: glob for normal (no hidden, no prefix) — zero subprocesses.
# Slow path: find for hidden files or prefix filter.
# Metadata is NOT collected here — lazy, only on first need.
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
    # Original fast glob — same as pre-displayer code
    for f in "$p"/*; do
      [ -e "$f" ] || continue
      items+=("$f")
    done
  fi
}

# ─── sorting ──────────────────────────────────────────────────────────────────
apply_sort() {
  local mode="${sort_mode:-az}"
  [ ${#items[@]} -eq 0 ] && return

  case "$mode" in
    az|za)
      # No metadata needed — sort by basename only (one subprocess: sort)
      local flag; [ "$mode" = "za" ] && flag="-r" || flag=""
      local sorted_output
      sorted_output=$(for f in "${items[@]}"; do
                        printf '%s\t%s\n' "${f##*/}" "$f"
                      done | sort -f $flag -t$'\t' -k1,1 | cut -f2-)
      items=()
      while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done <<< "$sorted_output"
      return
      ;;
  esac

  # Remaining modes need metadata
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

# ─── group key helpers ────────────────────────────────────────────────────────
_gk_ext() {
  local bn="${1##*/}"
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

# ─── flat display ─────────────────────────────────────────────────────────────
_display_items_flat() {
  local idx=1 f icon bn suffix
  for f in "${items[@]}"; do
    [ -d "$f" ] && icon="📁" || icon="📄"
    bn="${f##*/}"
    if [ -n "${display_suffix_set:-}" ]; then
      suffix=$(_build_suffix "$f")
    else
      suffix=""
    fi
    printf " %2d) %s %s%s\n" "$idx" "$icon" "$bn" "$suffix"
    idx=$(( idx + 1 ))
  done
}

# ─── grouped display ──────────────────────────────────────────────────────────
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
      [ -d "$f" ] && icon="📁" || icon="📄"
      bn="${f##*/}"
      [ -n "${display_suffix_set:-}" ] && suffix=$(_build_suffix "$f") || suffix=""
      printf "%s%2d) %s %s%s\n" "$indent_items" "$global_idx" "$icon" "$bn" "$suffix"
      global_idx=$(( global_idx + 1 ))
    done <<< "${key_items[$ck]}"
    echo
  done
}

# ─── main entry point ─────────────────────────────────────────────────────────
display_items() {
  if [ ${#items[@]} -eq 0 ]; then
    echo "🛑 This directory is empty"
    return
  fi

  # Load metadata now if display/grouping needs it
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
