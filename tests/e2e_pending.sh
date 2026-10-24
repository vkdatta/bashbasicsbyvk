#!/usr/bin/env bash
# End-to-end test of RESILIENCE (Pending): interrupted uploads continue, pause / resume / stop, lost connection: the REAL bash client against the REAL worker code
# (in-memory D1/R2, local HTTPS). Needs node >= 22 (node:sqlite), openssl, curl, tar, gzip.
#   bash tests/e2e_pending.sh
E2E_DEFAULT_DIR=/tmp/e2ep; E2E_DEFAULT_PORT=8793
source "$(dirname "${BASH_SOURCE[0]}")/e2e_common.sh"

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
_pend_id() { ls "$(_pn_root)" 2>/dev/null | grep -E '^[A-Za-z0-9_-]{43}$' | head -n1; }
blobs_on_server() { curl -s --cacert "$T/cert.pem" "$BASE/__test/r2" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const k=JSON.parse(d);const id=process.argv[1];process.stdout.write(String(k.filter(x=>x.startsWith(id+"/blob/")).length))})' "$1"; }
_blobs_ge() { local i; i=$(_pend_id); [ -n "$i" ] && [ "$(blobs_on_server "$i")" -ge "$1" ]; }
_no_xfer() { ! pgrep -f bashbasicsbyvk_staging_pending_xfer >/dev/null; }
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
  wait_until 60 "$1 blobs on the server" _blobs_ge "$1"; id=$(_pend_id)
  kill -9 -- -"$pid" 2>/dev/null; pkill -9 -f bashbasicsbyvk_staging_pending_xfer 2>/dev/null; wait_until 10 "the killed transfer to be gone" _no_xfer
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
wait_until 60 "5 blobs on the server" _blobs_ge 5; id=$(_pend_id)
before=$(blobs_on_server "$id"); offline 6                      # Wi-Fi off for 6 seconds, in the middle of the transfer
wait_file 90 "$T/glitch_rc"
chk "upload survived a 6 s outage without any user action" "$(cat "$T/glitch_rc" 2>/dev/null)" "rc=0"
chk "…two backups now" "$(q1 "select count(*) from links where svc='backup'")" "2"
chk "nothing left pending" "$(q1 "select count(*) from pending_ops")" "0"
wait_until 10 "the finished upload process to be gone" _no_xfer

echo "── 4. pause (from another terminal) → resume ──"
curl -s --cacert "$T/cert.pem" "$BASE/__test/slow?ms=250" >/dev/null     # slow server, so there is time to press pause
( cd "$T"; setsid bash -c '
    source "bashbasicsbyvk_auth.sh"; source "bashbasicsbyvk_fileapi_lib.sh"; source "bashbasicsbyvk_staging_pending.sh"; source "bashbasicsbyvk_staging_upload.sh"; source "bashbasicsbyvk_staging_ux.sh"; source "bashbasicsbyvk_staging_svc.sh"
    WORKER_URL="'"$BASE"'"; _BB_CURL_OPTS+=(--cacert "'"$T"'/cert.pem")
    _bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="'"$EMAIL"'" FILEAPI_BASHBASICS_DISEPS="'"$DISEPS"'" FILEAPI_BASHBASICS_KEY="'"$APIKEY"'"; P_DINONS="'"$DINONS"'"; return 0; }
    _SVC_QUIET=1; _svc_upload backup "20102026 1202 pause" "'"$T"'/data/big.bin"; echo "rc=$?" > "'"$T"'/pause_rc"
  ' > "$T/pause.log" 2>&1 & )
wait_until 60 "5 blobs on the server" _blobs_ge 5; id=$(_pend_id)
D=$(_pn_dir "$id"); out=$(_pn_pause "$id" 2>&1)
has "pause reaches the running transfer" "$out" "Paused"
wait_file 30 "$T/pause_rc"
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
out=$(_pn_stop "$BID" 2>&1); has "refused / nothing to stop" "$out" "📜"
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
F = float(os.environ.get('TEST_TIME_FACTOR', '1') or 1)
env = dict(os.environ, TERM="xterm", COLUMNS="100", LINES="40")
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("bash", ["bash", os.environ["MENU_SH"]], env)
buf = b""
def pump(t=0.3, stop=None):
    global buf
    end = time.time() + t
    while True:
        left = end - time.time()
        if left <= 0: return
        r, _, _ = select.select([fd], [], [], min(0.02, left))
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return
            if not d: return
            buf += d
        if stop and stop(): return
def settle(quiet=0.25, ceiling=4.0):          # until the app printed nothing for `quiet` s
    quiet *= F; ceiling *= F
    last = len(buf); since = time.time(); end = time.time() + ceiling
    while time.time() < end:
        pump(0.02)
        if len(buf) != last: last = len(buf); since = time.time()
        elif time.time() - since >= quiet: return
def wait(txt, to=90):                          # until the text has been printed (anywhere in the output so far): max `to` s, no guessed sleep
    pump(to, lambda: txt.encode() in buf); return txt.encode() in buf
def send(k): os.write(fd, k.encode()); settle(0.25, 4.0)
ok = wait("Pending FileAPI actions"); send("3\r")
ok = ok and wait("Backup"); settle()
send("1\r"); ok = ok and wait("Continue now"); send("1\r")
ok = ok and wait("Backed up as"); settle()
send(" "); send("u"); send("u"); send("q")
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
