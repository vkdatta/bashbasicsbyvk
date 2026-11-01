#!/usr/bin/env bash
# _vp_cells (display width in terminal cells of a row) gives the widths it always gave, and the first paint measures a row fast.     bash tests/cell_width.sh
# The expected numbers were produced by the original character-by-character version (every character looked at) before it was sped up.
set -u
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V="$(find "$ROOT/script" -name bashbasicsbyvk_viewport.sh -print -quit)"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
eval "$(sed -n '/^_vp_strip_ansi()/,/^}/p;/^_vp_in_set()/,/^}/p;/^_vp_cpw()/,/^}/p;/^_VP_WIDE_BMP=/p;/^_VP_TEXT_EMOJI=/p;/^_vp_cells()/,/^}/p;/^declare -gA _VP_CWC/p' "$V")"
declare -F _vp_cells >/dev/null || { bad "_vp_cells not found"; echo FAILED; exit 1; }
chk() { _vp_cells "$2"; [ "$_vp_w" = "$1" ] && ok "$1 cells: ${2//$'\033'/<ESC>}" || bad "want $1 got $_vp_w: ${2//$'\033'/<ESC>}"; }
chk 3  "abc"
chk 15 " 1) 📁 file.txt"
chk 14 " 12) ⚙️  run.sh"
chk 22 " 3) 🌄 pic.png | 12 KB"
chk 20 "日本語のファイル.txt"
chk 1  "é"
chk 12 "🧩 plugin 🔒"
chk 15 $'\033[1;7m 4) 📦 a.tar.gz\033[0m'
chk 6  "Ａｂｃ"
chk 26 "🛑 This directory is empty"
chk 11 "한국어 파일"
chk 9  "⏳ ... ⭐"
chk 13 "👨‍👩‍👧 family"
chk 0  ""
# the same character twice and a repeat call (the remembered width) give the same answer
_vp_cells " 1) 📁 a"; a=$_vp_w; _vp_cells " 2) 📁 b"; b=$_vp_w; [ "$a" = "$b" ] && ok "a remembered character measures the same" || bad "memo differs $a $b"
# speed: 52 first-screen rows must not take 100 ms even on a slow CI box (the old version needed ~40 ms here; this one ~4 ms)
rows=(); for i in $(seq 1 52); do rows+=(" $i) 📁 some-folder-name-$i | 12 KB"); done
t0=${EPOCHREALTIME/[.,]/}; for r in 1 2 3 4 5 6 7 8 9 10; do for s in "${rows[@]}"; do _vp_cells "$s"; done; done; t1=${EPOCHREALTIME/[.,]/}
per=$(( (t1 - t0) / 10 / 1000 ))
[ "$per" -lt 25 ] && ok "52 rows measured in ${per} ms" || bad "52 rows took ${per} ms (the character-by-character version needs ~40 ms or more)"
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
