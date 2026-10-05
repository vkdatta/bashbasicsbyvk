#!/usr/bin/env bash
# _3bvk_fileapi_lib.sh — the ONE place for the fileapi endpoint, transport hardening and
# credential/response helpers. Sourced by:
#   • cmd/bashbasicsbyvk_copy                          (stand-alone `bashbasicsbyvk_copy`)
#   • file/staging/!buffer/bashbasicsbyvk_staging_fileapi.sh   (uploads/imports inside `o`)
# Keep security-relevant behaviour (TLS opts, no secrets in argv) here so a fix lands everywhere.

WORKER_URL="https://fileapi.bashbasics.workers.dev"

_bb_get_credentials() {
  local email="${FILEAPI_BASHBASICS_EMAIL:-}"
  local apikey="${FILEAPI_BASHBASICS_KEY:-}"

  if [ -z "$email" ] || [ -z "$apikey" ]; then
    if [ ! -t 0 ]; then
      echo "❌ Error: fileapi.bashbasics.email / fileapi.bashbasics.key are not set, and no terminal is available to prompt for them."
      echo "   Set them with: export FILEAPI_BASHBASICS_EMAIL=you@example.com; export FILEAPI_BASHBASICS_KEY=your_api_key"
      return 1
    fi
    echo "🔑 No saved credentials found (FILEAPI_BASHBASICS_EMAIL / FILEAPI_BASHBASICS_KEY)."
    [ -z "$email" ] && read -p "   Enter email: " email
    if [ -z "$apikey" ]; then
      read -s -p "   Enter API key: " apikey
      echo
    fi
    if [ -z "$email" ] || [ -z "$apikey" ]; then
      echo "❌ Email and API key are both required."
      return 1
    fi
    export FILEAPI_BASHBASICS_EMAIL="$email"
    export FILEAPI_BASHBASICS_KEY="$apikey"
    echo "ℹ️  Using these for the rest of this session. Export them yourself beforehand to skip this prompt next time."
  fi
  return 0
}

# ---- transport hardening ---------------------------------------------------
# HTTPS only, TLS>=1.2, never follow redirects (a redirect could carry headers elsewhere).
_BB_CURL_OPTS=(--proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 0)

# Secrets must never appear in argv (visible to every local user via `ps`).
# They are fed to curl as a config file on stdin:  curl -K - ... <<< "$cfg"
_bb_cfg_escape() {
  local v="$1"
  v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/}; v=${v//$'\r'/}
  printf '%s' "$v"
}
_bb_cfg_header() { printf 'header = "%s: %s"\n' "$1" "$(_bb_cfg_escape "$2")"; }
_bb_auth_cfg() {
  _bb_cfg_header X-User-Email "$FILEAPI_BASHBASICS_EMAIL"
  _bb_cfg_header X-User-Key   "$FILEAPI_BASHBASICS_KEY"
}

_bb_json_get() {
  local json="$1" field="$2"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      try {
        const o = JSON.parse(d);
        process.stdout.write(o[process.argv[1]] !== undefined ? String(o[process.argv[1]]) : "");
      } catch (e) {}
    });
  ' "$field" <<< "$json"
}

_bb_fail_reason() {
  local body="$1" http_status="$2"
  local reason
  reason=$(_bb_json_get "$body" message)
  if [ -n "$reason" ]; then
    printf '%s' "$reason"
    return
  fi
  local trimmed
  trimmed=$(printf '%s' "$body" | tr '\n\r' '  ' | sed 's/  */ /g; s/^ *//; s/ *$//')
  if [ -n "$trimmed" ]; then
    printf 'HTTP %s: %s' "$http_status" "${trimmed:0:300}"
  else
    printf 'Request failed (HTTP %s)' "$http_status"
  fi
}
