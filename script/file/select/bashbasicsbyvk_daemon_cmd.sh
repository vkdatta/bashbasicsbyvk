#!/usr/bin/env bash
# bashbasicsbyvk_daemon_cmd.sh — the  .dm  commands (both background daemons)
# ════════════════════════════════════════════════════════════════════════════
#  LOCAL daemon (bashbasicsbyvk_local_daemon): keeps bookmarks, recents, favourites, locks and shortcuts attached to their paths,
#                and the hash / folder-size index warm.
#  ALIEN daemon (bashbasicsbyvk_alien_daemon.sh): takes snapshots while o runs.
#
#  .dm                  status of the local daemon (and one line for the alien daemon)
#  .dm.warm             warm the index now                  (SIGUSR1)
#  .dm.sync             reconcile favourites, bookmarks, recents, locks and shortcuts now (SIGUSR2) — also finds
#                       items that moved while the daemon was off
#  .dm.roots            edit the folders to keep warm  (~/.bashbasicsbyvk/index_roots.conf)
#  .dm.restart          restart the local daemon
#  .dm.alien            status of the alien daemon
#  .dm.alien.restart    restart the alien daemon
#
#  Files: ~/.bashbasicsbyvk/daemons/local.{pid,log,status,version}   ·   ~/.config/bashbasicsbyvk/snapshots/alien.{lock,log}
#  Both daemons are built on planetary resources (bashbasicsbyvk_planetary_resources.sh / .py).
# ════════════════════════════════════════════════════════════════════════════

_DM_DIR="${HOME}/.bashbasicsbyvk/daemons"
_DM_STATUS="${_DM_DIR}/local.status"
_DM_ROOTS="${HOME}/.bashbasicsbyvk/index_roots.conf"

_dm_pid() {          # the local daemon's pid, only when it is alive AND really the daemon (a recycled pid does not count)
  local p="" c
  [ -r "$_DM_DIR/local.pid" ] && read -r p < "$_DM_DIR/local.pid"
  [[ "$p" =~ ^[0-9]+$ ]] && kill -0 "$p" 2>/dev/null || return 1
  if [ -r "/proc/$p/cmdline" ]; then c=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null); case "$c" in *bashbasicsbyvk_local_daemon*) ;; *) return 1 ;; esac; fi
  printf '%s' "$p"
}

_dm_status() {
  local pid; pid=$(_dm_pid)
  if [ -z "$pid" ]; then
    echo "🔴  Local daemon is not running — it starts with the app (.dm.restart to start it now)"
    _dm_alien_line
    return
  fi
  if [ ! -f "$_DM_STATUS" ]; then echo "🛰️  Local daemon running (pid $pid) — no status yet, give it a few seconds"; _dm_alien_line; return; fi
  python3 - "$_DM_STATUS" "$HOME" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1])); home = sys.argv[2]
def ago(t):
    if not t: return "never"
    s = int(time.time() - t)
    return "%ds ago" % s if s < 90 else ("%dm ago" % (s // 60) if s < 5400 else "%dh ago" % (s // 3600))
def up(t):
    s = int(time.time() - t) if t else 0
    return "%dd%dh" % (s // 86400, s % 86400 // 3600) if s >= 86400 else ("%dh%dm" % (s // 3600, s % 3600 // 60) if s >= 3600 else "%dm" % (s // 60))
ix = d.get("index") or {}
print("🛰️  Local daemon v%s  pid %s  watcher: %s  up %s" % (d.get("version"), d.get("pid"), d.get("backend"), up(d.get("started"))))
fo = d.get("followed") or {}
print("   🕐 recents: %s   📌 bookmarks followed: %s (found by inode: %s)   🔒 locks followed: %s   last sync: %s" % (d.get("recents", 0), fo.get("bookmarks", 0), d.get("bookmarks_located", 0), fo.get("locks", 0), ago(d.get("last_track_reconcile"))))
if d.get("event_batches"):
    print("   ⚡ %s event(s) in %s batch(es)%s" % (d.get("events_seen", 0), d.get("event_batches", 0), ("  — %s dropped (queue full)" % d["events_dropped"]) if d.get("events_dropped") else ""))
print("   ⭐ favourite folders: %s   moves followed: %s   last sync: %s" % (d.get("fav_folders", 0), d.get("fav_followed", 0), ago(d.get("last_fav_reconcile"))))
if ix:
    print("   🗃️  index: %s hashes · %s folder sizes" % (format(ix.get("hashes", 0), ","), format(ix.get("dirsizes", 0), ",")))
else:
    print("   🗃️  index: off")
lw = d.get("last_warm") or []
print("   🔥 last warm: %s  (%d folder(s))" % (ago(d.get("last_warm_at")), len(lw)))
for w in lw[-4:]:
    print("      %s  %s files  %ss" % (w["root"].replace(home, "~"), format(w["files"], ","), w["seconds"]))
if d.get("backend") == "polling":
    print("   🔴  no inotify: moves are found by the periodic sync (every minute); folder-size cache is off")
print("   .dm.warm · .dm.sync · .dm.roots · .dm.restart · .dm.alien")
PY
  _dm_alien_line
}

_dm_alien_line() {   # one line about the alien daemon under the local one
  if _snap_daemon_alive 2>/dev/null; then echo "   📸 alien daemon (snapshots): running — .dm.alien"
  else echo "   📸 alien daemon (snapshots): not running — .dm.alien"; fi
}

_dm_restart_local() {
  local pid i; pid=$(_dm_pid) || true
  if [ -n "$pid" ]; then
    kill -TERM "$pid" 2>/dev/null
    for i in $(seq 1 100); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done      # it leaves within a second or two
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  fi
  rm -f "$_DM_DIR/local.pid" 2>/dev/null
  _pr_wake_local_daemon
  for i in $(seq 1 50); do [ -s "$_DM_DIR/local.pid" ] && break; sleep 0.1; done        # the new one writes its pid when it is up
}

handle_daemon_cmd() {
  local cmd="${1%% *}" pid
  case "$cmd" in
    .dm) _dm_status ;;
    .dm.warm|.dm.sync)
      pid=$(_dm_pid) || true
      [ -z "$pid" ] && { echo "🔴  Local daemon is not running"; return; }
      if [ "$cmd" = ".dm.warm" ]; then kill -USR1 "$pid" 2>/dev/null; echo "🔥 Warming started in the background (.dm to see progress)"
      else kill -USR2 "$pid" 2>/dev/null; echo "⭐ Sync of favourites, bookmarks, recents, locks and shortcuts started in the background"; fi ;;
    .dm.roots)
      [ -f "$_DM_ROOTS" ] || { echo "📜  The daemon creates $_DM_ROOTS on first start — start it with .dm.restart"; return; }
      _rule_editor "$_DM_ROOTS"
      echo "💫 Saved — picked up at the next warm cycle (or .dm.warm)" ;;
    .dm.restart)
      _dm_restart_local
      echo "🔄 Local daemon restarted"; _dm_status ;;
    .dm.alien) _snap_daemon_status ;;
    .dm.alien.restart)
      _snap_daemon_stop
      _snap_daemon_start
      echo "🔄 Alien daemon restarted (it starts only while a path is on the snapshot list and snapshots are not paused)"
      _snap_daemon_status ;;
    *) echo "🔴  Daemon commands: .dm  .dm.warm  .dm.sync  .dm.roots  .dm.restart  .dm.alien  .dm.alien.restart" ;;
  esac
}
