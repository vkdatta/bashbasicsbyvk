# bashbasicsbyvk_settings_ui.sh — one small menu engine for every Settings screen
# ════════════════════════════════════════════════════════════════════════════
#  Look (same feel as the main menu):
#
#     Settings
#     ─────────────────────────────
#      [x] Show hidden files
#          Sort order            A → Z       ›
#          Animation             pop / carpet ›
#     ─────────────────────────────
#     ↑↓ move · space/enter change · u back · q close
#
#  Keys   ↑ ↓ (or k j)  move          space / enter  change the row
#         u (or Esc)    back ONE level (settings → main menu from the top)
#         q             close Settings completely, straight to the main menu
#
#  A screen is just two functions:
#     build_fn            fills the rows from the current settings  (_st_add …)
#     act_fn IDX KEY      reacts to a row  (KEY = toggle | enter | left | right)
#
#  Row kinds   t toggle [x]/[ ]   r radio [x]/[ ]   a action ›   h heading
# ════════════════════════════════════════════════════════════════════════════

declare -ga _st_lbl=() _st_kind=() _st_on=() _st_val=() _st_tag=()
_st_quit=0
_st_back=0      # a screen sets this to close itself after an action
_st_k=""
_o=0

_st_reset()  { _st_lbl=(); _st_kind=(); _st_on=(); _st_val=(); _st_tag=(); }
# _st_add KIND LABEL [ON 0|1] [VALUE] [TAG]
_st_add()    { _st_kind+=("$1"); _st_lbl+=("$2"); _st_on+=("${3:-0}"); _st_val+=("${4:-}"); _st_tag+=("${5:-}"); }
_st_eq()     { [ "$1" = "$2" ] && _o=1 || _o=0; }   # sets _o (no subshell)

_st_selectable() { [ "${_st_kind[$1]:-h}" != "h" ]; }

# move $cur by $1 (+1/-1) to the next selectable row (stays put if none)
_st_step() {
  local d="$1" n=${#_st_lbl[@]} i=$cur
  while :; do
    i=$(( i + d ))
    (( i < 0 || i >= n )) && return 1
    if _st_selectable "$i"; then cur=$i; return 0; fi
  done
}

# read one key → _st_k  = up down left right home end pgup pgdn space enter u q other
_st_readkey() {
  local c
  _st_k="other"
  IFS= read -rsn1 c || { _st_k="q"; return; }
  case "$c" in
    "")        _st_k=enter ;;
    " ")       _st_k=space ;;
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

# Draw the block in place.  Uses the caller's locals: title hint cur top prev.
_st_draw() {
  local rows cols n=${#_st_lbl[@]} vis i out="" line mark val rule
  rows=$(_term_rows); cols=$(_term_cols)
  vis=$(( rows - 5 )); (( vis < 3 )) && vis=3; (( vis > n )) && vis=$n
  (( cur < top )) && top=$cur
  (( cur >= top + vis )) && top=$(( cur - vis + 1 ))
  (( top < 0 )) && top=0
  printf -v rule '%*s' "$(( cols > 42 ? 40 : cols - 2 ))" ''
  rule="${rule// /─}"

  (( prev > 0 )) && out+=$'\033['"$prev"$'A'
  out+=$'\r\033[2K\033[1m '"$title"$'\033[0m\n'
  out+=$'\r\033[2K '"$rule"$'\n'
  for (( i=top; i<top+vis; i++ )); do
    val="${_st_val[$i]}"
    case "${_st_kind[$i]}" in
      t|r) mark="[ ]"; [ "${_st_on[$i]}" = 1 ] && mark="[x]" ;;
      *)   mark="   " ;;
    esac
    if [ "${_st_kind[$i]}" = h ]; then
      line=" ── ${_st_lbl[$i]}"
    else
      [ "${_st_kind[$i]}" = a ] && val="${val:+$val }›"
      printf -v line ' %s %-22s %s' "$mark" "${_st_lbl[$i]}" "$val"
    fi
    line="${line:0:cols-1}"
    if (( i == cur )); then
      out+=$'\r\033[2K\033[1;7m'"$line"$'\033[0m\n'
    elif [ "${_st_kind[$i]}" = h ]; then
      out+=$'\r\033[2K\033[2m'"$line"$'\033[0m\n'
    else
      out+=$'\r\033[2K'"$line"$'\n'
    fi
  done
  out+=$'\r\033[2K '"$rule"$'\n'
  out+=$'\r\033[2K\033[2m'"${hint:0:cols-1}"$'\033[0m\n\033[J'
  builtin printf '%s' "$out"
  prev=$(( vis + 4 ))
}

# _st_run "Title" build_fn act_fn ["hint"]
_st_run() {
  local title="$1" build="$2" act="$3"
  local hint="${4:-↑↓ move · space/enter change · u back · q close}"
  local cur=0 top=0 prev=0 n
  _st_quit=0
  "$build"
  _st_selectable "$cur" || _st_step 1 || true

  while :; do
    "$build"
    n=${#_st_lbl[@]}
    (( cur >= n )) && cur=$(( n - 1 ))
    (( cur < 0 )) && cur=0
    _st_draw
    _st_readkey
    case "$_st_k" in
      up)    _st_step -1 ;;
      down)  _st_step 1 ;;
      home)  cur=0; _st_selectable 0 || _st_step 1 ;;
      end)   cur=$(( n - 1 )); _st_selectable "$cur" || _st_step -1 ;;
      pgup)  cur=$(( cur - 8 )); (( cur < 0 )) && cur=0; _st_selectable "$cur" || _st_step 1 ;;
      pgdn)  cur=$(( cur + 8 )); (( cur >= n )) && cur=$(( n - 1 )); _st_selectable "$cur" || _st_step -1 ;;
      u)     return 0 ;;
      q)     _st_quit=1; return 0 ;;
      left|right)
        _st_selectable "$cur" && "$act" "$cur" "$_st_k"
        ;;
      space|enter)
        _st_selectable "$cur" || continue
        case "${_st_kind[$cur]}" in
          t|r) "$act" "$cur" toggle ;;
          a)
            # actions may ask questions / open a sub-screen: wipe the block first
            (( prev > 0 )) && builtin printf '\033[%dA' "$prev"
            builtin printf '\r\033[J'
            prev=0
            "$act" "$cur" enter
            ;;
        esac
        ;;
    esac
    (( _st_quit )) && return 0
    (( _st_back )) && { _st_back=0; return 0; }
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

# short one-line note under the menu (printed once, scrolls away naturally)
_st_note() { builtin printf '  %s\n' "$1"; }
