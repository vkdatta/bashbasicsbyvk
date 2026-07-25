#!/usr/bin/env bash
# ============================================================
#  SMART MENU  —  universal interactive-menu highlighter
#
#  Retrofits arrow-key navigation, background highlighting and
#  PgUp/PgDn/Home/End onto EVERY menu in the project without
#  touching a single menu function, present or future.
#
#  How it works
#  ------------
#  Shell functions take precedence over builtins, so this file
#  shims three builtins:
#
#    echo / printf  record whatever they emit into a small ring
#                   buffer, then emit it unchanged.
#    read           when called as `read -p "..." var` on a tty,
#                   it looks back at the ring buffer. If the
#                   lines just printed look like a numbered menu
#                   it erases them, re-renders them through the
#                   viewport engine (highlight + scrolling), and
#                   returns the chosen option. Otherwise it hands
#                   straight over to the real builtin.
#
#  So any function that prints "1) ...\n2) ..." and then calls
#  read -p gets the full treatment for free. Nothing to register,
#  no per-menu wiring, and new menus are picked up automatically.
#
#  Disable at any time with:  export VK_SMART_MENUS=0
# ============================================================

_sm_enabled=true
[ "${VK_SMART_MENUS:-1}" = "0" ] && _sm_enabled=false
# _sm_on is the single hot-path flag: 1 only when capture is both
# enabled and not suspended. Kept as a plain int so the shims can
# test it and the tty in one [[ ]] compound.
_sm_on=1
$_sm_enabled || _sm_on=0
_sm_sync_on() {
  if $_sm_enabled && ! $_sm_active; then _sm_on=1; else _sm_on=0; fi
}

declare -a _sm_lines=()
_sm_partial=""
_sm_max=400
_sm_keep=250
_sm_active=false          # re-entrancy guard
_sm_result=""
_sm_tok=""

_sm_reset() { _sm_lines=(); _sm_partial=""; }

# ------------------------------------------------------------
# capture
# ------------------------------------------------------------
_sm_record() {
  # Callers have already established that output is reaching a tty
  # and that capture is enabled; see the shims below.
  local rest="$1"

  # a screen clear invalidates everything above it
  case "$rest" in
    *$'\033'"[2J"*) _sm_reset; rest="${rest##*$'\033'\[2J}" ;;
  esac

  while [[ "$rest" == *$'\n'* ]]; do
    _sm_partial+="${rest%%$'\n'*}"
    _sm_lines+=("$_sm_partial")
    _sm_partial=""
    rest="${rest#*$'\n'}"
  done
  _sm_partial+="$rest"

  if [ "${#_sm_lines[@]}" -gt "$_sm_max" ]; then
    _sm_lines=("${_sm_lines[@]: -$_sm_keep}")
  fi
  return 0
}

echo() {
  # Fast path: if nothing is going to the screen there is nothing
  # worth capturing, so hand straight to the builtin. This keeps
  # bulk output (item listings, subshells, redirects) at native cost.
  [[ $_sm_on == 1 && -t 1 ]] || { builtin echo "$@"; return $?; }
  local __n=0 __e=0 __s
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n)      __n=1; shift ;;
      -e)      __e=1; shift ;;
      -E)      __e=0; shift ;;
      -ne|-en) __n=1; __e=1; shift ;;
      *) break ;;
    esac
  done
  __s="$*"
  [ "$__e" -eq 1 ] && builtin printf -v __s '%b' "$__s"
  [ "$__n" -eq 1 ] || __s+=$'\n'
  builtin printf '%s' "$__s"
  _sm_record "$__s"
  return 0
}

printf() {
  if [ "$1" = "-v" ] || [[ $_sm_on != 1 || ! -t 1 ]]; then
    builtin printf "$@"
    return $?
  fi
  local __s __rc
  builtin printf -v __s "$@"
  __rc=$?
  builtin printf '%s' "$__s"
  _sm_record "$__s"
  return $__rc
}

clear() {
  command clear "$@"
  local __rc=$?
  _sm_reset
  return $__rc
}

# ------------------------------------------------------------
# menu detection
# ------------------------------------------------------------
# An option line is "  1) Label", "3. Label" or "cd) Label".
# Non-numeric tokens must use ')' so prose like "Note. blah"
# is not mistaken for a menu entry.
_sm_is_option() {
  local plain
  if declare -F _vp_strip_ansi >/dev/null 2>&1; then
    _vp_strip_ansi "$1"; plain="$_vp_plain"
  else
    plain="$1"
  fi
  if [[ "$plain" =~ ^[[:space:]]{0,4}([0-9]+)[\).][[:space:]] ]]; then
    _sm_tok="${BASH_REMATCH[1]}"; return 0
  fi
  if [[ "$plain" =~ ^[[:space:]]{0,4}([A-Za-z0-9_-]{1,4})\)[[:space:]] ]]; then
    _sm_tok="${BASH_REMATCH[1]}"; return 0
  fi
  return 1
}

_sm_plain_len() {
  if declare -F _vp_strip_ansi >/dev/null 2>&1; then
    _vp_strip_ansi "$1"; _sm_len=${#_vp_plain}
  else
    _sm_len=${#1}
  fi
}

# physical rows a logical line occupies at the current width
_sm_phys_rows() {
  local cols="${_vp_cols:-80}"
  _sm_plain_len "$1"
  (( cols < 2 )) && cols=80
  _sm_rows_of=$(( _sm_len / cols + 1 ))
}

# Fills _sm_hdr / _sm_rows_text / _sm_rows_token / _sm_ftr / _sm_erase
_sm_detect() {
  local n=${#_sm_lines[@]} i limit last=-1 first gap=0
  (( n == 0 )) && return 1
  limit=$(( n - 60 )); (( limit < 0 )) && limit=0

  for ((i=n-1; i>=limit; i--)); do
    if _sm_is_option "${_sm_lines[$i]}"; then last=$i; break; fi
  done
  (( last < 0 )) && return 1

  first=$last
  for ((i=last-1; i>=limit; i--)); do
    if _sm_is_option "${_sm_lines[$i]}"; then
      first=$i; gap=0
    else
      gap=$(( gap + 1 ))
      (( gap > 2 )) && break
    fi
  done

  _sm_rows_text=(); _sm_rows_token=(); _sm_hdr=(); _sm_ftr=()
  for ((i=first; i<=last; i++)); do
    if _sm_is_option "${_sm_lines[$i]}"; then
      _sm_rows_text+=("${_sm_lines[$i]}")
      _sm_rows_token+=("$_sm_tok")
    else
      # interleaved blank/sub-heading: keep it attached to the row above
      _sm_rows_text+=("${_sm_lines[$i]}")
      _sm_rows_token+=("")
    fi
  done

  # need at least two real choices to be worth taking over
  local real=0
  for i in "${_sm_rows_token[@]}"; do [ -n "$i" ] && real=$(( real + 1 )); done
  (( real < 2 )) && return 1

  # the options must still be adjacent to the prompt; if a pile of
  # other output came after them, this read is not that menu's read
  (( n - 1 - last > 3 )) && return 1

  # title lines immediately above the first option (max 6, stop at 2nd blank)
  local h_start=$first blanks=0
  for ((i=first-1; i>=limit && i>=first-6; i--)); do
    _sm_plain_len "${_sm_lines[$i]}"
    if [ "$_sm_len" -eq 0 ]; then
      blanks=$(( blanks + 1 ))
      (( blanks > 1 )) && break
    fi
    h_start=$i
  done
  for ((i=h_start; i<first; i++)); do _sm_hdr+=("${_sm_lines[$i]}"); done
  for ((i=last+1; i<n; i++)); do _sm_ftr+=("${_sm_lines[$i]}"); done

  # how many physical rows to erase before re-rendering
  _sm_erase=0
  for i in "${_sm_hdr[@]}" "${_sm_rows_text[@]}" "${_sm_ftr[@]}"; do
    _sm_phys_rows "$i"
    _sm_erase=$(( _sm_erase + _sm_rows_of ))
  done
  return 0
}

# ------------------------------------------------------------
# viewport hooks
# ------------------------------------------------------------
_sm_count()   { _vp_n=${#_sm_rows_text[@]}; }
_sm_rowtext() { _vp_line="${_sm_rows_text[$(($1-1))]}"; }
_sm_header_fn() { local l; for l in "${_sm_hdr[@]}"; do builtin echo "$l"; done; return 0; }
_sm_footer_fn() { local l; for l in "${_sm_ftr[@]}"; do builtin echo "$l"; done; return 0; }

_sm_input_fn() {
  builtin printf '\r\033[K%s%s' "$_sm_prompt" "$_buf"
  local back=$(( ${#_buf} - _pos ))
  [ "$back" -gt 0 ] && builtin printf '\033[%dD' "$back"
  return 0
}

# rows that are only spacing are not selectable
_sm_row_selectable() { [ -n "${_sm_rows_token[$(($1-1))]}" ]; }

_sm_next_selectable() {
  local i="$1" dir="$2" n=${#_sm_rows_text[@]} guard=0
  while (( guard++ < n )); do
    (( i < 1 )) && i=$n
    (( i > n )) && i=1
    _sm_row_selectable "$i" && { builtin echo "$i"; return 0; }
    i=$(( i + dir ))
  done
  builtin echo "$1"
}

# map the typed buffer onto the row whose token matches, so a
# menu numbered 0..2 highlights correctly
_sm_sync_from_buf() {
  [ -z "$_buf" ] && return 0
  local i n=${#_sm_rows_token[@]} old="${_hl_index:-0}"
  for ((i=0; i<n; i++)); do
    if [ "${_sm_rows_token[$i]}" = "$_buf" ]; then
      if [ "$(( i + 1 ))" -ne "$old" ]; then
        _hl_index=$(( i + 1 ))
        _vp_goto "$old" "$_hl_index"
      fi
      return 0
    fi
  done
  return 0
}

_sm_set_index() {
  local old="${_hl_index:-0}" new="$1"
  _hl_index="$new"
  _buf="${_sm_rows_token[$((new-1))]}"
  _pos=${#_buf}
  if [ "$new" -eq "$old" ]; then _sm_input_fn; else _vp_goto "$old" "$new"; fi
}

# ------------------------------------------------------------
# the interactive loop
# ------------------------------------------------------------
_sm_run() {
  local key _rc n
  _buf=""; _pos=0; _hl_index=0
  _can_nav=true
  _vp_mode="generic"
  _vp_count_fn=_sm_count
  _vp_rowtext_fn=_sm_rowtext
  _vp_header_fn=_sm_header_fn
  _vp_footer_fn=_sm_footer_fn
  _vp_hl_fn=_vp_is_hl_single
  _vp_input_fn=_sm_input_fn
  _vp_start=1
  _vp_cache_reset

  # wipe the already-printed copy of the menu, then draw our own
  local up="$_sm_erase" rows
  rows=$(_term_rows)
  (( up > rows - 1 )) && up=$(( rows - 1 ))
  if (( up > 0 )); then
    builtin printf '\r\033[%dA\033[J' "$up"
  else
    builtin printf '\r\033[J'
  fi

  _vp_render_fresh
  _sm_count
  n="$_vp_n"

  stty -icanon -echo min 1 time 0 2>/dev/null
  while true; do
    IFS= builtin read -rsn1 -t "${_vp_poll_cur:-0.5}" key
    _rc=$?
    if [ "$_rc" -gt 128 ]; then
      _vp_poll_tick
      if _vp_check_resize; then
        _vp_cache_reset
        _vp_render_fresh
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
        up)   _sm_set_index "$(_sm_next_selectable $(( ${_hl_index:-1} <= 1 ? n : _hl_index - 1 )) -1)" ;;
        down) _sm_set_index "$(_sm_next_selectable $(( ${_hl_index:-0} >= n ? 1 : _hl_index + 1 )) 1)" ;;
        pgup) _sm_set_index "$(_sm_next_selectable $(( ${_hl_index:-1} - ${_vp_page_step:-10} < 1 ? 1 : _hl_index - _vp_page_step )) 1)" ;;
        pgdn) _sm_set_index "$(_sm_next_selectable $(( ${_hl_index:-0} + ${_vp_page_step:-10} > n ? n : _hl_index + _vp_page_step )) -1)" ;;
        home) _sm_set_index "$(_sm_next_selectable 1 1)" ;;
        end)  _sm_set_index "$(_sm_next_selectable "$n" -1)" ;;
        right)
          if [ "$_pos" -lt "${#_buf}" ]; then _pos=$(( _pos + 1 )); builtin printf '\033[1C'; fi ;;
        left)
          if [ "$_pos" -gt 0 ]; then _pos=$(( _pos - 1 )); builtin printf '\033[1D'; fi ;;
        *) : ;;
      esac
      continue
    fi

    case "$key" in
      "") break ;;
      $'\x7f'|$'\x08')
        if [ "$_pos" -gt 0 ]; then
          _buf="${_buf:0:_pos-1}${_buf:_pos}"
          _pos=$(( _pos - 1 ))
          _sm_input_fn
          _sm_sync_from_buf
        fi
        ;;
      $'\x01') _sm_set_index "$(_sm_next_selectable 1 1)" ;;
      $'\x05') _sm_set_index "$(_sm_next_selectable "$n" -1)" ;;
      *)
        _is_ctrl_char "$key" && continue
        _buf="${_buf:0:_pos}${key}${_buf:_pos}"
        _pos=$(( _pos + 1 ))
        _sm_input_fn
        _sm_sync_from_buf
        ;;
    esac
  done

  [ -n "${_orig_stty:-}" ] && stty "$_orig_stty" 2>/dev/null
  builtin echo

  if [ -n "$_buf" ]; then
    _sm_result="$_buf"
  elif [ "${_hl_index:-0}" -ge 1 ]; then
    _sm_result="${_sm_rows_token[$((_hl_index-1))]}"
  else
    _sm_result=""
  fi
  return 0
}

# ------------------------------------------------------------
# the read shim
# ------------------------------------------------------------
read() {
  # fast path: anything without -p is never a menu prompt
  case "$*" in
    *-p*) ;;
    *) builtin read "$@"; return $? ;;
  esac

  # locals here also snapshot the outer values, which makes
  # nested menus (a submenu opened from a menu) re-entrant
  local _sm_prompt="" _sm_var="" _sm_ok=1 _sm_rc=0
  local _buf _pos _hl_index _can_nav _esc _kname
  local _vp_mode _vp_start _vp_end _vp_n _vp_page
  local _vp_count_fn _vp_rowtext_fn _vp_header_fn _vp_footer_fn
  local _vp_hl_fn _vp_input_fn _blk_h _vp_erase
  local -a _sm_hdr=() _sm_ftr=() _sm_rows_text=() _sm_rows_token=()
  local _sm_erase=0 _sm_len=0 _sm_rows_of=0

  local -a __smr_a=("$@")
  local __smr_i __smr_c __smr_f __smr_rest __smr_n=${#__smr_a[@]}
  for ((__smr_i=0; __smr_i<__smr_n; __smr_i++)); do
    __smr_f="${__smr_a[$__smr_i]}"
    case "$__smr_f" in
      --) ;;
      -*)
        __smr_rest="${__smr_f#-}"
        while [ -n "$__smr_rest" ]; do
          __smr_c="${__smr_rest:0:1}"; __smr_rest="${__smr_rest:1}"
          case "$__smr_c" in
            r) ;;
            p)
              if [ -n "$__smr_rest" ]; then _sm_prompt="$__smr_rest"; __smr_rest=""
              else __smr_i=$(( __smr_i + 1 )); _sm_prompt="${__smr_a[$__smr_i]}"; fi
              ;;
            *) _sm_ok=0; __smr_rest="" ;;    # -s -a -d -n -t -u -i -e ...
          esac
        done
        ;;
      *) [ -z "$_sm_var" ] && _sm_var="$__smr_f" ;;
    esac
  done
  [ -z "$_sm_var" ] && _sm_var="REPLY"

  # A read consumes whatever was printed above it, so the capture
  # is reset on every path out of here. Without this, a menu printed
  # before an unrelated prompt would still be sitting in the buffer
  # and could be re-rendered over the wrong question.
  # The target name must not collide with any local held by this
  # function, or printf -v would write to our local instead of the
  # caller's variable.
  case "$_sm_var" in
    _sm_*|_vp_*|__smr_*|_buf|_pos|_hl_index|_can_nav|_esc|_kname|_blk_h|REPLY_sm) _sm_ok=0 ;;
  esac

  if ! $_sm_enabled || [ "$_sm_ok" -eq 0 ] || $_sm_active \
     || [ ! -t 0 ] || [ ! -t 1 ] \
     || ! declare -F _vp_render_fresh >/dev/null 2>&1; then
    builtin read "$@"; _sm_rc=$?; _sm_reset; return $_sm_rc
  fi

  if ! _sm_detect; then
    builtin read "$@"; _sm_rc=$?; _sm_reset; return $_sm_rc
  fi

  local __smr_rows
  __smr_rows=$(_term_rows)
  if [ "$__smr_rows" -lt 8 ]; then
    builtin read "$@"; _sm_rc=$?; _sm_reset; return $_sm_rc
  fi

  # a partially written line becomes part of the prompt
  [ -n "$_sm_partial" ] && _sm_prompt="$_sm_partial$_sm_prompt"

  _sm_active=true; _sm_sync_on
  _sm_run
  _sm_active=false; _sm_sync_on
  _sm_reset

  builtin printf -v "$_sm_var" '%s' "$_sm_result"
  return 0
}
