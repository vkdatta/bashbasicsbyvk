# ============================================================
#  bashbasicsbyvk_menuchrome.sh — reusable menu header / options / footer
#
#  Every menu builds its "chrome" (title block above the options and the
#  key hints below them) from the same three helpers, each menu supplying
#  its own content:
#
#    _mc_header  "Title" ["Sub line" ...]      blank line + the lines
#    _mc_options START "Label" "Label" ...     "START) Label", "START+1) ..."
#    _mc_footer  "u:Up" "q:Quit" "h:Home"      blank line + "u) Up   q) Quit   h) Home"
#    _mc_footer  @name                         a footer registered below
#
#  Footer items are "key:Label". The item "|" starts a new footer line.
#
#  Register a footer once, use it anywhere:
#    _mc_footer_register file_menu  u:Up q:Quit h:Home
#    _mc_footer @file_menu
#
#  All output goes through echo/printf (NOT `builtin`), so the smart-menu
#  layer (bashbasicsbyvk_smartmenu.sh) records it and redraws the footer
#  inside its viewport. Printing a footer with `builtin printf` makes it
#  invisible to that layer — which is why a footer can vanish.
# ============================================================

declare -gA _MC_FOOTERS=()

_mc_footer_register() {
  local name="$1"; shift
  _MC_FOOTERS["$name"]="$*"
}

_mc_header() {
  local l
  echo
  for l in "$@"; do echo "$l"; done
}

# _mc_options START label...  — prints "N) label" lines, numbering from START
_mc_options() {
  local n="$1" l; shift
  for l in "$@"; do echo "${n}) ${l}"; n=$(( n + 1 )); done
}

_mc_footer() {
  local -a items=()
  local unders=0
  if [[ "$1" == @* ]]; then
    local reg="${_MC_FOOTERS[${1#@}]-}"
    if [ -z "$reg" ]; then echo; return 0; fi
    IFS=' ' read -r -a items <<< "$reg"; unders=1
  else
    items=("$@")
  fi
  local cols="${COLUMNS:-${_vp_cols:-80}}"
  (( cols < 20 )) && cols=80
  local it cell line="" out=()
  for it in "${items[@]}"; do
    if [ "$it" = "|" ]; then
      [ -n "$line" ] && out+=("$line"); line=""; continue
    fi
    cell="${it%%:*}) ${it#*:}"
    (( unders )) && cell="${cell//_/ }"   # registered footers: "Change_directory" -> "Change directory"
    if [ -z "$line" ]; then
      line="$cell"
    elif (( ${#line} + 3 + ${#cell} >= cols )); then
      out+=("$line"); line="$cell"
    else
      line+="   $cell"
    fi
  done
  [ -n "$line" ] && out+=("$line")
  echo
  for line in "${out[@]}"; do echo "$line"; done
}

# ---- registered footers -------------------------------------------------
_mc_footer_register file_menu  u:Up q:Quit h:Home
_mc_footer_register browse_main u:Up cd:Change_directory q:Quit '|' h:Home s:Settings -h:Help -u:Upgrade
