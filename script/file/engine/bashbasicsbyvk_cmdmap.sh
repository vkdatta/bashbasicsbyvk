#!/usr/bin/env bash
# ============================================================
#  COMMAND MAP  —  one grammar for every prompt in the app
#
#  Three kinds of file feed this layer (all under  cmdmap/):
#
#    bashbasicsbyvk_maincommands.sh        every MAIN command, defined once:
#                             cmd_def ID KIND HANDLER CLASS "description" ["example"]
#    bashbasicsbyvk_<menu>menucommands.sh  the commands that exist ONLY in that menu (same cmd_def)
#    bashbasicsbyvk_<menu>.map             the WIRING of one menu / prompt:
#
#                             @menu   upgrade
#                             @func   upgrade_menu          # which function owns it
#                             @kind   menu | prompt
#                             @back   u                     # key that leaves this menu
#                             @parent main                  # inherited map (default main)
#
#                             p-   .mapto()  p-  from bashbasicsbyvk_maincommands.sh
#                             i-   .mapto()  k-  from bashbasicsbyvk_upgrademenucommands.sh
#                             z    .mapto()  block()        # blocked in this menu
#                             u    .mapto()  back()         # "go back" (prompts)
#
#  RULES
#   1. A typed word that is a command ALWAYS wins over the natural action of the
#      prompt (rename, filter, enter a value ...).  There are no silent exceptions.
#   2. @ is the escape:   @s  → the text  s        @@s → the text  @s
#      (@word that is not a command word stays as typed:  @john → @john)
#   3. A command that is blocked / not wired where you typed it prints
#        ❌ Invalid command: z — exiting
#      cancels the whole flow, and the menu is redrawn.
#   4. Leaving a key unwired (inherited silently) is allowed only as a safety net;
#      `o --map-lint` lists every such gap, `bvk-mapgen` writes them in explicitly.
#
#  KINDS    exact   typed == key               (q, s, rf)
#           prefix  typed starts with key      (c-  → c-1,3)
#           word    key, or key + space or "."  (.s → ".s.ext png", ".s foo")
#  CLASSES  nav     can run from anywhere, opens a screen          (s h q i -h)
#           util    can run from anywhere, prints something        (disk ram health)
#           act     acts on the main file list: main prompt only   (c d r z t f ...)
#           filter  handled by the list loop itself (=)             (=)
#           local   the menu's own loop handles it (handler "-")
#           danger  main prompt only, never from a nested prompt    (kl)
#
#  Disable the whole layer with:  export VK_CMDMAP=0
# ============================================================

_CM_ON=1
[ "${VK_CMDMAP:-1}" = "0" ] && _CM_ON=0
_cm_on() { [ "$_CM_ON" = 1 ]; }

declare -gA _CM_DEF=()          # "file:ID" -> "kind|handler|class|desc|example"
declare -gA _CM_DEF_BYKEY=()    # "file:KEY" -> ID  (the key of a def is its ID)
declare -gA _CM_MAP_FUNC=()     # function name -> map
declare -gA _CM_MAP_KIND=()     # map -> menu|prompt
declare -gA _CM_MAP_BACK=()     # map -> key that leaves it
declare -gA _CM_MAP_PARENT=()   # map -> parent map
declare -gA _CM_MAP_FILE=()     # map -> source path
declare -gA _CM_MAP_LINES=()    # map -> newline separated "key|kind|tgt|lineno"
declare -ga _CM_MAP_NAMES=()
declare -gA _CM_MAP_PENDING=()   # map -> file, wiring not parsed yet (parsed on first use)
_CM_BOOTED=0
_CM_FLASH=""                    # one-shot message shown in the hint row
_CM_ABORT=0; _CM_ABORT_MSG=""; _CM_ABORT_DEPTH=0; _CM_ABORT_N=0
_CM_MAP=""; _CM_MDEPTH=0; _CM_FLOW=0     # set by _cm_ctx_find; defined here so nothing reads them unset
_CM_MUTE=0
# No command is longer than this many characters. Past it, nothing is looked up WHILE TYPING (live hint, highlight):
# only below it. Enter is the fallback: the gates (_cm_gate_*) still resolve the whole text (up to the 255 guard in _cm_resolve).
_CM_LIVE_MAX=56

# ------------------------------------------------------------ locating the files
# Built ONCE per session, with no subshells: the directories to look in, and every
# command-map file found in them (name -> full path).  Nothing is searched twice.
declare -gA _CM_PATHS=()       # basename -> full path
declare -ga _CM_MAPFILES=()    # *.map files, in discovery order
_CM_SCANNED=0
_cm_scan() {
  [ "$_CM_SCANNED" = 1 ] && return 0
  _CM_SCANNED=1
  local d f b IFS_save="$IFS"
  local -a dirs=()
  [ -n "${SCRIPT_DIR:-}" ] && dirs+=("$SCRIPT_DIR" "$SCRIPT_DIR/cmdmap" "$SCRIPT_DIR/file/cmdmap")
  local IFS=:
  for d in $PATH; do [ -n "$d" ] && dirs+=("$d"); done
  IFS="$IFS_save"
  # the files we need are named *commands.sh / *menucommands.sh / *.map — glob only those
  shopt -s nullglob
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*commands.sh "$d"/*.map; do
      b="${f##*/}"
      [ -n "${_CM_PATHS[$b]+x}" ] && continue
      _CM_PATHS["$b"]="$f"
      [[ "$b" == *.map ]] && _CM_MAPFILES+=("$f")
    done
  done
  shopt -u nullglob
  return 0
}
_cm_find() {   # name -> _CM_FOUND (and stdout)
  _cm_scan
  _CM_FOUND="${_CM_PATHS[$1]-}"
  [ -n "$_CM_FOUND" ] && { printf '%s' "$_CM_FOUND"; return 0; }
  return 1
}

# ------------------------------------------------------------ definitions
# cmd_def ID KIND HANDLER CLASS "description" ["example"]
# Registered under the basename of the file that calls it (a *commands.sh, loaded through the load mapper).
cmd_def() {
  local id="$1" kind="$2" handler="$3" class="$4" desc="${5:-}" ex="${6:-}"
  _CM_DEF["${BASH_SOURCE[1]##*/}:$id"]="$kind|$handler|$class|$desc|$ex"
}

# ------------------------------------------------------------ loading the .map files
_cm_boot() {
  [ "$_CM_BOOTED" = 1 ] && return 0
  _CM_BOOTED=1
  _cm_scan
  local f
  for f in "${_CM_MAPFILES[@]}"; do _cm_parse_map "$f" head; done   # headers only: cheap
  return 0
}

# kind of a typed key, learned from the command it is wired to
_cm_kind_of_tgt() {   # $1=file:ID  -> _CM_KIND   (no subshell)
  local d="${_CM_DEF[$1]-}"
  if [ -n "$d" ]; then _CM_KIND="${d%%|*}"; else _CM_KIND=exact; fi
}

_cm_parse_map() {   # $1 file  $2 = head (directives only, stop at the first wire line)
  local f="$1" headonly="${2:-}" line n=0 map="" kind="menu" key tgt rx srcfile id kd
  local fn="" back="u" parent="main" lines=""
  local rx_wire='^([^[:space:]]+)[[:space:]]+\.mapto\(\)[[:space:]]+(block\(\)|back\(\)|([^[:space:]]+)[[:space:]]+from[[:space:]]+([^[:space:]#]+))'
  while IFS= read -r line || [ -n "$line" ]; do
    n=$(( n + 1 ))
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in
      @menu*)   map="${line#@menu}";   map="${map//[[:space:]]/}" ;;
      @func*)   fn="${line#@func}";    fn="${fn//[[:space:]]/}" ;;
      @kind*)   kind="${line#@kind}";  kind="${kind//[[:space:]]/}" ;;
      @back*)   back="${line#@back}";  back="${back//[[:space:]]/}" ;;
      @parent*) parent="${line#@parent}"; parent="${parent//[[:space:]]/}" ;;
      @*)       ;;
      *)
        [ -n "$headonly" ] && break
        if [[ "$line" =~ $rx_wire ]]; then
          key="${BASH_REMATCH[1]}"
          if [ "${BASH_REMATCH[2]}" = "block()" ]; then tgt="BLOCK"
          elif [ "${BASH_REMATCH[2]}" = "back()" ]; then tgt="BACK"
          else
            id="${BASH_REMATCH[3]}"; srcfile="${BASH_REMATCH[4]}"
            tgt="$srcfile:$id"
            declare -F _lm_need >/dev/null 2>&1 && _lm_need "$srcfile"   # the load mapper: this menu's *commands.sh registers its cmd_defs only when it is wired in
          fi
          case "$tgt" in
            BLOCK|BACK)
              # the kind of a blocked key is the kind of the main command it shadows
              if [[ "$key" == *'*' ]]; then kd=prefix; key="${key%\*}"
              else _cm_kind_of_tgt "bashbasicsbyvk_maincommands.sh:$key"; kd="$_CM_KIND"; fi ;;
            *) _cm_kind_of_tgt "$tgt"; kd="$_CM_KIND" ;;
          esac
          lines+="$key|$kd|$tgt|$n"$'\n'
        fi ;;
    esac
  done < "$f"
  [ -z "$map" ] && return 0
  if [ -n "$headonly" ]; then _CM_MAP_PENDING["$map"]="$f"; else unset '_CM_MAP_PENDING[$map]'; fi
  _CM_MAP_KIND["$map"]="$kind"; _CM_MAP_BACK["$map"]="$back"
  _CM_MAP_PARENT["$map"]="$parent"; _CM_MAP_FILE["$map"]="$f"
  _CM_MAP_LINES["$map"]="$lines"
  case " ${_CM_MAP_NAMES[*]} " in *" $map "*) ;; *) _CM_MAP_NAMES+=("$map") ;; esac
  [ -n "$fn" ] && _CM_MAP_FUNC["$fn"]="$map"
  return 0
}

# ------------------------------------------------------------ context: which map owns this prompt?
# Walks the call stack outwards and takes the nearest function that a .map claims.
# _CM_MAP    the map (nearest, any kind)         _CM_MDEPTH  stack depth of the nearest MENU function
# _CM_FLOW   number of non-plumbing frames between the reader and that menu (0 = the menu's own prompt)
_cm_ctx_find() {
  _CM_MAP=""; _CM_MDEPTH=0; _CM_FLOW=0
  local i n=${#FUNCNAME[@]} fn m menu_found=0 flow=0
  for (( i=1; i<n; i++ )); do
    fn="${FUNCNAME[i]}"
    case "$fn" in
      _cm_*|_lt_*|_multi_*|_rc_click|_rc_wheel|_bvk_mouse_*|_st_click|_sm_click|_sm_wheel|select_items_common|select_imaginary_items_common|_read_choice|_read_choice_raw|_read_choice_filtered|read|_sm_*|_vp_*|_input_*|_print_input_line|_mc_ask|source|main) continue ;;
    esac
    m="${_CM_MAP_FUNC[$fn]-}"
    if [ -n "$m" ]; then
      [ -z "$_CM_MAP" ] && _CM_MAP="$m"
      if [ "${_CM_MAP_KIND[$m]}" = "menu" ]; then
        _CM_MDEPTH=$(( n - i )); menu_found=1; break
      fi
    else
      [ "$menu_found" = 0 ] && flow=$(( flow + 1 ))
    fi
  done
  _CM_FLOW=$flow
  [ -z "$_CM_MAP" ] && _CM_MAP="main"
  # rbam / nf / cs share ONE loop (_xui_loop) and differ only by screen: each screen owns a map
  # (xui_rb · xui_nf · xui_cs, parent xui) so its own commands (rf · r- · x- · ux ...) are not
  # blocked by the generic xui map.
  if [ "$_CM_MAP" = xui ] && [ -n "${_XUI_PFX:-}" ] && [ -n "${_CM_MAP_KIND[xui_${_XUI_PFX}]+x}" ]; then
    _CM_MAP="xui_${_XUI_PFX}"
  fi
  return 0
}

# ------------------------------------------------------------ the effective table of a map
declare -ga _ct_key=() _ct_kind=() _ct_tgt=() _ct_map=() _ct_impl=()
_CM_TBL_MAP=""
# wiring of a map is parsed the first time it is needed (a menu you never open costs nothing)
_cm_ensure() { [ -n "${_CM_MAP_PENDING[$1]+x}" ] && _cm_parse_map "${_CM_MAP_PENDING[$1]}"; return 0; }
_cm_ensure_all() { local m; for m in "${!_CM_MAP_PENDING[@]}"; do _cm_ensure "$m"; done; }

_cm_table_build() {   # $1 = map
  [ "$_CM_TBL_MAP" = "$1" ] && return 0
  _CM_TBL_MAP="$1"
  _ct_key=(); _ct_kind=(); _ct_tgt=(); _ct_map=(); _ct_impl=()
  local m="$1" depth=0 line key kd tgt rest seen=$'\n' lc
  while [ -n "$m" ] && [ "$depth" -lt 6 ]; do
    _cm_ensure "$m"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      key="${line%%|*}"; rest="${line#*|}"; kd="${rest%%|*}"; rest="${rest#*|}"; tgt="${rest%%|*}"
      lc="${key,,}|$kd"
      case "$seen" in *$'\n'"$lc"$'\n'*) continue ;; esac
      seen+="$lc"$'\n'
      _ct_key+=("${key,,}"); _ct_kind+=("$kd"); _ct_tgt+=("$tgt"); _ct_map+=("$m")
      [ "$depth" -gt 0 ] && _ct_impl+=(1) || _ct_impl+=(0)
    done <<< "${_CM_MAP_LINES[$m]-}"
    m="${_CM_MAP_PARENT[$m]-}"; [ "$m" = "$1" ] && break
    depth=$(( depth + 1 ))
  done
  return 0
}

_cm_match() {   # kind key typed(lowercase)
  case "$1" in
    exact)  [[ "$3" == "$2" ]] ;;
    prefix) [[ "$3" == "$2"* ]] ;;
    word)   [[ "$3" == "$2" || "$3" == "$2 "* || "$3" == "$2."* ]] ;;
    *)      return 1 ;;
  esac
}

# ------------------------------------------------------------ resolver
# _cm_resolve MODE TYPED       MODE = menu | text
# Sets _CM_ACT:
#   none    typed text is not a command            → treat as data / number
#   local   the loop's own case handles it         → pass through unchanged
#   run     a main nav/util command, run it here   (_CM_HANDLER)
#   back    "go back"                              → leave the prompt / flow
#   block   known command, not usable here         → invalid command
# plus _CM_KEY (matched key) _CM_DESC _CM_EX _CM_CLASS _CM_IMPL (1 = inherited without a wire)
_cm_resolve() {
  local mode="$1" t="$2" i best=-1 bl=-1 tgt d kind handler class
  _CM_ACT=none; _CM_KEY=""; _CM_DESC=""; _CM_EX=""; _CM_CLASS=""; _CM_IMPL=0; _CM_HANDLER=""
  [ "${#t}" -gt 255 ] && return 0          # no command is that long: it is plain text (a big paste is never matched row by row)
  t="${t,,}"
  local n=${#_ct_key[@]}
  for (( i=0; i<n; i++ )); do
    _cm_match "${_ct_kind[i]}" "${_ct_key[i]}" "$t" || continue
    if [ "${#_ct_key[i]}" -gt "$bl" ]; then best=$i; bl=${#_ct_key[i]}; fi
  done
  # "u" typed into a text prompt (a question inside a flow) is ALWAYS "go back" — the one rule the guide
  # promises everywhere. A map's own "u" (Up one folder, Up) is about the LIST, never about a question.
  if [ "$mode" = text ] && [ "$t" = u ] && { [ "$best" -lt 0 ] || [ "${_ct_tgt[best]}" != BLOCK ]; }; then
    _CM_ACT=back; _CM_KEY=u; _CM_DESC="Go back"; return 0
  fi
  [ "$best" -lt 0 ] && return 0
  tgt="${_ct_tgt[best]}"; _CM_KEY="${_ct_key[best]}"; _CM_IMPL="${_ct_impl[best]}"
  case "$tgt" in
    BLOCK) _CM_ACT=block; return 0 ;;
    BACK)  _CM_ACT=back;  _CM_DESC="Go back"; return 0 ;;
  esac
  d="${_CM_DEF[$tgt]-}"
  if [ -z "$d" ]; then _CM_ACT=block; return 0; fi
  kind="${d%%|*}"; d="${d#*|}"; handler="${d%%|*}"; d="${d#*|}"
  class="${d%%|*}"; d="${d#*|}"; _CM_DESC="${d%%|*}"; _CM_EX="${d#*|}"; _CM_CLASS="$class"
  _CM_HANDLER="$handler"
  local fromfile="${tgt%%:*}" in_main=0
  [ "${_ct_map[best]}" = "main" ] && in_main=1
  # a "tool" (print, loadtime) works at EVERY prompt: it only reads state, it never changes where you are
  if [ "$class" = tool ] && [ "$fromfile" = bashbasicsbyvk_maincommands.sh ] && declare -F "$handler" >/dev/null 2>&1; then
    _CM_ACT=run; return 0
  fi
  # ---- what does a typed command do HERE?
  if [ "$_CM_MAP" = "main" ] && [ "$mode" = "menu" ]; then _CM_ACT=local; return 0; fi
  if [ "$fromfile" != "bashbasicsbyvk_maincommands.sh" ] && [ "$handler" != back ] && [ "$mode" = text ]; then
    # A menu's OWN key (switch: s = Settings, c = Create ...) belongs to that menu's LIST prompt. Inside a
    # question (a name, a number, a time) it means what it means everywhere else: the main command of the
    # same name (s h q → opens that screen; c d r → "Invalid command"), or plain text when there is none.
    local md="${_CM_DEF[bashbasicsbyvk_maincommands.sh:$_CM_KEY]-}"
    if [ -z "$md" ]; then _CM_ACT=none; _CM_KEY=""; _CM_DESC=""; _CM_EX=""; _CM_CLASS=""; _CM_HANDLER=""; return 0; fi
    tgt="bashbasicsbyvk_maincommands.sh:$_CM_KEY"; d="$md"; _CM_IMPL=0
    kind="${d%%|*}"; d="${d#*|}"; handler="${d%%|*}"; d="${d#*|}"
    class="${d%%|*}"; d="${d#*|}"; _CM_DESC="${d%%|*}"; _CM_EX="${d#*|}"; _CM_CLASS="$class"; _CM_HANDLER="$handler"
    fromfile=bashbasicsbyvk_maincommands.sh
  fi
  if [ "$fromfile" != "bashbasicsbyvk_maincommands.sh" ]; then
    # the menu's own command: its loop handles it.
    if [ "$handler" = "back" ]; then _CM_ACT=back; else _CM_ACT=local; fi
    return 0
  fi
  case "$class" in
    nav|util)
      if [ "$handler" != "-" ] && declare -F "$handler" >/dev/null 2>&1; then
        # an unwired inherited command still runs from a MENU; from a TEXT prompt it must be wired
        if [ "$mode" = "text" ] && [ "$_CM_IMPL" = 1 ]; then _CM_ACT=block; else _CM_ACT=run; fi
      else _CM_ACT=block; fi ;;
    *)
      # act / filter / danger work on the main list. A MENU that does not block them keeps its
      # old behaviour (its loop decides); a TEXT prompt never takes them.
      if [ "$mode" = "menu" ]; then _CM_ACT=local; else _CM_ACT=block; fi ;;
  esac
  # "u" typed into a text prompt is always "go back" unless the map says otherwise
  if [ "$mode" = "text" ] && [ "$_CM_KEY" = "u" ] && [ "$_CM_ACT" = block ] && [ "$_CM_IMPL" = 1 ]; then _CM_ACT=back; _CM_DESC="Go back"; fi
  return 0
}

# is this word a command anywhere in the main table? (decides whether @word is an escape)
_cm_is_main_word() {
  local t="${1,,}" k d
  for k in "${!_CM_DEF[@]}"; do
    [[ "$k" == bashbasicsbyvk_maincommands.sh:* ]] || continue
    d="${_CM_DEF[$k]}"
    _cm_match "${d%%|*}" "${k#bashbasicsbyvk_maincommands.sh:}" "$t" && return 0
  done
  return 1
}

# @ escape.  @s → s   @@s → @s   @word (not a command) → unchanged
_cm_unescape() {
  _CM_LIT="$1"
  [[ "$1" == @* ]] || return 1
  local rest="${1#@}"
  if [[ "$rest" == @* ]] || _cm_is_main_word "$rest"; then _CM_LIT="$rest"; return 0; fi
  return 1
}

# ------------------------------------------------------------ one judge: would typing KEY here do something?
# Shared by the live suggestion ("could become: ..."), cc and the gates, so a hint can never offer a key
# that Enter would then reject.   _cm_usable MODE KEY   -> 0 = accepted (run / local / back), 1 = not
_cm_usable() {
  local sa="$_CM_ACT" sk="$_CM_KEY" sd="$_CM_DESC" se="$_CM_EX" sc="$_CM_CLASS" si="$_CM_IMPL" sh="$_CM_HANDLER" rc=1
  if [ -n "${_CM_LOCAL[${2,,}]+x}" ]; then rc=0
  else
    _cm_resolve "$1" "$2"
    case "$_CM_ACT" in run|local|back) rc=0 ;; esac
  fi
  _CM_ACT="$sa"; _CM_KEY="$sk"; _CM_DESC="$sd"; _CM_EX="$se"; _CM_CLASS="$sc"; _CM_IMPL="$si"; _CM_HANDLER="$sh"
  return $rc
}

# ------------------------------------------------------------ live suggestion
_cm_hint_fmt_one() {   # key desc ex
  local s="$1"
  [ -n "$3" ] && s="$3"
  [ -n "$2" ] && s+="  $2"
  printf '%s' "$s"
}

# sets _hint_want for the buffer typed so far.  $2 = menu|text (default menu)
_cm_hint() {
  local b="$1" mode="${2:-menu}"
  _hint_want=""
  if [ -n "$_CM_FLASH" ]; then
    if [ -z "$b" ]; then _hint_want="$_CM_FLASH"; return 0; fi
    _CM_FLASH=""
  fi
  [ -z "$b" ] && return 0
  [ "${#b}" -gt "$_CM_LIVE_MAX" ] && return 0   # longer than any command: no live lookup (Enter is the fallback)
  _cm_on || return 0
  [ "$_CM_BOOTED" = 1 ] || _cm_boot
  _cm_table_build "${_CM_MAP:-main}"
  # escape
  if [[ "$b" == @* ]]; then
    if _cm_unescape "$b"; then _hint_want="↳ enters the text \"$_CM_LIT\", not the command"; fi
    return 0
  fi
  local lb="${b,,}"
  if [ -n "${_CM_LOCAL[$lb]+x}" ]; then _hint_want="$b  →  ${_CM_LOCAL[$lb]}"; return 0; fi
  _cm_resolve "$mode" "$b"
  local more="" i k cnt=0
  # other commands this could still become
  if [ "${#b}" -le 4 ]; then
    local -A _mseen=()
    # keys this very prompt prints ("[c] continue", "c) copy link") first, then the map's keys —
    # and only those the prompt would really accept (same judge as Enter: _cm_usable)
    for k in "${!_CM_LOCAL[@]}"; do
      [[ "$k" == "$lb"* && "$k" != "$lb" ]] || continue
      _mseen["$k"]=1; more+="${more:+, }$k"; cnt=$(( cnt + 1 )); [ "$cnt" -ge 4 ] && break
    done
    for (( i=0; i<${#_ct_key[@]} && cnt<4; i++ )); do
      k="${_ct_key[i]}"
      [[ "$k" == "$lb"* && "$k" != "$lb" ]] || continue
      [[ "${_ct_tgt[i]}" == BLOCK ]] && continue
      [ -n "${_mseen[$k]+x}" ] && continue
      _cm_usable "$mode" "$k" || continue
      _mseen["$k"]=1; more+="${more:+, }$k"; cnt=$(( cnt + 1 ))
    done
  fi
  local esc=""; [ "$mode" = "text" ] && esc="  ·  @$b to type it as text"
  case "$_CM_ACT" in
    none)  [ -n "$more" ] && _hint_want="…  could become: $more" ;;
    local) _hint_want="$_CM_KEY  →  ${_CM_DESC:-command}${_CM_EX:+  (e.g. $_CM_EX)}${more:+   (also: $more)}" ;;
    run)   _hint_want="$_CM_KEY  →  ${_CM_DESC:-command}${esc}${more:+   (also: $more)}" ;;
    back)  _hint_want="$_CM_KEY  →  go back (cancels this)${esc}" ;;
    block) _hint_want="$_CM_KEY  →  ✗ not available here — Enter will cancel${esc}" ;;
  esac
  # no cut here: every painter expands a long suggestion onto the next rows (_bvk_hint_wrap)
  return 0
}

# ------------------------------------------------------------ aborting a flow
# A blocked command (or "go back") typed inside a nested prompt cancels the WHOLE flow:
# every following prompt of that flow returns at once, silently (echo/printf are muted), until
# the menu that owns the flow redraws and prints the one-line reason.
_cm_abort() {
  _CM_ABORT=1; _CM_ABORT_MSG="$1"; _CM_ABORT_DEPTH="$_CM_MDEPTH"; _CM_ABORT_N=0; _CM_MUTE=1
}
_cm_abort_clear() { _CM_ABORT=0; _CM_MUTE=0; _CM_ABORT_N=0; }

# Called at every redraw of a menu: the owner of the aborted flow reports and carries on.
_cm_abort_report() {
  [ "$_CM_ABORT" = 1 ] || return 0
  _cm_ctx_find
  [ "$_CM_FLOW" = 0 ] || return 0
  [ "$_CM_MDEPTH" -le "$_CM_ABORT_DEPTH" ] || return 0
  local m="$_CM_ABORT_MSG"
  _cm_abort_clear
  [ -n "$m" ] && echo "$m"
  return 0
}

# A prompt that fires while an abort is travelling up: answer it at once.
# returns 0 = short-circuited (caller returns 1), 1 = this prompt is where the abort lands / no abort
_cm_abort_swallow() {
  [ "$_CM_ABORT" = 1 ] || return 1
  _cm_ctx_find
  if [ "$_CM_FLOW" = 0 ] && [ "$_CM_MDEPTH" -le "$_CM_ABORT_DEPTH" ]; then return 1; fi
  _CM_ABORT_N=$(( _CM_ABORT_N + 1 ))
  if [ "$_CM_ABORT_N" -gt 400 ]; then   # a loop that never lets go — stop muting, let the user out
    _cm_abort_clear; return 1
  fi
  return 0
}

# ------------------------------------------------------------ running a main command from elsewhere
bvk_main_exec() {
  local c="${1,,}"
  case "$c" in
    q)      # q on the main loop's own prompt leaves the app; q anywhere else (a menu, a prompt inside a flow) closes to the main loop
            if [ "${_CM_MAP:-main}" = main ] && [ "${_CM_FLOW:-0}" = 0 ]; then _bvk_exit; else _bvk_quit; fi ;;
    h)      home_menu ;;
    s)      settings_menu ;;
    i)      infinity_stones_menu ;;
    -h)     open_help ;;
    disk)   df -h ;;
    ram)    free -h ;;
    health) bvk_health ;;
    lang)   bvk_lang ;;
    clear)  hash -r ;;
    sast)   bashbasicsbyvk_sast ;;
    -auth)  auth_menu ;;
    print)  bvk_print_cmd ;;
    loadtime|loadtime\ *) bvk_loadtime_cmd "$c" ;;
    cc)     bvk_cc_cmd ;;
    *)      return 1 ;;
  esac
}
# $2 = where the command was typed: menu (a list prompt) | text (a prompt inside a flow).  `cc` reads it
# to list only what that prompt would accept.
_CM_RUN_MODE=menu
_cm_run_main() {
  local h="${_CM_HANDLER:-bvk_main_exec}"
  [ "$h" = "-" ] && h=bvk_main_exec
  _CM_RUN_MODE="${2:-menu}"
  "$h" "$1"
}

# ------------------------------------------------------------ gate for MENUS (_read_choice)
# returns 0 = accept $choice ;  1 = re-prompt (a message was printed, caller redraws)
_cm_gate_choice() {
  _CC_PREFILL=""
  [ -n "$choice" ] || return 0
  [[ "$choice" == __* ]] && return 0
  _cm_on || return 0
  [ "$_CM_BOOTED" = 1 ] || _cm_boot
  _cm_table_build "$_CM_MAP"
  if [[ "$choice" == @* ]]; then echo "🔴  '@' only escapes text typed into a prompt — nothing to escape here"; return 1; fi
  _cm_resolve menu "$choice"
  case "$_CM_ACT" in
    none|local) return 0 ;;
    run)   local _g_main=0            # (the command may open screens that re-read the context: remember where WE are first)
           [ "${_CM_MAP:-main}" = main ] && [ "${_CM_FLOW:-0}" = 0 ] && _g_main=1
           _cm_run_main "$choice" menu
           if [ "${_BVK_TO_MAIN:-0}" = 1 ]; then
             if [ "$_g_main" = 1 ]; then _BVK_TO_MAIN=0                 # this IS the main loop: the q from the screen we opened has arrived
             else choice=q; return 0; fi                                # a menu: its own  q)  case closes it, up to the main loop
           fi
           return 1 ;;
    back)  choice="${_CM_MAP_BACK[$_CM_MAP]:-u}"; return 0 ;;
    block) echo "❌ Invalid command: $choice — not available in ${_CM_MAP}"; return 1 ;;
  esac
  return 0
}

_cm_read_choice() {
  _cm_on || { _read_choice_raw; return $?; }
  [ "$_CM_BOOTED" = 1 ] || _cm_boot
  _cm_ctx_find
  # an abort travelling up through a menu that is not its owner: leave this menu by its back key
  if [ "$_CM_ABORT" = 1 ] && { [ "$_CM_FLOW" != 0 ] || [ "$_CM_MDEPTH" -gt "$_CM_ABORT_DEPTH" ]; }; then
    choice="${_CM_MAP_BACK[$_CM_MAP]:-u}"; return 0
  fi
  while :; do
    _cm_ctx_find
    _read_choice_raw
    _cm_gate_choice && return 0
    # a message is on screen; draw the menu again below it (same convention as _bvk_invalid).
    # A command that opened a smart menu (print → "1) Copy …") leaves ITS rows in the row cache: rebuild them.
    # A menu whose list order depends on a setting (Settings › Display › Sort order typed as  s ) names a hook in
    # _vp_after_cmd_fn: it re-applies that setting to the menu's own arrays before the redraw.
    [ -n "${_vp_after_cmd_fn:-}" ] && "$_vp_after_cmd_fn"
    _vp_cache_reset; _vp_prime_rows
    _vp_render_fresh
  done
}

# ------------------------------------------------------------ keys a smart menu prints itself
# A key the menu draws ("c) Create user", "q) Close") is THAT MENU'S command: it beats the map.
declare -gA _CM_LOCAL=()
_cm_local_clear() { _CM_LOCAL=(); }
_cm_local_collect() {   # reads the caller's _sm_rows_text/_sm_rows_token/_sm_ftr/_sm_hdr
  _CM_LOCAL=()
  local i t lab cell rx='^[[:space:]]*([A-Za-z0-9_-]{1,4})\)[[:space:]]+(.*)$' line
  for (( i=0; i<${#_sm_rows_token[@]}; i++ )); do
    t="${_sm_rows_token[i]}"; [ -z "$t" ] && continue
    lab="${_sm_rows_text[i]}"
    declare -F _vp_strip_ansi >/dev/null 2>&1 && { _vp_strip_ansi "$lab"; lab="$_vp_plain"; }
    [[ "$lab" =~ $rx ]] && lab="${BASH_REMATCH[2]}"
    _CM_LOCAL["${t,,}"]="$lab"
  done
  for line in "${_sm_ftr[@]}" "${_sm_hdr[@]}"; do
    declare -F _vp_strip_ansi >/dev/null 2>&1 && { _vp_strip_ansi "$line"; line="$_vp_plain"; }
    while IFS= read -r cell; do
      [[ "$cell" =~ $rx ]] && _CM_LOCAL["${BASH_REMATCH[1],,}"]="${BASH_REMATCH[2]}"
    done <<< "${line//   /$'\n'}"
  done
}

# ------------------------------------------------------------ shared tail of the text and item-picker gates
# _cm_gate_dispatch <typed>   the typed text is not a key of the prompt itself: is it a command?  Sets _CM_OUT (what the prompt gets:
# the text, its un-escaped literal, or "" when the flow is cancelled).  returns 0 = accept · 3 = a command ran (ask again) · 4 = flow aborted
_cm_gate_dispatch() {
  local t="$1"
  _CM_OUT="$t"
  [ "$_CM_BOOTED" = 1 ] || _cm_boot
  _cm_table_build "$_CM_MAP"
  if _cm_unescape "$t"; then _CM_OUT="$_CM_LIT"; return 0; fi
  _cm_resolve text "$t"
  case "$_CM_ACT" in
    none|local) return 0 ;;
    run)   _cm_run_main "$t" text
           [ "${_BVK_TO_MAIN:-0}" = 1 ] && { _cm_abort ""; _CM_OUT=""; return 4; }   # q: cancel this flow silently, the menus close up to the main loop
           return 3 ;;
    back)  _cm_abort "↩️  Back"; _CM_OUT=""; return 4 ;;
    block) _cm_abort "❌ Invalid command: $t — exiting"; _CM_OUT=""; return 4 ;;
  esac
  return 0
}

# ------------------------------------------------------------ gate for the item picker (_multi_prompt_loop)
# uses the caller's _buf.  returns 0 = accept · 1 = a command ran, ask again
_cm_gate_multi() {
  local t="$_buf"
  _CC_PREFILL=""
  [ -n "$t" ] || return 0
  _cm_on || return 0
  [[ "$t" =~ ^[0-9a,\ -]+$ ]] && return 0
  [ -n "${_CM_LOCAL[${t,,}]+x}" ] && return 0
  _cm_gate_dispatch "$t"
  [ $? = 3 ] && return 1          # a command ran: ask again
  _buf="$_CM_OUT"
  return 0
}

# ------------------------------------------------------------ gate for SMART MENUS (read -p with a numbered list)
# uses the caller's _sm_result / _sm_rows_token / _sm_ftr / _sm_mode.
# returns 0 = accept ; 1 = re-run the menu ; 2 = flow aborted (var stays empty)
_cm_gate_sm() {
  local t="$_sm_result" lt tok
  _CC_PREFILL=""
  [ -n "$t" ] || return 0
  _cm_on || return 0
  lt="${t,,}"
  # a key the menu itself prints (rows or footer) is that menu's own command
  [ -n "${_CM_LOCAL[$lt]+x}" ] && return 0
  # numbers, ranges, lists, "a" (all)
  [[ "$t" =~ ^[0-9a,\ -]+$ ]] && return 0
  [ "$_CM_BOOTED" = 1 ] || _cm_boot
  _cm_table_build "$_CM_MAP"
  if _cm_unescape "$t"; then _sm_result="$_CM_LIT"; return 0; fi
  # selection grammars (c-1,3 · s1-5) are the menu's business
  if [ "$_sm_mode" != single ] && [[ "$t" =~ ^[A-Za-z]+-{0,2}[0-9] ]]; then return 0; fi
  _cm_resolve text "$t"
  case "$_CM_ACT" in
    none|local) return 0 ;;
    run)   _cm_run_main "$t" text
           [ "${_BVK_TO_MAIN:-0}" = 1 ] && { _cm_abort ""; _sm_result=""; return 2; }   # q: cancel this flow silently, the menus close up to the main loop
           _CM_REDRAW_FRESH=1; return 1 ;;
    back)  _cm_abort "↩️  Back"; _sm_result=""; return 2 ;;
    block) _cm_abort "❌ Invalid command: $t — exiting"; _sm_result=""; return 2 ;;
  esac
  return 0
}

# ------------------------------------------------------------ gate + editor for FREE-TEXT prompts
# does the prompt list its own answers?  [y/n]  (a/b/c)  [1-3] ...  then no command layer
_cm_prompt_has_choices() {
  local p="$1"
  [[ "$p" =~ [\[\(][A-Za-z0-9]([A-Za-z0-9]*)(/[A-Za-z0-9]+)+[\]\)] ]] && return 0
  [[ "$p" =~ [\[\(][A-Za-z0-9]+(/[A-Za-z0-9]+)+[[:space:]]*, ]] && return 0     # [Y/n, c = cancel the delete]
  [[ "$p" =~ [\[\(][0-9]+-[0-9]+[\]\)] ]] && return 0
  [[ "$p" =~ [Pp]ress\ (any\ )?[Kk]ey ]] && return 0
  return 1
}

# The keys a PROMPT prints in its own text are that prompt's own answers and beat the map
# (same rule as a smart menu's footer):   [c] continue · [r] reduce   ·   c) copy link   g) new link   Enter) back
# Fills _CM_LOCAL (key -> label) from the prompt string.
_cm_prompt_collect() {
  local p="$1" rest cell lab rx
  _CM_LOCAL=()
  p="${p//$'\n'/   }"
  rx='\[([A-Za-z0-9-]{1,5})\][[:space:]]+([^·\[]*)'          # [c] continue  ·  [r] reduce
  rest="$p"
  while [[ "$rest" =~ $rx ]]; do
    lab="${BASH_REMATCH[2]}"; lab="${lab%%  *}"; lab="${lab%"${lab##*[![:space:]]}"}"; lab="${lab%:}"
    _CM_LOCAL["${BASH_REMATCH[1],,}"]="$lab"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  p="${p//  ·  /$'\n'}"; p="${p//·/$'\n'}"; p="${p//   /$'\n'}"
  rx='^[[:space:]]*([A-Za-z0-9_-]{1,5})\)[[:space:]]+(.*)$'    # c) copy link
  while IFS= read -r cell; do
    if [[ "$cell" =~ $rx ]]; then
      lab="${BASH_REMATCH[2]}"; lab="${lab%:*}"; lab="${lab%"${lab##*[![:space:]]}"}"
      _CM_LOCAL["${BASH_REMATCH[1],,}"]="${lab:-answer}"
    fi
  done <<< "$p"
  # numbers are rows / counts, never commands
  local k; for k in "${!_CM_LOCAL[@]}"; do [[ "$k" =~ ^[0-9]+$ ]] && unset '_CM_LOCAL[$k]'; done
  return 0
}

_cm_gate_text() {   # $1 typed  $2 initial text ; sets _CM_OUT ; 0 accept · 3 ran a command (re-prompt) · 4 aborted
  local t="$1"
  _CM_OUT="$t"
  _CC_PREFILL=""
  [ -z "$t" ] && return 0
  [ "$t" = "$2" ] && return 0
  _cm_on || return 0
  # a key the prompt prints itself is THAT prompt's answer
  [ -n "${_CM_LOCAL[${t,,}]+x}" ] && return 0
  _cm_gate_dispatch "$t"
}

# ---- tiny line editor with a live hint row (replaces `read -e` for plain text prompts)
_cm_hint_row() {   # paints _hint_want on the row under the prompt; leaves the cursor at column 0 of the prompt row
  local want="$1"
  [ "$want" = "$_CM_HINT_CUR" ] && { builtin printf '\r'; return 0; }
  _CM_HINT_CUR="$want"
  if [ -n "$want" ]; then
    declare -F _bvk_clip >/dev/null 2>&1 && { _bvk_clip "$want"; want="$_BVK_CLIP"; }      # a hint longer than the row would wrap and scroll the screen
    builtin printf '\n\r\033[2K\033[2m%s\033[0m\033[1A\r' "$want"
  else builtin printf '\n\r\033[2K\033[1A\r'; fi
}
_cm_complete() {   # path completion for the word before the cursor  → sets _ce_buf/_ce_pos
  local before="${_ce_buf:0:_ce_pos}" after="${_ce_buf:_ce_pos}" word pre
  word="${before##*[[:space:]]}"; pre="${before%"$word"}"
  local -a m=(); local x
  while IFS= read -r x; do m+=("$x"); done < <(compgen -f -- "${word/#\~/$HOME}" 2>/dev/null | head -200)
  [ "${#m[@]}" -eq 0 ] && return 1
  local pick="${m[0]}"
  if [ "${#m[@]}" -gt 1 ]; then
    local len=${#pick} j
    for x in "${m[@]}"; do
      j=0; while [ "$j" -lt "$len" ] && [ "${x:j:1}" = "${pick:j:1}" ]; do j=$(( j + 1 )); done; len=$j
    done
    pick="${pick:0:len}"
  elif [ -d "$pick" ]; then pick+="/"; fi
  [ "$pick" = "$word" ] && return 1
  _ce_buf="${pre}${pick}${after}"; _ce_pos=$(( ${#pre} + ${#pick} ))
  return 0
}
_CE_ROW=0     # rows between the first row of the prompt and the row the cursor is on (after the last draw)
_cm_edit_draw() {   # redraw the whole prompt + text; long text WRAPS onto the next rows like `read -e` does
  local lastp="${_ce_prompt##*$'\n'}" W pw bw T tp erow ecol trow tcol hint="${_CM_HINT_SHOW:-}"
  if ! declare -F _bvk_dispw >/dev/null 2>&1; then          # helper not loaded: old single-row redraw
    builtin printf '\r\033[K%s%s' "$lastp" "$_ce_buf"
    local back=$(( ${#_ce_buf} - _ce_pos )); [ "$back" -gt 0 ] && builtin printf '\033[%dD' "$back"
    return 0
  fi
  _bvk_cols; W=$_BVK_COLS
  # a very long text (a big paste) is not wrapped over hundreds of rows: it stays ONE row that scrolls with the cursor
  if (( ${#_ce_buf} > W * ( ${_vp_rows_now:-24} > 14 ? ${_vp_rows_now:-24} - 8 : 6 ) )); then
    _bvk_fit_input "$lastp" "$_ce_buf" "$_ce_pos"
    builtin printf '\r'; [ "$_CE_ROW" -gt 0 ] && builtin printf '\033[%dA' "$_CE_ROW"
    builtin printf '\033[J%s%s' "$_BVK_FIT_PROMPT" "$_BVK_FIT"
    [ "$_BVK_FIT_BACK" -gt 0 ] && builtin printf '\033[%dD' "$_BVK_FIT_BACK"
    _bvk_dispw "${_BVK_FIT_PROMPT}${_BVK_FIT}"
    _CE_ROW=0; _CE_ENDROW=0; _CE_ENDCOL=$(( _BVK_W % W )); _CE_FULL=0
    return 0
  fi
  _bvk_dispw "$lastp"; pw=$_BVK_W
  _bvk_dispw "$_ce_buf"; bw=$_BVK_W
  T=$(( pw + bw ))
  _bvk_dispw "${_ce_buf:0:_ce_pos}"; tp=$(( pw + _BVK_W ))
  # 1. back to the first row of the prompt, wipe everything from there down (old text, old hint row)
  builtin printf '\r'; [ "$_CE_ROW" -gt 0 ] && builtin printf '\033[%dA' "$_CE_ROW"
  builtin printf '\033[J%s%s' "$lastp" "$_ce_buf"
  # text that ends exactly at the right edge leaves the cursor in the "pending wrap" state: force it onto the next row
  (( T > 0 && T % W == 0 )) && builtin printf ' \r'
  erow=$(( T / W )); ecol=$(( T % W )); trow=$(( tp / W )); tcol=$(( tp % W ))
  # 2. cursor from the end of the text to where it belongs
  (( erow > trow )) && builtin printf '\033[%dA' $(( erow - trow ))
  builtin printf '\r'; (( tcol > 0 )) && builtin printf '\033[%dC' "$tcol"
  _CE_ROW=$trow
  # 3. dim hint on the rows below the text (a long one expands onto more rows), then back
  if [ -n "$hint" ]; then
    local hl hn=1
    if declare -F _bvk_hint_wrap >/dev/null 2>&1; then _bvk_hint_wrap "$hint" "${_CE_HINT_MAX:-3}"; hn=$_BVK_HINT_N; else _bvk_clip "$hint"; _BVK_HINT_LN=("$_BVK_CLIP"); fi
    (( erow > trow )) && builtin printf '\033[%dB' $(( erow - trow ))
    for hl in "${_BVK_HINT_LN[@]}"; do builtin printf '\n\r\033[2K\033[2m%s\033[0m' "$hl"; done
    builtin printf '\033[%dA\r' $(( erow + hn - trow ))
    (( tcol > 0 )) && builtin printf '\033[%dC' "$tcol"
  fi
  _CE_ENDROW=$erow; _CE_ENDCOL=$ecol; _CE_FULL=$(( T > 0 && T % W == 0 ? 1 : 0 ))
}
# leave the editor: wipe the hint row, put the cursor after the text on a fresh row
_cm_edit_leave() {
  if ! declare -F _bvk_dispw >/dev/null 2>&1; then builtin printf '\033[%dC\n' "$(( ${#_ce_buf} - _ce_pos ))" 2>/dev/null; return 0; fi
  [ "${_CE_ENDROW:-0}" -gt "$_CE_ROW" ] && builtin printf '\033[%dB' $(( _CE_ENDROW - _CE_ROW ))
  builtin printf '\r'; [ "${_CE_ENDCOL:-0}" -gt 0 ] && builtin printf '\033[%dC' "$_CE_ENDCOL"
  builtin printf '\033[J'
  [ "${_CE_FULL:-0}" = 1 ] || builtin printf '\n'
  _CE_ROW=0
}

_cm_edit_paste() {   # insert a pasted text at the cursor (the caller's _ce_buf/_ce_pos)
  local t="$1"
  [ -z "$t" ] && return 0
  if (( ${#_ce_buf} + ${#t} > ${_BVK_MAX_INPUT:-512} )); then
    _ce_deny="Too large: $(( ${#_ce_buf} + ${#t} )) characters (limit ${_BVK_MAX_INPUT:-512}). Not accepted; nothing was changed."
    _bvk_paste_drain
    return 0
  fi
  t="${t//$'\n'/ }"                                   # a typed-line prompt is one logical line: its line breaks become spaces
  _ce_buf="${_ce_buf:0:_ce_pos}${t}${_ce_buf:_ce_pos}"; _ce_pos=$(( _ce_pos + ${#t} ))
}

# _cm_line_edit PROMPT INITIAL VAR EDIT(1|0)   ->  0 ok · 1 EOF/aborted
_cm_line_edit() {
  local _ce_prompt="$1" init="$2" var="$3" can_complete="$4"
  local _ce_buf="$init" _ce_pos=${#init} key seq rc stty_orig mode=text
  local no_cmds=0 _ce_deny=""
  _cm_prompt_has_choices "$_ce_prompt" && no_cmds=1
  _CM_HINT_CUR=""
  stty_orig=$(stty -g 2>/dev/null)
  stty -icanon -echo min 1 time 0 2>/dev/null
  _BVK_SCR_PROMPT="${_ce_prompt##*$'\n'}"
  _CE_ROW=0; _CM_HINT_SHOW=""
  # lines above the prompt row are printed once; the prompt row + text are (re)drawn by _cm_edit_draw, which counts wrapped rows
  [[ "$_ce_prompt" == *$'\n'* ]] && builtin printf '%s\n' "${_ce_prompt%$'\n'*}"
  _bvk_paste_on
  # _CE_FILL: a text the caller offers (the rename screen: the old name).  The Up arrow, or a tap / click on the row just above the
  # prompt (the "Old:" line), puts it into the line.  Reports for the tap are asked for only while such a text is offered.
  [ -n "${_CE_FILL:-}" ] && declare -F _bvk_mouse_on >/dev/null 2>&1 && _bvk_mouse_on
  _cm_edit_draw
  # text that cc just typed in for you: show what it does, like any typed command
  if [ "${_CC_HINT_NOW:-0}" = 1 ]; then
    _CC_HINT_NOW=0
    if [ "$no_cmds" = 0 ] && [ -n "$_ce_buf" ]; then _cm_hint "$_ce_buf" text; _CM_HINT_SHOW="$_hint_want"; _cm_edit_draw; fi
  fi
  while :; do
    IFS= builtin read -rsn1 key; rc=$?
    if [ "$rc" -ne 0 ]; then _ce_buf=""; _CM_OUT=""; break; fi
    if [[ "$key" == $'\x1b' ]]; then
      seq=""
      while IFS= builtin read -rsn1 -t 0.02 key; do
        seq+="$key"
        case "$seq" in '['*[A-Za-z~]|O[A-Za-z]) break ;; esac
      done
      case "$seq" in
        '[200~') _bvk_paste_bracketed; _cm_edit_paste "$_BVK_PASTE" ;;   # a paste: ONE insert, ONE redraw (line breaks are text)
        '[A') [ -n "${_CE_FILL:-}" ] && { _ce_buf="$_CE_FILL"; _ce_pos=${#_ce_buf}; } ;;
        '[<'*) if [ -n "${_CE_FILL:-}" ] && declare -F _bvk_mouse_decode >/dev/null 2>&1 && _bvk_mouse_decode "$seq" && [ "$_MS_ACT" = press ] && _bvk_mouse_prow; then
                 (( _BVK_CROW - _MS_Y == _CE_ROW + 1 )) && { _ce_buf="$_CE_FILL"; _ce_pos=${#_ce_buf}; }
               fi ;;
        '[D') [ "$_ce_pos" -gt 0 ] && _ce_pos=$(( _ce_pos - 1 )) ;;
        '[C') [ "$_ce_pos" -lt "${#_ce_buf}" ] && _ce_pos=$(( _ce_pos + 1 )) ;;
        '[H'|'[1~'|OH) _ce_pos=0 ;;
        '[F'|'[4~'|OF) _ce_pos=${#_ce_buf} ;;
        '[3~') [ "$_ce_pos" -lt "${#_ce_buf}" ] && _ce_buf="${_ce_buf:0:_ce_pos}${_ce_buf:_ce_pos+1}" ;;
      esac
    else
      # a paste that came without the bracketed-paste markers: the bytes already waiting are part of it (see viewport.sh)
      if [ -z "$key" ] || [[ "$key" == [[:print:]] ]]; then
        if _bvk_paste_burst "${key:-$'\n'}"; then
          _cm_edit_paste "$_BVK_PASTE"
          [ "$_BVK_PASTE_ENTER" = 1 ] && break
          if [ "$no_cmds" = 0 ]; then _cm_hint "$_ce_buf" text; else _hint_want=""; fi
          _CM_HINT_SHOW="$_hint_want"; [ -n "$_ce_deny" ] && { _CM_HINT_SHOW="$_ce_deny"; _ce_deny=""; }; _cm_edit_draw
          continue
        fi
      fi
      case "$key" in
        ""|$'\r'|$'\n') break ;;
        $'\x7f'|$'\x08') [ "$_ce_pos" -gt 0 ] && { _ce_buf="${_ce_buf:0:_ce_pos-1}${_ce_buf:_ce_pos}"; _ce_pos=$(( _ce_pos - 1 )); } ;;
        $'\x01') _ce_pos=0 ;;
        $'\x05') _ce_pos=${#_ce_buf} ;;
        $'\x15') _ce_buf="${_ce_buf:_ce_pos}"; _ce_pos=0 ;;
        $'\x0b') _ce_buf="${_ce_buf:0:_ce_pos}" ;;
        $'\x04') [ -z "$_ce_buf" ] && { _CM_OUT=""; rc=1; break; } ;;
        $'\t') [ "$can_complete" = 1 ] && _cm_complete ;;
        [[:cntrl:]]) : ;;
        *) if (( ${#_ce_buf} >= ${_BVK_MAX_INPUT:-512} )); then _ce_deny="Too large: over ${_BVK_MAX_INPUT:-512} characters. Not accepted."
           else _ce_buf="${_ce_buf:0:_ce_pos}${key}${_ce_buf:_ce_pos}"; _ce_pos=$(( _ce_pos + 1 )); fi ;;
      esac
    fi
    if [ "$no_cmds" = 0 ]; then _cm_hint "$_ce_buf" text; else _hint_want=""; fi
    _CM_HINT_SHOW="$_hint_want"; [ -n "$_ce_deny" ] && { _CM_HINT_SHOW="$_ce_deny"; _ce_deny=""; }
    _cm_edit_draw
  done
  # leave: wipe the hint row, put the cursor after the text, newline
  _bvk_paste_off
  declare -F _bvk_mouse_off >/dev/null 2>&1 && _bvk_mouse_off
  _CM_HINT_SHOW=""
  _cm_edit_leave
  [ -n "$stty_orig" ] && stty "$stty_orig" 2>/dev/null
  if [ "$rc" -ne 0 ]; then return 1; fi
  _CM_OUT="$_ce_buf"
  return 0
}

_cm_text_read_done() {   # put back the keys that were known before this prompt (usually none)
  _CM_LOCAL=()
  [ -n "$1" ] && eval "${1/declare -A/declare -gA}" 2>/dev/null
  return 0
}

# Entry used by the read shim. Returns the exit status the shim should give the caller.
# Sets _CM_RESULT to the value for the variable.
_cm_text_read() {   # prompt initial var can_complete
  [ "${_SL_WANT:-0}" = 1 ] && _sl_ready          # smartload: the wait is over
  local prompt="$1" init="$2" var="$3" cc="$4" st
  local start="$init"        # what the editor starts with; $init stays "what was already there" for the gate
  _cm_on || return 99
  [ "$_CM_BOOTED" = 1 ] || _cm_boot
  local _tr_saved; _tr_saved="$(declare -p _CM_LOCAL 2>/dev/null)"
  _cm_prompt_collect "$prompt"
  while :; do
    # a command that ran last time (print, cc, settings ...) may have asked questions of its own: each answer opened a wait, and
    # nothing closed it before this prompt is drawn again.  The prompt is up again here: the wait is over (else a bar sits on it)
    [ "${_SL_WANT:-0}" = 1 ] && _sl_ready
    _cm_ctx_find
    _cm_line_edit "$prompt" "$start" "$var" "$cc" || { _CM_RESULT=""; _cm_text_read_done "$_tr_saved"; return 1; }
    if _cm_prompt_has_choices "$prompt"; then _CM_RESULT="$_CM_OUT"; _cm_text_read_done "$_tr_saved"; return 0; fi
    _cm_gate_text "$_CM_OUT" "$init"; st=$?
    case "$st" in
      0) _CM_RESULT="$_CM_OUT"; _cm_text_read_done "$_tr_saved"; return 0 ;;
      3) init=""; start="${_CC_PREFILL:-}"; _CC_PREFILL=""; [ -n "$start" ] && _CC_HINT_NOW=1; continue ;;   # a command ran (e.g. settings, cc); ask again — cc leaves its pick in the line
      *) _CM_RESULT=""; _cm_text_read_done "$_tr_saved"; return 1 ;;           # aborted: the flow unwinds
    esac
  done
}

# ------------------------------------------------------------ show / lint
# o --map-show [menu]   prints the effective command table of a menu
_cm_show() {
  _cm_boot; _cm_ensure_all
  local m="${1:-main}" i
  [ -n "${_CM_MAP_LINES[$m]+x}" ] || { echo "no such map: $m"; echo "maps: ${_CM_MAP_NAMES[*]}"; return 1; }
  _CM_MAP="$m"; _CM_TBL_MAP=""; _cm_table_build "$m"
  printf 'MAP %s  (%s)  file=%s  back=%s  parent=%s\n' "$m" "${_CM_MAP_KIND[$m]}" "${_CM_MAP_FILE[$m]##*/}" "${_CM_MAP_BACK[$m]}" "${_CM_MAP_PARENT[$m]}"
  printf '%-10s %-7s %-8s %-7s %s\n' KEY KIND ACTION FROM DESCRIPTION
  local tgt d desc act from
  for (( i=0; i<${#_ct_key[@]}; i++ )); do
    tgt="${_ct_tgt[i]}"
    case "$tgt" in
      BLOCK) act=BLOCK; desc="(blocked)"; from="${_ct_map[i]}" ;;
      BACK)  act=back;  desc="go back";   from="${_ct_map[i]}" ;;
      *)  d="${_CM_DEF[$tgt]-}"; desc="${d#*|*|*|}"; desc="${desc%%|*}"
          act="${d#*|}"; act="${act%%|*}"; [ "$act" = "-" ] && act="loop"; [ -z "$d" ] && act="UNDEF"
          from="${tgt%%:*}"; from="${from#bashbasicsbyvk_}"; from="${from%commands.sh}" ;;
    esac
    printf '%-10s %-7s %-8s %-7s %s%s\n' "${_ct_key[i]}" "${_ct_kind[i]}" "$act" "$from" "$desc" "$([ "${_ct_impl[i]}" = 1 ] && printf '   [inherited – not wired here]')"
  done
}

# o --map-doc   the main-command reference as a markdown table, straight from cmd_def (the docs paste it; tests/cmd_docs.sh
#               fails when the pasted copy is out of date, so a new command can never be missing from the docs)
_cm_doc() {
  _cm_boot
  local k id d kind handler class desc ex
  printf '| Command | Class | What it does | Example |\n|---|---|---|---|\n'
  while IFS= read -r id; do
    d="${_CM_DEF[bashbasicsbyvk_maincommands.sh:$id]}"
    kind="${d%%|*}"; d="${d#*|}"; handler="${d%%|*}"; d="${d#*|}"; class="${d%%|*}"; d="${d#*|}"; desc="${d%%|*}"; ex="${d#*|}"
    printf '| `%s` | %s | %s | %s |\n' "$id" "$class" "$desc" "${ex:+\`$ex\`}"
  done < <(for k in "${!_CM_DEF[@]}"; do [[ "$k" == bashbasicsbyvk_maincommands.sh:* ]] && echo "${k#bashbasicsbyvk_maincommands.sh:}"; done | LC_ALL=C sort)
}

# o --map-lint   every gap in the wiring
_cm_lint() {
  _cm_boot; _cm_ensure_all
  local m k d bad=0 id line key tgt
  local -a mainkeys=()
  for k in "${!_CM_DEF[@]}"; do [[ "$k" == bashbasicsbyvk_maincommands.sh:* ]] && mainkeys+=("${k#bashbasicsbyvk_maincommands.sh:}"); done
  for m in "${_CM_MAP_NAMES[@]}"; do
    [ "$m" = main ] && continue
    [ "${_CM_MAP_PARENT[$m]:-main}" != main ] && continue   # child map (xui_rb ...): the parent is wired in full
    local wired=$'\n'
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      key="${line%%|*}"; tgt="${line#*|*|}"; tgt="${tgt%%|*}"
      wired+="${key,,}"$'\n'
      case "$tgt" in
        BLOCK|BACK) ;;
        *) [ -n "${_CM_DEF[$tgt]+x}" ] || { printf '✗ %s: %s → %s is not defined\n' "$m" "$key" "$tgt"; bad=$(( bad + 1 )); }
           d="${_CM_DEF[$tgt]-}"; if [ -n "$d" ]; then d="${d#*|}"; d="${d%%|*}"
             [ "$d" != "-" ] && [ "$d" != back ] && ! declare -F "$d" >/dev/null 2>&1 && printf '! %s: %s handler "%s" is not a function (yet)\n' "$m" "$key" "$d"; fi ;;
      esac
    done <<< "${_CM_MAP_LINES[$m]}"
    for id in "${mainkeys[@]}"; do
      case "$wired" in *$'\n'"${id,,}"$'\n'*) ;; *) printf '· %s: main command "%s" is not wired (inherited silently) — run: o --map-gen\n' "$m" "$id"; bad=$(( bad + 1 )) ;; esac
    done
    [ -n "${_CM_MAP_FUNC[$m]+x}" ] || :
  done
  local fn
  for fn in "${!_CM_MAP_FUNC[@]}"; do
    declare -F "$fn" >/dev/null 2>&1 || printf '! map %s claims function %s which does not exist\n' "${_CM_MAP_FUNC[$fn]}" "$fn"
  done
  echo "maps: ${#_CM_MAP_NAMES[@]}   main commands: ${#mainkeys[@]}   gaps: $bad"
  [ "$bad" -eq 0 ]
}
