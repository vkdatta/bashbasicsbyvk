_vp_rows_now=0
_vp_cols_now=0
_vp_size_pending=""

_vp_read_size() {
  local sz r c
  _vp_pr=""; _vp_pc=""
  sz=$(stty size 2>/dev/null)
  r="${sz%% *}"; c="${sz##* }"
  if [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -gt 0 ] \
     && [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ]; then
    _vp_pr="$r"; _vp_pc="$c"
    return 0
  fi
  r=$(tput lines 2>/dev/null); c=$(tput cols 2>/dev/null)
  if [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -gt 0 ] \
     && [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ]; then
    _vp_pr="$r"; _vp_pc="$c"
    return 0
  fi
  return 1
}

_vp_probe_size() {
  if _vp_read_size; then
    _vp_rows_now="$_vp_pr"; _vp_cols_now="$_vp_pc"
  elif [ "$_vp_rows_now" -gt 0 ] 2>/dev/null; then
    : 
  else
    _vp_rows_now=24; _vp_cols_now=80   
  fi
}

_term_rows() {
  [ "$_vp_rows_now" -gt 0 ] 2>/dev/null || _vp_probe_size
  echo "$_vp_rows_now"
}

_term_cols() {
  [ "$_vp_cols_now" -gt 0 ] 2>/dev/null || _vp_probe_size
  echo "$_vp_cols_now"
}

_vp_check_resize() {
  _vp_resized=false
  _vp_read_size || return 1
  local nr="$_vp_pr" nc="$_vp_pc"
  if [ "$nr" = "$_vp_rows_now" ] && [ "$nc" = "$_vp_cols_now" ]; then
    _vp_size_pending=""
    return 1
  fi
  if [ "$_vp_size_pending" = "${nr}x${nc}" ]; then
    _vp_rows_now="$nr"; _vp_cols_now="$nc"
    _vp_size_pending=""
    return 0
  fi
  _vp_size_pending="${nr}x${nc}"
  return 1
}

_set_available_above() {
  local total_lines="$1" rows cur_row
  rows=$(_term_rows)
  cur_row=$(( total_lines < rows ? total_lines : rows ))
  _available_above=$(( cur_row - 1 ))
}

_repaint_line_above() {
  local dist="$1" content="$2"
  [ "$dist" -gt "$_available_above" ] && return 1
  builtin printf '\033[s\033[%dA\r\033[2K%s\033[u' "$dist" "$content"
}

declare -gA _vp_rowcache=()
declare -ga _vp_hdr_arr=()
declare -ga _vp_ftr_arr=()
_vp_mode="items"
_vp_start=1
_vp_end=0
_vp_page=0
_vp_n=0
_vp_top_n=0
_vp_footer_n=0
_vp_rows_printed=0
_blk_h=0
_vp_cols=80
_vp_width_margin=2
_vp_line=""
_vp_resized=false
_vp_poll_fast="0.5"
_vp_poll_slow="4"
_vp_poll_cur="0.5"
_vp_idle=0
_vp_rule="   ─────────────────────────────"

_vp_poll_active() { _vp_idle=0; _vp_poll_cur="$_vp_poll_fast"; }
_vp_poll_tick() {
  _vp_idle=$(( _vp_idle + 1 ))
  (( _vp_idle > 12 )) && _vp_poll_cur="$_vp_poll_slow"
}

_vp_strip_ansi() {
  local s="$1" out=""
  while [[ "$s" == *$'\033['* ]]; do
    out+="${s%%$'\033['*}"
    s="${s#*$'\033['}"
    s="${s#*[a-zA-Z]}"
  done
  _vp_plain="$out$s"
}

_vp_fit() {
  local text="$1" limit
  limit=$(( _vp_cols - _vp_width_margin ))
  (( limit < 8 )) && limit=8
  _vp_strip_ansi "$text"
  if [ "${#_vp_plain}" -gt "$limit" ]; then
    _vp_line="${_vp_plain:0:limit-1}…"
  else
    _vp_line="$text"
  fi
}

_vp_count() {
if [ -n "${_vp_count_fn:-}" ]; then
    $_vp_count_fn
    return 0
  fi
  if [ "$_vp_mode" == "imaginary" ]; then
    _vp_n=${#imaginary_map[@]}
  else
    _vp_n=${#items[@]}
  fi
}
_vp_row_text() {
  local i="$1" t
  if [ -n "${_vp_rowcache[$i]+x}" ]; then
    _vp_line="${_vp_rowcache[$i]}"
    return 0
  fi
  if [ -n "${_vp_rowtext_fn:-}" ]; then
    $_vp_rowtext_fn "$i"
    t="$_vp_line"
  elif [ "$_vp_mode" == "imaginary" ]; then
    t="${imaginary_lines[$((i-1))]}"
  else
    t="$(_item_line_text "$i")"
  fi
  _vp_fit "$t"
  _vp_rowcache[$i]="$_vp_line"
  return 0
}

_vp_cache_reset() {
  unset _vp_rowcache
  declare -gA _vp_rowcache=()
  _vp_disp_ok=false
}

_vp_prime_rows() {
  [ "$_vp_mode" == "items" ] || return 0
  declare -F display_items >/dev/null 2>&1 || return 0
  _vp_count
  (( _vp_n == 0 )) && return 0
  local -a _dl=()
  mapfile -t _dl < <(display_items)
  if [ "${#_dl[@]}" -eq "$_vp_n" ]; then
    local i
    for ((i=1; i<=_vp_n; i++)); do
      _vp_fit "${_dl[$((i-1))]}"
      _vp_rowcache[$i]="$_vp_line"
    done
    _vp_disp_ok=true
  else
    _vp_disp_ok=false
    [ -n "$BVK_VP_DEBUG" ] && \
      echo "⚠️  display_items emitted ${#_dl[@]} lines for $_vp_n items — using _item_line_text" >&2
  fi
  return 0
}

_vp_is_hl_single() { [ "$1" -eq "${_hl_index:-0}" ]; }
_vp_is_hl_multi()  { [ -n "${_msel_set[$1]+x}" ]; }
_vp_is_hl() { $_vp_hl_fn "$1"; }

_vp_build_chrome() {
  mapfile -t _vp_hdr_arr < <($_vp_header_fn)
  mapfile -t _vp_ftr_arr < <($_vp_footer_fn)
  _vp_top_n=${#_vp_hdr_arr[@]}
  _vp_footer_n=${#_vp_ftr_arr[@]}
}

_vp_apply_chrome_budget() {
  local i n k tmp=()
  _vp_hdr_out=()
  _vp_ftr_out=()

  if (( _vp_hdr_show >= _vp_top_n )); then
    _vp_hdr_out=("${_vp_hdr_arr[@]}")
  else
    tmp=()
    for i in "${_vp_hdr_arr[@]}"; do [ -n "${i// /}" ] && tmp+=("$i"); done
    n=${#tmp[@]}
    k=$(( n - _vp_hdr_show )); (( k < 0 )) && k=0
    for ((i=k; i<n; i++)); do _vp_hdr_out+=("${tmp[$i]}"); done
  fi

  if (( _vp_ftr_show >= _vp_footer_n )); then
    _vp_ftr_out=("${_vp_ftr_arr[@]}")
  else
    tmp=()
    for i in "${_vp_ftr_arr[@]}"; do [ -n "${i// /}" ] && tmp+=("$i"); done
    n=${#tmp[@]}
    k=0
    for ((i=0; i<n && k<_vp_ftr_show; i++)); do _vp_ftr_out+=("${tmp[$i]}"); k=$((k+1)); done
  fi

  _vp_hdr_show=${#_vp_hdr_out[@]}
  _vp_ftr_show=${#_vp_ftr_out[@]}
}

_vp_geometry() {
  local rows chrome min_rows
  _vp_probe_size
  rows="$_vp_rows_now"
  _vp_cols="$_vp_cols_now"
  _vp_count

  _vp_ind=1
  _vp_hdr_show=$_vp_top_n
  _vp_ftr_show=$_vp_footer_n

  min_rows=3
  (( _vp_n > 0 && _vp_n < min_rows )) && min_rows=$_vp_n
  (( min_rows < 1 )) && min_rows=1

  while :; do
    chrome=$(( _vp_hdr_show + 2 * _vp_ind + _vp_ftr_show + 1 ))
    (( rows - chrome >= min_rows )) && break
    if   (( _vp_ftr_show > 0 ));  then _vp_ftr_show=$(( _vp_ftr_show - 1 ))
    elif (( _vp_ind > 0 ));       then _vp_ind=0
    elif (( _vp_hdr_show > 1 ));  then _vp_hdr_show=$(( _vp_hdr_show - 1 ))
    else break
    fi
  done

  _vp_apply_chrome_budget

  chrome=$(( _vp_hdr_show + 2 * _vp_ind + _vp_ftr_show + 1 ))
  _vp_page=$(( rows - chrome ))
  (( _vp_page < 1 )) && _vp_page=1
  (( _vp_page > _vp_n )) && _vp_page=$_vp_n
  _vp_rows_printed=$_vp_page
  (( _vp_n == 0 )) && _vp_rows_printed=1
  _blk_h=$(( _vp_hdr_show + _vp_ind + _vp_rows_printed + _vp_ind + _vp_ftr_show + 1 ))
}

_vp_ensure_visible() {
  local sel="$1" old="$_vp_start" max_start
  (( _vp_n == 0 )) && { _vp_start=1; return 1; }
  (( sel < 1 )) && sel=1
  (( sel > _vp_n )) && sel=$_vp_n
  if (( sel < _vp_start )); then
    _vp_start=$sel
  elif (( sel > _vp_start + _vp_page - 1 )); then
    _vp_start=$(( sel - _vp_page + 1 ))
  fi
  max_start=$(( _vp_n - _vp_page + 1 ))
  (( max_start < 1 )) && max_start=1
  (( _vp_start > max_start )) && _vp_start=$max_start
  (( _vp_start < 1 )) && _vp_start=1
  _vp_end=$(( _vp_start + _vp_page - 1 ))
  (( _vp_end > _vp_n )) && _vp_end=$_vp_n
  [ "$_vp_start" -ne "$old" ]
}

_vp_el() { builtin printf '\r\033[2K%s\n' "$1"; }

_vp_emit() {
  local i line
  _vp_count
  _vp_end=$(( _vp_start + _vp_page - 1 ))
  (( _vp_end > _vp_n )) && _vp_end=$_vp_n

  for line in "${_vp_hdr_out[@]}"; do _vp_el "$line"; done

  if (( _vp_ind > 0 )); then
    if (( _vp_start > 1 )); then
      _vp_el "   ▲ $(( _vp_start - 1 )) more above"
    else
      _vp_el "$_vp_rule"
    fi
  fi

  if (( _vp_n == 0 )); then
    _vp_el "   (no items)"
  else
    for ((i=_vp_start; i<=_vp_end; i++)); do
      _vp_row_text "$i"
      line="$_vp_line"
      _vp_is_hl "$i" && line="$(_highlight "$line")"
      _vp_el "$line"
    done
  fi

  if (( _vp_ind > 0 )); then
    if (( _vp_end < _vp_n )); then
      _vp_el "   ▼ $(( _vp_n - _vp_end )) more below"
    else
      _vp_el "$_vp_rule"
    fi
  fi

  for line in "${_vp_ftr_out[@]}"; do _vp_el "$line"; done
  _set_available_above "$_blk_h"
  return 0
}

# --- repaint the block in place (block top is _blk_h-1 lines up) ---
_vp_rerender() {
  builtin printf '\033[%dA\r' "$(( _blk_h - 1 ))"
  _vp_emit
  $_vp_input_fn
}

_vp_render_fresh() {
  _vp_build_chrome
  _vp_geometry
  _vp_ensure_visible "${_hl_index:-1}"
  _vp_emit
  $_vp_input_fn
}

_vp_redraw_in_place() {
  local up=$(( _blk_h - 1 ))
  local rows
  rows=$(_term_rows)
  (( up > rows - 1 )) && up=$(( rows - 1 ))
  (( up < 0 )) && up=0
  (( up > 0 )) && builtin printf '\033[%dA' "$up"
  builtin printf '\r\033[J'
  _vp_render_fresh
}

_vp_dist() { echo $(( _vp_end - $1 + _vp_ind + _vp_ftr_show + 1 )); }

_vp_repaint_row() {
  local i="$1" line
  (( i < _vp_start || i > _vp_end )) && return 1
  _vp_row_text "$i"
  line="$_vp_line"
  _vp_is_hl "$i" && line="$(_highlight "$line")"
  _repaint_line_above "$(_vp_dist "$i")" "$line"
  return 0
}

_vp_on_resize() { _vp_resized=true; }

_vp_page_step="${BVK_PAGE_STEP:-10}"

_read_key_seq() {
  local c
  _esc=""
  IFS= read -rsn1 -t 0.08 c || return 1
  _esc="$c"
  case "$c" in
    '[')
      while IFS= read -rsn1 -t 0.08 c; do
        _esc+="$c"
        case "$c" in
          [0-9]|';') continue ;;
          *) break ;;
        esac
      done
      ;;
    'O')
      IFS= read -rsn1 -t 0.08 c && _esc+="$c"
      ;;
  esac
  return 0
}

_key_name() {
  local s="$1" fin body num
  _kname=""
  [ -z "$s" ] && return 1
  fin="${s: -1}"
  case "$s" in
    'O'*)
      case "$fin" in
        A) _kname=up ;; B) _kname=down ;;
        C) _kname=right ;; D) _kname=left ;;
        H) _kname=home ;; F) _kname=end ;;
      esac
      return 0
      ;;
    '['*) ;;
    *) return 1 ;;
  esac
  body="${s:1}"
  num="${body%"$fin"}"
  num="${num%%;*}"
  case "$fin" in
    A) _kname=up ;;
    B) _kname=down ;;
    C) _kname=right ;;
    D) _kname=left ;;
    H) _kname=home ;;
    F) _kname=end ;;
    '~')
      case "$num" in
        1|7) _kname=home ;;
        4|8) _kname=end ;;
        5)   _kname=pgup ;;
        6)   _kname=pgdn ;;
      esac
      ;;
  esac
  return 0
}

_is_ctrl_char() {
  case "$1" in
    [[:cntrl:]]) return 0 ;;
    *) return 1 ;;
  esac
}

parse_selection() {
  local input="$1"
  local max="$2"
  local -a indices=()
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    part=$(echo "$part" | xargs)
    if [[ $part =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      for ((i=start; i<=end && i<=max; i++)); do
        indices+=("$i")
      done
    elif [[ $part =~ ^[0-9]+$ ]]; then
      local num="$part"
      (( num >= 1 && num <= max )) && indices+=("$num")
    fi
  done
  echo "${indices[@]}"
}

_multi_compute_set() {
  _msel_set=()
  local idx
  _vp_count
  for idx in $(parse_selection "$_buf" "$_vp_n"); do
    _msel_set["$idx"]=1
  done
}

_multi_print_input_line() {
  builtin printf '\r\033[K'
  if [ "$_vp_mode" == "imaginary" ]; then
    builtin printf "Group numbers: %s" "$_buf"
  else
    builtin printf "Item numbers: %s" "$_buf"
  fi
  local back=$(( ${#_buf} - _pos ))
  [ "$back" -gt 0 ] && builtin printf '\033[%dD' "$back"
}

_multi_header_fn() {
  _menu_header
  [ "$_vp_mode" == "imaginary" ] && echo "$_imag_banner"
  return 0
}

_multi_footer_fn() {
  echo
  echo "$_prompt (supports ranges: 1-10,15-20,33)"
  echo "up/down ±1, PgUp/PgDn ±${_vp_page_step}, Home/End first/last, left/right move cursor"
}

_multi_render() {
  _multi_compute_set
  clear
  _vp_header_fn=_multi_header_fn
  _vp_footer_fn=_multi_footer_fn
  _vp_hl_fn=_vp_is_hl_multi
  _vp_input_fn=_multi_print_input_line
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows
  _vp_render_fresh
}

_multi_cursor_index() {
  local bounds s e num
  bounds=$(_multi_number_token_bounds) || return 1
  [ -z "$bounds" ] && return 1
  read -r s e <<< "$bounds"
  num="${_buf:s:e-s}"
  [ -z "$num" ] && return 1
  echo $((10#$num))
}

_multi_sync() {
  local -A _old_set=()
  local k
  for k in "${!_msel_set[@]}"; do _old_set["$k"]=1; done

  _multi_compute_set

  local -A _changed=()
  for k in "${!_old_set[@]}"; do
    [ -z "${_msel_set[$k]+x}" ] && _changed["$k"]=1
  done
  for k in "${!_msel_set[@]}"; do
    [ -z "${_old_set[$k]+x}" ] && _changed["$k"]=1
  done

  local target
  target=$(_multi_cursor_index)
  if [ -n "$target" ] && _vp_ensure_visible "$target"; then
    _vp_rerender
    return 0
  fi

  if [ "${#_changed[@]}" -gt 0 ]; then
    local idx
    for idx in "${!_changed[@]}"; do
      _vp_repaint_row "$idx"
    done
  fi

  _multi_print_input_line
}

_multi_number_token_bounds() {
  local s=$_pos e=$_pos
  while [ "$s" -gt 0 ] && [[ "${_buf:s-1:1}" =~ [0-9] ]]; do s=$((s-1)); done
  while [ "$e" -lt "${#_buf}" ] && [[ "${_buf:e:1}" =~ [0-9] ]]; do e=$((e+1)); done
  [ "$s" -eq "$e" ] && return 1
  echo "$s $e"
}

_multi_adjust_number_at_cursor() {
  local dir="$1" bounds s e num n max newnum
  bounds=$(_multi_number_token_bounds)
  if [ -z "$bounds" ]; then
    if [ -z "$_buf" ]; then
      _buf="1"; _pos=1
      _multi_sync
    fi
    return
  fi
  read -r s e <<< "$bounds"
  num="${_buf:s:e-s}"
  n=$((10#$num))
  _vp_count
  max="$_vp_n"
  case "$dir" in
    up)   n=$((n+1)); [ "$n" -gt "$max" ] && n=1 ;;
    down) n=$((n-1)); [ "$n" -lt 1 ] && n=$max ;;
    # page/home/end clamp rather than wrap
    pgup) n=$(( n + _vp_page_step )); [ "$n" -gt "$max" ] && n=$max ;;
    pgdn) n=$(( n - _vp_page_step )); [ "$n" -lt 1 ] && n=1 ;;
    home) n=1 ;;
    end)  n=$max ;;
  esac
  newnum="$n"
  _buf="${_buf:0:s}${newnum}${_buf:e}"
  _pos=$(( s + ${#newnum} ))
  _multi_sync
}

_multi_prompt_loop() {
  local key seq _rc
  _buf=""
  _pos=0

  stty -icanon -echo min 1 time 0 2>/dev/null
  trap '_vp_on_resize' WINCH
  _multi_render

  while true; do
    IFS= read -rsn1 -t "$_vp_poll_cur" key
    _rc=$?
    if [ "$_rc" -gt 128 ]; then
      _vp_poll_tick
      if _vp_check_resize; then _multi_render; _vp_poll_active; fi
      continue
    fi
    [ "$_rc" -ne 0 ] && break
    _vp_poll_active
    if [[ "$key" == $'\x1b' ]]; then
      _read_key_seq || continue
      _key_name "$_esc"
      case "$_kname" in
        up)   _multi_adjust_number_at_cursor up ;;
        down) _multi_adjust_number_at_cursor down ;;
        pgup) _multi_adjust_number_at_cursor pgup ;;
        pgdn) _multi_adjust_number_at_cursor pgdn ;;
        home) _multi_adjust_number_at_cursor home ;;
        end)  _multi_adjust_number_at_cursor end ;;
        right)
          if [ "$_pos" -lt "${#_buf}" ]; then
            _pos=$(( _pos + 1 ))
            builtin printf '\033[1C'
          fi
          ;;
        left)
          if [ "$_pos" -gt 0 ]; then
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
        if [ "$_pos" -gt 0 ]; then
          _buf="${_buf:0:_pos-1}${_buf:_pos}"
          _pos=$(( _pos - 1 ))
          _multi_sync
        fi
        ;;
      $'\x01') _multi_adjust_number_at_cursor home ;;   # Ctrl-A
      $'\x05') _multi_adjust_number_at_cursor end ;;    # Ctrl-E
      *)
        # never let stray control bytes into the buffer
        _is_ctrl_char "$key" && continue
        _buf="${_buf:0:_pos}${key}${_buf:_pos}"
        _pos=$(( _pos + 1 ))
        _multi_sync
        ;;
    esac
  done

  trap - WINCH
  stty "$_orig_stty" 2>/dev/null
  echo
}
