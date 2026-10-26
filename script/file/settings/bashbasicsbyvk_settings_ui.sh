declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
# bashbasicsbyvk_settings_ui.sh — one small menu engine for every Settings screen
# ════════════════════════════════════════════════════════════════════════════
#  Styled exactly like the main menu (header · what this screen is · rule · numbered rows · rule ·
#  footer of suggested commands · "Select:" prompt):
#
#     ⚙️ Settings › Display
#
#     How the list of files looks and behaves. Choose a row ...      (the screen's own text, see settings_desc.sh)
#        ─────────────────────────────
#      1) Hidden files        hide ›
#      2) Sort order          A → Z ›
#        ─────────────────────────────
#     u) Back   q) Close settings
#
#     Select:
#
#  Keys   Typing works like the main menu's "Select:" prompt: type a row
#         number, u or q, then press ENTER.
#         ↑ ↓            move (wraps top ↔ bottom) and put that number in the
#                        prompt; Enter then chooses it. Nothing is highlighted
#                        until you move or type a number.
#         space          change the highlighted row (same as Enter on it)
#         u + Enter      back ONE level (settings → main menu from the top)
#         q + Enter      close Settings completely, straight to the main menu
#
#  A screen is just two functions:
#     build_fn            fills the rows from the current settings  (_st_add …)
#     act_fn IDX KEY      reacts to a row  (KEY = toggle | enter | left | right)
#
#  "=" filter  type  =text  to show only the rows (or headings) containing text,
#         live as you type. =text + Enter keeps the filter, then numbers refer to
#         the rows shown. = + Enter (or u) clears it. Partial/Exact follows
#         Settings → Search filter.
#
#  Row kinds   t checkbox [x]/[ ] (many can be on)   r radio [o]/[ ] (one is on)   a action ›   h heading
#  (headings are not numbered)
#  Optional, set by the caller as locals/globals before _st_run (bashbasicsbyvk_choose.sh uses all of them):
#     _st_f1_custom / _st_f2_custom   the two footer lines
#     _st_start_num                   number of the row the highlight starts on (default: none)
#     _st_radio_follow=1              the [o] of a radio row follows the highlight instead of the stored state
#     _st_choice=1                    a choice menu: no =) Filter hint, Enter says "choose" (not "switch")
# ════════════════════════════════════════════════════════════════════════════

declare -ga _st_lbl=() _st_kind=() _st_on=() _st_val=() _st_tag=()
declare -ga _st_num=() _st_nrow=()
_st_cnt=0       # how many numbered (selectable) rows the screen has
_st_quit=0
_st_filter_wide=0   # 1 = the = filter also searches the value column (Timezone screen)
_st_back=0      # a screen sets this to close itself after an action
_st_depth=0     # 1 = top Settings screen, 2+ = sub settings
_st_k=""
_st_d=""
_o=0
_st_stty=""       # saved terminal state while a Settings/Home screen owns the keyboard
_st_tty_owner=0   # depth that switched the terminal to raw mode

# same rule as the main menu
_ST_RULE="   ─────────────────────────────"

_st_reset()  { _st_lbl=(); _st_kind=(); _st_on=(); _st_val=(); _st_tag=(); }
# _st_add KIND LABEL [ON 0|1] [VALUE] [TAG]
_st_add()    { _st_kind+=("$1"); _st_lbl+=("$2"); _st_on+=("${3:-0}"); _st_val+=("${4:-}"); _st_tag+=("${5:-}"); }
_st_eq()     { [ "$1" = "$2" ] && _o=1 || _o=0; }   # sets _o (no subshell)

_st_selectable() { [ "${_st_kind[$1]:-h}" != "h" ]; }

# "=" filter: keep only the rows whose label matches $fq (a local of _st_run).
# Same rule as the file filter: partial = anywhere in the label, exact = label
# starts with it (Settings → Search filter). A heading stays only when at least
# one row under it matches. The arrays are compacted, so every act function
# keeps working with plain row indexes.
_st_filter_rows() {
  [ -n "${fq:-}" ] || return 0
  local q="${fq,,}" i l v keep n=${#_st_lbl[@]} hi=-1 hshown=0 hmatch=0 wide="${_st_filter_wide:-0}" xm="${filter_mode:-partial}"
  # wide (Timezone screen): also search the value column, ignore "_", and always match "contains"
  if [ "$wide" = 1 ]; then xm=partial; q="${q//_/ }"; fi
  local -a k=() L=() V=() O=() T=()
  for (( i=0; i<n; i++ )); do
    if [ "${_st_kind[$i]}" = h ]; then
      hi=$i; hshown=0; hmatch=0
      l="${_st_lbl[$i]}"; l="${l,,}"
      # a matching heading brings all its rows along
      if [ "$xm" = exact ]; then [[ "$l" == "$q"* ]] && hmatch=1
      else [[ "$l" == *"$q"* ]] && hmatch=1; fi
      continue
    fi
    l="${_st_lbl[$i]}"
    if [ "$wide" = 1 ]; then       # "UTC+05:30" → "+05:30" so that  =utc  does not match every zone
      v="${_st_val[$i]}"; v="${v//UTC+/+}"; v="${v//UTC-/-}"; l="$l $v"
    fi
    l="${l,,}"; [ "$wide" = 1 ] && l="${l//_/ }"
    keep=$hmatch
    if (( ! keep )); then
      if [ "$xm" = exact ]; then [[ "$l" == "$q"* ]] && keep=1
      else [[ "$l" == *"$q"* ]] && keep=1; fi
    fi
    (( keep )) || continue
    if (( hi >= 0 && ! hshown )); then
      k+=(h); L+=("${_st_lbl[$hi]}"); O+=(0); V+=(""); T+=(""); hshown=1
    fi
    k+=("${_st_kind[$i]}"); L+=("${_st_lbl[$i]}"); O+=("${_st_on[$i]}"); V+=("${_st_val[$i]}"); T+=("${_st_tag[$i]}")
  done
  _st_kind=("${k[@]}"); _st_lbl=("${L[@]}"); _st_on=("${O[@]}"); _st_val=("${V[@]}"); _st_tag=("${T[@]}")
}

# number the selectable rows 1..N  (_st_num[row] = N, _st_nrow[N] = row)
_st_number() {
  local i k=0
  _st_num=(); _st_nrow=()
  for i in "${!_st_lbl[@]}"; do
    if _st_selectable "$i"; then
      k=$(( k + 1 )); _st_num[$i]=$k; _st_nrow[$k]=$i
    else
      _st_num[$i]=""
    fi
  done
  _st_cnt=$k
}

# move $cur by $1 (+1/-1) to the next selectable row, wrapping top ↔ bottom.
# With nothing highlighted yet (cur=-1): down → first row, up → last row.
# $2 = how many selectable rows to jump (default 1); a page jump stops at the first/last row
# instead of wrapping, exactly like PgUp/PgDn in the main menu.
_st_move() {
  local d="$1" steps="${2:-1}" n=${#_st_lbl[@]} i=$cur t=0 moved=0 last=$cur
  if (( steps > 1 )); then
    (( n == 0 )) && return 1
    i=$cur; (( cur < 0 )) && { if (( d > 0 )); then i=-1; else i=$n; fi; }
    while (( moved < steps )); do
      i=$(( i + d ))
      (( i < 0 || i >= n )) && break
      if _st_selectable "$i"; then last=$i; moved=$(( moved + 1 )); fi
    done
    (( last >= 0 )) || return 1
    cur=$last; return 0
  fi
  (( n == 0 )) && return 1
  if (( cur < 0 )); then
    if (( d > 0 )); then i=-1; else i=$n; fi
  fi
  while (( t <= n )); do
    t=$(( t + 1 ))
    i=$(( i + d ))
    (( i >= n )) && i=0
    (( i < 0 ))  && i=$(( n - 1 ))
    if _st_selectable "$i"; then cur=$i; return 0; fi
  done
  return 1
}

# Raw keyboard (same as the main menu: no echo, no line buffering).  Without this the terminal echoes
# arrow keys that arrive while a screen is redrawing, which shows up as a flash of  ^[[B  /  ^^B.
_st_tty_raw() {
  [ -t 0 ] || return 0
  [ -n "$_st_stty" ] || _st_stty=$(stty -g 2>/dev/null)
  stty -icanon -echo min 1 time 0 2>/dev/null
  _bvk_paste_on
  declare -F _bvk_mouse_on >/dev/null 2>&1 && _bvk_mouse_on; _BVK_LAST_ITEM=""
}
# cooked again (echo on) for anything that asks a question with  read
_st_tty_cooked() {
  _bvk_paste_off
  declare -F _bvk_mouse_off >/dev/null 2>&1 && _bvk_mouse_off
  [ -t 0 ] && [ -n "$_st_stty" ] && stty "$_st_stty" 2>/dev/null
  return 0
}

# read one key → _st_k = up down left right home end pgup pgdn space enter bksp
#                        char (the character is in _st_d) other
#                        eof (input is gone: the tty closed, the SSH link dropped, the pane was killed)
_st_readkey() {
  local c rc rto
  _st_k="other"; _st_d=""
  if [ "${_ST_PEND_ENTER:-0}" = 1 ]; then _ST_PEND_ENTER=0; _st_k=enter; return; fi
  while :; do                                                    # a mouse release / drag is skipped by going round again (no recursion)
    _st_k="other"; _st_d=""
    while :; do
      rto=(); [ "${_BVK_MOUSE_PASS:-0}" = 1 ] && rto=(-t 1)        # the touch was handed back to the terminal: wake up to take it again
      IFS= read -rsn1 "${rto[@]}" c; rc=$?
      (( rc > 128 )) && { _bvk_mouse_rearm; continue; }            # idle: the reports come back once the hand-back time is over
      (( rc == 0 )) || { _st_k=eof; return; }                      # read failed (EOF / closed tty): the caller leaves, it must never type a key for us
      break
    done
    [ "${_BVK_MOUSE_PASS:-0}" = 1 ] && [ "$c" != $'\033' ] && _bvk_mouse_rearm force     # a typed key: the person is back on the keyboard
    case "$c" in
      "")            _st_k=enter ;;
      " ")           _st_k=space ;;
      $'\177'|$'\b') _st_k=bksp ;;
      $'\033')
        if _read_key_seq; then
          if [ "$_esc" = "[200~" ]; then _bvk_paste_bracketed; _st_k=paste; _st_d="$_BVK_PASTE"; return; fi
          if declare -F _bvk_mouse_decode >/dev/null 2>&1 && _bvk_mouse_decode "$_esc"; then
            case "$_MS_ACT" in
              press) _st_k=click; return ;;
              wheelup) _st_k=wheelup; return ;;
              wheeldown) _st_k=wheeldown; return ;;
              *) continue ;;                 # a button release / drag: nothing to do, wait for the next key (no redraw)
            esac
          fi
          _key_name "$_esc"
          case "$_kname" in
            up|down|left|right|home|end|pgup|pgdn) _st_k="$_kname" ;;
            *) _st_k=other ;;
          esac
        fi ;;                           # bare Esc does nothing (like the main menu)
      [[:print:]])   _st_k=char; _st_d="$c" ;;
    esac
    # a paste without the bracketed-paste markers: the bytes already waiting are part of it (see viewport.sh)
    if [ "$_st_k" = char ] || [ "$_st_k" = space ] || [ "$_st_k" = enter ]; then
      if _bvk_paste_burst "${c:-$'\n'}"; then _st_k=paste; _st_d="$_BVK_PASTE"; [ "$_BVK_PASTE_ENTER" = 1 ] && _st_k=pasteenter; fi
    fi
    return
  done
}

# Draw the block in place.  Uses the caller's (_st_run) locals:
#   path_title hint cur top prev buf
# The cursor is left at the end of the "Select:" line (no trailing newline).
_st_draw() {
  [ "${_SL_WANT:-0}" = 1 ] && _sl_ready          # smartload: the wait is over; wipe its bar before this screen is drawn
  local rows cols n=${#_st_lbl[@]} vis i out="" line mark val f1 f2 marks=0 nl=$'\r\033[2K'
  # The block is erased by moving up exactly $prev lines, so it must NEVER be taller than the
  # terminal really is.  _term_rows is a cache that only the main list refreshes; a nested prompt
  # (find results "Action:", cc ...) opens this screen with whatever size was true minutes ago, and on a
  # phone the keyboard / extra-keys row changes it all the time.  A too-tall block makes the cursor-up
  # clamp at the top of the screen and EVERY redraw leaves its first lines behind (the header stacks up
  # once per keypress).  So: re-read the real size when the screen opens and after every WINCH.
  if [ "${_ST_SIZE_STALE:-1}" = 1 ]; then
    declare -F _vp_probe_size >/dev/null 2>&1 && _vp_probe_size
    _ST_SIZE_STALE=0
  fi
  if [ "${_vp_rows_now:-0}" -gt 0 ] 2>/dev/null; then rows=$_vp_rows_now; cols=$_vp_cols_now
  else rows=$(_term_rows); cols=$(_term_cols); fi
  if declare -F _st_desc_prepare >/dev/null 2>&1; then _st_desc_prepare   # the plain-words text of the highlighted row (0 lines when there is none)
  else _ST_DESC_N=0; _ST_DESC_TRUNC=0; _ST_DESC_LN=(); fi                  # settings_desc.sh not loaded (a stand-alone caller): no description, nothing breaks
  vis=$(( rows - 12 - _ST_DESC_N )); (( vis < 3 )) && vis=3; (( vis > n )) && vis=$n
  if (( cur >= 0 )); then
    (( cur < top )) && top=$cur
    (( cur >= top + vis )) && top=$(( cur - vis + 1 ))
  fi
  (( top > n - vis )) && top=$(( n - vis ))
  (( top < 0 )) && top=0

  for (( i=0; i<n; i++ )); do
    case "${_st_kind[$i]}" in t|r) marks=1; break ;; esac
  done

  # footer = suggested commands (same two-step style as the main menu)
  if (( _st_depth > 1 )); then f1="u) Back   q) Close settings"; else f1="u) Up   q) Close"; fi
  [ -n "${_st_f1_custom:-}" ] && f1="$_st_f1_custom"          # cc: its own footer
  f2=""                                                        # second footer line: empty (a blank spacer) unless there is something to say
  if (( _st_cnt == 0 )); then if [ -n "${fq:-}" ]; then f2="No match for =$fq   (= + enter clears)"; else f2="Nothing to choose here"; fi; fi
  if [[ "$hint" == *"←/→"* ]]; then f2="clr) Clear all"; fi
  [ -n "${_st_f2_custom:-}" ] && f2="$_st_f2_custom"           # a choice menu lists its own keys (y) Yes   n) No ...)
  (( _ST_DESC_TRUNC )) && f2="${f2:+$f2   }?) Full text"       # the explanation in the header was cut: ? + Enter reads all of it

  _ST_FTR1="$f1"; _ST_FTR2="$f2"                           # what _st_click needs to find the footer key that was touched

  # move back to the first line of the previous block
  if (( prev > 1 )); then out+=$'\r\033['"$(( prev - 1 ))"$'A'; fi

  out+="$nl"$'\n'                                          # space above
  local hd="$path_title"
  [ -n "${fq:-}" ] && hd="$hd   [filter: =$fq]"
  out+="$nl${_st_icon:-⚙️} ${hd:0:cols-4}"$'\n'                          # header
  out+="$nl"$'\n'                                         # linebreak under the header
  local _dl
  for _dl in "${_ST_DESC_LN[@]}"; do out+="$nl"$'\033[2m'"$_dl"$'\033[0m\n'; done      # what this screen is, in plain words (between the header and the rule)
  if (( top > 0 )); then out+="$nl   ▲ $top more above"$'\n'; else out+="$nl$_ST_RULE"$'\n'; fi

  for (( i=top; i<top+vis; i++ )); do
    val="${_st_val[$i]}"
    if [ "${_st_kind[$i]}" = h ]; then
      line="    ── ${_st_lbl[$i]}"
      line="${line:0:cols-1}"
      out+="$nl"$'\033[2m'"$line"$'\033[0m\n'
      continue
    fi
    mark=""
    if (( marks )); then
      case "${_st_kind[$i]}" in
        t) mark="[ ] "; [ "${_st_on[$i]}" = 1 ] && mark="[x] " ;;      # checkbox: many can be on
        r) mark="[ ] "
           if [ "${_st_radio_follow:-0}" = 1 ] && (( cur >= 0 )); then (( i == cur )) && mark="[o] "      # a choice menu: the mark follows the highlight
           elif [ "${_st_on[$i]}" = 1 ]; then mark="[o] "; fi ;;                                          # radio: only one is on
        *) mark="    " ;;
      esac
    fi
    [ "${_st_kind[$i]}" = a ] && val="${val:+$val }›"
    printf -v line ' %2d) %s%-22s %s' "${_st_num[$i]}" "$mark" "${_st_lbl[$i]}" "$val"
    line="${line:0:cols-1}"
    if (( i == cur )); then
      out+="$nl"$'\033[1;7m'"$line"$'\033[0m\n'
    else
      out+="$nl$line"$'\n'
    fi
  done

  if (( top + vis < n )); then out+="$nl   ▼ $(( n - top - vis )) more below"$'\n'; else out+="$nl$_ST_RULE"$'\n'; fi
  out+="$nl"$'\n'                                         # linebreak above the footer
  out+="$nl${f1:0:cols-1}"$'\n'
  out+="$nl${f2:0:cols-1}"$'\n'                                  # footer 2, or a blank spacer
  _st_hint_text "$buf" "$cols"
  _ST_TAIL=0
  if [ -n "$_ST_HINT" ]; then out+="$nl"$'\033[2m'"$_ST_HINT"$'\033[0m\n'"$nl"$'\n'; _ST_TAIL=2     # the suggestion row + a blank line, only while there is a suggestion
  fi
  _BVK_SCR_RAW="$out"; _BVK_SCR_EXTRA=""; _BVK_SCR_PROMPT="Select:"   # print: the screen without the typed text
  if declare -F _bvk_fit_input >/dev/null 2>&1; then _bvk_fit_input "${_st_msg:+$_st_msg  }Select: " "$buf" "${#buf}"; out+="${nl}${_BVK_FIT_PROMPT}${_BVK_FIT}"$'\033[J'   # the block is redrawn by row count: the Select line must stay ONE row
  else out+="${nl}Select: $buf"$'\033[J'; fi
  builtin printf '\033[?2026h%s\033[?2026l' "$out"
  prev=$(( vis + 9 + _ST_DESC_N + _ST_TAIL ))
}

# The suggestion row of EVERY Settings / Home style screen (what the typed text would do).  Same engine as the main menu's
# row (_cm_hint: command map of the screen that owns this prompt), plus the two things only a list screen knows:
# a typed row number ("Enter -> open <row>") and the = filter.  -> _ST_HINT ("" = nothing to say, the row stays blank)
_ST_HINT=""; _ST_TAIL=0      # _ST_TAIL = rows of the suggestion (hint + blank) under the footer, 0 when there is none
_st_hint_text() {   # $1 typed text  $2 columns
  local b="$1" cols="${2:-80}" k
  _ST_HINT=""
  if [[ "$b" == "?" ]]; then
    _ST_HINT="?  →  read the whole explanation of the highlighted setting"
  elif [[ "$b" == =* ]]; then
    _ST_HINT="=  →  filter this list live  (= + Enter clears it)"
  elif [[ "$b" =~ ^[0-9]+$ ]] && (( ${#b} < 9 )); then
    k=$(( 10#$b ))
    if (( k >= 1 && k <= ${_st_cnt:-0} )) && [ -n "${_st_nrow[$k]+x}" ]; then case "${_st_kind[${_st_nrow[$k]}]}" in t|r) if [ "${_st_choice:-0}" = 1 ]; then _ST_HINT="Enter  →  choose  ${_st_lbl[${_st_nrow[$k]}]}"; else _ST_HINT="Enter  →  switch  ${_st_lbl[${_st_nrow[$k]}]}"; fi ;; *) _ST_HINT="Enter  →  open  ${_st_lbl[${_st_nrow[$k]}]}" ;; esac; else _ST_HINT="no row $k here  (1-${_st_cnt:-0})"; fi
  elif declare -F _cm_hint >/dev/null 2>&1; then
    declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
    _cm_hint "$b" menu; _ST_HINT="$_hint_want"
  fi
  (( ${#_ST_HINT} >= cols )) && _ST_HINT="${_ST_HINT:0:cols-2}…"
  return 0
}

# erase the block (cursor ends where the block started)
_st_wipe() {
  (( prev > 1 )) && builtin printf '\r\033[%dA' $(( prev - 1 ))
  builtin printf '\r\033[J'
  prev=0
}

# a click / tap (called from _st_run; shares its locals).  The block is  prev = vis + 9 + _ST_DESC_N + _ST_TAIL  rows, the cursor is on its last row (Select:):
#   rows from the top: blank · title · blank · description (_ST_DESC_N rows, the last one blank) · ▲/rule · vis list rows · ▼/rule · blank · footer 1 · footer 2 · [hint · blank: _ST_TAIL=2] · Select
# click a row = highlight it and type its number · double click = and open / switch it · ▲ / ▼ = page.  _ST_CLICK_ACT=1: a row was opened.
# click the path in the title ("Settings › Display": the part before the last ›) = go back to that screen (_st_crumb_tap), one tap like the file list's nav path.
_ST_CLICK_ACT=0
_st_click() {
  _ST_CLICK_ACT=0
  (( prev > 9 + _ST_DESC_N + _ST_TAIL )) || return 0
  _bvk_mouse_prow || return 0
  local vis=$(( prev - 9 - _ST_DESC_N - _ST_TAIL )) rel i d=$(( _BVK_CROW - _MS_Y )) t=$_ST_TAIL
  rel=$(( _MS_Y - ( _BVK_CROW - vis - 4 - t ) ))     # 0 = the first list row on screen
  if (( d == 0 )); then _BVK_LAST_ITEM=""; _bvk_mouse_pass "$_BVK_PASS_TAP_MS"      # the Select: row: the next tap opens the keyboard
  elif (( d == prev - 2 )); then _BVK_LAST_ITEM=""; _st_crumb_tap                    # the title row: a part of the path
  elif (( d == 1 + t || d == 2 + t )); then                    # footer 2 / footer 1: a key there needs a DOUBLE tap (it is typed and Enter pressed)
    if _bvk_mouse_cell_key "$( (( d == 2 + t )) && builtin printf '%s' "$_ST_FTR1" || builtin printf '%s' "$_ST_FTR2" )"; then
      _bvk_mouse_ftr_tap "$_MS_FKEY"
      case "$_MS_FACT" in
        run)  buf="$_MS_FTEXT"; navbuf=0; _ST_PEND_ENTER=1; _ST_CLICK_ACT=1 ;;
        type) buf="$_MS_FTEXT"; navbuf=0 ;;
      esac
    else _BVK_LAST_ITEM=""; fi
  elif (( rel >= 0 && rel < vis )); then
    i=$(( top + rel ))
    _st_selectable "$i" || return 0
    cur=$i; _st_navbuf
    if _bvk_mouse_dbl "st:$i"; then
      _lt_enter "click" "${_st_lbl[$i]}"; buf=""; navbuf=0; _ST_CLICK_ACT=1; _st_activate
    fi
  elif (( rel == -1 && top > 0 )); then _BVK_LAST_ITEM=""; _st_move -1 "$page"; _st_navbuf
  elif (( rel == vis && top + vis < ${#_st_lbl[@]} )); then _BVK_LAST_ITEM=""; _st_move 1 "$page"; _st_navbuf
  fi
  return 0
}

# A tap on the path in the title row ("⚙️ Settings › Display").  A part before the last › takes you back to that screen: the screens
# above this one close themselves (_ST_JUMP_DEPTH, checked at the top of every _st_run loop) until the depth of the tapped part is reached.
# Only the Settings path: a screen with its own crumb (Pending ...) or none (cc) is left alone.  Runs inside _st_click (_MS_X = the column).
_ST_JUMP_DEPTH=0
_st_crumb_tap() {
  [ "${_st_crumb-Settings}" = Settings ] && [[ "$path_title" == "Settings › "* ]] || return 0
  declare -F _bvk_dispw >/dev/null 2>&1 || return 0
  local c=$(( _MS_X - 1 )) off w
  _bvk_dispw "${_st_icon:-⚙️} "; off=$_BVK_W                 # the icon and its space come first
  _bvk_dispw "Settings"; w=$_BVK_W
  # the first part owns its text and the " › " after it (a fingertip is wider than one cell); the last part is where you already are
  if (( c >= off && c < off + w + 3 )); then _ST_JUMP_DEPTH=1; _st_back=1; fi
  return 0
}

# the wheel (called from _st_run; shares its locals).  Over the screen above the header / below the prompt, or with the highlight already
# on the first / last row, the touch goes back to the terminal so it can scroll (see _bvk_mouse_pass).   $1 = -1 up · 1 down
_st_wheel() {
  _bvk_mouse_wheel_outside "$prev" 0 && return 0
  local before="$cur"
  _st_move "$1" "${_BVK_WHEEL_STEP:-3}"
  _st_navbuf
  [ "$cur" = "$before" ] && _bvk_mouse_pass
  return 0
}

# do what the highlighted row says (called from _st_run; shares its locals)
_st_activate() {
  case "${_st_kind[$cur]}" in
    t|r) "$act" "$cur" toggle ;;
    a)
      # actions may ask questions / open a sub-screen: wipe the block first
      _st_wipe
      _st_tty_cooked
      "$act" "$cur" enter
      _st_tty_raw ;;
  esac
}

# The highlight was moved by an arrow, the wheel or a tap: the line shows its number so that Enter chooses it, but that number is only an echo
# (navbuf=1), not typing: the next typed character REPLACES it (Down, then 5 is row 5, not 15; Down, then h is h, not 3h).  Locals of _st_run.
_st_navbuf() {
  typed=0
  (( cur >= 0 )) && { buf="${_st_num[$cur]}"; navbuf=1; }
  return 0
}

# while a row number is being typed, highlight that row (live feedback).  Same rule as the main menu (_hl_typed_clear):
#   a number that names no row (0, 15 of 12)  -> nothing is highlighted, so Space / Enter cannot act on a stale row
#   the typed number erased (backspace)       -> the highlight typing put there goes; one moved with the arrows stays
# typed = the row number typing highlighted (a local of _st_run).
_st_follow() {
  local k
  if [ -z "$buf" ]; then
    (( typed > 0 )) && [ "$cur" = "${_st_nrow[$typed]:-x}" ] && cur=-1
    typed=0; return 0
  fi
  [[ "$buf" =~ ^[0-9]+$ ]] || return 0
  if (( ${#buf} > 9 )); then k=0; else k=$(( 10#$buf )); fi        # nine digits at most: a longer run would wrap around in bash arithmetic
  if (( k >= 1 && k <= _st_cnt )); then cur=${_st_nrow[$k]}; typed=$k
  else cur=-1; typed=0; fi
  return 0
}

# What a typed word does on a list screen (Settings, Home, Pending ...).  It asks the SAME resolver as the hint row above
# (_cm_resolve on the map that owns this screen), so the hint row, cc and Enter can never disagree:
#   run   -> the main command runs here (h s i -h -auth disk ram health lang clear sast ...), the screen redraws below its output
#   block -> a one-line note, nothing runs
# returns 0 = consumed · 1 = not a command here (a number, u, q, plain text, a key only the screen's own cmd_fn knows): the caller goes on.
# Runs inside _st_run: it uses its locals (prev buf cur) the same way the print / loadtime branch does.
_st_cm_gate() {   # $1 = typed text, lower case
  local t="$1"
  [ -n "$t" ] || return 1
  [[ "$t" =~ ^[0-9]+$ ]] && return 1
  case "$t" in u|q|=*) return 1 ;; esac
  [ "${_CC_OPEN:-0}" = 1 ] && return 1                       # the cc list itself: a typed word there is its filter, not a command
  declare -F _cm_resolve >/dev/null 2>&1 && declare -F _cm_on >/dev/null 2>&1 || return 1
  _cm_on || return 1
  [ "${_CM_BOOTED:-0}" = 1 ] || _cm_boot
  declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
  _cm_table_build "$_CM_MAP"
  _cm_resolve menu "$t"
  case "$_CM_ACT" in
    run)   _st_wipe; _st_tty_cooked
           _cm_run_main "$t" menu
           _st_tty_raw
           [ "${_BVK_TO_MAIN:-0}" = 1 ] && _st_quit=1        # q on a screen we opened: close up to the main loop, like the menus do
           return 0 ;;
    block) _st_msg="❌ $t is not available here"; return 0 ;;
    back)  _st_back=1; return 0 ;;
  esac
  return 1
}

# _st_run "Title" build_fn act_fn ["legacy hint"] [cmd_fn]
#   cmd_fn BUF — optional: gets typed text before the number/command rules; return 0 = handled
_st_run() {
  local title="$1" build="$2" act="$3" hint="${4:-}" cmdfn="${5:-}"
  local cur=-1 top=0 prev=0 n buf="" num path_title fq="" need=1 page="${_vp_page_step:-10}" navbuf=0 typed=0
  local parent_title="${_st_title_now:-}"
  _st_depth=$(( _st_depth + 1 ))
  # a sub screen shows its way in ("Settings › Sort order"); _st_crumb="" drops the prefix (cc)
  if (( _st_depth > 1 )) && [ -n "${_st_crumb-Settings}" ]; then path_title="${_st_crumb-Settings} › $title"; else path_title="$title"; fi
  _st_title_now="$path_title"
  _st_quit=0
  _st_tty_raw
  # terminal resized while this screen is open (keyboard, extra keys, rotation): re-measure on the next draw.
  # Whatever WINCH trap the caller had (_multi_prompt_loop has one) is put back when we leave.
  local _st_old_winch; _st_old_winch=$(trap -p WINCH)
  _ST_SIZE_STALE=1
  trap '_ST_SIZE_STALE=1' WINCH

  while :; do
    # rows are rebuilt only when something changed (a choice, a filter edit) — never for plain
    # ↑ ↓ PgUp PgDn Home End, which only move the highlight (this is what made long lists crawl)
    if (( need )); then
      _lt_b "settings: build the rows ($title)"
      "$build"
      _st_filter_rows
      _st_number
      _lt_e
      need=0
    fi
    if (( _ST_JUMP_DEPTH > 0 )); then                 # a tap on the path of a screen below: close every screen above the one that was tapped
      (( _st_depth > _ST_JUMP_DEPTH )) && break
      _ST_JUMP_DEPTH=0
    fi
    n=${#_st_lbl[@]}
    if [ -n "${_st_start_num:-}" ]; then      # a choice menu starts on its default row
      [ -n "${_st_nrow[$_st_start_num]+x}" ] && cur=${_st_nrow[$_st_start_num]}
      _st_start_num=""
    fi
    (( cur >= n )) && cur=$(( n - 1 ))
    (( cur < 0 && n == 0 )) && cur=-1
    _lt_b "settings: draw the screen"
    _st_draw
    _lt_e
    _lt_ready settings "$path_title"
    _st_readkey
    _st_msg=""                                   # the "too large" note lasts until the next key
    need=1
    case "$_st_k" in
      eof)   _st_quit=1 ;;                         # the input is gone (tty closed, SSH drop, pane killed): leave, never loop on it
      up)    need=0; _st_move -1; _st_navbuf ;;
      down)  need=0; _st_move 1;  _st_navbuf ;;
      pgup)  need=0; _st_move -1 "$page"; _st_navbuf ;;   # ±10 like the main menu
      pgdn)  need=0; _st_move 1 "$page";  _st_navbuf ;;
      click)     need=0; _st_click; (( _ST_CLICK_ACT )) && need=1 ;;
      wheelup)   need=0; _st_wheel -1 ;;
      wheeldown) need=0; _st_wheel 1 ;;
      home)  need=0; cur=-1; _st_move 1;  _st_navbuf ;;
      end)   need=0; cur=-1; _st_move -1; _st_navbuf ;;
      bksp)
        navbuf=0; buf="${buf%?}"
        if [[ "$buf" == =* ]]; then fq="${buf:1}"; cur=-1; top=0
        else _st_follow; need=0; fi ;;
      char)
        (( navbuf )) && [ "$_st_d" != "?" ] && { buf=""; navbuf=0; }        # the number an arrow put on the line is replaced by what is typed
        if (( ${#buf} >= ${_BVK_MAX_INPUT:-512} )); then _st_msg="[too large: max ${_BVK_MAX_INPUT:-512}]"
        elif [ -z "$buf" ] && [ "$_st_d" = "=" ]; then buf="="; fq=""; cur=-1; top=0
        elif [ "$_st_d" = "?" ] && [[ "$buf" =~ ^[0-9]*$ ]]; then          # ?  = read the whole explanation of the highlighted row (no Enter needed)
          _st_wipe; _st_tty_cooked; declare -F _st_desc_show >/dev/null 2>&1 && _st_desc_show; _st_tty_raw
        elif [[ "$buf" == =* ]]; then buf+="$_st_d"; fq="${buf:1}"; cur=-1; top=0
        else buf+="$_st_d"; _st_follow; need=0; fi ;;
      paste|pasteenter)
        # a pasted text goes into the row in ONE step; it is accepted only by the user's own Enter
        (( navbuf )) && { buf=""; navbuf=0; }
        if (( ${#buf} + ${#_st_d} > ${_BVK_MAX_INPUT:-512} )); then _st_msg="[too large: $(( ${#buf} + ${#_st_d} )) chars, max ${_BVK_MAX_INPUT:-512}, not accepted]"; _st_d=""; fi
        _st_d="${_st_d//$'\n'/ }"                                   # this row is one line: line breaks become spaces
        if [ -z "$_st_d" ]; then _st_k=paste           # refused (too large) or empty: its Enter must not run what was typed before it
        elif [ -z "$buf" ] && [ "${_st_d:0:1}" = "=" ]; then buf="$_st_d"; fq="${buf:1}"; cur=-1; top=0
        elif [[ "$buf" == =* ]]; then buf+="$_st_d"; fq="${buf:1}"; cur=-1; top=0
        else buf+="$_st_d"; _st_follow; need=0; fi
        [ "$_st_k" = pasteenter ] && _ST_PEND_ENTER=1 ;;    # typed text + Enter that arrived together: the Enter comes next
      left|right)
        (( cur >= 0 )) && _st_selectable "$cur" && { _lt_enter "$_st_k" "${_st_lbl[$cur]}"; "$act" "$cur" "$_st_k"; }
        ;;
      space)
        navbuf=0; typed=0
        if [[ "$buf" == =* ]]; then buf+=" "; fq="${buf:1}"; cur=-1; top=0     # a space inside =text is part of the search
        elif [ -n "$buf" ] && [[ "$buf" == [a-z]* ]]; then buf+=" "            # a command being typed (loadtime 2)
        elif (( cur >= 0 )) && _st_selectable "$cur"; then buf=""; _lt_enter "space" "${_st_lbl[$cur]}"; _st_activate; fi
        ;;
      enter)
        navbuf=0; typed=0
        if [[ "$buf" == =* ]]; then
          # =text + Enter keeps the filter · = + Enter clears it
          [ "$buf" = "=" ] && fq=""
          buf=""; cur=-1; top=0
          continue
        fi
        # print / loadtime work on every settings screen: wipe the block, run, draw it again
        case "${buf,,}" in
          "?")
            # the whole explanation of the highlighted setting (or of the screen)
            _st_wipe; _st_tty_cooked
            declare -F _st_desc_show >/dev/null 2>&1 && _st_desc_show
            _st_tty_raw; buf=""; continue ;;
          print|loadtime|loadtime\ *)
            _st_wipe; _st_tty_cooked
            bvk_main_exec "${buf,,}"
            _st_tty_raw; buf=""; cur=-1; continue ;;
          cc)
            # cheat codes: the list of what this screen accepts; the pick is typed into the line below
            [ "${_CC_OPEN:-0}" = 1 ] && { buf=""; continue; }
            _st_wipe; _st_tty_cooked
            _CC_CTX=st bvk_main_exec cc
            _st_tty_raw
            buf="${_CC_PREFILL:-}"; _CC_PREFILL=""; fq=""
            [[ "$buf" == =* ]] && fq="${buf:1}"
            cur=-1; top=0; continue ;;
        esac
        _ltl=""; (( cur >= 0 )) && _ltl="${_st_lbl[$cur]}"
        _lt_enter "${buf:-enter}" "$_ltl"
        if [ -n "$cmdfn" ] && "$cmdfn" "${buf,,}"; then
          buf=""
          (( _st_quit )) && break
          (( _st_back )) && { _st_back=0; break; }          # the handler finished this screen (a choice was made)
          continue
        fi
        if _st_cm_gate "${buf,,}"; then                    # a map command (run / refused): the same answer the hint row gave
          buf=""; cur=-1
          (( _st_quit )) && break
          (( _st_back )) && { _st_back=0; break; }
          continue
        fi
        case "${buf,,}" in
          u) if [ -n "$fq" ]; then fq=""; buf=""; cur=-1; top=0; continue; fi
             break ;;                       # buf keeps "u" so the prompt line can stay
          q) _st_quit=1; break ;;
          "") (( cur >= 0 )) && _st_selectable "$cur" && _st_activate ;;
          *[!0-9]*) buf="" ;;                         # not a command: clear it
          *)
            num=$(( 10#$buf )); buf=""
            if (( num >= 1 && num <= _st_cnt )); then
              cur=${_st_nrow[$num]}
              _st_activate
            fi ;;
        esac
        ;;
    esac
    (( _st_quit )) && break
    (( _st_back )) && { _st_back=0; break; }
  done

  # leave tidy: a sub screen erases itself so its parent redraws in the same
  # place; the top screen stays on screen with  Select: u  /  Select: q  as typed.
  if (( prev > 0 )); then
    if (( _st_depth > 1 )); then _st_wipe; else
      if declare -F _bvk_fit_input >/dev/null 2>&1; then _bvk_fit_input "Select: " "$buf" "${#buf}"; builtin printf '\r\033[2K%s%s' "$_BVK_FIT_PROMPT" "$_BVK_FIT"
      else builtin printf '\r\033[2KSelect: %s' "$buf"; fi
    fi
  fi
  if [ -n "$_st_old_winch" ]; then eval "$_st_old_winch"; else trap - WINCH; fi
  _ST_SIZE_STALE=1                      # the caller's size may differ again by the time we are back in it
  _st_depth=$(( _st_depth - 1 ))
  _st_title_now="$parent_title"
  if (( _st_depth == 0 )); then _st_tty_cooked; _st_stty=""; fi
  return 0
}

# ── small helpers used by the screens ────────────────────────────────────────

# _st_ask "What to type" [current]  → _st_in.  Returns 1 on u / q / blank.
_st_ask() {
  local p="$1" cur="${2:-}"
  [ -n "$cur" ] && p="$p [now: $cur]"
  read -e -r -p "  $p  (u = back): " _st_in
  _st_in="${_st_in%$'\r'}"
  case "${_st_in,,}" in
    u|"") return 1 ;;
    q) _st_quit=1; return 1 ;;
  esac
  return 0
}

# short one-line note under the menu (printed once, scrolls away naturally)
_st_note() { [ "${_SL_WANT:-0}" = 1 ] && _sl_pulse; builtin printf '  %s\n' "$1"; }
