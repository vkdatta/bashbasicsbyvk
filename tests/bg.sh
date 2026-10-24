#!/usr/bin/env bash
# Run a long command in the background and wait for it WITHOUT guessing a sleep.   (agents: never `sleep 600`; use this)
#   bash tests/bg.sh start <name> <command...>   start it detached; log in /tmp/bvk_bg/<name>.log
#   bash tests/bg.sh wait  <name> [max-secs]      returns THE MOMENT it ends (polls every 0.2 s), printing new log lines as they appear.
#                                                 max-secs default 25: if it is still running it says so and exits 124 - call `wait` again.
#   bash tests/bg.sh status <name> | tail <name> [n] | kill <name> | list
# Exit code of `wait` = the command's own exit code.
D=/tmp/bvk_bg; mkdir -p "$D"; cmd="${1:-}"; n="${2:-}"; shift 2 2>/dev/null
isrun() { [ -f "$D/$n.pid" ] && kill -0 "$(<"$D/$n.pid")" 2>/dev/null; }
case "$cmd" in
  start) [ -n "$n" ] && [ $# -gt 0 ] || { echo "usage: bg.sh start <name> <command...>"; exit 2; }
         isrun && { echo "$n is already running"; exit 1; }; rm -f "$D/$n.rc" "$D/$n.log" "$D/$n.off"
         setsid nohup bash -c 'echo $$ >"$1"; cd "$2"; shift 2; "$@"; echo $? >"$0"' "$D/$n.rc" "$D/$n.pid" "$PWD" "$@" >"$D/$n.log" 2>&1 </dev/null &
         for _ in $(seq 1 50); do [ -s "$D/$n.pid" ] && break; sleep 0.02; done; echo "started $n (pid $(cat "$D/$n.pid")), log $D/$n.log" ;;
  wait)  max="${1:-25}"; shown=$(cat "$D/$n.off" 2>/dev/null || echo 0); t0=$SECONDS      # only NEW log lines are printed on each call
         while :; do
           size=$(stat -c %s "$D/$n.log" 2>/dev/null || echo 0)
           [ "$size" -gt "$shown" ] && { tail -c +$((shown+1)) "$D/$n.log"; shown=$size; echo "$shown" >"$D/$n.off"; }
           [ -f "$D/$n.rc" ] && { rc=$(<"$D/$n.rc"); echo "[$n finished, exit $rc, after $((SECONDS-t0))s of waiting]"; exit "$rc"; }
           isrun || { [ -f "$D/$n.rc" ] || { echo "[$n is not running and left no exit code]"; exit 3; }; }
           [ $((SECONDS-t0)) -ge "$max" ] && { echo "[$n still running after ${max}s - call: bash tests/bg.sh wait $n]"; exit 124; }
           sleep 0.2
         done ;;
  status) if [ -f "$D/$n.rc" ]; then echo "$n finished, exit $(<"$D/$n.rc")"; elif isrun; then echo "$n running"; else echo "$n unknown/dead"; fi ;;
  tail)  tail -n "${1:-30}" "$D/$n.log" ;;
  kill)  if isrun; then p=$(<"$D/$n.pid"); kill -TERM -- -"$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; echo 143 >"$D/$n.rc"; fi; echo "killed $n" ;;
  list)  ls "$D" 2>/dev/null | sed -n 's/\.pid$//p' | while read -r x; do n=$x; printf '%-20s ' "$x"; "$0" status "$x"; done ;;
  *) sed -n '2,10p' "$0"; exit 2 ;;
esac
