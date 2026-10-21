#!/usr/bin/env bash
# print + loadtime.     bash tests/loadtime_print.sh
# (1) print: escape codes are stripped, the prompt ends the text
# (2) loadtime report: order, ranking, network phases, tool commands are not screen changes
# (3) the recorder itself: _lt_b/_lt_e, _lt_enter/_lt_ready, curl phases (needs curl >= 8.3 and no proxy)
# (4) end to end inside tmux when tmux is installed: print and loadtime at the main menu and in Settings
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
E="$ROOT/script/file/engine"
T="$(mktemp -d)"; trap 'rm -rf "$T"; [ -n "${HSPID:-}" ] && kill "$HSPID" 2>/dev/null' EXIT
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
has() { grep -qF -- "$2" <<<"$1"; }

# ---- (1) print --------------------------------------------------------------------------
source "$E/bashbasicsbyvk_print.sh"
_BVK_SCR_RAW=$'\r\033[2K\033[?7l📂 Location: /x\033[?7h\n\r\033[2K\033[?7l  1) 📄 a.txt\033[?7h\n\r\033[2K\033[1;7m  2) b.py\033[0m\n'
_BVK_SCR_PROMPT="Select: "; _BVK_SCR_EXTRA=$'\n'
out="$(_bvk_scr_text)"
[ "$out" = $'📂 Location: /x\n  1) 📄 a.txt\n  2) b.py\nSelect:' ] && ok "print: codes stripped, rows intact, ends with Select:" || { bad "print text"; printf '%s\n' "$out" | cat -A; }
_BVK_SCR_EXTRA=$'🔴  Invalid selection\n'
has "$(_bvk_scr_text)" "Invalid selection" && ok "print: output printed after the frame is kept" || bad "print extra"

# ---- (2) report -------------------------------------------------------------------------
L="$T/ev.log"; t0=1800000000000000
w() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$L"; }
w T $t0 0 1 "" "o" "shell|launch"
w S $((t0+1000)) 30000 1 "" "load engine" ""
w X $((t0+2000)) 20000 1 "" "python3 (inline script)" "rc=0"
w R $((t0+50000)) 0 1 "" "main" "menu"
w T $((t0+1000000)) 0 1 "" "s" "main|"
w S $((t0+1001000)) 5000 1 "" "settings: build the rows" ""
w N $((t0+1006000)) 300000 1 "" "curl api.example.com/v1" "rc=0;ns=0.01;co=0.03;ap=0.09;pt=0.09;st=0.25;tt=0.30;code=200;ver=2;dl=2048;nc=1"
w X $((t0+1100000)) 9000 1 b "curl telemetry" "rc=0"
w R $((t0+1320000)) 0 1 "" "Settings" "settings"
w T $((t0+2000000)) 0 1 "" "loadtime" "Settings|"      # a tool command: never a screen change
w T $((t0+3000000)) 0 1 "" "u" "Settings|"
w R $((t0+3010000)) 0 1 "" "main" "menu"
export BVK_LT_PROBE=0
rep="$(python3 -I "$E/bashbasicsbyvk_loadtime_report" "$L" --pick 2 --cols 100)"
has "$rep" "LOADTIME — main → Settings" && ok "report: previous → current screen" || bad "report header"
has "$rep" "TOTAL  320 ms" && ok "report: total = Enter → ready" || bad "report total"
has "$rep" "TLS handshake" && has "$rep" "60.0 ms" && ok "report: TLS handshake time" || bad "report TLS"
has "$rep" "server wait" && has "$rep" "160 ms" && ok "report: server wait / first byte" || bad "report wait"
has "$rep" "BACKGROUND" && ok "report: background work listed apart" || bad "report background"
first="$(grep -n 'TIMELINE' <<<"$rep" | head -1 | cut -d: -f1)"; has "$rep" "RANKED BY TIME CONSUMED" && ok "report: ranking section" || bad "ranking"
rank1="$(grep -m1 '#1 ' <<<"$rep")"; has "$rank1" "curl api.example.com" && ok "report: slowest first" || { bad "rank order"; echo "$rank1"; }
one="$(python3 -I "$E/bashbasicsbyvk_loadtime_report" "$L" --pick 1 --cols 100)"
has "$one" "main → Settings" && ok "report: the loadtime command itself is skipped (latest = main → Settings)" || bad "tool command not skipped"
all="$(python3 -I "$E/bashbasicsbyvk_loadtime_report" "$L" --pick all)"
has "$all" "shell → main" && has "$all" "main → Settings" && ok "report: loadtime all" || bad "loadtime all"
none="$(python3 -I "$E/bashbasicsbyvk_loadtime_report" "$T/empty" --pick 1)"; has "$none" "Nothing measured yet" && ok "report: no data is explained" || bad "empty log"

# ---- (3) recorder -----------------------------------------------------------------------
rec="$(bash -c '
  export TMPDIR="'"$T"'"
  source "'"$E"'/bashbasicsbyvk_loadtime.sh"; _lt_init
  _lt_b "step one"; sleep 0.05; _lt_e
  _lt_ready menu "main"
  _lt_enter "5" "folder"; _lt_b "inner"; sleep 0.02; _lt_e; _lt_ready menu "main"
  _lt_enter "loadtime"; _lt_tool_begin; _lt_enter "x"; _lt_ready menu "zzz"; _lt_tool_end
  cat "$_LT_LOG"; _lt_cleanup; [ -e "$_LT_LOG" ] && echo LOGLEFT')"
has "$rec" $'\tstep one\t' && ok "recorder: _lt_b/_lt_e writes a step" || bad "recorder step"
[ "$(grep -c '^R' <<<"$rec")" = 2 ] && ok "recorder: tool command records no screen change" || bad "recorder tool mute"
has "$rec" "LOGLEFT" && bad "recorder: log not removed" || ok "recorder: log removed on exit"
if curl --version 2>/dev/null | grep -q '^curl 8\.\([3-9]\|[1-9][0-9]\)' && [ -z "${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]; then
  python3 -m http.server 18766 --bind 127.0.0.1 >/dev/null 2>&1 & HSPID=$!; sleep 1
  net="$(bash -c '
    export TMPDIR="'"$T"'"
    source "'"$E"'/bashbasicsbyvk_loadtime.sh"; _lt_init
    body="$(curl -s -w "\n%{http_code}" http://127.0.0.1:18766/)"; echo "BODY_LAST=${body##*$'"'"'\n'"'"'}"
    cat "$_LT_LOG"; _lt_cleanup')"
  has "$net" "BODY_LAST=200" && ok "curl wrapper keeps the caller's -w output" || bad "curl -w passthrough"
  has "$net" $'\tcurl 127.0.0.1:18766' && has "$net" "ns=" && ok "curl wrapper logs the phase times" || bad "curl phases"
else echo "  skip curl phase test (curl < 8.3 or a proxy is set)"; fi

# ---- (4) tmux ---------------------------------------------------------------------------
if command -v tmux >/dev/null 2>&1; then
  H="$T/h"; mkdir -p "$H" "$T/d/sub"; touch "$T/d/a.txt"; B="$T/bin"; mkdir -p "$B"
  find "$ROOT/script" -type f -not -path '*/bvk-ls/*' -not -name '*.txt' -not -name '*.xlsx' -exec cp {} "$B/" \; ; chmod +x "$B"/*
  S="bvktest$$"; tmux kill-session -t "$S" 2>/dev/null
  tmux new-session -d -s "$S" -x 100 -y 40 -c "$T/d" "env PATH=$B:\$PATH HOME=$H TERM=xterm-256color VK_TELEMETRY=0 bash --norc --noprofile $B/o; sleep 20"
  snd() { tmux send-keys -t "$S" -l -- "$1"; tmux send-keys -t "$S" Enter; sleep "${2:-1}"; }
  scr() { tmux capture-pane -p -S -300 -t "$S"; }
  sleep 3
  snd print; has "$(scr)" "Copy to clipboard" && ok "tmux: print offers copy / save at the main menu" || bad "tmux print"
  snd 2 0.5; snd "pr.txt" 1
  [ -s "$T/d/pr.txt" ] && grep -q "Select:" "$T/d/pr.txt" && grep -q "a.txt" "$T/d/pr.txt" && ok "tmux: saved screen holds the rows and the Select: line" || bad "tmux saved file"
  snd s 1.2; snd print; has "$(scr)" "Copy to clipboard" && ok "tmux: print works inside Settings" || bad "tmux print in settings"
  snd 2 0.5; snd "st.txt" 1
  grep -q "1) Hidden files\|Display" "$T/d/st.txt" 2>/dev/null && ok "tmux: Settings screen captured with its first characters" || bad "tmux settings capture"
  snd loadtime 2; has "$(scr)" "LOADTIME" && has "$(scr)" "Settings" && ok "tmux: loadtime in Settings names the screens" || bad "tmux loadtime"
  tmux kill-session -t "$S" 2>/dev/null
else echo "  skip tmux end-to-end test (tmux not installed)"; fi

[ "$fail" = 0 ] && echo "ALL GOOD" || { echo "FAILED"; exit 1; }
