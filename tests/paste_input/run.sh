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
check() {  # name editor bracketed file
  local out; out="$(RESULT_OUT="$T/r" timeout 150 python3 "$D/driver.py" "$ROOT" "$2" "$3" "$T/$4" 1)"
  local fin red len; fin=$(sed -n 's/FINISHED_BEFORE_ENTER=//p' <<<"$out"); red=$(sed -n 's/REDRAWS=//p' <<<"$out"); len=$(sed -n 's/RESULT_LEN=//p' <<<"$out")
  if [ "$fin" = 0 ] && [ "${len:--1}" -gt 1000 ] && [ "${red:-99}" -le 40 ]; then echo "PASS $1 ($2 bracketed=$3, $len chars, $red redraws)"
  else echo "FAIL $1 ($2 bracketed=$3): $out" | tr '\n' ' '; echo; fail=1; fi
}
for ed in cm browse multi; do for b in 1 0; do
  check "10KB paste is text, not Enter" $ed $b s.txt
  check "100000-char paste"            $ed $b big.txt
done; done
echo "(a paste starting with '=' goes to the filter; the live filter is covered by running the real app: see the corpus note)"
rm -rf "$T"; exit $fail
