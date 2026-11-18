#!/usr/bin/env bash
# tests/static/lib/dump_resolve.sh MAP [MAP...] — ONE process: the REAL _cm_resolve / _cm_hint / _cc_collect for the map(s), both modes.
# Rows (TSV):  R map mode word act key handler class impl   |   H map mode prefix hint   |   C map mode key act   (the cc list and what each listed key does)
# Cost control: words that are blocked are probed only as themselves; the rest also upper-case, with an argument, (prefix kinds) with a list;
# live suggestions are probed once per distinct prefix.  (31 maps in about 10 s on 2 cores; tests/static/lib/bvk.py caches the result by a hash of its inputs.)
source "$(dirname "${BASH_SOURCE[0]}")/load.sh"; bvk_load cc || exit $?
ERR=("" " " "zzz" "@" "@@" "@s" "-" "--" "=" "==" "1" "99999" "1,3" "1-5" "a" "a-2" "-1" "1,,2" "3-1" $'\t' $'\x01' "é" "😀" "q q" "u u" "$(printf 'x%.0s' {1..300})")
for m in "$@"; do
  _CM_MAP="$m"; _CM_TBL_MAP=""; _cm_table_build "$m"
  declare -A seen=() hp=(); words=()
  add() { [ -z "${seen[k$1]+x}" ] && { seen[k$1]=1; words+=("$1"); }; return 0; }
  for i in "${!_ct_key[@]}"; do
    k="${_ct_key[i]}"; add "$k"; _cm_resolve menu "$k"
    [ "$_CM_ACT" = block ] && continue
    add "${k^^}"; add "${k}1"; [ "${_ct_kind[i]}" != exact ] && add "${k}1,3"
  done
  for w in "${ERR[@]}"; do add "$w"; done
  for md in menu text; do
    for w in "${words[@]}"; do
      _cm_resolve "$md" "$w"
      printf 'R\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$m" "$md" "${w//$'\t'/<TAB>}" "$_CM_ACT" "$_CM_KEY" "$_CM_HANDLER" "$_CM_CLASS" "$_CM_IMPL"
    done
    hp=()
    for i in "${!_ct_key[@]}"; do
      k="${_ct_key[i]}"; [ "${#k}" -ge 2 ] || continue; [ "${_ct_tgt[i]}" = BLOCK ] && continue
      hp[${k:0:1}]=1; [ "${#k}" -ge 3 ] && hp[${k:0:${#k}-1}]=1
    done
    for pre in "${!hp[@]}"; do
      _hint_want=""; _cm_hint "$pre" "$md" >/dev/null 2>&1
      printf 'H\t%s\t%s\t%s\t%s\n' "$m" "$md" "$pre" "${_hint_want//$'\n'/ }"
    done
  done
  for flow in 0 1; do
    _CM_FLOW=$flow; _CM_MAP="$m"; _CC_CTX=""; _cc_collect
    md=menu; { [ "${_CM_MAP_KIND[$m]:-menu}" = prompt ] || [ "$flow" != 0 ]; } && md=text
    _CM_TBL_MAP=""; _cm_table_build "$m"
    for k in "${_CC_KEY[@]}"; do _cm_resolve "$md" "$k"; printf 'C\t%s\t%s\t%s\t%s\n' "$m" "$md" "$k" "$_CM_ACT"; done
  done; _CM_FLOW=0
  unset seen hp
done
