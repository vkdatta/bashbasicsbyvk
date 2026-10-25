#!/usr/bin/env bash
# A question that deletes / removes / clears / overwrites has NO default answer: a bare Enter must never answer it.   bash tests/delete_confirm.sh
# (1) behaviour: _bvk_yn takes `-d n` / `-d y` / no -d on a destructive question as "no default" (the person must answer), a harmless one keeps its default
# (2) every _bvk_yn call whose question names a destructive action says `-d none` in the source too (the rule is enforced in _bvk_yn; this keeps the source honest)
# (3) the shared helper _xui_yes (Nuke / Remove / Revoke ... share and user lists) goes through _bvk_yn, so it is covered by (1)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/script"; fail=0
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
source "$S/file/settings/bashbasicsbyvk_choose.sh"

t() { local want="$1" in="$2"; shift 2; local out; out=$(printf '%b' "$in" | { "$@"; echo "a=[$a] rc=$?"; }); [[ "$out" == *"$want" ]] && ok "$want  <- $(printf '%q' "$in")  ${*:2:2}" || bad "want '$want' got '${out##*$'\n'}'  <- $(printf '%q' "$in")  $*"; }
# (1) a bare Enter does not answer a destructive question, whatever default the caller wrote; EOF backs out; a typed answer still works
t 'a=[] rc=1'  '\n'     _bvk_yn a "Delete 3 items?" -d n
t 'a=[] rc=1'  '\n'     _bvk_yn a "Delete 3 items?" -d y
t 'a=[] rc=1'  '\n'     _bvk_yn a "Delete 3 items?"
t 'a=[y] rc=0' '\ny\n'  _bvk_yn a "Nuke 2 share(s)?" -d n
t 'a=[n] rc=0' '\nn\n'  _bvk_yn a "Clear the entire buffer?" -d n
t 'a=[y] rc=0' 'y\n'    _bvk_yn a "Remove 1 user(s)?" -d none
t 'a=[] rc=1'  '\n'     _bvk_yn a "Overwrite the file?" -d n
t 'a=[] rc=1'  '\n'     _bvk_yn a "Are you really sure?" -d n
t 'a=[] rc=1'  '\n'     _bvk_yn a "Revoke 2 people?" -d n
t 'a=[] rc=1'  '\n'     _bvk_yn a "Free the downloaded content of this whole Drive?" -d n
# a harmless question keeps its default
t 'a=[n] rc=0' '\n'     _bvk_yn a "Open in browser now?" -d n
t 'a=[y] rc=0' '\n'     _bvk_yn a "Open in browser now?" -d y

# (2) the source says it too
miss=""
while IFS= read -r line; do
  q="$(sed -nE 's/.*_bvk_yn +[A-Za-z_]+ +"([^"]*)".*/\1/p' <<<"$line")"
  [ -n "$q" ] || continue
  _bvk_destructive "$q" || continue
  [[ "$line" == *"-d none"* ]] || miss+=$'\n    '"${line:0:170}"
done < <(grep -rhE '^[^#]*_bvk_yn +[A-Za-z_]+ +"' "$S" --include='*.sh' | grep -v 'bashbasicsbyvk_choose.sh')
[ -z "$miss" ] && ok "every destructive _bvk_yn call says -d none" || bad "destructive question without -d none:$miss"

# (3) _xui_yes (shared by Cloud Surf and RBAM) asks through _bvk_yn
grep -A3 '^_xui_yes()' "$S/file/loops/iloop/rbam/bashbasicsbyvk_xui.sh" | grep -q '_bvk_yn' && ok "_xui_yes asks through _bvk_yn (the rule applies to Nuke / Remove / Revoke there)" || bad "_xui_yes no longer uses _bvk_yn"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
