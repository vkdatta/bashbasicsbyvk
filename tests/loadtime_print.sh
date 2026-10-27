#!/usr/bin/env bash
# print + loadtime.     bash tests/loadtime_print.sh
# (1) print: escape codes are stripped, the prompt ends the text
# (2) loadtime report: order, ranking, network phases, tool commands are not screen changes
# (3) the recorder itself: _lt_b/_lt_e, _lt_enter/_lt_ready, curl phases (needs curl >= 8.3 and no proxy)
# (4) end to end inside tmux when tmux is installed: print and loadtime at the main menu and in Settings
set -u
source "$(dirname "${BASH_SOURCE[0]}")/wait_lib.sh"   # UTF-8 locale + wait_until / tmx_* (no fixed sleeps)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRINT_SH="$(bvk_need bashbasicsbyvk_print.sh)"; LT_SH="$(bvk_need bashbasicsbyvk_loadtime.sh)"; REPORT="$(bvk_need bashbasicsbyvk_loadtime_report)"   # found by name: the files moved before and will again
T="$(mktemp -d)"; trap 'tmux kill-session -t "${S:-none}" 2>/dev/null; bvk_reap "$T"; rm -rf "$T"; [ -n "${HSPID:-}" ] && kill "$HSPID" 2>/dev/null' EXIT
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
has() { grep -qF -- "$2" <<<"$1"; }

# ---- (1) print --------------------------------------------------------------------------
source "$PRINT_SH"
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
rep="$(python3 -I "$REPORT" "$L" --pick 2 --cols 100)"
has "$rep" "LOADTIME — main → Settings" && ok "report: previous → current screen" || bad "report header"
has "$rep" "TOTAL  320 ms" && ok "report: total = Enter → ready" || bad "report total"
has "$rep" "TLS handshake" && has "$rep" "60.0 ms" && ok "report: TLS handshake time" || bad "report TLS"
has "$rep" "server wait" && has "$rep" "160 ms" && ok "report: server wait / first byte" || bad "report wait"
has "$rep" "BACKGROUND" && ok "report: background work listed apart" || bad "report background"
first="$(grep -n 'TIMELINE' <<<"$rep" | head -1 | cut -d: -f1)"; has "$rep" "RANKED BY TIME CONSUMED" && ok "report: ranking section" || bad "ranking"
rank1="$(grep -m1 '#1 ' <<<"$rep")"; has "$rank1" "curl api.example.com" && ok "report: slowest first" || { bad "rank order"; echo "$rank1"; }
one="$(python3 -I "$REPORT" "$L" --pick 1 --cols 100)"
has "$one" "main → Settings" && ok "report: the loadtime command itself is skipped (latest = main → Settings)" || bad "tool command not skipped"
all="$(python3 -I "$REPORT" "$L" --pick all)"
has "$all" "shell → main" && has "$all" "main → Settings" && ok "report: loadtime all" || bad "loadtime all"
none="$(python3 -I "$REPORT" "$T/empty" --pick 1)"; has "$none" "Nothing measured yet" && ok "report: no data is explained" || bad "empty log"

# ---- (3) recorder -----------------------------------------------------------------------
rec="$(bash -c '
  export TMPDIR="'"$T"'"
  source "'"$LT_SH"'"; _lt_init
  _lt_b "step one"; sleep 0.05; _lt_e
  _lt_ready menu "main"
  _lt_enter "5" "folder"; _lt_b "inner"; sleep 0.02; _lt_e; _lt_ready menu "main"
  _lt_enter "loadtime"; _lt_tool_begin; _lt_enter "x"; _lt_ready menu "zzz"; _lt_tool_end
  cat "$_LT_LOG"; _lt_cleanup; [ -e "$_LT_LOG" ] && echo LOGLEFT')"
has "$rec" $'\tstep one\t' && ok "recorder: _lt_b/_lt_e writes a step" || bad "recorder step"
[ "$(grep -c '^R' <<<"$rec")" = 2 ] && ok "recorder: tool command records no screen change" || bad "recorder tool mute"
has "$rec" "LOGLEFT" && bad "recorder: log not removed" || ok "recorder: log removed on exit"
if curl --version 2>/dev/null | grep -q '^curl 8\.\([3-9]\|[1-9][0-9]\)' && [ -z "${HTTPS_PROXY:-}${https_proxy:-}${HTTP_PROXY:-}${http_proxy:-}" ]; then
  python3 -m http.server 18766 --bind 127.0.0.1 >/dev/null 2>&1 & HSPID=$!; wait_port 10 18766
  net="$(bash -c '
    export TMPDIR="'"$T"'"
    source "'"$LT_SH"'"; _lt_init
    body="$(curl -s -w "\n%{http_code}" http://127.0.0.1:18766/)"; echo "BODY_LAST=${body##*$'"'"'\n'"'"'}"
    cat "$_LT_LOG"; _lt_cleanup')"
  has "$net" "BODY_LAST=200" && ok "curl wrapper keeps the caller's -w output" || bad "curl -w passthrough"
  has "$net" $'\tcurl 127.0.0.1:18766' && has "$net" "ns=" && ok "curl wrapper logs the phase times" || bad "curl phases"
else echo "  skip curl phase test (curl < 8.3 or a proxy is set)"; fi

# ---- (4) tmux ---------------------------------------------------------------------------
if command -v tmux >/dev/null 2>&1; then
  H="$T/h"; mkdir -p "$H" "$T/d/sub" "$H/.config/bashbasicsbyvk/telemetry"; touch "$T/d/a.txt"; B="$T/bin"; mkdir -p "$B"
  echo 00000000-0000-4000-8000-000000000000 >"$H/.config/bashbasicsbyvk/telemetry/uuid"; echo "$(date -u +%F) true" >"$H/.config/bashbasicsbyvk/telemetry/daily"   # telemetry already reported today: no network wait
  find "$ROOT/script" -type f -not -path '*/bvk-ls/*' -not -name '*.txt' -not -name '*.xlsx' -exec cp {} "$B/" \; ; chmod +x "$B"/*
  S="bvktest$$"; t_start
  tmx_start "$S" 100 40 "$T/d" "env PATH=$B:\$PATH HOME=$H TERM=xterm-256color BVK_LOADMAP=all bash --norc --noprofile $B/o"   # all = nothing loads in the background: the report this test reads has the same length every time
  tmx_wait "$S" 15 "a.txt" || bad "app did not start"
  snd() { tmx_dol "$S" "$1"; }                       # type a line + Enter, wait for the screen to react
  tmx_line "$S" print "Copy to clipboard" && ok "tmux: print offers copy / save at the main menu" || bad "tmux print"
  snd 2; snd "pr.txt"; wait_file 8 "$T/d/pr.txt"
  [ -s "$T/d/pr.txt" ] && grep -q "Select:" "$T/d/pr.txt" && grep -q "a.txt" "$T/d/pr.txt" && ok "tmux: saved screen holds the rows and the Select: line" || bad "tmux saved file"
  snd s; tmx_line "$S" print "Copy to clipboard" && ok "tmux: print works inside Settings" || bad "tmux print in settings"
  snd 2; snd "st.txt"; wait_file 8 "$T/d/st.txt"
  grep -q "1) Hidden files\\|Display" "$T/d/st.txt" 2>/dev/null && ok "tmux: Settings screen captured with its first characters" || bad "tmux settings capture"
  tmx_line "$S" loadtime "LOADTIME" 10 && tmx_wait "$S" 2 "Settings" && ok "tmux: loadtime in Settings names the screens" || bad "tmux loadtime"
  tmux kill-session -t "$S" 2>/dev/null; echo "  tmux part: $(t_since)s"
else echo "  skip tmux end-to-end test (tmux not installed)"; fi

[ "$fail" = 0 ] && echo "ALL GOOD" || { echo "FAILED"; exit 1; }
