# ============================================================
#  bashbasicsbyvk_tpl.sh — THE TEMPLATE PROCESSOR
#
#  Reads  bashbasicsbyvk_<ID>.sh.tpl  and resolves every {placeholder} through the global definer (bashbasicsbyvk_tpl_defs.sh).
#  A screen never types its own layout: it SETS its data and asks for a template by ID.
#
#      _tpl_set NAME VALUE ...                 data for the placeholders (pairs; values may be several rows)
#      _tpl_clear                              forget every value (a screen starts clean)
#      _tpl_section ID SECTION                 PRINT one section (menu_header | menu_body | menu_footer): for screens whose engine draws the
#                                              three parts at different times (the viewport hooks, _mc_menu_n)
#      _tpl_render ID                          PRINT every section, in the order of the file
#      _tpl_build [-p PREFIX] ID SECTION VAR   BUILD the section into VAR instead of printing it (PREFIX starts every row): for a screen that
#                                              paints one block in a single write (Settings). fn / slot placeholders read their text
#                                              from _tpl_set here: nothing is run
#      _tpl_list_header TITLE [ROWS]           PRINT the header of a titled list screen (7P68NA): every auth / api / github / drive / notification list
#      _tpl_footer ID ITEM...                  PRINT the footer section of ID with the keys the chrome draws (_mc_footer items: key:Label, bare keys, "|",
#                                              "#note", or one "@registered" footer): the one call every list / tabbed screen's footer function makes
#      _tpl_check ID                           0 when the file exists and every name in it is defined
#
#  Printing goes through echo, never `builtin echo` (the smart-menu layer records echo to redraw the screen).
#  An empty placeholder prints nothing (no row, no blank row). A blank line in a template is one blank row.
# ============================================================

declare -g  _TPL_DIR; _TPL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
declare -gA _TPL_L=()          # "ID:section:i" -> template row
declare -gA _TPL_N=()          # "ID:section"   -> number of rows
declare -gA _TPL_ORD=()        # ID -> sections in file order
declare -gA _TPL_LOADED=()     # ID -> 1 loaded · 0 no such template
declare -g  _TPL_V="" _TPL_BUF="" _TPL_PFX="" _TPL_PROMPT=""

_tpl_file() { echo "$_TPL_DIR/bashbasicsbyvk_$1.sh.tpl"; }

_tpl_set() { while (( $# >= 2 )); do _TPL_VAL[$1]="$2"; shift 2; done; }
_tpl_clear() { _TPL_VAL=(); _TPL_FOOTER_ARR=(); }

# _tpl_load ID   parse the file once.  Rows starting with # are comments; a row that is only $name opens a section; blank rows at the END of a
# section are formatting (the next marker follows them) and are dropped, blank rows at the start and in the middle are rows.
_tpl_load() {
  local id="$1" f line sec="" n=0 i
  [ -n "${_TPL_LOADED[$id]-}" ] && { [ "${_TPL_LOADED[$id]}" = 1 ]; return; }
  f="$(_tpl_file "$id")"
  [ -r "$f" ] || { _TPL_LOADED[$id]=0; return 1; }
  _TPL_ORD[$id]=""
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" == "#"* ]] && continue
    if [[ "$line" =~ ^\$([a-z_]+)[[:space:]]*$ ]]; then
      [ -n "$sec" ] && _tpl_trim_tail "$id" "$sec"
      sec="${BASH_REMATCH[1]}"; _TPL_N[$id:$sec]=0; _TPL_ORD[$id]+="$sec "
      continue
    fi
    [ -n "$sec" ] || continue
    n="${_TPL_N[$id:$sec]}"; _TPL_L[$id:$sec:$n]="$line"; _TPL_N[$id:$sec]=$(( n + 1 ))
  done < "$f"
  [ -n "$sec" ] && _tpl_trim_tail "$id" "$sec"
  _TPL_LOADED[$id]=1
}
_tpl_trim_tail() {
  local n="${_TPL_N[$1:$2]}"
  while (( n > 0 )) && [ -z "${_TPL_L[$1:$2:$(( n - 1 ))]}" ]; do unset "_TPL_L[$1:$2:$(( n - 1 ))]"; n=$(( n - 1 )); done
  _TPL_N[$1:$2]=$n
}

# _tpl_val NAME   -> _TPL_V   the text of a var / text / prompt (what the screen set, else the definer's default); fn / slot: only what was set
_tpl_val() {
  local nm="$1"
  case "${_TPL_KIND[$nm]-}" in
    var)  _TPL_V="${_TPL_VAL[$nm]-${_TPL_SPEC[$nm]}}" ;;
    text|prompt) _TPL_V="${_TPL_SPEC[$nm]}" ;;
    fn|slot) _TPL_V="${_TPL_VAL[$nm]-}" ;;
    *) _TPL_V="${_TPL_VAL[$nm]-}" ;;      # a value a caller keeps for a definer function (nav_path_text ...)
  esac
}

# _tpl_put TEXT   one or several rows, to the screen (print) or to the buffer (build)
_tpl_put() {
  local t="$1" l
  if [ "$_TPL_MODE" = print ]; then echo "$t"; return; fi
  while IFS= read -r l || [ -n "$l" ]; do _TPL_BUF+="${_TPL_PFX}${l}"$'\n'; done <<< "$t"
}

# _tpl_emit NAME   a row that is only {NAME}
_tpl_emit() {
  local nm="$1" fn
  case "${_TPL_KIND[$nm]-}" in
    prompt) _TPL_PROMPT="${_TPL_SPEC[$nm]}" ;;                                   # not a row
    fn)   if [ "$_TPL_MODE" = print ]; then "${_TPL_SPEC[$nm]}"; else _tpl_val "$nm"; [ -n "$_TPL_V" ] && _tpl_put "$_TPL_V"; fi ;;
    slot) if [ "$_TPL_MODE" = print ]; then fn="${_TPL_VAL[$nm]-}"; [ -n "$fn" ] && declare -F "$fn" >/dev/null 2>&1 && "$fn"; else _tpl_val "$nm"; [ -n "$_TPL_V" ] && _tpl_put "$_TPL_V"; fi ;;
    var|text) _tpl_val "$nm"; [ -n "$_TPL_V" ] && _tpl_put "$_TPL_V" ;;
    *) ;;                                                                         # an undefined name prints nothing; tidy_gen --check names it
  esac
  return 0
}

# _tpl_walk MODE ID SECTION
_tpl_walk() {
  local _TPL_MODE="$1" id="$2" sec="$3" i n line cond rest out
  _tpl_load "$id" || return 1
  n="${_TPL_N[$id:$sec]-}"; [ -n "$n" ] || return 1
  for (( i=0; i<n; i++ )); do
    line="${_TPL_L[$id:$sec:$i]}"
    if [[ "$line" == "?"* ]]; then                                                # ?name rest: only when {name} is not empty
      cond="${line#\?}"; cond="${cond%% *}"; rest="${line#\?"$cond"}"; rest="${rest# }"
      _tpl_val "$cond"; [ -n "$_TPL_V" ] || continue
      line="$rest"
    fi
    if [ -z "$line" ]; then _tpl_put ""; continue; fi
    if [[ "$line" =~ ^\{([a-z_]+)\}$ ]]; then _tpl_emit "${BASH_REMATCH[1]}"; continue; fi
    out=""; rest="$line"
    while [[ "$rest" =~ ^([^\{]*)\{([a-z_]+)\}(.*)$ ]]; do
      out+="${BASH_REMATCH[1]}"; _tpl_val "${BASH_REMATCH[2]}"; out+="$_TPL_V"; rest="${BASH_REMATCH[3]}"
    done
    _tpl_put "$out$rest"
  done
  return 0
}

_tpl_section() { _tpl_walk print "$1" "$2"; }
_tpl_render()  { local s; _tpl_load "$1" || return 1; for s in ${_TPL_ORD[$1]}; do _tpl_walk print "$1" "$s"; done; }
_tpl_build() {                                  # _tpl_build [-p PREFIX] ID SECTION VAR
  local _TPL_PFX=""; [ "${1:-}" = -p ] && { _TPL_PFX="$2"; shift 2; }
  local _tb_var="$3"; _TPL_BUF=""
  _tpl_walk build "$1" "$2" || return 1
  printf -v "$_tb_var" '%s' "$_TPL_BUF"
}

# _tpl_list_header TITLE [ROWS]   the header of a titled list screen (template 7P68NA): blank, TITLE, ROWS (the state / "empty" note), the filter row
_tpl_list_header() { _tpl_clear; _tpl_set menu_name "$1" menu_description "${2:-}"; _tpl_section 7P68NA menu_header; }
_tpl_footer() { local _tf_id="$1"; shift; _tpl_clear; _TPL_FOOTER_ARR=("$@"); _tpl_set footer_style chrome; _tpl_section "$_tf_id" menu_footer; }

# _tpl_check ID   the file is there and every {name} / ?name / $section in it is defined (the static suite runs the same rule in python)
_tpl_check() {
  local id="$1" s i n line nm rc=0
  _tpl_load "$id" || { echo "template $id: no file $(_tpl_file "$id")"; return 1; }
  for s in ${_TPL_ORD[$id]}; do
    [ -n "${_TPL_SECTION[$s]-}" ] || { echo "template $id: section \$$s is not defined"; rc=1; }
    n="${_TPL_N[$id:$s]}"
    for (( i=0; i<n; i++ )); do
      line="${_TPL_L[$id:$s:$i]}"
      while [[ "$line" =~ \{([a-z_]+)\} ]]; do
        nm="${BASH_REMATCH[1]}"; [ -n "${_TPL_KIND[$nm]-}" ] || { echo "template $id: {$nm} is not defined"; rc=1; }
        line="${line#*\{"$nm"\}}"
      done
    done
  done
  return $rc
}
