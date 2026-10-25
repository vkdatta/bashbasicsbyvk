#!/usr/bin/env bash
# Every Settings screen and row explains itself in plain words (AGENTS rule 8).   bash tests/settings_desc.sh
# (1) the table: well-formed keys, no empty or duplicate text
# (2) the lookup: the highlighted row's text, else the screen's text, none on a short terminal, cut with "(? = all)" when long, never wider than the screen
# (3) coverage: every Settings screen and every literal row has a line (a new row without one fails here, not silently on a user's screen)
# (4) settings_ui.sh draws without settings_desc.sh loaded (a stand-alone caller must not break)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; D="$ROOT/script/file"; fail=0
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
f="$D/settings/bashbasicsbyvk_settings_desc.sh"

# (1)
tbl="$(sed -n "/<<'BVK_DESC_EOF'/,/^BVK_DESC_EOF/p" "$f" | sed '1d;$d')"
n=$(grep -c . <<<"$tbl")
[ "$n" -ge 300 ] && ok "table has $n lines" || bad "table has only $n lines"
badfmt=$(awk -F'\t' 'NF!=2 || $1 !~ /\|/ || length($2) < 20 {print NR": "substr($0,1,60)}' <<<"$tbl" | head -3)
[ -z "$badfmt" ] && ok "every line is  <screen>|<row><TAB><text>  with a real text" || bad "malformed table line: $badfmt"
dup=$(cut -f1 <<<"$tbl" | sort | uniq -d | head -3)
[ -z "$dup" ] && ok "no duplicate key" || bad "duplicate key: $dup"

# (2)
source "$f"
st() {   # st ROWS COLS TITLE PARENT CUR TAG   (the locals _st_draw hands to _st_desc_prepare)
  local rows=$1 cols=$2 title=$3 parent_title=$4 cur=$5; local -a _st_kind=(a) _st_tag=("$6")
  _st_desc_prepare; local last=""; (( ${#_ST_DESC_LN[@]} )) && last="${_ST_DESC_LN[${#_ST_DESC_LN[@]}-1]}"
  echo "$_ST_DESC_N|$_ST_DESC_TRUNC|${_ST_DESC_LN[0]-}|$last"
}
r="$(st 40 80 Display "Settings" 0 hidden)";  [[ "$r" == [1-9]*"|0|Decides whether hidden files"* ]] && ok "a highlighted row shows ITS text" || bad "row text: $r"
r="$(st 40 80 Display "Settings" -1 "")";     [[ "$r" == [1-9]*"|0|How the list of files looks"* ]] && ok "nothing highlighted shows the screen's text" || bad "screen text: $r"
r="$(st 40 80 Display "Settings" 0 nosuchrow)"; [[ "$r" == [1-9]*"|0|How the list of files looks"* ]] && ok "a row without a line shows its screen's text" || bad "fallback: $r"
r="$(st 40 80 "No such screen" "" 0 x)";      [[ "$r" == "0|0|"* ]] && ok "a screen without a line shows nothing (and breaks nothing)" || bad "unknown screen: $r"
r="$(st 17 80 Display "Settings" 0 hidden)";  [[ "$r" == "0|0|"* ]] && ok "a short terminal (< 18 rows) shows no description" || bad "short terminal: $r"
r="$(st 18 40 Display "Settings" 0 hidden)";  [[ "$r" == *"|1|"*"(? = all)" ]] && ok "a long text is cut with (? = all) and flagged" || bad "truncation: $r"
w=$(  rows=40 cols=30 title=Display parent_title=Settings cur=0; _st_kind=(a); _st_tag=(hidden); _st_desc_prepare; for l in "${_ST_DESC_LN[@]}"; do echo ${#l}; done | sort -n | tail -1)
[ "${w:-999}" -le 30 ] && ok "no line is wider than the screen ($w <= 30)" || bad "a line is $w wide on a 30-column screen"
r="$( rows=40 cols=80 title=Sort\ order parent_title="Settings › Pending uploads (pn)" cur=0; _st_kind=(a); _st_tag=(srv); _st_desc_prepare; echo "${_ST_DESC_LN[0]}")"
[[ "$r" == "This computer's own unfinished uploads"* ]] && ok "a parent-qualified key wins over the shared title" || bad "parent key: $r"

# the block keeps ONE height while the highlight moves (it is erased and redrawn by row count: a block that grew and shrank with the row moved the prompt)
hs=""; for c in -1 0 1 2 3 4 5 6; do
  hs+="$( rows=30 cols=80 title=Display parent_title=Settings cur=$c; _st_kind=(a a a a a a); _st_tag=(hidden sort details group index anim); _st_desc_prepare; echo -n "$_ST_DESC_N" ) "
done
[ "$(tr ' ' '\n' <<<"$hs" | grep . | sort -u | wc -l)" = 1 ] && [ "${hs%% *}" -gt 0 ] && ok "every row of a screen gets a description block of the same height ($hs)" || bad "the block height changes with the highlighted row: $hs"
r="$( rows=30 cols=80 title=Display parent_title=Settings cur=0; _st_kind=(a a); _st_tag=(hidden nosuch); _st_desc_prepare; echo "${#_ST_DESC_LN[@]}" )"
c="$( rows=30 cols=80 title=Display parent_title=Settings cur=1; _st_kind=(a a); _st_tag=(hidden nosuch); _st_desc_prepare; echo "${#_ST_DESC_LN[@]}" )"
[ "$r" = "$c" ] && ok "a row with a shorter text is padded to the screen's height" || bad "heights differ: $r vs $c"

# (3)
python3 -I "$ROOT/tests/settings_desc/coverage.py" "$D" || fail=1

# (4)
out="$(bash -c '
  _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }
  source "'"$D"'/engine/bashbasicsbyvk_viewport.sh"; source "'"$D"'/settings/bashbasicsbyvk_settings_ui.sh"
  declare -F _st_desc_prepare >/dev/null && echo DESC_LOADED
  rows=40; cols=80; title=T; parent_title=""; cur=-1; _st_kind=(); _st_tag=()
  _vp_rows_now=40; _vp_cols_now=80
  _st_reset; _st_add a "One" 0 "" one
  _st_draw >/dev/null 2>&1; echo "rc=$? n=${_ST_DESC_N:-unset}"' 2>&1 | tail -2)"
[[ "$out" == *"rc=0 n=0"* && "$out" != *DESC_LOADED* ]] && ok "settings_ui.sh draws with no description file loaded" || bad "settings_ui without settings_desc: $out"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
