#!/usr/bin/env bash
# Settings / cc list must not stack its header when the cached terminal size is stale.
#   bash tests/stale_size/run.sh
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
ROOT="$(cd ../.. && pwd)/script"
out=$(python3 emu.py "$ROOT" 50 46)   # cache says 50 rows, the pty really has 46
echo "$out"
[[ "$out" == *": 1" ]] && echo "ok" || { echo "FAIL: header stacked"; exit 1; }
