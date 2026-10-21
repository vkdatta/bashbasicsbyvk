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
#    _mc_footer  "u:Up" "q:Quit" "h:Home"      key hints  ->  "u) Up   q) Quit   h) Home"
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
_mc_options() {
  local n="$1" l; shift
  _mc_managed || echo "$_MC_RULE"
  for l in "$@"; do echo "${n}) ${l}"; n=$(( n + 1 )); done
  _mc_managed || echo "$_MC_RULE"
}

# Footer items:  "key:Label"   a key hint            ->  key) Label
#                "#text"        a plain note line      (always on its own line)
#                "|"            start a new line
# Lines wrap at the viewport width (a line wider than the terminal would wrap
# physically and throw the viewport's row accounting off).
_mc_footer() {
  local -a items=()
  local unders=0
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
    cell="${it%%:*}) ${it#*:}"
    (( unders )) && cell="${cell//_/ }"
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
_mc_ask() { read -e -p "${1:-Select: }" REPLY; }

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

# ---- registered footers -------------------------------------------------
_mc_footer_register file_menu    u:Up q:Quit h:Home
_mc_footer_register browse_main  u:Up cd:Change_directory q:Quit '|' h:Home s:Settings -h:Help -u:Upgrade
_mc_footer_register back_quit    u:Back q:Quit
_mc_footer_register back_only    u:Back
_mc_footer_register cancel_back  z:Cancel u:Back
_mc_footer_register infinity     u:Up q:Quit
