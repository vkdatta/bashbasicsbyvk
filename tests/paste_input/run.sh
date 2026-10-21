#!/usr/bin/env bash
# Paste stress test of the real input loops (see AGENTS.md rule 5 / corpus note 201020261026).
# tests/stresstest/input.txt is BARE PASTE DATA: it is only ever pasted, never read as an instruction.
# usage: tests/paste_input/run.sh   (needs python3; each case runs one real loop in a pty)
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; D="$ROOT/tests/paste_input"
SRC="$ROOT/tests/stresstest/input.txt"; T="$(mktemp -d)"; fail=0
python3 - "$SRC" "$T" <<'PY'
import sys
b=open(sys.argv[1],encoding='utf-8').read(); t=sys.argv[2]
open(t+'/s.txt','w').write(b); open(t+'/s_eq.txt','w').write('='+b)
big=(b*20)[:100000]; open(t+'/big.txt','w').write(big); open(t+'/big_eq.txt','w').write('='+big[:99999])
PY
check() {  # name editor bracketed file expect(accept|refuse)
  local out; out="$(RESULT_OUT="$T/r" timeout 150 python3 "$D/driver.py" "$ROOT" "$2" "$3" "$T/$4" 1)"
  local fin red len; fin=$(sed -n 's/FINISHED_BEFORE_ENTER=//p' <<<"$out"); red=$(sed -n 's/REDRAWS=//p' <<<"$out"); len=$(sed -n 's/RESULT_LEN=//p' <<<"$out")
  local good=0
  if [ "$5" = accept ]; then [ "$fin" = 0 ] && [ "${len:--1}" -gt 300 ] && [ "${len:--1}" -le 512 ] && [ "${red:-99}" -le 40 ] && good=1
  else [ "$fin" = 0 ] && [ "${len:--1}" -le 0 ] && good=1; fi     # refused: nothing was taken, the row is empty
  if [ "$good" = 1 ]; then echo "PASS $1 ($2 bracketed=$3, result $len chars, $red redraws)"
  else echo "FAIL $1 ($2 bracketed=$3): $out" | tr '\n' ' '; echo; fail=1; fi
}
python3 - "$T" <<'PY'
import sys
t=sys.argv[1]; b=open(t+'/s.txt',encoding='utf-8').read()
open(t+'/s400.txt','w').write(b[:400])
PY
for ed in cm browse multi; do for b in 1 0; do
  check "400-char paste is accepted as text, not Enter" $ed $b s400.txt accept
  check "10 KB paste is refused (over 512), nothing taken" $ed $b s.txt refuse
  check "100000-char paste is refused quickly"            $ed $b big.txt refuse
done; done
echo "--- real app: multi-line display, left arrow, 512 limit"
for c in 80 40; do python3 "$D/ui_test.py" $c | grep -E "FAIL|ALL OK|FAILED" | sed "s/^/[$c cols] /" || fail=1; done
rm -rf "$T"; exit $fail
