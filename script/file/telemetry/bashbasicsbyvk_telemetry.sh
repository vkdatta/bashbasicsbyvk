# bashbasicsbyvk anonymous telemetry: counts active unique users per day.
# Sends only: a random UUID (no link to the person/machine), and a country code.
# Opt out:  export BVK_TELEMETRY=off
#
# State lives in  ${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/telemetry/
#   uuid    random id, created once if missing
#   daily   "<UTC date> <true|false>"  -> true = already reported today (idempotent)

_BVK_TELEMETRY_URL="https://telemetry.bashbasics.workers.dev/ping"
_BVK_TELEMETRY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/telemetry"

_bvk_tel_gen_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid
  elif command -v uuidgen >/dev/null 2>&1; then uuidgen | tr 'A-Z' 'a-z'
  elif command -v python3 >/dev/null 2>&1; then python3 -c 'import uuid;print(uuid.uuid4())'
  fi
}

_bvk_telemetry_ping() {
  case "${BVK_TELEMETRY:-on}" in off|0|false|no) return 0 ;; esac
  command -v curl >/dev/null 2>&1 || return 0

  mkdir -p "$_BVK_TELEMETRY_DIR" 2>/dev/null || return 0

  # 1. uuid: create once, only if missing
  local uuid_file="$_BVK_TELEMETRY_DIR/uuid" uuid
  uuid=$(cat "$uuid_file" 2>/dev/null)
  if [[ ! "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    uuid=$(_bvk_tel_gen_uuid)
    [[ "$uuid" =~ ^[0-9a-f-]{36}$ ]] || return 0
    printf '%s\n' "$uuid" > "$uuid_file" 2>/dev/null || return 0
  fi
  # Read-only on disk. This only stops accidents: real tamper-protection is the server-issued
  # signature (sig) below -- an edited/forged id fails verification at the worker.
  chmod 400 "$uuid_file" "$_BVK_TELEMETRY_DIR/sig" 2>/dev/null

  # 2. idempotency flag: already reported today (UTC)?
  local today daily_file="$_BVK_TELEMETRY_DIR/daily" last_date last_flag
  today=$(date -u +%F)
  [ -r "$daily_file" ] && read -r last_date last_flag < "$daily_file"
  if [ "$last_date" = "$today" ] && [ "$last_flag" = "true" ]; then
    _BVK_TELEMETRY_IDEMPOTENT=true
    return 0
  fi
  _BVK_TELEMETRY_IDEMPOTENT=false
  printf '%s false\n' "$today" > "$daily_file" 2>/dev/null

  # 3. first start of the day -> country + send
  local country code
  country=$(curl -s --max-time 4 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]' | tr 'a-z' 'A-Z')
  [[ "$country" =~ ^[A-Z]{2}$ ]] || country="XX"

  local sig_file="$_BVK_TELEMETRY_DIR/sig" sig="" resp
  sig=$(cat "$sig_file" 2>/dev/null)
  resp=$(curl -s --max-time 5 -w '\n%{http_code}' \
    -X POST "$_BVK_TELEMETRY_URL" \
    -H 'Content-Type: application/json' \
    -d "{\"id\":\"$uuid\",\"country\":\"$country\",\"sig\":\"$sig\"}" 2>/dev/null)
  code="${resp##*$'\n'}"
  # first ping: worker answers {"sig":"<hmac of id>"}; keep it (never overwrite an existing one)
  if [ -z "$sig" ]; then
    sig=$(printf '%s' "${resp%$'\n'*}" | sed -n 's/.*"sig"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_-]\{20,128\}\)".*/\1/p')
    [ -n "$sig" ] && { printf '%s\n' "$sig" > "$sig_file" 2>/dev/null; chmod 400 "$sig_file" 2>/dev/null; }
  fi

  # only mark done on success, so a failed send retries on next launch
  [ "$code" = "200" ] && printf '%s true\n' "$today" > "$daily_file" 2>/dev/null
  return 0
}

# Fire-and-forget: never delays or breaks startup.
_bvk_telemetry_start() {
  ( _bvk_telemetry_ping ) >/dev/null 2>&1 &
  disown 2>/dev/null
  return 0
}
