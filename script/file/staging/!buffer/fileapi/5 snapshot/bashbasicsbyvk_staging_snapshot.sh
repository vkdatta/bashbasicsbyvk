#!/usr/bin/env bash
# bashbasicsbyvk_staging_snapshot.sh — Service 4: Snapshots
#
#   snap-<items>        put files/folders on the snapshot list of THIS computer          e.g.  snap-1-3
#   sn                  Home → Snapshots: every device's list, view / restore / nuke snapshots, stop watching a path
#
# How it behaves
#   • While  o  is running, a background process takes a snapshot of every watched path whose contents changed,
#     every <interval> (Settings → File API → Snapshots; 1 minute … 30 days, default 1 hour).
#   • It only runs while  o  is running. Close  o  (or the device) and nothing is taken. Reopen after 10 days with a
#     10-minute interval → exactly ONE snapshot of the state at that moment, not 1440.
#   • Consistency: each path is first COPIED to a temporary folder (cheap on copy-on-write disks), and the archive
#     is packed from that copy — so deleting or editing a 5 GB file mid-sync cannot corrupt the snapshot. A path
#     that changes while being copied is copied again.
#   • A path that has not changed since its last snapshot is skipped (no credits spent).
#   • The background work never prompts and never touches the screen. The one exception: when your credits are not
#     enough, a one-line notice appears in  o  and snapshots pause until they are.
#   • A snapshot is named   AS ON DDMMYYYY HHMM   and cannot be renamed.
#   • Devices are told apart by the existing telemetry uuid (never deleted: snapshots depend on it). The list of watched
#     paths of every device lives on the server (paths encrypted), so from any device you can see them, open that
#     device's snapshots, and remove a path from another device's list (that device stops on its next sync).
#   • Encryption/keys: client-side encryption like ux- (dinons → FEK → K). Data, paths and device names are encrypted here;
#     the server holds only keys wrapped with your FEK, which it cannot open. Needs the dinons on every device that takes or opens snapshots.


_SNAP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/snapshots"
_SNAP_TARGETS="$_SNAP_DIR/targets"          # tgt TAB kind(f|d) TAB abs path TAB pushed(0|1) TAB last_sig TAB last_epoch
_SNAP_LOCK="$_SNAP_DIR/daemon.lock"         # a directory; holds  pid
_SNAP_LOG="$_SNAP_DIR/log"
_SNAP_NOTICE="$_SNAP_DIR/notice"
_SNAP_LASTRUN="$_SNAP_DIR/last_cycle"
_SNAP_TMPROOT="${XDG_CACHE_HOME:-$HOME/.cache}/bashbasicsbyvk/snap-tmp"      # on disk on purpose: /tmp is often RAM
_SNAP_MIN_INTERVAL=60
_SNAP_MAX_INTERVAL=$((30*86400))
_SNAP_MAX_TARGETS=200

_snap_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$_SNAP_LOG" 2>/dev/null; }
_snap_log_trim() { [ -f "$_SNAP_LOG" ] && [ "$(wc -l < "$_SNAP_LOG" 2>/dev/null || echo 0)" -gt 500 ] && { tail -n 300 "$_SNAP_LOG" > "$_SNAP_LOG.tmp" && mv -f "$_SNAP_LOG.tmp" "$_SNAP_LOG"; }; true; }

# "AS ON 15102026 1030" from epoch-ms, in the app time zone
_snap_name() {
  local ms="$1" sec
  [[ "$ms" =~ ^[0-9]{10,}$ ]] || { printf 'AS ON ?'; return; }
  sec=$((ms / 1000))
  printf 'AS ON %s' "$(date -d "@$sec" '+%d%m%Y %H%M' 2>/dev/null || date -r "$sec" '+%d%m%Y %H%M' 2>/dev/null || echo "$sec")"
}

_snap_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -d' ' -f1
  else printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; fi
}

_snap_hostlabel() {
  local h; h=$(hostname 2>/dev/null || uname -n 2>/dev/null || echo computer)
  h=$(printf '%s' "$h" | LC_ALL=C tr -c 'A-Za-z0-9._ -' '_' | cut -c1-40)
  printf '%s' "${h:-computer}"
}

# "<signature> <bytes> <files>" of a file or folder: names, sizes and modification times (symlinks inside are not part of an archive, so not of this)
_snap_sig() {
  node -e '
    const fs = require("fs"), path = require("path"), crypto = require("crypto");
    const h = crypto.createHash("sha256"); let bytes = 0, count = 0;
    function walk(p, rel) {
      let st; try { st = fs.lstatSync(p); } catch (e) { return; }
      if (st.isDirectory()) {
        h.update("d\0" + rel + "\0");
        let ents; try { ents = fs.readdirSync(p).sort(); } catch (e) { return; }
        for (const e of ents) walk(path.join(p, e), rel + "/" + e);
      } else if (st.isFile()) {
        h.update("f\0" + rel + "\0" + st.size + "\0" + Math.floor(st.mtimeMs) + "\0"); bytes += st.size; count++;
      }
    }
    walk(process.argv[1], "");
    process.stdout.write(h.digest("hex").slice(0, 40) + " " + bytes + " " + count);
  ' "$1" 2>/dev/null
}

# ── local list of watched paths ───────────────────────────────────────────────────────────────────────
_snap_targets_write() {   # stdin → targets (atomic)
  mkdir -p "$_SNAP_DIR" 2>/dev/null; chmod 700 "$_SNAP_DIR" 2>/dev/null
  local tmp; tmp=$(umask 077; mktemp "$_SNAP_TARGETS.XXXXXX") || return 1
  cat > "$tmp" && mv -f "$tmp" "$_SNAP_TARGETS"
}
_snap_target_set() {      # _snap_target_set <tgt> <kind> <path> <pushed> <sig> <epoch>   (replace or add)
  local tgt="$1"
  { [ -f "$_SNAP_TARGETS" ] && awk -F'\t' -v t="$tgt" '$1 != t' "$_SNAP_TARGETS"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}" "${6:-0}"; } | _snap_targets_write
}
_snap_target_drop() {     # _snap_target_drop <tgt>
  [ -f "$_SNAP_TARGETS" ] || return 0
  awk -F'\t' -v t="$1" '$1 != t' "$_SNAP_TARGETS" | _snap_targets_write
}
_snap_target_count() { [ -s "$_SNAP_TARGETS" ] && wc -l < "$_SNAP_TARGETS" | tr -d ' ' || echo 0; }
_snap_target_line() {     # _snap_target_line <tgt> → the stored line
  [ -f "$_SNAP_TARGETS" ] && awk -F'\t' -v t="$1" '$1 == t' "$_SNAP_TARGETS"
}

# ── server calls ──────────────────────────────────────────────────────────────────────────────────────────
_snap_dev_hdrs() {         # sets _BB_CALL_HDRS from the device id files; returns 1 when this computer has no signed id yet
  local d="${_BVK_TELEMETRY_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/telemetry}" id sg
  id=$(cat "$d/uuid" 2>/dev/null); sg=$(cat "$d/sig" 2>/dev/null)
  [ -n "$id" ] && [ -n "$sg" ] || return 1
  _BB_CALL_HDRS=("X-Telemetry-Id: $id" "X-Telemetry-Sig: $sg")
}
_snap_labelkey() {         # → the per-user label key on stdout (shared with link names / stored links: _bb_labelkey_load)
  _bb_labelkey_load || return 1
  printf '%s' "$_BB_LK"
}
_snap_json_tsv() {         # stdin JSON → TSV by mode (targets | devices | snaps)
  node -e '
    let d = ""; process.stdin.on("data", c => d += c); process.stdin.on("end", () => {
      let o; try { o = JSON.parse(d); } catch (e) { process.exit(2); }
      const T = "\t", c = (v) => { const t = String(v ?? "").replace(/[\t\r\n]/g, " "); return t === "" ? "-" : t; };   // "-" = empty (a tab IFS would drop empty fields)
      const mode = process.argv[1];
      if (mode === "targets") for (const t of o.targets || []) console.log([t.tgt, c(t.labelEnc), t.kind, c(t.lastSig), t.lastTaken || 0, t.lastAttempt || 0].join(T));
      if (mode === "devices") { console.log(["SELF", c(o.self)].join(T)); for (const x of o.devices || []) console.log([x.device, c(x.labelEnc), x.targets, x.snapshots, x.lastSeen, x.firstSeen].join(T)); }
      if (mode === "snaps")   for (const s of o.snapshots || []) console.log([s.id, s.tgt, s.takenAt, s.bytes, s.expiresAt, s.createdAt].join(T));
    });' "$1" 2>/dev/null
}

# Make the server's list for THIS device and the local list agree.  Needs  LK  (label key) in $1.
#   removed on the server (from another device)  → dropped here
#   added here, not yet pushed                    → pushed
#   on the server but unknown here                → restored locally (e.g. after a reinstall)
_snap_reconcile() {
  local lk="$1" line tgt lab kind lsig ltaken lattempt p pushed
  _snap_dev_hdrs || return 1
  _bb_call PUT /snapshots/device "{\"labelEnc\":\"$(_bb_label_enc "$lk" "$(_snap_hostlabel)")\"}" || return 1
  [ "$_BB_STATUS" = 200 ] || return 1
  _bb_call GET "/snapshots/targets?device=self" || return 1
  [ "$_BB_STATUS" = 200 ] || return 1
  local srv; srv=$(_snap_json_tsv targets <<<"$_BB_BODY") || return 1
  local -A on_srv=() s_lab=() s_kind=() s_sig=() s_taken=()
  while IFS=$'\t' read -r tgt lab kind lsig ltaken lattempt; do
    [ -n "$tgt" ] || continue
    [ "$lsig" = "-" ] && lsig=""
    on_srv[$tgt]=1; s_lab[$tgt]="$lab"; s_kind[$tgt]="$kind"; s_sig[$tgt]="$lsig"; s_taken[$tgt]="$ltaken"
  done <<<"$srv"
  local -A on_loc=()
  if [ -f "$_SNAP_TARGETS" ]; then
    while IFS=$'\t' read -r tgt kind p pushed lsig ltaken; do
      [ -n "$tgt" ] || continue
      on_loc[$tgt]=1
      if [ "$pushed" = 1 ] && [ -z "${on_srv[$tgt]:-}" ]; then
        _snap_log "removed from the list on another device: $p"; _snap_target_drop "$tgt"; continue
      fi
      if [ "$pushed" != 1 ]; then
        _snap_dev_hdrs
        _bb_call PUT /snapshots/targets "{\"tgt\":\"$tgt\",\"labelEnc\":\"$(_bb_label_enc "$lk" "$p")\",\"kind\":\"$kind\"}" || continue
        if [ "$_BB_STATUS" = 200 ]; then _snap_target_set "$tgt" "$kind" "$p" 1 "$lsig" "$ltaken"
        else _snap_log "could not register $p: $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; fi
      fi
    done < "$_SNAP_TARGETS"
  fi
  for tgt in "${!on_srv[@]}"; do
    [ -n "${on_loc[$tgt]:-}" ] && continue
    p=$(_bb_label_dec "$lk" "${s_lab[$tgt]}")
    [ -n "$p" ] && [[ "$p" == /* ]] || continue
    _snap_target_set "$tgt" "${s_kind[$tgt]}" "$p" 1 "${s_sig[$tgt]}" "$(( ${s_taken[$tgt]:-0} / 1000 ))"
  done
  return 0
}

# ── one snapshot of one path ──────────────────────────────────────────────────────────────────────────────
# returns 0 taken · 1 skipped / failed (logged) · 3 not enough credits
_snap_take() {
  local tgt="$1" kind="$2" src="$3" lastsig="$4" now sig bytes count
  if [ ! -e "$src" ]; then _snap_log "missing, skipped: $src"; return 1; fi
  read -r sig bytes count <<<"$(_snap_sig "$src")"
  [ -n "$sig" ] || { _snap_log "could not read: $src"; return 1; }
  if [ "$sig" = "$lastsig" ]; then return 1; fi          # unchanged since the last snapshot: nothing to keep, nothing to pay

  mkdir -p "$_SNAP_TMPROOT" 2>/dev/null; chmod 700 "$_SNAP_TMPROOT" 2>/dev/null
  local need_kb=$(( bytes / 1024 + bytes / 20480 + 65536 )) free_kb
  free_kb=$(df -Pk "$_SNAP_TMPROOT" 2>/dev/null | awk 'NR==2{print $4}')
  if [[ "$free_kb" =~ ^[0-9]+$ ]] && [ "$free_kb" -lt "$need_kb" ]; then
    _snap_log "not enough free disk space for a consistent copy of $src (need ~$((need_kb/1024)) MB)"; return 1
  fi

  local work; work=$(mktemp -d "$_SNAP_TMPROOT/run.XXXXXX") || return 1
  _SNAP_WORK="$work"
  # consistent copy; if the source changes while it is being copied, copy again (once)
  local pass csig cb cc
  for pass in 1 2; do
    rm -rf "$work"/* "$work"/.[!.]* 2>/dev/null
    cp -a --reflink=auto "$src" "$work/" 2>/dev/null || cp -a "$src" "$work/" 2>/dev/null || { _snap_log "copy failed: $src"; rm -rf "$work"; _SNAP_WORK=""; return 1; }
    read -r csig cb cc <<<"$(_snap_sig "$work/$(basename "$src")")"
    [ "$csig" = "$sig" ] && break
    read -r sig bytes count <<<"$(_snap_sig "$src")"       # it moved under us: look again, then retry the copy
  done
  # what was archived is what we remember (a path that kept changing is simply picked up again next time)
  _SVC_SNAP_TGT="$tgt"; _SVC_SNAP_SIG="$csig"; _SVC_SNAP_KIND="$kind"; _SVC_SNAP_SRC="$src"; _SVC_QUIET=1
  _svc_upload snapshot "" "$work/$(basename "$src")"
  local rc=$?
  _SVC_QUIET=0; _SVC_SNAP_TGT=""; _SVC_SNAP_SIG=""; _SVC_SNAP_KIND=""; _SVC_SNAP_SRC=""
  rm -rf "$work"; _SNAP_WORK=""
  case $rc in
    0) now=$(date +%s); _snap_target_set "$tgt" "$kind" "$src" 1 "$csig" "$now"; _snap_log "snapshot taken: $src ($((bytes/1024/1024)) MB, ${_SVC_DEDUCTED:-?} credit(s))"; return 0 ;;
    3) return 3 ;;
    4) _snap_log "snapshot interrupted: $src — kept, it is finished automatically (or from Pending)"; return 1 ;;
    *) _snap_log "snapshot failed: $src"; return 1 ;;
  esac
}

# one pass over everything on the list
_snap_cycle() {
  _bb_get_credentials >/dev/null 2>&1 || return 0
  _crypto_check >/dev/null 2>&1 || return 0
  _snap_dev_hdrs || { _snap_log "device id not ready yet"; return 0; }
  _pn_auto_snapshots 2>/dev/null      # first finish snapshots an earlier run left half-sent (auto-continue)
  local lk; lk=$(_snap_labelkey 2>/dev/null) || { _snap_log "cannot open the key chain (server unreachable, or no dinons on this computer)"; return 0; }
  _snap_reconcile "$lk" || { _snap_log "could not sync the list with the server"; return 0; }
  [ -s "$_SNAP_TARGETS" ] || return 0

  local tgt kind p pushed lsig lepoch rc paused=0
  local -a lines=()
  mapfile -t lines < "$_SNAP_TARGETS"
  local ln
  for ln in "${lines[@]}"; do
    IFS=$'\t' read -r tgt kind p pushed lsig lepoch <<<"$ln"
    [ -n "$tgt" ] && [ "$pushed" = 1 ] || continue
    _snap_dev_hdrs
    _snap_take "$tgt" "$kind" "$p" "$lsig"; rc=$?
    if [ $rc -eq 3 ]; then
      paused=1
      printf '🔴  Snapshots paused: %s. Add credits, or lower the keep time / raise the interval (Settings → File API → Snapshots).\n' "${_BB_GATE_MSG:-not enough credits}" > "$_SNAP_NOTICE"
      _snap_log "paused: ${_BB_GATE_MSG:-not enough credits}"
      break
    fi
  done
  [ "$paused" = 0 ] && rm -f "$_SNAP_NOTICE"
  return 0
}

# ── the background process ───────────────────────────────────────────────────────────────────────────────
# stop everything below a process (children first). The process itself is left alone: a TERM trap that killed ITSELF would re-enter forever.
_snap_kill_desc() {
  local c
  for c in $(pgrep -P "$1" 2>/dev/null || ps -o pid= --ppid "$1" 2>/dev/null); do _snap_kill_desc "$c"; kill -TERM "$c" 2>/dev/null; done
}
_snap_interval() {
  local v; v=$(_bb_cfg_val snapshot_interval_seconds 3600)
  if [[ "$v" =~ ^[0-9]{1,9}$ ]] && [ "$v" -ge "$_SNAP_MIN_INTERVAL" ] && [ "$v" -le "$_SNAP_MAX_INTERVAL" ]; then printf '%s' "$v"; else printf '3600'; fi
}
_snap_daemon_alive() {
  local pid; pid=$(cat "$_SNAP_LOCK/pid" 2>/dev/null)
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

_snap_daemon_main() {       # runs in the background; $1 = pid of the  o  process it lives and dies with
  local oppid="$1" me="$BASHPID" now due last wait
  # settings are re-read from the config file every pass (a stale copy of the shell variables would hide changes)
  unset snapshot_enabled snapshot_interval_seconds snapshot_keep_seconds credit_prompts
  _SNAP_WORK=""
  _snap_cleanup() { [ -n "$_SNAP_WORK" ] && rm -rf "$_SNAP_WORK"; rm -rf "$_SNAP_LOCK"; }
  trap 'trap "" TERM INT HUP; _snap_kill_desc "$me"; _snap_cleanup; exit 0' TERM INT HUP
  trap '_snap_cleanup' EXIT
  # stop the moment  o  is gone — even in the middle of an upload ("snapshots only happen while o is running")
  ( while kill -0 "$oppid" 2>/dev/null; do sleep 2; done; kill -TERM "$me" 2>/dev/null ) &
  # leftovers of an earlier crash
  find "$_SNAP_TMPROOT" -maxdepth 1 -name 'run.*' -mmin +1440 -exec rm -rf {} + 2>/dev/null
  _snap_log "background snapshots started (o pid $oppid)"
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
  if ! mkdir "$_SNAP_LOCK" 2>/dev/null; then
    _snap_daemon_alive && return 0
    rm -rf "$_SNAP_LOCK"; mkdir "$_SNAP_LOCK" 2>/dev/null || return 0      # a dead owner left it behind
  fi
  local oppid=$$
  (
    declare -F _lt_off >/dev/null 2>&1 && _lt_off      # a daemon is never part of a loadtime report
    echo "$BASHPID" > "$_SNAP_LOCK/pid"
    exec </dev/null >>"$_SNAP_LOG" 2>&1
    _snap_daemon_main "$oppid"
  ) &
  disown 2>/dev/null
  return 0
}

# ── snap-<items> ──────────────────────────────────────────────────────────────────────────────────────────
handle_snap_add() {
  local raw="$1"
  _bb_split_alias "${raw#snap-}" || return 1
  [ -n "$_BB_LINK_ALIAS" ] && { echo "📜  Snapshots cannot be renamed — they are named AS ON <date> <time>."; _BB_LINK_ALIAS=""; }
  _sp_guard_and_resolve "$_BB_ITEMLIST" "snap-" || return 1
  _crypto_check || return 1
  _bb_get_credentials || return 1
  local it p tgt kind sig bytes count added=0 have
  for it in "${sp_resolved[@]}"; do
    p=$(readlink -f -- "$it" 2>/dev/null || realpath "$it" 2>/dev/null)
    [ -n "$p" ] && [ -e "$p" ] || { echo "🔴  Skipping (not found): $it"; continue; }
    if [ "$p" = "/" ]; then echo "🔴  Skipping '/' — pick folders or files."; continue; fi
    case "$p" in "$_SNAP_DIR"|"$_SNAP_DIR"/*|"$_SNAP_TMPROOT"|"$_SNAP_TMPROOT"/*) echo "🔴  Skipping (snapshots' own folder): $p"; continue ;; esac
    [ -d "$p" ] && kind=d || kind=f
    tgt=$(_snap_sha256 "$p")
    have=$(_snap_target_line "$tgt")
    if [ -n "$have" ]; then echo "📜  Already on the list: $p"; continue; fi
    if [ "$(_snap_target_count)" -ge "$_SNAP_MAX_TARGETS" ]; then echo "🔴  At most $_SNAP_MAX_TARGETS files/folders per device."; break; fi
    read -r sig bytes count <<<"$(_snap_sig "$p")"
    _snap_target_set "$tgt" "$kind" "$p" 0 "" 0
    added=$((added + 1))
    echo "📸 On the snapshot list: $p   ($count file(s), $((bytes/1024/1024)) MB before compression)"
    if [[ "$bytes" =~ ^[1-9][0-9]*$ ]] && _bb_estimate "$bytes" "$(_bb_svc_ttl snapshot)"; then
      echo "   ≈ $_BB_E_CREDITS credit(s) per snapshot (kept $(_bb_fmt_duration "$(_bb_svc_ttl snapshot)")) — an upper bound; compression usually lowers it, and unchanged data is never re-uploaded."
    fi
  done
  [ "$added" -gt 0 ] || return 0
  echo "   Taken every $(_bb_fmt_duration "$(_snap_interval)") while  o  is running  ·  see and manage them in Home → Snapshots (sn)."
  # register now (best effort) so other devices see it right away, then make sure the background process runs
  if _snap_dev_hdrs; then
    local lk; lk=$(_snap_labelkey) && _snap_reconcile "$lk" >/dev/null 2>&1
  else
    echo "📜  This computer's id is not registered with the server yet (needs internet once) — it will be on the next start."
  fi
  rm -f "$_SNAP_LASTRUN"          # first snapshot soon, not after a whole interval
  _snap_daemon_start
  return 0
}

# ── Home → Snapshots (sn) ─────────────────────────────────────────────────────────────────────────────────
_snap_menu_devices() {
  local lk="$1" out self
  _snap_dev_hdrs >/dev/null 2>&1 || _BB_CALL_HDRS=()
  _bb_call GET /snapshots/devices || return 1
  [ "$_BB_STATUS" = 200 ] || { echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; return 1; }
  out=$(_snap_json_tsv devices <<<"$_BB_BODY") || { echo "❌ Unreadable answer from the server."; return 1; }
  SNAP_D_ID=(); SNAP_D_LABEL=(); SNAP_D_TARGETS=(); SNAP_D_SNAPS=(); SNAP_D_SEEN=(); SNAP_D_SELF=""
  local a b c d e f
  while IFS=$'\t' read -r a b c d e f; do
    [ -n "$a" ] || continue
    if [ "$a" = SELF ]; then [ "$b" = "-" ] && b=""; SNAP_D_SELF="$b"; continue; fi
    [ "$b" = "-" ] && b=""
    SNAP_D_ID+=("$a"); SNAP_D_LABEL+=("$(_bb_label_dec "$lk" "$b")"); SNAP_D_TARGETS+=("$c"); SNAP_D_SNAPS+=("$d"); SNAP_D_SEEN+=("$e")
  done <<<"$out"
  # Settings (s) › Display › Sort order of this list: A-Z · Z-A · last seen · number of snapshots (default: last seen first, as the server sends it)
  _ms_perm snap_devices "${#SNAP_D_ID[@]}" name=SNAP_D_LABEL seen=SNAP_D_SEEN snaps=SNAP_D_SNAPS
  _ms_reorder SNAP_D_ID SNAP_D_LABEL SNAP_D_TARGETS SNAP_D_SNAPS SNAP_D_SEEN
  return 0
}

_snap_menu_device_view() {   # one device: its watched paths, and its snapshots
  local _MS_CTX=snap_targets
  local lk="$1" dev="$2" dlabel="$3" is_self="$4" a n i
  local out
  while :; do
    _BB_CALL_HDRS=()
    _bb_call GET "/snapshots/targets?device=$dev" || return 1
    [ "$_BB_STATUS" = 200 ] || { echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; return 1; }
    out=$(_snap_json_tsv targets <<<"$_BB_BODY")
    local -a T_ID=() T_PATH=() T_KIND=() T_LAST=()
    local tgt lab kind lsig ltaken latt
    while IFS=$'\t' read -r tgt lab kind lsig ltaken latt; do
      [ -n "$tgt" ] || continue
      T_ID+=("$tgt"); T_PATH+=("$(_bb_label_dec "$lk" "$lab")"); T_KIND+=("$kind"); T_LAST+=("$ltaken")
    done <<<"$out"
    _ms_perm snap_targets "${#T_ID[@]}" name=T_PATH last=T_LAST       # Settings › Display › Sort order of this list
    _ms_reorder T_ID T_PATH T_KIND T_LAST
    echo
    echo "📸 $dlabel$( [ "$is_self" = 1 ] && echo '  (this computer)' )   —   files/folders on its snapshot list: ${#T_ID[@]}"
    if [ ${#T_ID[@]} -eq 0 ]; then echo "   (none)  — add some with  snap-1-3"; fi
    for i in "${!T_ID[@]}"; do
      printf '  %2d) %s %s   — last snapshot: %s\n' "$((i+1))" "$( [ "${T_KIND[$i]}" = d ] && echo 📁 || echo 📄 )" "${T_PATH[$i]:-(path hidden: key unavailable)}" \
        "$( [ "${T_LAST[$i]:-0}" -gt 0 ] 2>/dev/null && _snap_name "${T_LAST[$i]}" || echo none yet )"
    done
    echo "   N: snapshots of that path · all: every snapshot of this device · x-N: stop snapshotting it (removes it from the list$( [ "$is_self" = 1 ] || echo ' — that device stops on its next sync' )) · u: back"
    [ "${_BVK_TO_MAIN:-0}" = 1 ] && return 0      # q in a deeper screen: close to the main loop
    read -e -r -p "   > " a || return 0
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    case "${a,,}" in
      u|"") return 0 ;;
      q) _bvk_quit; return 0 ;;
      all) _snap_menu_snaps "$lk" "$dev" "" "all paths" ;;
      x-*)
        n="${a#*-}"
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#T_ID[@]} ]; then
          _bvk_yn a "Stop snapshotting '${T_PATH[$((n-1))]}'? Existing snapshots stay until they expire." -d n
          case "${a,,}" in y|yes)
            _BB_CALL_HDRS=(); _bb_call DELETE "/snapshots/targets/$dev/${T_ID[$((n-1))]}" || true
            if [ "$_BB_STATUS" = 200 ]; then echo "💫 Removed from the list."; [ "$is_self" = 1 ] && _snap_target_drop "${T_ID[$((n-1))]}"
            else echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; fi ;;
          esac
        else echo "🔴  Usage: x-2"; fi ;;
      *)
        if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#T_ID[@]} ]; then
          _snap_menu_snaps "$lk" "$dev" "${T_ID[$((a-1))]}" "${T_PATH[$((a-1))]}"
        else echo "🔴  Not an option."; fi ;;
    esac
  done
}

_snap_menu_snaps() {         # snapshots of a device (optionally of one path)
  local _MS_CTX=snapshots
  local lk="$1" dev="$2" tgt="$3" label="$4" a n i out
  while :; do
    _BB_CALL_HDRS=()
    _bb_call GET "/snapshots?device=$dev${tgt:+&tgt=$tgt}" || return 1
    [ "$_BB_STATUS" = 200 ] || { echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; return 1; }
    out=$(_snap_json_tsv snaps <<<"$_BB_BODY")
    local -a S_ID=() S_TGT=() S_AT=() S_BYTES=() S_EXP=()
    local id t at by ex cr
    while IFS=$'\t' read -r id t at by ex cr; do
      [ -n "$id" ] || continue
      S_ID+=("$id"); S_TGT+=("$t"); S_AT+=("$at"); S_BYTES+=("$by"); S_EXP+=("$ex")
    done <<<"$out"
    _ms_perm snapshots "${#S_ID[@]}" created=S_AT size=S_BYTES expiry=S_EXP      # Settings › Display › Sort order of this list
    _ms_reorder S_ID S_TGT S_AT S_BYTES S_EXP
    echo
    _ms_label snapshots; echo "🕘 SNAPSHOTS — $label   (${#S_ID[@]}, sorted: $_ms_l)   🕐 times in $(_tz_label 2>/dev/null || date +%Z)"
    [ ${#S_ID[@]} -eq 0 ] && echo "   (none yet — they appear after the first sync while  o  is running)"
    local nowms; nowms=$(( $(date +%s) * 1000 ))
    for i in "${!S_ID[@]}"; do
      printf '  %2d) %s   %s   gone in %s\n' "$((i+1))" "$(_snap_name "${S_AT[$i]}")" "$(_api_hsize "${S_BYTES[$i]}" 2>/dev/null || echo "${S_BYTES[$i]} B")" \
        "$(_bb_fmt_duration $(( (${S_EXP[$i]} - nowms) / 1000 )))"
    done
    echo "   N: restore here (into a new folder named after it) · e-N: extend / shorten · x-N: nuke · u: back      (snapshots cannot be renamed)"
    [ "${_BVK_TO_MAIN:-0}" = 1 ] && return 0      # q in a deeper screen: close to the main loop
    read -e -r -p "   > " a || return 0
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    case "${a,,}" in
      u|"") return 0 ;;
      q) _bvk_quit; return 0 ;;
      x-*|e-*)
        local verb="${a:0:1}" spec=""; n="${a#*-}"
        if [ "$verb" = e ]; then local nn="${n%%[[:space:]]*}"; [ "$nn" != "$n" ] && spec="${n#*[[:space:]]}"; n="$nn"; fi
        if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt ${#S_ID[@]} ]; then echo "🔴  Pick a number from the list."; continue; fi
        i=$((n-1))
        if [ "$verb" = x ]; then
          _bvk_yn a "Nuke $(_snap_name "${S_AT[$i]}") now?" -d none
          case "${a,,}" in y|yes)
            _BB_CALL_HDRS=(); _bb_call DELETE "/links/${S_ID[$i]}" || true
            [ "$_BB_STATUS" = 200 ] && echo "💫 Nuked." || echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")" ;;
          esac
        else
          _snap_extend "${S_ID[$i]}" "${S_AT[$i]}" "${S_EXP[$i]}" "$spec"
        fi ;;
      *)
        if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#S_ID[@]} ]; then
          i=$((a-1)); local nm; nm=$(_snap_name "${S_AT[$i]}")
          _svc_restore snapshot "${S_ID[$i]}" "$nm" "${path:-$PWD}/$nm"
        else echo "🔴  Not an option."; fi ;;
    esac
  done
}

_snap_extend() {             # _snap_extend <id> <taken-ms> <expires-ms> [spec]   (total life counted from when it was taken)
  local id="$1" taken="$2" exp="$3" spec="$4" cur total ans
  cur=$(( (exp - taken) / 1000 ))
  if [ -z "$spec" ]; then
    echo "   Total life now $(_bb_fmt_duration "$cur"). Enter the NEW TOTAL (2d · 36h), or +12h to extend / -1d to shorten."
    read -e -r -p "   New time (u = back): " spec
    case "${spec,,}" in u|q|"") return 0 ;; esac
  fi
  total=$(_bb_resolve_time "$cur" "$spec"); case $? in 1) echo "🔴  Use e.g. 2d · +12h · -1d."; return 1 ;; 2) echo "🔴  Between 1 minute and 30 days."; return 1 ;; esac
  if [ "$(_bb_cfg_val credit_prompts show)" != skip ] && [ "$total" -gt "$cur" ]; then
    _BB_CALL_HDRS=(); _bb_call POST "/links/$id/expiry" "{\"totalSeconds\":$total,\"dryRun\":true}"
    if [ "$_BB_STATUS" = 200 ]; then
      local ch bal mx; ch=$(_bb_json_get "$_BB_BODY" charge); bal=$(_bb_json_get "$_BB_BODY" balance); mx=$(_bb_json_get "$_BB_BODY" maxTotalSeconds)
      if [[ "$ch" =~ ^[0-9]+$ && "$bal" =~ ^[0-9]+$ ]]; then
        if [ "$ch" -gt "$bal" ]; then
          echo "💳 Not enough credits: that costs $ch, you have $bal."
          [[ "$mx" =~ ^[0-9]+$ ]] && [ "$mx" -gt "$cur" ] || { echo "❌ Nothing more can be afforded."; return 1; }
          _bvk_yn ans "Longest you can afford: total $(_bb_fmt_duration "$mx"). Use that?" -d n
          case "${ans,,}" in y|yes) total="$mx" ;; *) echo "🚫 Cancelled"; return 1 ;; esac
        elif [ "$ch" -gt 0 ]; then
          _bvk_yn ans "Costs $ch credit(s) (balance $bal → $((bal-ch))). Continue?" -d n
          case "${ans,,}" in y|yes) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
        fi
      fi
    fi
  fi
  _BB_CALL_HDRS=(); _bb_call POST "/links/$id/expiry" "{\"totalSeconds\":$total}"
  if [ "$_BB_STATUS" = 200 ]; then echo "💫 Now gone at $(_bb_fmt_when "$(_bb_json_get "$_BB_BODY" expiresAt)")   |   Balance: $(_bb_json_get "$_BB_BODY" balance)"
  else echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; fi
}

snapshot_menu() {
  _dep_need -c "Snapshots" fileapi.snapshot || return
  local _MS_CTX=snap_devices            # s → Display → Sort order is this list's own
  _crypto_check || return 1
  _bb_get_credentials || return 1
  local lk a n i
  if ! _snap_dev_hdrs; then
    echo "📜  This computer's id is not registered yet (it is created and signed by the server on the first start with internet)."
    echo "   Other devices are still listed below."
  fi
  while :; do
    lk=$(_snap_labelkey) || { echo "❌ Could not reach the server."; return 1; }
    _snap_menu_devices "$lk" || return 1
    echo
    echo "📸 SNAPSHOTS (sn)   every $(_bb_fmt_duration "$(_snap_interval)") while o runs · kept $(_bb_fmt_duration "$(_bb_svc_ttl snapshot)") · $( [ "$(_bb_cfg_val snapshot_enabled on)" = off ] && echo 'PAUSED (Settings → File API → Snapshots)' || echo on )"
    [ -s "$_SNAP_NOTICE" ] && cat "$_SNAP_NOTICE"
    echo "   Devices (told apart by their telemetry id):"
    [ ${#SNAP_D_ID[@]} -eq 0 ] && echo "   (none yet — add files with  snap-1-3  and keep  o  open)"
    for i in "${!SNAP_D_ID[@]}"; do
      printf '  %2d) %s %s · %s  — %s path(s), %s snapshot(s), last seen %s\n' "$((i+1))" \
        "$( [ "${SNAP_D_ID[$i]}" = "$SNAP_D_SELF" ] && echo '★' || echo ' ' )" "${SNAP_D_LABEL[$i]:-device}" "${SNAP_D_ID[$i]:0:8}" "${SNAP_D_TARGETS[$i]}" "${SNAP_D_SNAPS[$i]}" "$(_bb_fmt_when "${SNAP_D_SEEN[$i]}")"
    done
    echo "   N: open that device · rf: refresh · u: back       (★ = this computer)"
    [ "${_BVK_TO_MAIN:-0}" = 1 ] && return 0      # q in a deeper screen: close to the main loop
    read -e -r -p "   > " a || return 0
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    case "${a,,}" in
      u|sn|"") return 0 ;;
      q) _bvk_quit; return 0 ;;
      rf) ;;
      *)
        if [[ "$a" =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#SNAP_D_ID[@]} ]; then
          i=$((a-1))
          _snap_menu_device_view "$lk" "${SNAP_D_ID[$i]}" "${SNAP_D_LABEL[$i]:-device} · ${SNAP_D_ID[$i]:0:8}" "$( [ "${SNAP_D_ID[$i]}" = "$SNAP_D_SELF" ] && echo 1 || echo 0 )"
        else echo "🔴  Not an option."; fi ;;
    esac
  done
}
