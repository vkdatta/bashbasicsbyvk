#!/usr/bin/env bash
# ALL scoring tests, no terminal, every menu — a few seconds.   bash tests/advert_score.sh
# (the slow truth audit that types into the real app is  python3 tests/advert_pty.py  — run it when you want a live cross-check)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
s=$(date +%s.%N); rc=0
echo "── registry · budget · dispatcher (unit) ──";  bash tests/cc_footer_truth.sh | grep -v "^  ok" ; [ "${PIPESTATUS[0]}" = 0 ] || rc=1
echo "── every menu: declared (cc) vs handled vs footer ──"; python3 tests/advert_static.py || rc=1
echo "── footer keys are wired (cmd_drift) ──"; bash tests/cmd_drift.sh | tail -1; [ "${PIPESTATUS[0]}" = 0 ] || rc=1
e=$(date +%s.%N); printf 'done in %.1f s\n' "$(echo "$e - $s" | bc)"; exit $rc
