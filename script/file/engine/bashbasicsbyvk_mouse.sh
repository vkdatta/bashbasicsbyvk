# Mouse and touch input for the numbered lists  (Settings → Display → Mouse / touch).
#
#   click / tap an item   → the item is selected: its number is typed into the prompt, the row is highlighted.  Enter opens it.
#   double click / tap    → the same, and Enter is pressed for you.
#   click / tap ▲ / ▼     → page up / page down.
#   wheel / swipe         → scroll the list (3 items per step).
#   click / tap the status row  (py | ⏰ 0 | 📣 0)  → runs  lang / nf / pn  (first / second / third field)
#   click / tap a tab name (sw, fx, -u, .r, cs, rbam ...)  → that tab (a tab bar is found by the labels its screen registered)
#   click / tap a folder name in the  nav path:  → browse that folder (the shell's  cd path  is never touched)
#   DOUBLE click / tap a footer key  (u) Up   q) Quit   h) Home ...)  → that key is typed and Enter pressed for you.  A single tap does
#        nothing: footers sit next to the prompt and are the easiest thing to touch by accident.  A key with a placeholder
#        (x-N, r-N ...) only has its prefix typed (x-), never Enter.
#   wheel / swipe at the END of a list, or started OUTSIDE the menu block (on the screen above its header / below its prompt)
#        → handed back to the terminal, so its own scrollback scrolls (see _bvk_mouse_pass).
#   tap on the Select: prompt row → handed back to the terminal for a moment, so the NEXT tap opens the soft keyboard
#        (a terminal never opens the keyboard on a tap while mouse reports are on; the tap that is reported is the one that is lost).
# Wired into every loop that shows a numbered list: the file list and the menus built on it (fx, sw, api, ...), Settings / Home /
# cc (_st_run), every  read -p  menu (_sm_run: the file menu, find, create, ...) and the Item numbers picker.
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
_BVK_NAV_TARGET=""           # the folder a touched nav-path name asks for (read by the main loop on  __navpath__ )
_BVK_DBL_MS="${BVK_DBLCLICK_MS:-500}"        # two clicks on the same item within this many ms = double click (500: taps are slower than clicks)
_BVK_WHEEL_STEP=3
_BVK_MOUSE_PASS=0            # 1 = reports are switched off on purpose for a while, the terminal gets scroll / tap back (_bvk_mouse_pass)
_BVK_PASS_UNTIL=0
_BVK_PASS_SCROLL_MS=1500     # how long after the last wheel event that was handed back the reports come on again
_BVK_PASS_TAP_MS=8000        # ... after a tap on the prompt row (long enough to tap again and get the keyboard)

_bvk_mouse_enabled() {
  [ "${mouse_mode:-on}" = on ] && [ "${BVK_MOUSE:-1}" != 0 ] && [ "$_BVK_MOUSE_BROKEN" = 0 ] || return 1
  [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != dumb ]
}
_bvk_mouse_on() {
  _bvk_mouse_enabled || return 0
  builtin printf '\033[?1000h\033[?1006h'; _BVK_MOUSE_ON=1; _BVK_MOUSE_PASS=0
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
  [[ "$s" =~ $re ]] || { _bvk_mouse_rearm force; return 1; }      # an arrow / Home / ... : the person is on the keyboard again
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
  (( d <= 0 && d > - ${_BLK_ROWS:-1} )) && { _MS_KIND=prompt; return 0; }       # the Select: row itself (a long text spans several rows)
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

# Tabs.  A screen with tabs registers the labels exactly as its tab bar prints them (once, when its file is loaded):
#     _bvk_tabs_register "📌 Bookmarks" "🕐 Recents" "⭐ Favourites"
# A header line that holds all the labels of a set is that screen's tab bar; the bracketed label is the current tab.  A tap on
# another label asks for (target - current) ←/→ steps: _BVK_TAB_STEPS, consumed one per turn by the read loop as if the key was pressed.
_BVK_TAB_SETS=()
_BVK_TAB_STEPS=0
_BVK_TAB_SCREEN=""
_MS_TABDELTA=0
_bvk_tabs_register() { local IFS='|'; _BVK_TAB_SETS+=("$*"); }

# _bvk_mouse_tab_hit LINE  (plain header line; the click column is _MS_X)  -> 0 and _MS_TABDELTA (≠ 0) when a tab other than the current one was hit
_bvk_mouse_tab_hit() {
  local line="$1" c=$(( _MS_X - 1 )) set lab i n cur=-1 hit=-1
  local -a labs st en
  for set in "${_BVK_TAB_SETS[@]}"; do
    IFS='|' read -ra labs <<< "$set"; n=${#labs[@]}
    st=(); en=(); local ok=1
    for (( i=0; i<n; i++ )); do
      lab="${labs[i]}"
      [[ "$line" == *"$lab"* ]] || { ok=0; break; }
      _bvk_dispw "${line%%"$lab"*}"; st[i]=$_BVK_W
      _bvk_dispw "$lab"; en[i]=$(( st[i] + _BVK_W ))
      [[ "$line" == *"[$lab]"* ]] && cur=$i
    done
    (( ok && cur >= 0 )) || continue
    # the bar runs from one cell before the first label (its bracket) to one after the last; between two labels the middle of the gap splits
    (( c >= st[0] - 1 && c <= en[n-1] )) || return 1
    hit=$(( n - 1 ))
    for (( i=0; i<n-1; i++ )); do (( c < (en[i] + st[i+1]) / 2 )) && { hit=$i; break; }; done
    (( hit != cur )) || return 1
    _MS_TABDELTA=$(( hit - cur )); return 0
  done
  return 1
}

# _bvk_mouse_dbl KEY   0 = this click is the second of a double click on the same KEY (and the memory is cleared), 1 = first click
_bvk_mouse_dbl() {
  _bvk_now_ms
  if [ "$1" = "$_BVK_LAST_ITEM" ] && (( _BVK_MS - _BVK_LAST_MS <= _BVK_DBL_MS )); then _BVK_LAST_ITEM=""; return 0; fi
  _BVK_LAST_ITEM="$1"; _BVK_LAST_MS=$_BVK_MS
  return 1
}

# _bvk_mouse_prow -> _BVK_CROW (the prompt's row).  The cursor sits on the prompt row, so one cursor-position query answers it.
# A terminal that does not answer: reports are switched off for good (the keyboard keeps working).
_bvk_mouse_prow() {
  _bvk_cursor_row && return 0
  _BVK_MOUSE_BROKEN=1; _bvk_mouse_off
  return 1
}

# scroll the list window by N rows without touching the selection (cursor must be on the prompt's first row)
_bvk_mouse_scroll() {
  local s=$(( _vp_start + $1 )) mx=$(( _vp_R - _vp_page + 1 ))
  (( mx < 1 )) && mx=1; (( s > mx )) && s=$mx; (( s < 1 )) && s=1
  (( s == _vp_start )) && return 0
  _vp_start=$s; _vp_rerender
  return 0
}

# Handing the touch back to the terminal.  While reports are on, the terminal gives US every wheel event and every tap: it can no longer
# scroll its own scrollback (the screen above / below the menu) and a tap no longer opens the soft keyboard.  So reports go off on purpose:
#   _bvk_mouse_pass [MS]   off now, and back on after MS ms without input (the read loops call _bvk_mouse_rearm from their idle tick and
#                          with "force" on every key, because a typed key means the person is back at the list).
# Reports that were already on their way are decoded as "ignore" while the feature is off, so none is ever typed into the prompt.
_bvk_mouse_pass() {
  (( _BVK_MOUSE_ON )) || return 0
  _bvk_mouse_off; _BVK_MOUSE_PASS=1
  _bvk_now_ms; _BVK_PASS_UNTIL=$(( _BVK_MS + ${1:-$_BVK_PASS_SCROLL_MS} ))
  return 0
}
_bvk_mouse_rearm() {    # [force]
  (( _BVK_MOUSE_PASS )) || return 0
  if [ "${1:-}" != force ]; then _bvk_now_ms; (( _BVK_MS < _BVK_PASS_UNTIL )) && return 0; fi
  _bvk_mouse_on
  return 0
}

# _bvk_mouse_wheel_outside [BLOCK_ROWS] [EXTRA_ROWS_BELOW_PROMPT]
#   For a wheel event at _MS_Y: 0 = it was NOT over the menu block (on the screen above its header, or below its prompt), and the
#   touch has just been handed back (_bvk_mouse_pass); the caller then does nothing else.  1 = over the block: the caller scrolls the list.
#   The cursor must be on the prompt's first row (the callers _bvk_blk_park first).
_bvk_mouse_wheel_outside() {
  _bvk_mouse_prow || return 1
  local h=${1:-${_blk_h:-0}} below=${2:-$(( ${_BLK_ROWS:-1} - 1 ))} top
  (( h > 0 )) || return 1
  top=$(( _BVK_CROW - h + 1 ))
  if (( _MS_Y < top || _MS_Y > _BVK_CROW + below )); then _bvk_mouse_pass; return 0; fi
  return 1
}

# wheel over a list that scrolls as a window (the picker, multi / command menus): park, hand back when the wheel is outside the block,
# scroll, and hand back when the window did not move (already at the first / last row).   $1 = -1 up · 1 down
_bvk_mouse_wheel_window() {
  _bvk_blk_park
  _bvk_mouse_wheel_outside && return 0
  local before=$_vp_start
  _bvk_mouse_scroll $(( $1 * _BVK_WHEEL_STEP ))
  [ "$_vp_start" = "$before" ] && _bvk_mouse_pass
  return 0
}

# Footer rows.  A footer line holds cells  "key) Label"  split by three spaces (see _mc_footer).  The footer lines sit between the
# ▼/rule line and the suggestion row:  prompt (d=0) · hint row · LAST footer line (d=hint+1) ... FIRST footer line (d=hint+shown).
#   _bvk_mouse_ftr_hit CLICKED_ROW PROMPT_ROW  -> 0 and _MS_FKEY = the key of the cell that was touched (the text before the ")"), else 1
_bvk_mouse_ftr_hit() {
  _MS_FKEY=""
  local d=$(( $2 - $1 )) h=${_vp_hint_row:-0} f=${_vp_ftr_show:-0}
  (( f > 0 && d > h && d <= h + f )) || return 1
  local k=$(( f - (d - h) ))
  _vp_strip_ansi "${_vp_ftr_out[k]:-}"
  _bvk_mouse_cell_key "$_vp_plain"
}

# _bvk_mouse_cell_key PLAIN_LINE  -> 0 and _MS_FKEY when the click column (_MS_X) is on a  "key) Label"  cell of the line, else 1
_bvk_mouse_cell_key() {
  _MS_FKEY=""
  local rest="$1" cell off=0 w lead re='^([^[:space:])]+)\) ' c=$(( _MS_X - 1 ))
  while [ -n "$rest" ]; do
    lead="${rest%%[![:space:]]*}"; off=$(( off + ${#lead} )); rest="${rest#"$lead"}"        # spaces in front of a cell are no cell
    [ -n "$rest" ] || break
    cell="${rest%%   *}"
    _bvk_dispw "$cell"; w=$_BVK_W
    # a cell owns its text and the gap after it (a fingertip is wider than one cell)
    if (( c >= off && c <= off + w + 2 )); then
      [[ "$cell" =~ $re ]] || return 1
      _MS_FKEY="${BASH_REMATCH[1]}"; return 0
    fi
    off=$(( off + w )); rest="${rest#"$cell"}"
  done
  return 1
}

# _bvk_mouse_ftr_tap  KEY  -> sets _MS_FACT:   run  = a DOUBLE tap on a plain key: type _MS_FTEXT and press Enter
#                                              type = a double tap on a key with a placeholder (x-N): only the prefix (x-) is typed
#                                              none = first tap (remembered), or a key that cannot be typed
_bvk_mouse_ftr_tap() {
  local key="$1" re='^[A-Za-z0-9=.?+-]+$'
  _MS_FACT=none; _MS_FTEXT=""
  [[ "$key" =~ $re ]] || { _BVK_LAST_ITEM=""; return 0; }
  _bvk_mouse_dbl "f:$key" || return 0
  if [[ "$key" == *N* ]]; then
    [ -n "${key%%N*}" ] && { _MS_FACT=type; _MS_FTEXT="${key%%N*}"; }
  else _MS_FACT=run; _MS_FTEXT="$key"; fi
  return 0
}

# _bvk_mouse_other CLICKED_ROW PROMPT_ROW  — the tap landed on no list row and no ▲/▼: a footer key or the prompt row.
#   0 = it was a footer / prompt tap (_MS_FACT / _MS_FTEXT say what to do, see _bvk_mouse_ftr_tap); 1 = something else
_bvk_mouse_other() {
  _MS_FACT=none; _MS_FTEXT=""
  if [ "$_MS_KIND" = prompt ]; then _BVK_LAST_ITEM=""; _bvk_mouse_pass "$_BVK_PASS_TAP_MS"; return 0; fi
  if _bvk_mouse_ftr_hit "$1" "$2"; then _bvk_mouse_ftr_tap "$_MS_FKEY"; return 0; fi
  return 1
}

# Header rows.  The block's top row is (prompt row - _blk_h + 1) and the header lines are its first rows (_vp_hdr_out).
#   _bvk_mouse_hdr_hit CLICKED_ROW PROMPT_ROW   -> returns 0 and sets
#     _MS_HKIND = cmd   _MS_CMD = lang | nf | pn     the status row:  "py | ⏰ 0 | 📣 0"  (first / second / third field)
#     _MS_HKIND = nav   _MS_NAV = /a/b               a folder name of "☁️ nav path: /a/b/c" was touched (c itself = where you are: ignored)
#   returns 1 when the click is on no such field.
_bvk_mouse_hdr_hit() {
  _MS_HKIND=none; _MS_CMD=""; _MS_NAV=""
  local k=$(( $1 - ( $2 - ${_blk_h:-0} + 1 ) )) line c=$(( _MS_X - 1 ))
  (( k >= 0 && k < ${#_vp_hdr_out[@]} )) || return 1
  _vp_strip_ansi "${_vp_hdr_out[k]}"; line="$_vp_plain"

  if _bvk_mouse_tab_hit "$line"; then _MS_HKIND=tab; return 0; fi

  if [[ "$line" == *' | ⏰ '*' | 📣 '* ]]; then
    local f1="${line%% | ⏰ *}" rest="${line#* | ⏰ }" f2 f3 a w2 w3 s2 s3
    f2="⏰ ${rest%% | 📣 *}"; f3="📣 ${rest#* | 📣 }"
    _bvk_dispw "$f1"; a=$_BVK_W; _bvk_dispw "$f2"; w2=$_BVK_W; _bvk_dispw "$f3"; w3=$_BVK_W
    s2=$(( a + 3 )); s3=$(( s2 + w2 + 3 ))
    # each field owns its text plus the first half of the " | " that follows it (a fingertip is wider than one cell)
    if   (( c <= a ));          then _MS_HKIND=cmd; _MS_CMD=lang
    elif (( c <= s2 + w2 ));    then _MS_HKIND=cmd; _MS_CMD=nf
    elif (( c <= s3 + w3 ));    then _MS_HKIND=cmd; _MS_CMD=pn
    fi
    [ "$_MS_HKIND" = cmd ]; return
  fi

  if [[ "$line" == *'nav path: '* ]]; then
    local pre="${line%%nav path: *}nav path: " rest="${line#*nav path: }" off seg acc="" col sw p="${path:-}"
    [ -n "$p" ] && [ "$p" != "/" ] || return 1
    [[ "$rest" == "$p" || "$rest" == "$p "* ]] || return 1          # Google Drive view / something else: not a real path, leave it alone
    _bvk_dispw "$pre"; off=$_BVK_W
    if (( c == off )); then _MS_HKIND=nav; _MS_NAV="/"; return 0; fi    # the leading "/"
    col=$(( off + 1 ))
    local -a segs; IFS='/' read -ra segs <<< "${p#/}"
    local i n=${#segs[@]}
    for (( i=0; i<n; i++ )); do
      seg="${segs[i]}"; acc+="/$seg"
      _bvk_dispw "$seg"; sw=$_BVK_W
      # a name owns its cells and the "/" after it (the last name has none: it is where you already are)
      if (( c >= col && c < col + sw + (i < n - 1 ? 1 : 0) )); then
        (( i < n - 1 )) || return 1
        _MS_HKIND=nav; _MS_NAV="$acc"; return 0
      fi
      col=$(( col + sw + 1 ))
    done
    return 1
  fi
  return 1
}

# the file list itself (not a flow, not an inner screen) is the only place where a header tap may act:
#   0 = a status-row tap may run lang / nf / pn here · nothing else is waiting for an answer
_bvk_mouse_hdr_ok() {
  declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
  [ "${_CM_FLOW:-0}" = 0 ]
}
#   0 = the nav path may be used to browse somewhere else (the main file list only)
_bvk_mouse_nav_ok() {
  case "${_vp_header_fn:-}" in _menu_header_flat|_menu_header_imaginary) ;; *) return 1 ;; esac
  [ "${_sw_in_mode:-0}" != 1 ] && [ "${_fx_in_mode:-0}" != 1 ] && [ "${_GD_ACTIVE:-0}" != 1 ] || return 1
  declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
  [ "${_CM_FLOW:-0}" = 0 ] && [ "${_CM_MAP:-main}" = main ]
}
