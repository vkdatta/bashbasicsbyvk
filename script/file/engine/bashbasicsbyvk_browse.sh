get_abs_path() {
  local target="$1"
  if [ -d "$target" ]; then
    cd -- "$target" && pwd
  elif [ -f "$target" ]; then
    local dir=$(dirname -- "$target")
    local base=$(basename -- "$target")
    echo "$(cd -- "$dir" && pwd)/$base"
  else
    echo "Error: '$target' does not exist" >&2
    return 1
  fi
}

fast_count() {
  local pattern="$1"
  local arr=("$pattern")
  echo "${#arr[@]}"
}

count_items_in_path() {
  local p="$1"
  local total
  if $show_hidden_files; then
    local a=("$p"/*)
    local b=("$p"/.*)
    local count_a="${#a[@]}"
    local count_b="${#b[@]}"
    [[ "${a[0]}" == "$p/*" ]] && count_a=0
    local filtered=0
    for x in "${b[@]}"; do
      local bn; bn=$(basename "$x")
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ((filtered++))
    done
    total=$((count_a + filtered))
  else
    local a=("$p"/*)
    total="${#a[@]}"
    [[ "${a[0]}" == "$p/*" ]] && total=0
  fi
  echo "$total"
}
build_items_for_prefix() {
  build_items_with_meta "$1" "$2"
  apply_sort
}

build_all_items() {
  build_items_with_meta "$1" ""
  apply_sort
}

get_imaginary_groups() {
  local p="$1"
  local pfx="$2"
  declare -gA group_counts=()
  group_chars=()
  local chars=()
  local -A _seen_chars=()

  while IFS= read -r -d '' entry; do
    local bn="${entry##*/}"
    [[ "$bn" == "." || "$bn" == ".." ]] && continue
    if ! $show_hidden_files && [[ "$bn" == .* ]]; then
      continue
    fi
    [[ ${#bn} -le ${#pfx} ]] && continue
    local bn_lower="${bn,,}"
    [[ "$bn_lower" != "$pfx"* ]] && continue
    local next="${bn_lower:${#pfx}:1}"

    if [[ "$next" =~ ^[a-z]$ ]]; then
      local upper="${next^^}"
      group_counts["$upper"]=$(( ${group_counts["$upper"]:-0} + 1 ))
      [ -z "${_seen_chars["$upper"]+x}" ] && chars+=("$upper") && _seen_chars["$upper"]=1
    elif [[ "$next" =~ ^[0-9]$ ]]; then
      group_counts["$next"]=$(( ${group_counts["$next"]:-0} + 1 ))
      [ -z "${_seen_chars["$next"]+x}" ] && chars+=("$next") && _seen_chars["$next"]=1
    else
      case "$next" in
        _|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ')
          group_counts["$next"]=$(( ${group_counts["$next"]:-0} + 1 ))
          [ -z "${_seen_chars["$next"]+x}" ] && chars+=("$next") && _seen_chars["$next"]=1
          ;;
        *)
          group_counts["#"]=$(( ${group_counts["#"]:-0} + 1 ))
          [ -z "${_seen_chars["#"]+x}" ] && chars+=("#") && _seen_chars["#"]=1
          ;;
      esac
    fi
  done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)

  group_chars=("${chars[@]}")
}

build_imaginary_groups() {
  local p="$1"
  local pfx="$2"
  local total="$3"
  _imag_banner="📂 Too many items ($total). Imaginary groups by next character:"
  get_imaginary_groups "$p" "$pfx"

  local specials=()
  local digits=()
  local letters=()
  local fallback=()

  for ch in "${group_chars[@]}"; do
    if [[ "$ch" =~ ^[A-Z]$ ]]; then
      letters+=("$ch")
    elif [[ "$ch" =~ ^[0-9]$ ]]; then
      digits+=("$ch")
    elif [[ "$ch" == "#" ]]; then
      fallback+=("$ch")
    else
      specials+=("$ch")
    fi
  done

  IFS=$'\n' sorted_specials=($(builtin printf '%s\n' "${specials[@]}" | sort))
  IFS=$'\n' sorted_digits=($(builtin printf '%s\n' "${digits[@]}" | sort))
  IFS=$'\n' sorted_letters=($(builtin printf '%s\n' "${letters[@]}" | sort))
  unset IFS

  local sorted=("${sorted_specials[@]}" "${sorted_digits[@]}" "${sorted_letters[@]}" "${fallback[@]}")

  imaginary_map=()
  imaginary_lines=()
  local idx=1
  for ch in "${sorted[@]}"; do
    local cnt="${group_counts[$ch]}"
    imaginary_lines+=("$(builtin printf ' %2d) 📁 %s (%d items)' "$idx" "$ch" "$cnt")")
    imaginary_map+=("$ch")
    idx=$((idx+1))
  done
}

display_imaginary_groups() {
  build_imaginary_groups "$1" "$2" "$3"
  builtin printf "%s\n" "$_imag_banner" "${imaginary_lines[@]}"
}
select_items_common() {
  local prompt="$1"
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available"
    return 1
  fi

  local _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos itemlist

  _vp_mode="items"
  _multi_prompt_loop

  itemlist="$_buf"
  local indices=($(parse_selection "$itemlist" "${#items[@]}"))
  selected_items=()
  for idx in "${indices[@]}"; do
    selected_items+=("${items[$((idx-1))]}")
  done
  if [ ${#selected_items[@]} -eq 0 ]; then
    echo "❌ No valid items selected"
    return 1
  fi
  return 0
}

select_imaginary_items_common() {
  local p="$1"
  local pfx="$2"
  local prompt="${3:-DELETE}"

  if [ "${#imaginary_map[@]}" -eq 0 ]; then
    echo "❌ No groups available"
    return 1
  fi

  local _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos

  _vp_mode="imaginary"
  _multi_prompt_loop

  local indices=($(parse_selection "$_buf" "${#imaginary_map[@]}"))
  if [ "${#indices[@]}" -eq 0 ]; then
    echo "❌ No valid groups selected"
    return 1
  fi
  selected_items=()
  for idx in "${indices[@]}"; do
    local ch="${imaginary_map[$((idx-1))]}"
    local ch_lower="${ch,,}"
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ! $show_hidden_files && [[ "$bn" == .* ]] && continue
      local bn_lower="${bn,,}"
      [[ "$bn_lower" != "$pfx"* ]] && continue
      local next_char="${bn_lower:${#pfx}:1}"
      if [ "$ch" == "#" ]; then
        case "$next_char" in
          [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ')
            continue ;;
        esac
      else
        [[ "$next_char" != "$ch_lower" ]] && continue
      fi
      selected_items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  done
  local -A _seen=()
  local unique=()
  for f in "${selected_items[@]}"; do
    [ -z "${_seen[$f]+x}" ] && unique+=("$f") && _seen["$f"]=1
  done
  selected_items=("${unique[@]}")
  if [ "${#selected_items[@]}" -eq 0 ]; then
    echo "❌ No items found for selected groups"
    return 1
  fi
  return 0
}

handle_force_show() {
  if $force_show; then
    force_show=false
    echo "🔓 Force show disabled"
  else
    force_show=true
    echo "🔓 Force show enabled — displaying all items"
  fi
}

handle_selection() {
  local choice="$1"
  if $imaginary_mode; then
    local matched=false
    local ch=""

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"
      matched=true
    elif [[ ${#choice} -eq 1 ]]; then
      local uc="${choice^^}"
      for gc in "${imaginary_map[@]}"; do
        if [[ "$gc" == "$uc" ]] || [[ "$gc" == "$choice" ]]; then
          ch="$gc"
          matched=true
          break
        fi
      done
    fi

    if $matched; then
      if [ "$ch" == "#" ]; then
        imaginary_mode=false
        items=()
        while IFS= read -r -d '' _f; do
          _bn="${_f##*/}"
          [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
          ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
          local _bn_lower="${_bn,,}"
          [ -n "$group_prefix" ] && [[ "$_bn_lower" != "$group_prefix"* ]] && continue
          local _next="${_bn_lower:${#group_prefix}:1}"
          case "$_next" in
            [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ')
              continue ;;
          esac
          items+=("$_f")
        done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
        _collect_metadata
        apply_sort
      elif [[ "$ch" =~ ^[A-Z]$ ]]; then
        group_prefix="${group_prefix}${ch,,}"
        force_show=false
      else
        group_prefix="${group_prefix}${ch}"
        force_show=false
      fi
    else
      echo "⚠️  Invalid selection"
    fi
  else
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
      selected="${items[$((choice-1))]}"
      local bn="${selected##*/}"

      if [[ "$bn" == *.shortcut ]]; then
        local sc_target sc_type
        sc_target=$(_shortcut_resolve "$selected")
        if [ $? -ne 0 ]; then
          echo "💡 The shortcut file is still present — you can delete or rename it."
          return
        fi
        sc_type=$(_shortcut_read_field "$selected" "SHORTCUT_TYPE")

        if [ "$sc_type" == "dir" ] || [ -d "$sc_target" ]; then
          path="$sc_target"
          group_prefix=""
          force_show=false
        else
          handle_file "$sc_target"
        fi
        return
      fi

      if [ -d "$selected" ]; then
        path="$selected"
        group_prefix=""
        force_show=false
      elif [ -f "$selected" ]; then
        handle_file "$selected"
      fi
    else
      echo "⚠️  Invalid selection"
    fi
  fi
}
_menu_header() {
  echo
  local _hdr_loc="📂 Location: $path${group_prefix:+ [group: ${group_prefix^^}*]}"
  if [ -n "$_filter_query" ]; then
    local _fcnt="${#items[@]}"
    local _tcnt="${#_all_items[@]}"
    _hdr_loc+="  🔍 filter: ${_filter_query^^}*  (${_fcnt}/${_tcnt} items)"
  fi
  echo "$_hdr_loc"
}

_menu_header_flat() {
  _menu_header
  if $_has_group_view; then
    _gv_chain="${group_view_levels[*]}"
    echo "🗂️  Group view: ${_gv_chain// / → }  (change in Settings → 9)"
  fi
}

_menu_header_imaginary() {
  _menu_header
  echo "$_imag_banner"
}

_menu_body_flat() {
  if $_has_group_view; then
    _gv_chain="${group_view_levels[*]}"
    echo "🗂️  Group view: ${_gv_chain// / → }  (change in Settings → 9)"
  fi
  display_items
}

_menu_footer_lines() {
  builtin printf "\nu) Up   cd) Change directory   t) Transfer\nd) Delete   c) Create   f) Find    r) Rename\nq/h) Quit/Home   s) Settings   x) Organise\n-h) Help   -u) Upgrade\n"
  [ -n "$group_prefix" ] && echo "back) Remove last prefix char (current: ${group_prefix^^}*)"
  if [ "$total" -gt "${index_mode_threshold:-200}" ] && ! $force_show && [ "${#group_view_levels[@]}" -gt 0 ]; then
    echo "Group view is set but above threshold. Press forceshow to enable grouped display"
  fi
}

_render_items_with_highlight() {
  local -A hl=()
  local x
  for x in "$@"; do hl["$x"]=1; done
  local i line
  for ((i=1; i<=${#items[@]}; i++)); do
    line=$(_item_line_text "$i")
    if [ -n "${hl[$i]+x}" ]; then
      builtin printf '%s\n' "$(_highlight "$line")"
    else
      builtin printf '%s\n' "$line"
    fi
  done
}

_print_input_line() {
  builtin printf '\r\033[K'
  builtin printf "Select: %s" "$_buf"
  local back=$(( ${#_buf} - _pos ))
  [ "$back" -gt 0 ] && builtin printf '\033[%dD' "$back"
}

_update_highlight() {
  local old="$1" new="$2"
  if [ "$old" -ge 1 ] && [ "$old" -ne "$new" ]; then
    _vp_repaint_row "$old"
  fi
  if [ "$new" -ge 1 ]; then
    _vp_repaint_row "$new"
  fi
  return 0
}
_vp_goto() {
  local old="$1" new="$2"
  if _vp_ensure_visible "$new"; then
    _vp_rerender
  else
    _update_highlight "$old" "$new"
    $_vp_input_fn
  fi
}

_nav_jump_to() {
  $_can_nav || return 0
  _vp_count
  (( _vp_n == 0 )) && return 0
  local target="$1" old="${_hl_index:-0}"
  (( target < 1 )) && target=1
  (( target > _vp_n )) && target=$_vp_n
  _hl_index=$target
  _buf="$_hl_index"; _pos=${#_buf}
  if [ "$target" -eq "$old" ]; then
    $_vp_input_fn
  else
    _vp_goto "$old" "$_hl_index"
  fi
  return 0
}

_sync_highlight_from_buf() {
  $_can_nav || return
  _vp_count
  (( _vp_n == 0 )) && return

  if [[ "$_buf" =~ ^([A-Za-z]+-{1,2})(a(-[0-9][0-9,-]*)?|[0-9][0-9,-]*)$ ]]; then
    local body="${BASH_REMATCH[2]}"
    local -A _old=()
    local k
    for k in "${!_msel_set[@]}"; do _old[$k]=1; done
    _msel_set=()
    local -a _hl_indices=()
    if [[ "$body" == "a" ]]; then
      _hl_indices=($(seq 1 "$_vp_n"))
    elif [[ "$body" =~ ^a-(.+)$ ]]; then
      _hl_indices=($(_sp_parse_all_except "${BASH_REMATCH[1]}" "$_vp_n"))
    else
      _hl_indices=($(parse_selection "$body" "$_vp_n"))
    fi
    for k in "${_hl_indices[@]}"; do _msel_set[$k]=1; done

    if [ "$_vp_hl_fn" != "_vp_is_hl_multi" ]; then
      _vp_hl_fn=_vp_is_hl_multi
      _hl_index=0
      _vp_rerender
    else
      local -A _chg=()
      for k in "${!_old[@]}";      do [ -z "${_msel_set[$k]+x}" ] && _chg[$k]=1; done
      for k in "${!_msel_set[@]}"; do [ -z "${_old[$k]+x}"      ] && _chg[$k]=1; done
      for k in "${!_chg[@]}"; do _vp_repaint_row "$k"; done
      if [[ "$body" != a* ]]; then
        local last="${body##*[,-]}"
        [[ "$last" =~ ^[0-9]+$ ]] && _vp_ensure_visible "$last" && _vp_rerender
      fi
    fi
    _print_input_line
    return
  fi

  if [ "${_vp_hl_fn:-}" = "_vp_is_hl_multi" ]; then
    _msel_set=()
    _vp_hl_fn=_vp_is_hl_single
    _hl_index=0
    _vp_rerender
    _print_input_line
  fi

  [[ "$_buf" =~ ^[0-9]+$ ]] || return
  local n=$((10#$_buf))
  (( n < 1 )) && n=1
  (( n > _vp_n )) && n=$_vp_n
  if [ "$n" -ne "${_hl_index:-0}" ]; then
    local old="${_hl_index:-0}"
    _hl_index=$n
    _vp_goto "$old" "$_hl_index"
  fi
}
_read_choice() {
  choice=""
  _can_nav=false
  _vp_count
  if [ "$_vp_n" -gt 0 ]; then
    _can_nav=true
    [ "${_hl_index:-0}" -gt "$_vp_n" ] && _hl_index="$_vp_n"
  else
    _hl_index=0
  fi

  stty -icanon -echo min 1 time 0 2>/dev/null
  trap '_vp_on_resize' WINCH

  _buf=""
  _pos=0
  local key seq _rc
  _print_input_line

  while true; do
    IFS= read -rsn1 -t "$_vp_poll_cur" key
    _rc=$?
    if [ "$_rc" -gt 128 ]; then
      _vp_poll_tick
      if _vp_check_resize; then
        _vp_cache_reset
        _vp_prime_rows
        _vp_redraw_in_place
        _vp_poll_active
      fi
      continue
    fi
    [ "$_rc" -ne 0 ] && break
    _vp_poll_active
    if [[ "$key" == $'\x1b' ]]; then
      _read_key_seq || continue
      _key_name "$_esc"
      case "$_kname" in
        up)
          if $_can_nav; then
            local old="$_hl_index"
            if [ "$_hl_index" -lt 1 ]; then
              _hl_index="$_vp_n"
            else
              _hl_index=$(( _hl_index - 1 ))
              [ "$_hl_index" -lt 1 ] && _hl_index="$_vp_n"
            fi
            _buf="$_hl_index"; _pos=${#_buf}
            _vp_goto "$old" "$_hl_index"
          fi
          ;;
        down)
          if $_can_nav; then
            local old="$_hl_index"
            if [ "$_hl_index" -lt 1 ]; then
              _hl_index=1
            else
              _hl_index=$(( _hl_index + 1 ))
              [ "$_hl_index" -gt "$_vp_n" ] && _hl_index=1
            fi
            _buf="$_hl_index"; _pos=${#_buf}
            _vp_goto "$old" "$_hl_index"
          fi
          ;;
        pgup)   _nav_jump_to $(( _hl_index - _vp_page_step )) ;;
        pgdn)   _nav_jump_to $(( _hl_index + _vp_page_step )) ;;
        home)   _nav_jump_to 1 ;;
        end)    _nav_jump_to "$_vp_n" ;;
        right)
          if [ -z "$_buf" ] && [ "${_sw_in_mode:-0}" = "1" ]; then
            choice="__sw_tab_right__"; break
          elif [ "$_pos" -lt "${#_buf}" ]; then
            _pos=$(( _pos + 1 ))
            builtin printf '\033[1C'
          fi
          ;;
        left)
          if [ -z "$_buf" ] && [ "${_sw_in_mode:-0}" = "1" ]; then
            choice="__sw_tab_left__"; break
          elif [ "$_pos" -gt 0 ]; then
            _pos=$(( _pos - 1 ))
            builtin printf '\033[1D'
          fi
          ;;
        *) : ;;
      esac
      continue
    fi

    case "$key" in
      "")
        break
        ;;
      $'\x7f'|$'\x08')
        if ! _filter_on_backspace; then
          if [ "$_pos" -gt 0 ]; then
            _buf="${_buf:0:_pos-1}${_buf:_pos}"
            _pos=$(( _pos - 1 ))
            _print_input_line
            _sync_highlight_from_buf
          fi
        fi
        ;;
      $'\x01') _nav_jump_to 1 ;;
      $'\x05') _nav_jump_to "$_vp_n" ;;
      *)
        _is_ctrl_char "$key" && continue
        if ! _filter_on_char "$key"; then
          _buf="${_buf:0:_pos}${key}${_buf:_pos}"
          _pos=$(( _pos + 1 ))
          _print_input_line
          _sync_highlight_from_buf
        fi
        ;;
    esac
  done

  trap - WINCH
  stty "$_orig_stty" 2>/dev/null
  echo

  if [ -n "$_buf" ]; then
    choice="$_buf"
  elif $_can_nav && [ "$_hl_index" -ge 1 ]; then
    choice="$_hl_index"
  fi
}
_BVK_LASTDIR_FILE="${HOME}/.bashbasicsbyvk/lastdir"
_BVK_RECENTS_PID_FILE="${HOME}/.bashbasicsbyvk/recents.pid"

_bvk_wake_recents_daemon() {
  local _candidates=(
    "$SCRIPT_DIR/file/bashbasicsbyvk_recents_daemon.py"
    "$SCRIPT_DIR/file/bashbasicsbyvk_recents_daemon"
    "$SCRIPT_DIR/bashbasicsbyvk_recents_daemon.py"
    "$SCRIPT_DIR/bashbasicsbyvk_recents_daemon"
  )
  local _daemon_script=""
  local _c
  for _c in "${_candidates[@]}"; do
    if [ -f "$_c" ]; then
      _daemon_script="$_c"
      break
    fi
  done
  [ -n "$_daemon_script" ] || return

  local _pid
  _pid=$(cat "$_BVK_RECENTS_PID_FILE" 2>/dev/null)
  kill -0 "$_pid" 2>/dev/null && return

  if [ -x "$_daemon_script" ]; then
    "$_daemon_script" </dev/null >/dev/null 2>&1 &
  elif command -v python3 >/dev/null 2>&1; then
    python3 "$_daemon_script" </dev/null >/dev/null 2>&1 &
  else
    python "$_daemon_script" </dev/null >/dev/null 2>&1 &
  fi
  disown
}
path="$(pwd -P)"
export BVK_FILEMANAGER_BOUNDARY="$path"
selected_items=()
group_prefix=""
force_show=false
_has_group_view=false
_gv_chain=""
declare -a imaginary_map=()
declare -a imaginary_lines=()
_imag_banner=""
declare -a group_chars=()
declare -A group_counts=()
nav_result_path=""
nav_selected_items=()
gcloud_nav_result_path=""
gcloud_nav_selected_items=()
_sw_did_switch=false
