#!/usr/bin/env bash
# _3bvk_fileapi_lib.sh — the ONE place for the fileapi endpoint, transport hardening and
# credential/response helpers. Sourced by:
#   • cmd/bashbasicsbyvk_copy                          (stand-alone `bashbasicsbyvk_copy`)
#   • file/staging/!buffer/bashbasicsbyvk_staging_fileapi.sh   (uploads/imports inside `o`)
# Keep security-relevant behaviour (TLS opts, no secrets in argv) here so a fix lands everywhere.

WORKER_URL="https://fileapi.bashbasics.workers.dev"

# Credentials now come ONLY from the active -auth profile (no env-var / prompt fallback).
_bb_get_credentials() {
  if [ -z "${_BVK_AUTH_DIR:-}" ]; then
    _BVK_AUTH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth"
  fi
  if ! declare -F _bvk_auth_load_active >/dev/null 2>&1; then
    local _d; _d="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)" 2>/dev/null)"
    # shellcheck disable=SC1090
    source "$_d/../auth/bashbasicsbyvk_auth.sh" 2>/dev/null || source "bashbasicsbyvk_auth.sh" 2>/dev/null
  fi
  if declare -F _bvk_auth_load_active >/dev/null 2>&1 && _bvk_auth_load_active; then
    return 0
  fi
  echo "❌ No active user. Run  -auth  inside 'o' to create or import one." >&2
  return 1
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
  _bb_cfg_header X-User-Email  "$FILEAPI_BASHBASICS_EMAIL"
  _bb_cfg_header X-User-Diseps "$FILEAPI_BASHBASICS_DISEPS"
  _bb_cfg_header X-User-Key    "$FILEAPI_BASHBASICS_KEY"
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
