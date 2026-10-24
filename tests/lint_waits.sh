#!/usr/bin/env bash
# Tests must WAIT FOR A CONDITION, not for a guessed time.  bash tests/lint_waits.sh
# Rejects, in every test file: a fixed `sleep N` (N > 0.1), python time.sleep(N > 0.1), a blind `pump(N)` of 0.5 s or more, and `sleep` in a
# `for/while ... break` poll loop of more than 0.25 s.  Use tests/wait_lib.sh (bash) or tests/paste_input/ptyapp.py (pty) instead.
# A wait that IS the behaviour under test (an app timer, a double-click window) is allowed with a reason on the same line:  # lint-wait-ok: <why>
# wait_lib.sh and ptyapp.py (which implement the waiting) are exempt.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT/tests" || exit 2
bad=0
while IFS= read -r f; do
  case "$f" in ./wait_lib.sh|./paste_input/ptyapp.py|./lint_waits.sh|./run.sh|./bg.sh|./polyglot/*|./stresstest/*) continue ;; esac
  awk -v F="${f#./}" '
    /lint-wait-ok:/ { next }
    { line=$0 }
    match(line, /(^|[^A-Za-z_.])sleep[ \t]+[0-9]+(\.[0-9]+)?/) { s=substr(line,RSTART,RLENGTH); sub(/.*sleep[ \t]+/,"",s); if (s+0 > 0.1) { printf "  FAIL %s:%d: fixed sleep %s  ->  wait_until / wait_file / tmx_wait / a.wait(...)\n    %s\n", F, NR, s, line; bad=1 } }
    match(line, /time\.sleep\([ ]*[0-9.]+/)  { s=substr(line,RSTART,RLENGTH); sub(/.*\(/,"",s); if (s+0 > 0.1) { printf "  FAIL %s:%d: time.sleep(%s)  ->  a.wait(...) / settle\n    %s\n", F, NR, s, line; bad=1 } }
    match(line, /\.pump\([ ]*[0-9.]+/)       { s=substr(line,RSTART,RLENGTH); sub(/.*\(/,"",s); if (s+0 >= 0.5) { printf "  FAIL %s:%d: blind pump(%s)  ->  a.wait(cond) or a.settle()\n    %s\n", F, NR, s, line; bad=1 } }
    match(line, /(^|[^A-Za-z_])pump\([ ]*[0-9.]+/) { if (line !~ /def pump/) { s=substr(line,RSTART,RLENGTH); sub(/.*\(/,"",s); if (s+0 >= 0.5 && line !~ /lambda|stop=/ ) { printf "  FAIL %s:%d: blind pump(%s)  ->  wait for the condition (pump(t, stop))\n    %s\n", F, NR, s, line; bad=1 } } }
    END { exit bad }' "$f" || bad=1
done < <(find . -type f \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' \) | sort)
[ $bad = 0 ] && echo "  ok   no fixed sleeps / blind pumps in the tests" || { echo "FAILED: see tests/wait_lib.sh and AGENTS.md > Tests"; exit 1; }
