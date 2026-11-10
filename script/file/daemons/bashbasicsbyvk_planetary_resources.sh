#!/usr/bin/env bash
# bashbasicsbyvk_planetary_resources.sh - planetary resources, the BASH flavour.
# ════════════════════════════════════════════════════════════════════════════
#  The one helper both daemons consume (the python flavour is bashbasicsbyvk_planetary_resources.py; same rules, same lock layout,
#  same file formats, so a bash writer and the python daemon use ONE lock):
#
#    local daemon   bashbasicsbyvk_local_daemon      (python)   pointers that follow their path
#    alien daemon   bashbasicsbyvk_alien_daemon.sh   (bash)     snapshots while  o  runs
#
#  Locks        _pr_lock_take DIR [WAIT_TENTHS] [STALE_S]    0 = this caller owns it, 1 = a live owner kept it too long (go on without; never drop it)
#               _pr_lock_drop DIR                            only after a take that returned 0
#               A lock is a directory with the owner's pid inside. It is taken over ONLY when its owner is dead or it is older than STALE_S.
#  Services     _pr_svc_claim LOCKDIR / _pr_svc_alive LOCKDIR / _pr_svc_pid_write LOCKDIR PID    one live daemon per lock, a recycled pid never counts
#               _pr_die_with PARENT_PID CHILD_PID                                               TERM the child the moment the parent is gone
#               _pr_kill_desc PID                                                              stop everything below a process (children first)
#  Log          _pr_log FILE MSG...   _pr_log_trim FILE [MAX_LINES] [KEEP_LINES]
#  Versions     _pr_version NAME      the daemon's version from bashbasicsbyvk_planetary_versions.list (the ONE place)
#  The local daemon's keeper   _pr_wake_local_daemon   (start-up, .dm.restart): starts it unless a live one of the current version runs
# ════════════════════════════════════════════════════════════════════════════

_PR_SELF="${BASH_SOURCE[0]}"; _PR_DIR="${_PR_SELF%/*}"; [ "$_PR_DIR" = "$_PR_SELF" ] && _PR_DIR=.
declare -gA _PR_FOUND=()
_PR_DAEMONS_DIR="${HOME}/.bashbasicsbyvk/daemons"
_PR_VERSION=""

# the path of a script file by name: next to this file, then PATH (the flat install), cached
_pr_find_file() {
  local n="$1" d
  [ -n "${_PR_FOUND[$n]:-}" ] && { printf '%s' "${_PR_FOUND[$n]}"; return 0; }
  if [ -r "$_PR_DIR/$n" ]; then _PR_FOUND[$n]="$_PR_DIR/$n"
  else
    local IFS=:; for d in $PATH; do [ -r "$d/$n" ] && { _PR_FOUND[$n]="$d/$n"; break; }; done
  fi
  [ -n "${_PR_FOUND[$n]:-}" ] && printf '%s' "${_PR_FOUND[$n]}"
}

_pr_version() {      # _pr_version NAME → _PR_VERSION (empty when the list is not found); also on stdout
  _PR_VERSION=""
  local f k v; f=$(_pr_find_file bashbasicsbyvk_planetary_versions.list) || return 1
  while IFS='=' read -r k v || [ -n "$k" ]; do
    [ "$k" = "$1" ] && { _PR_VERSION="$v"; break; }
  done < "$f"
  printf '%s' "$_PR_VERSION"
  [ -n "$_PR_VERSION" ]
}

_pr_now() { printf '%(%s)T' -1; }
_pr_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
_pr_pid_start() {     # the start time of a process (Linux: field 22 of /proc/PID/stat); empty where there is no /proc
  local s; [ -r "/proc/$1/stat" ] || return 0
  s=$(<"/proc/$1/stat") || return 0
  s="${s##*) }"; set -- $s; printf '%s' "${20:-}"
}

# ── locks ────────────────────────────────────────────────────────────────────────────────────────
_pr_lock_stale() {    # _pr_lock_stale DIR STALE_S
  local pid=""; read -r pid < "$1/pid" 2>/dev/null
  if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then return 0; fi     # its owner died holding it
  [ $(( $(_pr_now) - $(_pr_mtime "$1") )) -gt "$2" ]
}
_pr_lock_break() {    # the rename is atomic: of several breakers exactly one wins
  local dead="$1.dead.$BASHPID.$RANDOM"
  mv "$1" "$dead" 2>/dev/null && rm -rf "$dead"
  return 0
}
_pr_lock_take() {     # _pr_lock_take DIR [WAIT_TENTHS=30] [STALE_S=10]
  local d="$1" tries=0 max="${2:-30}" stale="${3:-10}"
  mkdir -p "${d%/*}" 2>/dev/null
  while :; do
    if mkdir "$d" 2>/dev/null; then printf '%s\n' "$BASHPID" > "$d/pid" 2>/dev/null; return 0; fi
    if _pr_lock_stale "$d" "$stale"; then _pr_lock_break "$d"; continue; fi
    tries=$(( tries + 1 ))
    [ "$tries" -ge "$max" ] && return 1
    sleep 0.1
  done
}
_pr_lock_drop() { rm -rf "$1" 2>/dev/null; return 0; }

# ── one live daemon per lock directory ───────────────────────────────────────────────────────────────
_pr_svc_alive() {     # _pr_svc_alive LOCKDIR : the pid inside is alive and is still the process that was claimed (start time); a claim younger than 10 s without a pid counts
  local d="$1" pid="" st="" cur
  { read -r pid; read -r st; } < "$d/pid" 2>/dev/null
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill -0 "$pid" 2>/dev/null || return 1
    if [ -n "$st" ]; then cur=$(_pr_pid_start "$pid"); [ -n "$cur" ] && [ "$cur" != "$st" ] && return 1; fi
    return 0
  fi
  [ -d "$d" ] && [ $(( $(_pr_now) - $(_pr_mtime "$d") )) -le 10 ]
}
_pr_svc_claim() {     # 0 = the caller now owns LOCKDIR (write the pid with _pr_svc_pid_write), 1 = a live daemon owns it
  local d="$1" i
  mkdir -p "${d%/*}" 2>/dev/null
  for i in 1 2 3; do
    mkdir "$d" 2>/dev/null && return 0
    _pr_svc_alive "$d" && return 1
    _pr_lock_break "$d"                      # a dead owner left it behind
  done
  return 1
}
_pr_svc_pid_write() { printf '%s\n%s\n' "$2" "$(_pr_pid_start "$2")" > "$1/pid" 2>/dev/null; }
_pr_svc_release() {   # _pr_svc_release LOCKDIR PID : remove it only when it is OURS (a replaced daemon must not delete its successor's lock)
  local pid=""; read -r pid < "$1/pid" 2>/dev/null
  [ "$pid" = "$2" ] && rm -rf "$1" 2>/dev/null
  return 0
}

# stop everything below a process (children first). The process itself is left alone: a TERM trap that killed ITSELF would re-enter forever.
_pr_kill_desc() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null || ps -o pid= --ppid "$1" 2>/dev/null); do _pr_kill_desc "$c"; kill -TERM "$c" 2>/dev/null; done
}

# _pr_die_with PARENT CHILD : in the background, TERM CHILD the moment PARENT is gone. It also ends when CHILD is gone first, so it never
# signals a pid that was recycled meanwhile.
_pr_die_with() {
  ( while kill -0 "$1" 2>/dev/null && kill -0 "$2" 2>/dev/null; do sleep 2; done
    kill -0 "$2" 2>/dev/null && kill -TERM "$2" 2>/dev/null ) &
}

# ── log ──────────────────────────────────────────────────────────────────────────────────────────────
_pr_log() { local f="$1"; shift; printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$f" 2>/dev/null; }
_pr_log_trim() {      # _pr_log_trim FILE [MAX_LINES=500] [KEEP_LINES=300]
  local f="$1" max="${2:-500}" keep="${3:-300}"
  [ -f "$f" ] && [ "$(wc -l < "$f" 2>/dev/null || echo 0)" -gt "$max" ] && { tail -n "$keep" "$f" > "$f.tmp" && mv -f "$f.tmp" "$f"; }
  true
}

# ── the local daemon's keeper ───────────────────────────────────────────────────────────────────────────
# Starts bashbasicsbyvk_local_daemon unless a live one of the CURRENT version runs. An older one is replaced by the daemon script itself.
# Runs after the first paint (an @call of the load mapper) and from  .dm.restart .
_pr_wake_local_daemon() {
  local script pid="" ver="" want="" c
  script=$(_pr_find_file bashbasicsbyvk_local_daemon) || return 0
  [ -r "$_PR_DAEMONS_DIR/local.pid" ] && read -r pid < "$_PR_DAEMONS_DIR/local.pid"
  [ -r "$_PR_DAEMONS_DIR/local.version" ] && read -r ver < "$_PR_DAEMONS_DIR/local.version"
  want=$(_pr_version local)
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && [ -n "$want" ] && [ "$ver" = "$want" ]; then
    # alive, current version: is it really the daemon (a recycled pid)? Linux can tell from the command line.
    if [ -r "/proc/$pid/cmdline" ]; then
      c=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
      case "$c" in *bashbasicsbyvk_local_daemon*) return 0 ;; esac
    else
      return 0
    fi
  fi
  # not running / an older version / the pid is somebody else's: the script replaces an old one and starts a new one (one at a time: it holds a flock)
  if [ -x "$script" ]; then "$script" </dev/null >/dev/null 2>&1 &
  elif command -v python3 >/dev/null 2>&1; then python3 "$script" </dev/null >/dev/null 2>&1 &
  else python "$script" </dev/null >/dev/null 2>&1 &
  fi
  disown 2>/dev/null
  return 0
}
