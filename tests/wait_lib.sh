#!/usr/bin/env bash
# Shared WAIT helpers of every bash test. SOURCE it, don't run it.  (python pty tests: tests/paste_input/ptyapp.py does the same job.)
#
# THE RULE: a test never sleeps for a guessed time. It waits for the THING it needs (a file, a port, a screen text, a process
# that ended, a count in the server) and fails the moment the thing is clearly not coming, printing what it saw.
# A test that passes in 0.3 s when the app is fast and fails after the timeout (with the screen) when it is not.
#
#   wait_until  <secs> "<what>" <cmd...>      poll <cmd> until it succeeds (poll step 20 ms .. 100 ms); on timeout print what + dump, return 1
#   wait_file   <secs> <path>                 until the file exists and is not empty
#   wait_gone   <secs> <pid>                  until the process is gone (kill -0 fails)
#   wait_port   <secs> <port>                 until 127.0.0.1:<port> accepts a connection
#   wait_grep   <secs> <file> <text>          until the file contains the fixed text
#   wait_count  <secs> "<what>" <got-cmd> <n> until `got-cmd` prints a number >= n
#   settle      <secs> <quiet-secs> <cmd...>  until <cmd>'s output stays the same for <quiet-secs> (used ONLY for "nothing else may happen" checks)
#   tmx_start <session> <cols> <rows> <dir> <cmd>   tmx_wait <session> <secs> "<text>"   tmx_send <session> <keys...>
#   tmx_do <session> <keys...>   send keys, wait for the screen to react + settle     tmx_until <session> <text> <tries> <keys...>   repeat keys until text shows
#   tmx_line  <session> <text> ["<wait-text>"]      type a line + Enter; with <wait-text> wait until it shows once more than before     tmx_dol <session> <text>   type a line + Enter, wait for the screen to react + settle   tmx_screen <session>
#   bvk_reap <temp dir>                               kill everything started from that dir (call it when a test that started the app ends)
#   bvk_file <name> / bvk_need <name>                 path of a script file found by name (bvk_need stops the test with a clear message when it is gone)
#   t_start / t_since                                 elapsed seconds (a test prints its own time so a slow one is visible at once)
# Set WAIT_DUMP to a function name: it is called (and its output printed) whenever a wait times out - that is the "failure instance, live".
# Fixed `sleep N` in a test is rejected by tests/lint_waits.sh (only this file may poll).

# --- locale: the app measures UTF-8 widths, so every test runs in a UTF-8 locale whatever the host has (a C locale made 'width' fail "from the start")
for _wl in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if LC_ALL="$_wl" locale charmap 2>/dev/null | grep -qi 'utf-\?8'; then export LC_ALL="$_wl" LANG="$_wl"; break; fi
done; unset _wl

# --- script files are found BY NAME (names are unique, the installed app has them flat on PATH), so moving a file between folders never breaks a test
bvk_file() { find "${ROOT:?set ROOT before using bvk_file}/script" -type f -name "$1" -print -quit 2>/dev/null; }
bvk_need() { local f; f="$(bvk_file "$1")"; [ -n "$f" ] || { echo "  FAIL test setup: no script file named $1 under $ROOT/script" >&2; exit 2; }; printf '%s' "$f"; }

# TEST_TIME_FACTOR (set by tests/run.sh when the machine is oversubscribed) stretches every wait. A timeout only matters when something is wrong, so a longer one costs nothing when the app answers.
TEST_TIME_FACTOR="${TEST_TIME_FACTOR:-1}"
WAIT_DUMP="${WAIT_DUMP:-}"
_wl_now() { local t="${EPOCHREALTIME:-}"; [ -n "$t" ] && { printf '%s' "${t/./}"; return; }; date +%s%N | cut -c1-16; }   # microseconds
_WL_T0="$(_wl_now)"
t_start() { _WL_T0="$(_wl_now)"; }
t_since() { local d=$(( $(_wl_now) - _WL_T0 )); printf '%d.%02d' $((d/1000000)) $(( (d%1000000)/10000 )); }
_wl_pause() { sleep "$1" 2>/dev/null || read -rt "$1" <> <(:) 2>/dev/null || true; }

wait_until() {   # <secs> <what> <cmd...>
  local secs="$1" what="$2" end step=0.02 n=0; shift 2
  end=$(( $(_wl_now) + $(printf '%.0f' "$(echo "$secs * $TEST_TIME_FACTOR * 1000000" | bc -l 2>/dev/null || echo $((secs*1000000)))") ))
  while :; do
    "$@" >/dev/null 2>&1 && return 0
    [ "$(_wl_now)" -ge "$end" ] && break
    _wl_pause "$step"; n=$((n+1)); [ "$n" -ge 10 ] && step=0.1
  done
  printf '  TIMEOUT after %ss waiting for: %s\n' "$secs" "$what" >&2
  [ -n "$WAIT_DUMP" ] && { printf '  --- what was there instead ---\n' >&2; $WAIT_DUMP 2>&1 | tail -25 | sed 's/^/  | /' >&2; }
  return 1
}
wait_file()  { wait_until "$1" "file $2" test -s "$2"; }
wait_gone()  { wait_until "$1" "process $2 to end" bash -c '! kill -0 "$1" 2>/dev/null' _ "$2"; }
wait_port()  { wait_until "$1" "port $2 to accept connections" bash -c 'exec 3<>/dev/tcp/127.0.0.1/$1' _ "$2"; }
wait_grep()  { wait_until "$1" "'$3' in $2" grep -qF -- "$3" "$2"; }
_wl_ge()     { local v; v="$("$1")"; [ "${v:-0}" -ge "$2" ] 2>/dev/null; }
wait_count() { wait_until "$1" "$2 (>= $4)" _wl_ge "$3" "$4"; }
settle() {       # <secs max> <quiet> <cmd...>  -> the output of cmd did not change for <quiet> seconds
  local max="$1" quiet="$2" last cur since end; shift 2
  end=$(( $(_wl_now) + $(printf '%.0f' "$(echo "$max * 1000000" | bc -l)") )); last="$("$@" 2>&1)"; since="$(_wl_now)"
  local q; q=$(printf '%.0f' "$(echo "$quiet * 1000000" | bc -l)")
  while [ "$(_wl_now)" -lt "$end" ]; do
    cur="$("$@" 2>&1)"
    if [ "$cur" != "$last" ]; then last="$cur"; since="$(_wl_now)"; elif [ $(( $(_wl_now) - since )) -ge "$q" ]; then return 0; fi
    _wl_pause 0.02
  done; return 0
}

bvk_reap() { pkill -f -- "$1" >/dev/null 2>&1 || true; }   # stop every process started from this temp dir (the app leaves its recents daemon / watchers running when it is killed)

# --- tmux (only when tmux is installed; every tmx_* returns 1 and prints the screen when something does not show up in time)
tmx_screen() { tmux capture-pane -p -t "$1" 2>/dev/null; }                 # what is VISIBLE now (older lines still in the scrollback must not count as "shown")
tmx_scrollback() { tmux capture-pane -p -S -300 -t "$1" 2>/dev/null; }      # visible + history, for output that scrolled away
tmx_start()  { # <session> <cols> <rows> <dir> <command string>; the pane stays after the command ends so the last screen can be read
  tmux kill-session -t "$1" 2>/dev/null; tmux new-session -d -s "$1" -x "$2" -y "$3" -c "$4" "$5"; }
_tmx_has()   { tmx_screen "$1" | grep -qaF -- "$2"; }
tmx_wait()   { local s="$1"; WAIT_DUMP="tmx_screen $s" wait_until "$2" "screen $s shows '$3'" _tmx_has "$s" "$3"; }
_tmx_changed() { [ "$(tmx_screen "$1")" != "$2" ]; }
tmx_do()     { # <session> <keys...>: send keys, wait until the screen CHANGED (the app reacted), then until it stopped redrawing. For steps whose result text is not unique.
  local s="$1" before; shift; before="$(tmx_screen "$s")"; tmux send-keys -t "$s" "$@"
  WAIT_DUMP="tmx_screen $s" wait_until "${TMX_REACT_MAX:-8}" "screen $s to react to: $*" _tmx_changed "$s" "$before" && settle 3 0.2 tmx_screen "$s"; }
tmx_until()  { # <session> <text> <tries> <keys...>: repeat the keys (each waits for the screen to react) until <text> is on screen - "go back to X"
  local s="$1" txt="$2" n="$3" i; shift 3
  for ((i=0; i<n; i++)); do _tmx_has "$s" "$txt" && return 0; tmx_do "$s" "$@" || true; done; _tmx_has "$s" "$txt"; }
tmx_send()   { local s="$1"; shift; tmux send-keys -t "$s" "$@"; }
tmx_count()  { tmx_screen "$1" | grep -acF -- "$2"; }
_tmx_more()  { [ "$(tmx_count "$1" "$2")" -gt "$3" ]; }
tmx_line()   { # <session> <line> [text [secs]]: type the line + Enter; with <text>, wait until it shows ONE MORE TIME than before (the app prints menus inline, so an older copy of the text may still be on screen)
  local s="$1" before=0; [ -n "${3:-}" ] && before="$(tmx_count "$s" "$3")"
  tmux send-keys -t "$s" -l -- "$2"; tmux send-keys -t "$s" Enter
  [ -n "${3:-}" ] && { WAIT_DUMP="tmx_screen $s" wait_until "${4:-8}" "'$3' to show (again) on screen $s" _tmx_more "$s" "$3" "$before"; return $?; }; return 0; }
tmx_dol()    { # <session> <line>: type the line + Enter, then wait for the screen to react + settle (text not unique)
  local s="$1" before; before="$(tmx_screen "$s")"; tmux send-keys -t "$s" -l -- "$2"; tmux send-keys -t "$s" Enter
  WAIT_DUMP="tmx_screen $s" wait_until "${TMX_REACT_MAX:-8}" "screen $s to react to: $2" _tmx_changed "$s" "$before" && settle 3 0.2 tmx_screen "$s"; }
