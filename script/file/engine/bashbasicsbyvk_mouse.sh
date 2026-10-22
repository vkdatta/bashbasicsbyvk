# Mouse and touch input for the numbered lists  (Settings → Display → Mouse / touch).
#
#   click / tap an item   → the item is selected: its number is typed into the prompt, the row is highlighted.  Enter opens it.
#   double click / tap    → the same, and Enter is pressed for you.
#   click / tap ▲ / ▼     → page up / page down.
#   wheel / swipe         → scroll the list (3 items per step).
#
# A terminal has no real "touch" events: every terminal that supports touch (Termux, Blink, iSH, iTerm2, ...) turns a tap into a
# mouse click when the program asks for mouse reports, so ONE code path serves both.  Mouse reports are asked for with
#   ESC[?1000h  (button press / release)   +   ESC[?1006h  (the SGR format:  ESC[<button;column;row M|m , no 223-column limit)
# and are switched on only while a numbered list waits for a key (_read_choice_raw), and off again before anything else runs
# (a child process, an editor, a plain  read ), so no other screen ever sees them.
#
# Trade-off: while reports are on, the terminal's own text selection needs Shift held (Option on macOS terminals).
# That is why it is a setting.   BVK_MOUSE=0 in the environment switches it off for one run.
#
# Where did the click land?  The list is drawn INLINE (no alternate screen), so its absolute screen row is not known; the cursor
# is always parked on the prompt row, and the app knows how many rows lie between the prompt and each list row (_vp_dist).  One
# cursor-position query (ESC[6n) at click time gives the prompt's row: (prompt row − clicked row) → list row → item number.

_BVK_MOUSE_ON=0
_BVK_MOUSE_BROKEN=0          # the terminal never answered the cursor-position query: reports are switched off for good
_BVK_LAST_ITEM=""            # the item of the previous click and when it happened (double-click detection)
_BVK_LAST_MS=0
_BVK_DBL_MS="${BVK_DBLCLICK_MS:-500}"        # two clicks on the same item within this many ms = double click (500: taps are slower than clicks)
_BVK_WHEEL_STEP=3

_bvk_mouse_enabled() {
  [ "${mouse_mode:-on}" = on ] && [ "${BVK_MOUSE:-1}" != 0 ] && [ "$_BVK_MOUSE_BROKEN" = 0 ] || return 1
  [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]
}
_bvk_mouse_on() {
  _bvk_mouse_enabled || return 0
  builtin printf '\033[?1000h\033[?1006h'; _BVK_MOUSE_ON=1
  return 0
}
_bvk_mouse_off() {
  (( _BVK_MOUSE_ON )) || return 0
  builtin printf '\033[?1006l\033[?1000l'; _BVK_MOUSE_ON=0
  return 0
}

# _bvk_now_ms -> _BVK_MS
_bvk_now_ms() {
  local t
  if [ -n "${EPOCHREALTIME:-}" ]; then
    t="${EPOCHREALTIME/[.,]/}"; _BVK_MS=$(( 10#$t / 1000 )); return 0
  fi
  t=$(date +%s%N 2>/dev/null)
  if [[ "$t" =~ ^[0-9]{16,}$ ]]; then _BVK_MS=$(( 10#$t / 1000000 )); return 0; fi
  builtin printf -v t '%(%s)T' -1; _BVK_MS=$(( 10#$t * 1000 ))     # whole seconds only: a double click then needs the same second
}

# _bvk_mouse_decode SEQ   SEQ is what _read_key_seq returned (without the ESC).
#   returns 1 when it is not a mouse report; else 0 and sets _MS_ACT = press | wheelup | wheeldown | ignore, _MS_X, _MS_Y (1-based)
_bvk_mouse_decode() {
  local s="$1" re='^\[<([0-9]+);([0-9]+);([0-9]+)([Mm])$' b
  _MS_ACT=ignore
  [[ "$s" == '[M'* ]] && return 0                      # the old X10 format (a terminal without SGR): swallowed, never typed into the prompt
  [[ "$s" =~ $re ]] || return 1
  b=$(( 10#${BASH_REMATCH[1]} )); _MS_X=$(( 10#${BASH_REMATCH[2]} )); _MS_Y=$(( 10#${BASH_REMATCH[3]} ))
  [ "${BASH_REMATCH[4]}" = M ] && (( _BVK_MOUSE_ON )) || return 0     # a release, or a stray report while the feature is off: swallowed, not acted on
  if   (( b & 64 )); then
    case $(( b & 3 )) in 0) _MS_ACT=wheelup ;; 1) _MS_ACT=wheeldown ;; esac
  elif (( (b & 35) == 0 )); then _MS_ACT=press        # the left button, not a drag, not wheel
  fi
  return 0
}

# _bvk_cursor_row -> _BVK_CROW   (row of the cursor, 1-based; returns 1 when the terminal does not answer)
_bvk_cursor_row() {
  local r=""
  builtin printf '\033[6n'
  IFS= builtin read -rs -d R -t 0.4 r || return 1
  r="${r##*$'\033'[}"; r="${r%%;*}"
  [[ "$r" =~ ^[0-9]+$ ]] || return 1
  _BVK_CROW=$(( 10#$r ))
}

# _bvk_mouse_hit CLICKED_ROW PROMPT_ROW  -> _MS_KIND = item | pgup | pgdn | none ; _MS_ITEM
# The screen, bottom up:  prompt · hint row · footer lines · ▼/rule line · last list row ... first list row · ▲/rule line.
_bvk_mouse_hit() {
  local d=$(( $2 - $1 )) base r it
  _MS_KIND=none; _MS_ITEM=0
  (( d > 0 )) || return 0
  base=$(( ${_vp_ind:-0} + ${_vp_ftr_show:-0} + ${_vp_hint_row:-0} ))
  r=$(( _vp_end + base + 1 - d ))                       # screen row of the list (inverse of _vp_dist)
  if (( _vp_n > 0 && r >= _vp_start && r <= _vp_end )); then
    it=$r
    if (( ${_vp_gv:-0} )); then
      it="${_gv_row[$((r-1))]:-}"
      [[ "$it" == H* || -z "$it" ]] && return 0         # a group header is not an item
    fi
    _MS_KIND=item; _MS_ITEM=$it; return 0
  fi
  if (( ${_vp_ind:-0} > 0 )); then
    (( _vp_start > 1 && d == _vp_end - _vp_start + base + 2 )) && { _MS_KIND=pgup; return 0; }
    (( _vp_end < _vp_R && d == base )) && { _MS_KIND=pgdn; return 0; }
  fi
  return 0
}
