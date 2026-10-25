#!/usr/bin/env bash
# The key handling of the list screens (_st_run: Settings, Home, choose menus), checked WITHOUT a terminal: the screen is a stub that prints
# the state (cur = highlighted row, buf = the typed line) every time it would draw, and the keys come through a pipe.   bash tests/settings_keys.sh
#  1. the input is gone (EOF / closed tty): the screen LEAVES; it does not type q forever          (BB-251020261341-1)
#  2. an arrow puts a row number on the line, the next typed character REPLACES it (Down 5 = 5, Down h = h)   (BB-251020261341-2)
#  3. a typed number that names no row, or an erased one, leaves no stale highlight: Space / Enter do nothing  (BB-251020261341-3)
#  4. a paste that was refused (too large) does not queue its Enter; an accepted one does                     (BB-251020261341-4)
#  5. a long run of mouse release reports does not nest function calls (FUNCNEST would stop a recursion)      (BB-251020261341-5)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fail=0
source "$ROOT/tests/wait_lib.sh"
UI="$(bvk_need bashbasicsbyvk_settings_ui.sh)"; VP="$(bvk_need bashbasicsbyvk_viewport.sh)"; MS="$(bvk_need bashbasicsbyvk_mouse.sh)"
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

# the harness: 12 toggle rows; _st_draw prints  D cur=<row index> buf=[<line>] ; an activated row prints  ACT <row index> <key>
# stub for _bvk_paste_burst: $BURST = "N:TEXT:ENTER" -> on the Nth key read it answers "that key began a paste of TEXT (+ Enter if ENTER=1)"
read -r -d '' HARNESS <<'EOF'
source "$UI"; source "$VP"; source "$MS"
_st_draw() { echo "D cur=$cur buf=[$buf]"; }
_bvk_paste_on() { :; }; _bvk_paste_off() { :; }; _bvk_mouse_rearm() { :; }; _BVK_MOUSE_ON=1
_N=0
_bvk_paste_burst() {
  _N=$(( _N + 1 ))
  [ -n "${BURST:-}" ] && [ "${BURST%%:*}" = "$_N" ] || return 1
  local r="${BURST#*:}"; _BVK_PASTE="${r%:*}"; _BVK_PASTE_ENTER="${r##*:}"
  [ "${_BVK_PASTE:0:1}" = "@" ] && _BVK_PASTE="$(head -c "${_BVK_PASTE:1}" /dev/zero | tr '\0' 'x')"
  return 0
}
build() { _st_reset; local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do _st_add t "Row $i" 0; done; }
act() { echo "ACT $1 $2"; }
[ -n "${NEST:-}" ] && FUNCNEST="$NEST"
_st_run "T" build act
rc=$?; echo; echo "RC=$rc QUIT=$_st_quit"
EOF

# run <input as printf %b> [VAR=value ...]  -> the harness output (5 s hard limit: a loop that never ends shows up as RC=124)
run() { local in="$1"; shift; printf '%b' "$in" | env UI="$UI" VP="$VP" MS="$MS" "$@" timeout 5 bash -c "$HARNESS" 2>&1; echo "TIMEOUT_RC=${PIPESTATUS[1]}"; }
last_d() { grep '^D ' <<<"$1" | tail -1; }
acts() { grep -c '^ACT' <<<"$1"; }
chk() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; echo "$OUT" | tail -6 | sed 's/^/        /'; fi; }

# 1. EOF
OUT="$(run '')"
chk "EOF: the screen leaves (no endless loop)"           grep -q '^RC=0 QUIT=1' <<<"$OUT"
chk "EOF: nothing was typed into the line"               grep -q 'buf=\[\]' <<<"$(last_d "$OUT")"
OUT="$(run '\e[B')"
chk "EOF after a key: still leaves"                      grep -q '^RC=0 QUIT=1' <<<"$OUT"

# 2. an arrow's number is replaced by typing
OUT="$(run '\e[Bh')";   chk "Down, h -> the line is h (not 1h)"               grep -qx 'D cur=0 buf=\[h\]' <<<"$(last_d "$OUT")"
OUT="$(run '\e[B5')";   chk "Down, 5 -> row 5 (not 15)"                       grep -qx 'D cur=4 buf=\[5\]' <<<"$(last_d "$OUT")"
OUT="$(run '\e[B\e[B')"; chk "Down, Down -> the line follows the highlight"   grep -qx 'D cur=1 buf=\[2\]' <<<"$(last_d "$OUT")"
OUT="$(run '\e[B=')";   chk "Down, = -> a filter starts (the arrow's number is gone)" grep -qx 'D cur=-1 buf=\[=\]' <<<"$(last_d "$OUT")"
OUT="$(run '\e[B\n')";  chk "Down, Enter -> opens row 1"                      grep -qx 'ACT 0 toggle' <<<"$OUT"
OUT="$(run '12')";      chk "typing 1 then 2 still makes 12"                  grep -qx 'D cur=11 buf=\[12\]' <<<"$(last_d "$OUT")"

# escape-like TEXT typed on the keyboard is plain text (the ESC byte is what makes a key sequence)
OUT="$(run '[C')";          chk "typing [C is text, not a right arrow"       grep -qx 'D cur=-1 buf=\[\[C\]' <<<"$(last_d "$OUT")"
OUT="$(run '[<0;44;37M')";  chk "typing [<0;44;37M is text, not a click"      grep -qx 'D cur=-1 buf=\[\[<0;44;37M\]' <<<"$(last_d "$OUT")"
OUT="$(run '[C\n')";        chk "[C + Enter: not a command, the line is cleared" grep -qx 'D cur=-1 buf=\[\]' <<<"$(last_d "$OUT")"

# 3. no stale highlight
OUT="$(run '1000 ')";   chk "1000 (no such row), Space -> nothing toggles"    test "$(acts "$OUT")" = 0
chk "1000 leaves nothing highlighted"                                         grep -qx 'D cur=-1 buf=\[1000\]' <<<"$(last_d "$OUT")"
OUT="$(run '15 ')";     chk "15 of 12 rows, Space -> nothing toggles"         test "$(acts "$OUT")" = 0
OUT="$(run '1\x7f\n')"; chk "1, Backspace, Enter -> nothing is opened"        test "$(acts "$OUT")" = 0
chk "1, Backspace -> the typed highlight is gone"                             grep -qx 'D cur=-1 buf=\[\]' <<<"$(last_d "$(run '1\x7f')")"
OUT="$(run '1\x7f1\n')"; chk "1, Backspace, 1, Enter -> row 1 opens"          grep -qx 'ACT 0 toggle' <<<"$OUT"
OUT="$(run '\e[B\x7f\n')"; chk "Down, Backspace, Enter -> the arrow's row still opens" grep -qx 'ACT 0 toggle' <<<"$OUT"
OUT="$(run '3\n')";     chk "3, Enter -> row 3 opens (unchanged)"             grep -qx 'ACT 2 toggle' <<<"$OUT"
OUT="$(run '3 ')";      chk "3, Space -> row 3 toggles (unchanged)"           grep -qx 'ACT 2 toggle' <<<"$OUT"
OUT="$(run '1000\x7f\x7f\x7f ')"; chk "1000, 3x Backspace, then Space -> row 1 (the number is valid again)" grep -qx 'ACT 0 toggle' <<<"$OUT"

# 4. a refused paste does not bring its Enter along
OUT="$(run '3x' BURST='2:@900:1')"
chk "too-large paste + Enter: the Enter is NOT run (row 3 stays closed)"      test "$(acts "$OUT")" = 0
chk "too-large paste: the line keeps what was typed"                          grep -qx 'D cur=2 buf=\[3\]' <<<"$(last_d "$OUT")"
OUT="$(run '1x' BURST='2:1:1')"
chk "accepted paste + Enter: the Enter runs (11 -> row 11)"                   grep -qx 'ACT 10 toggle' <<<"$OUT"

# 5. mouse releases are skipped in a loop
rel=''; for _ in $(seq 1 120); do rel+='\e[<0;5;5m'; done
OUT="$(run "${rel}x" NEST=60)"
chk "120 release reports, then x: no nested calls, the key arrives"           grep -qx 'D cur=-1 buf=\[x\]' <<<"$(last_d "$OUT")"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
