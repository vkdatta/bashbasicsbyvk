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

# ════════════════════════════════════════════════════════════════════════════
#  Nuke time, aliases and credit estimates (shared by up- / c2c- / the api loop / Settings)
# ════════════════════════════════════════════════════════════════════════════
#
#  Pricing (mirrors the worker, fileapi/src/ledger.js — the server is the authority):
#     1 credit per GB per hour, whole credits, with a minimum charge by size bucket:
#        0-5 MB: 1 per month · 6-50 MB: 1 per week · 51-500 MB: 1 per day · >500 MB: 1 per hour
#     anything shorter than 1 hour is billed as 1 hour.   The WHOLE nuke time is paid up front.
#     Refunds (shorten / nuke from  api) come back in whole days only; time already used rounds UP to a day.

_BB_NUKE_DEFAULT=3600            # 1 hour
_BB_NUKE_MIN=60                  # 1 minute  (billed as 1 hour)
_BB_NUKE_MAX=$((30*86400))       # 30 days

# The nuke time to send: the Settings value (nuke_time_seconds) when the app has loaded it, else the
# config file (so stand-alone scripts honour it too), else 1 hour.
_bb_nuke_seconds() {
  local v="${nuke_time_seconds:-}"
  if [ -z "$v" ]; then
    local cf="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/config"
    [ -r "$cf" ] && v=$(sed -n 's/^nuke_time_seconds=\([0-9]\{1,9\}\)$/\1/p' "$cf" 2>/dev/null | tail -n 1)
  fi
  if [[ "$v" =~ ^[0-9]{1,9}$ ]] && [ "$v" -ge "$_BB_NUKE_MIN" ] && [ "$v" -le "$_BB_NUKE_MAX" ]; then
    printf '%s' "$v"
  else
    printf '%s' "$_BB_NUKE_DEFAULT"
  fi
}

# "90m"  "1 day"  "2d12h"  "1 week"  → seconds on stdout.  Needs a unit (s m h d w). Returns 1 if unreadable.
_bb_parse_duration() {
  local rest="${1,,}" total=0 n u mult
  rest="${rest//[[:space:]]/}"
  [ -n "$rest" ] || return 1
  while [ -n "$rest" ]; do
    [[ "$rest" =~ ^([0-9]{1,7})(seconds|second|secs|sec|minutes|minute|mins|min|hours|hour|hrs|hr|days|day|weeks|week|s|m|h|d|w)([0-9].*)?$ ]] || return 1
    n=$((10#${BASH_REMATCH[1]})); u="${BASH_REMATCH[2]}"; rest="${BASH_REMATCH[3]}"
    case "$u" in
      s*) mult=1 ;;
      mi*|m) mult=60 ;;
      h*) mult=3600 ;;
      d*) mult=86400 ;;
      w*) mult=604800 ;;
      *) return 1 ;;
    esac
    total=$((total + n * mult))
    [ "$total" -le 99999999 ] || return 1
  done
  printf '%s' "$total"
}

# 3600 → "1h" · 90000 → "1d 1h" · 60 → "1m"   (at most two parts)
_bb_fmt_duration() {
  local s="${1:-0}" d h m out=""
  [[ "$s" =~ ^-?[0-9]+$ ]] || { printf '?'; return; }
  [ "$s" -lt 0 ] && s=0
  d=$((s / 86400)); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if [ "$d" -gt 0 ]; then out="${d}d"; [ "$h" -gt 0 ] && out+=" ${h}h"
  elif [ "$h" -gt 0 ]; then out="${h}h"; [ "$m" -gt 0 ] && out+=" ${m}m"
  elif [ "$m" -gt 0 ]; then out="${m}m"
  else out="${s}s"; fi
  printf '%s' "$out"
}

# epoch-ms → local "YYYY-MM-DD HH:MM" (GNU or BSD date)
_bb_fmt_when() {
  local ms="$1" sec
  [[ "$ms" =~ ^[0-9]{10,}$ ]] || { printf '?'; return; }
  sec=$((ms / 1000))
  date -d "@$sec" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$sec" '+%Y-%m-%d %H:%M' 2>/dev/null || printf '%ss' "$sec"
}

# ---- alias ("up-1-3 as user data") ----------------------------------------------------------------
_BB_ALIAS_RE='^[A-Za-z0-9 ._@+-]{1,48}$'
_BB_LINK_ALIAS=""

# _bb_split_alias "<itemlist> as <alias>"  → _BB_ITEMLIST + _BB_LINK_ALIAS.  Returns 1 (message printed) on a bad alias.
# "as" must be a separate word, so names such as "class" or "alias" are not split.
_bb_split_alias() {
  local raw="$1" lc idx pre
  _BB_ITEMLIST="$raw"; _BB_LINK_ALIAS=""
  lc="${raw,,}"
  if [[ "$lc" == *" as" ]]; then
    echo "⚠️  Alias missing — use:  <items> as <alias>   e.g.  up-1-5 as user data"
    return 1
  fi
  [[ "$lc" == *" as "* ]] || return 0
  pre="${lc%% as *}"; idx=${#pre}
  _BB_ITEMLIST="${raw:0:idx}"
  _BB_LINK_ALIAS="${raw:$((idx + 4))}"
  _BB_LINK_ALIAS="${_BB_LINK_ALIAS#"${_BB_LINK_ALIAS%%[![:space:]]*}"}"
  _BB_LINK_ALIAS="${_BB_LINK_ALIAS%"${_BB_LINK_ALIAS##*[![:space:]]}"}"
  if [[ ! "$_BB_LINK_ALIAS" =~ $_BB_ALIAS_RE ]]; then
    echo "⚠️  Alias may use letters, digits, spaces and . _ @ + -  (1-48 characters)."
    _BB_LINK_ALIAS=""
    return 1
  fi
  return 0
}

# Per-link headers for an upload: how long it lives, and its alias.
_bb_link_cfg() {
  _bb_cfg_header X-Nuke-Seconds "$(_bb_nuke_seconds)"
  [ -n "$_BB_LINK_ALIAS" ] && _bb_cfg_header X-Link-Alias "$_BB_LINK_ALIAS"
  true
}

# After a successful upload: when it will be nuked.   _bb_print_expiry <expires-ms-or-empty>
_bb_print_expiry() {
  local ms="$1" secs; secs=$(_bb_nuke_seconds)
  local label="🕐 Nuke time: $(_bb_fmt_duration "$secs")"
  [ "$secs" -lt 3600 ] && label+=" (billed as 1 hour)"
  [ -n "$ms" ] && label+="  →  gone at $(_bb_fmt_when "$ms")"
  [ -n "$_BB_LINK_ALIAS" ] && label+="   |   alias: $_BB_LINK_ALIAS"
  echo "$label"
  echo "   Change or nuke it early from  api  (Home → Links)."
}
