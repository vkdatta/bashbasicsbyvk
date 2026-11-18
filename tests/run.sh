#!/usr/bin/env bash
# tests/run.sh — THE runner.  Default = the STATIC suites (tests/static/suites.list): no terminal, no sleeps, hard-capped, ~1 s warm.
#   bash tests/run.sh                       the static suites (what you run once after a change)
#   bash tests/run.sh baseline              OWNER ONLY: accept today's findings as known drift (rewrites tests/static/baseline/*.txt)
#   bash tests/run.sh pty fast [name..]     pty / old shell tests in tests/pty/fast  (deep trace, screenshots: see AGENTS.md decision matrix)
#   bash tests/run.sh pty slow [name..]     the slow ones in tests/pty/slow (release time, or a bug no static test can show)
#   bash tests/run.sh pty list              what is in tests/pty/pty.list
#   bash tests/run.sh list                  the static suites
# Output is capped at 40 lines: one line per NEW finding, then one RESULT line.   env: JOBS=<n> (default: CPUs, min 2)   KEEP=1 keeps the logs
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 2
CPUS="$(nproc 2>/dev/null || echo 2)"; JOBS="${JOBS:-$(( CPUS < 2 ? 2 : CPUS ))}"; MAXLINES=40
OUT="$(mktemp -d "${TMPDIR:-/tmp}/bvk_run.XXXXXX")"; [ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$OUT"' EXIT
now() { date +%s.%N; }; T0="$(now)"; secs() { awk -v a="$T0" -v b="$(now)" 'BEGIN{printf "%.1f", b-a}'; }
mode="${1:-default}"; [ $# -gt 0 ] && shift
rows_of() { grep -vE '^[[:space:]]*(#|$)' "tests/$1" 2>/dev/null; }      # suites.list lives in tests/static/, the pty list in tests/pty/
need_missing() { case "$1" in node|python3) command -v "$1" >/dev/null 2>&1 || echo "$1 not installed" ;; fileapi) [ -d "$ROOT/../fileapi/test" ] || echo "../fileapi repo not found" ;; esac; }
PTYTIER=""
case "$mode" in
  list) echo "== static/suites.list"; rows_of static/suites.list | cut -d'|' -f1 ; exit 0 ;;
  baseline) for f in tests/static/t_*.py; do python3 -I "$f" --write-baseline; done; exit 0 ;;
  default) LIST=static/suites.list; CAP=25; FMT=2 ;;
  pty) PTYTIER="${1:-}"; [ $# -gt 0 ] && shift
       case "$PTYTIER" in
         list) echo "== pty/pty.list  (name folder timeout)"; rows_of pty/pty.list | cut -d'|' -f1,2,3 | awk -F'|' '{printf "  %-24s %-5s %s\n",$1,$2,$3}'; exit 0 ;;
         fast) CAP=240 ;; slow) CAP=600 ;;
         *) echo "usage: bash tests/run.sh pty fast|slow|list [name..]"; exit 2 ;;
       esac; LIST=pty/pty.list; FMT=5 ;;
  *) echo "unknown mode $mode (default | baseline | pty fast|slow|list | list)"; exit 2 ;;
esac
declare -a NAMES CMDS CAPS; declare -A WANT; for n in "$@"; do WANT[$n]=1; done
while IFS= read -r r; do
  n="${r%%|*}"; if [ -n "$PTYTIER" ]; then f="${r#*|}"; f="${f%%|*}"; [ "$f" = "$PTYTIER" ] || continue; fi; [ $# -gt 0 ] && [ -z "${WANT[$n]:-}" ] && continue
  if [ $FMT = 2 ]; then c="${r#*|}"; to=$CAP; nd=""; else IFS='|' read -r _ _ to c nd _ <<<"$r"; [ "${to:-0}" -gt "$CAP" ] && to=$CAP; fi
  NAMES+=("$n"); CMDS+=("$c"); CAPS+=("$to"); echo "$nd" >"$OUT/$n.need"
done < <(rows_of "$LIST")
[ ${#NAMES[@]} -gt 0 ] || { echo "nothing selected"; exit 2; }
run_one() { local i="$1" n="${NAMES[$1]}" miss; miss="$(need_missing "$(<"$OUT/$n.need")")"
  [ -n "$miss" ] && { echo "SKIP $miss" >"$OUT/$n.log"; echo SKIP >"$OUT/$n.rc"; return; }
  TEST_TIME_FACTOR=1 TMPDIR="${TMPDIR_FOR_TEST:-$TMPDIR}" timeout -k 2 "${CAPS[$i]}" bash -c "${CMDS[$i]}" >"$OUT/$n.log" 2>&1; local rc=$?
  if [ $rc = 0 ]; then echo PASS >"$OUT/$n.rc"; elif [ $rc = 124 ] || [ $rc = 137 ]; then echo "TIMEOUT after ${CAPS[$i]}s" >>"$OUT/$n.log"; echo TIMEOUT >"$OUT/$n.rc"; else echo FAIL >"$OUT/$n.rc"; fi; }
[ $mode = default ] || export TMPDIR_FOR_TEST="$OUT"      # the old tests keep per-run temp dirs; the static suites keep their cache in the normal temp dir
running=0
for i in "${!NAMES[@]}"; do run_one "$i" & running=$((running+1)); [ "$running" -ge "$JOBS" ] && { wait -n; running=$((running-1)); }; done; wait
declare -A KNOWN; while IFS=$'\t' read -r n why; do [ -n "$n" ] && KNOWN[$n]="$why"; done < <(grep -vE '^[[:space:]]*(#|$)' tests/pty/known_failing.txt 2>/dev/null)
bad=0; pass=0; skip=0; { for n in "${NAMES[@]}"; do st="$(<"$OUT/$n.rc")"
  case "$st" in
    PASS) pass=$((pass+1)); [ $mode = default ] && grep -a '^[a-z]*: ' "$OUT/$n.log" | head -1 | sed 's/^/  /' ;;
    SKIP) skip=$((skip+1)); echo "  SKIP  $n: $(<"$OUT/$n.log")" ;;
    *) if [ -n "${KNOWN[$n]:-}" ]; then echo "  KNOWN $n (known_failing.txt)"; else bad=$((bad+1)); echo "  $st  $n"
         grep -a 'NEW\|FAIL\|TIMEOUT' "$OUT/$n.log" | cut -c1-190 | head -12 | sed 's/^/      /'
         [ $mode = default ] && grep -a '^[a-z]*: ' "$OUT/$n.log" | head -1 | sed 's/^/      /'; fi ;;
  esac; done; } > "$OUT/report.txt"
total=$(wc -l <"$OUT/report.txt"); head -n $MAXLINES "$OUT/report.txt"; [ "$total" -gt $MAXLINES ] && echo "  ... $((total-MAXLINES)) more lines (KEEP=1 keeps the logs)"
echo "  RESULT: $([ $bad = 0 ] && echo OK || echo "$bad FAILED")   ($pass passed, $skip skipped, ${#NAMES[@]} total, $(secs)s)"; [ "${KEEP:-0}" = 1 ] && echo "  logs: $OUT"
[ $bad = 0 ]
