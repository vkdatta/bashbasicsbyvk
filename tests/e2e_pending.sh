#!/usr/bin/env bash
# End-to-end test of RESILIENCE (Pending): interrupted uploads continue, pause / resume / stop, lost connection: the REAL bash client against the REAL worker code
# (in-memory D1/R2, local HTTPS). Needs node >= 22 (node:sqlite), openssl, curl, tar, gzip.
#   bash tests/e2e_pending.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILEAPI="${FILEAPI:-$ROOT/../fileapi}"
T=${E2E_DIR:-/tmp/e2ep}; PORT=${E2E_PORT:-8793}
rm -rf "$T/home" "$T/info.json"; mkdir -p "$T/home"
[ -f "$T/cert.pem" ] || openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/key.pem" -out "$T/cert.pem" -days 2 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1

export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_CACHE_HOME="$T/home/.cache" NODE_EXTRA_CA_CERTS="$T/cert.pem" NODE_NO_WARNINGS=1
mkdir -p "$XDG_CONFIG_HOME/bashbasicsbyvk" "$HOME/.bashbasicsbyvk"
export PATH="$(find "$ROOT/script" -type d | paste -sd: -):$PATH"

( cd "$FILEAPI/test" && node --experimental-sqlite e2e_server.mjs "$PORT" "$T/cert.pem" "$T/key.pem" "$T/info.json" 1000 ) > "$T/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null; pkill -f "e2e_server.mjs $PORT" 2>/dev/null; true' EXIT
for _ in $(seq 1 50); do grep -q ready "$T/server.log" 2>/dev/null && break; sleep 0.2; done
grep -q ready "$T/server.log" || { echo "server did not start"; cat "$T/server.log"; exit 1; }

jget() { node -e 'const o=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); process.stdout.write(String(o[process.argv[2]]))' "$T/info.json" "$1"; }
EMAIL=$(jget mail); DISEPS=$(jget diseps); APIKEY=$(jget apikey); UUID=$(jget uuid); SIG=$(jget sig); UUID2=$(jget uuid2); SIG2=$(jget sig2)
BASE="https://localhost:$PORT"
sql() { curl -s --cacert "$T/cert.pem" -G "$BASE/__test/sql" --data-urlencode "q=$1"; }
setbal() { curl -s --cacert "$T/cert.pem" -X POST "$BASE/__test/balance?set=$1" >/dev/null; }
bal() { curl -s --cacert "$T/cert.pem" "$BASE/__test/balance"; }
q1() { sql "$1" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const r=JSON.parse(d);const o=r[0]||{};process.stdout.write(String(Object.values(o)[0] ?? ""))})'; }

# device id files (what the telemetry ping would have written)
export _BVK_TELEMETRY_DIR="$XDG_CONFIG_HOME/bashbasicsbyvk/telemetry"; mkdir -p "$_BVK_TELEMETRY_DIR"
printf '%s\n' "$UUID" > "$_BVK_TELEMETRY_DIR/uuid"; printf '%s\n' "$SIG" > "$_BVK_TELEMETRY_DIR/sig"

# ---- client under test ----
source "bashbasicsbyvk_auth.sh"
source "bashbasicsbyvk_fileapi_lib.sh"; source "bashbasicsbyvk_staging_pending.sh"; source "bashbasicsbyvk_staging_upload.sh"; source "bashbasicsbyvk_staging_ux.sh"; source "bashbasicsbyvk_staging_svc.sh"; source "bashbasicsbyvk_staging_backup.sh"; source "bashbasicsbyvk_staging_saved.sh"; source "bashbasicsbyvk_staging_snapshot.sh"
WORKER_URL="$BASE"; _BB_CURL_OPTS+=(--cacert "$T/cert.pem")
# the user's key chain, made the way -auth makes it: dinons (never sent) wrap a random FEK; only the wrapped FEK is on the server
DINONS=$(_bvk_auth_gen_codes 29); FEK_HEX=$(_bvk_auth_gen_fek)
sql "update users set fek_wrapped='$(_bvk_auth_fek_wrap "$FEK_HEX" "$DINONS")'" >/dev/null
HAVE_DINONS=1
_bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="$EMAIL" FILEAPI_BASHBASICS_DISEPS="$DISEPS" FILEAPI_BASHBASICS_KEY="$APIKEY"; P_DINONS=""; [ "$HAVE_DINONS" = 1 ] && P_DINONS="$DINONS"; return 0; }
_SNAP_DIR="$XDG_CONFIG_HOME/bashbasicsbyvk/snapshots"   # (same value; explicit for the reader)


source "bashbasicsbyvk_auth.sh"
source "bashbasicsbyvk_fileapi_lib.sh"; source "bashbasicsbyvk_staging_pending.sh"; source "bashbasicsbyvk_staging_upload.sh"; source "bashbasicsbyvk_staging_ux.sh"
source "bashbasicsbyvk_staging_svc.sh"; source "bashbasicsbyvk_hidefiles.sh" 2>/dev/null; source "bashbasicsbyvk_settings_ui.sh" 2>/dev/null; source "bashbasicsbyvk_pending.sh"
WORKER_URL="$BASE"; _BB_CURL_OPTS+=(--cacert "$T/cert.pem")
DINONS=$(_bvk_auth_gen_codes 29); FEK_HEX=$(_bvk_auth_gen_fek)
sql "update users set fek_wrapped='$(_bvk_auth_fek_wrap "$FEK_HEX" "$DINONS")'" >/dev/null
_bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="$EMAIL" FILEAPI_BASHBASICS_DISEPS="$DISEPS" FILEAPI_BASHBASICS_KEY="$APIKEY"; P_DINONS="$DINONS"; return 0; }
export FILEAPI_BASHBASICS_PACK_MB=1 FILEAPI_BASHBASICS_PARALLEL=2 FILEAPI_BASHBASICS_RETRY_MIN=2
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1  (got '$2', want '$3')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1  (output: ${2:0:400})" ;; esac; }
blobs_on_server() { curl -s --cacert "$T/cert.pem" "$BASE/__test/r2" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const k=JSON.parse(d);const id=process.argv[1];process.stdout.write(String(k.filter(x=>x.startsWith(id+"/blob/")).length))})' "$1"; }
offline() { curl -s --cacert "$T/cert.pem" "$BASE/__test/offline?sec=$1" >/dev/null; }

mkdir -p "$T/data"; head -c $((48*1024*1024)) /dev/urandom > "$T/data/big.bin"; echo "hello" > "$T/data/small.txt"
SUM=$(sha256sum "$T/data/big.bin" | cut -d' ' -f1)
setbal 1000

# a helper: start an upload (backup service: exercises the kdk path) in its OWN process group, wait for N blobs on the server, kill -9 the group
interrupt_backup_after() {   # $1 = blobs to wait for
  ( cd "$T"; setsid bash -c '
      source "bashbasicsbyvk_auth.sh"; source "bashbasicsbyvk_fileapi_lib.sh"; source "bashbasicsbyvk_staging_pending.sh"; source "bashbasicsbyvk_staging_upload.sh"; source "bashbasicsbyvk_staging_ux.sh"; source "bashbasicsbyvk_staging_svc.sh"
      WORKER_URL="'"$BASE"'"; _BB_CURL_OPTS+=(--cacert "'"$T"'/cert.pem")
      _bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="'"$EMAIL"'" FILEAPI_BASHBASICS_DISEPS="'"$DISEPS"'" FILEAPI_BASHBASICS_KEY="'"$APIKEY"'"; P_DINONS="'"$DINONS"'"; return 0; }
      _SVC_QUIET=1; _svc_upload backup "20102026 1200 resil" "'"$T"'/data/big.bin"; echo "rc=$?" > "'"$T"'/first_rc"
    ' > "$T/first.log" 2>&1 & echo $! > "$T/first.pid" )
  local pid i id n=0; pid=$(cat "$T/first.pid")
  for i in $(seq 1 120); do
    id=$(ls "$(_pn_root)" 2>/dev/null | grep -E '^[A-Za-z0-9_-]{43}$' | head -n1)
    [ -n "$id" ] && n=$(blobs_on_server "$id") || n=0
    [ "${n:-0}" -ge "$1" ] && break; sleep 0.25
  done
  kill -9 -- -"$pid" 2>/dev/null; pkill -9 -f bashbasicsbyvk_staging_pending_xfer 2>/dev/null; sleep 0.5
  PEND_ID="$id"
}

echo "── 1. kill -9 in the middle of an upload ──"
interrupt_backup_after 8
D=$(_pn_dir "$PEND_ID")
[ -s "$D/state" ] && ok "the encrypted blobs and the state survive the kill (kept in $(_pn_root | sed "s|$HOME|~|"))" || bad "no pending folder"
chk "state remembers the kind" "$(_pn_get "$D" kind)" "backup"
has "the server's noter lists it as active with some blobs" "$(curl -s --cacert "$T/cert.pem" -G "$BASE/__test/sql" --data-urlencode "q=select kind,status from pending_ops")" '"status":"active"'
GOT=$(blobs_on_server "$PEND_ID"); NB=$(_pn_get "$D" nblobs)
[ "$GOT" -ge 8 ] && [ "$GOT" -lt "$NB" ] && ok "server holds $GOT of $NB blobs (not finished, not empty)" || bad "server holds $GOT of $NB"
chk "state says: interrupted (the heartbeat is dead)" "$(_pn_status "$D")" "interrupted"
chk "a backup was NOT created yet" "$(q1 "select count(*) from links where svc='backup'")" "0"
chk "kill left no raw key on disk (only the wrapped kdk)" "$(grep -c '^key=' "$D/state")" "0"

echo "── 2. Continue: only the missing blobs are sent ──"
out=$(_pn_continue "$D" 2>&1); rc=$?
chk "continue finishes" "$rc" "0"
has "it says how much was already there" "$out" "already on the server"
has "…and reports the backup" "$out" "Backed up as"
chk "the pending folder is gone" "$([ -d "$D" ] && echo yes || echo no)" "no"
chk "the noter row is gone" "$(q1 "select count(*) from pending_ops")" "0"
chk "exactly one backup exists, all blobs there" "$(q1 "select count(*) from links where svc='backup'")" "1"
BID=$(q1 "select id from links where svc='backup'")
rm -rf "$T/rest1"; mkdir -p "$T/rest1"; _svc_restore backup "$BID" resil "$T/rest1" >/dev/null 2>&1
chk "restored file is byte-identical to the original" "$(sha256sum "$T/rest1/big.bin" 2>/dev/null | cut -d' ' -f1)" "$SUM"

echo "── 3. the connection drops for a while — it continues BY ITSELF ──"
( cd "$T"; rm -f "$T/glitch_rc"; setsid bash -c '
    source "bashbasicsbyvk_auth.sh"; source "bashbasicsbyvk_fileapi_lib.sh"; source "bashbasicsbyvk_staging_pending.sh"; source "bashbasicsbyvk_staging_upload.sh"; source "bashbasicsbyvk_staging_ux.sh"; source "bashbasicsbyvk_staging_svc.sh"
    WORKER_URL="'"$BASE"'"; _BB_CURL_OPTS+=(--cacert "'"$T"'/cert.pem")
    _bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="'"$EMAIL"'" FILEAPI_BASHBASICS_DISEPS="'"$DISEPS"'" FILEAPI_BASHBASICS_KEY="'"$APIKEY"'"; P_DINONS="'"$DINONS"'"; return 0; }
    _SVC_QUIET=1; _svc_upload backup "20102026 1201 glitch" "'"$T"'/data/big.bin"; echo "rc=$?" > "'"$T"'/glitch_rc"
  ' > "$T/glitch.log" 2>&1 & )
for i in $(seq 1 120); do id=$(ls "$(_pn_root)" 2>/dev/null | grep -E '^[A-Za-z0-9_-]{43}$' | head -n1); [ -n "$id" ] && [ "$(blobs_on_server "$id")" -ge 5 ] && break; sleep 0.25; done
before=$(blobs_on_server "$id"); offline 6                      # Wi-Fi off for 6 seconds, in the middle of the transfer
for i in $(seq 1 120); do [ -s "$T/glitch_rc" ] && break; sleep 0.5; done
chk "upload survived a 6 s outage without any user action" "$(cat "$T/glitch_rc" 2>/dev/null)" "rc=0"
chk "…two backups now" "$(q1 "select count(*) from links where svc='backup'")" "2"
chk "nothing left pending" "$(q1 "select count(*) from pending_ops")" "0"
sleep 1

echo "── 4. pause (from another terminal) → resume ──"
curl -s --cacert "$T/cert.pem" "$BASE/__test/slow?ms=250" >/dev/null     # slow server, so there is time to press pause
( cd "$T"; setsid bash -c '
    source "bashbasicsbyvk_auth.sh"; source "bashbasicsbyvk_fileapi_lib.sh"; source "bashbasicsbyvk_staging_pending.sh"; source "bashbasicsbyvk_staging_upload.sh"; source "bashbasicsbyvk_staging_ux.sh"; source "bashbasicsbyvk_staging_svc.sh"
    WORKER_URL="'"$BASE"'"; _BB_CURL_OPTS+=(--cacert "'"$T"'/cert.pem")
    _bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="'"$EMAIL"'" FILEAPI_BASHBASICS_DISEPS="'"$DISEPS"'" FILEAPI_BASHBASICS_KEY="'"$APIKEY"'"; P_DINONS="'"$DINONS"'"; return 0; }
    _SVC_QUIET=1; _svc_upload backup "20102026 1202 pause" "'"$T"'/data/big.bin"; echo "rc=$?" > "'"$T"'/pause_rc"
  ' > "$T/pause.log" 2>&1 & )
for i in $(seq 1 120); do id=$(ls "$(_pn_root)" 2>/dev/null | grep -E '^[A-Za-z0-9_-]{43}$' | head -n1); [ -n "$id" ] && [ "$(blobs_on_server "$id")" -ge 5 ] && break; sleep 0.25; done
D=$(_pn_dir "$id"); out=$(_pn_pause "$id" 2>&1)
has "pause reaches the running transfer" "$out" "Paused"
for i in $(seq 1 30); do [ -s "$T/pause_rc" ] && break; sleep 0.5; done
chk "the running upload ended with 'kept' (rc=4)" "$(cat "$T/pause_rc")" "rc=4"
chk "status is paused (local)" "$(_pn_status "$D")" "paused"
chk "status is paused (server)" "$(q1 "select status from pending_ops where id='$id'")" "paused"
out=$(_pn_continue "$D" 2>&1); chk "resume completes" "$?" "0"
chk "three backups" "$(q1 "select count(*) from links where svc='backup'")" "3"

curl -s --cacert "$T/cert.pem" "$BASE/__test/slow?ms=0" >/dev/null
echo "── 5. stop for good deletes the incomplete blobs ──"
interrupt_backup_after 4
D=$(_pn_dir "$PEND_ID"); [ "$(blobs_on_server "$PEND_ID")" -ge 4 ] && ok "blobs are on the server" || bad "no blobs"
out=$(_pn_stop "$PEND_ID" 2>&1); has "stop says the blobs were deleted" "$out" "deleted from the server"
chk "no blob of it left on the server" "$(blobs_on_server "$PEND_ID")" "0"
chk "local folder removed" "$([ -d "$D" ] && echo yes || echo no)" "no"
chk "row removed" "$(q1 "select count(*) from pending_ops")" "0"
chk "no new backup, nothing charged for it" "$(q1 "select count(*) from links where svc='backup'")" "3"

echo "── 6. stopping a FINISHED upload cannot delete it ──"
out=$(_pn_stop "$BID" 2>&1); has "refused / nothing to stop" "$out" "ℹ️"
chk "the finished backup is still there" "$(q1 "select count(*) from links where svc='backup' and id='$BID'")" "1"

echo "── 7. the Pending menu rows ──"
interrupt_backup_after 3
_pn_srv_load; _pn_ids_of backup
chk "the backup is listed under Backup" "${#_PN_IDS[@]}" "1"
_pn_info "${_PN_IDS[0]}"; chk "…as interrupted, from this computer" "$_I_origin/$_I_status" "here/interrupted"
_pn_ids_of upload; chk "…and not under Upload" "${#_PN_IDS[@]}" "0"

echo "── 8. driven like a user: pn → Backup → the item → Continue now ──"
cat > "$T/menu_drive.py" <<'PYEOF'
import os, pty, sys, time, select
env = dict(os.environ, TERM="xterm", COLUMNS="100", LINES="40")
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("bash", ["bash", os.environ["MENU_SH"]], env)
buf = b""
def pump(t=0.3):
    global buf
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return
            if not d: return
            buf += d
def wait(txt, to=90):
    end = time.time() + to
    while time.time() < end:
        pump(0.2)
        if txt.encode() in buf: return True
    return False
def send(k): os.write(fd, k.encode()); pump(0.4)
ok = wait("Pending FileAPI actions"); send("3\r")
ok = ok and wait("1 pending"[:0] + "Backup"); pump(0.5)
send("1\r"); ok = ok and wait("Continue now"); send("1\r")
ok = ok and wait("Backed up as"); pump(0.5)
send(" "); send("u"); send("u"); send("q"); pump(0.5)
sys.stdout.write(buf.decode("utf8", "replace")); sys.exit(0 if ok else 3)
PYEOF
cat > "$T/menu.sh" <<EOS
cd "$PWD"; export PATH="$PATH"
$(declare -p T BASE EMAIL DISEPS APIKEY DINONS | sed 's/^declare -[-a-zA-Z]* //; s/^/export /')
export HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" FILEAPI_BASHBASICS_PACK_MB=1 FILEAPI_BASHBASICS_PARALLEL=2
source bashbasicsbyvk_auth.sh; source bashbasicsbyvk_fileapi_lib.sh; source bashbasicsbyvk_staging_pending.sh; source bashbasicsbyvk_staging_upload.sh; source bashbasicsbyvk_staging_ux.sh; source bashbasicsbyvk_staging_svc.sh
source bashbasicsbyvk_colors.sh 2>/dev/null; source bashbasicsbyvk_viewport.sh 2>/dev/null; source bashbasicsbyvk_settings_ui.sh; source bashbasicsbyvk_pending.sh
WORKER_URL="$BASE"; _BB_CURL_OPTS+=(--cacert "$T/cert.pem")
_bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="\$EMAIL" FILEAPI_BASHBASICS_DISEPS="\$DISEPS" FILEAPI_BASHBASICS_KEY="\$APIKEY"; P_DINONS="\$DINONS"; return 0; }
pending_menu
EOS
before=$(q1 "select count(*) from links where svc='backup'")
MENU_SH="$T/menu.sh" python3 "$T/menu_drive.py" > "$T/menu.out" 2>&1; mrc=$?
chk "the menu run reached 'Backed up as' by keystrokes alone" "$mrc" "0"
has "the top screen lists the 5 services" "$(cat "$T/menu.out")" "Snapshots"
has "…the item screen offers Continue now / Stop for good" "$(cat "$T/menu.out")" "Stop for good"
chk "the interrupted backup was finished from the menu" "$(q1 "select count(*) from links where svc='backup'")" "$((before+1))"
chk "nothing pending afterwards" "$(q1 "select count(*) from pending_ops")" "0"

echo; echo "RESULT: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
