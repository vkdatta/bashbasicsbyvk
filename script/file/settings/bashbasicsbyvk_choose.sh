declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
# bashbasicsbyvk_choose.sh — THE choice menu: yes / no / cancel, pick one, pick many, run an action
# ════════════════════════════════════════════════════════════════════════════
#  Every question with a few fixed answers is asked with THIS menu, never with a one-line
#  `read -p "... (y/N): "` and never with a hand-made row of keys (`c) copy   x) nuke   Enter) back:`).
#  It is the Settings screen engine (_st_run, bashbasicsbyvk_settings_ui.sh) in a small box, so it has
#  the same look, arrows, touch / click, paste handling and  u) / q)  as every other screen:
#
#     ❓ Select Option
#
#        ─────────────────────────────
#      1) [o] Yes
#      2) [ ] No
#      3) [ ] Cancel
#        ─────────────────────────────
#
#     u) Back   q) Close
#     y) Yes   n) No   c/x) Cancel
#     Select:
#
#  Answer by: a row number · a tap or click on a row (double tap = choose) · the arrows + Enter ·
#  or the key printed in the second footer line (y n c x ...) + Enter.  u = back out, q = close up to the main loop.
#
#  Marks (never mix them up):   [o] radio    = exactly ONE can be on   (the mark follows the highlight)
#                               [x] checkbox = ANY number can be on    (Enter / Space / tap toggles)
#                               [ ] off
#
#  API
#     _bvk_yn   VAR "Question" [-d y|n] [-c] [-t Title] [-i Icon]
#                  VAR = y | n | c        rc 0 answered · 1 backed out (u / q / a cancelled flow: VAR is "")
#                  -d  the answer a bare Enter gives (highlighted at start).  Default n: a destructive question never
#                      says yes by accident.   -c  add the Cancel row (c or x)
#     _bvk_menu VAR [-t Title] [-i Icon] [-q Question] [-d key] [-k] [-m] [-n] item...
#                  item = key:Label  or  key|alt|alt:Label     (the first key is the answer; Label is shown)
#                  VAR = the key (-m: the keys, space separated, in row order)     rc 0 chosen · 1 backed out
#                  -k  print the keys in a second footer line     -m  checkboxes (a Done row is added; d = done)
#                  -n  no receipt line after the choice
#
#  Where it cannot draw (no terminal, VK_SMART_MENUS=0, the Settings engine not loaded, a stand-alone tool) it asks the
#  same question as one plain line and reads the answer, so scripts and tests that pipe answers in keep working.
#
#  Needs: _st_run/_st_add (settings_ui). The answer is NOT typed text: never parse it again, compare it to the keys.
# ════════════════════════════════════════════════════════════════════════════

# can the box be drawn here?
_bc_can_draw() {
  [ -t 0 ] && [ -t 1 ] && [ "${VK_SMART_MENUS:-1}" != 0 ] && declare -F _st_run >/dev/null 2>&1
}

# build the rows (called by _st_run before every draw; shares _bvk_menu's locals)
_bc_build() {
  local _bc_j _bc_kind=r
  _st_reset
  (( _bc_multi )) && _bc_kind=t
  for _bc_j in "${!_bc_key[@]}"; do
    _st_add "$_bc_kind" "${_bc_lbl[$_bc_j]}" "${_bc_on[$_bc_j]}" "" "${_bc_key[$_bc_j]}"
  done
  (( _bc_multi )) && _st_add a "Done" 0 "" "@done"
  return 0
}

# the answer for row i (shares _bvk_menu's locals)
_bc_hit() {
  local _bc_j="$1"
  if (( _bc_multi )); then
    if [ "${_bc_on[$_bc_j]}" = 1 ]; then _bc_on[$_bc_j]=0; else _bc_on[$_bc_j]=1; fi
  else
    _bc_pick="${_bc_key[$_bc_j]}"; _bc_text="${_bc_lbl[$_bc_j]}"; _st_back=1
  fi
}

_bc_index() {   # key or alt key ($1, lower case) -> _bc_ix, or return 1
  local _bc_j
  for _bc_j in "${!_bc_key[@]}"; do
    case " ${_bc_alt[$_bc_j]} " in *" $1 "*) _bc_ix=$_bc_j; return 0 ;; esac
  done
  return 1
}

# a row was activated by Enter / Space / a double tap (act_fn of _st_run)
_bc_act() {
  local _bc_kk="${_st_tag[$1]}"
  if [ "$_bc_kk" = "@done" ]; then _bc_done=1; _st_back=1; return 0; fi
  _bc_index "${_bc_kk,,}" && _bc_hit "$_bc_ix"
  return 0
}

# u / q: leave the way every prompt of the app leaves (the command layer cancels the whole flow); shares _bvk_menu's locals
_bc_leave() {
  local _bc_t="$1" _bc_st=0
  _bc_aborted=1; _st_back=1
  if declare -F _cm_on >/dev/null 2>&1 && _cm_on && declare -F _cm_gate_dispatch >/dev/null 2>&1; then
    _st_wipe; _st_tty_cooked
    declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
    _cm_gate_dispatch "$_bc_t"; _bc_st=$?
    _st_tty_raw
    case "$_bc_st" in
      3) _bc_aborted=0; _st_back=0 ;;      # a command ran and returned: show the box again
    esac
  fi
  return 0
}

# typed text + Enter (cmd_fn of _st_run: return 0 = handled)
_bc_cmd() {
  local _bc_t="$1"
  if [ -z "$_bc_t" ]; then
    (( cur >= 0 )) && return 1                       # Enter on a highlighted row: the engine activates it
    if [ -n "$_bc_def" ] && _bc_index "$_bc_def"; then _bc_hit "$_bc_ix"; fi
    return 0                                         # nothing highlighted, no default: stay on the box
  fi
  [[ "$_bc_t" =~ ^[0-9]+$ ]] && return 1             # a row number: the engine
  if _bc_index "$_bc_t"; then _bc_hit "$_bc_ix"; return 0; fi
  case "$_bc_t" in
    d|done) (( _bc_multi )) && { _bc_done=1; _st_back=1; } ;;
    u|q)    _bc_leave "$_bc_t" ;;
  esac
  return 0                                           # anything else is not an answer: cleared
}

# split a long question into rows no wider than $2; fills _bc_q
_bc_wrap() {
  local _bc_text_in="$1" _bc_w="$2" _bc_word _bc_line=""
  _bc_q=()
  for _bc_word in $_bc_text_in; do
    if [ -z "$_bc_line" ]; then _bc_line="$_bc_word"
    elif (( ${#_bc_line} + 1 + ${#_bc_word} <= _bc_w )); then _bc_line+=" $_bc_word"
    else _bc_q+=("$_bc_line"); _bc_line="$_bc_word"; fi
  done
  [ -n "$_bc_line" ] && _bc_q+=("$_bc_line")
  return 0
}

# the plain one-line version of the question (no terminal, or the engine is not loaded)
_bc_plain() {
  local _bc_j _bc_p _bc_a _bc_h _bc_k
  if (( _bc_yn )); then
    _bc_h="y/n"; [ "$_bc_def" = y ] && _bc_h="Y/n"; [ "$_bc_def" = n ] && _bc_h="y/N"
    (( _bc_cancel )) && _bc_h+=", c = cancel"
  else
    _bc_h=""; for _bc_j in "${!_bc_key[@]}"; do _bc_k="${_bc_key[$_bc_j]}"; _bc_h+="${_bc_h:+/}$_bc_k"; done
  fi
  _bc_p="${_bc_question:-$_bc_title} [$_bc_h]: "
  read -e -r -p "$_bc_p" _bc_a || return 1
  [ "${_CM_ABORT:-0}" = 1 ] && return 1
  _bc_a="${_bc_a,,}"
  [ -z "$_bc_a" ] && _bc_a="$_bc_def"
  if _bc_index "$_bc_a"; then _bc_pick="${_bc_key[$_bc_ix]}"; return 0; fi
  # not one of the answers: a yes/no question takes the safe answer (u / back = cancel when there is a Cancel), a menu backs out
  if (( _bc_yn )); then
    _bc_pick="n"
    if (( _bc_cancel )) && { [ "$_bc_a" = u ] || [ "$_bc_a" = back ]; }; then _bc_pick="c"; fi
    return 0
  fi
  return 1
}

_bvk_menu() {
  local _bc_var="$1"; shift
  local _bc_title="" _bc_icon="❓" _bc_question="" _bc_def="" _bc_multi=0 _bc_keys=0 _bc_receipt=1 _bc_yn=0 _bc_cancel=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -t) _bc_title="$2"; shift 2 ;;
      -i) _bc_icon="$2"; shift 2 ;;
      -q) _bc_question="$2"; shift 2 ;;
      -d) _bc_def="${2,,}"; shift 2 ;;
      -k) _bc_keys=1; shift ;;
      -m) _bc_multi=1; shift ;;
      -n) _bc_receipt=0; shift ;;
      --yn) _bc_yn=1; shift ;;
      --cancel) _bc_cancel=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  # every local is _bc_ prefixed: the caller's variable (VAR) can then never be one of ours
  local -a _bc_key=() _bc_alt=() _bc_lbl=() _bc_on=() _bc_q=()
  local _bc_it _bc_ks _bc_k _bc_lab _bc_i _bc_cols _bc_seg _bc_out
  for _bc_it in "$@"; do
    _bc_ks="${_bc_it%%:*}"; _bc_lab="${_bc_it#*:}"
    _bc_k="${_bc_ks%%|*}"
    _bc_key+=("${_bc_k,,}"); _bc_alt+=("${_bc_ks//|/ }"); _bc_lbl+=("$_bc_lab"); _bc_on+=(0)
  done
  for _bc_i in "${!_bc_alt[@]}"; do _bc_alt[$_bc_i]="${_bc_alt[$_bc_i],,}"; done
  local _bc_pick="" _bc_text="" _bc_done=0 _bc_aborted=0 _bc_ix=0
  [ -z "$_bc_title" ] && _bc_title="Select Option"
  # a flow that is being cancelled: every question answers at once (same rule as the read shim)
  if [ "${_CM_ABORT:-0}" = 1 ] && [ -t 0 ] && declare -F _cm_abort_swallow >/dev/null 2>&1 && _cm_abort_swallow; then
    printf -v "$_bc_var" '%s' ""; return 1
  fi

  if ! _bc_can_draw; then
    _bc_plain || { printf -v "$_bc_var" '%s' ""; return 1; }
    printf -v "$_bc_var" '%s' "$_bc_pick"
    return 0
  fi

  # the default row: highlighted at the start, taken by a bare Enter
  if [ -n "$_bc_def" ] && _bc_index "$_bc_def"; then _st_start_num=$(( _bc_ix + 1 )); fi

  # the header is the question when it fits, otherwise a short title and the question above the box
  _bc_cols=${_vp_cols_now:-80}
  [ "${_vp_cols_now:-0}" -gt 0 ] 2>/dev/null || _bc_cols=$(_term_cols 2>/dev/null || echo 80)
  if [ -n "$_bc_question" ]; then
    if [ "$_bc_title" = "Select Option" ] && (( ${#_bc_question} <= _bc_cols - 8 )); then _bc_title="$_bc_question"
    else _bc_wrap "$_bc_question" $(( _bc_cols - 4 )); for _bc_it in "${_bc_q[@]}"; do echo "$_bc_it"; done; fi
  fi

  # the footer: u / q always; the answer keys on a second line when asked for
  local _st_f1_custom="u) Back   q) Close" _st_f2_custom="" _st_icon="$_bc_icon" _st_crumb="" _st_verb="choose"
  if (( _bc_keys )); then
    _bc_seg=""
    for _bc_i in "${!_bc_key[@]}"; do          # the first key and its one-letter twins (c/x); typed words (yes, cancel) work but are not printed
      _bc_ks=""; for _bc_k in ${_bc_alt[$_bc_i]}; do (( ${#_bc_k} == 1 )) && _bc_ks+="${_bc_ks:+/}$_bc_k"; done
      _bc_seg+="${_bc_seg:+   }${_bc_ks:-${_bc_key[$_bc_i]}}) ${_bc_lbl[$_bc_i]}"
    done
    _st_f2_custom="$_bc_seg"
  elif (( _bc_multi )); then _st_f2_custom="Enter or tap toggles, then Done   d) Done"; fi
  local _st_choice=1 _st_radio_follow=0; (( _bc_multi )) || _st_radio_follow=1   # [o] follows the highlight in a one-of-many menu

  # the keys this box prints are ITS answers (the live hint row and the command layer must not read them as commands)
  local -A _CM_LOCAL=()
  for _bc_i in "${!_bc_key[@]}"; do for _bc_k in ${_bc_alt[$_bc_i]}; do _CM_LOCAL["$_bc_k"]="${_bc_lbl[$_bc_i]}"; done; done

  # run it as a sub screen: it wipes itself when it ends; the terminal goes back to normal only if we switched it on
  local _bc_outer=$_st_depth
  _st_depth=$(( _bc_outer + 1 ))
  _st_run "$_bc_title" _bc_build _bc_act "" _bc_cmd
  _st_depth=$_bc_outer
  (( _bc_outer == 0 )) && { _st_tty_cooked; _st_stty=""; }

  if (( _bc_aborted )) || [ "${_CM_ABORT:-0}" = 1 ]; then printf -v "$_bc_var" '%s' ""; return 1; fi
  if (( _bc_multi )); then
    _bc_out=""
    for _bc_i in "${!_bc_key[@]}"; do [ "${_bc_on[$_bc_i]}" = 1 ] && _bc_out+="${_bc_out:+ }${_bc_key[$_bc_i]}"; done
    printf -v "$_bc_var" '%s' "$_bc_out"
    (( _bc_receipt )) && echo "   → ${_bc_out:-none}"
    return 0
  fi
  if [ -z "$_bc_pick" ]; then printf -v "$_bc_var" '%s' ""; return 1; fi
  printf -v "$_bc_var" '%s' "$_bc_pick"
  (( _bc_receipt )) && echo "   → $_bc_text"
  return 0
}

# _bvk_yn VAR "Question" [-d y|n] [-c] [-t Title] [-i Icon]    → VAR = y | n | c
_bvk_yn() {
  local _by_var="$1" _by_q="$2"; shift 2
  local _by_def=n _by_c=0 _by_t="" _by_i="❓"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -d) _by_def="${2,,}"; shift 2 ;;
      -c) _by_c=1; shift ;;
      -t) _by_t="$2"; shift 2 ;;
      -i) _by_i="$2"; shift 2 ;;
      *)  shift ;;
    esac
  done
  local -a _by_items=("y|yes:Yes" "n|no:No")
  (( _by_c )) && _by_items+=("c|x|cancel:Cancel")
  local -a _by_flags=(-q "$_by_q" -i "$_by_i" -d "$_by_def" -k --yn)
  [ -n "$_by_t" ] && _by_flags+=(-t "$_by_t")
  (( _by_c )) && _by_flags+=(--cancel)
  _bvk_menu "$_by_var" "${_by_flags[@]}" "${_by_items[@]}"
}
