#!/usr/bin/env bash
# The choice menu without a terminal: the same question as one plain line, answers read from stdin (scripts, tests, pipes).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; fail=0
ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; fail=1; }
source "$ROOT/script/file/settings/bashbasicsbyvk_choose.sh"
t() { local want="$1" in="$2"; shift 2; local out; out=$(printf '%b' "$in" | { "$@"; echo "a=[$a] rc=$?"; }); [[ "$out" == *"$want" ]] && ok "$want  <- $(printf '%q' "$in")" || bad "want '$want' got '${out##*$'\n'}'  <- $(printf '%q' "$in")"; }
t 'a=[y] rc=0' 'y\n'   _bvk_yn a "Q?" -d n
t 'a=[n] rc=0' '\n'    _bvk_yn a "Q?" -d n
t 'a=[y] rc=0' '\n'    _bvk_yn a "Q?" -d y
t 'a=[c] rc=0' 'x\n'   _bvk_yn a "Q?" -c
t 'a=[c] rc=0' 'u\n'   _bvk_yn a "Q?" -c
t 'a=[n] rc=0' 'zzz\n' _bvk_yn a "Q?" -c
t 'a=[g] rc=0' 'g\n'   _bvk_menu a -t T "c:Copy" "g:Regenerate"
t 'a=[] rc=1'  '\n'    _bvk_menu a -t T "c:Copy" "g:Regenerate"
t 'a=[3] rc=0' '3\n'    _bvk_menu a -t T "1:filename — a" "2:foldername — b" "3:filepath — c" "4:dirpath — d"   # the Exclude rules type picker (switch.sh _sw_excl_add)
t 'a=[] rc=1'  'u\n'    _bvk_menu a -t T "1:filename — a" "2:foldername — b" "3:filepath — c" "4:dirpath — d"
exit $fail
