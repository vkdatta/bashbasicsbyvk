#!/usr/bin/env bash
# The master menu templates (menuchrome.sh): selection / text / review return codes, q unwinds, h + cc run, and no menu
# drifts away from them (no hand-made "u q" footers, no private Choice:/Nav:/Action: prompts).   bash tests/menu_templates.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; F="$ROOT/script/file"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
_vp_usable() { _vp_usable_w=80; }; _vp_cells() { _vp_w=${#1}; }; _sm_on=0
_BVK_TO_MAIN=0; _bvk_quit() { _BVK_TO_MAIN=1; return 0; }; _bvk_invalid() { echo "INVALID"; }
bvk_main_exec() { echo "[ran $1]"; }
parse_selection() { local p i; for p in ${1//,/ }; do if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then for ((i=BASH_REMATCH[1]; i<=BASH_REMATCH[2]; i++)); do [ "$i" -le "$2" ] && echo "$i"; done; elif [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -le "$2" ]; then echo "$p"; fi; done; }
source "$F/engine/bashbasicsbyvk_menuchrome.sh"
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1: want [$3] got [$2]"; }
sel() { local in="$1"; shift; local out rc; out=$(printf "$in" | { "$@"; echo "rc=$? v=${V:-} q=$_BVK_TO_MAIN"; } 2>&1); echo "${out##*$'\n'}"; }
two() { _mc_select -d exact V "T" "exact|Exact Case|e" "any|Any Case|a"; }
eq "number picks row 2"            "$(sel '2\n' two)" "rc=0 v=any q=0"
eq "Enter picks the default"       "$(sel '\n' two)"  "rc=0 v=exact q=0"
eq "typed alias picks a row"       "$(sel 'a\n' two)" "rc=0 v=any q=0"
eq "u = back (1)"                  "$(sel 'u\n' two)" "rc=1 v= q=0"
eq "q = quit (2) and raises unwind" "$(sel 'q\n' two)" "rc=2 v= q=1"
eq "EOF = cancelled (3)"           "$(sel '' two)"    "rc=3 v= q=0"
eq "invalid redraws, then 1"       "$(sel 'zz\n1\n' two)" "rc=0 v=exact q=0"
out=$(printf 'h\n2\n' | two 2>&1); [[ "$out" == *"[ran h]"* ]] && ok "h runs Home, the menu draws again" || bad "h not run"
out=$(printf 'cc\n1\n' | two 2>&1); [[ "$out" == *"[ran cc]"* ]] && ok "cc runs Cheat codes" || bad "cc not run"
out=$(two </dev/null 2>&1); foot=$(grep -n "u) Up   q) Quit   h) Home   cc) Cheat codes" <<<"$out" | head -1)
[ -n "$foot" ] && ok "footer is the standard u q h cc, below the rows" || bad "standard footer missing"
# review: confirm / remove / quit
A=(/a/x /a/y /a/z)
rv() { A=(/a/x /a/y /a/z); printf "$1" | { _mc_review A; echo "rc=$? n=${#A[@]} q=$_BVK_TO_MAIN"; } 2>&1 | tail -1; }
eq "review: c confirms"            "$(rv 'c\n')" "rc=0 n=3 q=0"
eq "review: x 1,3 removes two"     "$(rv 'x\n1,3\nc\n')" "rc=0 n=1 q=0"
eq "review: u is back (1)"         "$(rv 'u\n')" "rc=1 n=3 q=0"
eq "review: q is quit (2), flag up, no redraw" "$(rv 'q\nc\n')" "rc=2 n=3 q=1"
eq "review: EOF is cancelled, never spins"     "$(rv '')" "rc=3 n=3 q=0"
# the tab menu footers come from the same standard
eq "tabmenu footer = standard"  "$(grep -c 'std_nav' "$F/engine/bashbasicsbyvk_tabmenu.sh")" "2"
# drift: no hand-made u/q footers or private prompts outside the master
d=$(grep -rnE '_mc_footer [^#]*"u(\.up)?" "q"' --include='*.sh' "$F" | grep -v 'menuchrome.sh' | head -3)
[ -z "$d" ] && ok "no hand-made u/q footer (use _mc_footer_std)" || bad "hand-made footer: $d"
d=$(grep -rnE 'read -e -?r? ?-p "(Choice|Nav|GCloud Nav|Action|Pick|Selected items|Selection view): ' --include='*.sh' "$F" | head -3)
[ -z "$d" ] && ok "no private Choice:/Nav:/Action:/Pick: prompt" || bad "private prompt: $d"
d=$(grep -rn '@back_quit' --include='*.sh' "$F" | grep -v 'menuchrome.sh' | head -3)
[ -z "$d" ] && ok "no menu is wired by hand to the back_quit footer" || bad "hand-wired: $d"
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"; exit "$fail"
