#!/usr/bin/env bash
# ============================================================
#  LOADTIME  —  what took how long between "Enter" and "menu ready"
#
#  Typed at any prompt:
#      loadtime        the last screen change:  previous menu → this menu, event by event
#      loadtime 2      the one before that (3, 4 …)
#      loadtime all    the last 25 screen changes in one table
#  Every report ends with the same two options as  p- :  1) copy to clipboard  2) save as txt
#
#  How it works
#  ------------
#  A screen change starts when the person presses ENTER at a prompt and ends when the next
#  prompt (menu, settings screen, text question) is drawn and waiting for a key.  Between those
#  two moments everything that costs time writes ONE line to a small log file:
#
#      kind <TAB> start(µs) <TAB> duration(µs) <TAB> pid <TAB> flags <TAB> name <TAB> detail
#
#      T  Enter pressed            R  prompt ready           S  a timed step (_lt_b … _lt_e)
#      X  an external command      N  a network request      M  a marker        P  process start
#
#  A file (not a variable) is used so that  $( … )  subshells, background helpers and the Python
#  tools can all write to the same timeline.  The log only receives lines while a screen change
#  is in progress, so idling at a prompt costs nothing.  The report itself is built by
#  _3bvk_loadtime_core (python3) from that file.
#
#  Network   curl  → DNS / TCP / TLS / first byte / download, per request (curl ≥ 8.3).
#            Python tools → the same, hooked into http.client by _3bvk_lt.py.
#            git / rclone → whole-command time, plus a fresh probe of the host in the report.
#
#  Switch off:   export VK_LOADTIME=0
# ============================================================

_LT_ON=0                # 1 = recording
_LT_PEND=""             # non-empty = a screen change is in progress (exported: Python tools read it)
_LT_BG=""               # non-empty = this process is a background helper (exported)
_LT_MUTE=""             # non-empty = a tool command (print / loadtime) is running: record nothing
_LT_LOG=""
_LT_SCREEN="shell"      # name of the screen the person is looking at
_LT_MAIN_PID=$$
_LT_LINES=0
_LT_SB_T=(); _LT_SB_N=(); _LT_SB_D=()      # stack of open steps
_LT_CURL_OK=""          # 1 when curl can write its own phase timings (needs curl ≥ 8.3)

# ── the log ──────────────────────────────────────────────────────────────────────────────
# _lt_w KIND START DUR NAME [DETAIL]   (never prints, never fails)
# The main shell collects its lines in memory and writes them in one go when a prompt is reached
# (_lt_flush) — a file write per event would itself show up as load time.  Subshells ($( ), helpers)
# cannot share memory with the main shell, so they append to the file straight away.
_LT_BUF=()
_lt_w() {
  local n="${4//[$'\t\n\r']/ }" d="${5//[$'\t\n\r']/ }" l
  builtin printf -v l '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "${BASHPID:-$$}" "$_LT_BG" "$n" "$d"
  if [ "${BASHPID:-$$}" = "$_LT_MAIN_PID" ]; then _LT_BUF+=("$l")
  else builtin printf '%s\n' "$l" >>"$_LT_LOG" 2>/dev/null; fi
  _LT_LINES=$(( _LT_LINES + 1 ))
  return 0
}
_lt_flush() {
  (( ${#_LT_BUF[@]} )) || return 0
  builtin printf '%s\n' "${_LT_BUF[@]}" >>"$_LT_LOG" 2>/dev/null
  _LT_BUF=()
}

# ── steps:  _lt_b "name" [detail]  …work…  _lt_e [detail] ────────────────────────────────
_lt_b() {
  [ "$_LT_ON" = 1 ] || return 0                     # always push (even when idle) so every _lt_e pops its own _lt_b
  _LT_SB_T+=("${EPOCHREALTIME/[.,]/}"); _LT_SB_N+=("$1"); _LT_SB_D+=("${2:-}")
  return 0
}
_lt_e() {
  local n=${#_LT_SB_T[@]}
  (( n )) || return 0
  local t0="${_LT_SB_T[n-1]}" nm="${_LT_SB_N[n-1]}" dt="${_LT_SB_D[n-1]}"
  unset '_LT_SB_T[n-1]' '_LT_SB_N[n-1]' '_LT_SB_D[n-1]'
  [ -n "$_LT_PEND" ] && [ -z "$_LT_MUTE" ] || return 0   # logged only while a screen change is in progress
  local t1="${EPOCHREALTIME/[.,]/}"
  _lt_w S "$t0" "$(( t1 - t0 ))" "$nm" "${1:-$dt}"
}
# a marker: "something happened now"
_lt_mark() {
  [ "$_LT_ON" = 1 ] && [ -n "$_LT_PEND" ] && [ -z "$_LT_MUTE" ] || return 0
  _lt_w M "${EPOCHREALTIME/[.,]/}" 0 "$1" "${2:-}"
}
# run a command as one step, from the shell (not for functions that set variables in a $( ) )
_lt_run() { local _n="$1"; shift; _lt_b "$_n"; "$@"; local _rc=$?; _lt_e; return $_rc; }

# Run as a background helper: its commands are logged, but flagged "did not block the menu".
_lt_bg()   { _LT_BG=1; export _LT_BG; }
# Daemons and animators: record nothing at all.
_lt_off()  { _LT_ON=0; _LT_PEND=""; export _LT_PEND; }

# ── screen changes ───────────────────────────────────────────────────────────────────────
# a readable name for "the screen the person is on": the nearest function that is not plumbing
_lt_screen_id() {
  _LT_SID=""
  local i n=${#FUNCNAME[@]} fn m
  for (( i=1; i<n; i++ )); do
    fn="${FUNCNAME[i]}"
    case "$fn" in
      _lt_*|_cm_*|_multi_*|select_items_common|select_imaginary_items_common|_read_choice*|read|_sm_*|_vp_*|_input_*|_print_input_line|_mc_*|_st_*|source|main|echo|printf|_map_deliver|bvk_*) continue ;;
    esac
    m="${_CM_MAP_FUNC[$fn]-}"
    if [ -n "$m" ]; then _LT_SID="$m"; return 0; fi
    fn="${fn#_}"; fn="${fn#handle_}"; fn="${fn%_menu}"; fn="${fn%_loop}"; fn="${fn%_settings}"
    _LT_SID="${fn//_/ }"; return 0
  done
  _LT_SID="main"
}

# ENTER was pressed at a prompt.  $1 = what was typed (or chosen)   $2 = a friendlier label (optional)
_lt_enter() {
  [ "$_LT_ON" = 1 ] && [ -z "$_LT_MUTE" ] || return 0
  _LT_PEND=1
  _lt_w T "${EPOCHREALTIME/[.,]/}" 0 "$1" "${_LT_SCREEN}|${2:-}"
  _lt_flush
  # keep the log small: after ~4000 lines keep only the recent tail
  if (( _LT_LINES > 4000 )); then
    local keep; keep="$(tail -n 2500 "$_LT_LOG" 2>/dev/null)" && printf '%s\n' "$keep" >"$_LT_LOG" 2>/dev/null
    _LT_LINES=2500
  fi
  return 0
}

# a prompt is drawn and is now waiting for a key.   $1 = kind (menu | smart | settings | text)   $2 = screen name
_lt_ready() {
  [ "$_LT_ON" = 1 ] && [ -n "$_LT_PEND" ] && [ -z "$_LT_MUTE" ] || return 0
  local t="${EPOCHREALTIME/[.,]/}"
  _LT_PEND=""
  if [ -n "${2:-}" ]; then _LT_SID="$2"; else _lt_screen_id; fi
  _LT_SCREEN="$_LT_SID"
  _lt_w R "$t" 0 "$_LT_SID" "$1"
  _lt_flush
  return 0
}

# Tool commands (print / loadtime) must not count as a screen change themselves.
_lt_tool_begin() { _LT_MUTE=1; }
_lt_tool_end()   { _LT_MUTE=""; _LT_PEND=""; }

# ── externals: every command that costs a fork shows up on the timeline ───────────────
# _lt_xrun NAME ARGS…   (the wrappers below call it; when nothing is being timed it only runs the command)
_lt_xrun() {
  local n="$1"; shift
  if [ "$_LT_ON" != 1 ] || [ -z "$_LT_PEND" ] || [ -n "$_LT_MUTE" ]; then command "$n" "$@"; return $?; fi
  local t0="${EPOCHREALTIME/[.,]/}" rc lab="$n" a
  command "$n" "$@"; rc=$?
  local t1="${EPOCHREALTIME/[.,]/}"
  # a short label: python3 → the script's name, timeout → the command it runs
  case "$n" in
    python3|python)
      a="${1:-}"
      case "$a" in
        -|"") lab="$n (inline script)" ;;
        -c)   lab="$n -c" ;;
        -*)   lab="$n $a" ;;
        *)    lab="$n ${a##*/}" ;;
      esac ;;
    timeout)
      a="${1:-}"
      if [[ "$a" =~ ^[0-9.]+[smhd]?$ ]]; then lab="timeout ${2##*/} ${3:-}"; else lab="timeout ${1##*/} ${2:-}"; fi ;;
    git|rclone|sqlite3) lab="$n ${1:-}" ;;
    node) lab="node ${1##*/}" ;;
  esac
  _lt_w X "$t0" "$(( t1 - t0 ))" "$lab" "rc=$rc"
  return $rc
}
_lt_install_externals() {
  local c
  for c in python3 python rclone git node stat stty find du df ls uname date readlink realpath dirname basename \
           mktemp wc tput timeout sqlite3 cp mv rm mkdir touch ln tar zip unzip; do
    # only wrap what exists: `command -v name` must keep telling the truth
    type -P "$c" >/dev/null 2>&1 || continue
    eval "$c() { _lt_xrun $c \"\$@\"; }"
  done
  type -P curl >/dev/null 2>&1 && curl() { _lt_curl "$@"; }
}

# curl: one line per request with the phase times (DNS · TCP · TLS · first byte · download)
_lt_curl_probe() {
  [ -n "$_LT_CURL_OK" ] && return 0
  local v; v="$(command curl --version 2>/dev/null)"; v="${v#curl }"; v="${v%% *}"
  local maj="${v%%.*}" min="${v#*.}"; min="${min%%.*}"
  if [[ "$maj" =~ ^[0-9]+$ && "$min" =~ ^[0-9]+$ ]] && { (( maj > 8 )) || (( maj == 8 && min >= 3 )); }; then _LT_CURL_OK=1; else _LT_CURL_OK=0; fi
}
_lt_curl() {
  if [ "$_LT_ON" != 1 ] || [ -z "$_LT_PEND" ] || [ -n "$_LT_MUTE" ]; then command curl "$@"; return $?; fi
  _lt_curl_probe
  local -a a=()
  local x url="" fmt="" have_fmt=0 skip=0
  for x in "$@"; do
    if (( skip )); then fmt="$x"; have_fmt=1; skip=0; continue; fi
    case "$x" in
      -w|--write-out) skip=1; continue ;;
      --write-out=*)  fmt="${x#--write-out=}"; have_fmt=1; continue ;;
    esac
    [[ "$x" =~ ^https?:// ]] && url="$x"
    a+=("$x")
  done
  local t0="${EPOCHREALTIME/[.,]/}" rc tf="" t1
  if [ "$_LT_CURL_OK" = 1 ]; then
    tf="$_LT_LOG.c.${BASHPID:-$$}.$RANDOM"
    local my="%output{>>$tf}ns=%{time_namelookup};co=%{time_connect};ap=%{time_appconnect};pt=%{time_pretransfer};st=%{time_starttransfer};tt=%{time_total};rd=%{time_redirect};code=%{response_code};ver=%{http_version};ip=%{remote_ip};dl=%{size_download};ul=%{size_upload};nc=%{num_connects};nr=%{num_redirects}"$'\n'
    # an existing -w keeps working: our part goes to a file, the caller's part to stdout as before
    if (( have_fmt )); then command curl "${a[@]}" -w "$my%{stdout}$fmt"; rc=$?
    else command curl "${a[@]}" -w "$my"; rc=$?; fi
  else
    if (( have_fmt )); then command curl "${a[@]}" -w "$fmt"; rc=$?; else command curl "${a[@]}"; rc=$?; fi
  fi
  t1="${EPOCHREALTIME/[.,]/}"
  # host + a path whose long segments (link ids, tokens) are shortened: they never reach the report
  local rest host path seg shown=""
  local -a segs=()
  rest="${url#*://}"; host="${rest%%[/?#]*}"; host="${host##*@}"
  path="${rest#"${rest%%[/?#]*}"}"; path="${path%%[?#]*}"
  IFS=/ read -ra segs <<<"$path"
  for seg in "${segs[@]}"; do
    [ -z "$seg" ] && continue
    (( ${#seg} > 18 )) && seg="${seg:0:6}…"
    shown+="/$seg"
  done
  local det="rc=$rc"
  if [ -n "$tf" ] && [ -r "$tf" ]; then IFS= read -r det <"$tf"; det="rc=$rc;$det"; rm -f "$tf"; fi
  _lt_w N "$t0" "$(( t1 - t0 ))" "curl ${host:-?}${shown}" "$det"
  return $rc
}

# ── process start: how long before "o" even began (bash start-up, PATH lookups) ─────────────
_lt_proc_age_us() {   # µs since this process was spawned, or non-zero return when unknown (needs /proc)
  [ -r "/proc/$$/stat" ] && [ -r /proc/uptime ] || return 1
  local st up rest ticks
  read -r st <"/proc/$$/stat" || return 1
  st="${st##*) }"                    # after "pid (comm) " — the name may hold spaces
  set -- $st                         # $1 = field 3 → starttime (field 22) is $20
  ticks="${20:-}"
  [[ "$ticks" =~ ^[0-9]+$ ]] || return 1
  read -r up rest </proc/uptime || return 1
  up="${up/./}"; [[ "$up" =~ ^[0-9]+$ ]] || return 1
  _LT_AGE=$(( 10#$up * 10000 - ticks * 10000 ))        # centiseconds → µs (CLK_TCK = 100)
  (( _LT_AGE >= 0 && _LT_AGE < 60000000 ))
}

# ── start ──────────────────────────────────────────────────────────────────────────────────
_lt_init() {
  [ "${VK_LOADTIME:-1}" = 0 ] && return 0
  [ -n "${EPOCHREALTIME:-}" ] || return 0              # bash < 5: no µs clock without a fork — stay off
  local d="${TMPDIR:-/tmp}"
  [ -d "$d" ] && [ -w "$d" ] || return 0
  _LT_LOG="$d/bvk-loadtime.${UID:-0}.$$.log"
  : >"$_LT_LOG" 2>/dev/null || return 0
  export BVK_LT_LOG="$_LT_LOG"
  _LT_ON=1; _LT_PEND=1; _LT_MAIN_PID=$$
  export _LT_PEND _LT_BG
  local now="${EPOCHREALTIME/[.,]/}" t0
  t0="$now"
  if _lt_proc_age_us; then
    t0=$(( now - _LT_AGE ))
    _lt_w P "$t0" "$_LT_AGE" "shell start: process spawn + bash init → first line of o" ""
  fi
  _lt_w T "$t0" 0 "o" "shell|launch"
  _lt_install_externals
  return 0
}
_lt_cleanup() { [ -n "$_LT_LOG" ] && [ "$$" = "$_LT_MAIN_PID" ] && rm -f "$_LT_LOG" "$_LT_LOG".c.* 2>/dev/null; return 0; }

# ── the command: loadtime [N | all] ───────────────────────────────────────────────────────
bvk_loadtime_cmd() {
  local arg="${1,,}"; arg="${arg#loadtime}"; arg="${arg# }"; arg="${arg//[^a-z0-9 ]/}"
  if [ "$_LT_ON" != 1 ] || [ ! -s "$_LT_LOG" ]; then
    echo "⏱  loadtime is switched off (VK_LOADTIME=0) or could not create its log file."
    return 0
  fi
  local core; core="$(command -v _3bvk_loadtime_core 2>/dev/null)" || core=""
  [ -n "$core" ] || { echo "❌ _3bvk_loadtime_core not found — reinstall bashbasicsbyvk."; return 0; }
  command -v python3 >/dev/null 2>&1 || { echo "❌ loadtime needs python3 to build its report."; return 0; }
  _lt_flush
  _lt_tool_begin
  local cols rows report
  cols="$(_term_cols 2>/dev/null)"; rows="$(_term_rows 2>/dev/null)"
  report="$(python3 -I "$core" "$_LT_LOG" --pick "${arg:-1}" --cols "${cols:-80}" \
      --meta "bash=${BASH_VERSION%%(*};cols=${cols:-?};rows=${rows:-?};screen=$_LT_SCREEN;os=$(uname -sr 2>/dev/null)" 2>&1)"
  builtin printf '\n%s\n' "$report"
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  if declare -F _map_deliver >/dev/null 2>&1; then
    _map_deliver "$report" "bvk-loadtime-$(date +%Y%m%d-%H%M%S).txt"
  fi
  _lt_tool_end
  return 0
}
