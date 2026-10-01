#!/usr/bin/env bash
# bashbasicsbyvk_daemon_cmd.sh — the  .dm  commands (background daemon)
# ════════════════════════════════════════════════════════════════════════════
#  .dm           status: version, watcher, recents, favourites, index, last warm
#  .dm.warm      warm the index now          (SIGUSR1)
#  .dm.sync      reconcile favourites now    (SIGUSR2) — also finds items that
#                moved while the daemon was off
#  .dm.roots     edit the folders to keep warm  (~/.bashbasicsbyvk/index_roots.conf)
#  .dm.restart   restart the daemon
#
#  The daemon (bashbasicsbyvk_recents_daemon) tracks recents AND
#    • keeps favourites attached through renames / moves,
#    • keeps a hash + folder-size index so .s.dup / .s.size are fast,
#  see  ~/.bashbasicsbyvk/daemon.status  and  recents.log.
# ════════════════════════════════════════════════════════════════════════════

_DM_STATUS="${HOME}/.bashbasicsbyvk/daemon.status"
_DM_ROOTS="${HOME}/.bashbasicsbyvk/index_roots.conf"

_dm_pid() {
  local p; p=$(cat "${HOME}/.bashbasicsbyvk/recents.pid" 2>/dev/null)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null && printf '%s' "$p"
}

_dm_status() {
  local pid; pid=$(_dm_pid)
  if [ -z "$pid" ]; then
    echo "⚠️  Daemon is not running — it starts with the app (.dm.restart to start it now)"
    return
  fi
  if [ ! -f "$_DM_STATUS" ]; then echo "🛰️  Daemon running (pid $pid) — no status yet, give it a few seconds"; return; fi
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
print("🛰️  Daemon v%s  pid %s  watcher: %s  up %s" % (d.get("version"), d.get("pid"), d.get("backend"), up(d.get("started"))))
print("   🕐 recents tracked: %s" % d.get("recents", 0))
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
    print("   ⚠️  polling mode: moves are found by the periodic sync only; folder-size cache is off")
print("   .dm.warm · .dm.sync · .dm.roots · .dm.restart")
PY
}

handle_daemon_cmd() {
  local cmd="${1%% *}" pid
  case "$cmd" in
    .dm) _dm_status ;;
    .dm.warm|.dm.sync)
      pid=$(_dm_pid) || true
      [ -z "$pid" ] && { echo "⚠️  Daemon is not running"; return; }
      if [ "$cmd" = ".dm.warm" ]; then kill -USR1 "$pid" 2>/dev/null; echo "🔥 Warming started in the background (.dm to see progress)"
      else kill -USR2 "$pid" 2>/dev/null; echo "⭐ Favourites sync started in the background"; fi ;;
    .dm.roots)
      [ -f "$_DM_ROOTS" ] || { echo "ℹ️  The daemon creates $_DM_ROOTS on first start — start it with .dm.restart"; return; }
      _rule_editor "$_DM_ROOTS"
      echo "✅ Saved — picked up at the next warm cycle (or .dm.warm)" ;;
    .dm.restart)
      pid=$(_dm_pid) || true
      [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null && sleep 1
      rm -f "${HOME}/.bashbasicsbyvk/recents.pid" 2>/dev/null
      _bvk_wake_recents_daemon
      sleep 1
      echo "🔄 Daemon restarted"; _dm_status ;;
    *) echo "⚠️  Daemon commands: .dm  .dm.warm  .dm.sync  .dm.roots  .dm.restart" ;;
  esac
}
