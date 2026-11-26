# bashbasicsbyvk_xlr8.sh - XLR8, the workflow language of bashbasicsbyvk: reading and writing it. Recording / running it: bashbasicsbyvk_wf.sh.
# The language, for the person, is bashbasicsbyvk_xlr8.txt (shown by  wf > How to write xlr8).
# One step per line (or several on a line with  =>  between them).  A parsed step is one index of these arrays:
#   _XL_T type (from on goto cmd where select input confirm)   _XL_Q question hint   _XL_A argument   _XL_K name|path|option
#   _XL_V the values, one per line   _XL_S the step as written (for messages)

declare -ga _XL_T=() _XL_Q=() _XL_A=() _XL_K=() _XL_V=() _XL_S=()
declare -g _XL_ERR="" _XL_OUT="" _XL_REST=""

_xl_trim() { _XL_OUT="$1"; _XL_OUT="${_XL_OUT#"${_XL_OUT%%[![:space:]]*}"}"; _XL_OUT="${_XL_OUT%"${_XL_OUT##*[![:space:]]}"}"; }
_xl_quote() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/ }"; _XL_OUT="\"$s\""; }
# _xl_value TEXT : the first value of TEXT ("quoted" or bare up to  ,  / next key=) -> _XL_OUT, what follows -> _XL_REST
_xl_value() {
  local s="$1" i c out=""
  _xl_trim "$s"; s="$_XL_OUT"
  if [ "${s:0:1}" = '"' ]; then
    for (( i=1; i<${#s}; i++ )); do
      c="${s:i:1}"
      if [ "$c" = "\\" ]; then i=$(( i + 1 )); out+="${s:i:1}"
      elif [ "$c" = '"' ]; then _XL_REST="${s:i+1}"; _XL_OUT="$out"; return 0
      else out+="$c"; fi
    done
    return 1
  fi
  if [[ "$s" =~ ^(.*[^[:space:],])[[:space:],]+((name|path|option)[[:space:]]*=.*)$ ]]; then out="${BASH_REMATCH[1]}"; _XL_REST="${BASH_REMATCH[2]}"
  else out="$s"; _XL_REST=""; fi
  _xl_trim "$out"
}
# _xl_pairs "name=a name=b"  -> _XL_PK (the key), _XL_PV (values, one per line), _XL_REST (an  as SET  tail)
_xl_pairs() {
  local s="$1"
  _XL_PK=""; _XL_PV=""
  while :; do
    _xl_trim "$s"; s="${_XL_OUT#,}"; _xl_trim "$s"; s="$_XL_OUT"
    [[ "$s" =~ ^(name|names|path|option|options)[[:space:]]*=(.*)$ ]] || break
    _XL_PK="${BASH_REMATCH[1]%s}"
    _xl_value "${BASH_REMATCH[2]}" || return 1
    [ -n "$_XL_OUT" ] || return 1
    _XL_PV+="${_XL_PV:+$'\n'}$_XL_OUT"
    s="$_XL_REST"
    # further bare / quoted values of the same key:  options="A","B"
    while _xl_trim "$s"; [ "${_XL_OUT:0:1}" = "," ]; do
      s="${_XL_OUT:1}"; _xl_trim "$s"; [[ "$_XL_OUT" =~ ^(name|names|path|option|options)[[:space:]]*= ]] && break
      _xl_value "$s" || return 1; _XL_PV+=$'\n'"$_XL_OUT"; s="$_XL_REST"
    done
  done
  _XL_REST="$s"
}
_xl_add() {   # TYPE QUESTION ARG KEY VALUES SOURCE
  _XL_T+=("$1"); _XL_Q+=("$2"); _XL_A+=("$3"); _XL_K+=("$4"); _XL_V+=("$5"); _XL_S+=("$6")
}
# one segment of a line.  rc 1 + _XL_ERR = not understood
_xl_segment() {
  local s w rest q="" low
  _xl_trim "$1"; s="$_XL_OUT"
  [ -n "$s" ] || return 0
  low="${s,,}"; w="${low%%[[:space:]]*}"; rest="${s:${#w}}"; _xl_trim "$rest"; rest="$_XL_OUT"
  case "$low" in
    start|end|cmd) return 0 ;;
    "confirm auto"|"auto confirm"|"auto confirm?"|"auto confirm"[?\ ]*yes*) _xl_add confirm "" auto "" "" "$s"; return 0 ;;
  esac
  if [[ "$low" =~ (^|[[:space:]\"\?])where[[:space:]]+(name|names|path|option|options)[[:space:]]*= ]]; then
    local m="${BASH_REMATCH[0]}" head
    head="${low%%"$m"*}"; q="${s:0:${#head}}${BASH_REMATCH[1]}"
    _xl_trim "$q"; q="$_XL_OUT"
    [ "${q:0:1}" = '"' ] && { _xl_value "$q" || { _XL_ERR="a quote is not closed"; return 1; }; q="$_XL_OUT"; }
    rest="${s:${#head}}"; rest="${rest#*[wW][hH][eE][rR][eE]}"
    _xl_pairs "$rest" && [ -n "$_XL_PV" ] && [ -z "$_XL_REST" ] || { _XL_ERR="did not understand the part after 'where'"; return 1; }
    _xl_add where "$q" "" "$_XL_PK" "$_XL_PV" "$s"; return 0
  fi
  case "$w" in
    from|on|goto)
      [ -n "$rest" ] || { _XL_ERR="'$w' needs a value"; return 1; }
      _xl_value "$rest" || { _XL_ERR="a quote is not closed"; return 1; }
      _xl_add "$w" "" "$_XL_OUT" "" "" "$s" ;;
    select)
      case "${rest,,}" in
        all) _xl_add select "" all "" "" "$s" ;;
        "all except "*) rest="${rest:11}"; _xl_pairs "$rest" && [ -n "$_XL_PV" ] || { _XL_ERR="select all except name=\"...\""; return 1; }
                        _xl_add select "" except "$_XL_PK" "$_XL_PV" "$s" ;;
        name*|path*) _xl_pairs "$rest" && [ -n "$_XL_PV" ] || { _XL_ERR="select name=\"...\""; return 1; }
                     _xl_add select "" only "$_XL_PK" "$_XL_PV" "$s" ;;
        *) _XL_ERR="select all  ·  select name=\"...\""; return 1 ;;
      esac ;;
    input)
      if [ "${rest:0:1}" = '"' ]; then _xl_value "$rest" || { _XL_ERR="a quote is not closed"; return 1; }; q="$_XL_OUT"; _xl_trim "$_XL_REST"; rest="$_XL_OUT"; fi
      case "${rest,,}" in
        ask|"from user") _xl_add input "$q" ask "" "" "$s" ;;
        default) _xl_add input "$q" default "" "" "$s" ;;
        value*=*) _xl_value "${rest#*=}" || { _XL_ERR="a quote is not closed"; return 1; }; _xl_add input "$q" value "" "$_XL_OUT" "$s" ;;
        *) _XL_ERR="input \"question\" ask | default | value=\"text\""; return 1 ;;
      esac ;;
    cmd|*)
      [ "$w" = cmd ] || rest="$s"
      _XL_PK=""; _XL_PV=""
      if [ "${rest:0:1}" = '"' ]; then _xl_value "$rest" || { _XL_ERR="a quote is not closed"; return 1; }; w="$_XL_OUT"; _xl_trim "$_XL_REST"; rest="$_XL_OUT"
      else
        w="${rest%%[[:space:]]*}"; rest="${rest:${#w}}"; _xl_trim "$rest"; rest="$_XL_OUT"
        [ "$w" = "d-" ] && [ -n "$rest" ] && { w="d- $rest"; rest=""; }          # d- set1
      fi
      if [ -n "$rest" ] && [[ "$rest" =~ ^(name|names|path)[[:space:]]*= ]]; then
        _xl_pairs "$rest" || { _XL_ERR="did not understand the names"; return 1; }; rest="$_XL_REST"
      fi
      _xl_trim "$rest"; rest="$_XL_OUT"
      [ -z "$rest" ] || [[ "$rest" =~ ^as[[:space:]] ]] || { _XL_ERR="not understood: $s"; return 1; }
      [[ "$w" =~ ^[0-9][0-9,-]*$ ]] && { _XL_ERR="a bare number breaks when the list changes: write  where name=\"...\"  or  where option=\"...\""; return 1; }
      _xl_add cmd "" "$w" "$_XL_PK" "$_XL_PV${rest:+$'\t'$rest}" "$s" ;;
  esac
  return 0
}
# _xl_load FILE -> the arrays.  rc 1: _XL_ERR says which line
_xl_load() {
  local line n=0 i c seg inq
  _XL_T=(); _XL_Q=(); _XL_A=(); _XL_K=(); _XL_V=(); _XL_S=(); _XL_ERR=""
  [ -r "$1" ] || { _XL_ERR="the file cannot be opened: $1"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    n=$(( n + 1 )); line="${line%$'\r'}"; seg=""; inq=0
    for (( i=0; i<${#line}; i++ )); do
      c="${line:i:1}"
      if (( inq )); then
        [ "$c" = "\\" ] && { seg+="${line:i:2}"; i=$(( i + 1 )); continue; }
        [ "$c" = '"' ] && inq=0
      else
        [ "$c" = '"' ] && inq=1
        [ "$c" = "#" ] && { _xl_trim "$seg"; [ -z "$_XL_OUT" ] && break; }        # a comment starts a segment
        if [ "${line:i:2}" = "=>" ]; then _xl_segment "$seg" || { _XL_ERR="line $n: $_XL_ERR"; return 1; }; seg=""; i=$(( i + 1 )); continue; fi
      fi
      seg+="$c"
    done
    _xl_segment "$seg" || { _XL_ERR="line $n: $_XL_ERR"; return 1; }
  done < "$1"
  (( ${#_XL_T[@]} )) || { _XL_ERR="there are no steps"; return 1; }
  return 0
}
