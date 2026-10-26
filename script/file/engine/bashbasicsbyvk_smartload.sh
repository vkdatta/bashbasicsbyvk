declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
# ============================================================
#  SMART LOAD  —  a loading bar for EVERY wait, drawn by itself
#
#     [░░░░████░░░░░░░░░░░░] Working on pn…  3s
#
#  Rule: wait time > loading bar.  Nothing calls it, nothing registers with it:
#  not a menu, not a command, not a function that will be written next year.
#  (Same idea as smartmenu: that file draws every menu by itself; this one draws
#  the bar by itself.)
#
#  What a "wait" is
#  ----------------
#  A wait starts when the person presses ENTER (or taps / clicks a row): the app
#  hears it through the same two events the loadtime recorder uses, _lt_enter
#  and _lt_ready.  It ends when the app is ready for the next key: a menu, a
#  settings screen or a text question is about to be drawn.  Everything that
#  runs in between is the wait, whatever it is: a replace-in-files, a Cloudflare
#  call, deleting 1000 items, walking into pn or nf.
#
#  When the bar shows
#  ------------------
#  Only if the wait is longer than 0.5 s (a short wait never flashes a bar), and
#  only while the screen is quiet.  Output restarts that clock:
#      echo / printf / clear  tell smartload "something is being written", so the
#      bar is wiped BEFORE the text appears and comes back only if the next silent
#      stretch is long again.  A function that prints a line and then thinks for
#      5 s gets its bar for those 5 s; a loop that prints 1000 lines fast gets none.
#
#  How it works
#  ------------
#  One tiny background animator is started once.  It sleeps on a pipe (no fork,
#  no polling cost) and is told what is going on with ONE letter, written by the
#  shims below:
#      B  a wait begins            A  something was printed: restart the clock
#      D  the wait is over         P  stop drawing and tell me if a bar is on screen
#  The bar is drawn ON the cursor's own row, starting at the cursor's column: it takes the
#  cursor's place (the cursor is hidden while the bar shows).  After Enter the cursor sits at
#  the start of a fresh row, so the bar is simply "where you would type next".  Save / restore
#  cursor and auto-wrap off mean the typed text above and left of it is never touched and
#  nothing ever scrolls, on any row.  Before the foreground writes, or draws a screen, it asks
#  the animator "is a bar showing?" (P) and wipes it (erase to the end of the row, cursor
#  shown again).  Nothing is run in a subshell: shell functions that fill global variables run
#  exactly as before.
#
#  Full-screen programs (nano, vim, less, htop ...) are NOT a wait: they own the whole terminal
#  and the person is working in them.  They are wrapped (see the end of this file) with
#  _sl_hold / _sl_release, so no bar is ever drawn over them.
#
#  Who has to do what
#  ------------------
#  Nobody, for any ordinary code: print with echo / printf, ask with read, draw
#  with the menu engines.  Only code that writes the terminal with  builtin printf
#  (engines, redraws) and may do so while a wait is on calls  _sl_pulse  first.
#  Code that draws its OWN progress bar calls  _sl_hold  before and  _sl_release
#  after (the bar then stays out of its way).
#
#  Safe everywhere: with no terminal (pipes, tests, cron) or  VK_SMARTLOAD=0  every
#  call is a no-op.  If the app dies, the animator notices and ends itself.
#  VK_SMARTLOAD_GRACE_MS=500 changes how long a wait must last before the bar shows (50 to 5000).  ONE delay for everything: an Enter, a click, a Space, a Left / Right,
#  the app start and a program's start-up all use it (there is no "light" or "slow" variant: the same action always behaves the same).
#  A TRANSFER'S PROGRESS BAR (x/n MB, %, speed, ETA) is not this bar and always wins over it: code that lets a transfer tool draw its own bar calls
#  _sl_hold / _sl_release around it (the fileapi services use _bb_progress_begin / _bb_progress_end, one shared pair in the fileapi lib).  _sl_hold wipes
#  a loading bar that is already showing; the loading bar comes back only after _sl_release, once the quiet period has passed again.
#  A child program that DRAWS ON the terminal (its own prompt or progress bar) is not a wait either: no bar while it runs (_sl_owned; VK_SMARTLOAD_AUTOHOLD=0 turns that off).
#  "Draws on the terminal" is a positive test, not a list of names: the child is exec'd (not a plain fork of the app), its stdout or stderr IS the terminal, and it has
#  WRITTEN something (wchar in /proc/<pid>/io above 0).  A helper that is still silent (python, node, a Go engine that is only computing) is a wait and gets the bar;
#  the moment it prints its first prompt / progress line the bar is wiped and stays away.  If /proc/<pid>/io can not be read the child counts as the owner (quiet side).
#  The plain silent utilities (rm, cp, sleep, find ...) are skipped without reading anything.
#
#  WHY IT SHOWED / WHY NOT: VK_SMARTLOAD_DEBUG=1 writes one line per decision to ${VK_SMARTLOAD_DEBUG_FILE:-${TMPDIR:-/tmp}/bvk-smartload.log}: which Enter opened a wait (and
#  which functions called it), what the label is, who closed it, which child owned the terminal, who held it back, when the bar was drawn and wiped.  `tail -f` it in a second terminal.
#
#  A PROGRAM THE PERSON CHOSE TO RUN (a script, a binary, a compiled file: run.sh's run_file) is not our app's environment.  The only wait is the start-up: from the launch
#  to the program's FIRST WRITE (_sl_launch).  The bar may show in that gap (after the same delay as everywhere); the moment the program has written anything
#  it is gone and never comes back for that program, and it ends for good when the program exits, or after VK_SMARTLOAD_LAUNCH_MAX_MS (default 8000) of silence.
#  "Has it written?" is read from /proc/<pid>/io (wchar > 0).  Any write counts, files too: the error is always on the quiet side (the bar leaves early, it is never
#  drawn over a program's screen).  If /proc/<pid>/io can not be read there is no bar at all for that launch.  Call sites write  _sl_launch <label> <command...>.
# ============================================================

_SL_ON=""             # 1 = running (needs a terminal, bash 5, mkfifo)
_SL_WANT=0            # 1 = between "Enter" and "ready for the next key": a wait is on
_SL_HOLD=0            # >0 = somebody draws its own progress: no bar
_SL_PID=""            # the animator
_SL_MAIN=$$
_SL_TTY=""
_SL_BASE=""
_SL_CTLFD=""; _SL_ACKFD=""
_SL_MSG=""            # file the animator reads its label from
_SL_LABEL=""
_SL_NEWLABEL=""
_SL_SIGT=0            # µs: when the animator's clock was last (re)started
_SL_GRACE=500000      # µs a wait must last before the bar shows (0.5 s, for every kind of Enter and for a program's start-up: what the header, the tests and VK_SMARTLOAD_GRACE_MS say)
_SL_LCAP=8000000      # µs: the start-up bar never lasts longer than this
_SL_LAUNCH=0          # 1 = a user program is starting / running (see _sl_launch)
_SL_KIDS=""; _SL_KT=0  # _sl_children: the answer, and when /proc was last scanned
_SL_DBG=""; _SL_T0=0   # VK_SMARTLOAD_DEBUG=1: the log file, and the µs the app started
_SL_OWNER=""; _SL_SILENT=""   # _sl_owned: who owns the terminal / which child holds it but has not written yet (for the log)
_SL_PULSE_US=50000    # µs between two "A" letters during a burst of output

# one line per decision when VK_SMARTLOAD_DEBUG=1 (a no-op otherwise); works in the animator too (it inherits the variables)
_sl_dbg() {
  [ -n "$_SL_DBG" ] || return 0
  builtin printf '%7d ms  %s\n' $(( (${EPOCHREALTIME/[.,]/} - _SL_T0) / 1000 )) "$*" >>"$_SL_DBG" 2>/dev/null
  return 0
}
_sl_from() { local i o=""; for (( i=${1:-2}; i < ${1:-2} + 5 && i < ${#FUNCNAME[@]}; i++ )); do o+="${o:+ < }${FUNCNAME[i]}"; done; builtin printf '%s' "${o:-main}"; }     # who called: the functions up the stack

# where to draw: the controlling terminal
_sl_target() {
  if [ -w /dev/tty ] && { : >/dev/tty; } 2>/dev/null; then _SL_TTY=/dev/tty; return 0; fi
  _SL_TTY=""; return 1
}

# is a child program of the app using the terminal?  (a tool with its own prompts / progress bar: gitpush, bvk-xfer, rclone, git ...)
# Then it is NOT a wait: no bar is drawn while it runs.  A child counts when it was exec'd (its command line differs from the app's: a subshell
# of the app is not one), has the terminal on fd 0, 1 or 2, and is not a plain silent utility.  Needs /proc; without it: always 1 (old behaviour).
_SL_PTS=""; _SL_PCMD=""

# the child pids of $1 → _SL_KIDS.  /proc/<pid>/task/<pid>/children needs CONFIG_PROC_CHILDREN, which many Android kernels lack: then /proc/*/stat is scanned
# for parent = $1 (the scan costs a few ms, so it is repeated at most every $2 µs, default 0.4 s).  VK_SMARTLOAD_NOCHILDREN=1 forces the scan (tests).
_sl_children() {
  local f="/proc/$1/task/$1/children" s l p k="" now=${EPOCHREALTIME/[.,]/}; local -a w
  if [ -z "${VK_SMARTLOAD_NOCHILDREN:-}" ] && [ -r "$f" ]; then
    _SL_KIDS=""; builtin read -r _SL_KIDS <"$f" 2>/dev/null; return 0   # the file has no trailing newline: read returns 1 but fills the variable
  fi
  (( now - _SL_KT < ${2:-400000} )) && return 0
  _SL_KT=$now
  for s in /proc/[0-9]*/stat; do
    l=""; builtin read -r l <"$s" 2>/dev/null; [ -n "$l" ] || continue
    l="${l##*) }"; w=($l)                                      # after the "(comm)" field: state, ppid, ...
    [ "${w[1]:-}" = "$1" ] || continue
    p="${s#/proc/}"; k+="${p%/stat} "
  done
  _SL_KIDS="$k"
  return 0
}

# has process $1 written anything yet?  0 = yes, or it can not be told · 1 = not yet.   wchar in /proc/<pid>/io counts every write() the process has made.
_sl_wrote() {
  local line w=-1
  while IFS= builtin read -r line; do
    case "$line" in "wchar: "*) w="${line#wchar: }"; break ;; esac
  done <"/proc/$1/io" 2>/dev/null
  [[ "$w" =~ ^[0-9]+$ ]] || return 0
  (( w > 0 ))
}

# is a child program of the app DRAWING on the terminal?  (a tool with its own prompts / progress bar: gitpush, bvk-xfer, rclone, git ...)  Then it is NOT a wait.
# Positive test: exec'd (its command line differs from the app's: a subshell of the app is not one) AND its stdout or stderr is the terminal AND it has written
# something.  A child that holds the terminal but is still silent is a wait (_SL_SILENT names it for the log).  Sets _SL_OWNER.  Without /proc: always 1.
_sl_owned() {
  [ -n "$_SL_PTS" ] || return 1
  local parent="$1" me="$2" kids c f comm; local -a cmd
  _SL_OWNER=""; _SL_SILENT=""
  _sl_children "$parent"; kids="$_SL_KIDS"
  [ -n "$kids" ] || return 1
  for c in $kids; do
    [ "$c" = "$me" ] && continue
    builtin read -r comm <"/proc/$c/comm" 2>/dev/null || continue
    case "$comm" in rm|cp|mv|find|zip|unzip|tar|sleep|sed|awk|grep|sort|cat|ls|du|df|stat|touch|mkdir|chmod|chown|head|tail|tr|cut|wc|tee|mkfifo|stty|tput|date|basename|dirname|readlink|realpath|xargs|diff|cmp|file|md5sum|sha256sum|ps|kill|true|false|test) continue ;; esac
    cmd=(); builtin mapfile -d '' -t cmd <"/proc/$c/cmdline" 2>/dev/null
    [ "${#cmd[@]}" -gt 0 ] && [ "${cmd[*]}" = "$_SL_PCMD" ] && continue      # same command line = a subshell of the app, not a tool
    for f in 1 2; do
      if [[ "/proc/$c/fd/$f" -ef "$_SL_PTS" ]]; then
        if _sl_wrote "$c"; then _SL_OWNER="$c $comm (fd $f is the terminal, it has written)"; return 0; fi
        _SL_SILENT="$c $comm"; break
      fi
    done
  done
  return 1
}

# start-up of a user program (animator side): has it written anything yet?   0 = yes, or it can not be told (the bar must go and stay away) · 1 = still silent / not started.
# $1 app pid  $2 the animator's own pid.  `kid` is a local of the animator (found once, then kept): the program is the first child that is neither the animator nor
# a plain fork of the app (same command line).  Written = wchar in /proc/<kid>/io is above 0: a fresh process has written nothing, whatever the interpreter reads.
_sl_kid_wrote() {
  local parent="$1" me="$2" c; local -a cmd
  if [ -z "$kid" ]; then
    _sl_children "$parent" 0
    for c in $_SL_KIDS; do
      [ "$c" = "$me" ] && continue
      cmd=(); builtin mapfile -d '' -t cmd <"/proc/$c/cmdline" 2>/dev/null
      [ "${#cmd[@]}" -gt 0 ] || continue
      [ "${cmd[*]}" = "$_SL_PCMD" ] && continue
      kid="$c"; break
    done
    [ -n "$kid" ] || return 1
  fi
  _sl_wrote "$kid"                            # exited, or /proc/<pid>/io is not readable: counts as written (no bar)
}

# the animator (a background copy of the shell; it only ever draws)
#   $1 tty  $2 parent pid  $3 grace µs  $4 label file  $5 command fd  $6 answer fd
_sl_anim() {
  local tty="$1" parent="$2" grace="$3" msgf="$4" cfd="$5" afd="$6"
  exec </dev/null >/dev/null 2>&1           # holds no pipe, no file and no terminal of the foreground
  trap '' INT QUIT                          # Ctrl-C belongs to the foreground
  declare -F _lt_off >/dev/null 2>&1 && _lt_off     # the animator's own work is not work
  local armed=0 paused=0 drawn=0 owned=0 t_arm=0 t_last=0 now tick cmd="" st launch=0 kid="" g="$grace" lcap="$_SL_LCAP" o_prev="" s_prev=""
  local W=22 BW=5 pos=0 dir=1 n=0 cols room maxmsg msg="" track blk left right line el t
  while :; do
    if (( armed && ! paused )); then tick=0.05; else tick=5; fi
    cmd=""
    builtin read -r -t "$tick" -N1 -u "$cfd" cmd 2>/dev/null
    case "$cmd" in
      B) armed=1; paused=0; drawn=0; launch=0; t_arm=${EPOCHREALTIME/[.,]/}; t_last=$t_arm; o_prev=""; s_prev=""; _sl_dbg "animator: armed (wait, delay $(( g / 1000 )) ms)" ;;
      L) armed=1; paused=0; drawn=0; launch=1; kid=""; t_arm=${EPOCHREALTIME/[.,]/}; t_last=$t_arm; _sl_dbg "animator: armed (a program is starting, delay $(( g / 1000 )) ms)" ;;   # a user program is starting
      A) armed=1; paused=0; t_last=${EPOCHREALTIME/[.,]/} ;;
      D) armed=0; paused=0; drawn=0; launch=0; _sl_dbg "animator: disarmed" ;;
      P) paused=1; builtin printf '%s\n' "$drawn" >&"$afd"; (( drawn )) && _sl_dbg "animator: bar stopped for a write / wipe"; drawn=0 ;;      # the foreground wipes the row when it is 1
    esac
    kill -0 "$parent" 2>/dev/null || break  # the app is gone: end too
    (( armed && ! paused )) || continue
    now=${EPOCHREALTIME/[.,]/}
    if (( launch )); then
      # a user program is starting: the bar is for the gap before its first write only.  Once it has written (or the cap is reached) the bar is wiped and this
      # animator sleeps until the foreground says the program is over: nothing may be drawn into the program's screen.
      if (( now - t_arm >= lcap )) || _sl_kid_wrote "$parent" "${BASHPID:-0}"; then
        (( now - t_arm >= lcap )) && _sl_dbg "animator: start-up cap reached, no more bar for this program" || _sl_dbg "animator: the program has written (or can not be told): no more bar for it"
        (( drawn )) && { builtin printf '\0337\033[K\033[?25h\0338' >"$tty" 2>/dev/null; drawn=0; }
        armed=0; continue
      fi
    elif _sl_owned "$parent" "${BASHPID:-0}"; then    # a tool is drawing on the terminal: wipe a bar that is showing, draw nothing
      [ "$_SL_OWNER" = "$o_prev" ] || { o_prev="$_SL_OWNER"; _sl_dbg "animator: NO bar, terminal owned by $_SL_OWNER"; }
      (( drawn )) && { builtin printf '\0337\033[K\033[?25h\0338' >"$tty" 2>/dev/null; drawn=0; }
      owned=1; continue
    elif (( owned )); then owned=0; o_prev=""; t_last=$now; _sl_dbg "animator: the tool that owned the terminal is gone, delay starts again"; continue
    elif [ -n "$_SL_SILENT" ] && [ "$_SL_SILENT" != "$s_prev" ]; then s_prev="$_SL_SILENT"; _sl_dbg "animator: child $_SL_SILENT holds the terminal but has not written: still a wait"; fi
    (( now - t_last >= g )) || continue
    if (( ! drawn )); then
      # first frame: size the bar to the screen and read the label.  The bar is drawn on the cursor's OWN row (never a row below it), so it
      # can never scroll the screen, not even on the last row; auto-wrap is switched off while it is drawn, so a long label is clipped
      # at the right edge instead of wrapping.
      cols="$(command stty size <"$tty" 2>/dev/null)"; cols="${cols##* }"
      [[ "$cols" =~ ^[0-9]+$ ]] && (( cols > 0 )) || cols=60
      W=22; BW=5
      room=$(( cols - 14 )); (( room < 12 )) && room=12
      (( W > room - 4 )) && W=$(( room - 4 ))
      (( W < 8 )) && W=8
      (( BW > W / 3 )) && BW=$(( W / 3 ))
      (( BW < 2 )) && BW=2
      maxmsg=$(( cols - W - 14 )); (( maxmsg < 0 )) && maxmsg=0
      msg=""; IFS= builtin read -r msg <"$msgf" 2>/dev/null
      msg="${msg}…"
      [ "${#msg}" -gt "$maxmsg" ] && msg="${msg:0:$(( maxmsg > 1 ? maxmsg - 1 : 0 ))}…"
      printf -v track '%*s' "$W" ''; track="${track// /░}"
      printf -v blk '%*s' "$BW" ''; blk="${blk// /█}"
      pos=0; dir=1; n=0
      drawn=1
      _sl_dbg "animator: bar DRAWN after $(( (now - t_arm) / 1000 )) ms, label '$msg'"
    fi
    n=$(( n + 1 ))
    if (( n % 2 )); then                     # the block moves every other tick (a sweep takes about 3 s)
      left="${track:0:pos}"; right="${track:0:$(( W - pos - BW ))}"
      el=$(( (now - t_arm) / 1000000 )); t=""
      (( el >= 2 )) && t="  ${el}s"
      line=$'\033[36m['"$left$blk$right"$']\033[0m '"$msg$t"
      builtin printf '\0337\033[?25l\033[?7l%s\033[K\033[?7h\0338' "$line" >"$tty" 2>/dev/null || break   # save, hide the cursor, no wrap, bar + erase the rest of the row, wrap on, restore
      pos=$(( pos + dir ))
      if (( pos >= W - BW )); then pos=$(( W - BW )); dir=-1
      elif (( pos <= 0 )); then pos=0; dir=1; fi
    fi
  done
  (( drawn )) && builtin printf '\033[K\033[?25h' >"$tty" 2>/dev/null     # the app died with a bar showing: leave a visible cursor and no bar behind
  exit 0
}

# ── the foreground side ──────────────────────────────────────────────────────────────────────

_sl_send() { builtin printf '%s' "$1" >&"$_SL_CTLFD" 2>/dev/null; }

_sl_spawn() {
  [ -n "$_SL_ON" ] || return 1
  _sl_anim "$_SL_TTY" "$_SL_MAIN" "$_SL_GRACE" "$_SL_MSG" "$_SL_CTLFD" "$_SL_ACKFD" &
  _SL_PID=$!
  disown "$_SL_PID" 2>/dev/null            # no job-table entry: no "Killed" notices, a bare  wait  never waits for it
  return 0
}

# is a bar on the screen right now?  If so, wipe its row.  (The animator stops drawing first and says what it had drawn.)
# Wipe = erase from the cursor to the end of its row and show the cursor again.  The cursor has not moved since the bar was drawn (save / restore), so this removes
# exactly the bar and nothing else.
_sl_wipe() {
  local st=""
  kill -0 "$_SL_PID" 2>/dev/null || return 0
  while builtin read -r -t 0 -u "$_SL_ACKFD" st 2>/dev/null; do builtin read -r -t 0.01 -u "$_SL_ACKFD" st 2>/dev/null || break; done
  _sl_send P
  builtin read -r -t 0.3 -u "$_SL_ACKFD" st 2>/dev/null || return 0
  [ "$st" = 1 ] && { builtin printf '\033[K\033[?25h' >"$_SL_TTY" 2>/dev/null; _sl_dbg "wiped the bar (before: $(_sl_from 2))"; }
  return 0
}

# wipe only when a bar can be there (it needs a silent grace period first)
_sl_wipe_if_due() {
  local now=${EPOCHREALTIME/[.,]/}
  (( now - _SL_SIGT >= _SL_GRACE )) && _sl_wipe
  return 0
}

# "Working on <what was chosen>"
_sl_label() {   # $1 typed text  $2 the row's name  $3 a ready-made label (wins)
  local t="$1" l="$2"
  [ -n "${3:-}" ] && { _SL_NEWLABEL="$3"; return 0; }
  if [ -z "$l" ] && (( ${#t} > 1 )); then case "$t" in enter|space|click|left|right|[0-9]*) ;; *) l="$t" ;; esac; fi   # "y", "3", "enter" say nothing
  if [[ "$l" == *$'\033'* ]]; then local _e=$'\033'; while [[ "$l" =~ ${_e}\[[0-9\;\?]*[A-Za-z] ]]; do l="${l/"${BASH_REMATCH[0]}"/}"; done; fi   # colours of a menu row
  l="${l//[[:cntrl:]]/ }"
  while [[ "$l" =~ ^[[:space:]]*([0-9]+\)|\[[\ xXo]\]|[-*•>])[[:space:]]+ ]]; do l="${l:${#BASH_REMATCH[0]}}"; done    # "3) [ ] Label": the number and the mark say nothing
  l="${l%"${l##*[![:space:]]}"}"; l="${l:0:40}"
  if [ -n "$l" ]; then _SL_NEWLABEL="Working on $l"; else _SL_NEWLABEL="Working"; fi
}

# ENTER was pressed (hooked into _lt_enter): a wait begins.   $1 typed text   $2 the chosen row's name   $3 label override
_sl_enter() {
  [ -n "$_SL_ON" ] || return 0
  if [ "${BASHPID:-$$}" != "$_SL_MAIN" ]; then _sl_dbg "Enter IGNORED: it happened in a subshell / pipeline (pid ${BASHPID}), a wait can only open in the main shell  [$(_sl_from 2)]"; return 0; fi
  (( _SL_WANT )) && (( _SL_HOLD == 0 )) && _sl_wipe_if_due        # Enter twice without a prompt in between
  _SL_WANT=1
  if (( _SL_HOLD > 0 )); then _sl_dbg "Enter ignored: held back (hold=$_SL_HOLD), somebody draws its own progress  [$(_sl_from 2)]"; return 0; fi
  kill -0 "$_SL_PID" 2>/dev/null || _sl_spawn || return 0
  _sl_label "${1:-}" "${2:-}" "${3:-}"
  if [ "$_SL_NEWLABEL" != "$_SL_LABEL" ]; then _SL_LABEL="$_SL_NEWLABEL"; builtin printf '%s' "$_SL_LABEL" >"$_SL_MSG" 2>/dev/null; fi
  _SL_SIGT=${EPOCHREALTIME/[.,]/}
  _sl_dbg "ENTER opens a wait: key='${1:-}' row='${2:-}' label='$_SL_LABEL'  [$(_sl_from 2)]"
  _sl_send B
  return 0
}

# a program the person chose to run (their script, a binary, a compiled file): it is not our app's environment.  The wait is only its start-up, up to its first
# write (see the header); then nothing draws until it exits.   _sl_launch <label> <command and arguments...>   (returns the program's status)
_sl_launch() {
  local _ll="$1" _lrc
  shift
  if [ -z "$_SL_ON" ] || [ "${BASHPID:-$$}" != "$_SL_MAIN" ] || (( _SL_HOLD > 0 )) || [ "${VK_SMARTLOAD_LAUNCH:-1}" = 0 ]; then
    _sl_dbg "launch of '$_ll': no start-up bar (subshell, held back or VK_SMARTLOAD_LAUNCH=0)"
    _sl_ready; "$@"; return $?
  fi
  _sl_ready                                                  # the app's own wait ends here: the program is not ours
  kill -0 "$_SL_PID" 2>/dev/null || _sl_spawn || { "$@"; return $?; }
  _ll="${_ll//[[:cntrl:]]/ }"; _ll="${_ll:0:40}"
  if [ -n "$_ll" ]; then _SL_NEWLABEL="Starting $_ll"; else _SL_NEWLABEL="Starting"; fi
  if [ "$_SL_NEWLABEL" != "$_SL_LABEL" ]; then _SL_LABEL="$_SL_NEWLABEL"; builtin printf '%s' "$_SL_LABEL" >"$_SL_MSG" 2>/dev/null; fi
  _SL_LAUNCH=1; _SL_SIGT=${EPOCHREALTIME/[.,]/}
  _sl_dbg "LAUNCH of '$_ll' (bar only until its first write)  [$(_sl_from 2)]"
  _sl_send L
  "$@"; _lrc=$?
  _SL_LAUNCH=0
  _sl_dbg "launch of '$_ll' ended, status $_lrc"
  _sl_wipe                                                   # a bar that was still showing (a silent program) goes before the app draws again
  _sl_send D
  return "$_lrc"
}

# the app is ready for the next key (hooked into _lt_ready, the read shim and every screen-drawing engine):
# the wait is over.  Call it BEFORE drawing, so that a bar on the screen is wiped while the cursor is still where the bar was drawn.
_sl_ready() {
  (( _SL_WANT )) || return 0
  [ "${BASHPID:-$$}" = "$_SL_MAIN" ] || return 0
  _SL_WANT=0
  _sl_dbg "wait CLOSED after $(( (${EPOCHREALTIME/[.,]/} - _SL_SIGT) / 1000 )) ms since its last restart, by  [$(_sl_from 2)]"
  (( _SL_HOLD > 0 )) && return 0
  _sl_wipe_if_due
  _sl_send D
  return 0
}

# something is about to be written to the terminal (echo / printf / clear shims; engines call it before a redraw)
_sl_pulse() {
  (( _SL_WANT )) && (( _SL_HOLD == 0 )) || return 0
  [ "${BASHPID:-$$}" = "$_SL_MAIN" ] || return 0
  local now=${EPOCHREALTIME/[.,]/} dt
  dt=$(( now - _SL_SIGT ))
  (( dt < _SL_PULSE_US )) && return 0       # a burst of output: the animator's clock is fresh, no bar can be showing
  (( dt >= 200000 )) && _sl_dbg "output after $(( dt / 1000 )) ms of silence restarts the delay  [$(_sl_from 2)]"
  (( dt >= _SL_GRACE )) && _sl_wipe
  _SL_SIGT=$now
  _sl_send A
  return 0
}

# code that draws its own progress (a transfer bar) asks the smart bar to stay out of the way
_sl_hold() {
  [ -n "$_SL_ON" ] || return 0
  _SL_HOLD=$(( _SL_HOLD + 1 ))
  _sl_dbg "HOLD ($_SL_HOLD): bar kept away  [$(_sl_from 2)]"
  if (( _SL_HOLD == 1 && _SL_WANT )); then _sl_wipe_if_due; _sl_send D; fi
  return 0
}
_sl_release() {
  [ -n "$_SL_ON" ] || return 0
  (( _SL_HOLD > 0 )) && _SL_HOLD=$(( _SL_HOLD - 1 ))
  _sl_dbg "release (hold=$_SL_HOLD), wait is $( ((_SL_WANT)) && echo open: delay starts again || echo not open )  [$(_sl_from 2)]"
  if (( _SL_HOLD == 0 && _SL_WANT )); then _SL_SIGT=${EPOCHREALTIME/[.,]/}; _sl_send B; fi
  return 0
}

# the app is leaving (exit, or exec of a shell): nothing may keep drawing
_sl_shutdown() {
  [ -n "$_SL_ON" ] && [ "$$" = "$_SL_MAIN" ] || return 0
  (( _SL_WANT )) && _sl_wipe_if_due
  _SL_WANT=0
  [ -n "$_SL_PID" ] && kill -KILL "$_SL_PID" 2>/dev/null
  _SL_PID=""; _SL_ON=""
  [ -n "$_SL_CTLFD" ] && exec {_SL_CTLFD}>&-
  [ -n "$_SL_ACKFD" ] && exec {_SL_ACKFD}>&-
  [ -n "$_SL_BASE" ] && command rm -f "$_SL_BASE".ctl "$_SL_BASE".ack "$_SL_BASE".msg 2>/dev/null
  return 0
}

_sl_init() {
  [ "${VK_SMARTLOAD:-1}" = 0 ] && return 0
  [ -n "${EPOCHREALTIME:-}" ] || return 0               # bash < 5: no µs clock without a fork
  [ -t 0 ] && [ -t 1 ] || return 0                      # no terminal (pipes, tests, cron): nothing to draw on
  _sl_target || return 0
  type -P mkfifo >/dev/null 2>&1 || return 0
  local d="${TMPDIR:-/tmp}" g="${VK_SMARTLOAD_GRACE_MS:-}"
  [ -d "$d" ] && [ -w "$d" ] || return 0
  [[ "$g" =~ ^[0-9]+$ ]] && (( g >= 50 && g <= 5000 )) && _SL_GRACE=$(( g * 1000 ))
  g="${VK_SMARTLOAD_LAUNCH_MAX_MS:-}"; [[ "$g" =~ ^[0-9]+$ ]] && (( g >= 500 && g <= 60000 )) && _SL_LCAP=$(( g * 1000 ))
  if [ "${VK_SMARTLOAD_DEBUG:-}" = 1 ]; then
    _SL_DBG="${VK_SMARTLOAD_DEBUG_FILE:-$d/bvk-smartload.log}"; _SL_T0=${EPOCHREALTIME/[.,]/}
    builtin printf '=== smartload debug, pid %s, delay %s ms, %s\n' "$$" "$(( _SL_GRACE / 1000 ))" "$(date '+%F %T')" >>"$_SL_DBG" 2>/dev/null || _SL_DBG=""
  fi
  _SL_BASE="$d/bvk-sl.${UID:-0}.$$"
  command mkfifo "$_SL_BASE.ctl" "$_SL_BASE.ack" 2>/dev/null || return 0
  _SL_MSG="$_SL_BASE.msg"
  { exec {_SL_CTLFD}<>"$_SL_BASE.ctl"; } 2>/dev/null || { command rm -f "$_SL_BASE".ctl "$_SL_BASE".ack; return 0; }
  { exec {_SL_ACKFD}<>"$_SL_BASE.ack"; } 2>/dev/null || { exec {_SL_CTLFD}>&-; command rm -f "$_SL_BASE".ctl "$_SL_BASE".ack; return 0; }
  _SL_MAIN=$$
  if [ "${VK_SMARTLOAD_AUTOHOLD:-1}" != 0 ] && [ -d "/proc/$$" ]; then      # no children file needed: _sl_children scans /proc without it
    _SL_PTS="$(command readlink "/proc/$$/fd/1" 2>/dev/null)"; [ -e "$_SL_PTS" ] || _SL_PTS=""
    local -a _pc=(); builtin mapfile -d '' -t _pc <"/proc/$$/cmdline" 2>/dev/null; _SL_PCMD="${_pc[*]}"
  fi
  _SL_ON=1
  _sl_spawn || { _SL_ON=""; return 0; }
  _sl_enter "" "" "Starting"                               # the wait before the very first screen
  return 0
}
_sl_init

# ── full-screen programs are not a wait ──────────────────────────────────────────────────────
# An editor / pager / monitor takes over the whole terminal for as long as the person works in it.  A bar drawn while it runs lands in the middle
# of ITS screen (it showed up in nano's title row).  Each of these names is a function that holds the bar back for the time the program runs and
# brings it back when it exits (the wait of the code after it, if any, is a real wait).  `command` skips the function, so the real program runs.
# Nobody calls these helpers: a call site just writes  nano "$file"  as before.  With smartload off every call is a plain pass-through.
_sl_fs() {
  local _c="$1" _rc; shift
  _sl_hold
  command "$_c" "$@"; _rc=$?
  _sl_release
  return "$_rc"
}
for _sl_n in nano pico micro vi vim nvim view emacs hx kak joe less man top htop btop mc ranger; do
  eval "$_sl_n() { _sl_fs $_sl_n \"\$@\"; }"
done
unset _sl_n
