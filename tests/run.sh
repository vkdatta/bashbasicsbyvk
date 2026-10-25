#!/usr/bin/env bash
# THE way to run tests.  Seconds, not half an hour: independent tests run in parallel, every one has a hard timeout, failures print the moment they happen.
#   bash tests/run.sh fast                 the quick tier (what you run after most changes)
#   bash tests/run.sh for [files...]       only the tests that cover those files (tests/covers.map); no files = `git diff --name-only`
#   bash tests/run.sh all                  everything (before release / when asked for the full suite)
#   bash tests/run.sh <name> [name...]     named tests (see `list`)         bash tests/run.sh list
# env: JOBS=<n> parallel jobs (default: one per CPU, at least 2; longest tests start first; a test marked `serial` in tests.list field 6 runs alone afterwards)  TEST_TIME_FACTOR=<n> stretch every wait (default: jobs / cpus)   KEEP=1 keep the logs   Exit 0 = nothing unexpected failed.  SKIP is never a pass: it is listed at the end.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT" || exit 2
source tests/wait_lib.sh
CPUS="$(nproc 2>/dev/null || echo 1)"; JOBS="${JOBS:-$(( CPUS < 2 ? 2 : CPUS ))}"    # max parallel: one job per CPU (never lower it; a test that needs order is marked `serial` in tests.list field 6)
# more jobs than cores = every app is slower: stretch all waits by that ratio (a timeout costs nothing when the app answers, and it keeps load from causing false failures)
export TEST_TIME_FACTOR="${TEST_TIME_FACTOR:-$(( (JOBS + CPUS - 1) / CPUS ))}"
OUT="$(mktemp -d /tmp/bvk_run.XXXXXX)"; [ "${KEEP:-0}" = 1 ] || trap 'rm -rf "$OUT"' EXIT
mapfile -t ROWS < <(grep -vE '^[[:space:]]*(#|$)' tests/tests.list)
declare -A KNOWN; while IFS=$'\t' read -r n why; do [ -n "$n" ] && KNOWN[$n]="$why"; done < <(grep -vE '^[[:space:]]*(#|$)' tests/known_failing.txt)
field() { cut -d'|' -f"$2" <<<"$1"; }
names_of() { local r; for r in "${ROWS[@]}"; do [ -z "$1" ] || [ "$(field "$r" 2)" = "$1" ] && field "$r" 1; done; }
mode="${1:-fast}"; [ $# -gt 0 ] && shift
case "$mode" in
  list) for r in "${ROWS[@]}"; do printf '%-18s %-5s %4ss  %s\n' "$(field "$r" 1)" "$(field "$r" 2)" "$(field "$r" 3)" "$(field "$r" 4)"; done; exit 0 ;;
  fast) SEL=($(names_of fast)) ;;
  all)  SEL=($(names_of "")) ;;
  for)  files=("$@"); [ ${#files[@]} -eq 0 ] && mapfile -t files < <(git diff --name-only HEAD 2>/dev/null)
        [ ${#files[@]} -eq 0 ] && { echo "no changed files given or found - running the fast tier"; SEL=($(names_of fast)); }
        declare -A pick; pick[lint_waits]=1
        for f in "${files[@]}"; do hit=0
          while IFS=$'\t' read -r re ts; do [[ "$f" =~ $re ]] && { hit=1; for t in $ts; do pick[$t]=1; done; }; done < <(grep -vE '^[[:space:]]*(#|$)' tests/covers.map)
          [ $hit = 0 ] && for t in $(names_of fast); do pick[$t]=1; done
        done
        SEL=(); for n in $(names_of ""); do [ -n "${pick[$n]:-}" ] && SEL+=("$n"); done ;;
  *)    SEL=("$mode" "$@") ;;
esac
[ ${#SEL[@]} -gt 0 ] || { echo "nothing selected"; exit 2; }
row_of() { local r; for r in "${ROWS[@]}"; do [ "$(field "$r" 1)" = "$1" ] && { printf '%s' "$r"; return; }; done; }
need_missing() { case "$1" in node|python3) command -v "$1" >/dev/null 2>&1 || echo "$1 not installed" ;; fileapi) [ -d "$ROOT/../fileapi/test" ] || echo "../fileapi repo not found (set FILEAPI=...)" ;; esac; }
run_one() {   # runs in a background job: writes $OUT/<n>.rc (PASS/FAIL/SKIP/TIMEOUT), .secs, .log
  local n="$1" r cmd to need why t0; r="$(row_of "$n")"
  [ -n "$r" ] || { echo "no such test: $n" >"$OUT/$n.log"; echo FAIL >"$OUT/$n.rc"; echo 0 >"$OUT/$n.secs"; return; }
  to="$(field "$r" 3)"; cmd="$(field "$r" 4)"; need="$(field "$r" 5)"
  why="$(need_missing "$need")"; [ -n "$need" ] && [ -n "$why" ] && { echo "$why" >"$OUT/$n.log"; echo SKIP >"$OUT/$n.rc"; echo 0 >"$OUT/$n.secs"; return; }
  mkdir -p "$OUT/tmp.$n"; t0="$(_wl_now)"
  TMPDIR="$OUT/tmp.$n" timeout -k 5 "$to" bash -c "$cmd" >"$OUT/$n.log" 2>&1; local rc=$?
  bvk_reap "$OUT/tmp.$n"; rm -rf "$OUT/tmp.$n"          # every temp dir of this test lives under its own TMPDIR: whatever the app left running from there (daemons, watchers) is stopped
  echo "$(( ($(_wl_now) - t0) / 10000 ))" >"$OUT/$n.secs"
  if [ $rc = 0 ]; then echo PASS >"$OUT/$n.rc"; elif [ $rc = 124 ] || [ $rc = 137 ]; then echo "TIMEOUT after ${to}s" >>"$OUT/$n.log"; echo TIMEOUT >"$OUT/$n.rc"; else echo FAIL >"$OUT/$n.rc"; fi
}
report() {   # print one finished test the moment it ends
  local n="$1" st secs; st="$(<"$OUT/$n.rc")"; secs="$(<"$OUT/$n.secs")"; secs="$((secs/100)).$(printf '%02d' $((secs%100)))"
  case "$st" in
    PASS) if [ -n "${KNOWN[$n]:-}" ]; then printf '  PASS    %-18s %6ss   (listed in known_failing.txt - it passes now: remove the line)\n' "$n" "$secs"; else printf '  PASS    %-18s %6ss\n' "$n" "$secs"; fi ;;
    SKIP) printf '  SKIP    %-18s          %s\n' "$n" "$(<"$OUT/$n.log")" ;;
    *) if [ -n "${KNOWN[$n]:-}" ]; then printf '  KNOWN   %-18s %6ss   already failing: %s\n' "$n" "$secs" "${KNOWN[$n]}"
       else printf '  %-7s %-18s %6ss   <- what failed (FAIL lines first, then the last lines of its output):\n' "$st" "$n" "$secs"
            { grep -a 'FAIL\|TIMEOUT' "$OUT/$n.log" | cut -c1-200 | head -12; echo '  ...'; grep -avE '^[[:space:]]*(ok|PASS)[[:space:]]' "$OUT/$n.log" | tail -14; } | sed 's/^/          | /'; fi ;;
  esac
}
PAR=(); SER=()   # longest first (the slowest tests start first, so they are not the tail of the run); `serial` tests (field 6) run alone, after the parallel ones
while read -r _ n; do [ -z "$n" ] && continue; [ "$(field "$(row_of "$n")" 6)" = serial ] && SER+=("$n") || PAR+=("$n"); done < <(for n in "${SEL[@]}"; do t="$(field "$(row_of "$n")" 3)"; echo "${t:-0} $n"; done | sort -rn)
t_start; declare -A PID REPORTED; running=0
for n in "${PAR[@]}"; do
  run_one "$n" & PID[$n]=$!; running=$((running+1))
  while [ "$running" -ge "$JOBS" ]; do
    wait -n; running=$((running-1))
    for m in "${!PID[@]}"; do [ -s "$OUT/$m.rc" ] && [ -z "${REPORTED[$m]:-}" ] && { REPORTED[$m]=1; report "$m"; }; done
  done
done
while [ "$running" -gt 0 ]; do
  wait -n; running=$((running-1))
  for m in "${!PID[@]}"; do [ -s "$OUT/$m.rc" ] && [ -z "${REPORTED[$m]:-}" ] && { REPORTED[$m]=1; report "$m"; }; done
done
for n in "${SER[@]}"; do run_one "$n"; PID[$n]=0; REPORTED[$n]=1; report "$n"; done
for m in "${!PID[@]}"; do [ -z "${REPORTED[$m]:-}" ] && report "$m"; done
bad=0; npass=0; ndone=0; skipped=(); for n in "${SEL[@]}"; do st="$(<"$OUT/$n.rc")"
  case "$st" in PASS) npass=$((npass+1)); ndone=$((ndone+1)) ;; SKIP) skipped+=("$n") ;; *) ndone=$((ndone+1)); [ -z "${KNOWN[$n]:-}" ] && bad=$((bad+1)) ;; esac; done
echo "  ----"; echo "  ${#SEL[@]} test(s) in $(t_since)s wall time (JOBS=$JOBS, waits x$TEST_TIME_FACTOR)"
echo "  STATUS: $npass/$ndone/${#SEL[@]}  (passed/completed/total; a skip is not completed)  <- copy this into the delivery line: <task name> (tests: $npass/$ndone/${#SEL[@]})"
[ ${#skipped[@]} -gt 0 ] && echo "  NOT RUN (skipped, so NOT verified): ${skipped[*]}"
if [ $bad = 0 ]; then echo "  RESULT: OK${skipped:+ - but ${#skipped[@]} skipped}"; exit 0; else echo "  RESULT: $bad FAILED"; [ "${KEEP:-0}" = 1 ] && echo "  logs: $OUT"; exit 1; fi
