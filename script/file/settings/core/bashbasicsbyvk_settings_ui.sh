declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
# bashbasicsbyvk_settings_ui.sh — one small menu engine for every Settings screen
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
#     u) Up   q) Quit   h) Home   cc) Cheat codes
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
#              p plain choice row (numbered, no mark; like r in a choice menu)
#              i info row (display only; VALUE = the number shown in front, "" = none)   s rule line (display only)
#  (headings, info rows and rule lines are not numbered, never highlighted, never chosen)
#  Optional, set by the caller as locals/globals before _st_run (bashbasicsbyvk_choose.sh uses all of them):
#     _st_start_num                   number of the row the highlight starts on (default: none)
#     _st_radio_follow=1              the [o] of a radio row follows the highlight instead of the stored state
#     _st_choice=1                    a choice menu: no =) Filter hint, Enter says "choose" (not "switch")
#     _st_tab_labels=("A" "B")  +  _st_tab_cur=0     TABS (cc uses them): a tab bar "[A] B" under the title, ← → (empty line) or a tap switches the
#                                     tab by moving _st_tab_cur; the build function fills only the rows of the current tab. The caller
#                                     registers the labels once with _bvk_tabs_register so the bar is tappable.

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

# tabs (see the header): _st_tab_step DELTA moves the current tab (wraps round)
_st_tab_step() {
  local n=${#_st_tab_labels[@]}
  (( n > 1 )) || return 1
  _st_tab_cur=$(( ( ( _st_tab_cur + $1 ) % n + n ) % n ))
}
# _st_tab_bar_v VAR  the bar as the tabbed menus print it:  "[A] B"
_st_tab_bar_v() {
  local _tb="" _ti
  for (( _ti = 0; _ti < ${#_st_tab_labels[@]}; _ti++ )); do
    if (( _ti == _st_tab_cur )); then _tb+="${_tb:+ }[${_st_tab_labels[_ti]}]"; else _tb+="${_tb:+ }${_st_tab_labels[_ti]}"; fi
  done
  printf -v "$1" '%s' "$_tb"
}

_st_selectable() { case "${_st_kind[$1]:-h}" in h|i|s) return 1 ;; esac; return 0; }   # h heading · i info row · s rule: shown, never numbered or chosen

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
    case "${_st_kind[$i]}" in i|s) k+=("${_st_kind[$i]}"); L+=("${_st_lbl[$i]}"); O+=(0); V+=("${_st_val[$i]}"); T+=(""); continue ;; esac    # display-only rows are not filtered
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
  _bvk_tty_raw                                 # raw keys + a clean selection, bracketed paste, mouse reports (viewport.sh)
}
# cooked again (echo on) for anything that asks a question with  read
_st_tty_cooked() {
  _bvk_tty_cooked
  [ -t 0 ] && [ -n "$_st_stty" ] && stty "$_st_stty" 2>/dev/null
  return 0
}

# Draw the block in place.  Uses the caller's (_st_run) locals:
#   path_title hint cur top prev buf
# The cursor is left at the end of the "Select:" line (no trailing newline).
_st_draw() {
  [ "${_SL_WANT:-0}" = 1 ] && _sl_ready          # smartload: the wait is over; wipe its bar before this screen is drawn
  local rows cols n=${#_st_lbl[@]} vis i out="" line mark val f1 f2 marks=0 nl=$'\r\033[2K'
  # This screen paints its suggestion INSIDE its own block.  _st_run made _vp_hint_row / _vp_hint_n LOCAL (0), but bash dynamic scope lets a
  # screen opened from here (Cloud Surf, Links, RBAM ... = the viewport: _vp_geometry -> _bvk_hint_area_on) assign THROUGH that local and leave 1 in
  # it.  Back here, _bvk_draw_input -> _input_hint_sync then painted a second copy of the suggestion on the blank row.  So every draw says it again.
  _vp_hint_row=0; _vp_hint_n=0
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
  _ST_TABBAR=""
  if (( ${#_st_tab_labels[@]} > 1 )); then      # tabs: the bar and a blank row come first in the description block (the geometry counts them in _ST_DESC_N)
    _st_tab_bar_v _ST_TABBAR
    _ST_DESC_LN=("$_ST_TABBAR" "" "${_ST_DESC_LN[@]}"); _ST_DESC_N=${#_ST_DESC_LN[@]}
  fi
  _st_hint_text "$buf" "$cols"
  [ -n "$_st_msg" ] && _ST_HINT="$_st_msg"                  # a notice (too large, not available here) takes the suggestion row, as _bvk_notice does on every menu
  # the suggestion first: a long one expands onto more rows (_bvk_hint_wrap) and the list gives them up
  _ST_HINT_N=0; _BVK_HINT_LN=()
  [ -n "$_ST_HINT" ] && { if declare -F _bvk_hint_wrap >/dev/null 2>&1; then _bvk_hint_wrap "$_ST_HINT" 3 $(( cols - 2 )); else _BVK_HINT_LN=("${_ST_HINT:0:cols-2}"); _BVK_HINT_N=1; fi; _ST_HINT_N=$_BVK_HINT_N; }
  vis=$(( rows - 12 - _ST_DESC_N - ( _ST_HINT_N > 1 ? _ST_HINT_N - 1 : 0 ) )); (( vis < 3 )) && vis=3; (( vis > n )) && vis=$n
  if (( cur >= 0 )); then
    (( cur < top )) && top=$cur
    (( cur >= top + vis )) && top=$(( cur - vis + 1 ))
  fi
  (( top > n - vis )) && top=$(( n - vis ))
  (( top < 0 )) && top=0

  for (( i=0; i<n; i++ )); do
    case "${_st_kind[$i]}" in t|r) marks=1; break ;; esac
  done

  # footer = ADVERT (bashbasicsbyvk_advert.sh).  The screen DECLARES what it accepts; the footer prints the free keys and what the budget
  # buys (a command costs 10, a screen has 50); cc lists every declared command.  Nothing here looks anything up.
  _ad_open "${_CM_MAP:-}"
  _ad_free u "Up, one screen back" u "Up"
  _ad_free q "Quit, back to the main menu" q "Quit"
  _ad_free h "Home" h "Home"
  _ad_free cc "Cheat codes — every command this screen takes" cc "Cheat codes"
  _ad_from_cmdfn "${_ST_CMDFN:-}"                                                           # the screen's own typed commands (clr, a-2, d ...)
  _ad_accept '?' "Read the whole explanation of the highlighted row" $(( _ST_DESC_TRUNC ? 20 : 0 )) '?' 0 "Full text"   # in the footer only when the text was cut
  _ad_accept '='      "Filter the rows  (=text · Enter keeps it · = + Enter clears it)" 0
  _ad_accept print    "Print what is on screen — copy it or save as txt" 0
  _ad_accept loadtime "Load time: what each screen change cost  (loadtime 2 · loadtime all)" 0
  _ad_from_dispatcher "${_CM_MAP:-main}"
  _ad_from_map "${_CM_MAP:-main}" st                                                        # the main words this screen's map runs (h s i -h -auth disk ram ...)
  _ad_footer_cells
  f1="$_AD_STD_LINE"                                          # the ONE common footer; the screen's own commands are line 2
  f2=""; (( ${#_AD_FT_PAID[@]} )) && { printf -v f2 '%s   ' "${_AD_FT_PAID[@]}"; f2="${f2%   }"; }
  if (( _st_cnt == 0 )); then if [ -n "${fq:-}" ]; then f2="No match for =$fq   (= + enter clears)"; else f2="Nothing to choose here"; fi; fi

  _ST_FTR1="$f1"; _ST_FTR2="$f2"                           # what _st_click needs to find the footer key that was touched

  # move back to the first line of the previous block (the cursor may sit on a later row of a multi-row text)
  _bvk_blk_park
  if (( prev > 1 )); then out+=$'\r\033['"$(( prev - 1 ))"$'A'; fi

  # The layout is the template 373QS6 (templates/bashbasicsbyvk_373QS6.sh.tpl): this screen paints ONE block in a single write, so the
  # template is BUILT (_tpl_build, every row starts with $nl) from the data below; the geometry (_ST_DESC_N, _ST_TAIL, prev) is unchanged.
  local hd="$path_title" _dl _lst="" _desc="" _sug="" hl _th _tb _tf
  [ -n "${fq:-}" ] && hd="$hd   [filter: =$fq]"
  local _di=0
  for _dl in "${_ST_DESC_LN[@]}"; do
    if [ -n "$_ST_TABBAR" ] && (( _di == 0 )); then _desc+="$_dl"$'\n'      # the tab bar is not dimmed
    else _desc+=$'\033[2m'"$_dl"$'\033[0m\n'; fi
    _di=$(( _di + 1 ))
  done              # what this screen is, in plain words (between the header and the rule)
  _desc="${_desc%$'\n'}"
  if (( top > 0 )); then _lst+="   ▲ $top more above"$'\n'; else _lst+="$_ST_RULE"$'\n'; fi
  for (( i=top; i<top+vis; i++ )); do
    val="${_st_val[$i]}"
    if [ "${_st_kind[$i]}" = h ]; then
      line="    ── ${_st_lbl[$i]}"
      line="${line:0:cols-1}"
      _lst+=$'\033[2m'"$line"$'\033[0m\n'
      continue
    fi
    if [ "${_st_kind[$i]}" = s ]; then _lst+="$_ST_RULE"$'\n'; continue; fi      # a rule between two blocks of rows
    if [ "${_st_kind[$i]}" = i ]; then                                         # an info row: the number sits in the same column as the numbered rows below it
      if [ -n "$val" ]; then printf -v line ' %2s) %s' "$val" "${_st_lbl[$i]}"
      else printf -v line '     %s' "${_st_lbl[$i]}"; fi
      _lst+="${line:0:cols-1}"$'\n'
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
    if (( i == cur )); then _lst+=$'\033[1;7m'"$line"$'\033[0m\n'
    else _lst+="$line"$'\n'; fi
  done
  if (( top + vis < n )); then _lst+="   ▼ $(( n - top - vis )) more below"$'\n'; else _lst+="$_ST_RULE"$'\n'; fi
  _lst="${_lst%$'\n'}"
  _ST_TAIL=0
  if (( _ST_HINT_N > 0 )); then
    for hl in "${_BVK_HINT_LN[@]}"; do _sug+=$'\033[2m'"$hl"$'\033[0m\n'; done
    _ST_TAIL=$(( _ST_HINT_N + 1 ))     # the suggestion rows + a blank line (the trailing newline of the value), only while there is a suggestion
  fi
  # The gap rule: one blank row between the footer and the Select line (or the suggestion).  When footer 2 is empty, that row IS footer 2
  # (Settings); when footer 2 holds keys (a choice question's answers, a screen with commands) the gap is one more row, counted in _ST_TAIL.
  local _gap=""
  if [ -n "$f2" ]; then _gap=$'\n'; _ST_TAIL=$(( _ST_TAIL + 1 )); fi
  _tpl_clear
  _tpl_set menu_name "${_st_icon:-⚙️} ${hd:0:cols-4}" menu_description "$_desc" menu_list "$_lst" \
           footer_commands "${f1:0:cols-1}"$'\n'"${f2:0:cols-1}$_gap" menu_suggestions "$_sug"
  _tpl_build -p "$nl" 373QS6 menu_header _th; _tpl_build -p "$nl" 373QS6 menu_body _tb; _tpl_build -p "$nl" 373QS6 menu_footer _tf
  out+="$_th$_tb$_tf"
  _BVK_SCR_RAW="$out"; _BVK_SCR_EXTRA=""; _BVK_SCR_PROMPT="${_TPL_ACCEPTOR:-Select:}"   # print: the screen without the typed text
  out+=$'\033[J'                                         # from the prompt row down: the old text (a block of rows) goes
  builtin printf '\033[?2026h%s' "$out"
  _BLK_ROWS=1; _BLK_CROW=0; _BLK_TOP=0
  _bvk_draw_input "${_TPL_ACCEPTOR:-Select:} " "$buf" "${pos:-${#buf}}"      # THE typed-line drawer: cursor / selection, rows of a long text, the tap geometry
  builtin printf '\033[?2026l'
  prev=$(( vis + 9 + _ST_DESC_N + _ST_TAIL ))
}

# "==" (deep search, bashbasicsbyvk_deepsearch.sh) is on every screen except a choice menu (a short list of values: there is nothing below it).
_st_deep_on() { [ "${_st_choice:-0}" != 1 ] && declare -F st_deep_search >/dev/null 2>&1; }
# the live filter text for what is typed (a local of _st_run): "=text" filters the rows as you type; "==text" only collects the text, Enter searches all screens
_st_fq_sync() { if [[ "$buf" == ==* ]] && _st_deep_on; then fq=""; else fq="${buf:1}"; fi; }

# The suggestion row of EVERY Settings / Home style screen (what the typed text would do).  Same engine as the main menu's
# row (_cm_hint: command map of the screen that owns this prompt), plus the two things only a list screen knows:
# a typed row number ("Enter -> open <row>") and the = filter.  -> _ST_HINT ("" = nothing to say, the row stays blank)
_ST_HINT=""; _ST_HINT_N=0; _ST_TAIL=0      # _ST_TAIL = rows of the suggestion (hint + blank) under the footer, 0 when there is none
_st_hint_text() {   # $1 typed text  $2 columns
  local b="$1" cols="${2:-80}" k
  _ST_HINT=""
  if [[ "$b" == "?" ]]; then
    _ST_HINT="?  →  read the whole explanation of the highlighted setting"
  elif [[ "$b" == ==* ]] && _st_deep_on; then
    if [ -n "${b:2}" ]; then _ST_HINT="Enter  →  search every screen for “${b:2}”"
    else _ST_HINT="==  →  type what to look for, then Enter searches every screen  (== + Enter clears it)"; fi
  elif [[ "$b" == =* ]]; then
    _ST_HINT="=  →  filter this list live  (= + Enter clears it;  == searches every screen)"
  elif [[ "$b" =~ ^[0-9]+$ ]] && (( ${#b} < 9 )); then
    k=$(( 10#$b ))
    if (( k >= 1 && k <= ${_st_cnt:-0} )) && [ -n "${_st_nrow[$k]+x}" ]; then case "${_st_kind[${_st_nrow[$k]}]}" in t|r|p) if [ "${_st_choice:-0}" = 1 ]; then _ST_HINT="Enter  →  choose  ${_st_lbl[${_st_nrow[$k]}]}"; else _ST_HINT="Enter  →  switch  ${_st_lbl[${_st_nrow[$k]}]}"; fi ;; *) _ST_HINT="Enter  →  open  ${_st_lbl[${_st_nrow[$k]}]}" ;; esac; else _ST_HINT="no row $k here  (1-${_st_cnt:-0})"; fi
  elif declare -F _cm_hint >/dev/null 2>&1; then
    declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
    _cm_hint "$b" menu; _ST_HINT="$_hint_want"
  fi
  return 0
}

# erase the block (cursor ends where the block started)
_st_wipe() {
  _bvk_blk_park
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
  local vis=$(( prev - 9 - _ST_DESC_N - _ST_TAIL )) rel i d=$(( _BVK_CROW - _MS_Y )) t=$_ST_TAIL
  rel=$(( _MS_Y - ( _BVK_CROW - vis - 4 - t ) ))     # 0 = the first list row on screen
  # a tap on the typed text (the Select: row) never gets here: _bvk_edit_press takes it (cursor to the tap / the touch handed back)
  if [ -n "${_ST_TABBAR:-}" ] && (( d == prev - 4 )); then                         # the tab bar (row 3 of the block): a tap on another tab switches to it
    _BVK_LAST_ITEM=""
    if declare -F _bvk_mouse_tab_hit >/dev/null 2>&1 && _bvk_mouse_tab_hit "$_ST_TABBAR"; then _st_tab_step "$_MS_TABDELTA"; cur=-1; top=0; buf=""; navbuf=0; _ST_CLICK_ACT=1; fi
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
    t|r|p) "$act" "$cur" toggle ;;
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
  if [[ ! "$buf" =~ ^[0-9]+$ ]]; then
    # a typed ANSWER WORD (y, n, yes ...) highlights its row the way a number does (and a radio row's [o] follows the highlight).  Only a screen that
    # declares its words does this (_ST_WORDFN: _bvk_menu / _bvk_yn); it sets _ST_WORDNUM = the row number the word answers, 0 = "the start of an
    # answer, keep what is highlighted", -1 = not an answer: nothing stays highlighted, so Space / Enter cannot act on a stale row.
    [ -n "${_ST_WORDFN:-}" ] || return 0
    _ST_WORDNUM=-1; "$_ST_WORDFN" "${buf,,}"
    if (( _ST_WORDNUM > 0 )) && [ -n "${_st_nrow[$_ST_WORDNUM]:-}" ]; then cur=${_st_nrow[$_ST_WORDNUM]}; typed=$_ST_WORDNUM
    elif (( _ST_WORDNUM < 0 )); then cur=-1; typed=0; fi
    return 0
  fi
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

# The typed line of a screen is edited by the shared template (bashbasicsbyvk_textedit.sh).  These are the small callbacks it
# needs; they run inside _st_run and use its locals (buf pos posb navbuf cur top fq need typed).
#   pos  = the cursor in buf.  posb = the text pos belongs to: a text set by hand elsewhere in _st_run (buf="" / buf="=" / the number
#   an arrow echoes ...) is not the text pos was set for, so the cursor simply goes to its end.
_st_type() {            # type / paste TEXT at the cursor (a selection is replaced)
  [ "$buf" = "$posb" ] || pos=${#buf}
  _te_insert buf pos "$1"; posb="$buf"
}
_st_drop_sel() {        # typing or pasting over a selected text: the selection goes first
  (( ${_TE_ANC:--1} >= 0 )) || return 0
  [ "$buf" = "$posb" ] || pos=${#buf}
  _te_del_sel buf pos || return 0
  posb="$buf"; navbuf=0
  return 0
}
_st_cursor() { need=0; posb="$buf"; }                  # (also called by the engine after a tap: _ED_REDRAW)              # the cursor / selection moved: nothing else changed
# Ctrl-C / Ctrl-Z reach the template as signals, while the loop waits in its key read: nothing redraws unless these do
_st_sig_cursor() { _st_cursor; _st_draw; }
_st_sig_edited() { _st_edited; _st_draw; }
_st_edited() {          # an editing key changed buf (Backspace, Delete, cut, a word delete, undo): the =filter / the typed row follow it
  navbuf=0; posb="$buf"
  if [[ "$buf" == =* ]]; then _st_fq_sync; cur=-1; top=0
  elif [ "${_st_wasf:-0}" = 1 ]; then fq=""; cur=-1; top=0         # the =filter text is gone: the filter ends
  else _st_follow; need=0; fi
}
_st_paste_text() {      # a pasted text goes into the row in ONE step; it is accepted only by the user's own Enter
  _st_d="$1"
  (( navbuf )) && { buf=""; navbuf=0; }
  _st_drop_sel
  if (( ${_BVK_MAX_INPUT:-20000} > 0 && ${#buf} + ${#_st_d} > ${_BVK_MAX_INPUT:-20000} )); then _bvk_too_large_text $(( ${#buf} + ${#_st_d} )); _st_msg="$_BVK_NOTICE"; _st_d=""; fi
  if [ -z "$_st_d" ]; then _BVK_PASTE_ENTER=0     # refused (too large) or empty: its Enter must not run what was typed before it (the engine reads this after the paste)
  elif [ -z "$buf" ] && [ "${_st_d:0:1}" = "=" ]; then buf="$_st_d"; _st_fq_sync; cur=-1; top=0
  elif [[ "$buf" == =* ]]; then _st_type "$_st_d"; _st_fq_sync; cur=-1; top=0
  else _st_type "$_st_d"; _st_follow; need=0; fi
}

# _st_run "Title" build_fn act_fn ["legacy hint"] [cmd_fn] [word_fn]
#   cmd_fn BUF — optional: gets typed text before the number/command rules; return 0 = handled
# ── the loop of a Settings screen: HOOKS around THE typed-line loop (_bvk_edit_run, bashbasicsbyvk_viewport.sh)
# Nothing here reads a key: the engine does (editing keys, paste + burst paste, mouse, the hand-back, the typed line drawn by _bvk_draw_input).  These
# are the rows, the highlight, the filter and the commands of a screen.  They run in _st_run's scope (its locals: buf pos cur top prev need ...).
_st_ev() { (( _st_msgclr )) && { _st_msg=""; _st_msgclr=0; }; return 0; }     # the "too large" note lasts until the next key
_st_turn() {          # top of every turn: rebuild the rows if something changed, draw the screen; rc 1 = leave this screen
  if (( _st_idle )); then _st_idle=0; return 0; fi                              # an idle tick (the hand-back timer): nothing changed, nothing to redraw
  if (( _st_began )); then                                                      # only AFTER an event: a screen opened from a handler that is leaving (_st_back=1) must still draw
    (( _st_quit )) && return 1
    (( _st_back )) && { _st_back=0; return 1; }                                 # the handler finished this screen (a choice was made)
  fi
  _st_began=1
  # rows are rebuilt only when something changed (a choice, a filter edit) — never for plain ↑ ↓ PgUp PgDn Home End, which only move the highlight
  if (( need )); then
    _lt_b "settings: build the rows ($title)"
    "$build"
    _st_filter_rows
    _st_number
    _lt_e
    need=0
  fi
  if (( _ST_JUMP_DEPTH > 0 )); then                 # a tap on the path of a screen below: close every screen above the one that was tapped
    (( _st_depth > _ST_JUMP_DEPTH )) && return 1
    _ST_JUMP_DEPTH=0
  fi
  n=${#_st_lbl[@]}
  if [ -n "${_st_start_num:-}" ]; then      # a choice menu starts on its default row
    [ -n "${_st_nrow[$_st_start_num]+x}" ] && cur=${_st_nrow[$_st_start_num]}
    _st_start_num=""
  fi
  (( cur >= n )) && cur=$(( n - 1 ))
  (( cur < 0 && n == 0 )) && cur=-1
  [ "$buf" = "$posb" ] || { pos=${#buf}; posb="$buf"; }      # a text set elsewhere: the cursor is at its end
  _lt_b "settings: draw the screen"
  _st_draw
  _lt_e
  _lt_ready settings "$path_title"
  need=1; _st_msgclr=1                                       # whatever the next key is, the rows are rebuilt unless its handler says otherwise
  return 0
}
_st_tick() { _st_idle=1; return 0; }
_st_pre() {           # before an editing key: the cursor follows a text set elsewhere; remember whether the =filter was on
  _st_ev
  [ "$buf" = "$posb" ] || { pos=${#buf}; posb="$buf"; }
  _st_wasf=0; [[ "$buf" == =* ]] && _st_wasf=1
  return 0
}
_st_nav() {           # a named key that is not an editing key
  _st_ev
  case "$1" in
    up)    need=0; _st_move -1; _st_navbuf ;;
    down)  need=0; _st_move 1;  _st_navbuf ;;
    pgup)  need=0; _st_move -1 "$page"; _st_navbuf ;;   # ±10 like the main menu
    pgdn)  need=0; _st_move 1 "$page";  _st_navbuf ;;
    home)  need=0; cur=-1; _st_move 1;  _st_navbuf ;;
    end)   need=0; cur=-1; _st_move -1; _st_navbuf ;;
    left|right)           # ← → change the value of the highlighted row (while nothing is typed); on a screen with tabs they switch the tab
      if (( ${#_st_tab_labels[@]} > 1 )); then
        _st_tab_step "$([ "$1" = right ] && echo 1 || echo -1)"; cur=-1; top=0; buf=""; navbuf=0; need=1; return 0
      fi
      (( cur >= 0 )) && _st_selectable "$cur" && { _lt_enter "$1" "${_st_lbl[$cur]}"; "$act" "$cur" "$1"; } ;;
  esac
  return 0
}
_st_click_hook() { _st_ev; need=0; _st_click; (( _ST_CLICK_ACT )) && need=1; return 0; }
_st_wheel_hook() { _st_ev; need=0; _st_wheel "$([ "$1" = up ] && echo -1 || echo 1)"; return 0; }
_st_toolarge()   { _bvk_too_large_text "$1"; _st_msg="$_BVK_NOTICE"; _st_draw; }
_st_byte() {          # Enter and Space; every other byte is typed by _st_type_key.  rc 0 handled · 1 leave this screen · 2 not mine
  _st_ev
  case "$1" in
    "")
      navbuf=0; typed=0
      if [[ "$buf" == ==* ]] && _st_deep_on; then
        # ==text + Enter searches every screen (a list of the screens that match; a number opens one) · == + Enter clears
        _sdq="${buf:2}"; buf=""; fq=""; cur=-1; top=0
        if [ -n "${_sdq//[[:space:]]/}" ]; then
          _lt_enter "==" "$_sdq"
          _st_wipe; _st_tty_cooked          # like a row that opens a sub-screen (_st_activate)
          st_deep_search "${_sdq#"${_sdq%%[![:space:]]*}"}"
          _st_tty_raw
          (( _st_quit )) && return 1
        fi
        return 0
      fi
      if [[ "$buf" == =* ]]; then
        # =text + Enter keeps the filter · = + Enter clears it
        [ "$buf" = "=" ] && fq=""
        buf=""; cur=-1; top=0
        return 0
      fi
      # print / loadtime work on every settings screen: wipe the block, run, draw it again
      case "${buf,,}" in
        "?")
          # the whole explanation of the highlighted setting (or of the screen)
          _st_wipe; _st_tty_cooked
          declare -F _st_desc_show >/dev/null 2>&1 && _st_desc_show
          _st_tty_raw; buf=""; return 0 ;;
        print|loadtime|loadtime\ *)
          _st_wipe; _st_tty_cooked
          if declare -F bvk_main_exec >/dev/null 2>&1; then bvk_main_exec "${buf,,}"
          else echo "  (\"${buf%% *}\" needs the full app: here type a number, u = back, q = close)"; fi   # a stand-alone door has no command runner
          _st_tty_raw; buf=""; cur=-1; return 0 ;;
        cc)
          # cheat codes: the list of what this screen accepts; the pick is typed into the line below
          [ "${_CC_OPEN:-0}" = 1 ] && { buf=""; return 0; }
          _st_wipe; _st_tty_cooked
          if declare -F bvk_main_exec >/dev/null 2>&1; then _CC_CTX=st bvk_main_exec cc
          else echo "  (cheat codes need the full app: here type a number, u = back, q = close)"; fi   # a stand-alone door has no command runner
          _st_tty_raw
          buf="${_CC_PREFILL:-}"; _CC_PREFILL=""; fq=""
          [[ "$buf" == =* ]] && fq="${buf:1}"
          cur=-1; top=0; return 0 ;;
      esac
      _ltl=""; (( cur >= 0 )) && _ltl="${_st_lbl[$cur]}"
      _lt_enter "${buf:-enter}" "$_ltl"
      if [ -n "$cmdfn" ] && "$cmdfn" "${buf,,}"; then
        buf=""
        (( _st_quit )) && return 1
        (( _st_back )) && { _st_back=0; return 1; }          # the handler finished this screen (a choice was made)
        return 0
      fi
      if _st_cm_gate "${buf,,}"; then                    # a map command (run / refused): the same answer the hint row gave
        buf=""; cur=-1
        (( _st_quit )) && return 1
        (( _st_back )) && { _st_back=0; return 1; }
        return 0
      fi
      case "${buf,,}" in
        u) if [ -n "$fq" ]; then fq=""; buf=""; cur=-1; top=0; return 0; fi
           return 1 ;;                       # buf keeps "u" so the prompt line can stay
        q) _st_quit=1; return 1 ;;
        "") (( cur >= 0 )) && _st_selectable "$cur" && _st_activate ;;
        *[!0-9]*) buf="" ;;                         # not a command: clear it
        *)
          num=$(( 10#$buf )); buf=""
          if (( num >= 1 && num <= _st_cnt )); then
            cur=${_st_nrow[$num]}
            _st_activate
          fi ;;
      esac
      return 0 ;;
    " ")
      navbuf=0; typed=0
      _st_drop_sel
      if [[ "$buf" == =* ]]; then _st_type " "; _st_fq_sync; cur=-1; top=0     # a space inside =text is part of the search
      elif [ -n "$buf" ] && [[ "$buf" == [a-z]* ]]; then _st_type " "            # a command being typed (loadtime 2)
      elif (( cur >= 0 )) && _st_selectable "$cur"; then buf=""; _lt_enter "space" "${_st_lbl[$cur]}"; _st_activate; fi
      return 0 ;;
  esac
  return 2
}
_st_type_key() {      # a typed character
  _st_ev
  [[ "$1" == [[:print:]] ]] || return 0
  _st_d="$1"
  (( navbuf )) && [ "$_st_d" != "?" ] && { buf=""; navbuf=0; }
  _st_drop_sel        # the number an arrow put on the line is replaced by what is typed
  if (( ${_BVK_MAX_INPUT:-20000} > 0 && ${#buf} >= ${_BVK_MAX_INPUT:-20000} )); then _bvk_too_large_text $(( ${#buf} + 1 )); _st_msg="$_BVK_NOTICE"
  elif [ -z "$buf" ] && [ "$_st_d" = "=" ]; then buf="="; fq=""; cur=-1; top=0
  elif [ "$_st_d" = "?" ] && [[ "$buf" =~ ^[0-9]*$ ]]; then          # ?  = read the whole explanation of the highlighted row (no Enter needed)
    _st_wipe; _st_tty_cooked; declare -F _st_desc_show >/dev/null 2>&1 && _st_desc_show; _st_tty_raw
  elif [[ "$buf" == =* ]]; then _st_type "$_st_d"; _st_fq_sync; cur=-1; top=0
  else _st_type "$_st_d"; _st_follow; need=0; fi
  return 0
}

_st_run() {
  local title="$1" build="$2" act="$3" hint="${4:-}" cmdfn="${5:-}"
  [ -n "${BVK_WF_DIR:-}" ] && declare -F _wf_screen >/dev/null 2>&1 && _wf_screen "$title"
  local _ST_CMDFN="$cmdfn"      # the screen declares its typed commands with "$_ST_CMDFN --cc"  (key|description|prio|shown|short per line)
  local _ST_WORDFN="${6:-}" _ST_WORDNUM=-1   # optional: "$_ST_WORDFN word" sets _ST_WORDNUM = the row a typed answer word belongs to (_st_follow highlights it)
  local cur=-1 top=0 prev=0 n buf="" pos=0 posb="" _st_wasf=0 num path_title fq="" _sdq="" need=1 page="${_vp_page_step:-10}" navbuf=0 typed=0
  local parent_title="${_st_title_now:-}"
  # This screen draws its suggestion INSIDE its own block (_st_draw, _ST_HINT).  _vp_hint_row is the main menu's global flag "the prompt has the
  # suggestion area above it": left on, the shared drawer (_bvk_draw_input -> _input_hint_sync) painted a second copy on the blank row under
  # the first one (from 100 columns up, where the area is 1 row).  Local = the menu's value is back when the screen closes.
  local _vp_hint_row=0 _vp_hint_n=0 _hint_cur=""
  _st_depth=$(( _st_depth + 1 ))
  # a sub screen shows its way in ("Settings › Sort order"); _st_crumb="" drops the prefix (cc)
  if (( _st_depth > 1 )) && [ -n "${_st_crumb-Settings}" ]; then path_title="${_st_crumb-Settings} › $title"; else path_title="$title"; fi
  _st_title_now="$path_title"
  _st_quit=0
  [ -t 0 ] && [ -z "$_st_stty" ] && _st_stty=$(stty -g 2>/dev/null)         # what _st_tty_cooked puts back
  # terminal resized while this screen is open (keyboard, extra keys, rotation): re-measure on the next draw.
  # Whatever WINCH trap the caller had (_multi_prompt_loop has one) is put back when we leave.
  local _st_old_winch; _st_old_winch=$(trap -p WINCH)
  _ST_SIZE_STALE=1
  trap '_ST_SIZE_STALE=1; _vp_probe_t=0' WINCH     # _vp_probe_t=0: the next _vp_probe_size is live, not the 0.3 s reuse

  local _st_msgclr=0 _st_idle=0 _st_began=0
  # THE typed-line loop (bashbasicsbyvk_viewport.sh): keys, selection, paste, tap, wheel, the mouse hand-back.  A screen supplies the hooks above.
  local $_BVK_ED_HOOKS
  local _ED_BUF=buf _ED_POS=pos _ED_MODE=list _ED_REDRAW=_st_cursor _ED_EDITED=_st_edited _ED_SIG_REDRAW=_st_sig_cursor _ED_SIG_EDITED=_st_sig_edited _ED_PASTE=_st_paste_text
  local _ED_TURN=_st_turn _ED_TICK=_st_tick _ED_PRE=_st_pre _ED_CLICK=_st_click_hook _ED_WHEEL=_st_wheel_hook _ED_NAV=_st_nav _ED_BYTE=_st_byte _ED_TYPE=_st_type_key
  local _ED_TOOLARGE=_st_toolarge _ED_DEFER_ENTER=1
  _bvk_edit_run
  (( _ED_EOF )) && _st_quit=1                                                  # the input is gone (tty closed, SSH drop, pane killed): leave, never loop on it

  # leave tidy: a sub screen erases itself so its parent redraws in the same
  # place; the top screen stays on screen with  Select: u  /  Select: q  as typed.
  if (( prev > 0 )); then
    _TE_ANC=-1                                    # the line is left: no selection mark on it
    if (( _st_depth > 1 )); then _st_wipe; else
      _bvk_blk_park; if declare -F _bvk_fit_input >/dev/null 2>&1; then _bvk_fit_input "${_TPL_ACCEPTOR} " "$buf" "${#buf}"; builtin printf '\r\033[J%s%s' "$_BVK_FIT_PROMPT" "$_BVK_FIT"
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

# ── small helpers used by the screens

# _st_ask "What to type" [current]  → _st_in.  Returns 1 on u / q / blank.
_st_ask() {
  local p="$1" cur="${2:-}"
  [ -n "$cur" ] && p="$p [now: $cur]"
  _bvk_read _st_in "  $p  (u = back): "
  _st_in="${_st_in%$'\r'}"
  case "${_st_in,,}" in
    u|"") return 1 ;;
    q) _st_quit=1; return 1 ;;
  esac
  return 0
}

# short one-line note under the menu (printed once, scrolls away naturally)
_st_note() { [ "${_SL_WANT:-0}" = 1 ] && _sl_pulse; builtin printf '  %s\n' "$1"; }
