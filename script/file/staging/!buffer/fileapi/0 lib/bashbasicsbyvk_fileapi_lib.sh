#!/usr/bin/env bash
# bashbasicsbyvk_fileapi_lib.sh — the ONE place for the fileapi endpoint, transport hardening and
# credential/response helpers. Sourced by:
#   • cmd/bashbasicsbyvk_copy                          (stand-alone `bashbasicsbyvk_copy`)
#   • file/staging/!buffer/bashbasicsbyvk_staging_upload.sh   (uploads/imports inside `o`)
# Keep security-relevant behaviour (TLS opts, no secrets in argv) here so a fix lands everywhere.

WORKER_URL="https://fileapi.bashbasics.workers.dev"

# Credentials now come ONLY from the active -auth profile (no env-var / prompt fallback).
_bb_get_credentials() {
  if [ -z "${_BVK_AUTH_DIR:-}" ]; then
    _BVK_AUTH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth"
  fi
  # _bvk_auth_load_active comes from bashbasicsbyvk_auth.sh (loaded by o / the import file of the calling command)
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

# ── bvk-xfer: the Go engine (pack · send · jget).  One static binary per OS/CPU, found like bvk-ls; when it is missing or refuses to run, every
# caller silently uses the old node path, so a machine without it only loses speed, never function.
#   BVK_NO_XFER=1 switches it off on purpose.      _bvk_xfer_bin → sets _BVK_XFER_BIN (empty = not available)
_BVK_XFER_WHY=""
_bvk_xfer_bin() {
  if [ -z "${_BVK_XFER_BIN+x}" ]; then
    _BVK_XFER_BIN=""; _BVK_XFER_WHY=""
    if [ "${BVK_NO_XFER:-0}" = 1 ]; then
      _BVK_XFER_WHY="BVK_NO_XFER=1 is set — the Go engine is switched off on purpose"
    else
      local _m _os _o _d _b _out
      case "$(uname -m)" in
        aarch64|arm64) _m=arm64 ;; x86_64|amd64) _m=amd64 ;; armv7*|armv8l) _m=arm ;;
        *) _m=""; _BVK_XFER_WHY="no bvk-xfer build for CPU '$(uname -m)'" ;;
      esac
      case "$OSTYPE" in
        *android*) _os=android ;;
        *) case "$(uname -o 2>/dev/null)" in Android) _os=android ;; *) _os=linux ;; esac ;;
      esac
      if [ -n "$_m" ]; then
        _BVK_XFER_WHY="no bvk-xfer-$_os-$_m binary found (looked next to 'o' and on PATH)"
        _o="$(command -v o 2>/dev/null)"; _d="${_o%/*}"
        for _b in "$(command -v bvk-xfer 2>/dev/null)" "$_d/../bashbasicsbyvk/bin/bvk-xfer-$_os-$_m" "$(command -v "bvk-xfer-$_os-$_m" 2>/dev/null)"; do
          [ -n "$_b" ] && [ -f "$_b" ] || continue
          [ -x "$_b" ] || chmod +x "$_b" 2>/dev/null
          [ -x "$_b" ] || { _BVK_XFER_WHY="$_b exists but is not executable"; continue; }
          _out="$("$_b" selftest 2>&1)"
          [ "$_out" = "bvk-xfer ok" ] || { _BVK_XFER_WHY="$_b failed its self-test (run: health)"; continue; }
          _BVK_XFER_BIN="$_b"; _BVK_XFER_WHY=""; break
        done
      fi
    fi
  fi
  [ -n "$_BVK_XFER_BIN" ]
}

# one line per time the app had to use Node (or hand a Go upload to the resumable path), read by `health`:  <date> <event> <why>
_bb_xfer_note() {
  local f="${HOME}/.bashbasicsbyvk/xfer.log"
  mkdir -p "${f%/*}" 2>/dev/null
  printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${2//$'\n'/ }" >> "$f" 2>/dev/null
  if [ "$(wc -l < "$f" 2>/dev/null || echo 0)" -gt 300 ]; then tail -n 150 "$f" > "$f.n" 2>/dev/null && mv -f "$f.n" "$f"; fi
  return 0
}

_bb_json_get() {
  local json="$1" field="$2"
  if _bvk_xfer_bin; then "$_BVK_XFER_BIN" jget "$field" <<< "$json"; return; fi
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
  # one-shot value chosen at a credit prompt (reduce / increase time) wins for that single operation
  if [[ "${_BB_TTL_OVERRIDE:-}" =~ ^[0-9]{1,9}$ ]] && [ "$_BB_TTL_OVERRIDE" -ge "$_BB_NUKE_MIN" ] && [ "$_BB_TTL_OVERRIDE" -le "$_BB_NUKE_MAX" ]; then
    printf '%s' "$_BB_TTL_OVERRIDE"; return
  fi
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

# epoch-ms → "YYYY-MM-DD HH:MM IST" in the app timezone (Settings → Timezone; zone abbreviation included)
_bb_fmt_when() {
  local ms="$1" sec
  [[ "$ms" =~ ^[0-9]{10,}$ ]] || { printf '?'; return; }
  sec=$((ms / 1000))
  date -d "@$sec" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || date -r "$sec" '+%Y-%m-%d %H:%M %Z' 2>/dev/null || printf '%ss' "$sec"
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
    echo "🔴  Alias missing — use:  <items> as <alias>   e.g.  up-1-5 as user data"
    return 1
  fi
  [[ "$lc" == *" as "* ]] || return 0
  pre="${lc%% as *}"; idx=${#pre}
  _BB_ITEMLIST="${raw:0:idx}"
  _BB_LINK_ALIAS="${raw:$((idx + 4))}"
  _BB_LINK_ALIAS="${_BB_LINK_ALIAS#"${_BB_LINK_ALIAS%%[![:space:]]*}"}"
  _BB_LINK_ALIAS="${_BB_LINK_ALIAS%"${_BB_LINK_ALIAS##*[![:space:]]}"}"
  if [[ ! "$_BB_LINK_ALIAS" =~ $_BB_ALIAS_RE ]]; then
    echo "🔴  Alias may use letters, digits, spaces and . _ @ + -  (1-48 characters)."
    _BB_LINK_ALIAS=""
    return 1
  fi
  return 0
}

# Per-link headers for an upload: how long it lives, and its alias.
_bb_link_cfg() {
  _bb_cfg_header X-Nuke-Seconds "$(_bb_svc_ttl "${_BB_SVC:-}")"
  # names are sent ENCRYPTED ("e1." + AES-GCM under your label key, made by _bb_alias_prepare) — the server never sees them
  [ -n "${_BB_LINK_ALIAS_WIRE:-}" ] && _bb_cfg_header X-Link-Alias "$_BB_LINK_ALIAS_WIRE"
  # Backup / Saved Surf / Snapshots tag their upload so the server files it under the right menu
  if [ -n "${_BB_SVC:-}" ]; then
    _bb_cfg_header X-Service "$_BB_SVC"
    [ "$_BB_SVC" = snapshot ] && _bb_device_cfg
  fi
  true
}

# After a successful upload: when it will be nuked.   _bb_print_expiry <expires-ms-or-empty>
_bb_print_expiry() {
  local ms="$1" secs; secs=$(_bb_svc_ttl "${_BB_SVC:-}")
  local label="🕐 Nuke time: $(_bb_fmt_duration "$secs")"
  [ "$secs" -lt 3600 ] && label+=" (billed as 1 hour)"
  [ -n "$ms" ] && label+="  →  gone at $(_bb_fmt_when "$ms")"
  [ -n "$_BB_LINK_ALIAS" ] && label+="   |   alias: $_BB_LINK_ALIAS"
  echo "$label"
  echo "   Change or nuke it early from  api  (Home → Links)."
}


# ---- link keys (so a link can be copied / rebuilt later from the api loop) --------------------------
# The decryption key lives only in the "#k=" part of a link. To let you copy a link again without
# uploading anything, the key is kept on THIS computer: ~/.bashbasicsbyvk/link_keys  (<id> TAB <key>, mode 600).
# It never goes to the server. Turn it off with  FILEAPI_BASHBASICS_STORE_KEYS=0  (new links only).
_BB_KEY_FILE="${HOME}/.bashbasicsbyvk/link_keys"
_BB_KEY_RE='^[A-Za-z0-9_-]{43}$'

# _bb_key_store <id> <key|"">   ("" = forget)
_bb_key_store() {
  local id="$1" key="$2" tmp
  # NB: no {n,m} with m>255 in a bash regex: bionic/BSD regcomp (Termux/Android) caps repeats at 255 -> "invalid repetition count(s)". Check length separately.
  [[ "$id" =~ ^[A-Za-z0-9_-]+$ ]] && [ "${#id}" -le 256 ] || return 1
  mkdir -p "$(dirname "$_BB_KEY_FILE")" 2>/dev/null
  tmp="$(umask 077; mktemp "${_BB_KEY_FILE}.XXXXXX" 2>/dev/null)" || return 1
  { [ -f "$_BB_KEY_FILE" ] && awk -F'\t' -v id="$id" '$1 != id' "$_BB_KEY_FILE"
    [ -n "$key" ] && printf '%s\t%s\n' "$id" "$key"; true; } > "$tmp"
  chmod 600 "$tmp" 2>/dev/null
  mv -f "$tmp" "$_BB_KEY_FILE"
}

# _bb_key_get <id>  → key on stdout, status 1 when unknown
_bb_key_get() {
  local id="$1" k i
  [ -f "$_BB_KEY_FILE" ] || return 1
  while IFS=$'\t' read -r i k || [ -n "$i" ]; do
    [ "$i" = "$id" ] && [[ "$k" =~ $_BB_KEY_RE ]] && { printf '%s' "$k"; return 0; }
  done < "$_BB_KEY_FILE"
  return 1
}

# _bb_key_remember <full link with #k=...>   (called for every new link)
_bb_key_remember() {
  [ "${FILEAPI_BASHBASICS_STORE_KEYS:-1}" = "0" ] && return 0
  local url="$1" base id key
  [[ "$url" == *"#k="* ]] || return 0
  key="${url#*#k=}"; base="${url%%#*}"; base="${base%/}"; id="${base##*/}"
  [[ "$key" =~ $_BB_KEY_RE ]] || return 0
  _bb_key_store "$id" "$key" 2>/dev/null || true
}


# ════════════════════════════════════════════════════════════════════════════
#  Shared plumbing for the credit prompt, Backup, Saved Surf and Snapshots
# ════════════════════════════════════════════════════════════════════════════

# A setting by name: the live shell variable (the app loaded it), else the config file (so the background
# snapshot process and stand-alone scripts agree), else the default.   _bb_cfg_val <name> <default>
_bb_cfg_val() {
  local name="$1" def="$2" v
  [[ "$name" =~ ^[a-z_]+$ ]] || { printf '%s' "$def"; return; }
  v="${!name:-}"
  if [ -z "$v" ]; then
    local cf="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/config"
    [ -r "$cf" ] && v=$(sed -n "s/^${name}=\([A-Za-z0-9_.-]\{1,40\}\)\$/\1/p" "$cf" 2>/dev/null | tail -n 1)
  fi
  printf '%s' "${v:-$def}"
}

# The nuke time for a service (backup | saved | snapshot), clamped to what the server accepts.
_bb_svc_ttl() {
  local key def v
  if [[ "${_BB_TTL_OVERRIDE:-}" =~ ^[0-9]{1,9}$ ]] && [ "$_BB_TTL_OVERRIDE" -ge "$_BB_NUKE_MIN" ] && [ "$_BB_TTL_OVERRIDE" -le "$_BB_NUKE_MAX" ]; then
    printf '%s' "$_BB_TTL_OVERRIDE"; return
  fi
  case "$1" in
    backup)   key=backup_nuke_time_seconds;   def=$_BB_NUKE_MAX ;;
    saved)    key=saved_nuke_time_seconds;    def=$_BB_NUKE_MAX ;;
    snapshot) key=snapshot_keep_seconds;      def=$((7*86400)) ;;
    ux)       key=ux_nuke_time_seconds;       def=$_BB_NUKE_MAX ;;
    *)        printf '%s' "$(_bb_nuke_seconds)"; return ;;
  esac
  v=$(_bb_cfg_val "$key" "$def")
  if [[ "$v" =~ ^[0-9]{1,9}$ ]] && [ "$v" -ge "$_BB_NUKE_MIN" ] && [ "$v" -le "$_BB_NUKE_MAX" ]; then printf '%s' "$v"; else printf '%s' "$def"; fi
}

# This computer's id for the server: the telemetry uuid + the signature the server issued for it.
_bb_device_cfg() {
  local d="${_BVK_TELEMETRY_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/telemetry}" id sg
  id=$(cat "$d/uuid" 2>/dev/null); sg=$(cat "$d/sig" 2>/dev/null)
  [ -n "$id" ] && [ -n "$sg" ] || return 1
  _bb_cfg_header X-Telemetry-Id "$id"
  _bb_cfg_header X-Telemetry-Sig "$sg"
}
_bb_device_ready() { _bb_device_cfg >/dev/null 2>&1; }

# _bb_call <METHOD> <path> [json-body] [max-seconds=40]     → _BB_STATUS (000 = unreachable) and _BB_BODY.
# THE one authenticated JSON call to the worker: api.sh (_api_http) and staging_ux.sh (_ux_http) are thin wrappers around it.
# Extra request headers: set  _BB_CALL_HDRS=("Name: value" ...)  before calling (they go through the curl config, never argv).
_BB_CALL_HDRS=()
_bb_call() {
  local method="$1" path="$2" body="${3:-}" tmo="${4:-40}" cfg out h
  _bb_get_credentials || { _BB_STATUS=000; _BB_BODY=""; return 1; }
  cfg=$({ _bb_auth_cfg
          for h in "${_BB_CALL_HDRS[@]}"; do _bb_cfg_header "${h%%:*}" "${h#*: }"; done
          [ -n "$body" ] && _bb_cfg_header Content-Type application/json; true; })
  if [ -n "$body" ]; then
    out=$(curl -s --max-time "$tmo" "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X "$method" --data-binary "$body" "$WORKER_URL$path" <<<"$cfg")
  else
    out=$(curl -s --max-time "$tmo" "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X "$method" "$WORKER_URL$path" <<<"$cfg")
  fi
  _BB_STATUS="${out##*$'\n'}"
  _BB_BODY="${out%$'\n'*}"
  [[ "$_BB_STATUS" =~ ^[0-9]{3}$ ]] || _BB_STATUS=000
  return 0
}

# _bb_http_fail <status> <body>   prints the server's reason for a failed _bb_call-style answer (one place for the wording)
_bb_http_fail() {
  case "$1" in
    000) echo "❌ Could not reach the server (offline?)." ;;
    401) echo "❌ $(_bb_json_get "$2" message)"; echo "🔁 Fix the active user with  -auth  inside 'o', then try again." ;;
    *)   echo "❌ $(_bb_fail_reason "$2" "$1")" ;;
  esac
}

# _bb_created_emit <header-file> <body>   the answer of a successful (HTTP 201) link-creating call, as the callers read it:
# prints  body \n credits-deducted \n credits-balance \n link-expires  (the three come from the response headers) and removes <header-file>.
_bb_created_emit() {
  local hdrfile="$1" body="$2" deducted balance expires
  deducted=$(grep -i '^X-Credits-Deducted:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
  balance=$(grep -i '^X-Credits-Balance:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
  expires=$(grep -i '^X-Link-Expires:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
  rm -f "$hdrfile"
  printf '%s\n%s\n%s\n%s\n' "$body" "$deducted" "$balance" "$expires"
}

# _bb_jslib  → prints the path of bashbasicsbyvk_staging_jslib.js (the status-line / chunk-writer code the node transfer tools share).
# Callers hand it to node as  BB_JSLIB=...  (ux_crypto, pending_xfer and the node fallbacks in staging_upload.sh require() it).
# Searched on PATH by readability, not +x: it is a library, and a source checkout has no exec bits.
_BB_JSLIB=""
_bb_jslib() {
  if [ -z "$_BB_JSLIB" ]; then
    local d IFS=:
    for d in $PATH; do [ -n "$d" ] && [ -r "$d/bashbasicsbyvk_staging_jslib.js" ] && { _BB_JSLIB="$d/bashbasicsbyvk_staging_jslib.js"; break; }; done
  fi
  [ -n "$_BB_JSLIB" ] || { echo "❌ bashbasicsbyvk_staging_jslib.js not found (reinstall bashbasicsbyvk)." >&2; return 127; }
  printf '%s' "$_BB_JSLIB"
}

# ── packing helpers shared by svc (backup/saved/snapshot), up- and ux- ────────────────────────────────────────────
# _bb_stage_links <stage-dir> <say-fn> <path>...   → appends "./<name>" to the CALLER's  rel_items  array.
# Symlinks each existing item into <stage-dir> under a unique name, so the archive holds "<name>/..." entries relative to nothing
# absolute. The "./" keeps a name that starts with "-" from ever being read as an option. A missing item is skipped with a notice
# through <say-fn> (echo when empty; svc passes its quiet-aware _svc_say).
_bb_stage_links() {
  local stage="$1" say="${2:-echo}" p bn cand n
  shift 2
  for p in "$@"; do
    p="${p%/}"; [[ "$p" == /* ]] || p="$PWD/$p"
    if [ ! -f "$p" ] && [ ! -d "$p" ]; then "$say" "  🔴  Skipping missing item: $p" >&2; continue; fi
    bn="${p##*/}"; cand="$bn"; n=1
    while [ -e "$stage/$cand" ] || [ -L "$stage/$cand" ]; do n=$((n + 1)); cand="${bn}_$n"; done
    ln -s "$p" "$stage/$cand"
    rel_items+=("./$cand")
  done
}

# _bb_gzip_setup  → sets the CALLER's  gz  array (pigz when installed, else gzip) and  lvl  (FILEAPI_BASHBASICS_GZIP_LEVEL, 1-9, default 6)
_bb_gzip_setup() {
  gz=(gzip)
  command -v pigz &>/dev/null && gz=(pigz)          # parallel gzip when available
  lvl="${FILEAPI_BASHBASICS_GZIP_LEVEL:-6}"
  [[ "$lvl" =~ ^[1-9]$ ]] || lvl=6
}

# "90m" / "2d" absolute, or "+1d" / "-12h" relative to <current-seconds>   → new total seconds, within 1 minute..30 days.
# The same rules as editing a link's time in  api, so the two feel identical.
_bb_resolve_time() {
  local cur="$1" spec="$2" sign="" d new
  spec="${spec#"${spec%%[![:space:]]*}"}"
  case "$spec" in +*|-*) sign="${spec:0:1}"; spec="${spec:1}" ;; esac
  d=$(_bb_parse_duration "$spec") || return 1
  case "$sign" in
    +) new=$((cur + d)) ;;
    -) new=$((cur - d)) ;;
    *) new=$d ;;
  esac
  [ "$new" -ge "$_BB_NUKE_MIN" ] && [ "$new" -le "$_BB_NUKE_MAX" ] || return 2
  printf '%s' "$new"
}

# estimate → _BB_E_CREDITS _BB_E_BAL _BB_E_OK _BB_E_MAXS _BB_E_OVER _BB_E_ONEH   (returns 1 when the server cannot price it)
_bb_estimate() {
  local bytes="$1" ttl="$2" line
  _bb_call POST /estimate "{\"bytes\":$bytes,\"ttlSeconds\":$ttl}" || return 1
  [ "$_BB_STATUS" = "200" ] || return 1
  line=$(node -e '
    let d=""; process.stdin.on("data",c=>d+=c); process.stdin.on("end",()=>{ try { const o=JSON.parse(d);
      const f=[o.credits,o.balance,o.affordable?1:0,o.maxSeconds,o.oversized?1:0,o.oneHourCredits];
      if (f.some(v=>!Number.isFinite(Number(v)))) process.exit(1); process.stdout.write(f.join(" ")); } catch(e){ process.exit(1); } });
  ' <<<"$_BB_BODY") || return 1
  read -r _BB_E_CREDITS _BB_E_BAL _BB_E_OK _BB_E_MAXS _BB_E_OVER _BB_E_ONEH <<<"$line"
  [[ "$_BB_E_CREDITS" =~ ^[0-9]+$ ]] || return 1
  return 0
}

# Ask for a new time. $1=current seconds  $2=hint text  $3=value taken on plain Enter ("" = none)
# → _BB_NEWTTL.  Returns 1 if the user backs out.
_bb_ask_time() {
  local cur="$1" hint="$2" dflt="$3" a n rc
  while :; do
    read -e -r -p "   ⏱️  $hint: " a || return 1
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    case "${a,,}" in
      s|stop|n|no|q|cancel) return 1 ;;
      "") if [ -n "$dflt" ]; then _BB_NEWTTL="$dflt"; return 0; fi; return 1 ;;
    esac
    n=$(_bb_resolve_time "$cur" "$a"); rc=$?
    if [ $rc -eq 0 ]; then _BB_NEWTTL="$n"; return 0; fi
    [ $rc -eq 2 ] && echo "   🔴  Between 1 minute and 30 days, please." || echo "   🔴  Use e.g. 12h · 2d · +1d · -6h  (units: s m h d w)."
  done
}

# The price check before any fileapi upload.  _bb_credit_gate <packed-bytes> <what> [service]
#   cost 1 and affordable                → carry on silently
#   cost > 1 and affordable              → ask: continue / reduce time / increase time / stop
#   cannot afford                        → ask: stop, or reduce the time (suggests the longest time your credits cover)
# A time chosen here applies to this one operation (_BB_TTL_OVERRIDE). Returns 1 = stop.
# Settings → File API → Credits → "Ask before spending credits" = off skips all of this (the server still enforces your balance).
_BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""

# _bb_price_is_one <bytes> <ttl-seconds>  → 0 when the server's price is CERTAINLY 1 credit (so the prompt would stay silent anyway and the
# /estimate round trip can be skipped).  Same formula as the server (ledger.js creditsForHours): credits = max(1, ceil(max(mb/1024*hours, ceil(hours/minPeriod(mb)))))
# — and 1 only when mb*hours <= 1024 and hours <= minPeriod(mb); under 10 GB, so never the 1.2x rate.  Anything unsure → 1 (ask the server).
_bb_price_is_one() {
  local bytes="$1" ttl="$2" mb hours minp
  [[ "$bytes" =~ ^[1-9][0-9]*$ ]] && [[ "$ttl" =~ ^[0-9]+$ ]] || return 1
  [ "$bytes" -lt $((10*1024*1024*1024)) ] || return 1
  mb=$(( (bytes + 1048575) / 1048576 )); [ "$mb" -ge 1 ] || mb=1
  hours=$(( (ttl + 3599) / 3600 )); [ "$hours" -ge 1 ] || hours=1
  if   [ "$mb" -le 5 ];   then minp=720
  elif [ "$mb" -le 50 ];  then minp=168
  elif [ "$mb" -le 500 ]; then minp=24
  else minp=1; fi
  [ "$hours" -le "$minp" ] && [ $((mb * hours)) -le 1024 ]
}

_bb_credit_gate() {
  local bytes="$1" what="${2:-this operation}" svc="${3:-}" ttl a guard=0
  _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""
  [ "$(_bb_cfg_val credit_prompts show)" = "skip" ] && return 0
  [[ "$bytes" =~ ^[1-9][0-9]*$ ]] || return 0
  ttl=$(_bb_svc_ttl "$svc")
  _bb_price_is_one "$bytes" "$ttl" && return 0         # certainly 1 credit: nothing to ask, no round trip (the server still enforces your balance)
  while [ "$guard" -lt 25 ]; do
    guard=$((guard + 1))
    _bb_estimate "$bytes" "$ttl" || return 0          # cannot price it → the server decides at upload
    local after=$((_BB_E_BAL - _BB_E_CREDITS)) over=""
    [ "$_BB_E_OVER" = "1" ] && over=" (includes the 1.2x rate for over 10GB)"
    if [ "$_BB_E_OK" = "1" ]; then
      if [ "$_BB_E_CREDITS" -le 1 ] && [ "$_BB_E_OVER" != "1" ]; then return 0; fi
      echo "💳 $what costs $_BB_E_CREDITS credits for $(_bb_fmt_duration "$ttl")$over — balance $_BB_E_BAL → $after."
      read -e -r -p "   [c] continue  ·  [r] reduce time  ·  [i] increase time  ·  [s] stop: " a || { echo "🚫 Stopped."; return 1; }
      case "${a,,}" in
        c|y|yes|continue) [ "$_BB_E_OVER" = "1" ] && _BB_OVERSIZE_OK=1; return 0 ;;
        r|reduce)   _bb_ask_time "$ttl" "New time (e.g. 12h · 2d · -1d)" "" || { echo "🚫 Stopped."; return 1; }; ttl="$_BB_NEWTTL"; _BB_TTL_OVERRIDE="$ttl" ;;
        i|increase) _bb_ask_time "$ttl" "New time (e.g. 7d · +2d)" "" || { echo "🚫 Stopped."; return 1; }; ttl="$_BB_NEWTTL"; _BB_TTL_OVERRIDE="$ttl" ;;
        *) echo "🚫 Stopped."; return 1 ;;
      esac
    else
      if [ "${_BB_E_MAXS:-0}" -lt 3600 ]; then
        echo "❌ Not enough credits: $what needs at least $_BB_E_ONEH credit(s) even for the shortest time (1 hour); you have $_BB_E_BAL."
        echo "   Top up your credits, or select less data."
        return 1
      fi
      local sug="$_BB_E_MAXS"
      echo "💳 Not enough credits: keeping $what for $(_bb_fmt_duration "$ttl") costs $_BB_E_CREDITS$over; you have $_BB_E_BAL."
      read -e -r -p "   [r] reduce time  ·  [s] stop: " a || { echo "🚫 Stopped."; return 1; }
      case "${a,,}" in
        r|reduce)
          _bb_ask_time "$ttl" "Longest your credits cover: $(_bb_fmt_duration "$sug") — Enter to use it, or type a time" "$sug" || { echo "🚫 Stopped."; return 1; }
          ttl="$_BB_NEWTTL"; _BB_TTL_OVERRIDE="$ttl" ;;
        *) echo "🚫 Stopped."; return 1 ;;
      esac
    fi
  done
  echo "🚫 Stopped."; return 1
}

# Quiet variant for background work (no prompts): 0 = affordable at <ttl>, 1 = not (message in _BB_GATE_MSG), 2 = could not price
_bb_credit_check_quiet() {
  local bytes="$1" ttl="$2"
  _BB_GATE_MSG=""
  _bb_estimate "$bytes" "$ttl" || return 2
  [ "$_BB_E_OK" = "1" ] && return 0
  _BB_GATE_MSG="needs $_BB_E_CREDITS credits, you have $_BB_E_BAL"
  return 1
}

# A short label for a service item:  DDMMYYYY HHMM [NAME]   (app timezone) — used by Backup and Saved Surf
# _bb_svc_alias [name]  → alias on stdout; returns 1 if the name has characters the server does not allow
_bb_svc_alias() {
  local name="$1" stamp out
  stamp=$(date '+%d%m%Y %H%M')
  name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
  if [ -z "$name" ]; then printf '%s' "$stamp"; return 0; fi
  out="$stamp $name"
  [[ "$out" =~ $_BB_ALIAS_RE ]] || return 1
  printf '%s' "$out"
}

# AES-256-GCM label helpers (paths, device names): the key is a per-user label key made on the client and kept on the server only wrapped with the FEK (CSE).
# _bb_label_enc <key> <text>  →  base64url      _bb_label_dec <key> <base64url> → text (empty on failure)
_bb_label_enc() {
  BB_LK="$1" node -e '
    const c=require("crypto"); const k=Buffer.from(process.env.BB_LK,"base64url"); let d="";
    process.stdin.on("data",x=>d+=x); process.stdin.on("end",()=>{ const iv=c.randomBytes(12); const ci=c.createCipheriv("aes-256-gcm",k,iv);
      ci.setAAD(Buffer.from("bbvk6|label")); const ct=Buffer.concat([ci.update(Buffer.from(d,"utf8")),ci.final()]);
      process.stdout.write(Buffer.concat([iv,ct,ci.getAuthTag()]).toString("base64url")); });' <<<"$2" | tr -d '\n'
}
_bb_label_dec() {
  BB_LK="$1" BB_ENC="$2" node -e '
    try { const c=require("crypto"); const k=Buffer.from(process.env.BB_LK,"base64url"); const b=Buffer.from(process.env.BB_ENC,"base64url");
      const d=c.createDecipheriv("aes-256-gcm",k,b.subarray(0,12)); d.setAuthTag(b.subarray(b.length-16)); d.setAAD(Buffer.from("bbvk6|label"));
      process.stdout.write(Buffer.concat([d.update(b.subarray(12,b.length-16)),d.final()]).toString("utf8").replace(/\n$/,"")); } catch(e) {}' 2>/dev/null
}


# ════════════════════════════════════════════════════════════════════════════
#  Client-side encryption of names and stored links (works from any device that has e-mail + diseps + apikey + dinons)
#
#  One LABEL KEY per user: made here on first use, kept on the server only wrapped with your FEK (dinons → FEK → label key).
#  It encrypts
#    • every name you type (up-… as <name>, backup / save- names, a-N renames)     →  sent as "e1.<ciphertext>"
#    • the full address of each up- link (so Links can copy it again on any device) →  stored as ciphertext in /links/<id>/secret
#  The server stores only ciphertext it cannot open. Without the dinons a name is NOT sent (never sent in clear) and a link is
#  simply not kept in the cloud.
# ════════════════════════════════════════════════════════════════════════════
_BB_LK=""; _BB_LK_FOR=""; _BB_LINK_ALIAS_WIRE=""; _BB_LAST_SECRET_ENC=""

# _bb_labelkey_load  → sets _BB_LK (cached per account); returns 1 when it cannot be opened (no dinons / offline).
# Call it directly (not inside $( )) so the cache survives.
_bb_labelkey_load() {
  if [ -n "$_BB_LK" ] && [ "$_BB_LK_FOR" = "${FILEAPI_BASHBASICS_DISEPS:-}" ]; then return 0; fi
  local kdk k nk
  _BB_LK=""; _BB_CALL_HDRS=()
  _ux_self_fek || return 1
  _bb_call GET /vault/labelkey || return 1
  if [ "$_BB_STATUS" = 404 ]; then
    nk=$(_ux_core newkey) && [[ "$nk" =~ $_BB_KEY_RE ]] || return 1
    kdk=$(BB_FEK="$_UX_FEK" BB_K="$nk" _ux_core dk-wrap 2>/dev/null)
    [[ "$kdk" =~ ^[A-Za-z0-9_-]{60,200}$ ]] || return 1
    _bb_call PUT /vault/labelkey "{\"kdk\":\"$kdk\"}" || return 1     # first writer wins: the answer is the stored one
  fi
  [ "$_BB_STATUS" = 200 ] || { echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")" >&2; return 1; }
  kdk=$(_bb_json_get "$_BB_BODY" kdk)
  [[ "$kdk" =~ ^[A-Za-z0-9_-]{60,200}$ ]] || return 1
  k=$(printf '%s' "$kdk" | BB_FEK="$_UX_FEK" _ux_core dk-unwrap) && [[ "$k" =~ $_BB_KEY_RE ]] || return 1
  _BB_LK="$k"; _BB_LK_FOR="${FILEAPI_BASHBASICS_DISEPS:-}"
}

# _bb_alias_prepare : _BB_LINK_ALIAS → _BB_LINK_ALIAS_WIRE ("e1.…"). Never falls back to sending the name in clear.
_bb_alias_prepare() {
  _BB_LINK_ALIAS_WIRE=""
  [ -n "${_BB_LINK_ALIAS:-}" ] || return 0
  if _bb_labelkey_load 2>/dev/null; then
    local e; e=$(_bb_label_enc "$_BB_LK" "$_BB_LINK_ALIAS")
    if [[ "$e" =~ ^[A-Za-z0-9_-]{40,180}$ ]]; then _BB_LINK_ALIAS_WIRE="e1.$e"; return 0; fi
  fi
  echo "🔴  The name '$_BB_LINK_ALIAS' was NOT stored: names are kept encrypted and that needs your dinons on this computer." >&2
  return 0
}

# _bb_alias_show <stored name> → readable name ("e1." names are decrypted; older plain names pass through)
_bb_alias_show() {
  local a="$1" p
  case "$a" in
    e1.*) if [ -n "$_BB_LK" ]; then p=$(_bb_label_dec "$_BB_LK" "${a#e1.}"); [ -n "$p" ] && { printf '%s' "$p"; return 0; }; fi
          printf '🔒 (open with your dinons)' ;;
    *)    printf '%s' "$a" ;;
  esac
}

# _bb_link_secret_put <id> <full link with #k=…>   → keeps the link, encrypted, on the server (Links on any device)
_bb_link_secret_put() {
  local id="$1" url="$2" enc
  _BB_LAST_SECRET_ENC=""
  [[ "$id" =~ ^[A-Za-z0-9_-]{43}$ ]] || return 1
  _bb_labelkey_load 2>/dev/null || return 1
  enc=$(_bb_label_enc "$_BB_LK" "$url")
  # length checked separately: {60,1500} breaks on Android/Termux (regex repeat limit 255)
  [[ "$enc" =~ ^[A-Za-z0-9_-]+$ ]] && [ "${#enc}" -ge 60 ] && [ "${#enc}" -le 1500 ] || return 1
  _BB_CALL_HDRS=()
  _bb_call PUT "/links/$id/secret" "{\"enc\":\"$enc\"}" || return 1
  [ "$_BB_STATUS" = 200 ] || return 1
  _BB_LAST_SECRET_ENC="$enc"
}

# the three codes other people see next to your mail (positions 13, 24 and 7 of the diseps) — same as RBAM's d3
_bb_d3() { printf '%s' "$1" | awk -F- 'NF==27 { printf "%s-%s-%s", $13, $24, $7 }'; }
