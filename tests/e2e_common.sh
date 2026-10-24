#!/usr/bin/env bash
# Shared set-up of the two end-to-end tests (e2e_pending.sh, e2e_services.sh): temp dir + local HTTPS cert, the REAL worker
# code as a local server, the owner's test identity, the sql/setbal/bal helpers and the cleanup trap. SOURCE it, don't run it.
# The caller sets E2E_DEFAULT_DIR and E2E_DEFAULT_PORT first (each test has its own, so both can run side by side).
# Everything that is the same in both tests lives HERE — change it once, not twice.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/wait_lib.sh"   # UTF-8 locale + wait_until / wait_file / wait_gone / settle (no fixed sleeps)
FILEAPI="${FILEAPI:-$ROOT/../fileapi}"
T=${E2E_DIR:-${E2E_DEFAULT_DIR:?}}; PORT=${E2E_PORT:-${E2E_DEFAULT_PORT:?}}
rm -rf "$T/home" "$T/info.json"; mkdir -p "$T/home"
[ -f "$T/cert.pem" ] || openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/key.pem" -out "$T/cert.pem" -days 2 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/dev/null 2>&1

export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_CACHE_HOME="$T/home/.cache" NODE_EXTRA_CA_CERTS="$T/cert.pem" NODE_NO_WARNINGS=1
mkdir -p "$XDG_CONFIG_HOME/bashbasicsbyvk" "$HOME/.bashbasicsbyvk"
export PATH="$(find "$ROOT/script" -type d | paste -sd: -):$PATH"

( cd "$FILEAPI/test" && node --experimental-sqlite e2e_server.mjs "$PORT" "$T/cert.pem" "$T/key.pem" "$T/info.json" 1000 ) > "$T/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null; pkill -f "e2e_server.mjs $PORT" 2>/dev/null; true' EXIT
WAIT_DUMP="cat $T/server.log" wait_grep 15 "$T/server.log" ready || { echo "server did not start"; exit 1; }; WAIT_DUMP=

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
