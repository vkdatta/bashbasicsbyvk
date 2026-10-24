#!/usr/bin/env bash
# Find & replace engine tests.  bash tests/findrep/findrep_run.sh [quick|full]
#   builds the C engine (bvk-fr) natively into a temp dir, then runs findrep_test.py on it AND on the Python twin (differential check).
#   quick (default) = a few hundred operations, seconds · full = 1200 random operations + 1500 regexes (~3 min)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; cd "$ROOT" || exit 2
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
E="script/file/engine/bvk-fr"
command -v cc >/dev/null 2>&1 || { echo "SKIP: no C compiler"; exit 0; }
cc -std=c11 -O2 -Wall -Wextra -D_GNU_SOURCE -D_DEFAULT_SOURCE -fPIE -I"$E/include" "$E"/src/*.c -o "$T/bvk-fr" -pthread -pie || { echo "FAIL: bvk-fr does not compile"; exit 1; }
if [ "${1:-quick}" = full ]; then n=1200; rx=1500; else n=120; rx=150; fi
python3 -W ignore -I tests/findrep/findrep_test.py --engine "$T/bvk-fr" --engine script/file/functions/bashbasicsbyvk_findrep --n "$n" --rx "$rx" --seed 1
