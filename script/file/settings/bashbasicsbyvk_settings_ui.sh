# bashbasicsbyvk_settings_ui.sh — one small menu engine for every Settings screen
# ════════════════════════════════════════════════════════════════════════════
#  Styled exactly like the main menu (header · rule · numbered rows · rule ·
#  footer of suggested commands · "Select:" prompt):
#
#     ⚙️ Settings
#        ─────────────────────────────
#      1) Hidden files        hide ›
#      2) Sort order          A → Z ›
#      3) Animation           pop / carpet ›
#        ─────────────────────────────
#     u/q) Back to main menu   ↑↓) Move
#     Type 1-3 to choose   enter) Select
#     Select:
#
#  Keys   1-9…          type a row number to choose it (Enter if it has 2 digits)
#         ↑ ↓ (or k j)  move (wraps top ↔ bottom). Nothing is highlighted
#                       until you choose or move.
#         space / enter change the highlighted row
#         u (or Esc)    back ONE level (settings → main menu from the top)
#         q             close Settings completely, straight to the main menu
#
#  A screen is just two functions:
#     build_fn            fills the rows from the current settings  (_st_add …)
#     act_fn IDX KEY      reacts to a row  (KEY = toggle | enter | left | right)
#
#  Row kinds   t toggle [x]/[ ]   r radio [x]/[ ]   a action ›   h heading
#  (headings are not numbered)
# ════════════════════════════════════════════════════════════════════════════

declare -ga _st_lbl=() _st_kind=() _st_on=() _st_val=() _st_tag=()
declare -ga _st_num=() _st_nrow=()
_st_cnt=0       # how many numbered (selectable) rows the screen has
_st_quit=0
_st_back=0      # a screen sets this to close itself after an action
_st_depth=0     # 1 = top Settings screen, 2+ = sub settings
_st_k=""
_st_d=""
_o=0

# same rule as the main menu
_ST_RULE="   ─────────────────────────────"

_st_reset()  { _st_lbl=(); _st_kind=(); _st_on=(); _st_val=(); _st_tag=(); }
# _st_add KIND LABEL [ON 0|1] [VALUE] [TAG]
_st_add()    { _st_kind+=("$1"); _st_lbl+=("$2"); _st_on+=("${3:-0}"); _st_val+=("${4:-}"); _st_tag+=("${5:-}"); }
_st_eq()     { [ "$1" = "$2" ] && _o=1 || _o=0; }   # sets _o (no subshell)

_st_selectable() { [ "${_st_kind[$1]:-h}" != "h" ]; }

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
_st_move() {
  local d="$1" n=${#_st_lbl[@]} i=$cur t=0
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

# read one key → _st_k = up down left right home end pgup pgdn space enter bksp
#                        digit (digit in _st_d) u q other
_st_readkey() {
  local c
  _st_k="other"; _st_d=""
  IFS= read -rsn1 c || { _st_k="q"; return; }
  case "$c" in
    "")            _st_k=enter ;;
    " ")           _st_k=space ;;
    $'\177'|$'\b') _st_k=bksp ;;
    [0-9])         _st_k=digit; _st_d="$c" ;;
    $'\033')
      if _read_key_seq; then
        _key_name "$_esc"
        case "$_kname" in
          up|down|left|right|home|end|pgup|pgdn) _st_k="$_kname" ;;
          *) _st_k=other ;;
        esac
      else
        _st_k=u                       # bare Esc = back
      fi ;;
    k|K) _st_k=up ;;
    j|J) _st_k=down ;;
    u|U) _st_k=u ;;
    q|Q) _st_k=q ;;
  esac
}

# Draw the block in place.  Uses the caller's (_st_run) locals:
#   path_title hint cur top prev buf
# The cursor is left at the end of the "Select:" line (no trailing newline).
_st_draw() {
  local rows cols n=${#_st_lbl[@]} vis i out="" line mark val f1 f2 marks=0 nl=$'\r\033[2K'
  rows=$(_term_rows); cols=$(_term_cols)
  vis=$(( rows - 9 )); (( vis < 3 )) && vis=3; (( vis > n )) && vis=$n
  if (( cur >= 0 )); then
    (( cur < top )) && top=$cur
    (( cur >= top + vis )) && top=$(( cur - vis + 1 ))
  fi
  (( top > n - vis )) && top=$(( n - vis ))
  (( top < 0 )) && top=0

  for (( i=0; i<n; i++ )); do
    case "${_st_kind[$i]}" in t|r) marks=1; break ;; esac
  done

  # footer = suggested commands
  if (( _st_depth > 1 )); then f1="u) Back   q) Close settings"; else f1="u/q) Back to main menu"; fi
  f1+="   ↑↓) Move"
  case "$_st_cnt" in
    0) f2="Nothing to choose here" ;;
    1) f2="Type 1 to choose   enter) Select" ;;
    *) f2="Type 1-$_st_cnt to choose   enter) Select" ;;
  esac
  if [[ "$hint" == *"←/→"* ]]; then
    case "$_st_cnt" in 0|1) ;; *) f2="Type 1-$_st_cnt to choose   ←/→) Reorder" ;; esac
  fi

  # move back to the first line of the previous block
  if (( prev > 1 )); then out+=$'\r\033['"$(( prev - 1 ))"$'A'; fi

  out+="$nl"$'\n'                                          # space above
  out+="$nl⚙️ ${path_title:0:cols-4}"$'\n'                  # header
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
        t|r) mark="[ ] "; [ "${_st_on[$i]}" = 1 ] && mark="[x] " ;;
        *)   mark="    " ;;
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
  out+="$nl${f1:0:cols-1}"$'\n'
  out+="$nl${f2:0:cols-1}"$'\n'
  out+="${nl}Select: $buf"$'\033[J'
  builtin printf '\033[?2026h%s\033[?2026l' "$out"
  prev=$(( vis + 7 ))
}

# erase the block (cursor ends where the block started)
_st_wipe() {
  (( prev > 1 )) && builtin printf '\r\033[%dA' $(( prev - 1 ))
  builtin printf '\r\033[J'
  prev=0
}

# do what the highlighted row says (called from _st_run; shares its locals)
_st_activate() {
  case "${_st_kind[$cur]}" in
    t|r) "$act" "$cur" toggle ;;
    a)
      # actions may ask questions / open a sub-screen: wipe the block first
      _st_wipe
      "$act" "$cur" enter ;;
  esac
}

# _st_run "Title" build_fn act_fn ["legacy hint"]
_st_run() {
  local title="$1" build="$2" act="$3" hint="${4:-}"
  local cur=-1 top=0 prev=0 n buf="" num path_title
  local parent_title="${_st_title_now:-}"
  _st_depth=$(( _st_depth + 1 ))
  if (( _st_depth > 1 )); then path_title="Settings › $title"; else path_title="$title"; fi
  _st_title_now="$path_title"
  _st_quit=0

  while :; do
    "$build"
    _st_number
    n=${#_st_lbl[@]}
    (( cur >= n )) && cur=$(( n - 1 ))
    (( cur < 0 && n == 0 )) && cur=-1
    _st_draw
    _st_readkey
    case "$_st_k" in
      up)    buf=""; _st_move -1 ;;
      down)  buf=""; _st_move 1 ;;
      home|pgup) buf=""; cur=-1; _st_move 1 ;;
      end|pgdn)  buf=""; cur=-1; _st_move -1 ;;
      bksp)  buf="${buf%?}" ;;
      digit)
        buf+="$_st_d"
        (( 10#$buf > _st_cnt )) && buf="$_st_d"       # not a valid row: start over
        if (( 10#$buf < 1 || 10#$buf > _st_cnt )); then
          buf=""
        elif (( 10#$buf * 10 > _st_cnt )); then       # can't grow into a longer number
          num=$(( 10#$buf )); buf=""
          cur=${_st_nrow[$num]}
          _st_activate
        fi
        ;;
      u)     buf=""; break ;;
      q)     buf=""; _st_quit=1; break ;;
      left|right)
        (( cur >= 0 )) && _st_selectable "$cur" && "$act" "$cur" "$_st_k"
        ;;
      space|enter)
        if [ -n "$buf" ]; then
          num=$(( 10#$buf )); buf=""
          if (( num >= 1 && num <= _st_cnt )); then
            cur=${_st_nrow[$num]}
            _st_activate
          fi
        elif (( cur >= 0 )) && _st_selectable "$cur"; then
          _st_activate
        fi
        ;;
    esac
    (( _st_quit )) && break
    (( _st_back )) && { _st_back=0; break; }
  done

  # leave tidy: a sub screen erases itself so its parent redraws in the same
  # place; the top screen leaves the block and just clears the prompt line.
  if (( prev > 0 )); then
    if (( _st_depth > 1 )); then _st_wipe; else builtin printf '\r\033[2K'; fi
  fi
  _st_depth=$(( _st_depth - 1 ))
  _st_title_now="$parent_title"
  return 0
}

# ── small helpers used by the screens ────────────────────────────────────────

# _st_ask "What to type" [current]  → _st_in.  Returns 1 on u / q / blank.
_st_ask() {
  local p="$1" cur="${2:-}"
  [ -n "$cur" ] && p="$p [now: $cur]"
  read -r -p "  $p  (u = back): " _st_in
  _st_in="${_st_in%$'\r'}"
  case "${_st_in,,}" in
    u|"") return 1 ;;
    q) _st_quit=1; return 1 ;;
  esac
  return 0
}

# short one-line note under the menu (printed once, scrolls away naturally)
_st_note() { builtin printf '  %s\n' "$1"; }
