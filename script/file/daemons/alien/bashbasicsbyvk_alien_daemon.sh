#!/usr/bin/env bash
# bashbasicsbyvk_alien_daemon.sh - the ALIEN daemon: snapshots that leave this computer.
# ════════════════════════════════════════════════════════════════════════════
#  While  o  runs, one background process takes a snapshot of every watched path whose contents changed, every <interval>
#  (Settings → File API → Snapshots). It dies with  o  (it watches o's pid). Its sibling, the local daemon, keeps pointers at
#  paths attached on THIS computer. Both consume planetary resources (bashbasicsbyvk_planetary_resources.sh / .py).
#
#  What it does per pass (_snap_cycle, in bashbasicsbyvk_staging_snapshot.sh): finish snapshots an earlier run left half-sent,
#  sync the watched-path list with the server, copy + encrypt + upload what changed.
#
#  The snapshot menu, the list of watched paths and the server calls stay in bashbasicsbyvk_staging_snapshot.sh; this file is
#  only the process: start it once, keep it alive, stop it with o, tell its status (.dm.alien).
#
#  Files: $_SNAP_DIR/alien.lock/pid (pid + start time of the daemon) · alien.log (trimmed) · last_cycle · notice
# ════════════════════════════════════════════════════════════════════════════

_snap_interval() {
  local v; v=$(_bb_cfg_val snapshot_interval_seconds 3600)
  if [[ "$v" =~ ^[0-9]{1,9}$ ]] && [ "$v" -ge "$_SNAP_MIN_INTERVAL" ] && [ "$v" -le "$_SNAP_MAX_INTERVAL" ]; then printf '%s' "$v"; else printf '3600'; fi
}
_snap_daemon_alive() { _pr_svc_alive "$_SNAP_LOCK"; }       # alive AND still the process that was started (a recycled pid does not count)
_snap_daemon_pid() { local p=""; read -r p < "$_SNAP_LOCK/pid" 2>/dev/null; [[ "$p" =~ ^[0-9]+$ ]] && printf '%s' "$p"; }

_snap_daemon_main() {       # runs in the background; $1 = pid of the  o  process it lives and dies with
  local oppid="$1" me="$BASHPID" now due last wait
  # settings are re-read from the config file every pass (a stale copy of the shell variables would hide changes)
  unset snapshot_enabled snapshot_interval_seconds snapshot_keep_seconds credit_prompts
  _SNAP_WORK=""
  _snap_cleanup() { [ -n "$_SNAP_WORK" ] && rm -rf "$_SNAP_WORK"; _pr_svc_release "$_SNAP_LOCK" "$me"; }     # only OUR lock
  trap 'trap "" TERM INT HUP; _pr_kill_desc "$me"; _snap_cleanup; exit 0' TERM INT HUP
  trap '_snap_cleanup' EXIT
  _pr_svc_pid_write "$_SNAP_LOCK" "$me"
  # stop the moment  o  is gone — even in the middle of an upload ("snapshots only happen while o is running")
  _pr_die_with "$oppid" "$me"
  # leftovers of an earlier crash
  find "$_SNAP_TMPROOT" -maxdepth 1 -name 'run.*' -mmin +1440 -exec rm -rf {} + 2>/dev/null
  _snap_log "background snapshots started (o pid $oppid, alien daemon v$(_pr_version alien))"
  while kill -0 "$oppid" 2>/dev/null; do
    if [ "$(_bb_cfg_val snapshot_enabled on)" = off ]; then sleep 20; continue; fi
    # this computer's id is created and signed by the server on the first start with internet; until then there is nothing to do
    if ! _snap_dev_hdrs; then sleep 15; continue; fi
    now=$(date +%s); last=$(cat "$_SNAP_LASTRUN" 2>/dev/null); [[ "$last" =~ ^[0-9]+$ ]] || last=0
    due=$(( last + $(_snap_interval) ))
    if [ "$now" -ge "$due" ]; then
      _snap_cycle
      date +%s > "$_SNAP_LASTRUN"
      _snap_log_trim
      sleep 5
    else
      wait=$(( due - now )); [ "$wait" -gt 5 ] && wait=5
      sleep "$wait"
    fi
  done
}

# start it (once per computer) when  o  starts, and again when the first path is added
_snap_daemon_start() {
  [ "$(_bb_cfg_val snapshot_enabled on)" = off ] && return 0
  [ -s "$_SNAP_TARGETS" ] || return 0
  command -v node >/dev/null 2>&1 || return 0
  mkdir -p "$_SNAP_DIR" 2>/dev/null; chmod 700 "$_SNAP_DIR" 2>/dev/null
  _pr_svc_claim "$_SNAP_LOCK" || return 0           # a live alien daemon already runs: one per computer
  local oppid=$$
  (
    declare -F _lt_off >/dev/null 2>&1 && _lt_off      # a daemon is never part of a loadtime report
    exec </dev/null >>"$_SNAP_LOG" 2>&1
    _snap_daemon_main "$oppid"
  ) &
  _pr_svc_pid_write "$_SNAP_LOCK" "$!"                # written by the starter too: the claim is never seen without a pid
  disown 2>/dev/null
  return 0
}

# stop it now (.dm.alien.restart); it is started again right after
_snap_daemon_stop() {
  local pid; pid=$(_snap_daemon_pid) || return 0
  _snap_daemon_alive && kill -TERM "$pid" 2>/dev/null
  local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  _pr_svc_release "$_SNAP_LOCK" "$pid"
  return 0
}

_snap_daemon_status() {     # .dm.alien : what the alien daemon is doing
  local pid last now iv n
  now=$(date +%s); iv=$(_snap_interval)
  if pid=$(_snap_daemon_pid) && _snap_daemon_alive; then
    echo "📸  Alien daemon v$(_pr_version alien)  pid $pid  — takes snapshots while o runs"
  else
    echo "🔴  Alien daemon is not running — it starts with the app once a path is on the snapshot list (snap-1), or with .dm.alien.restart"
  fi
  [ "$(_bb_cfg_val snapshot_enabled on)" = off ] && echo "   ⏸️  snapshots are PAUSED (Settings → File API → Snapshots)"
  n=$(_snap_target_count)
  last=$(cat "$_SNAP_LASTRUN" 2>/dev/null); [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if [ "$last" -gt 0 ]; then echo "   🕐 paths on the list: $n   last pass: $(( (now - last) / 60 )) min ago   every $(_bb_fmt_duration "$iv")   next in about $(( (last + iv - now) > 0 ? (last + iv - now) / 60 : 0 )) min"
  else echo "   🕐 paths on the list: $n   no pass yet   every $(_bb_fmt_duration "$iv")"; fi
  [ -s "$_SNAP_NOTICE" ] && sed 's/^/   /' "$_SNAP_NOTICE"
  if [ -s "$_SNAP_LOG" ]; then echo "   last log lines (alien.log):"; tail -n 3 "$_SNAP_LOG" | sed 's/^/      /'; fi
  echo "   .dm.alien · .dm.alien.restart"
}
