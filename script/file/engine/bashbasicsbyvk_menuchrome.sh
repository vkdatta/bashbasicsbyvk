# ============================================================
#  bashbasicsbyvk_menuchrome.sh — the ONE menu layout, reusable by every menu
#
#  Layout (the viewport draws the rules and the spacing; see _vp_build_chrome):
#
#      header
#      ─────────────────────────────
#      options
#      ─────────────────────────────
#      <linebreak>
#      footer
#      <linebreak>
#      Select:
#
#  A menu supplies only its own CONTENT with these helpers:
#
#    _mc_header  "Title" ["Sub line" ...]      title block
#    _mc_options START "Label" "Label" ...     "START) Label", "START+1) …"
#    _mc_keyed   "c:Copy" "m:Move" ...         lettered options, one per row
#    _mc_footer  "u.up" "q" "h:Home"      key hints  ->  "u) Up   q) Quit   h) Home"
#    _mc_footer  @name                         a footer registered below
#    _mc_footer_register name item ...         register one (underscores in a label = spaces)
#
#  Footer items: "key:Label" · "#plain note line" · "|" (new line).
#
#  A whole simple menu in one call:
#    _mc_menu "Title"  "Sub line"  --  Run View Edit  --  @file_menu
#  (sections are separated by "--": header lines · option labels · footer)
#  and for a free-standing prompt that returns the answer in $REPLY:
#    _mc_ask "Choice: "   (wraps `read -e -p`, so the viewport takes it over)
#
#  Menus that draw through the viewport directly (_vp_header_fn / _vp_footer_fn)
#  just call _mc_header / _mc_footer from those two functions.
#
#  THE MASTER TEMPLATES (a menu supplies DATA and ACTIONS only; this file owns look, prompt, keys and return codes):
#
#    MC-01/02  _mc_select [-d DEFAULT] [-b] [-s SUB]... [-x FOOTER_ITEM]... OUTVAR "Title" ROW...
#                  numbered selection menu.  ROW = "label"  |  "value|label"  |  "value|label|alias,alias".
#                  OUTVAR gets the row's value (its number when the row has none).  Two rows = the two-option setting.
#    MC-04     _mc_review ARRAY [-t Title] [-f FORMATTER]     review the chosen items: c) Confirm  x) Remove
#    MC-07     _mc_text OUTVAR "Prompt: " ["hint line"...]    a free-text prompt with the standard footer (not a selection)
#    FOOTER-01 _mc_footer_std [-b] [extra items...]            screen actions, then the standard  u) q) h) cc)   (profiles std_nav / std_nav_back)
#    CONTROL-01 return contract of every template:  0 answered · 1 back (u) · 2 quit (q: _BVK_TO_MAIN is raised, UNWIND, never redraw) · 3 cancelled / EOF
#               _mc_unwind is true once q was pressed anywhere below: every loop checks it before it draws again.
#    h and cc are handled by the template itself (_mc_std_key): a key printed in a footer is the menu's own key and reaches it as typed.
#
#  RULES
#   * print through echo/printf — NEVER `builtin printf/echo`. The smart-menu
#     layer records echo/printf to redraw the menu; `builtin` output is invisible
#     to it, which is how footers vanish and menus get drawn twice.
#   * the extra linebreaks and the rules are the viewport's job. When there is
#     no viewport (not a tty, VK_SMART_MENUS=0) _mc_* print the same layout
#     themselves, so a menu looks the same either way.
# ============================================================

declare -gA _MC_FOOTERS=()
_MC_RULE="   ─────────────────────────────"

# ONE label per generic key. A footer item written as the bare key ("u", "q", "z", "rf") takes its label from here, so
# the wording cannot drift between menus. A generic key that really means something else gets a NAMED variant in this table
# ("u.up" = u) Up, go up a folder); the part after the dot is only a name, the key shown is the part before it.
# A generic key is NEVER written "key:Label" (tests/cmd_drift.sh fails on it, whatever the spelling): add a variant here instead.
declare -gA _MC_KEYLABEL=([u]=Back [u.up]=Up [u.prefix]="Remove last prefix" [q]=Quit [z]=Cancel [rf]=Refresh)

# ---- CONTROL-01: the return contract of every template below, and the one unwind test --------------------
_MC_OK=0; _MC_BACK=1; _MC_QUIT=2; _MC_EOF=3
# true once q was pressed in this menu or in any screen / prompt below it (_bvk_quit raises the flag, see viewport.sh)
_mc_unwind() { [ "${_BVK_TO_MAIN:-0}" = 1 ]; }

_mc_footer_register() {
  local name="$1"; shift
  _MC_FOOTERS["$name"]="$*"
}

# true when the viewport will draw the rules/spacing for us
_mc_managed() { [[ "${_sm_on:-0}" == 1 && -t 1 ]]; }

_mc_header() {
  local l
  echo
  for l in "$@"; do echo "$l"; done
}

# _mc_options START label...  — prints "N) label" lines, numbering from START
#   The viewport draws the rules only when it takes the menu over (two or more rows); a one-row list is read as it was printed,
#   so it prints its own rules and looks the same.
_mc_options() {
  local n="$1" l r=0; shift
  { _mc_managed && (( $# >= 2 )); } || r=1
  (( r )) && echo "$_MC_RULE"
  for l in "$@"; do echo "${n}) ${l}"; n=$(( n + 1 )); done
  (( r )) && echo "$_MC_RULE"
}

# Footer items:  "key:Label"   a key hint            ->  key) Label
#                "#text"        a plain note line      (always on its own line)
#                "|"            start a new line
# Lines wrap at the viewport width (a line wider than the terminal would wrap
# physically and throw the viewport's row accounting off).
declare -g _MC_UNDER_FOOTER=0
declare -gA _MC_PRINTED=()     # the keys the LAST footer printed ("u", "z", "v" ...): a plain prompt under it takes them as its own answers (cmdmap _cm_prompt_collect)
_mc_footer() {
  local -a items=()
  local unders=0
  _MC_PRINTED=()
  if [[ "${1:-}" == @* ]]; then
    local reg="${_MC_FOOTERS[${1#@}]-}"
    [ -z "$reg" ] && return 0
    IFS=' ' read -r -a items <<< "$reg"; unders=1
  else
    items=("$@")
  fi
  _vp_usable; local cols=$_vp_usable_w          # the ONE width source (viewport)
  (( cols < 18 )) && cols=18
  local it cell line="" out=()
  for it in "${items[@]}"; do
    if [ "$it" = "|" ]; then
      [ -n "$line" ] && out+=("$line"); line=""; continue
    fi
    if [[ "$it" == "#"* ]]; then
      [ -n "$line" ] && out+=("$line"); line=""
      out+=("${it#\#}"); continue
    fi
    if [[ "$it" == *:* ]]; then cell="${it%%:*}) ${it#*:}"
    elif [ -n "${_MC_KEYLABEL[$it]-}" ]; then cell="${it%%.*}) ${_MC_KEYLABEL[$it]}"
    else cell="${it}) ${it}"; fi
    (( unders )) && cell="${cell//_/ }"
    [[ "$cell" =~ ^([A-Za-z0-9_-]{1,5})\) ]] && _MC_PRINTED["${BASH_REMATCH[1],,}"]=1
    if [ -z "$line" ]; then
      line="$cell"
    elif _vp_cells "$line"; local _lw=$_vp_w; _vp_cells "$cell"; (( _lw + 3 + _vp_w >= cols )); then
      out+=("$line"); line="$cell"
    else
      line+="   $cell"
    fi
  done
  [ -n "$line" ] && out+=("$line")
  echo
  for line in "${out[@]}"; do echo "$line"; done
  echo
}

# _mc_keyed "c:Copy" "m:Move" ...  — lettered OPTIONS (one per row, like numbered ones)
_mc_keyed() {
  local it
  _mc_managed || echo "$_MC_RULE"
  for it in "$@"; do echo "${it%%:*}) ${it#*:}"; done
  _mc_managed || echo "$_MC_RULE"
}

# _mc_menu  header… -- labels… -- footer…      (numbering starts at 1; use _mc_menu0 for 0)
_mc_menu_n() {
  local start="$1"; shift
  local -a hdr=() opt=() ftr=()
  local part=0 a
  for a in "$@"; do
    if [ "$a" = "--" ]; then part=$(( part + 1 )); continue; fi
    case $part in 0) hdr+=("$a") ;; 1) opt+=("$a") ;; *) ftr+=("$a") ;; esac
  done
  (( ${#hdr[@]} )) && _mc_header "${hdr[@]}"
  _mc_options "$start" "${opt[@]}"
  (( ${#ftr[@]} )) && _mc_footer "${ftr[@]}"
}
_mc_menu()  { _mc_menu_n 1 "$@"; }
_mc_menu0() { _mc_menu_n 0 "$@"; }

# prompt wrapper: answer lands in $REPLY
_mc_ask() { _bvk_read REPLY "${1:-Select: }"; }

# ---- FOOTER-01: the standard footer with a screen's own actions in front ----------------------------------------
#   _mc_footer_std [-b] [item...]     -b = no folders on this screen: u reads "Back", not "Up"
#   Own actions first, then the standard  u q h cc.  Items from the first "|" or "#note" on stay AFTER the standard keys.
_mc_std_items() {                      # -> _MC_STD = the standard keys as footer items (for a footer that needs its own line layout)
  local p=std_nav it
  [ "${1:-}" = -b ] && p=std_nav_back
  _MC_STD=(); for it in ${_MC_FOOTERS[$p]}; do _MC_STD+=("${it//_/ }"); done
}
_mc_footer_std() {
  local prof=std_nav it intail=0
  [ "${1:-}" = -b ] && { prof=std_nav_back; shift; }
  local -a head=() tail=() nav=()
  for it in "$@"; do
    [[ "$it" == "|" || "$it" == "#"* ]] && intail=1
    if (( intail )); then tail+=("$it"); else head+=("$it"); fi
  done
  for it in ${_MC_FOOTERS[$prof]}; do nav+=("${it//_/ }"); done
  _mc_footer "${head[@]}" "${nav[@]}" "${tail[@]}"
}

# _mc_std_key TYPED   the two standard keys that open a screen: h (Home) and cc (Cheat codes).
#   0 = TYPED was one of them and has run (the caller draws its menu again, after checking _mc_unwind) · 1 = not a standard key
#   A key printed in a footer is the menu's own key (cmdmap: "a key the menu draws beats the map"), so it reaches the menu as
#   typed and the menu has to run it: every template does that here, once.
_mc_std_key() {
  case "${1,,}" in
    h)  _CM_RUN_MODE=menu bvk_main_exec h ;;
    cc) _CM_RUN_MODE=menu bvk_main_exec cc ;;
    *)  return 1 ;;
  esac
  return 0
}

# _mc_read OUTVAR PROMPT   ONE read for every template: 0 = a line came back, 1 = u (back: that one prompt was cancelled), 3 = the command layer cancelled the flow / EOF
#   (a loop that ignores this rc spins on the swallowed prompt: that was the 13-second loading bar of "Selection view").
_mc_read() {
  local _mr_a _mr_rc
  _CM_BACKED=0; _MC_UNDER_FOOTER=1          # this prompt is drawn right under a footer: the keys it printed are this prompt's own
  _bvk_read _mr_a "$2"; _mr_rc=$?
  _MC_UNDER_FOOTER=0
  (( _mr_rc )) && { [ "${_CM_BACKED:-0}" = 1 ] && { _CM_BACKED=0; return 1; }; return 3; }
  _mr_a="${_mr_a%$'\r'}"
  printf -v "$1" '%s' "$_mr_a"
  return 0
}

# _mc_nav KEY   the answer every template shares:   u → 1 back · q → 2 quit (raises the unwind flag) · h / cc → runs, then 4 = "draw again"
#   (rc 5 = not a navigation key.)  4 turns into 2 when the screen it opened asked to quit.
_mc_nav() {
  case "${1,,}" in
    u) return 1 ;;
    q) _bvk_quit; return 2 ;;
    h|cc) _mc_std_key "$1"; _mc_unwind && return 2; return 4 ;;
  esac
  return 5
}

# ---- STEPS-01: a flow of several questions, where u = ONE QUESTION BACK --------------------------------------
#   _mc_steps STEP...      each STEP is a function name that asks ONE question and returns the CONTROL-01 code
#                          (0 answered · 1 back (u) · 2 quit · 3 cancelled) or 5 = "this question does not apply now".
#                          Runs them in order: 0 -> the next question · 1 -> the question before it (it is asked again) ·
#                          5 -> skipped, in the direction you were going (forward on the way in, backward after a u) · 2 / 3 -> stop at once.
#   Returns 0 all answered · 1 u on the FIRST question (the caller goes back one level) · 2 quit · 3 cancelled.
#   A question that is already settled is simply not in the list (or answers 5), so u never lands on it.
#   Every multi-question flow uses this (never `|| return` after the first u): u is one menu back, nothing else.
#   The steps share the caller's local variables (bash dynamic scope): the caller declares them, the steps fill them.
_mc_steps() {
  local -a _mst=("$@"); local _msi=0 _msrc _msd=1
  while (( _msi >= 0 && _msi < ${#_mst[@]} )); do
    "${_mst[$_msi]}"; _msrc=$?
    case "$_msrc" in
      0) _msd=1;  _msi=$(( _msi + 1 )) ;;
      1) _msd=-1; _msi=$(( _msi - 1 )) ;;
      5) _msi=$(( _msi + _msd )) ;;
      *) return "$_msrc" ;;
    esac
  done
  (( _msi < 0 )) && return 1
  return 0
}

# ---- MC-01 / MC-02: numbered selection (and the two-option setting) ------------------------------------------
#   _mc_select [-d DEFAULT] [-b] [-s SUB]... [-x ITEM]... OUTVAR "Title" ROW...
#     -d VALUE  Enter picks the row with that value (marked "(default)");  without it a bare Enter is an invalid answer
#     -b        no folders here: footer says u) Back instead of u) Up
#     -k        keyed rows: each row shows its FIRST alias as its key ("c) Copy") instead of a number; the typed key picks it.
#               A key that is also a main command (c s r f ...) can only be an alias when the menu PRINTS it: this is how.
#     -s TEXT   a sub line under the title (repeatable)        -x ITEM  a screen action added to the footer (repeatable)
#     ROW       "label"  ·  "value|label"  ·  "value|label|alias,alias"     (aliases are accepted typed; they are not advertised)
#   Draws:  title · rule · 1. … · rule · footer (actions + u q h cc) · Select:      An invalid answer draws the menu again.
_mc_select() {
  local _ms_def="" _ms_b="" _ms_o _ms_keyed=0
  local -a _ms_sub=() _ms_x=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -d) _ms_def="$2"; shift 2 ;;
      -b) _ms_b="-b"; shift ;;
      -k) _ms_keyed=1; shift ;;
      -s) _ms_sub+=("$2"); shift 2 ;;
      -x) _ms_x+=("$2"); shift 2 ;;
      *) break ;;
    esac
  done
  _ms_o="$1"; local _ms_title="$2"; shift 2
  local -a _ms_val=() _ms_lab=() _ms_ali=()
  local _ms_row _ms_i=0 _ms_p
  for _ms_row in "$@"; do
    _ms_i=$(( _ms_i + 1 ))
    if [[ "$_ms_row" == *"|"* ]]; then
      _ms_val+=("${_ms_row%%|*}"); _ms_p="${_ms_row#*|}"
      _ms_lab+=("${_ms_p%%|*}")
      [[ "$_ms_p" == *"|"* ]] && _ms_ali+=("${_ms_p#*|}") || _ms_ali+=("")
    else
      _ms_val+=("$_ms_i"); _ms_lab+=("$_ms_row"); _ms_ali+=("")
    fi
  done
  local -a _ms_show=()
  for _ms_i in "${!_ms_lab[@]}"; do
    if [ -n "$_ms_def" ] && [ "${_ms_val[$_ms_i]}" = "$_ms_def" ]; then _ms_show+=("${_ms_lab[$_ms_i]}  (default)")
    else _ms_show+=("${_ms_lab[$_ms_i]}"); fi
  done
  local _ms_a _ms_rc _ms_al
  local -a _ms_kshow=()
  if (( _ms_keyed )); then
    for _ms_i in "${!_ms_show[@]}"; do _ms_al="${_ms_ali[$_ms_i]%%,*}"; _ms_kshow+=("${_ms_al:-$((_ms_i+1))}:${_ms_show[$_ms_i]}"); done
  fi
  while true; do
    [ -n "$_ms_title" ] && _mc_header "$_ms_title" "${_ms_sub[@]}"
    if (( _ms_keyed )); then _mc_keyed "${_ms_kshow[@]}"; else _mc_options 1 "${_ms_show[@]}"; fi
    _mc_footer_std $_ms_b "${_ms_x[@]}"
    _mc_read _ms_a "Select: " || { local _mc_rc=$?; _mc_unwind && return 2; return "$_mc_rc"; }
    _ms_a="${_ms_a,,}"; _ms_a="${_ms_a//[[:space:]]/}"
    _mc_nav "$_ms_a"; _ms_rc=$?
    case "$_ms_rc" in
      1) return 1 ;;
      2) return 2 ;;
      4) continue ;;
    esac
    if [ -z "$_ms_a" ]; then
      if [ -n "$_ms_def" ]; then printf -v "$_ms_o" '%s' "$_ms_def"; return 0; fi
    elif (( ! _ms_keyed )) && [[ "$_ms_a" =~ ^[0-9]+$ ]] && (( _ms_a >= 1 && _ms_a <= ${#_ms_val[@]} )); then
      printf -v "$_ms_o" '%s' "${_ms_val[$((_ms_a-1))]}"; return 0
    else
      for _ms_i in "${!_ms_ali[@]}"; do
        for _ms_al in ${_ms_ali[$_ms_i]//,/ }; do
          [ "$_ms_a" = "${_ms_al,,}" ] && { printf -v "$_ms_o" '%s' "${_ms_val[$_ms_i]}"; return 0; }
        done
      done
    fi
    _bvk_invalid
  done
}

# ---- MC-07: a free-text / number prompt (not a selection) -----------------------------------------------------
#   _mc_text [-x ITEM]... OUTVAR "Prompt: " ["hint line"...]     -x = a screen action / note added to the footer (repeatable)
#   0 answered (may be empty) · 1 back · 2 quit · 3 cancelled
_mc_text() {
  local -a _mt_x=()
  while [ "${1:-}" = "-x" ]; do _mt_x+=("$2"); shift 2; done
  local _mt_o="$1" _mt_p="$2" _mt_a _mt_rc; shift 2
  while true; do
    (( $# )) && _mc_header "$@"
    _mc_footer_std -b "${_mt_x[@]}"
    _mc_read _mt_a "$_mt_p" || { local _mc_rc=$?; _mc_unwind && return 2; return "$_mc_rc"; }
    _mc_nav "$_mt_a"; _mt_rc=$?
    case "$_mt_rc" in 1) return 1 ;; 2) return 2 ;; 4) continue ;; esac
    printf -v "$_mt_o" '%s' "$_mt_a"; return 0
  done
}

# ---- MC-04: review the chosen items (confirm, or remove some) -------------------------------------------------
#   _mc_review ARRAYNAME [-t "Title"] [-f FORMATTER]     FORMATTER gets one item and prints its row label (default: basename)
#   0 confirmed · 1 back · 2 quit (the unwind flag is up: the caller must return at once) · 3 cancelled
#   Needs parse_selection (viewport.sh) for the "1,3 or 2-5" of the remove prompt.
_mc_review_label() { basename -- "$1"; }
_mc_review() {
  local -n _mrv_ref="$1"; shift
  local _mrv_title="" _mrv_fmt=_mc_review_label _mrv_a _mrv_rc _mrv_s _mrv_i
  while [ $# -gt 0 ]; do
    case "$1" in -t) _mrv_title="$2"; shift 2 ;; -f) _mrv_fmt="$2"; shift 2 ;; *) break ;; esac
  done
  local -a _mrv_lab=() _mrv_rm=() _mrv_new=()
  local -A _mrv_del=()
  while true; do
    _mrv_lab=()
    for _mrv_s in "${_mrv_ref[@]}"; do _mrv_lab+=("$("$_mrv_fmt" "$_mrv_s")"); done
    if (( ${#_mrv_ref[@]} == 0 )); then
      _mc_header "📋 No items selected yet."
    else
      _mc_header "${_mrv_title:-📋 Current selections (${#_mrv_ref[@]}):}"
      _mc_options 1 "${_mrv_lab[@]}"
    fi
    _mc_footer_std -b "c:Confirm" "x:Remove"
    _mc_read _mrv_a "Select: " || { local _mc_rc=$?; _mc_unwind && return 2; return "$_mc_rc"; }
    _mrv_a="${_mrv_a,,}"; _mrv_a="${_mrv_a//[[:space:]]/}"
    _mc_nav "$_mrv_a"; _mrv_rc=$?
    case "$_mrv_rc" in
      1) echo "↩️  Back to navigation"; return 1 ;;
      2) return 2 ;;
      4) continue ;;
    esac
    case "$_mrv_a" in
      c)
        if (( ${#_mrv_ref[@]} == 0 )); then echo "🔴  Nothing selected — add items before confirming."
        else echo "💫 Selections confirmed (${#_mrv_ref[@]} item(s))"; return 0; fi ;;
      x)
        if (( ${#_mrv_ref[@]} == 0 )); then echo "🔴  Nothing to remove."; continue; fi
        _mc_text _mrv_a "Remove: " "Remove selected item numbers:" "Enter: 1,3 or 2-5"; _mrv_rc=$?
        case "$_mrv_rc" in 1) continue ;; 2) return 2 ;; 3) return 3 ;; esac
        _mrv_rm=($(parse_selection "$_mrv_a" "${#_mrv_ref[@]}"))
        if (( ${#_mrv_rm[@]} == 0 )); then echo "❌ No valid numbers entered"; continue; fi
        _mrv_del=(); for _mrv_i in "${_mrv_rm[@]}"; do _mrv_del[$_mrv_i]=1; done
        _mrv_new=(); _mrv_i=1
        for _mrv_s in "${_mrv_ref[@]}"; do [ -z "${_mrv_del[$_mrv_i]+x}" ] && _mrv_new+=("$_mrv_s"); _mrv_i=$(( _mrv_i + 1 )); done
        _mrv_ref=("${_mrv_new[@]}")
        echo "💫 Removed ${#_mrv_rm[@]} item(s). Remaining: ${#_mrv_ref[@]}" ;;
      *) _bvk_invalid ;;
    esac
  done
}

# ---- THE invalid-choice handler: every menu calls this, nobody prints its own ----------
#   _bvk_invalid            one standard message (the caller's loop redraws, e.g. outer loop)
#   _bvk_invalid VAR        message + VAR=true  -> the loop's "$VAR && redraw_fresh" redraws
#                           the SAME menu (upgrade / api / rules use _xx_fresh flags)
# The message is printed with echo (the smart-menu layer records it) and the menu is
# always redrawn FRESH below it, exactly like the outer loop.  Never leave the menu
# on screen with only a new "Select:" -- the extra line makes the viewport's block
# height wrong, and every later in-place repaint / tick lands on the wrong rows.
_BVK_MSG_INVALID="🔴  Invalid selection"
_bvk_invalid() {
  echo "$_BVK_MSG_INVALID"
  [ -n "${1:-}" ] && printf -v "$1" '%s' true
  return 0
}

# Info mode: a command that only SHOWS something (i-N: info of a version, a rule, a release) prints it, then waits for one key
# and hands back to the menu, which then redraws below.  Without the wait the menu was never drawn again and the screen ended
# on a bare "Select:" under the text (the footer came back, the menu did not).  Usage:  show_it && _bvk_info_wait ; fresh=true
_BVK_MSG_INFO_EXIT="Press any key to exit info mode"
_bvk_info_wait() {
  [ -t 0 ] && [ -t 1 ] || return 0                      # no terminal (a pipe, a test harness): nothing to wait for
  local _k _s
  [ "${_SL_WANT:-0}" = 1 ] && _sl_ready                  # smartload: the command is done, we wait for the person now (no "Working…" bar on the prompt)
  echo
  echo -n "$_BVK_MSG_INFO_EXIT"
  stty -icanon -echo min 1 time 0 2>/dev/null
  IFS= builtin read -rsn1 _k   # bvk-read-ok: "press any key" pause of info mode: one raw key (then its escape tail), no line to edit
  if [[ "$_k" == $'\x1b' ]]; then                       # an arrow key / mouse report is ONE key: swallow the rest of it
    while IFS= builtin read -rsn1 -t 0.02 _s; do :; done
  fi
  builtin printf '\r\033[2K'                            # the question goes away, the text above it stays
  return 0
}

# ---- registered footers -------------------------------------------------
# FOOTER-01: THE standard navigation footer.  Every ordinary selection menu and every tabbed screen shows exactly this
# (tabmenu.sh registers its two footers from these, so one edit here changes all of them).
_mc_footer_register std_nav      u.up q h:Home cc:Cheat_codes       # u) Up   q) Quit   h) Home   cc) Cheat codes
_mc_footer_register std_nav_back u    q h:Home cc:Cheat_codes       # a screen with no folders: u) Back
_mc_footer_register file_menu    u.up q h:Home
_mc_footer_register browse_main  u.up cd:Change_directory q '|' h:Home s:Settings -h:Help -u:Upgrade
_mc_footer_register back_quit    u.up q h:Home cc:Cheat_codes       # = std_nav: the numbered option menus (create, organise, find ...)
_mc_footer_register back_only    u
_mc_footer_register cancel_back  z u
_mc_footer_register infinity     u.up q
