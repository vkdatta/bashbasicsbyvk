# bashbasicsbyvk_wf.sh - workflows: start_record · stop_record · wf · wf NAME.  The language is read by bashbasicsbyvk_xlr8.sh.
# ════════════════════════════════════════════════════════════════════════════
#  Every question of the app is answered in one of a few places; each calls ONE hook here, only while BVK_WF_DIR is set:
#     _wf_list     the list screens (main, sw ...)        _wf_pick   the "pick items" screen
#     _wf_prompt   typed lines and numbered menus         _wf_box    yes/no and choice boxes
#     _wf_confirm  the "type this number" gate            _wf_trip   something failed
#  A hook returns 0 = "answered (recording never does)", 1 = ask the person.
#  State lives in FILES (BVK_WF_DIR: mode, steps, at, start, name, screen): tools run in subshells, and  cd  replaces the app by a shell.
#  THE GUARD: an answer is only given to the kind of question (and the question text) it was recorded for; anything else stops the run.
# ════════════════════════════════════════════════════════════════════════════

declare -g _WF_HOME="${BVK_WF_HOME:-$HOME/.bashbasicsbyvk/workflows}"
declare -g _WF_ANSWER="" _WF_MUTE=0
declare -g _WF_NEVER=" cc print tidy loadtime start_record stop_record "   # tools about the app, not steps of a task

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
  for n in "${nums[@]}"; do
    i=$(( n - 1 )); (( i >= 0 )) && [ -n "${_WF_ROWS[$i]:-}" ] || return 1
    _wf_index "${_WF_ROWS[$i]}" "${_WF_ROWS[@]}"; dup=$?
    if (( dup == 2 )) && [ -n "${_WF_PATHS[$i]}" ]; then _xl_quote "${_WF_PATHS[$i]}"; out+=" path=$_XL_OUT"
    else _xl_quote "${_WF_ROWS[$i]}"; out+=" name=$_XL_OUT"; fi
  done
  _XL_OUT="$out"
}
# rows named by a step -> _XL_OUT = "1,3"  (rc 1: _WF_WHY)
_wf_numbers() {   # KEY VALUES
  local key="$1" v out="" rc
  while IFS= read -r v; do
    if [ "$key" = path ]; then _wf_index "$v" "${_WF_PATHS[@]}"; else _wf_index "$v" "${_WF_ROWS[@]}"; fi
    rc=$?
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
_wf_run() {   # NAME
  local name="$1" file i start
  _wf_mode && { echo "🔴  Finish first (stop_record) before running a workflow"; return 0; }
  file="$_WF_HOME/${name%.xlr8}.xlr8"
  [ -r "$file" ] || { echo "❌ No workflow called '$name' (type wf to see them)"; return 0; }
  _xl_load "$file" || { echo "❌ '$name' has a mistake, nothing was run. $_XL_ERR"; return 0; }
  start="$path"
  for i in "${!_XL_T[@]}"; do
    [ "${_XL_T[$i]}" = from ] || continue
    case "${_XL_A[$i]}" in
      here|current_path|navigation_path) ;;
      *) [ -d "${_XL_A[$i]}" ] || { echo "❌ '$name' starts in a folder that is gone: ${_XL_A[$i]}. Nothing was run."; return 0; }
         path="${_XL_A[$i]}"; group_prefix=""; force_show=false ;;
    esac
  done
  _wf_off
  BVK_WF_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bvk-wf.XXXXXX")" || return 0
  export BVK_WF_DIR
  cp -- "$file" "$BVK_WF_DIR/steps"
  _wf_set mode play; _wf_set at 0; _wf_set name "${name%.xlr8}"; _wf_set start "$path"; _wf_set screen ""
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
_wf_asks() {   # STEP QUESTION: is this the question the step was written for?
  local want got
  _wf_key "${_XL_Q[$1]}"; want="$_XL_OUT"; _wf_key "$2"; got="$_XL_OUT"
  [ -z "$want" ] || [[ "$got" == *"$want"* ]]
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
  _wf_next "$scr" || return 1
  while (( _WF_AT < ${#_XL_T[@]} )) && _wf_optional "$_WF_AT"; do _wf_skip "$scr" || return 1; done
  (( _WF_AT >= ${#_XL_T[@]} )) && { _wf_done; return 1; }
  local at=$_WF_AT t a want n
  t="${_XL_T[$at]}"; a="${_XL_A[$at]}"
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
    if _wf_names "$c"; then _wf_emit "where${_XL_OUT}"; else _wf_emit "# a row number with no name was typed here; write: where name=\"...\""; fi
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
      a-*) _wf_rows; if _wf_names "${c#a-}"; then _wf_emit "select all except$_XL_OUT"; else _wf_emit 'input "pick items" ask'; fi ;;
      *) _wf_rows; if _wf_names "$c"; then _wf_emit "select$_XL_OUT"; else _wf_emit 'input "pick items" ask'; fi ;;
    esac
    return 0
  fi
  [ "$_WF_M" = play ] || return 1
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
  local q="$1" yn="$2" at t v out=""
  _wf_next "" || return 1
  while (( _WF_AT < ${#_XL_T[@]} )) && _wf_optional "$_WF_AT" && ! { [ "${_XL_T[$_WF_AT]}" = where ] && _wf_asks "$_WF_AT" "$q"; }; do _wf_skip "" || return 1; done
  (( _WF_AT < ${#_XL_T[@]} )) || { _wf_get at; _wf_fail "the app asked something the workflow has no answer for: $q"; return 1; }
  at=$_WF_AT; t="${_XL_T[$at]}"
  if [ "$t" = cmd ]; then
    if (( ! yn )) || [ "${_XL_A[$at]}" = u ] || [ "${_XL_A[$at]}" = q ]; then _wf_say "$at"; _wf_advance; _WF_ANSWER="${_XL_A[$at]}"; return 0; fi
  fi
  [ "$t" = where ] && [ "${_XL_K[$at]}" = option ] || { _wf_fail "unexpected question: $q"; return 1; }
  _wf_asks "$at" "$q" || { _wf_fail "the app asked '$q' but the step answers '${_XL_Q[$at]}'"; return 1; }
  (( yn )) && [ -z "${_XL_Q[$at]}" ] && [ "${_XL_V[$at],,}" = yes ] && { _wf_fail "a Yes must name its question:  \"...?\" where option=\"Yes\"   (asked now: $q)"; return 1; }
  while IFS= read -r v; do
    _wf_index "$v" "${_WF_LABS[@]}" || { _wf_fail "no option called '$v' (options: $(printf '%s · ' "${_WF_LABS[@]}"))"; return 1; }
    out+="${out:+ }${_WF_KEYS[$_WF_I]}"
  done <<<"${_XL_V[$at]}"
  _wf_say "$at"; _wf_advance
  _WF_ANSWER="$out"
}
_wf_rec_options() {   # QUESTION KEYS-chosen...
  local q="$1" k i out=""; shift
  for k in "$@"; do
    for i in "${!_WF_KEYS[@]}"; do [ "${_WF_KEYS[$i]}" = "$k" ] && { _xl_quote "${_WF_LABS[$i]%%  *}"; out+="${out:+,}$_XL_OUT"; break; }; done
  done
  [ -n "$out" ] || return 1
  _xl_quote "$q"; q="$_XL_OUT"
  _wf_emit "$q where option=$out"
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
    _xl_quote "$_WF_Q"
    # what was typed is never stored: the run stops here and asks again (a commit message is new every time); Enter alone = the default
    if [ -n "$ans" ]; then _wf_emit "input $_XL_OUT ask"; else _wf_emit "input $_XL_OUT default"; fi
    return 0
  fi
  [ "$_WF_M" = play ] || return 1
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
    value) _WF_ANSWER="${_XL_V[$at]}" ;;
  esac
}

# ── hook: the "type this number" gate ──────────────────────────────────────
_wf_confirm() {   # record|play ; rc 0 (play) = the workflow confirms
  _wf_mode || return 1
  if [ "$1" = record ]; then [ "$_WF_M" = rec ] && _wf_emit "confirm auto"; return 0; fi
  [ "$_WF_M" = play ] || return 1
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

# ── wf: the list of workflows ──────────────────────────────────────────────
_wf_menu() {
  _wf_mode && { echo "🔴  Type stop_record first"; return 0; }
  local pick="" act="" ans="" new="" f n doc i
  local -a files=() rows=()
  while :; do
    files=(); rows=(); i=0
    for f in "$_WF_HOME"/*.xlr8; do
      [ -f "$f" ] || continue
      files+=("$f"); i=$(( i + 1 )); n="${f##*/}"; rows+=("$i:${n%.xlr8}")
    done
    rows+=("help:How to write xlr8")
    (( i )) || echo "📜  No workflows yet: type start_record, do your task once, then stop_record"
    _bvk_menu pick -t "Workflows" -i "🔁" -n -- "${rows[@]}" || return 0
    if [ "$pick" = help ]; then
      doc="$(_wf_find_doc bashbasicsbyvk_xlr8.txt 2>/dev/null)"
      [ -r "$doc" ] && cat "$doc" || echo "The language guide is not installed"
      continue
    fi
    f="${files[$((pick-1))]}"; n="${f##*/}"; n="${n%.xlr8}"
    _bvk_menu act -t "$n" -i "🔁" -n -- "run:Run" "view:View steps" "edit:Edit steps" "ren:Rename" "d:Delete" || continue
    case "$act" in
      run) _wf_run "$n"; return 0 ;;
      view) echo; cat -- "$f"; echo ;;
      edit)
        if command -v nano >/dev/null 2>&1; then nano "$f"; else "${EDITOR:-vi}" "$f"; fi
        _xl_load "$f" && echo "💫 '$n' reads fine (${#_XL_T[@]} steps)" || echo "🔴  '$n' will not run until this is fixed. $_XL_ERR" ;;
      ren)
        _bvk_read new "New name: " -i "$n" || continue
        if [[ "$new" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] && [ ! -e "$_WF_HOME/$new.xlr8" ]; then
          command mv -- "$f" "$_WF_HOME/$new.xlr8"
        else echo "🔴  Not renamed (name taken or not allowed)"; fi ;;
      d) _bvk_yn ans "Delete the workflow '$n'?" || continue; [ "$ans" = y ] && rm -f -- "$f" && echo "💫 Deleted '$n'" ;;
    esac
  done
}
_wf_find_doc() {   # an installed *.txt sits in the data dir, a source tree beside this file
  local d="${BASH_SOURCE[0]%/*}" c
  for c in "$d/$1" "$d/../share/bashbasicsbyvk/$1" "${SCRIPT_DIR:-.}/../bashbasicsbyvk/$1" "${SCRIPT_DIR:-.}/$1"; do [ -r "$c" ] && { printf '%s' "$c"; return 0; }; done
  return 1
}
handle_wf_cmd() {   # "wf" | "wf NAME"
  local name="${1#??}"
  _xl_trim "$name"; name="$_XL_OUT"
  if [ -n "$name" ]; then _wf_run "$name"; else _wf_menu; fi
}
