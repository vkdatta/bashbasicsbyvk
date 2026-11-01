#!/usr/bin/env bash
# First screen: `o` paints the saved screen of the folder at once, the real first paint replaces it in one write.     bash tests/firstscreen.sh
# (1) the screen is saved after the first paint  (2) the next start shows it (loadtime marks it) and ends with ONE clean screen
# (3) no preview when: the window size differs, something changed in the folder, BVK_FIRSTSCREEN=0, a file name is given
set -u
source "$(dirname "${BASH_SOURCE[0]}")/wait_lib.sh"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'tmux kill-session -t "${S:-none}" 2>/dev/null; bvk_reap "$T"; rm -rf "$T"' EXIT
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
command -v tmux >/dev/null 2>&1 || { echo "  skip (tmux not installed)"; echo "ALL OK"; exit 0; }

H="$T/h"; D="$T/d"; B="$T/bin"; mkdir -p "$H/.config/bashbasicsbyvk/telemetry" "$D/sub" "$B"; touch "$D/a.txt" "$D/b.py"
echo 00000000-0000-4000-8000-000000000000 >"$H/.config/bashbasicsbyvk/telemetry/uuid"; echo "$(date -u +%F) true" >"$H/.config/bashbasicsbyvk/telemetry/daily"
find "$ROOT/script" -type f -not -path '*/bvk-ls/*' -not -name '*.txt' -not -name '*.xlsx' -exec cp {} "$B/" \; ; chmod +x "$B"/*
FS="$H/.bashbasicsbyvk/firstscreen"; KEY="${D//\//%}"; S="bvkfs$$"
run() { # <cols> <rows> <extra env> [o args]
  local c="$1" r="$2" e="$3"; shift 3
  tmx_start "$S" "$c" "$r" "$D" "env PATH=$B:\$PATH HOME=$H TERM=xterm-256color BVK_LOADMAP=all $e bash --norc --noprofile $B/o $*"; }
quit() { tmux kill-session -t "$S" 2>/dev/null; }     # the saved screen is already written; nothing to wait for
selects() { tmx_screen "$S" | grep -ac "Select:"; }
ready() { wait_until 15 "the real screen (a Select: line)" bash -c "tmux capture-pane -pt $S | grep -q 'Select:'"; }
# loadtime prints a report longer than the window: read the whole scrollback, not the visible screen
lt_report() { tmux send-keys -t "$S" -l loadtime; tmux send-keys -t "$S" Enter
  wait_until 10 "the loadtime report" bash -c "tmux capture-pane -pt $S -S - | grep -q 'main is ready for input'"; tmux capture-pane -pt "$S" -S -; }

# (1) first start: nothing saved yet; after the paint the screen is saved
run 100 40 ""
tmx_wait "$S" 15 "a.txt" || bad "app did not start"
wait_file 8 "$FS/$KEY" && ok "the first paint saved the screen" || bad "no saved screen"
head -1 "$FS/$KEY" | grep -qE '^v1 40 100 [0-9]+ [0-9]+$' && ok "header: version, rows, cols, block height, length" || { bad "header"; head -1 "$FS/$KEY"; }
grep -q "a.txt" "$FS/$KEY" && grep -q "b.py" "$FS/$KEY" && ok "the saved frame holds the rows" || bad "frame rows"
quit

# (2) second start: the preview is on screen and the end result is one clean screen
touch -d '2 seconds ago' "$D"; touch "$FS/$KEY"                  # the folder is older than its saved screen
run 100 40 ""
tmx_wait "$S" 15 "a.txt" || bad "second start: app did not start"
ready
rep="$(lt_report)"
grep -q "cached first screen is on the screen" <<<"$rep" && ok "loadtime shows that the saved screen was painted first" || { bad "no preview marker"; tail -30 <<<"$rep"; }
quit
run 100 40 ""
tmx_wait "$S" 15 "a.txt" || bad "app did not start"
ready
[ "$(selects)" = 1 ] && ok "one clean screen: exactly one Select: line, no leftover preview" || { bad "leftover preview: $(selects) Select: lines"; tmx_screen "$S"; }
quit

# (3) no preview ...
tmx_has_marker() { lt_report | grep -q "cached first screen is on the screen"; }
touch -d '2 seconds ago' "$D"; touch "$FS/$KEY"
run 80 30 ""; tmx_wait "$S" 15 "a.txt"; ready
tmx_has_marker && bad "a window of another size must not get the preview" || ok "another window size: no preview"; quit
touch -d '2 seconds ago' "$D"; touch "$FS/$KEY"; touch "$D/new.txt"       # the folder changed AFTER the save
run 100 40 ""; tmx_wait "$S" 15 "new.txt" || bad "new file not listed"; ready
tmx_has_marker && bad "a changed folder must not get the preview" || ok "folder changed since the save: no preview and the new file is listed"; quit
rm -f "$D/new.txt"; touch -d '2 seconds ago' "$D"; touch "$FS/$KEY"
run 100 40 "BVK_FIRSTSCREEN=0"; tmx_wait "$S" 15 "a.txt"; ready
tmx_has_marker && bad "BVK_FIRSTSCREEN=0 must switch it off" || ok "BVK_FIRSTSCREEN=0: no preview"; quit
run 100 40 "" "$D"; tmx_wait "$S" 15 "a.txt"; ready
tmx_has_marker && bad "a folder given as argument must not get the preview" || ok "o <folder>: no preview"; quit

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
