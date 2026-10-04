# bashbasicsbyvk_settings_ui.sh — one small menu engine for every Settings screen
# ════════════════════════════════════════════════════════════════════════════
#  Behaves like the main menu:
#
#     Sort order
#     Current: A → Z
#     ────────────────────────────────────────
#       1) [x] A → Z
#       2) [ ] Z → A
#       3) [ ] Newest first
#     ────────────────────────────────────────
#     u) Back   q) Close settings
#     ↑↓ move · space check · enter select
#     Select: 2
#
#  Keys   ↑ ↓            move the highlight (↑ from nothing → last item, wraps)
#         space          check / uncheck the highlighted [ ] row
#         digits         type an item number, then Enter
#         u + Enter      back ONE level (sub-screen → Settings)
#         q + Enter      close Settings completely → main menu
#         Enter          run the highlighted / typed item
#         Esc            same as  u  (no Enter needed)
#         ← →            only on screens that ask for it (Group by: change order)
#
#  A screen is just two functions:
#     build_fn            fills the rows from the current settings  (_st_add …)
#                         and may set  _st_head  (one status line under the title)
#     act_fn IDX KEY      reacts to a row  (KEY = toggle | enter | left | right)
#
#  Row kinds   t toggle [x]/[ ]   r radio [x]/[ ]   a action ›   h heading
#  Only t / r / a rows are numbered; headings are not.
# ════════════════════════════════════════════════════════════════════════════

declare -ga _st_lbl=() _st_kind=() _st_on=() _st_val=() _st_tag=()
declare -ga _st_num=() _st_row=()     # row index → item number ; item number → row index
_st_quit=0
_st_back=0        # a screen sets this to close itself after an action
_st_want_lr=0     # a screen sets this to 1 right before _st_run to receive ← →
_st_depth=0       # 0 outside settings, 1 = Settings, 2+ = sub-screens
_st_head=""       # one status line shown under the title
_st_msg=""        # one-shot message shown in the hint line on the next draw
_st_count=0
_st_hasmark=0
_st_labw=10
_st_k=""; _st_ch=""; _st_in=""
_o=0

_st_reset()  { _st_lbl=(); _st_kind=(); _st_on=(); _st_val=(); _st_tag=(); _st_head=""; }
# _st_add KIND LABEL [ON 0|1] [VALUE] [TAG]
_st_add()    { _st_kind+=("$1"); _st_lbl+=("$2"); _st_on+=("${3:-0}"); _st_val+=("${4:-}"); _st_tag+=("${5:-}"); }
_st_eq()     { [ "$1" = "$2" ] && _o=1 || _o=0; }   # sets _o (no subshell)

# number the selectable rows, remember the widest label
_st_index() {
  local i n=${#_st_lbl[@]} c=0 w=0
  _st_num=(); _st_row=(); _st_hasmark=0
  for (( i=0; i<n; i++ )); do
    if [ "${_st_kind[$i]}" = h ]; then
      _st_num[$i]=""
    else
      c=$(( c + 1 )); _st_num[$i]=$c; _st_row[$c]=$i
      (( ${#_st_lbl[$i]} > w )) && w=${#_st_lbl[$i]}
      [ "${_st_kind[$i]}" = a ] || _st_hasmark=1
    fi
  done
  _st_count=$c
  (( w > 28 )) && w=28
  (( w < 8 ))  && w=8
  _st_labw=$w
}

# read one key → _st_k = up down left right home end pgup pgdn space enter bksp esc char other eof
#                _st_ch = the typed character when _st_k=char
_st_readkey() {
  local c
  _st_k=other; _st_ch=""
  IFS= read -rsn1 c || { _st_k=eof; return; }
  case "$c" in
    "")             _st_k=enter ;;
    " ")            _st_k=space ;;
    $'\177'|$'\b')  _st_k=bksp ;;
    $'\033')
      if _read_key_seq; then
        _key_name "$_esc"
        case "$_kname" in
          up|down|left|right|home|end|pgup|pgdn) _st_k="$_kname" ;;
          *) _st_k=other ;;
        esac
      else
        _st_k=esc
      fi ;;
    *)
      if [[ "$c" == [[:cntrl:]] ]]; then _st_k=other; else _st_k=char; _st_ch="$c"; fi ;;
  esac
}

# Draw the whole block in place; the cursor ends on the  Select:  line.
# Uses the caller's locals: title hint cur top prev buf.
_st_draw() {
  local rows cols n=${#_st_lbl[@]} vis i out="" line mark val rule fixed=6 lbl
  local foot1="u) Back   q) Close settings"
  rows=${_vp_rows_now:-24}; cols=${_vp_cols_now:-80}
  (( _st_depth <= 1 )) && foot1="q) Close settings   (back to the main menu)"
  [ -n "$_st_head" ] && fixed=7
  vis=$(( rows - fixed - 1 )); (( vis < 3 )) && vis=3; (( vis > n )) && vis=$n
  (( cur >= 0 && cur < top )) && top=$cur
  (( cur >= top + vis )) && top=$(( cur - vis + 1 ))
  (( top > n - vis )) && top=$(( n - vis ))
  (( top < 0 )) && top=0
  printf -v rule '%*s' "$(( cols > 42 ? 40 : cols - 2 ))" ''
  rule="${rule// /─}"

  (( prev > 0 )) && out+=$'\033['"$prev"$'A'
  out+=$'\r\033[2K\033[1m'"${title:0:cols-1}"$'\033[0m\n'
  [ -n "$_st_head" ] && out+=$'\033[2K\033[2m'"${_st_head:0:cols-1}"$'\033[0m\n'
  out+=$'\033[2K'"$rule"$'\n'
  for (( i=top; i<top+vis; i++ )); do
    lbl="${_st_lbl[$i]}"; val="${_st_val[$i]}"
    if [ "${_st_kind[$i]}" = h ]; then
      line="  ── $lbl"
    else
      case "${_st_kind[$i]}" in
        t|r) mark="[ ] "; [ "${_st_on[$i]}" = 1 ] && mark="[x] " ;;
        *)   mark=""; (( _st_hasmark )) && mark="    " ;;
      esac
      [ "${_st_kind[$i]}" = a ] && val="${val:+$val }›"
      printf -v line ' %2d) %s%-*s  %s' "${_st_num[$i]}" "$mark" "$_st_labw" "${lbl:0:28}" "$val"
    fi
    line="${line:0:cols-1}"
    if (( i == cur )); then
      out+=$'\033[2K\033[1;7m'"$line"$'\033[0m\n'
    elif [ "${_st_kind[$i]}" = h ]; then
      out+=$'\033[2K\033[2m'"$line"$'\033[0m\n'
    else
      out+=$'\033[2K'"$line"$'\n'
    fi
  done
  out+=$'\033[2K'"$rule"$'\n'
  out+=$'\033[2K'"$foot1"$'\n'
  if [ -n "$_st_msg" ]; then
    out+=$'\033[2K'"${_st_msg:0:cols-1}"$'\n'; _st_msg=""
  else
    out+=$'\033[2K\033[2m'"${hint:0:cols-1}"$'\033[0m\n'
  fi
  out+=$'\033[2K'"Select: $buf"$'\033[J'
  builtin printf '%s' "$out"
  prev=$(( vis + fixed - 1 ))
}

# repaint only the  Select:  line (typing / backspace)
_st_input() { builtin printf '\r\033[2KSelect: %s' "$buf"; }

# erase the whole block and leave the cursor where the block started
_st_wipe() {
  (( prev > 0 )) && builtin printf '\033[%dA' "$prev"
  builtin printf '\r\033[J'
  prev=0
}

# _st_run "Title" build_fn act_fn ["hint"]
_st_run() {
  _st_depth=$(( _st_depth + 1 ))
  _st_run_inner "$@"
  local rc=$?
  _st_depth=$(( _st_depth - 1 ))
  return $rc
}

_st_run_inner() {
  local title="$1" build="$2" act="$3"
  local hint="${4:-↑↓ move · space check · enter select}"
  local lr=$_st_want_lr; _st_want_lr=0
  local cur=-1 top=0 prev=0 buf="" auto=0 dirty=1 pos n cmd leaving=0

  # tidy hints written for the old instant-key screens
  hint="${hint// · u back · q close settings/}"
  hint="${hint// · u back · q close/}"
  hint="${hint// · u\/q back to main menu/}"

  _vp_probe_size 2>/dev/null
  _st_quit=0; _st_back=0

  _st_refresh() {
    "$build"
    [ -z "$_st_head" ] && declare -F "${build}_head" >/dev/null 2>&1 && "${build}_head"
    _st_index
    (( cur >= ${#_st_lbl[@]} )) && cur=$(( ${#_st_lbl[@]} - 1 ))
    (( cur >= 0 )) && [ "${_st_kind[$cur]:-h}" = h ] && cur=-1
    return 0
  }
  _st_refresh

  # run the row at index $1
  _st_exec() {
    local idx="$1"
    case "${_st_kind[$idx]}" in
      t|r) "$act" "$idx" toggle ;;
      a)   _st_wipe; "$act" "$idx" enter; _vp_probe_size 2>/dev/null ;;
    esac
    (( _st_quit )) && return 0
    (( _st_back )) && { _st_back=0; leaving=1; return 0; }
    _st_refresh
    dirty=1
  }

  while :; do
    if (( dirty )); then _st_draw; dirty=0; fi
    _st_readkey
    n=$_st_count
    pos=0; (( cur >= 0 )) && pos=${_st_num[$cur]:-0}

    case "$_st_k" in
      up|down|home|end|pgup|pgdn)
        (( n == 0 )) && continue
        case "$_st_k" in
          up)   pos=$(( pos <= 1 ? n : pos - 1 )) ;;
          down) pos=$(( pos >= n ? 1 : pos + 1 )) ;;
          home) pos=1 ;;
          end)  pos=$n ;;
          pgup) pos=$(( pos - 8 )); (( pos < 1 )) && pos=1 ;;
          pgdn) pos=$(( pos + 8 )); (( pos > n )) && pos=$n ;;
        esac
        cur=${_st_row[$pos]}; buf="$pos"; auto=1; dirty=1 ;;

      left|right)
        if (( lr && cur >= 0 )); then
          "$act" "$cur" "$_st_k"
          _st_refresh; dirty=1
        fi ;;

      space)
        (( cur < 0 )) && continue
        _st_exec "$cur" ;;

      enter)
        cmd="${buf//[[:space:]]/}"; cmd="${cmd,,}"
        case "$cmd" in
          u) leaving=1 ;;
          q) _st_quit=1 ;;
          "")
            (( cur >= 0 )) && _st_exec "$cur" ;;
          *[!0-9]*)
            _st_msg="⚠️  Not an option — type a number, u or q, then Enter"
            buf=""; auto=0; dirty=1 ;;
          *)
            pos=$(( 10#$cmd ))
            if (( pos >= 1 && pos <= n )); then
              cur=${_st_row[$pos]}; buf="$pos"; auto=1
              _st_exec "$cur"
            else
              _st_msg="⚠️  No item $cmd"
              buf=""; auto=0; dirty=1
            fi ;;
        esac ;;

      bksp)
        if (( auto )); then buf=""; auto=0; else buf="${buf%?}"; fi
        _st_input ;;

      char)
        if (( auto )); then buf=""; auto=0; fi
        (( ${#buf} < 8 )) && buf+="$_st_ch"
        if [[ "$buf" =~ ^[0-9]+$ ]] && (( 10#$buf >= 1 && 10#$buf <= n )); then
          cur=${_st_row[$(( 10#$buf ))]}; dirty=1
        else
          _st_input
        fi ;;

      esc) leaving=1 ;;
      eof) _st_quit=1 ;;
    esac

    if (( _st_quit || leaving )); then
      # a sub-screen cleans up after itself so the screen above redraws cleanly
      (( _st_depth > 1 )) && _st_wipe
      return 0
    fi
  done
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

# short message: shown in the hint line of the next redraw
_st_note() {
  if (( _st_depth > 0 )); then _st_msg="$1"; else builtin printf '  %s\n' "$1"; fi
}
