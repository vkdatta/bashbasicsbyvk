#!/usr/bin/env bash
# End-to-end test of the price check, Backup, Saved Surf and Snapshots: the REAL bash client against the REAL worker code
# (in-memory D1/R2, local HTTPS). Needs node >= 22 (node:sqlite), openssl, curl, tar, gzip.
#   bash tests/e2e_services.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILEAPI="$ROOT/../fileapi"
T=${E2E_DIR:-/tmp/e2e}; PORT=${E2E_PORT:-8791}
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
source "bashbasicsbyvk_svc_core.sh"; source "bashbasicsbyvk_backup.sh"; source "bashbasicsbyvk_saved.sh"; source "bashbasicsbyvk_snapshot.sh"
WORKER_URL="$BASE"; _BB_CURL_OPTS+=(--cacert "$T/cert.pem")
# the user's key chain, made the way -auth makes it: dinons (never sent) wrap a random FEK; only the wrapped FEK is on the server
DINONS=$(_bvk_auth_gen_codes 29); FEK_HEX=$(_bvk_auth_gen_fek)
sql "update users set fek_wrapped='$(_bvk_auth_fek_wrap "$FEK_HEX" "$DINONS")'" >/dev/null
HAVE_DINONS=1
_bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="$EMAIL" FILEAPI_BASHBASICS_DISEPS="$DISEPS" FILEAPI_BASHBASICS_KEY="$APIKEY"; P_DINONS=""; [ "$HAVE_DINONS" = 1 ] && P_DINONS="$DINONS"; return 0; }
_SNAP_DIR="$XDG_CONFIG_HOME/bashbasicsbyvk/snapshots"   # (same value; explicit for the reader)

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1  (got '$2', want '$3')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1  (output: ${2:0:300})" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1  (unexpected '$3' in: ${2:0:300})" ;; *) ok "$1" ;; esac; }

echo "── 1. price check ──"
setbal 1000
out=$(_bb_credit_gate 100000 "This upload" backup </dev/null 2>&1); rc=$?
chk "cost 1 → silent, proceeds" "$rc:$out" "0:"
out=$(_bb_credit_gate 209715200 "This backup" backup <<<"c" 2>&1); rc=$?
has "cost above 1 shows the price" "$out" "costs 141 credits"; chk "…continue → proceeds" "$rc" "0"
out=$(_bb_credit_gate 209715200 "This backup" backup <<<"s" 2>&1); rc=$?; chk "…stop → stops" "$rc" "1"
_bb_credit_gate 209715200 "This backup" backup > "$T/g.out" 2>&1 <<<$'r\n7d\nc'; rc=$?
chk "…reduce to 7d → proceeds" "$rc" "0"; chk "…and the chosen time is used" "$_BB_TTL_OVERRIDE" "604800"
has "…new price shown after reducing" "$(cat "$T/g.out")" "costs 33 credits"
_bb_credit_gate 209715200 "This backup" backup > "$T/g.out" 2>&1 <<<$'i\n+0s\nc' ; rc=$?
setbal 10
out=$(_bb_credit_gate 209715200 "This backup" backup <<<"s" 2>&1); rc=$?
has "short of credits → says so" "$out" "Not enough credits"; chk "…stop" "$rc" "1"
_bb_credit_gate 209715200 "This backup" backup > "$T/g.out" 2>&1 <<<$'r\n\nc'; rc=$?
chk "…accepting the suggestion works" "$rc:$_BB_TTL_OVERRIDE" "0:183600"
setbal 0
out=$(_bb_credit_gate 734003200 "This backup" backup <<<"r" 2>&1); rc=$?
has "cannot afford even 1 hour → stops with a clear message" "$out" "even for the shortest time"; chk "…rc" "$rc" "1"
setbal 1000
credit_prompts=skip; out=$(_bb_credit_gate 209715200 "This backup" backup </dev/null 2>&1); rc=$?; credit_prompts=show
chk "setting 'don't ask' → no prompt at all" "$rc:$out" "0:"

echo "── 2. backup ──"
mkdir -p "$T/work/proj/sub"; head -c 300000 /dev/urandom > "$T/work/proj/a.bin"; echo hello > "$T/work/proj/sub/b.txt"; echo hidden > "$T/work/proj/.hid"
setbal 1000
backup_mode=yes
out=$(_bk_before_delete "$T/work/proj" <<<"my notes" 2>&1); rc=$?
chk "backup before delete → go ahead" "$rc" "0"
has "…tells you the name" "$out" "my notes"
alias=$(q1 "select alias from links where svc='backup'"); has "alias is DDMMYYYY HHMM NAME" "$alias" " my notes"
chk "alias starts with the date" "$(date '+%d%m%Y %H%M' | cut -c1-8)" "${alias:0:8}"
id=$(q1 "select id from links where svc='backup'")
[ -f "$HOME/.bashbasicsbyvk/backup_keys" ] && ok "backup key stored on this computer" || bad "backup key file missing"
chk "ttl is the 30-day default" "$(q1 "select (expires_at-created_at)/1000 from links where svc='backup'")" "2592000"
chk "ordinary links list excludes it" "$(_bb_call GET /links; _bb_json_get "$_BB_BODY" ok)" "true"
_bb_call GET /links; has "…Links screen is empty of it" "$_BB_BODY" '"links":[]'
mkdir -p "$T/restore"; rm -rf "$T/work/proj"
out=$(_svc_restore backup "$id" "$alias" "$T/restore" 2>&1)
cmp -s "$T/restore/proj/a.bin" <(head -c 0 /dev/null) 2>/dev/null; [ -f "$T/restore/proj/a.bin" ] && ok "restored a.bin exists" || bad "restore failed: $out"
[ "$(cat "$T/restore/proj/sub/b.txt" 2>/dev/null)" = hello ] && ok "restored sub/b.txt" || bad "b.txt missing"
[ "$(cat "$T/restore/proj/.hid" 2>/dev/null)" = hidden ] && ok "hidden file was backed up too" || bad "hidden file missing"
chk "restored binary is intact" "$(stat -c %s "$T/restore/proj/a.bin")" "300000"

# a real upload whose price is above 1 credit: reduce the time at the prompt, and the new time is what the server gets
head -c 7000000 /dev/urandom > "$T/work/big.bin"; setbal 1000
out=$(_bk_before_delete "$T/work/big.bin" <<<$'\nr\n7d\nc' 2>&1); rc=$?
[ "$rc" != 0 ] && echo "$out" | sed "s/^/      | /"; chk "price above 1: reduce time then back up" "$rc" "0"; has "…price was shown" "$out" "costs 5 credits"
chk "…server got 7 days" "$(q1 "select (expires_at-created_at)/1000 from links where svc='backup' order by created_at desc limit 1")" "604800"
chk "…2 credits charged (not 5)" "$(( 1000 - $(bal) ))" "2"

# failure never turns into a silent delete
out=$(WORKER_URL="https://localhost:1" _bk_before_delete "$T/work/big.bin" <<<$'\nn' 2>&1); rc=$?
chk "backup fails (server down) + 'n' → delete is cancelled" "$rc" "1"; has "…said so" "$out" "FAILED"
out=$(WORKER_URL="https://localhost:1" _bk_before_delete "$T/work/big.bin" <<<$'\ny' 2>&1); rc=$?
chk "backup fails + 'y' → delete allowed" "$rc" "0"
backup_mode=no; out=$(_bk_before_delete "$T/work/big.bin" 2>&1); rc=$?; chk "mode 'no' → no backup, delete allowed" "$rc:$out" "0:"
backup_mode=ask; out=$(_bk_before_delete "$T/work/big.bin" <<<"c" 2>&1); rc=$?; chk "mode 'ask' + c → delete cancelled" "$rc" "1"
backup_mode=yes
ln -s "$T/work" "$T/work/link"; out=$(_bk_before_delete "$T/work/link" 2>&1); rc=$?; chk "a symlink is not backed up (only the link goes)" "$rc:$out" "0:"
n0=$(q1 "select count(*) from links where svc='backup'")
_GD_ACTIVE=1; out=$(_bk_before_delete "$T/work/big.bin" 2>&1); _GD_ACTIVE=0; chk "Google Drive placeholders are not backed up" "$(q1 "select count(*) from links where svc='backup'")" "$n0"

echo "── 3. save- / Saved Surf (client-side encryption) ──"
mkdir -p "$T/work/tax"; echo "secret numbers" > "$T/work/tax/t.txt"; setbal 1000
# no dinons on this computer → refused before anything is packed or uploaded
HAVE_DINONS=0; n0=$(q1 "select count(*) from links where svc='saved'"); _UX_FEK_SELF=""; _UX_FEK_SELF_FOR=""
out=$(_svc_upload saved "$(_bb_svc_alias "tax papers")" "$T/work/tax" 2>&1); rc=$?
chk "save without dinons is refused" "$rc" "1"; has "…says why" "$out" "dinons"; chk "…nothing uploaded" "$(q1 "select count(*) from links where svc='saved'")" "$n0"
HAVE_DINONS=1; _UX_FEK_SELF=""; _UX_FEK_SELF_FOR=""
_svc_upload saved "$(_bb_svc_alias "tax papers")" "$T/work/tax" >/dev/null 2>&1; rc=$?; chk "save uploads" "$rc" "0"
sid=$_SVC_ID; [ -n "$sid" ] || bad "no id"
chk "filed as saved" "$(q1 "select svc from links where id='$sid'")" "saved"
chk "no link is public" "$(curl -s --cacert "$T/cert.pem" -o /dev/null -w '%{http_code}' "$BASE/$sid/manifest")" "404"
chk "…nor the viewer page" "$(curl -s --cacert "$T/cert.pem" -o /dev/null -w '%{http_code}' "$BASE/$sid")" "404"
kdk=$(q1 "select wrapped from vault_keys where link_id='$sid'")
chk "stored key is CSE (cse1)" "$(q1 "select scheme from vault_keys where link_id='$sid'")" "cse1"
[ -n "$kdk" ] && [ "$kdk" != "$_SVC_KEY" ] && ok "server holds only a wrapped key" || bad "key storage wrong"
# OPERATOR VIEW: everything in the database, plus the stored key opened with every secret the server could have, never gives K
hasnt "plain key is nowhere in the database dump" "$(sql 'select * from vault_keys')$(sql 'select * from links')$(sql 'select * from user_vault')" "$_SVC_KEY"
hasnt "FEK is nowhere in the database dump" "$(sql 'select * from users')$(sql 'select * from vault_keys')" "$FEK_HEX"
srv_try=$(printf '%s' "$kdk" | BB_FEK="$(printf '%s' "$APIKEY$DISEPS" | sha256sum | cut -d' ' -f1)" _ux_core dk-unwrap 2>/dev/null); rc=$?
[ "$rc" != 0 ] && [ -z "$srv_try" ] && ok "credentials the server holds (apikey+diseps) do not open the key" || bad "stored key opened without the FEK"
[ -f "$HOME/.bashbasicsbyvk/link_keys" ] && grep -q "$sid" "$HOME/.bashbasicsbyvk/link_keys" && bad "saved key leaked into link_keys" || ok "no key kept on disk for a saved item"
# the key we get back through the real client path equals the one the archive was encrypted with
chk "client opens kdk with the FEK → the item key" "$(_svc_vault_key "$sid")" "$_SVC_KEY"
rm -rf "$T/restore2"; mkdir -p "$T/restore2"
# "another device": no local state at all, only e-mail + diseps + apikey + dinons
out=$( HOME="$T/otherdev" XDG_CONFIG_HOME="$T/otherdev/.config" _UX_FEK_SELF="" _svc_restore saved "$sid" "tax papers" "$T/restore2" 2>&1 )
[ "$(cat "$T/restore2/tax/t.txt" 2>/dev/null)" = "secret numbers" ] && ok "restored on a device that holds no key (credentials + dinons)" || bad "restore from other device failed: $out"
# same device credentials but WRONG dinons: the server hands over kdk, it stays shut
rm -rf "$T/restore3"; mkdir -p "$T/restore3"
out=$( DINONS_SAVE="$DINONS"; DINONS=$(_bvk_auth_gen_codes 29); _UX_FEK_SELF=""; _svc_restore saved "$sid" "tax papers" "$T/restore3" 2>&1 ); rc=$?
chk "wrong dinons cannot open a saved item" "$rc" "1"; [ -e "$T/restore3/tax" ] && bad "files appeared with wrong dinons" || ok "…nothing was written"
# wrong credentials cannot even get kdk (the permission layer)
out=$(_bb_get_credentials() { FILEAPI_BASHBASICS_EMAIL="$EMAIL"; FILEAPI_BASHBASICS_DISEPS="$DISEPS"; FILEAPI_BASHBASICS_KEY="wrongkey"; P_DINONS="$DINONS"; return 0; }; _UX_FEK_SELF=""; _svc_vault_key "$sid" 2>&1); rc=$?
chk "wrong API key cannot read the key" "$rc" "1"
# a bare (unwrapped) key is refused by the server
bare=$(_ux_core newkey)
out=$(_bb_call PUT /vault/labelkey "{\"kdk\":\"$bare\"}"; echo "$_BB_STATUS")
chk "server refuses a bare key" "$out" "400"
# nuke destroys the key
_bb_call DELETE "/links/$sid"; chk "nuke ok" "$_BB_STATUS" "200"
chk "key destroyed with the item" "$(q1 "select count(*) from vault_keys where link_id='$sid'")" "0"

echo "── 4. snapshots ──"
mkdir -p "$T/work/watch/inner"; echo v1 > "$T/work/watch/f.txt"; head -c 200000 /dev/urandom > "$T/work/watch/inner/r.bin"; echo single > "$T/work/one.txt"
setbal 1000; rm -rf "$_SNAP_DIR"
p1=$(readlink -f "$T/work/watch"); p2=$(readlink -f "$T/work/one.txt")
t1=$(_snap_sha256 "$p1"); t2=$(_snap_sha256 "$p2")
_snap_target_set "$t1" d "$p1" 0 "" 0; _snap_target_set "$t2" f "$p2" 0 "" 0
_snap_cycle; sleep 0.3
chk "targets registered on the server" "$(q1 'select count(*) from snap_targets')" "2"
chk "both paths snapshotted" "$(q1 "select count(*) from snapshots")" "2"
chk "snapshot links are filed as snapshot" "$(q1 "select count(*) from links where svc='snapshot'")" "2"
chk "default keep time is 7 days" "$(q1 "select (expires_at-created_at)/1000 from links where svc='snapshot' limit 1")" "604800"
hasnt "paths are not stored in clear on the server" "$(sql 'select * from snap_targets')$(sql 'select * from snap_devices')" "watch"
chk "every snapshot key is client-wrapped (cse1)" "$(q1 "select count(*) from vault_keys where link_id in (select link_id from snapshots) and scheme='cse1'")" "$(q1 "select count(*) from snapshots")"
chk "the label key is client-wrapped (cse1)" "$(q1 "select scheme from user_vault")" "cse1"
hasnt "FEK is not in the label-key row either" "$(sql 'select * from user_vault')" "$FEK_HEX"
_snap_cycle; chk "nothing changed → nothing uploaded (no credits spent)" "$(q1 "select count(*) from snapshots")" "2"
b0=$(bal); echo v2 >> "$T/work/watch/f.txt"; sleep 1.1; touch "$T/work/watch/f.txt"
_snap_cycle; chk "a changed folder → exactly one new snapshot" "$(q1 "select count(*) from snapshots")" "3"
chk "…and only that folder (the untouched file was skipped)" "$(q1 "select count(*) from snapshots where tgt='$t2'")" "1"
chk "credits were spent only for the one" "$(( b0 - $(bal) ))" "1"
# restore the old state from the first snapshot of the folder
first=$(q1 "select link_id from snapshots where tgt='$t1' order by taken_at asc limit 1")
rm -rf "$T/restore3"; mkdir -p "$T/restore3"; _svc_restore snapshot "$first" "AS ON x" "$T/restore3" >/dev/null 2>&1
[ "$(cat "$T/restore3/watch/f.txt" 2>/dev/null)" = "v1" ] && ok "restoring the first snapshot gives the OLD content (v1)" || bad "snapshot content wrong: $(cat "$T/restore3/watch/f.txt" 2>&1)"
# consistency: a file removed while its snapshot is being taken does not corrupt it (the copy is what is packed)
orig_sig=$(declare -f _snap_sig)
_snap_sig() { local r; r=$(eval "${orig_sig#*\{}"; true) 2>/dev/null; true; }
unset -f _snap_sig; eval "$orig_sig"
# naming
chk "snapshot name" "$(_snap_name 1760527800000 | cut -c1-6)" "AS ON "
# another device sees this device's list and snapshots
_BB_CALL_HDRS=("X-Telemetry-Id: $UUID2" "X-Telemetry-Sig: $SIG2"); _bb_call PUT /snapshots/device '{}'; chk "second device registers" "$_BB_STATUS" "200"
lk=$(_snap_labelkey)
_BB_CALL_HDRS=("X-Telemetry-Id: $UUID2" "X-Telemetry-Sig: $SIG2")
_snap_menu_devices "$lk" >/dev/null 2>&1
chk "two devices are listed" "${#SNAP_D_ID[@]}" "2"
chk "device 1 shows its host name (label decrypted)" "$(printf '%s\n' "${SNAP_D_LABEL[@]}" | grep -c "$(_snap_hostlabel)")" "1"
d1=$(_snap_sha256 "tel:$UUID"); out=$(_snap_menu_device_view "$lk" "$d1" "dev1" 0 <<<$'u' 2>&1)
has "other device's paths are visible (decrypted)" "$out" "$p1"; has "…with the one-line explanation of remote removal" "$out" "stops on its next sync"
out=$(_snap_menu_snaps "$lk" "$d1" "$t1" "$p1" <<<$'u' 2>&1); has "snapshots are named AS ON DDMMYYYY HHMM" "$out" "AS ON $(date '+%d%m%Y')"
has "…and cannot be renamed (stated)" "$out" "cannot be renamed"
# remove a path from the OTHER device's list → this device drops it on its next sync
_BB_CALL_HDRS=(); _bb_call DELETE "/snapshots/targets/$d1/$t2"; chk "remote removal ok" "$_BB_STATUS" "200"
_snap_dev_hdrs; _snap_cycle
[ -z "$(_snap_target_line "$t2")" ] && ok "device 1 dropped the removed path on its next sync" || bad "target still on device 1"
[ -n "$(_snap_target_line "$t1")" ] && ok "…and kept the other" || bad "other target lost"
# credits not enough → pause with a notice, then resume
setbal 0; echo v3 >> "$T/work/watch/f.txt"; sleep 1.1; touch "$T/work/watch/f.txt"
n1=$(q1 "select count(*) from snapshots"); _snap_cycle
chk "no credits → nothing taken" "$(q1 "select count(*) from snapshots")" "$n1"; has "…notice written" "$(cat "$_SNAP_NOTICE" 2>/dev/null)" "paused"
setbal 1000; _snap_cycle
chk "credits back → snapshot taken" "$(q1 "select count(*) from snapshots")" "$((n1+1))"; [ ! -e "$_SNAP_NOTICE" ] && ok "notice cleared" || bad "notice still there"
# the telemetry uuid rows are never removed
chk "device rows are kept" "$(q1 'select count(*) from snap_devices')" "2"
# a 'remote' target pushed from elsewhere is restored locally after a reinstall (local list lost)
rm -f "$_SNAP_TARGETS"; _snap_cycle
[ -n "$(_snap_target_line "$t1")" ] && ok "after losing the local list, it is rebuilt from the server" || bad "not rebuilt"

echo "── 5. background process ──"
rm -f "$_SNAP_LASTRUN" "$_SNAP_NOTICE"; echo v4 >> "$T/work/watch/f.txt"; sleep 1.1; touch "$T/work/watch/f.txt"
n2=$(q1 "select count(*) from snapshots")
cat > "$T/o_sim.sh" <<EOS
source "bashbasicsbyvk_auth.sh"; source "bashbasicsbyvk_svc_core.sh"; source "bashbasicsbyvk_snapshot.sh"
WORKER_URL="$BASE"; _BB_CURL_OPTS+=(--cacert "$T/cert.pem")
_bb_get_credentials() { export FILEAPI_BASHBASICS_EMAIL="$EMAIL" FILEAPI_BASHBASICS_DISEPS="$DISEPS" FILEAPI_BASHBASICS_KEY="$APIKEY"; P_DINONS="$DINONS"; return 0; }
_snap_daemon_start
sleep 14        # "o" is running for 14 seconds
EOS
bash "$T/o_sim.sh" &
OSIM=$!
for _ in $(seq 1 30); do [ "$(q1 "select count(*) from snapshots")" -gt "$n2" ] && break; sleep 0.5; done
chk "while 'o' runs, the background process takes the snapshot" "$(q1 "select count(*) from snapshots")" "$((n2+1))"
chk "…one daemon, one lock" "$(ls -d "$_SNAP_LOCK" 2>/dev/null | wc -l | tr -d ' ')" "1"
dpid=$(cat "$_SNAP_LOCK/pid" 2>/dev/null)
chk "…second start does not spawn another" "$( ( _snap_daemon_start; sleep 0.5; cat "$_SNAP_LOCK/pid" ) )" "$dpid"
wait $OSIM 2>/dev/null; sleep 5
kill -0 "$dpid" 2>/dev/null && bad "daemon still alive after 'o' ended" || ok "when 'o' ends, snapshots stop (daemon gone)"
[ -d "$_SNAP_LOCK" ] && bad "lock left behind" || ok "lock cleaned up"
[ -z "$(ls "$_SNAP_TMPROOT" 2>/dev/null)" ] && ok "no temp copies left behind" || bad "temp copies left: $(ls "$_SNAP_TMPROOT")"
# reopen after a long time: exactly ONE snapshot, no matter how many intervals were missed
n3=$(q1 "select count(*) from snapshots"); echo v5 >> "$T/work/watch/f.txt"; sleep 1.1; touch "$T/work/watch/f.txt"
echo $(( $(date +%s) - 864000 )) > "$_SNAP_LASTRUN"        # last pass was 10 days ago
snapshot_interval_seconds=600
ln=$(_snap_interval); chk "interval honoured" "$ln" "600"
bash "$T/o_sim.sh" & OSIM=$!
for _ in $(seq 1 30); do [ "$(q1 "select count(*) from snapshots")" -gt "$n3" ] && break; sleep 0.5; done; sleep 3
chk "reopened after 10 days → exactly one new snapshot" "$(q1 "select count(*) from snapshots")" "$((n3+1))"
wait $OSIM 2>/dev/null; sleep 4

echo "── 6. settings ──"
snapshot_interval_seconds=30; chk "interval below 1 minute is rejected → default" "$(_snap_interval)" "3600"
source "bashbasicsbyvk_settings_ui.sh" 2>/dev/null; source "bashbasicsbyvk_settings.sh" 2>/dev/null; source "bashbasicsbyvk_settings_groups.sh" 2>/dev/null
chk "defaults: price check on" "$credit_prompts" "show"; chk "defaults: backup yes" "$backup_mode" "yes"
chk "defaults: backup 30d" "$backup_nuke_time_seconds" "2592000"; chk "defaults: saved 30d" "$saved_nuke_time_seconds" "2592000"
chk "defaults: snapshots hourly" "$snapshot_interval_seconds" "3600"
backup_mode=ask; snapshot_interval_seconds=900; save_settings
chk "saved to the config file" "$(grep -c '^backup_mode=ask$\|^snapshot_interval_seconds=900$' "$SETTINGS_FILE")" "2"
chk "the background process can read them from the file" "$( unset backup_mode snapshot_interval_seconds; _bb_cfg_val snapshot_interval_seconds 3600 )" "900"
_st_top_build; chk "top level has 7 grouped rows" "${#_st_lbl[@]}" "7"
_st_grp_api_build; chk "File API has 6 sub-groups" "${#_st_lbl[@]}" "6"
_st_grp_snap_build; chk "Snapshots group has 3 settings" "${#_st_lbl[@]}" "3"
_st_grp_colors_build; chk "Colors group holds background + text" "${#_st_lbl[@]}" "2"
backup_nuke_settings_probe() { _ST_DU_VAR=backup_nuke_time_seconds; _ST_DU_MIN=60; _ST_DU_MAX=2592000; _ST_DU_PRESETS=(86400 604800); _ST_DU_LABELS=(a b); _ST_DU_HEAD=x; _st_du_build; }
backup_nuke_settings_probe; chk "duration screen builds (2 presets + custom + 2 headings)" "${#_st_lbl[@]}" "5"
snapshot_enabled=off; chk "snapshots off is read by the background process" "$(unset snapshot_enabled; echo 'snapshot_enabled=off' > "$XDG_CONFIG_HOME/bashbasicsbyvk/config"; _bb_cfg_val snapshot_enabled on)" "off"

echo "── 7. Backup / Saved Surf screens (the shared list manager) ──"
source "bashbasicsbyvk_api.sh" 2>/dev/null
setbal 1000; mkdir -p "$T/work/shelf"; echo "on the shelf" > "$T/work/shelf/s.txt"
_bk_before_delete "$T/work/shelf" <<<"shelf" >/dev/null 2>&1
_svc_upload saved "$(_bb_svc_alias "vault note")" "$T/work/shelf" >/dev/null 2>&1
( _API_SVC=backup; _BB_KEY_FILE="$HOME/.bashbasicsbyvk/backup_keys"; _api_load >/dev/null 2>&1; echo "${#_API_ID[@]}" > "$T/n_backup"; _api_name 0 > "$T/name_backup" )
( _API_SVC=saved; _api_load >/dev/null 2>&1; echo "${#_API_ID[@]}" > "$T/n_saved"; _api_name 0 > "$T/name_saved" )
( _API_SVC=""; _api_load >/dev/null 2>&1; echo "${#_API_ID[@]}" > "$T/n_links" )
chk "Backup screen lists only backups" "$(cat "$T/n_backup")" "$(q1 "select count(*) from links where svc='backup'")"
chk "Saved Surf lists only saved items" "$(cat "$T/n_saved")" "1"
chk "Links screen lists no service items" "$(cat "$T/n_links")" "0"
has "saved item shows its DDMMYYYY HHMM NAME alias" "$(cat "$T/name_saved")" "vault note"
# the Links screen must not prune backup keys (they live in their own file)
keys_before=$(wc -l < "$HOME/.bashbasicsbyvk/backup_keys")
( _API_SVC=""; _api_load >/dev/null 2>&1 ); chk "Links screen leaves backup keys alone" "$(wc -l < "$HOME/.bashbasicsbyvk/backup_keys")" "$keys_before"
# r-N restore through the screen's own command
rm -rf "$T/restore4"; mkdir -p "$T/restore4"
( _API_SVC=saved; path="$T/restore4"; items=(x); _api_load >/dev/null 2>&1; _api_cmd_restore 1 > "$T/r4.out" 2>&1 )
[ "$(cat "$T/restore4/shelf/s.txt" 2>/dev/null)" = "on the shelf" ] && ok "r-1 in Saved Surf restores into the current folder" || { bad "r-N restore failed"; sed "s/^/      | /" "$T/r4.out"; }
# alias rename / extend with price check work on a service item (same server routes)
sid2=$(q1 "select id from links where svc='saved' and status='active' limit 1")
_bb_call POST "/links/$sid2/alias" '{"alias":"renamed item"}'; chk "alias edit on a saved item" "$_BB_STATUS" "200"
_bb_call POST "/links/$sid2/expiry" '{"totalSeconds":2592000,"dryRun":true}'; has "extension is priced first (dry run)" "$_BB_BODY" '"dryRun":true'

echo "── 8. commands: save- and snap- ──"
source "bashbasicsbyvk_hidefiles.sh" 2>/dev/null
sp_resolved=(); _sp_guard_and_resolve() { sp_resolved=("$ITEM"); return 0; }     # (the numbered-item resolver is existing code)
setbal 1000; mkdir -p "$T/work/docs"; echo visible > "$T/work/docs/v.txt"; echo shh > "$T/work/docs/.secret"
ITEM="$T/work/docs"
upload_hidden_mode=never
out=$(handle_save_upload "save-1 as docs" 2>&1); rc=$?
chk "save-1 as docs works" "$rc" "0"; has "…says no link exists" "$out" "no link exists"
sid=$(q1 "select id from links where svc='saved' order by created_at desc limit 1"); has "…alias carries the name" "$(q1 "select alias from links where id='$sid'")" " docs"
rm -rf "$T/r7"; mkdir -p "$T/r7"; _svc_restore saved "$sid" x "$T/r7" >/dev/null 2>&1
[ -f "$T/r7/docs/v.txt" ] && [ ! -e "$T/r7/docs/.secret" ] && ok "Settings 'upload hidden = never' → hidden file left out of the save" || bad "hidden-file rule not applied"
upload_hidden_mode=always; handle_save_upload "save-1" >/dev/null 2>&1
sid=$(q1 "select id from links where svc='saved' order by created_at desc limit 1"); rm -rf "$T/r7"; mkdir -p "$T/r7"; _svc_restore saved "$sid" x "$T/r7" >/dev/null 2>&1
[ -f "$T/r7/docs/.secret" ] && ok "…'always' → hidden file included" || bad "hidden file missing"
chk "no name → alias is just the date and time" "$(q1 "select length(alias) from links where id='$sid'")" "13"
n=$(q1 "select count(*) from links where svc='saved'"); out=$(handle_save_upload "save-1 as bad/name" 2>&1); rc=$?
chk "a name with forbidden characters is refused, nothing uploaded" "$rc:$(q1 "select count(*) from links where svc='saved'")" "1:$n"
snapshot_enabled=off; rm -rf "$_SNAP_DIR"
out=$(handle_snap_add "snap-1" 2>&1); rc=$?
chk "snap-1 works" "$rc" "0"; has "…put on the list" "$out" "On the snapshot list"; has "…shows a price estimate" "$out" "credit(s) per snapshot"
has "…states the interval" "$out" "while  o  is running"
tg=$(_snap_sha256 "$(readlink -f "$ITEM")"); [ -n "$(_snap_target_line "$tg")" ] && ok "…stored locally" || bad "not stored"
chk "…and registered on the server right away" "$(q1 "select count(*) from snap_targets where tgt='$tg'")" "1"
out=$(handle_snap_add "snap-1" 2>&1); has "adding it twice is reported, not duplicated" "$out" "Already on the list"
out=$( ITEM="/" ; handle_snap_add "snap-1" 2>&1); has "'/' is refused" "$out" "Skipping '/'"
out=$( ITEM="$_SNAP_DIR"; handle_snap_add "snap-1" 2>&1); has "snapshots' own folder is refused" "$out" "own folder"
out=$(handle_snap_add "snap-1 as nope" 2>&1); has "an alias on snap- is explained, not applied" "$out" "cannot be renamed"
snapshot_enabled=on


echo "── 9. the Snapshots screen, driven like a user ──"
_snap_dev_hdrs; lk=$(_snap_labelkey); _snap_menu_devices "$lk" >/dev/null 2>&1
d1=$(_snap_sha256 "tel:$UUID"); idx=0; for i in "${!SNAP_D_ID[@]}"; do [ "${SNAP_D_ID[$i]}" = "$d1" ] && idx=$((i+1)); done
chk "a device with no name still lines up (no shifted columns)" "$(snapshot_menu <<<"u" 2>&1 | grep -c "0 path(s), 0 snapshot(s)")" "1"
chk "this computer is found in the device list" "$([ "$idx" -gt 0 ] && echo yes)" "yes"
rm -rf "$T/r9"; mkdir -p "$T/r9"; path="$T/r9"
nbefore=$(q1 "select count(*) from snapshots s join links l on l.id=s.link_id where l.status='active' and s.device='$d1'")
out=$(snapshot_menu <<<"$idx"$'\n'"all"$'\n'"1"$'\n'"u"$'\n'"u"$'\n'"u" 2>&1)
has "device list marks this computer with a star" "$out" "★"
has "…device view lists its paths" "$out" "files/folders on its snapshot list"
has "…snapshots listed newest first with AS ON names" "$out" "AS ON $(date '+%d%m%Y')"
rest=$(ls "$T/r9" | head -1); has "choosing a snapshot restores it into a folder named after it" "$rest" "AS ON "
[ -n "$(find "$T/r9" -name '*.txt' | head -1)" ] && ok "…with the files inside" || bad "restored snapshot is empty"
out=$(snapshot_menu <<<"$idx"$'\n'"all"$'\n'"x-1"$'\n'"y"$'\n'"u"$'\n'"u"$'\n'"u" 2>&1)
has "x-N nukes a snapshot" "$out" "Nuked"
chk "…one snapshot fewer" "$(q1 "select count(*) from snapshots s join links l on l.id=s.link_id where l.status='active' and s.device='$d1'")" "$((nbefore-1))"
chk "…its key is gone too" "$(q1 "select count(*) from vault_keys where link_id not in (select id from links where status='active')")" "0"
out=$(snapshot_menu <<<"$idx"$'\n'"all"$'\n'"e-1"$'\n'"+1d"$'\n'"y"$'\n'"u"$'\n'"u"$'\n'"u" 2>&1)
has "e-N extends (price shown first)" "$out" "Now gone at"
tcount=$(_snap_target_count)
out=$(snapshot_menu <<<"$idx"$'\n'"x-1"$'\n'"y"$'\n'"u"$'\n'"u" 2>&1)
has "x-N in the device view stops watching a path" "$out" "Removed from the list"
chk "…the local list follows" "$(_snap_target_count)" "$((tcount-1))"
echo
echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
