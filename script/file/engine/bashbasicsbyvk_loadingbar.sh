# bashbasicsbyvk_loadingbar.sh — reusable "back and forth" loading bar
#
#   [░░░░████░░░░░░░░░░░░] Loading stable releases…  3s
#
# Same look as the upload progress bar (cyan, █ / ░, redrawn in place on one line), but
# for work whose length is unknown: the block bounces left ↔ right until the work is done.
# It runs as a tiny background animator, so ANY foreground work can sit in front of it —
# shell functions that fill global arrays included (nothing is run in a subshell).
#
# Usage
#   _lb_run   "message" command [args…]     run the command with the bar; returns its status
#                                           (stdout untouched, stderr is held back and replayed
#                                           after the bar is gone, so it never garbles the bar)
#   _lb_start "message"                     start the bar on the CURRENT line …
#   _lb_stop                                … clear it (cursor shown again, back at column 1)
#
# Options (before the message)
#   --below   draw on the row BELOW the cursor instead of the current one (the cursor stays put,
#             hidden meanwhile) — for screens that own the current row, like the Select prompt
# _lb_stop option
#   --keep-hidden   leave the cursor hidden (caller redraws a screen and shows it itself)
#
# The bar appears only if the work takes longer than ~0.15 s.  Start it on an EMPTY line
# (or use --below): stopping clears the row it was drawn on.
#
# Safe everywhere: with no terminal to draw on (pipes, tests, cron) every call is a no-op and
# _lb_run simply runs the command.  If the program dies, the animator notices and cleans up.

_LB_PID=""
_LB_BELOW=0
_LB_TTY=""

# where to draw: the controlling terminal, else stderr when that is a terminal, else nowhere
_lb_target() {
  if [ -w /dev/tty ] && { : >/dev/tty; } 2>/dev/null; then _LB_TTY=/dev/tty; return 0; fi
  if [ -t 2 ]; then _LB_TTY=/dev/stderr; return 0; fi
  _LB_TTY=""; return 1
}

_lb_cols() {
  local c=""
  c="$(stty size <"$_LB_TTY" 2>/dev/null)"; c="${c##* }"
  [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ] || c="${COLUMNS:-}"
  [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ] || c="$(tput cols 2>/dev/null)"
  [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ] || c=60
  printf '%s' "$c"
}

# the animator (runs in the background; the parent kills it)
#   $1 tty  $2 message  $3 below(0/1)  $4 columns  $5 parent pid
_lb_loop() {
  local tty="$1" msg="$2" below="$3" cols="$4" parent="$5"
  local W=22 BW=5 pos=0 dir=1 left right bar line el t0=$SECONDS pre="" post="" slp=0.1
  sleep 0.15 2>/dev/null || slp=1      # short grace period: instant work never flashes a bar
  # bar width / message length follow the screen, like the upload bar does
  local room=$(( cols - 14 ))
  (( room < 12 )) && room=12
  (( W > room - 4 )) && W=$(( room - 4 ))
  (( W < 8 )) && W=8
  (( BW > W / 3 )) && BW=$(( W / 3 ))
  (( BW < 2 )) && BW=2
  local maxmsg=$(( cols - W - 14 ))
  (( maxmsg < 0 )) && maxmsg=0
  [ "${#msg}" -gt "$maxmsg" ] && msg="${msg:0:$(( maxmsg > 1 ? maxmsg - 1 : 0 ))}…"
  if [ "$below" = 1 ]; then pre=$'\033[1B\r\033[2K'; post=$'\033[1A'; else pre=$'\r\033[2K'; fi
  local track blk
  printf -v track '%*s' "$W" ''; track="${track// /░}"       # built once, sliced per frame
  printf -v blk '%*s' "$BW" ''; blk="${blk// /█}"
  while kill -0 "$parent" 2>/dev/null; do
    left="${track:0:pos}"; bar="$blk"; right="${track:0:$(( W - pos - BW ))}"
    el=$(( SECONDS - t0 )); t=""
    (( el >= 2 )) && t="  ${el}s"
    line=$'\033[36m['"$left$bar$right"$']\033[0m '"$msg$t"
    builtin printf '%s%s%s' "$pre" "$line" "$post" >"$tty" 2>/dev/null || exit 0
    pos=$(( pos + dir ))
    if (( pos >= W - BW )); then pos=$(( W - BW )); dir=-1
    elif (( pos <= 0 )); then pos=0; dir=1; fi
    sleep "$slp"
  done
  # parent is gone without calling _lb_stop: leave the terminal clean
  builtin printf '%s\033[?25h' "$pre" >"$tty" 2>/dev/null
  exit 0
}

_lb_start() {
  local below=0
  [ "$1" = "--below" ] && { below=1; shift; }
  [ -n "$_LB_PID" ] && _lb_stop
  _lb_target || return 0
  _LB_BELOW=$below
  local cols; cols="$(_lb_cols)"
  builtin printf '\033[?25l' >"$_LB_TTY" 2>/dev/null          # no cursor box while loading
  # make sure the row below exists (scrolls one row only when the cursor is on the last row)
  [ "$below" = 1 ] && builtin printf '\n\033[1A' >"$_LB_TTY" 2>/dev/null
  _lb_loop "$_LB_TTY" "${1:-Loading…}" "$below" "$cols" "$$" &
  _LB_PID=$!
}

_lb_stop() {
  local keep=0
  [ "$1" = "--keep-hidden" ] && keep=1
  [ -n "$_LB_PID" ] || return 0
  { kill -KILL "$_LB_PID"; wait "$_LB_PID"; } 2>/dev/null
  _LB_PID=""
  [ -n "$_LB_TTY" ] || return 0
  if [ "$_LB_BELOW" = 1 ]; then builtin printf '\033[1B\r\033[2K\033[1A\r' >"$_LB_TTY" 2>/dev/null
  else builtin printf '\r\033[2K' >"$_LB_TTY" 2>/dev/null; fi
  [ "$keep" = 1 ] || builtin printf '\033[?25h' >"$_LB_TTY" 2>/dev/null
  return 0
}

_lb_run() {
  local below="" msg rc errf
  [ "$1" = "--below" ] && { below="--below"; shift; }
  msg="$1"; shift
  errf="$(mktemp 2>/dev/null)" || errf=""
  _lb_start $below "$msg"
  if [ -n "$_LB_PID" ] && [ -n "$errf" ]; then
    "$@" 2>"$errf"; rc=$?
  else
    "$@"; rc=$?
  fi
  _lb_stop
  if [ -n "$errf" ]; then [ -s "$errf" ] && cat "$errf" >&2; rm -f "$errf"; fi
  return $rc
}
