# bashbasicsbyvk_wf.sh - workflows: start_record · stop_record · wf · wf NAME.  The language is read by bashbasicsbyvk_xlr8.sh.
# ════════════════════════════════════════════════════════════════════════════
#  Every question of the app is answered in one of a few places; each calls ONE hook here, only while BVK_WF_DIR is set:
#     _wf_list     the list screens (main, sw ...)        _wf_pick   the "pick items" screen
#     _wf_prompt   typed lines and numbered menus         _wf_box    yes/no and choice boxes
#     _wf_confirm  the "type this number" gate            _wf_trip   something failed
#  A hook returns 0 = "answered (recording never does)", 1 = ask the person.
#  State lives in FILES (BVK_WF_DIR: mode, steps, at, start, name, screen): tools run in subshells, and  cd  replaces the app by a shell.
#  THE GUARD: an answer is only given to the kind of question (and the question text) it was recorded for; anything else stops the run.
#  IF:   "if asked / option / screen ... else ... end if" is decided when the app asks its NEXT question (_wf_ctx says what that is).
#  {$name}: a value given when the run starts (wf NAME name=value, or asked then); the steps use it: input "Q" value="{$name}".
# ════════════════════════════════════════════════════════════════════════════

declare -g _WF_HOME="${_WF_HOME:-${BVK_WF_HOME:-$HOME/.bashbasicsbyvk/workflows}}"    # the app sets it first (browse.sh); this covers the file sourced alone
declare -g _WF_ANSWER="" _WF_MUTE=0
declare -g _WF_NEVER=" cc print tidy loadtime start_record stop_record "   # tools about the app, not steps of a task
declare -g _WF_CK="" _WF_CQ="" _WF_FLOW=0   # what the app asks NOW (list | menu | input | pick | confirm) and its text: the 'if' steps read it
declare -ga _WF_WQ=() _WF_WS=() _WF_WV=() _WF_WE=()   # bashbasicsbyvk_wf_when.txt: question, setting, asked only when, whole-question flag
declare -g _WF_WI=0 _WF_WLOADED=0 _WF_POS="" _WF_PBAD=""
declare -ga _WF_PL=()
declare -gA _WF_HAND=()
declare -gA _WF_ARGV=()                     # the {$name} values while a run starts (the run then keeps them in BVK_WF_DIR/var.NAME)

_wf_mode() { _WF_M=""; [ -n "${BVK_WF_DIR:-}" ] && [ -r "$BVK_WF_DIR/mode" ] && IFS= read -r _WF_M < "$BVK_WF_DIR/mode"; [ "${_WF_MUTE:-0}" = 0 ] && [ -n "$_WF_M" ]; }
_wf_get() { _WF_G=""; [ -r "$BVK_WF_DIR/$1" ] && IFS= read -r _WF_G < "$BVK_WF_DIR/$1"; return 0; }
_wf_set() { printf '%s\n' "$2" > "$BVK_WF_DIR/$1"; }
_wf_off() { [ -n "${BVK_WF_DIR:-}" ] && [ -d "$BVK_WF_DIR" ] && rm -rf -- "$BVK_WF_DIR"; unset BVK_WF_DIR; return 0; }
_wf_plain() {   # a row as words: no colours, no "N)" / mark / arrow
  local t="$1"
  declare -F _vp_strip_ansi >/dev/null 2>&1 && { _vp_strip_ansi "$t"; t="$_vp_plain"; }
  _xl_trim "$t"; t="$_XL_OUT"
  [[ "$t" =~ ^[0-9A-Za-z]{1,3}\)[[:space:]]+(.*)$ ]] && t="${BASH_REMATCH[1]}"
  case "$t" in "[ ] "*|"[x] "*|"[o] "*) t="${t:4}" ;; esac
  t="${t%›}"; t="${t%(default)}"; _xl_trim "$t"
}
_wf_key() {   # comparable form of a question / option: letters only, no [Default: ...]
  local t="${1,,}"
  while [[ "$t" == *"["*"]"* ]]; do t="${t%%\[*}${t#*\]}"; done
  _XL_OUT="${t//[^a-z]/}"
}
# _wf_index TARGET LABEL...  -> _WF_I (0-based), rc 1 none, rc 2 more than one.  Exact, then without case, then the part before a double space.
_wf_index() {
  local want="$1" pass i lab hits; shift
  local -a L=("$@")
  for pass in 1 2 3; do
    hits=0
    for i in "${!L[@]}"; do
      lab="${L[$i]}"
      case $pass in
        1) [ "$lab" = "$want" ] || continue ;;
        2) [ "${lab,,}" = "${want,,}" ] || continue ;;
        3) lab="${lab%%  *}"; [ "${lab,,}" = "${want%%  *}" ] || [ "${lab,,}" = "${want,,}" ] || continue ;;
      esac
      hits=$(( hits + 1 )); _WF_I=$i
    done
    (( hits == 1 )) && return 0
    (( hits > 1 )) && return 2
  done
  return 1
}

# ── failure: say what, where and why; the screen stays with the person ──────
_wf_fail() {
  local why="$1" at n name src=""
  _wf_get at; at="${_WF_G:-0}"; _wf_get name; name="$_WF_G"
  n=${#_XL_T[@]}; (( at < n )) && src="${_XL_S[$at]}"
  (( at >= n && n > 0 )) && { at=$(( n - 1 )); src="${_XL_S[$at]}"; }
  echo
  echo "❌ Workflow '$name' stopped at step $(( at + 1 )) of $n"
  echo "   step:   $src"
  echo "   reason: $why"
  echo "   Steps before it are done; nothing after it was run. You are in control now."
  _wf_off
}
# _wf_trip "reason": the app hit a failure.  Running: stop.  Recording: forget the step that caused a refused command.
_wf_trip() {
  _wf_mode || return 0
  if [ "$_WF_M" = play ]; then _wf_load_run || return 0; local a; _wf_get at; a="${_WF_G:-0}"; (( a > 0 )) && _wf_set at $(( a - 1 )); _wf_fail "$1"
  elif [ "${2:-}" = drop ]; then sed -i.bak '$d' "$BVK_WF_DIR/steps" 2>/dev/null; fi
  return 0
}

# ── recording ──────────────────────────────────────────────────────────────
_wf_emit() { printf '%s\n' "$1" >> "$BVK_WF_DIR/steps"; }
# ── the questions the app does not always ask (bashbasicsbyvk_wf_when.txt) ─
_wf_when_load() {   # once
  local f q s v
  (( _WF_WLOADED )) && return 0
  _WF_WLOADED=1
  f="$(_wf_find_doc bashbasicsbyvk_wf_when.txt)" || return 0
  while IFS='|' read -r q s v; do
    _xl_trim "$q"; q="$_XL_OUT"
    case "$q" in ''|'#'*) continue ;; esac
    if [ "${q:0:1}" = "=" ]; then _WF_WE+=(1); q="${q:1}"; else _WF_WE+=(0); fi
    _WF_WQ+=("$q"); _xl_trim "$s"; _WF_WS+=("$_XL_OUT"); _xl_trim "$v"; _WF_WV+=("$_XL_OUT")
  done < "$f"
}
_wf_when_find() {   # QUESTION -> _WF_WI = its line; rc 1 = this question is always asked
  local i k
  _wf_when_load
  for i in "${!_WF_WQ[@]}"; do
    if (( _WF_WE[i] )); then _wf_key "${_WF_WQ[$i]}"; k="$_XL_OUT"; _wf_key "$1"; [ -n "$k" ] && [ "$_XL_OUT" = "$k" ] || continue
    else _wf_has "${_WF_WQ[$i]}" "$1" || continue; fi
    _WF_WI=$i; return 0
  done
  return 1
}
_wf_when_why() {   # LINE -> _XL_OUT: why the question may be missing (the setting and what it is set to now)
  local s="${_WF_WS[$1]}" v="${_WF_WV[$1]}"
  if [[ "$s" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then _XL_OUT="Settings: $s is '${!s:-}', it asks only on '$v'"; else _XL_OUT="asked only when $v"; fi
}
# PREFIX"QUESTION" REST as a step.  A question that Settings or the state can switch off goes inside  if asked "..." ... end if  (named by
# the short text of the list, so a question with a file name in it still fits on the next run)
_wf_emit_q() {   # QUESTION PREFIX REST [COMMENT line for just above the step]
  if _wf_when_find "$1"; then
    _xl_quote "${_WF_WQ[$_WF_WI]}"; _wf_emit "if asked $_XL_OUT"; [ -n "${4:-}" ] && _wf_emit "  $4"; _wf_emit "  $2$_XL_OUT $3"; _wf_emit "end if"
  else _xl_quote "$1"; [ -n "${4:-}" ] && _wf_emit "$4"; _wf_emit "$2$_XL_OUT $3"; fi
}
# ── at stop_record: two optional passes over the recorded steps, each a multi-select ──────────────────
# a multi-select over the steps of FILE that TESTFN accepts (TESTFN STEP PREVIOUS-LINE) -> _WF_HAND[line]=1.  rc 1 = none to offer, none chosen, or u
_wf_pass_menu() {   # FILE TESTFN TITLE QUESTION
  local f="$1" test="$2" line t prev="" n=0 k=0 picked=""
  local -a rows=() at=()
  _WF_HAND=()
  while IFS= read -r line; do
    n=$(( n + 1 )); t="${line#"${line%%[![:space:]]*}"}"
    if "$test" "$t" "$prev"; then k=$(( k + 1 )); at[k]=$n; rows+=("$k:${t:0:70}"); fi
    prev="$t"
  done < "$f"
  (( k )) || return 1
  _bvk_menu picked -m -t "$3" -i "✋" -q "$4" "${rows[@]}" || return 1
  [ -n "$picked" ] || return 1
  for k in $picked; do [ -n "${at[$k]:-}" ] && _WF_HAND[${at[$k]}]=1; done
  (( ${#_WF_HAND[@]} ))
}
# every line chosen above is replaced by what REWRITEFN prints for it (REWRITEFN STEP PREVIOUS-LINE)
_wf_pass_apply() {   # FILE REWRITEFN
  local f="$1" fn="$2" line t prev="" ind n=0
  while IFS= read -r line; do
    n=$(( n + 1 )); ind="${line%%[![:space:]]*}"; t="${line#"$ind"}"
    if [ -n "${_WF_HAND[$n]:-}" ]; then printf '%s' "$ind"; "$fn" "$t" "$prev"; else printf '%s\n' "$line"; fi
    prev="$t"
  done < "$f" > "$f.new" && mv "$f.new" "$f"
}
# 1. a choice made by a name, with the position the recorder saw above it: it can be taken by position instead (row 1 = the newest, whatever it is called next time)
_wf_pos_re='^(.*(where|except|select))[[:space:]]+(name|names|path|option|options)[[:space:]]*='
_wf_pos_test() { [[ "$2" =~ ^#\ position\ [0-9,]+\ of\ [0-9]+$ ]] && [[ "$1" =~ $_wf_pos_re ]]; }
_wf_pos_rewrite() { [[ "$1" =~ $_wf_pos_re ]]; local pre="${BASH_REMATCH[1]}"; [[ "$2" =~ ^#\ position\ ([0-9,]+)\ of ]]; printf '%s number=%s\n' "$pre" "${BASH_REMATCH[1]}"; }
_wf_position_pass() {   # STEPSFILE (Enter alone, or u: nothing changes)
  _wf_pass_menu "$1" _wf_pos_test "Pick by position?" "These steps pick by a name (a version, a file). Which should pick by position instead: the same row or option number next time, whatever it is called?" && _wf_pass_apply "$1" _wf_pos_rewrite
  return 0
}
# 2. the steps that name the exact rows you used (select name=..., a command or an open on a name): they can wait for you each time
_wf_by_name() {   # TRIMMED-STEP
  case "$1" in 'select ask') return 1 ;; select*) return 0 ;; esac
  [[ "$1" =~ ^(cmd|where)[[:space:]].*[[:space:]](name|path)= || "$1" =~ ^where[[:space:]]+(name|path)= ]]
}
_wf_hand_test() { _wf_by_name "$1"; }
_wf_hand_rewrite() { local t="$1"; case "$t" in select*) printf 'select ask\n' ;; *) _xl_quote "recorded: $t"; printf 'pause %s\n' "$_XL_OUT" ;; esac; }
_wf_manual_pass() {   # STEPSFILE: the chosen steps become  select ask  /  pause "..."   (Enter alone, or u: nothing changes)
  _wf_pass_menu "$1" _wf_hand_test "Leave steps to you?" "These steps name the exact files you used. Which should wait for you each time (you pick, the workflow goes on)?" && _wf_pass_apply "$1" _wf_hand_rewrite
  return 0
}
_wf_start_record() {
  _wf_mode && { echo "🔴  Already ${_WF_M/rec/recording}: type stop_record first"; return 0; }
  _cm_ctx_find 2>/dev/null
  [ "${_CM_MAP:-main}" = main ] || { echo "🔴  Start recording from the main file list (u / q until you are there)"; return 0; }
  _wf_off
  BVK_WF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bvk-wf.XXXXXX")" || return 0
  export BVK_WF_DIR
  _wf_set mode rec; _wf_set screen ""
  printf 'start\n' > "$BVK_WF_DIR/steps"
  _xl_quote "$path"; _wf_emit "from $_XL_OUT"
  echo "🔴 Recording. Do your task once, then type  stop_record"
}
_wf_stop_record() {
  _wf_mode && [ "$_WF_M" = rec ] || { echo "📜  Nothing is being recorded (start_record starts)"; return 0; }
  if [ "$(grep -cvE '^(start|from |on )' "$BVK_WF_DIR/steps")" = 0 ]; then echo "📜  No steps were recorded: recording ended"; _wf_off; return 0; fi
  local _wf_name="" _wf_ans="" _wf_file
  _WF_MUTE=1
  while :; do
    if ! _bvk_read _wf_name "Name for this workflow (u = keep recording): " || [ "$_wf_name" = u ] || [ -z "$_wf_name" ]; then
      echo "🔴 Still recording. Type stop_record when you are done."; break
    fi
    if ! [[ "$_wf_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then echo "🔴  Use letters, numbers, - _ . (no spaces)"; continue; fi
    _wf_file="$_WF_HOME/$_wf_name.xlr8"
    if [ -e "$_wf_file" ]; then _bvk_yn _wf_ans "Replace the workflow '$_wf_name'?" || continue; [ "$_wf_ans" = y ] || continue; fi
    _wf_position_pass "$BVK_WF_DIR/steps"; _wf_manual_pass "$BVK_WF_DIR/steps"
    mkdir -p "$_WF_HOME" && { cat "$BVK_WF_DIR/steps"; printf 'goto start\nend\n'; } > "$_wf_file" || { echo "❌ Could not save $_wf_file"; break; }
    echo "💫 Saved '$_wf_name'. Run it:  wf $_wf_name   ·   see or edit it:  wf"
    _wf_off; break
  done
  _WF_MUTE=0
}
# the app started while a recording is alive: the person did  cd  (a shell) and then  o
_wf_resume() {
  _wf_mode || { unset BVK_WF_DIR; return 0; }
  [ "$_WF_M" = rec ] || { _wf_off; return 0; }
  _wf_emit "cmd o"; _wf_set screen ""
  echo "🔴 Still recording (type stop_record to finish)"
}

# ── names of the rows on a list screen ─────────────────────────────────────
_wf_rows() {   # -> _WF_ROWS[0..n-1] = the name of each row, _WF_PATHS[..] = its path ('' = not a file row)
  local i t
  _WF_ROWS=(); _WF_PATHS=()
  _vp_count
  for (( i=1; i<=_vp_n; i++ )); do
    t=""
    if [ -n "${_vp_rowtext_fn:-}" ]; then $_vp_rowtext_fn "$i"; _wf_plain "$_vp_line"; t="$_XL_OUT"; _WF_PATHS+=("")
    elif [ "${_vp_mode:-}" = imaginary ]; then t="${imaginary_map[$((i-1))]}"; _WF_PATHS+=("")
    else t="${items[$((i-1))]}"; _WF_PATHS+=("$t"); t="${t%/}"; t="${t##*/}"; t="${t%.swlink}"; fi
    _WF_ROWS+=("$t")
  done
}
# _wf_names "1,3-5"  -> _XL_OUT = ' name="a" name="b"' (path= when two rows share a name), rc 1 = no name for a number
_wf_names() {
  local n i out="" dup
  local -a nums=()
  read -ra nums <<<"$(parse_selection "${1// /}" "${#_WF_ROWS[@]}" 2>/dev/null | tr '\n' ' ')"
  (( ${#nums[@]} )) || return 1
  _WF_POS="${nums[*]}"; _WF_POS="${_WF_POS// /,}"
  for n in "${nums[@]}"; do
    i=$(( n - 1 )); (( i >= 0 )) && [ -n "${_WF_ROWS[$i]:-}" ] || return 1
    _wf_index "${_WF_ROWS[$i]}" "${_WF_ROWS[@]}"; dup=$?
    if (( dup == 2 )) && [ -n "${_WF_PATHS[$i]}" ]; then _xl_quote "${_WF_PATHS[$i]}"; out+=" path=$_XL_OUT"
    else _xl_quote "${_WF_ROWS[$i]}"; out+=" name=$_XL_OUT"; fi
  done
  _XL_OUT="$out"
}
# rows named by a step -> _XL_OUT = "1,3"  (rc 1: _WF_WHY)
# a position: 3 · first · last · -1 (the last) · -2 ...  COUNT = how many there are -> _WF_I (0-based).  rc 1 = there is no such position
_wf_pos() {   # VALUE COUNT
  local v="${1,,}" n="$2"
  v="${v// /}"
  case "$v" in first) v=1 ;; last) v=-1 ;; esac
  [[ "$v" =~ ^-?[0-9]+$ ]] || return 1
  (( v < 0 )) && v=$(( n + v + 1 ))
  (( v >= 1 && v <= n )) || return 1
  _WF_I=$(( v - 1 ))
}
# "1,3" · "2-4" · "last" · "-2" · "first", COUNT things -> _WF_PL (0-based indexes).  rc 1 = _WF_PBAD is the part that is not there
_wf_pos_list() {   # VALUE COUNT
  local v="${1// /}" n="$2" part a b j
  local -a parts=()
  _WF_PL=(); _WF_PBAD=""
  IFS=, read -ra parts <<<"$v"
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      a="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"
      (( a >= 1 && b >= a && b <= n )) || { _WF_PBAD="$part"; return 1; }
      for (( j=a; j<=b; j++ )); do _WF_PL+=($(( j - 1 ))); done
    else _wf_pos "$part" "$n" || { _WF_PBAD="$part"; return 1; }; _WF_PL+=("$_WF_I"); fi
  done
  (( ${#_WF_PL[@]} )) || { _WF_PBAD="$1"; return 1; }
}
_wf_numbers() {   # KEY VALUES
  local key="$1" v out="" rc j
  while IFS= read -r v; do
    _wf_subst "$v"; v="$_XL_OUT"
    if [ "$key" = number ]; then   # 1 · 1,3 · 2-4 · last · -2 : the rows by position
      _wf_pos_list "$v" "${#_WF_ROWS[@]}" || { _WF_WHY="no row number '$_WF_PBAD' here (the list has ${#_WF_ROWS[@]} rows)"; return 1; }
      for j in "${_WF_PL[@]}"; do out+="${out:+,}$(( j + 1 ))"; done
      continue
    fi
    if [ "$key" = path ]; then _wf_index "$v" "${_WF_PATHS[@]}"; rc=$?; else _wf_index "$v" "${_WF_ROWS[@]}"; rc=$?; fi
    if (( rc )); then
      local seen; seen="$(printf '%s, ' "${_WF_ROWS[@]:0:8}")"
      (( rc == 2 )) && _WF_WHY="more than one row is called '$v'" || _WF_WHY="no row called '$v' here (rows: ${seen%, })"
      return 1
    fi
    out+="${out:+,}$(( _WF_I + 1 ))"
  done <<<"$2"
  _XL_OUT="$out"
}

# ── running ────────────────────────────────────────────────────────────────
_wf_load_run() {
  _xl_load "$BVK_WF_DIR/steps" || { echo "❌ Workflow cannot be read: $_XL_ERR"; _wf_off; return 1; }
}
_wf_run() {   # NAME [VALUES for the {$name}s: name=value ... | value ...]
  local name="$1" args="${2:-}" file i start v a
  if _wf_mode; then
    if [ "$_WF_M" = rec ]; then echo "🔴  Finish first (stop_record). To run one workflow from another, add the line  wf NAME  to the saved workflow (wf, then edit)"
    else echo "🔴  A workflow is running. To run one from another, make  wf NAME  a step of the workflow"; fi
    return 0
  fi
  file="$_WF_HOME/${name%.xlr8}.xlr8"
  [ -r "$file" ] || { echo "❌ No workflow called '$name' (type wf to see them)"; return 0; }
  _xl_load "$file" || { echo "❌ '$name' has a mistake, nothing was run. $_XL_ERR"; return 0; }
  _WF_FLAT=""
  if _wf_has_call; then   # one list: the called workflows' steps are put in place of the  wf NAME  steps
    local flat rc
    _WF_FLAT=$'start\n'
    _wf_flatten "$name" "${name%.xlr8}" 1 "" || { echo "❌ '$name': $_XL_ERR. Nothing was run."; _WF_FLAT=""; return 0; }
    flat="$(mktemp "${TMPDIR:-/tmp}/bvk-wfflat.XXXXXX")" || { _WF_FLAT=""; return 0; }
    printf '%s' "$_WF_FLAT" > "$flat"; _xl_load "$flat"; rc=$?; rm -f "$flat"
    (( rc == 0 )) || { echo "❌ '$name' has a mistake once its calls are put in, nothing was run. $_XL_ERR"; _WF_FLAT=""; return 0; }
  fi
  _wf_collect "$args" || { _WF_ARGV=(); _WF_FLAT=""; return 0; }
  start="$path"
  for i in "${!_XL_T[@]}"; do
    [ "${_XL_T[$i]}" = from ] || continue
    _wf_subst "${_XL_A[$i]}"; a="$_XL_OUT"
    case "$a" in
      here|current_path|navigation_path) ;;
      *) [ -d "$a" ] || { echo "❌ '$name' starts in a folder that is gone: $a. Nothing was run."; _WF_ARGV=(); _WF_FLAT=""; return 0; }
         path="$a"; group_prefix=""; force_show=false ;;
    esac
  done
  _wf_off
  BVK_WF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bvk-wf.XXXXXX")" || return 0
  export BVK_WF_DIR
  if [ -n "$_WF_FLAT" ]; then printf '%s' "$_WF_FLAT" > "$BVK_WF_DIR/steps"; else cp -- "$file" "$BVK_WF_DIR/steps"; fi
  _WF_FLAT=""
  _wf_set mode play; _wf_set at 0; _wf_set name "${name%.xlr8}"; _wf_set start "$path"; _wf_set screen ""
  if (( ${#_WF_ARGV[@]} )); then for v in "${!_WF_ARGV[@]}"; do printf '%s\n' "${_WF_ARGV[$v]}" > "$BVK_WF_DIR/var.$v"; done; fi
  _WF_ARGV=()
  echo "▶ Running workflow '${name%.xlr8}' from $path"
}
_wf_done() { _wf_get name; [ -t 1 ] && builtin printf '\r\033[K'; echo "✅ Workflow '$_WF_G' finished: all ${#_XL_T[@]} steps."; _wf_off; }
_wf_say() { [ -t 1 ] && builtin printf '\r\033[K'; echo "▶ $(( $1 + 1 ))/${#_XL_T[@]}  ${_XL_S[$1]}"; }
# the next step that needs a prompt -> _WF_AT.  from / on are settled here.  rc 1 = the run is over (done or failed)
_wf_next() {   # SCREEN ('' = not a list screen)
  local at t
  _wf_load_run || return 1
  _wf_get at; at="${_WF_G:-0}"
  while (( at < ${#_XL_T[@]} )); do
    t="${_XL_T[$at]}"
    if [ "$t" = from ]; then at=$(( at + 1 )); continue; fi
    if [ "$t" = on ]; then _wf_set screen "${_XL_A[$at]}"; at=$(( at + 1 )); continue; fi
    case "$t" in if|else|endif) _wf_flow "$at"; at=$_WF_FLOW; continue ;; esac
    if [ "$t" = pause ]; then   # the NEXT question is the person's: say so, step over, and let the app ask them
      _wf_subst "${_XL_Q[$at]}"
      [ -t 1 ] && builtin printf '\r\033[K'; echo "✋ $(( at + 1 ))/${#_XL_T[@]}  Your turn${_XL_OUT:+: $_XL_OUT}. The workflow goes on after your answer."
      at=$(( at + 1 )); _wf_set at "$at"; _wf_set tries 0; _WF_AT=$at
      return 1
    fi
    if [ "$t" = goto ] && [ -n "$1" ]; then
      case "${_XL_A[$at]}" in
        start|path|/*|"~"*) ;;
        *) break ;;
      esac
    fi
    break
  done
  _wf_set at "$at"; _WF_AT=$at
  return 0
}
_wf_advance() { _wf_set at $(( _WF_AT + 1 )); _wf_set tries 0; }
# a question the workflow expected did not come (nothing to delete a second time, no force push needed): only yes/no and confirm
# answers may be passed over, because not giving one can never do anything
_wf_optional() {
  local t="${_XL_T[$1]}" v="${_XL_V[$1],,}"
  [ "$t" = confirm ] || { [ "$t" = where ] && [ "${_XL_K[$1]}" = option ] && { [ "$v" = yes ] || [ "$v" = no ]; }; }
}
_wf_has() {   # WANT GOT: is GOT the question WANT was written for?  (letters only; an empty WANT fits any)
  local want got
  _wf_key "$1"; want="$_XL_OUT"; _wf_key "$2"; got="$_XL_OUT"
  [ -z "$want" ] || [[ "$got" == *"$want"* ]]
}
_wf_asks() { _wf_has "${_XL_Q[$1]}" "$2"; }   # STEP QUESTION: is this the question the step was written for?

# ── {$name}: values the steps use ──────────────────────────────────────────
_wf_var_get() {   # NAME -> _WF_G   (the run's files; while a run starts, _WF_ARGV)
  _WF_G=""
  if [ -n "${BVK_WF_DIR:-}" ] && [ -r "$BVK_WF_DIR/var.$1" ]; then IFS= read -r _WF_G < "$BVK_WF_DIR/var.$1"; else _WF_G="${_WF_ARGV[$1]:-}"; fi
  return 0
}
_wf_subst() {   # TEXT -> _XL_OUT = TEXT with every {$name} replaced by its value (one pass: a value is never read again as a name)
  local s="$1" out=""
  while [[ "$s" == *'{$'* ]]; do
    out+="${s%%'{$'*}"; s="${s#*'{$'}"
    if [[ "$s" =~ ^([A-Za-z_][A-Za-z0-9_]*)\} ]]; then _wf_var_get "${BASH_REMATCH[1]}"; out+="$_WF_G"; s="${s:${#BASH_REMATCH[0]}}"
    else out+='{$'; fi
  done
  _XL_OUT="$out$s"
}
_wf_arg_word() {   # TEXT -> _XL_OUT = its first word (a "quoted" word keeps its spaces), _XL_REST = the rest;  rc 1 = a quote is not closed
  local s="$1" w
  if [ "${s:0:1}" = '"' ]; then _xl_value "$s"; return; fi
  w="${s%%[[:space:]]*}"; _XL_OUT="$w"; _XL_REST="${s:${#w}}"
}
# the values of the {$name}s of the workflow just loaded (_XL_VN) -> _WF_ARGV, from a command line or a call:  name=value ...  or bare values
# in the order the names first appear  (ONE name: the whole rest of the line is its value).  rc 1 + _XL_ERR = refused
_wf_args_parse() {   # ARGS (one string)
  local s="$1" k val i j
  local -a bare=()
  _WF_ARGV=()
  _xl_trim "$s"; s="$_XL_OUT"
  if (( ! ${#_XL_VN[@]} )); then [ -z "$s" ] || { _XL_ERR="this workflow has no {\$name} to fill, so '$s' is not used."; return 1; }; return 0; fi
  if (( ${#_XL_VN[@]} == 1 )) && [ -n "$s" ] && ! [[ "$s" =~ ^${_XL_VN[0]}[[:space:]]*= ]]; then
    val="$s"
    if [ "${s:0:1}" = '"' ] && _xl_value "$s"; then val="$_XL_OUT"; _xl_trim "$_XL_REST"; [ -z "$_XL_OUT" ] || val="$s"; fi
    _WF_ARGV[${_XL_VN[0]}]="${val//$'\n'/ }"; s=""
  fi
  while :; do
    _xl_trim "$s"; s="$_XL_OUT"; [ -n "$s" ] || break
    if [[ "$s" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"; s="${BASH_REMATCH[2]}"
      [[ " ${_XL_VN[*]} " == *" $k "* ]] || { _XL_ERR="this workflow has no {\$$k}."; return 1; }
      _wf_arg_word "$s" || { _XL_ERR="a quote is not closed."; return 1; }
      _WF_ARGV[$k]="$_XL_OUT"
    else
      _wf_arg_word "$s" || { _XL_ERR="a quote is not closed."; return 1; }
      bare+=("$_XL_OUT")
    fi
    s="$_XL_REST"
  done
  i=0
  for (( j=0; j<${#bare[@]}; j++ )); do
    while (( i < ${#_XL_VN[@]} )) && [ -n "${_WF_ARGV[${_XL_VN[$i]}]+x}" ]; do i=$(( i + 1 )); done
    (( i < ${#_XL_VN[@]} )) || { _XL_ERR="more values than names to fill ({\$${_XL_VN[0]}} ...)."; return 1; }
    _WF_ARGV[${_XL_VN[$i]}]="${bare[$j]}"
  done
  return 0
}
# _wf_args_parse, then ask for what is still missing (the question is the text of the first input step that uses the name).  rc 1 = nothing is run
_wf_collect() {   # ARGS (one string)
  local v q val i
  _wf_args_parse "$1" || { echo "❌ ${_XL_ERR^} Nothing was run."; return 1; }
  for v in "${_XL_VN[@]}"; do
    [ -n "${_WF_ARGV[$v]+x}" ] && continue
    q=""
    for i in "${!_XL_T[@]}"; do
      [ "${_XL_T[$i]}" = input ] && [ -n "${_XL_Q[$i]}" ] && [[ "${_XL_S[$i]}" == *"{\$$v}"* ]] && { q="${_XL_Q[$i]}"; break; }
    done
    val=""
    _bvk_read val "${q:-Value for {\$$v}}: " && [ -n "$val" ] || { echo "🔴  No value for {\$$v}: nothing was run."; return 1; }
    _WF_ARGV[$v]="${val//$'\n'/ }"
  done
  return 0
}

# ── wf NAME [values]: a workflow that runs another one ─────────────────────
# At the start of a run every  wf NAME  step is replaced by the steps of that workflow (and of the ones it calls), so the run sees ONE list and
# if / pause / {$name} / the guard work inside it unchanged.  A called workflow keeps its steps but not its  from  (it runs where the caller is)
# and not the  goto start  the recorder writes at its end (the caller decides where to go next).  The values given in the call are put into its
# {$name}s; the names it is not given are shared with the caller (asked once, when the run starts).
declare -g _WF_FLAT=""
_wf_inject() {   # TEXT NAME VALUE -> _XL_OUT: every {$NAME} in TEXT becomes VALUE (made safe inside "...")
  local s="$1" tag="{\$$2}" out="" v
  _xl_quote "$3"; v="${_XL_OUT:1:${#_XL_OUT}-2}"
  while [[ "$s" == *"$tag"* ]]; do out+="${s%%"$tag"*}$v"; s="${s#*"$tag"}"; done
  _XL_OUT="$out$s"
}
_wf_flatten() {   # NAME CHAIN TOP ARGS: append the steps of workflow NAME to _WF_FLAT.  rc 1 + _XL_ERR
  local name="${1%.xlr8}" chain="$2" top="$3" args="$4" file i last s k
  local -a T=() A=() Q=() V=() S=() ch=()
  local -A given=()
  if [ "$top" != 1 ]; then
    [[ " $chain " == *" $name "* ]] && { _XL_ERR="workflows call each other in a circle: ${chain// / → } → $name"; return 1; }
    chain="$chain $name"; read -ra ch <<<"$chain"
    (( ${#ch[@]} <= 9 )) || { _XL_ERR="workflows call each other more than 8 deep: ${chain// / → }"; return 1; }
  fi
  file="$_WF_HOME/$name.xlr8"
  [ -r "$file" ] || { _XL_ERR="there is no workflow called '$name' (type wf to see them)"; return 1; }
  _xl_load "$file" || { _XL_ERR="'$name' has a mistake: $_XL_ERR"; return 1; }
  if [ "$top" != 1 ]; then
    _wf_args_parse "$args" || { _XL_ERR="the call  wf $name $args : $_XL_ERR"; return 1; }
    for k in "${!_WF_ARGV[@]}"; do given[$k]="${_WF_ARGV[$k]}"; done
    _WF_ARGV=()
  fi
  T=("${_XL_T[@]}"); A=("${_XL_A[@]}"); Q=("${_XL_Q[@]}"); V=("${_XL_V[@]}"); S=("${_XL_S[@]}")
  last=$(( ${#T[@]} - 1 ))
  for i in "${!T[@]}"; do
    case "${T[$i]}" in
      from) [ "$top" = 1 ] || continue ;;
      goto) [ "$top" != 1 ] && (( i == last )) && [ "${A[$i]}" = start ] && continue ;;
      call) _wf_flatten "${Q[$i]}" "$chain" 0 "${V[$i]}" || return 1; continue ;;
    esac
    s="${S[$i]}"
    for k in "${!given[@]}"; do _wf_inject "$s" "$k" "${given[$k]}"; s="$_XL_OUT"; done
    _WF_FLAT+="$s"$'\n'
  done
}
_wf_has_call() { local t; for t in "${_XL_T[@]}"; do [ "$t" = call ] && return 0; done; return 1; }

# ── if / else / end if: decided against the question the app asks NOW ──────
_wf_ctx() { _WF_CK="$1"; _WF_CQ="$2"; }   # KIND TEXT   (the options of a menu are in _WF_LABS)
_wf_cond() {   # IDX: does the condition of this 'if' hold now?   (not: the caller turns it round)
  local at="$1" want
  _wf_subst "${_XL_Q[$at]}"; want="$_XL_OUT"
  case "${_XL_A[$at]}" in
    asked)  [ "$_WF_CK" != list ] && _wf_has "$want" "$_WF_CQ" ;;
    option) _wf_index "$want" "${_WF_LABS[@]}"; (( $? == 0 || $? == 2 )) ;;
    screen) [ "$_WF_CK" = list ] && [ "${_WF_CQ,,}" = "${want,,}" ] ;;
  esac
}
_wf_flow() {   # IDX of an if / else / end if -> _WF_FLOW = the index of the step that follows
  local at="$1" yes=0
  case "${_XL_T[$at]}" in
    endif) _WF_FLOW=$(( at + 1 )); return 0 ;;
    else)  _WF_FLOW=$(( ${_XL_J[$at]} + 1 )); return 0 ;;   # the if-side has run: step over the else-side
  esac
  _wf_cond "$at" && yes=1
  [ "${_XL_K[$at]}" = not ] && yes=$(( 1 - yes ))
  if (( yes )); then _wf_say "$at"; _WF_FLOW=$(( at + 1 ))
  else
    local why=""
    if [ "${_XL_A[$at]}" = asked ] && [ -z "${_XL_K[$at]}" ] && _wf_when_find "${_XL_Q[$at]}"; then _wf_when_why "$_WF_WI"; why="  ($_XL_OUT)"; fi
    [ -t 1 ] && builtin printf '\r\033[K'; echo "⏭  $(( at + 1 ))/${#_XL_T[@]}  skipped: ${_XL_S[$at]}$why"; _WF_FLOW=$(( ${_XL_J[$at]} + 1 ))
  fi
}
_wf_skip() { echo "⏭  $(( _WF_AT + 1 ))/${#_XL_T[@]}  not asked this time: ${_XL_S[$_WF_AT]}"; _wf_advance; _wf_next "$1"; }

# ── hook: a list screen ────────────────────────────────────────────────────
# reads choice (when recording) / sets choice (when running)
_wf_list() {   # record|play
  _wf_mode || return 1
  _cm_ctx_find 2>/dev/null
  local scr="${_CM_MAP:-main}"
  [ "${_sw_in_mode:-0}" = 1 ] && [ "$scr" = main ] && scr=switch
  if [ "$1" = record ]; then [ "$_WF_M" = rec ] && _wf_rec_list "$scr"; return 0; fi
  [ "$_WF_M" = play ] || return 1
  _WF_LABS=(); _wf_ctx list "$scr"
  _wf_next "$scr" || return 1
  while (( _WF_AT < ${#_XL_T[@]} )) && _wf_optional "$_WF_AT"; do _wf_skip "$scr" || return 1; done
  (( _WF_AT >= ${#_XL_T[@]} )) && { _wf_done; return 1; }
  local at=$_WF_AT t a want n
  t="${_XL_T[$at]}"; _wf_subst "${_XL_A[$at]}"; a="$_XL_OUT"
  _wf_get screen; want="$_WF_G"
  [ -z "$want" ] || [ "$want" = "$scr" ] || { _wf_fail "expected the '$want' screen but this is '$scr'"; return 1; }
  case "$t" in
    goto)
      case "$a" in
        start|path) _wf_get start; a="$_WF_G" ;;
        "~"*) a="$HOME${a:1}" ;;
      esac
      if [[ "$a" == /* ]]; then
        [ -d "$a" ] || { _wf_fail "that folder does not exist: $a"; return 1; }
        _wf_say "$at"; _wf_advance
        [ "$a" = "$path" ] && { _wf_list play; return $?; }
        _BVK_NAV_TARGET="$a"; choice=__navpath__; return 0
      fi
      local cur=""
      [ "${_sw_in_mode:-0}" = 1 ] && cur="${_sw_tab:-}"
      [ -n "$cur" ] || { _wf_fail "'goto $a' needs a screen with tabs (type sw first)"; return 1; }
      if [ "${cur,,}" = "${a,,}" ]; then _wf_say "$at"; _wf_advance; _wf_list play; return $?; fi
      _wf_get tries; n="${_WF_G:-0}"
      (( n < 6 )) || { _wf_fail "there is no tab called '$a'"; return 1; }
      _wf_set tries $(( n + 1 ))
      if (( n < 3 )); then choice=__sw_tab_right__; else choice=__sw_tab_left__; fi
      return 0 ;;
    cmd)
      # cd (and q after sw) leave the app for a shell and the person types o to come back: running a workflow never has to leave
      if [ "$a" = cd ] || [ "$a" = q ]; then
        n=$(( at + 1 )); while (( n < ${#_XL_T[@]} )) && [ "${_XL_T[$n]}" = on ]; do n=$(( n + 1 )); done
        if (( n < ${#_XL_T[@]} )) && [ "${_XL_T[$n]}" = cmd ] && [ "${_XL_A[$n]}" = o ]; then
          _wf_say "$at"; _wf_say "$n"; echo "   (already inside the app: no need to leave and come back)"
          _wf_set at $(( n + 1 )); _wf_set screen ""; _wf_list play; return $?
        fi
      fi
      if [ -n "${_XL_K[$at]}" ]; then
        _wf_rows; _wf_numbers "${_XL_K[$at]}" "${_XL_V[$at]%%$'\t'*}" || { _wf_fail "$_WF_WHY"; return 1; }
        a+="$_XL_OUT"
      fi
      [[ "${_XL_V[$at]}" == *$'\t'* ]] && a+=" ${_XL_V[$at]#*$'\t'}" ;;
    where)
      [ "${_XL_K[$at]}" != option ] || { _wf_fail "expected a menu with the option '${_XL_V[$at]}', but this is a file list"; return 1; }
      _wf_rows; _wf_numbers "${_XL_K[$at]}" "${_XL_V[$at]}" || { _wf_fail "$_WF_WHY"; return 1; }
      a="$_XL_OUT" ;;
    *) _wf_fail "this step answers a question, but the app is showing a list"; return 1 ;;
  esac
  _wf_say "$at"; _wf_advance
  # a final cd / q really leaves the app: the run is over before it does
  [ "$t" = cmd ] && { [ "$a" = cd ] || [ "$a" = q ]; } && (( _WF_AT + 1 >= ${#_XL_T[@]} )) && _wf_off
  choice="$a"
  return 0
}
_wf_rec_list() {   # SCREEN ; reads choice
  local scr="$1" c="$choice" last tab=""
  case "$c" in
    ""|wf|"wf "*|__sw_tab_*) return 0 ;;
  esac
  [[ "$_WF_NEVER" == *" ${c%% *} "* ]] && return 0
  _wf_get screen; last="$_WF_G"
  [ "${_sw_in_mode:-0}" = 1 ] && tab="${_sw_tab:-}"
  if [ "$scr" != "$last" ]; then _wf_emit "on $scr"; _wf_set screen "$scr"; _wf_set tab ""; fi
  _wf_get tab
  [ -n "$tab" ] && [ "$tab" != "$_WF_G" ] && { _wf_emit "goto $tab"; _wf_set tab "$tab"; }
  if [ "$c" = __navpath__ ]; then _xl_quote "${_BVK_NAV_TARGET:-}"; _wf_emit "goto $_XL_OUT"; return 0; fi
  _wf_rows
  if [[ "$c" =~ ^[0-9][0-9,\ -]*$ ]]; then
    if _wf_names "$c"; then (( ${#_WF_ROWS[@]} > 1 )) && _wf_emit "# position $_WF_POS of ${#_WF_ROWS[@]}"; _wf_emit "where${_XL_OUT}"; else _wf_emit "# a row number with no name was typed here; write: where name=\"...\""; fi
    return 0
  fi
  if [[ "$c" =~ ^(([A-Za-z]{1,6}--?)|(fa\ ))([0-9][0-9,-]*)(\ +as\ .+)?$ ]]; then
    local head="${BASH_REMATCH[1]}" nums="${BASH_REMATCH[4]}" tail="${BASH_REMATCH[5]}"
    if _wf_names "$nums"; then _xl_quote "$head"; _wf_emit "cmd $_XL_OUT$( _wf_names "$nums"; printf '%s' "$_XL_OUT")$tail"; return 0; fi
  fi
  if [[ "$c" =~ ^[A-Za-z0-9._-]+$ ]]; then _wf_emit "cmd $c"; else _xl_quote "$c"; _wf_emit "cmd $_XL_OUT"; fi
}

# ── hook: "pick items" (delete, rename ...)  : reads / sets _buf ───────────
_wf_pick() {   # record|play
  _wf_mode || return 1
  if [ "$1" = record ]; then
    [ "$_WF_M" = rec ] || return 0
    local c="${_buf// /}"
    case "${c,,}" in
      "") return 0 ;;
      u|q) _wf_emit "cmd ${c,,}" ;;
      a) _wf_emit "select all" ;;
      a-*) _wf_rows; if _wf_names "${c#a-}"; then _wf_emit "# position $_WF_POS of ${#_WF_ROWS[@]}"; _wf_emit "select all except$_XL_OUT"; else _wf_emit 'input "pick items" ask'; fi ;;
      *) _wf_rows; if _wf_names "$c"; then _wf_emit "# position $_WF_POS of ${#_WF_ROWS[@]}"; _wf_emit "select$_XL_OUT"; else _wf_emit 'input "pick items" ask'; fi ;;
    esac
    return 0
  fi
  [ "$_WF_M" = play ] || return 1
  _WF_LABS=(); _wf_ctx pick "pick items"
  _wf_next "" || return 1
  (( _WF_AT < ${#_XL_T[@]} )) || return 1
  local at=$_WF_AT t a
  t="${_XL_T[$at]}"; a="${_XL_A[$at]}"
  case "$t" in
    select)
      if [ "$a" = all ]; then _buf=a
      else _wf_rows; _wf_numbers "${_XL_K[$at]}" "${_XL_V[$at]}" || { _wf_fail "$_WF_WHY"; return 1; }
        [ "$a" = except ] && _buf="a-$_XL_OUT" || _buf="$_XL_OUT"; fi ;;
    where) _wf_rows; _wf_numbers "${_XL_K[$at]}" "${_XL_V[$at]}" || { _wf_fail "$_WF_WHY"; return 1; }; _buf="$_XL_OUT" ;;
    cmd) case "$a" in a|u|q) _buf="$a" ;; *) _wf_fail "the app asks to pick items; write  select all  or  select name=\"...\""; return 1 ;; esac ;;
    input) [ "$a" = ask ] || { _wf_fail "the app asks to pick items"; return 1; }; _wf_say "$at"; _wf_advance; return 1 ;;
    *) _wf_fail "the app asks to pick items, the step is something else"; return 1 ;;
  esac
  _wf_say "$at"; _wf_advance
  return 0
}

# ── answering / recording a question with options ──────────────────────────
# _wf_answer_options QUESTION YESNO(0|1) MULTI  (arrays _WF_KEYS _WF_LABS) -> _WF_ANSWER.  rc 0 answered, 1 ask the person
_wf_answer_options() {
  local q="$1" yn="$2" at t v out="" _wf_j
  _wf_next "" || return 1
  while (( _WF_AT < ${#_XL_T[@]} )) && _wf_optional "$_WF_AT" && ! { [ "${_XL_T[$_WF_AT]}" = where ] && _wf_asks "$_WF_AT" "$q"; }; do _wf_skip "" || return 1; done
  (( _WF_AT < ${#_XL_T[@]} )) || { _wf_get at; _wf_fail "the app asked something the workflow has no answer for: $q"; return 1; }
  at=$_WF_AT; t="${_XL_T[$at]}"
  if [ "$t" = cmd ]; then
    if (( ! yn )) || [ "${_XL_A[$at]}" = u ] || [ "${_XL_A[$at]}" = q ]; then _wf_say "$at"; _wf_advance; _WF_ANSWER="${_XL_A[$at]}"; return 0; fi
  fi
  if [ "$t" = input ] && [ "${_XL_A[$at]}" = ask ]; then   # input "Question" ask: you choose this one
    _wf_asks "$at" "$q" || { _wf_fail "the app asked '$q' but the step answers '${_XL_Q[$at]}'"; return 1; }
    _wf_say "$at"; _wf_advance; return 1
  fi
  [ "$t" = where ] && { [ "${_XL_K[$at]}" = option ] || [ "${_XL_K[$at]}" = number ]; } || { _wf_fail "unexpected question: $q"; return 1; }
  _wf_asks "$at" "$q" || { _wf_fail "the app asked '$q' but the step answers '${_XL_Q[$at]}'"; return 1; }
  (( yn )) && [ -z "${_XL_Q[$at]}" ] && [ "${_XL_V[$at],,}" = yes ] && { _wf_fail "a Yes must name its question:  \"...?\" where option=\"Yes\"   (asked now: $q)"; return 1; }
  while IFS= read -r v; do
    _wf_subst "$v"; v="$_XL_OUT"
    if [ "${_XL_K[$at]}" = number ]; then   # 1 · 1,3 · 2-4 · last · -2 : the options by position
      _wf_pos_list "$v" "${#_WF_LABS[@]}" || { _wf_fail "no option number '$_WF_PBAD' (the menu has ${#_WF_LABS[@]}: $(printf '%s · ' "${_WF_LABS[@]}"))"; return 1; }
      for _wf_j in "${_WF_PL[@]}"; do out+="${out:+ }${_WF_KEYS[$_wf_j]}"; done
      continue
    fi
    _wf_index "$v" "${_WF_LABS[@]}" || { _wf_fail "no option called '$v' (options: $(printf '%s · ' "${_WF_LABS[@]}"))"; return 1; }
    out+="${out:+ }${_WF_KEYS[$_WF_I]}"
  done <<<"${_XL_V[$at]}"
  _wf_say "$at"; _wf_advance
  _WF_ANSWER="$out"
}
_wf_rec_options() {   # QUESTION KEYS-chosen...
  local q="$1" k i out="" pos="" note=""; shift
  for k in "$@"; do
    for i in "${!_WF_KEYS[@]}"; do [ "${_WF_KEYS[$i]}" = "$k" ] && { _xl_quote "${_WF_LABS[$i]%%  *}"; out+="${out:+,}$_XL_OUT"; pos+="${pos:+,}$(( i + 1 ))"; break; }; done
  done
  [ -n "$out" ] || return 1
  (( ${#_WF_KEYS[@]} > 2 )) && note="# position $pos of ${#_WF_KEYS[@]}"   # what stop_record can turn the choice into (a yes / no is never by position)
  _wf_emit_q "$q" "" "where option=$out" "$note"
}

# ── hook: yes/no and choice boxes (_bvk_menu: its _bc_ variables) ──────────
_wf_box() {   # record|play
  _wf_mode || return 1
  local i q="${_bc_question:-$_bc_title}"
  _WF_KEYS=(); _WF_LABS=()
  for i in "${!_bc_key[@]}"; do _wf_plain "${_bc_lbl[$i]}"; _WF_KEYS+=("${_bc_key[$i]}"); _WF_LABS+=("$_XL_OUT"); done
  if [ "$1" = record ]; then
    [ "$_WF_M" = rec ] || return 0
    local got="${!_bc_var}"
    [ -n "$got" ] || { _wf_emit "cmd u"; return 0; }
    local -a g=(); read -ra g <<<"$got"
    _wf_rec_options "$q" "${g[@]}" || :
    return 0
  fi
  [ "$_WF_M" = play ] || return 1
  _wf_ctx menu "$q"
  _wf_answer_options "$q" "$_bc_yn" || return 1
  case "$_WF_ANSWER" in u|q) _BVK_LEFT="$_WF_ANSWER"; _WF_ANSWER="" ;; esac
  return 0
}

# ── hook: typed lines and numbered menus (the read shim) ───────────────────
# _wf_prompt record|play PROMPT [ANSWER] ; uses the shim's _sm_rows_* / _sm_hdr when the prompt sits under a menu (_WF_MENU=1)
_wf_menu_rows() {
  local i
  _WF_KEYS=(); _WF_LABS=()
  for i in "${!_sm_rows_token[@]}"; do
    [ -n "${_sm_rows_token[$i]}" ] || continue
    _wf_plain "${_sm_rows_text[$i]}"; _WF_KEYS+=("${_sm_rows_token[$i]}"); _WF_LABS+=("$_XL_OUT")
  done
  _WF_Q="$1"
  for (( i=${#_sm_hdr[@]}-1; i>=0; i-- )); do _wf_plain "${_sm_hdr[$i]}"; [[ "$_XL_OUT" == *[A-Za-z]* ]] && { _WF_Q="$_XL_OUT"; break; }; done   # the title nearest the rows
}
_wf_prompt() {
  _wf_mode || return 1
  local op="$1" p="$2" ans="${3:-}"
  _xl_trim "$p"; p="${_XL_OUT%:}"
  if (( _WF_MENU )); then _wf_menu_rows "$p"; else _WF_Q="$p"; _WF_KEYS=(); _WF_LABS=(); fi
  if [ "$op" = record ]; then
    [ "$_WF_M" = rec ] || return 0
    [ -n "$ans" ] && [[ "$_WF_NEVER" == *" ${ans,,} "* ]] && return 0
    case "${ans,,}" in
      u|q) _wf_emit "cmd ${ans,,}"; return 0 ;;
    esac
    if (( _WF_MENU )); then
      [ -n "$ans" ] || return 0
      local -a g=(); read -ra g <<<"${ans//,/ }"
      _wf_rec_options "$_WF_Q" "${g[@]}" && return 0
    fi
    # what was typed is never stored: the run stops here and asks again (a commit message is new every time); Enter alone = the default
    if [ -n "$ans" ]; then _wf_emit_q "$_WF_Q" "input " ask; else _wf_emit_q "$_WF_Q" "input " default; fi
    return 0
  fi
  [ "$_WF_M" = play ] || return 1
  if (( _WF_MENU )); then _wf_ctx menu "$_WF_Q $p"; else _wf_ctx input "$p"; fi
  if (( _WF_MENU )); then
    _wf_next "" || return 1
    if (( _WF_AT < ${#_XL_T[@]} )) && [ "${_XL_T[$_WF_AT]}" != input ]; then _wf_answer_options "$_WF_Q" 0; return $?; fi
    _WF_Q="$p"
  fi
  _wf_next "" || return 1
  while (( _WF_AT < ${#_XL_T[@]} )) && _wf_optional "$_WF_AT"; do _wf_skip "" || return 1; done
  (( _WF_AT < ${#_XL_T[@]} )) || { _wf_fail "the app asked something the workflow has no answer for: $_WF_Q"; return 1; }
  local at=$_WF_AT t a
  t="${_XL_T[$at]}"; a="${_XL_A[$at]}"
  if [ "$t" = cmd ] && { [ "$a" = u ] || [ "$a" = q ]; }; then _wf_say "$at"; _wf_advance; _WF_ANSWER="$a"; return 0; fi
  [ "$t" = input ] || { _wf_fail "the app wants typed text ($_WF_Q), the step is something else"; return 1; }
  _wf_asks "$at" "$_WF_Q" || { _wf_fail "the app asked '$_WF_Q' but the step answers '${_XL_Q[$at]}'"; return 1; }
  _wf_say "$at"; _wf_advance
  case "$a" in
    ask) echo "✍️  Your turn: type it, then the workflow goes on"; return 1 ;;
    default) _WF_ANSWER="" ;;
    value) _wf_subst "${_XL_V[$at]}"; _WF_ANSWER="$_XL_OUT" ;;
  esac
}

# ── hook: the "type this number" gate ──────────────────────────────────────
_wf_confirm() {   # record|play ; rc 0 (play) = the workflow confirms
  _wf_mode || return 1
  if [ "$1" = record ]; then [ "$_WF_M" = rec ] && _wf_emit "confirm auto"; return 0; fi
  [ "$_WF_M" = play ] || return 1
  _WF_LABS=(); _wf_ctx confirm "type this number"
  _wf_next "" || return 1
  (( _WF_AT < ${#_XL_T[@]} )) && [ "${_XL_T[$_WF_AT]}" = confirm ] || { _wf_fail "a safety number is asked and the workflow has no 'confirm auto' here"; return 1; }
  _wf_say "$_WF_AT"; _wf_advance
}

# ── a Settings-style screen opened by itself: xlr8 cannot drive those ──────
_wf_screen() {   # TITLE
  _wf_mode || return 0
  case " ${FUNCNAME[*]} " in *" _bvk_menu "*|*" bvk_cc_cmd "*) return 0 ;; esac
  if [ "$_WF_M" = play ]; then _wf_load_run && _wf_fail "the screen '$1' opened: workflows cannot drive Settings / Home screens"
  else _wf_emit "# the screen '$1' was used here: workflows cannot replay it"; echo "🔴  Recording: steps inside '$1' are not recorded"; fi
  return 0
}

# ── wf: the list of workflows is the main list on the workflows folder (_wfv_* in bashbasicsbyvk_browse.sh); a number opens the run loop (handle_file)
_wf_menu() {
  _wf_mode && { echo "🔴  Type stop_record first"; return 0; }
  [ "${_GD_ACTIVE:-0}" = 1 ] && { echo "☁️  Leave Google Drive first (gdx), then type wf"; return 0; }
  mkdir -p -- "$_WF_HOME" || { echo "❌ Cannot create $_WF_HOME"; return 0; }
  _wfv_on || _WF_RETURN="$path"
  path="$_WF_HOME"; group_prefix=""; force_show=false; _gv_crumbs=()
}
# Run from the run loop: the workflow starts in the folder the person came from, never in the workflows folder
_wf_run_here() {   # NAME [VALUES]
  local was="$path"
  _wfv_on && [ -d "$_WF_RETURN" ] && path="$_WF_RETURN"
  _wf_run "$1" "${2:-}"
  _wf_mode || path="$was"      # nothing started: stay on the list
}
# after Edit: say at once when the file will not run
_wf_check() {   # FILE
  local n="${1##*/}"; n="${n%.xlr8}"
  _xl_load "$1" && echo "💫 '$n' reads fine (${#_XL_T[@]} steps)" || echo "🔴  '$n' will not run until this is fixed. $_XL_ERR"
}
_wf_find_doc() {   # an installed *.txt sits in the data dir, a source tree beside this file
  local d="${BASH_SOURCE[0]%/*}" c
  for c in "$d/$1" "$d/../share/bashbasicsbyvk/$1" "${SCRIPT_DIR:-.}/../bashbasicsbyvk/$1" "${SCRIPT_DIR:-.}/$1"; do [ -r "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}
handle_wf_cmd() {   # "wf" | "wf NAME" | "wf NAME value..." (the values of the workflow's {$name}s)
  local name="${1#??}" args=""
  _xl_trim "$name"; name="$_XL_OUT"
  if [[ "$name" =~ ^([^[:space:]]+)[[:space:]]+(.*)$ ]]; then name="${BASH_REMATCH[1]}"; args="${BASH_REMATCH[2]}"; fi
  if [ -n "$name" ]; then _wf_run_here "$name" "$args"; else _wf_menu; fi
}
