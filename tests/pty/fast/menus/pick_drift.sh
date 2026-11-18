#!/usr/bin/env bash
# ONE pick screen: every picker (transfer local + GCloud, csv file picker) draws its header and rows through _pick_header / _pick_rows
# (browse.sh), and those rows are byte for byte the rows of the folder view (display_items).   bash tests/pty/fast/menus/pick_drift.sh
#  1. a picker file has no hand-written numbered row (printf "%2d) ...") - a copy of the list is how the screens drifted apart
#  2. each picker file calls _pick_header and _pick_rows
#  3. _pick_rows == display_items for the same paths (icons, 🔒, name)      4. -r (remote) rows carry no lock mark
#  5. the Find & replace results are NOT drawn by Find: _fr_results_fill hands paths + the engine's extra text to _results_view (the "==" display), and no
#     hand-made list (_fr_show, _pick_header + printed rows) is left in the Find files
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"; fail=0
source "$ROOT/tests/pty/lib/wait_lib.sh"
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
for n in bashbasicsbyvk_transfer.sh bashbasicsbyvk_csv.sh; do
  f="$(bvk_need "$n")"
  if grep -nE 'printf[^|]*"[ ]*%[0-9]*d\)' "$f" >/dev/null; then bad "$n draws its own numbered rows"; grep -nE 'printf[^|]*"[ ]*%[0-9]*d\)' "$f" | head -3; else ok "$n has no hand-written rows"; fi
  grep -q '_pick_header' "$f" && grep -q '_pick_rows' "$f" && ok "$n uses the shared pick screen" || bad "$n does not call _pick_header / _pick_rows"
done
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/d/sub"; touch "$T/d/a.zip" "$T/d/b.txt" "$T/d/run.sh"; chmod +x "$T/d/run.sh"
DSP="$(bvk_need bashbasicsbyvk_displayer.sh)"; BRW="$(bvk_need bashbasicsbyvk_browse.sh)"
out="$(D="$T/d" DSP="$DSP" BRW="$BRW" bash -c '
  declare -gA item_icon=() _LK_SET=() _FAV_LABEL=() _REC_LABEL=(); declare -ga items=()
  source "$DSP" >/dev/null 2>&1
  eval "$(awk "/^_desc_print_dim\\(\\) \\{/{f=1} f{print} /^_menu_header_flat\\(\\) \\{/{exit}" "$BRW" | sed "\$d")"
  _pick_rows "$D/sub" "$D/a.zip" "$D/b.txt" "$D/run.sh" > "$D/../r1"
  items=("$D/sub" "$D/a.zip" "$D/b.txt" "$D/run.sh"); display_items > "$D/../r2"
  _LK_SET["$D/a.zip"]=1; _lk_suffix_v() { _lk_suffix=" 🔒"; }
  item_icon[$D/a.zip]=file; _pick_rows -r "$D/a.zip" > "$D/../r3"
' 2>&1)"
[ -s "$T/r1" ] && cmp -s "$T/r1" "$T/r2" && ok "_pick_rows == display_items" || { bad "_pick_rows differs from display_items"; echo "$out" | head -5; diff "$T/r1" "$T/r2" | head -6; }
grep -q '📦 a.zip' "$T/r1" && grep -q '⚙️ run.sh' "$T/r1" && ok "archive and executable icons" || bad "icons"
grep -q '🔒' "$T/r3" && bad "remote row wears a local lock mark" || ok "remote rows have no lock mark"
# 5. Find results: Find only supplies DATA (paths + engine extras); the screen is _results_view, the "==" display
FF="$(bvk_need bashbasicsbyvk_find.sh)"; FR="$(bvk_need bashbasicsbyvk_findrun.sh)"; TW="$(bvk_file bashbasicsbyvk_findrep)"
grep -q '_results_view' "$FF" && ! grep -q '_fr_show\|_pick_header' "$FF" "$FR" && ok "Find shows its hits through _results_view (no list of its own)" || bad "Find still draws its own results"
if command -v python3 >/dev/null 2>&1 && [ -n "$TW" ]; then
  mkdir -p "$T/r/sales"; echo "hello 2026" > "$T/r/sales/IMG-2026-1.jpg"; echo ok > "$T/r/note2026.txt"
  for sc in names both; do
    R="$T/r" FR="$FR" SC="$sc" PATH="$(dirname "$TW"):$PATH" bash -c '
      declare -gA _RES_NOTE=(); declare -ga _RES_LIST=(); declare -g _RES_ROOT="" _RES_HDR=""
      source "$FR"
      _bvk_engine_target() { _bet_m=""; _bet_os=""; }
      path=$R; _fr_root=$R; _fr_scope=$SC
      _fo_depth=rec _fo_case=exact _fo_regex=0 _fo_word=0 _fo_hidden=0 _fo_vcs=0 _fo_target=both _fo_binary=0 _fo_maxsize=0 _fo_threads=0 _fo_limit=0
      _fr_finds=(2026); _fr_reps=(X); _fr_exec find && _fr_results_fill "HDR" || exit 1
      for p in "${_RES_LIST[@]}"; do echo "ROW ${p#$R/}"; done
      for k in "${!_RES_NOTE[@]}"; do echo "NOTE ${k#$R/}=${_RES_NOTE[$k]}"; done
      echo "HDR=$_RES_HDR"' > "$T/f_$sc" 2>&1
  done
  grep -q '^ROW sales/IMG-2026-1.jpg' "$T/f_names" && grep -q '^ROW note2026.txt' "$T/f_names" && grep -q '^HDR=HDR' "$T/f_names" && ok "find hands every hit to the results screen" || { bad "find results are not handed over"; head -5 "$T/f_names"; }
  grep -q 'NOTE sales/IMG-2026-1.jpg=(1 match)' "$T/f_both" && grep -q 'L1: hello 2026' "$T/f_both" && ok "engine extras (matches, snippets) travel as notes" || { bad "engine extras lost"; head -8 "$T/f_both"; }
else ok "find rows: skipped (no python3 / twin)"; fi
[ "$fail" = 0 ] && echo "PASS" || echo "FAILED"; exit "$fail"
