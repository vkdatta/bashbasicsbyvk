#!/usr/bin/env bash
# bashbasicsbyvk_staging_pending.sh — RESILIENCE for the five upload services: up- · ux- · backup · save- · snapshot
# ════════════════════════════════════════════════════════════════════════════
#  An upload used to be all-or-nothing: Wi-Fi off, Ctrl-C, Ctrl-Z or a kill at 4 GB of 5 GB threw the 4 GB away.
#  Now every upload is NOTED, and the same engine finishes it whether it is a fresh run or a continued one:
#
#    pack + encrypt into  <pending>/<id>/   (blob0… + manifest, or the ux chunks)      ← kept on disk until the upload is finished
#    server: unique SERVICE ID = SHA-256(email | diseps | time | crypto random);  pending_ops row;  R2 holds the blobs that arrived
#    local : <pending>/<id>/state      what is needed to FINISH it (name, key or wrapped key, commit headers …) — data, never sourced
#            <pending>/<id>/progress   "<blobs done> <blobs> <last blob> <bytes sent> <bytes>"   ← where it stopped
#            <pending>/<id>/run.hb     heartbeat of the process that is sending (so "running" is never guessed)
#            <pending>/<id>/pause.flag / stop.flag   written by the Pending menu, honoured by a running transfer within a second
#
#  1 auto-continue   a lost connection is waited out inside the running transfer (bashbasicsbyvk_staging_pending_xfer) and it carries
#                    on by itself; an expired token is renewed; the snapshot daemon finishes interrupted snapshots on its own
#  2 manual continue the Pending menu (pn) → service → item → Continue: only the blobs the server does NOT hold are sent
#  3 pause           p while uploading · Pending → Pause (also reaches a transfer running in another terminal)
#  4 resume          Pending → Resume
#  5 stop for good   Pending → Stop: the incomplete blobs are deleted on the server and on this computer (never touches a FINISHED upload)
#  Ctrl-C, Ctrl-Z, kill, kill -9 / "kl", a dead battery: nothing is lost — the item shows up in Pending as "interrupted".
#
#  The server keeps an unfinished upload for 3 days after its last activity, then wipes it (credits are only charged at commit,
#  so an unfinished upload costs nothing).  Settings: FILEAPI_BASHBASICS_PENDING_DIR (where it lives), FILEAPI_BASHBASICS_RETRY_MIN
#  (minutes of continuous outage to wait out, default 30).
# ════════════════════════════════════════════════════════════════════════════

_PN_HERE="${BASH_SOURCE[0]%/*}"
_PN_URL=""; _PN_KEY=""; _PN_KIND=""; _PN_DEDUCTED=""; _PN_BALANCE=""; _PN_EXPIRES=""; _PN_NBLOBS=""
_PN_TOKEN=""; _PN_DONE=""; _PN_DONE_ITEMS="{}"
_BB_COMMIT_STATUS=""; _BB_COMMIT_ERR=""

# ── where things live ─────────────────────────────────────────────────────────
_pn_root() { printf '%s' "${FILEAPI_BASHBASICS_PENDING_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/bashbasicsbyvk/pending}"; }
_pn_mkroot() { local r; r=$(_pn_root); mkdir -p "$r" 2>/dev/null && chmod 700 "$r" 2>/dev/null; }
# a work folder INSIDE the pending root: it is renamed (not copied) to <id> once the server has given the id
_pn_mkpack() { _pn_mkroot || return 1; mktemp -d "$(_pn_root)/.pack.XXXXXX"; }
_pn_dir() { printf '%s/%s' "$(_pn_root)" "$1"; }

# ── the state file: key=value lines, read as DATA (never sourced) ──────────────
_pn_get() { sed -n "s/^$2=//p" "$1/state" 2>/dev/null | tail -n 1; }
_pn_set() {
  local d="$1" k="$2" v="${3//$'\n'/ }"
  local tmp="$d/state.n.${BASHPID:-$$}"       # two processes may update the state at once (a running transfer and the Pending menu)
  { grep -v "^$k=" "$d/state" 2>/dev/null; printf '%s=%s\n' "$k" "$v"; } > "$tmp" && mv -f "$tmp" "$d/state"
  chmod 600 "$d/state" 2>/dev/null
}

# _pn_adopt <packdir> <id> <kind> <nblobs> <total-bytes> <display-name> [key=value …]  → prints the final folder
_pn_adopt() {
  local tmp="$1" id="$2" kind="$3" nb="$4" total="$5" name="$6"; shift 6
  local d ttl svc="$kind"; d=$(_pn_dir "$id")
  [ "$kind" = upload ] && svc=""
  ttl=$(_bb_svc_ttl "$svc")
  _pn_mkroot; rm -rf "$d"; mv "$tmp" "$d" || return 1
  chmod 700 "$d" 2>/dev/null
  : > "$d/state"; chmod 600 "$d/state"
  _pn_set "$d" v 1; _pn_set "$d" id "$id"; _pn_set "$d" kind "$kind"; _pn_set "$d" nblobs "$nb"; _pn_set "$d" total "$total"
  _pn_set "$d" name "$name"; _pn_set "$d" alias "${_BB_LINK_ALIAS:-}"; _pn_set "$d" ttl "$ttl"; _pn_set "$d" created "$(date +%s)"
  _pn_set "$d" status running
  local kv; for kv in "$@"; do _pn_set "$d" "${kv%%=*}" "${kv#*=}"; done
  printf '%s' "$d"
}

# ── is a transfer running right now? (pid alive AND a fresh heartbeat — never a guess) ──
_pn_running() {
  local d="$1" pid="" t="" hb="" now
  [ -r "$d/lock" ] || return 1
  read -r pid t < "$d/lock"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null || return 1
  # a killed process that nobody has reaped yet (zombie) still answers kill -0: it is NOT running
  if [ -r "/proc/$pid/stat" ]; then local st; st=$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null); [ "${st:0:1}" = Z ] && return 1; fi
  now=$(date +%s)
  [ -r "$d/run.hb" ] && read -r _ hb < "$d/run.hb"
  [[ "$hb" =~ ^[0-9]+$ ]] && [ "$hb" -gt "${t:-0}" ] || hb="${t:-0}"
  [ $((now - hb)) -lt 45 ]
}
_pn_lock() {
  local d="$1"; _pn_running "$d" && return 1
  printf '%s %s\n' "${BASHPID:-$$}" "$(date +%s)" > "$d/lock"; rm -f "$d/run.hb"; return 0
}
_pn_unlock() { rm -f "$1/lock" "$1/run.hb" 2>/dev/null; }
# running · paused · interrupted
_pn_status() {
  local d="$1" s
  _pn_running "$d" && { printf running; return; }
  s=$(_pn_get "$d" status); [ "$s" = paused ] && printf paused || printf interrupted
}

# ── talking to the server ──────────────────────────────────────────────────────
_pn_jf() {      # _pn_jf <json> <field>  → strings as they are, objects as JSON
  node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{const v=JSON.parse(d)[process.argv[1]];process.stdout.write(v===undefined||v===null?"":typeof v==="object"?JSON.stringify(v):String(v))}catch(e){}})' "$2" <<<"$1"
}
# POST /pending/<id>/resume → _PN_TOKEN _PN_DONE _PN_DONE_ITEMS.   0 ok · 2 credits · 4 gone · 5 offline · 1 other
_pn_resume_info() {
  _bb_call POST "/pending/$1/resume" || return 5
  case "$_BB_STATUS" in
    200) _PN_TOKEN=$(_bb_json_get "$_BB_BODY" token); _PN_DONE=$(_pn_jf "$_BB_BODY" done); _PN_DONE_ITEMS=$(_pn_jf "$_BB_BODY" doneItems); [ -n "$_PN_DONE_ITEMS" ] || _PN_DONE_ITEMS="{}"
         [ -n "$_PN_TOKEN" ] || return 1; return 0 ;;
    404) return 4 ;;
    402) echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")" >&2; return 2 ;;
    000) return 5 ;;
    *)   echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")" >&2; return 1 ;;
  esac
}
_pn_xfer_bin() {
  local b; b=$(command -v bashbasicsbyvk_staging_pending_xfer 2>/dev/null)
  [ -n "$b" ] || { [ -r "$_PN_HERE/bashbasicsbyvk_staging_pending_xfer" ] && b="$_PN_HERE/bashbasicsbyvk_staging_pending_xfer"; }
  [ -n "$b" ] && printf '%s' "$b"
}
# _pn_xfer <pipeline> <id> <dir> <nblobs> <token>  → the verdict word on stdout (progress bar on stderr).  What the server holds is read
# from <dir>/server.json (the resume answer: done ranges + stored sizes)
_pn_xfer() {
  local pipe="$1" id="$2" d="$3" nb="$4" tok="$5" bin conc="$_BB_MAX_PAR" retry
  bin=$(_pn_xfer_bin) || { echo "❌ bashbasicsbyvk_staging_pending_xfer not found (reinstall bashbasicsbyvk)." >&2; echo FAIL; return; }
  retry="${FILEAPI_BASHBASICS_RETRY_MIN:-30}"; [[ "$retry" =~ ^[0-9]{1,4}$ ]] || retry=30
  [ "$pipe" = ux ] && [ "$conc" -gt 8 ] && conc=8
  BB_EMAIL="$FILEAPI_BASHBASICS_EMAIL" BB_UTOKEN="$tok" BB_N="$nb" BB_CHUNK="$_BB_CHUNK_BYTES" BB_CONC="$conc" \
  BB_DONEFILE="$d/server.json" BB_STATE="$d" BB_OFFLINE_MAX=$((retry * 60)) \
    node "$bin" "$pipe" "$WORKER_URL" "$id" "$d" | tail -n 1
}

# ── commit (the last request) — one function per pipeline; both set _BB_COMMIT_STATUS / _BB_COMMIT_ERR ──
# prints "<body>\n<deducted>\n<balance>\n<expires>" on success
_pn_commit() {
  local d="$1" id="$2" kind="$3" nb="$4" tok="$5" kdk
  _BB_COMMIT_HDRS=()
  case "$kind" in
    backup|saved) _BB_COMMIT_HDRS=("X-Vault-Kdk: $(_pn_get "$d" kdk)") ;;
    snapshot)     _BB_COMMIT_HDRS=("X-Vault-Kdk: $(_pn_get "$d" kdk)" "X-Snap-Target: $(_pn_get "$d" snap_tgt)" "X-Snap-Sig: $(_pn_get "$d" snap_sig)") ;;
  esac
  if [ "$kind" = ux ]; then
    _ux_commit "$id" "$tok" "$d" "$(_pn_get "$d" rids)"
  else
    _bb_upload_commit "$id" "$nb" "$d/manifest.enc" "$tok"
  fi
  local rc=$?; _BB_COMMIT_HDRS=()
  return $rc
}

# 0 = it IS finished on the server (lost answer) · 1 = it is gone
_pn_reconcile() {
  local id="$1" kind="$2"
  case "$kind" in
    ux)     _bb_call GET /ux/shares || return 1 ;;
    upload) _bb_call GET /links ;;
    *)      _bb_call GET "/links?svc=$kind" ;;
  esac
  [ "$_BB_STATUS" = 200 ] && [[ "$_BB_BODY" == *"\"id\":\"$id\""* ]]
}

# ════════════════════════════════════════════════════════════════════════════
#  _pn_complete <dir> [quiet]   finish an upload from its folder: send what the server lacks → commit → clean up.
#  Fresh runs and continued runs both come through here.
#  0 done (_PN_URL _PN_KEY _PN_KIND _PN_DEDUCTED _PN_BALANCE _PN_EXPIRES set; the folder is gone)
#  else the upload is KEPT:  20 paused · 21 interrupted by Ctrl-C/kill · 22 stopped · 23 offline too long · 24 failed/transient · 2 credits · 9 already running
#  or it was ended by the server (1) and the folder removed.
# ════════════════════════════════════════════════════════════════════════════
_pn_complete() {
  local d="$1" quiet="${2:-0}" id kind nb pipe verdict rc phase=upload stuck=0 retries=0 found=0 out
  id=$(_pn_get "$d" id); kind=$(_pn_get "$d" kind); nb=$(_pn_get "$d" nblobs)
  [[ "$id" =~ ^[A-Za-z0-9_-]{43}$ ]] && [[ "$nb" =~ ^[0-9]+$ ]] || { echo "❌ That pending item is damaged." >&2; return 1; }
  say() { [ "$quiet" = 1 ] || echo "$@"; }
  _pn_lock "$d" || { say "⚠️  It is already running (another terminal)."; return 9; }
  _pn_set "$d" status running; rm -f "$d/pause.flag" "$d/stop.flag"
  _crypto_check >/dev/null 2>&1 || { _pn_unlock "$d"; return 1; }
  _bb_get_credentials >/dev/null 2>&1 || { _pn_unlock "$d"; return 1; }
  pipe=upload; [ "$kind" = ux ] && pipe=ux
  _PN_KIND="$kind"; _PN_KEY=$(_pn_get "$d" key); _PN_NBLOBS="$nb"
  while :; do
    _pn_resume_info "$id"; rc=$?
    case $rc in
      0) printf '%s' "$_BB_BODY" > "$d/server.json"; chmod 600 "$d/server.json" ;;
      4) if _pn_reconcile "$id" "$kind"; then found=1; _PN_URL="$WORKER_URL/$id"; _PN_DEDUCTED=""; _PN_BALANCE=""; _PN_EXPIRES=""; break
         else say "⚠️  The server no longer has this upload (stopped, or idle for more than 3 days). It was removed here too."; rm -rf "$d"; return 1; fi ;;
      2) _pn_set "$d" status interrupted; _pn_unlock "$d"; say "   Nothing is lost — add credits, then continue it from Pending (pn)."; return 2 ;;
      5) _pn_set "$d" status interrupted; _pn_unlock "$d"; say "📡 Cannot reach the server. Kept — continue it from Pending (pn) when you are online."; return 23 ;;
      *) _pn_set "$d" status interrupted; _pn_unlock "$d"; return 24 ;;
    esac
    if [ "$phase" = upload ]; then
      verdict=$(_pn_xfer "$pipe" "$id" "$d" "$nb" "$_PN_TOKEN")
      case "$verdict" in
        OK)  phase=commit; stuck=0; continue ;;
        TOKEN) stuck=$((stuck + 1)); [ "$stuck" -ge 3 ] && { _pn_set "$d" status interrupted; _pn_unlock "$d"; say "❌ The server keeps refusing the upload token. Kept — try again from Pending (pn)."; return 24; }; continue ;;
        PAUSED)      _pn_set "$d" status paused; _bb_call POST "/pending/$id/pause" >/dev/null 2>&1; _pn_unlock "$d"; say "⏸  Paused — nothing is lost. Resume it from Pending (pn)."; return 20 ;;
        INTERRUPTED) _pn_set "$d" status interrupted; _pn_unlock "$d"; say "⏸  Stopped for now — nothing is lost. Continue it from Pending (pn)."; return 21 ;;
        STOPPED)     _pn_unlock "$d"; return 22 ;;
        OFFLINE)     _pn_set "$d" status interrupted; _pn_unlock "$d"; say "📡 Offline for too long. Everything is kept — continue it from Pending (pn) when the connection is back."; return 23 ;;
        *)           _pn_set "$d" status interrupted; _pn_unlock "$d"; say "❌ Some blobs could not be sent. Everything is kept — continue it from Pending (pn)."; return 24 ;;
      esac
    fi
    # phase = commit (with a token minted a moment ago)
    printf '%s %s\n' "${BASHPID:-$$}" "$(date +%s)" > "$d/lock"
    out=$(_pn_commit "$d" "$id" "$kind" "$nb" "$_PN_TOKEN"); rc=$?
    if [ $rc -eq 0 ]; then
      _PN_URL=$(printf '%s' "$out" | sed -n '1p'); _PN_DEDUCTED=$(printf '%s' "$out" | sed -n '2p')
      _PN_BALANCE=$(printf '%s' "$out" | sed -n '3p'); _PN_EXPIRES=$(printf '%s' "$out" | sed -n '4p'); found=1; break
    fi
    case "$_BB_COMMIT_STATUS:$_BB_COMMIT_ERR" in
      409:already_committed) found=1; _PN_URL="$WORKER_URL/$id"; _PN_DEDUCTED=""; _PN_BALANCE=""; _PN_EXPIRES=""; break ;;
      400:incomplete_upload) retries=$((retries + 1)); [ "$retries" -le 3 ] && { phase=upload; continue; }
                             _pn_set "$d" status interrupted; _pn_unlock "$d"; return 24 ;;
      5??:*|000:*|429:*) _pn_set "$d" status interrupted; _pn_unlock "$d"; say "   Kept — continue it from Pending (pn)."; return 24 ;;
      *) _bb_call DELETE "/pending/$id" >/dev/null 2>&1; rm -rf "$d"; return 1 ;;   # the server ended it (credits, size, removed target …)
    esac
  done
  [ "$found" = 1 ] || return 1
  rm -rf "$d"
  return 0
}

# ── what to say when a CONTINUED upload finishes (a fresh run's caller says its own words) ──
# _pn_report <kind> <alias> <ttl> <name> <nblobs-or-extra…>   (reads _PN_* set by _pn_complete)
_pn_report() {
  local kind="$1" alias="$2" ttl="$3" extra="$4"
  case "$kind" in
    upload)
      _BB_LINK_ALIAS="$alias"; _BB_TTL_OVERRIDE="$ttl"; _BB_SVC=""
      _announce_link "${_PN_URL}#k=${_PN_KEY}"
      [ -n "$_PN_DEDUCTED" ] && echo "💳 Credits deducted: $_PN_DEDUCTED   |   Balance: $_PN_BALANCE"
      _bb_print_expiry "$_PN_EXPIRES"
      _BB_LINK_ALIAS=""; _BB_TTL_OVERRIDE="" ;;
    backup) echo "🗄️  Backed up as '$alias' — kept $(_bb_fmt_duration "$ttl")  ·  Home → Backup (bk) to restore." ;;
    saved)  echo "💾 Saved as '$alias' — no link exists. Open it from any device: Home → Saved Surf (sv)." ;;
    snapshot) echo "📸 Snapshot finished  ·  Home → Snapshots (sn)." ;;
    ux)     echo "✅ Shared with ${extra:-the chosen} person(s). No link exists — each of them gets a notification and accepts it into their Cloud Surf." ;;
  esac
  case "$kind" in backup|saved|snapshot|ux)
    [ -n "$_PN_DEDUCTED" ] && echo "💳 Credits deducted: $_PN_DEDUCTED   |   Balance: $_PN_BALANCE"
    [ -n "$_PN_EXPIRES" ] && echo "🕐 Gone at $(_bb_fmt_when "$_PN_EXPIRES")" ;;
  esac
}

# Continue / Resume an item from its folder (the Pending menu and the snapshot daemon call this)
_pn_continue() {
  local d="$1" quiet="${2:-0}" kind alias ttl rids rc src skind tgt csig
  kind=$(_pn_get "$d" kind); alias=$(_pn_get "$d" alias); ttl=$(_pn_get "$d" ttl); rids=$(_pn_get "$d" rids)
  src=$(_pn_get "$d" snap_src); skind=$(_pn_get "$d" snap_kind); tgt=$(_pn_get "$d" snap_tgt); csig=$(_pn_get "$d" snap_sig)
  _pn_complete "$d" "$quiet"; rc=$?
  if [ $rc -eq 0 ]; then
    if [ "$quiet" != 1 ]; then
      local n=""; [ -n "$rids" ] && n=$(awk -F, '{print NF}' <<<"$rids")
      _pn_report "$kind" "$alias" "$ttl" "$n"
    fi
    if [ "$kind" = snapshot ] && declare -F _snap_target_set >/dev/null 2>&1 && [ -n "$tgt" ]; then
      _snap_target_set "$tgt" "${skind:-d}" "$src" 1 "${csig:-0}" "$(date +%s)"
    fi
  fi
  return $rc
}

# ── pause / stop (menu actions; they also reach a transfer running in ANOTHER terminal) ──
_pn_pause() {
  local id="$1" d; d=$(_pn_dir "$id")
  if [ -d "$d" ]; then
    if _pn_running "$d"; then : > "$d/pause.flag"; echo "⏸  Asked the running transfer to pause…"
      local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do _pn_running "$d" || break; sleep 1; done
    fi
    _pn_set "$d" status paused; rm -f "$d/pause.flag"
  fi
  _bb_call POST "/pending/$id/pause"
  case "$_BB_STATUS" in 200) echo "⏸  Paused. Resume it any time." ;; 404) echo "ℹ️  The server no longer has it." ;; 000) echo "⏸  Paused here (the server could not be reached; it is only a marker there)." ;; *) echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")" ;; esac
}
# stop for good: incomplete blobs are deleted on the server and here.  0 stopped · 1 not stopped
_pn_stop() {
  local id="$1" d; d=$(_pn_dir "$id")
  if [ -d "$d" ] && _pn_running "$d"; then
    : > "$d/stop.flag"; echo "⏹  Asking the running transfer to stop…"
    local i; for i in 1 2 3 4 5 6 7 8; do _pn_running "$d" || break; sleep 1; done
  fi
  _bb_call DELETE "/pending/$id"
  case "$_BB_STATUS" in
    200) echo "🗑️  Stopped. The incomplete blobs were deleted from the server." ;;
    404) echo "ℹ️  The server had already dropped it." ;;
    409) echo "ℹ️  It had already finished — it is a normal item now (nothing was deleted). Nuke it from its own menu if you do not want it." ;;
    000) echo "📡 Cannot reach the server, so nothing was deleted. Try again when you are online."; return 1 ;;
    *)   echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")"; return 1 ;;
  esac
  [ -d "$d" ] && rm -rf "$d"
  return 0
}

# ── local list (no network): one TSV line per item  id · kind · status · name · done · blobs · last · bytes-sent · bytes · created ──
_pn_local_ids() {
  local r d; r=$(_pn_root); [ -d "$r" ] || return 0
  for d in "$r"/*/; do
    d="${d%/}"; [ -s "$d/state" ] || continue
    printf '%s\n' "${d##*/}"
  done
}
_pn_local_row() {
  local d; d=$(_pn_dir "$1"); [ -s "$d/state" ] || return 1
  local done_=0 nb last=-1 sent=0 tot=0
  nb=$(_pn_get "$d" nblobs); tot=$(_pn_get "$d" total)
  [ -r "$d/progress" ] && read -r done_ _ last sent _ < "$d/progress"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$(_pn_get "$d" kind)" "$(_pn_status "$d")" "$(_pn_get "$d" name)" "${done_:-0}" "${nb:-0}" "${last:--1}" "${sent:-0}" "${tot:-0}" "$(_pn_get "$d" created)"
}
_pn_count_local() { local n=0 i; while read -r i; do [ -n "$i" ] && n=$((n + 1)); done < <(_pn_local_ids); printf '%s' "$n"; }

# one line for the main screen when something is waiting (cheap: directory listing only, cached 20 s)
_PN_HINT_AT=0; _PN_HINT=""
_pn_hint() {
  local now=${EPOCHSECONDS:-$(date +%s)} n
  if [ $((now - _PN_HINT_AT)) -ge 20 ]; then
    _PN_HINT_AT=$now; n=$(_pn_count_local)
    if [ "$n" -gt 0 ]; then _PN_HINT="⏸  $n unfinished upload(s) — nothing is lost: type  pn  to continue, pause or stop them."; else _PN_HINT=""; fi
  fi
  [ -n "$_PN_HINT" ] && echo "$_PN_HINT"
  return 0
}

# the snapshot daemon (quiet, background) finishes interrupted snapshots on its own — "auto continue"
_pn_auto_snapshots() {
  local id d k st
  while read -r id; do
    d=$(_pn_dir "$id"); k=$(_pn_get "$d" kind); [ "$k" = snapshot ] || continue
    st=$(_pn_status "$d"); [ "$st" = interrupted ] || continue
    _pn_continue "$d" 1
  done < <(_pn_local_ids)
  return 0
}

# old leftovers: half-packed folders from a crash while packing (never reached the server)
_pn_gc() { local r; r=$(_pn_root); [ -d "$r" ] && find "$r" -maxdepth 1 -name '.pack.*' -mmin +1440 -exec rm -rf {} + 2>/dev/null; return 0; }
