# Unit test of the text-edit template (script/file/engine/bashbasicsbyvk_textedit.sh): chord decoding, selection, word / line moves,
# cut / copy / paste (the app's own clipboard), undo / redo, the reverse-video marking.  No terminal needed.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/script/file/engine/bashbasicsbyvk_textedit.sh"
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got [$2] want [$3]"; fi; }
nop() { :; }
k() { # chord... applied to B/P
  local c; for c in "$@"; do _te_dispatch "$c" B P text nop nop nop; done; }
reset() { B="$1"; P=${2:-${#1}}; _TE_ANC=-1; _TE_ABUF=""; _TE_UNDO=(); _TE_REDO=(); _TE_LASTOP=""; }
# decode
_te_decode_esc '[1;2D'; chk dec-shift-left "$_TE_CH" shift-left
_te_decode_esc '[1;5C'; chk dec-ctrl-right "$_TE_CH" ctrl-right
_te_decode_esc '[1;6D'; chk dec-ctrl-shift-left "$_TE_CH" ctrl-shift-left
_te_decode_esc '[3~';   chk dec-delete "$_TE_CH" delete
_te_decode_esc '[3;5~'; chk dec-ctrl-delete "$_TE_CH" ctrl-delete
_te_decode_esc '[2;2~'; chk dec-shift-insert "$_TE_CH" shift-insert
_te_decode_esc '[99;6u'; chk dec-kitty-ctrl-shift-c "$_TE_CH" ctrl-shift-c
_te_decode_esc '[27;5;118~'; chk dec-xterm-ctrl-v "$_TE_CH" ctrl-v
_te_decode_esc '[1;2H'; chk dec-shift-home "$_TE_CH" shift-home
_te_decode_esc 'OH'; chk dec-ss3-home "$_TE_CH" home
_te_decode_esc $'\x7f'; chk dec-alt-bs "$_TE_CH" ctrl-backspace
_te_decode_esc 'b'; chk dec-alt-b "$_TE_CH" ctrl-left
_te_decode_esc '[<0;5;5M'; chk dec-mouse-rc "$?" 1
_te_decode_esc '[200~'; chk dec-paste-rc "$?" 1
_te_decode_byte $'\x01'; chk byte-ctrl-a "$_TE_CH" ctrl-a
_te_decode_byte a; chk byte-a-rc "$?" 1
# movement + selection
reset "hello world"
k shift-left shift-left shift-left
_te_sel "$B" "$P"; chk sel-lohi "$_TE_LO-$_TE_HI" "8-11"
k left; chk collapse-left "$P" 8; _te_sel "$B" "$P"; chk collapse-nosel "$?" 1
reset "hello world" 0
k ctrl-right; chk word-right "$P" 5
k ctrl-right; chk word-right2 "$P" 11
k ctrl-left; chk word-left "$P" 6
k ctrl-shift-left; _te_sel "$B" "$P"; chk word-select "$_TE_LO-$_TE_HI" "0-6"
reset "hello world" 3
k shift-home; _te_sel "$B" "$P"; chk shift-home "$_TE_LO-$_TE_HI" "0-3"
reset "hello world" 3
k shift-end; _te_sel "$B" "$P"; chk shift-end "$_TE_LO-$_TE_HI" "3-11"
reset "hello world" 7
k shift-up; chk shift-up-start "$P" 0
reset "hello world" 3
k shift-down; chk shift-down-end "$P" 11
reset $'ab\ncdef\ngh' 5
k shift-up; chk multiline-up "$P" 2
reset $'ab\ncdef\ngh' 5
k shift-down; chk multiline-down "$P" 10
# select all / delete / replace
reset "abc"
k ctrl-a; _te_sel "$B" "$P"; chk selall "$_TE_LO-$_TE_HI" 0-3
k backspace; chk selall-bs "[$B]" "[]"
reset "abc"; k ctrl-a; _te_insert B P x; chk replace "$B/$P" "x/1"
reset ""; _te_apply ctrl-a B P list; chk ctrl-a-empty-list-rc "$?" 0
_te_apply ctrl-a B P text; chk ctrl-a-empty-text-rc "$?" 4
reset "abc" 1; _te_apply left B P list; chk left-nonempty-list "$P" 0
reset "" 0; _te_apply left B P list; chk left-empty-list-rc "$?" 0
reset "abc" 1; _te_apply up B P list; chk up-list-rc "$?" 0
reset "abc" 1; _te_apply home B P list; chk home-list-rc "$?" 0
reset "abc" 1; _te_apply home B P text; chk home-text "$P" 0
reset "abc" 1; _te_apply ctrl-home B P list; chk ctrl-home-list "$P" 0
# word deletes
reset "foo bar baz"
k ctrl-backspace; chk ctrl-bs "$B" "foo bar "
k ctrl-w; chk ctrl-w "$B" "foo "
reset "foo bar baz" 4; k ctrl-delete; chk ctrl-del "$B" "foo  baz"
reset "foo bar baz" 4; k ctrl-k; chk ctrl-k "$B" "foo "
reset "foo bar baz" 4; k ctrl-u; chk ctrl-u "$B/$P" "bar baz/0"
reset "abc" 1; k delete; chk delete "$B" "ac"
reset "abc" 3; k delete; chk delete-end "$B" "abc"
reset "abc" 1; _te_apply ctrl-d B P text; chk ctrl-d-del "$?" 2
reset ""; _te_apply ctrl-d B P text; chk ctrl-d-empty-rc "$?" 0
# clipboard internal: cut/copy/paste
reset "hello world" 11
k shift-left shift-left shift-left shift-left shift-left
k ctrl-c; chk copy-text "$_TE_CLIP" world; chk copy-keeps "$B" "hello world"
k ctrl-x; chk cut "$B" "hello "
reset "ab" 2; _te_apply ctrl-v B P text; rc=$?; chk paste-rc "$rc" 3; chk paste-text "$_BVK_PASTE" world
# undo / redo
reset "abc" 3
_te_insert B P x; _te_insert B P y; chk typed "$B" abcxy
k ctrl-z; chk undo-coalesced "$B" abc
k ctrl-y; chk redo "$B" abcxy
reset "abc" 3; k backspace backspace; chk bs2 "$B" a; k ctrl-z; chk undo-bs "$B" abc
reset "abc" 3; k ctrl-a backspace; k ctrl-z; chk undo-cut "$B" abc
# hl
reset "hello world" 11; k shift-left shift-left shift-left
_te_hl "$B" "$P" 0 11; chk hl "${_TE_OUT//$'\033'/E}" "hello woE[7mrldE[27m"
_te_hl "$B" "$P" 9 2;  chk hl-slice "${_TE_OUT//$'\033'/E}" "E[7mldE[27m" 2>/dev/null || true
_te_sel_len "$B" "$P"; chk sellen "$_TE_N" 3
B="other"; _te_hl "$B" 3 0 5; chk hl-stale "$_TE_OUT" other
echo "pass=$pass fail=$fail"; [ "$fail" -eq 0 ]
