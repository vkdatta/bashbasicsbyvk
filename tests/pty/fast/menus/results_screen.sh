ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"; fail=0
python3 -I "$ROOT/tests/pty/fast/menus/results/pty_test.py" "$ROOT" || fail=1
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
