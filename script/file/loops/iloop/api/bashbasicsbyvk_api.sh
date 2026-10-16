#!/usr/bin/env bash
# bashbasicsbyvk_api.sh — the  api  loop: manage the links you have created (an inner loop, like fx / sw / .r / -u)
# ════════════════════════════════════════════════════════════════════════════
#  api   opens the link manager (also: Home → Links).   Every ACTIVE link you made with up- / c2c- is
#  listed, soonest expiry first. A link is shown by its ALIAS (up-1-3 as user data); without one you see
#  the start of its id. The full link is shown only on request (c-N). The link (with its key) is kept in the cloud
#  ONLY as ciphertext made with your label key (dinons → FEK → label key), so c-N works on every device you log in on and the
#  server cannot read it; names are encrypted the same way. The key also stays on this computer as a cache.
#
#  Commands
#    N          open link N (details, then  e  edit  /  x  nuke)
#    c-N        copy the link of link N to the clipboard (bashbasicsbyvk_copy)   c-1,3-5 several, one per line
#    g-N        regenerate: link N gets a NEW address (old one stops working at once), nothing re-uploaded   g-1,3-5
#    k-N        attach the key of an OLDER link (paste its full link once) so c-N works for it too
#    a-N        set or rename the alias of link N   a-N my notes  (saved on the server; also works for links made without one)
#    e-N        edit the expiry of link N          e-N 2d   (value given inline)
#    x-N        nuke link N now                    x-1,3-5  (several)
#    rf         refresh the list          u  exit          api  close          q  quit the app
#    fx / sw / .r / -u   hand over to those loops
#
#  Editing the expiry
#    Type the NEW TOTAL life, counted from when the link was created:   2d   ·   36h   ·   1 week
#    or move the current expiry:   +12h  (extend)   ·   -1d  (shorten).   Limits: 1 minute – 30 days.
#      extend            the extra time is charged now (same rate and size-bucket minimums as an upload)
#      shorten / nuke    refunded to your ledger in WHOLE DAYS only; time already used is rounded UP to a
#                        whole day (a 30-day link nuked after 1 day and 1 minute refunds 28 days, not 29)
#
#  Server routes used:  GET /links · POST /links/<id>/expiry · POST /links/<id>/alias · POST /links/<id>/regenerate · DELETE /links/<id>   (full credentials)
#
#  Uses (from the main app): _vp_* viewport, _read_choice_filtered, _inner_run, _filter_reset_state,
#  _bvk_quit, parse_selection, and _bb_* helpers from _3bvk_fileapi_lib.sh
# ════════════════════════════════════════════════════════════════════════════

declare -ga _API_ID=() _API_KIND=() _API_ALIAS=() _API_BYTES=() _API_CREATED=() _API_EXPIRES=()
declare -ga _API_PAID=() _API_RFND=() _API_RFND_D=() _API_PUB=() _API_LENC=()
_API_BAL=""
_API_NOW=0           # server clock (ms) at the last refresh
_API_LOCAL=0         # this computer's clock (s) at the same moment → server "now" stays live between refreshes
declare -ga _API_PRE=() _API_POST=()   # per-row text that never changes (everything but the countdown)
_API_ERR=""
_API_LOADED=0
_API_US=$'\x1f'

# ── network ───────────────────────────────────────────────────────────────────
# _api_http METHOD PATH [json-body]  → _API_STATUS / _API_BODY.  Credentials travel in a curl config on
# stdin, never in argv.
_api_http() {
  local method="$1" path="$2" body="${3:-}" cfg out
  _bb_get_credentials || return 1
  cfg=$({ _bb_auth_cfg; [ -n "$body" ] && _bb_cfg_header Content-Type application/json; true; })
  if [ -n "$body" ]; then
    out=$(curl -s --max-time 40 "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X "$method" --data-binary "$body" "$WORKER_URL$path" <<<"$cfg")
  else
    out=$(curl -s --max-time 40 "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X "$method" "$WORKER_URL$path" <<<"$cfg")
  fi
  _API_STATUS="${out##*$'\n'}"
  _API_BODY="${out%$'\n'*}"
  [[ "$_API_STATUS" =~ ^[0-9]{3}$ ]] || _API_STATUS=000
  return 0
}

_api_fail() {            # prints the server's reason for the last call
  case "$_API_STATUS" in
    000) echo "❌ Could not reach the server (offline?)." ;;
    401) echo "❌ $(_bb_json_get "$_API_BODY" message)"; echo "🔁 Fix the active user with  -auth  inside 'o', then try again." ;;
    *)   echo "❌ $(_bb_fail_reason "$_API_BODY" "$_API_STATUS")" ;;
  esac
}

# ── loading ───────────────────────────────────────────────────────────────────
# _API_SVC: "" = the Links screen · backup = Backup · saved = Saved Surf.  They share this whole loop (alias, expiry, nuke).
_API_SVC="${_API_SVC:-}"
_api_load() {
  _API_ID=(); _API_KIND=(); _API_ALIAS=(); _API_BYTES=(); _API_CREATED=(); _API_EXPIRES=()
  _API_PAID=(); _API_RFND=(); _API_RFND_D=(); _API_PUB=(); _API_LENC=()
  _API_ERR=""; _API_LOADED=1; _API_BAL=""
  if ! _crypto_check >/dev/null 2>&1; then _API_ERR="node is required (used to read the server's answer)"; return 1; fi
  _api_http GET "/links${_API_SVC:+?svc=$_API_SVC}" || { _API_ERR="no active user — run  -auth  inside 'o'"; return 1; }
  if [ "$_API_STATUS" != "200" ]; then _API_ERR="$(_api_fail | head -n 1 | sed 's/^❌ //')"; return 1; fi
  # names and stored links are encrypted (label key ← FEK ← dinons): open it once per session so they can be shown
  if [ -z "$_API_SVC" ] || [[ "$_API_BODY" == *'"alias":"e1.'* ]]; then _bb_labelkey_load 2>/dev/null || true; fi
  local out
  out=$(BB_LK="$_BB_LK" node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const US = "\x1f";
      let o; try { o = JSON.parse(d); } catch (e) { process.exit(2); }
      if (!o || !Array.isArray(o.links)) process.exit(2);
      const clean = (v) => String(v ?? "").replace(/[\x00-\x1f\x7f]/g, " ");
      const dec = (a) => {              // "e1." names are AES-GCM under the label key; older names are plain
        if (!/^e1\./.test(a)) return a;
        if (!process.env.BB_LK) return "🔒 (open with your dinons)";
        try { const c = require("crypto"); const k = Buffer.from(process.env.BB_LK, "base64url"); const b = Buffer.from(a.slice(3), "base64url");
          const x = c.createDecipheriv("aes-256-gcm", k, b.subarray(0, 12)); x.setAuthTag(b.subarray(b.length - 16)); x.setAAD(Buffer.from("bbvk6|label"));
          return Buffer.concat([x.update(b.subarray(12, b.length - 16)), x.final()]).toString("utf8").replace(/\n$/, ""); } catch (e) { return "🔒 (cannot decrypt)"; }
      };
      console.log(["META", o.balance, o.now].join(US));
      for (const l of o.links) {
        console.log(["L", l.id, l.kind, clean(dec(String(l.alias ?? ""))), l.bytes, l.createdAt, l.expiresAt, l.paidHours, l.nukeRefund, l.nukeRefundDays, l.publicId || l.id, l.linkEnc || ""].join(US));
      }
    });' <<<"$_API_BODY") || { _API_ERR="the server answered, but not with a link list"; return 1; }
  local tag a b c d e f g h i j k
  while IFS="$_API_US" read -r tag a b c d e f g h i j k; do
    case "$tag" in
      META) _API_BAL="$a"; _API_NOW="$b"; _API_LOCAL="${EPOCHSECONDS:-$(date +%s)}"; _API_PRE=(); _API_POST=() ;;
      L)    _API_ID+=("$a"); _API_KIND+=("$b"); _API_ALIAS+=("$c"); _API_BYTES+=("$d")
            _API_CREATED+=("$e"); _API_EXPIRES+=("$f"); _API_PAID+=("$g"); _API_RFND+=("$h"); _API_RFND_D+=("$i"); _API_PUB+=("${j:-$a}"); _API_LENC+=("$k") ;;
    esac
  done <<<"$out"
  _api_sync_local_aliases
  _api_prune_keys
  _api_apply_aliases
  _api_backfill_secrets
  return 0
}

# Links made before links were kept in the cloud (or while no dinons were on hand): their key is on this computer, so store
# them (encrypted) now — then every other device can copy them too. A few per refresh, silently.
_api_backfill_secrets() {
  [ -z "$_API_SVC" ] && [ -n "$_BB_LK" ] || return 0
  [ "${FILEAPI_BASHBASICS_STORE_KEYS:-1}" = "0" ] && return 0
  local i n=0 key
  for i in "${!_API_ID[@]}"; do
    [ -z "${_API_LENC[$i]:-}" ] || continue
    key=$(_bb_key_get "${_API_ID[$i]}") || continue
    _bb_link_secret_put "${_API_ID[$i]}" "${WORKER_URL%/}/${_API_PUB[$i]:-${_API_ID[$i]}}#k=$key" && _API_LENC[$i]="$_BB_LAST_SECRET_ENC"
    n=$((n + 1)); [ "$n" -ge 10 ] && break
  done
  return 0
}

# ── aliases ───────────────────────────────────────────────────────────────────
# An alias is stored ON THE SERVER (POST /links/<id>/alias), so it is the same on every computer and can
# be set or renamed for any link, also one made without an alias.
# ~/.bashbasicsbyvk/link_aliases (one line per link:  <id> TAB <alias>) is now only a PENDING list: a name
# that could not be sent (offline, error) — and names saved by older versions, which were local-only.
# They are pushed to the server the next time the list loads, then dropped from the file.
_API_ALIAS_FILE="${HOME}/.bashbasicsbyvk/link_aliases"
_API_ALIAS_PUSH_MAX=25      # at most this many pending names are pushed per refresh

# _api_alias_push <id> <alias|"">   ""/null removes the alias.  Sets _API_STATUS.
_api_alias_push() {
  local id="$1" al="$2" body
  if [ -n "$al" ]; then
    _BB_LINK_ALIAS="$al"; _bb_alias_prepare 2>/dev/null; _BB_LINK_ALIAS=""
    if [ -z "$_BB_LINK_ALIAS_WIRE" ]; then   # never send a name in clear
      _API_STATUS=409; _API_BODY='{"error":"no_dinons","message":"Names are stored encrypted — this computer has no usable dinons (or the server is unreachable)."}'
      return 1
    fi
    body="{\"alias\":\"$_BB_LINK_ALIAS_WIRE\"}"       # "e1." + base64url: no quotes/backslashes
  else body='{"alias":null}'; fi
  _api_http POST "/links/$id/alias" "$body" || return 1
  [ "$_API_STATUS" = "200" ]
}

# apply pending names on top of the server's, for display
_api_apply_aliases() {
  [ -f "$_API_ALIAS_FILE" ] || return 0
  local id al i
  while IFS=$'\t' read -r id al || [ -n "$id" ]; do
    [ -n "$id" ] && [ -n "$al" ] || continue
    for i in "${!_API_ID[@]}"; do
      [ "${_API_ID[$i]}" = "$id" ] && { _API_ALIAS[$i]="$al"; break; }
    done
  done < "$_API_ALIAS_FILE"
}

# _api_alias_store <id> <alias|"">   pending list: "" = forget the entry
_api_alias_store() {
  local id="$1" al="$2" tmp
  mkdir -p "$(dirname "$_API_ALIAS_FILE")" 2>/dev/null
  tmp="$(mktemp "${_API_ALIAS_FILE}.XXXXXX" 2>/dev/null)" || return 1
  { [ -f "$_API_ALIAS_FILE" ] && awk -F'\t' -v id="$id" '$1 != id' "$_API_ALIAS_FILE"
    [ -n "$al" ] && printf '%s\t%s\n' "$id" "$al"; true; } > "$tmp"
  if [ ! -s "$tmp" ]; then rm -f "$tmp" "$_API_ALIAS_FILE"; else mv -f "$tmp" "$_API_ALIAS_FILE"; fi
}

# after a successful list load: push pending names, drop the ones that are settled or whose link is gone
_api_sync_local_aliases() {
  [ -f "$_API_ALIAS_FILE" ] || return 0
  local -a pids=() pals=()
  local id al i pushed=0 found
  while IFS=$'\t' read -r id al || [ -n "$id" ]; do
    [ -n "$id" ] && [ -n "$al" ] || continue
    pids+=("$id"); pals+=("$al")
  done < "$_API_ALIAS_FILE"
  for i in "${!pids[@]}"; do
    id="${pids[$i]}"; al="${pals[$i]}"; found=-1
    local j
    for j in "${!_API_ID[@]}"; do [ "${_API_ID[$j]}" = "$id" ] && { found=$j; break; }; done
    if [ "$found" -lt 0 ]; then _api_alias_store "$id" ""; continue; fi            # link expired / nuked
    if [ "${_API_ALIAS[$found]}" = "$al" ]; then _api_alias_store "$id" ""; continue; fi   # server already has it
    [ "$pushed" -ge "$_API_ALIAS_PUSH_MAX" ] && continue
    pushed=$((pushed + 1))
    if _api_alias_push "$id" "$al"; then _API_ALIAS[$found]="$al"; _api_alias_store "$id" ""; fi
  done
}

# _api_do_alias <idx> [alias]  — set / rename (blank new name = cancel; "-" = remove the alias)
_api_do_alias() {
  local k="$1" new="${2:-}" id="${_API_ID[$1]}"
  echo "🏷️  Link $((k + 1)):  current alias: ${_API_ALIAS[$k]:-(none)}"
  if [ -z "$new" ]; then
    read -e -r -p "   New alias (blank = cancel, - = remove alias): " new
  fi
  new="${new#"${new%%[![:space:]]*}"}"; new="${new%"${new##*[![:space:]]}"}"
  [ -z "$new" ] && { echo "🚫 Skipped"; return 1; }
  if [ "$new" = "-" ]; then
    if _api_alias_push "$id" ""; then
      _api_alias_store "$id" ""
      echo "✅ Alias removed"
    else
      _api_fail; return 1
    fi
  else
    if [[ ! "$new" =~ $_BB_ALIAS_RE ]]; then
      echo "⚠️  Alias may use letters, digits, spaces and . _ @ + -  (1-48 characters)."; return 1
    fi
    if _api_alias_push "$id" "$new"; then
      _api_alias_store "$id" ""                     # settled on the server: no pending copy needed
      echo "✅ Alias: $new   (saved to the server)"
    elif [ "$_API_STATUS" = "000" ] || [[ "$_API_STATUS" == 5* ]]; then
      _api_alias_store "$id" "$new" || { echo "❌ Could not save"; return 1; }
      _api_fail
      echo "💾 Kept on this computer — it will be sent to the server the next time the list loads."
    else
      _api_fail; return 1
    fi
  fi
  _API_LOADED=0
  return 0
}

# ── copy / rebuild links ──────────────────────────────────────────────────────
# A link = <server>/<id>#k=<key>. The id is on the server; the key is kept on this computer (link_keys,
# see _3bvk_fileapi_lib.sh) from the moment a link is made. So any link can be copied or rebuilt at will —
# nothing is uploaded again. Links made before this feature have no stored key: attach it once with
# k-N (paste the old link) and they work too.

# drop keys of links that are gone (expired / nuked); only after a successful list load
_api_prune_keys() {
  [ -f "$_BB_KEY_FILE" ] || return 0
  local -a gone=()
  local id k i present
  while IFS=$'\t' read -r id k || [ -n "$id" ]; do
    [ -n "$id" ] || continue
    present=0
    for i in "${!_API_ID[@]}"; do [ "${_API_ID[$i]}" = "$id" ] && { present=1; break; }; done
    [ "$present" -eq 0 ] && gone+=("$id")
  done < "$_BB_KEY_FILE"
  for id in "${gone[@]}"; do _bb_key_store "$id" ""; done
}

# _api_link_url <idx>  → full link on stdout, status 1 when the key is unknown
_api_link_url() {
  local id="${_API_ID[$1]}" key
  key=$(_bb_key_get "$id") || key=$(_api_key_from_server "$1") || return 1
  printf '%s/%s#k=%s' "${WORKER_URL%/}" "${_API_PUB[$1]:-$id}" "$key"
}

# no key on this computer (a link made on another device): open the copy the server keeps — ciphertext it cannot read —
# with the label key (dinons), and remember the key here. The address is rebuilt from the CURRENT public id, so regenerating
# a link never makes the stored copy stale.
_api_key_from_server() {
  local enc="${_API_LENC[$1]:-}" full key
  [ -n "$enc" ] || return 1
  [ -n "$_BB_LK" ] || _bb_labelkey_load 2>/dev/null || return 1
  full=$(_bb_label_dec "$_BB_LK" "$enc")
  [[ "$full" == *"#k="* ]] || return 1
  key="${full#*#k=}"
  [[ "$key" =~ $_BB_KEY_RE ]] || return 1
  _bb_key_store "${_API_ID[$1]}" "$key" 2>/dev/null || true
  printf '%s' "$key"
}

# can this machine copy more than ~1 KB without bashbasicsbyvk_copy falling back to uploading it?
# (with no native clipboard tool that script UPLOADS anything over 1 KB — which would cost credits)
_api_clip_native() {
  local t
  for t in pbcopy clip.exe wl-copy xclip termux-clipboard-set; do command -v "$t" >/dev/null 2>&1 && return 0; done
  return 1
}

# c-LIST : copy the link(s) to the clipboard with bashbasicsbyvk_copy.  c-2   c-1,3   c-1-4
_api_cmd_copy() {
  local list="$1" idx k url out="" got=0 missing=0 n
  local -a ks=() shown=()
  for idx in $(parse_selection "$list" "${#items[@]}"); do ks+=("$((idx - 1))"); done
  if [ "${#ks[@]}" -eq 0 ]; then echo "⚠️  Usage: c-2   or   c-1,3-5   (copies the link to the clipboard)"; return 1; fi
  for k in "${ks[@]}"; do
    if url=$(_api_link_url "$k"); then
      out+="${url}"$'\n'; shown+=("$url"); got=$((got + 1))
    else
      echo "❌ $(_api_name "$k"): no key on this computer and none kept in the cloud (needs your dinons) — attach it with  k-$((k + 1))  (paste the old link once)"
      missing=$((missing + 1))
    fi
  done
  [ "$got" -gt 0 ] || return 1
  out="${out%$'\n'}"
  if ! command -v bashbasicsbyvk_copy >/dev/null 2>&1; then
    echo "⚠️  bashbasicsbyvk_copy not found — the link(s):"; printf '%s\n' "${shown[@]}"; return 1
  fi
  if [ "${#out}" -gt 1000 ] && ! _api_clip_native; then
    # no native clipboard: a long text would be uploaded instead of copied — keep to what fits in 1 KB
    local keep="" cnt=0 u
    for u in "${shown[@]}"; do
      [ $(( ${#keep} + ${#u} + 1 )) -gt 1000 ] && break
      keep+="${u}"$'\n'; cnt=$((cnt + 1))
    done
    out="${keep%$'\n'}"
    echo "ℹ️  No system clipboard here: only $cnt of $got link(s) fit one copy. Copy the rest separately."
    got=$cnt
  fi
  printf '%s' "$out" | bashbasicsbyvk_copy
  echo "📋 $got link(s) copied$( [ "$got" -gt 1 ] && printf ' (one per line)' )"
  [ "$missing" -gt 0 ] && echo "⚠️  $missing link(s) skipped: no stored key."
  return 0
}

# g-LIST : regenerate — give each link a NEW address; the old one stops working at once.
# Nothing is uploaded again: the data stays where it is, only the id in the address changes (the key stays).
_api_cmd_regen() {
  local list="$1" idx k ans ok=0 id
  local -a ks=() done_ks=()
  for idx in $(parse_selection "$list" "${#items[@]}"); do ks+=("$((idx - 1))"); done
  if [ "${#ks[@]}" -eq 0 ]; then echo "⚠️  Usage: g-2   or   g-1,3-5   (new address for the link; the old one dies)"; return 1; fi
  echo "🔄 Regenerate ${#ks[@]} link(s) — each gets a NEW address; the current address stops working immediately,"
  echo "   for everyone who has it. Nothing is re-uploaded, expiry and credits are unchanged."
  for k in "${ks[@]}"; do printf '   • %s\n' "$(_api_name "$k")"; done
  read -e -r -p "   Regenerate now? (y/N): " ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
  for k in "${ks[@]}"; do
    id="${_API_ID[$k]}"
    _api_http POST "/links/$id/regenerate" "{}" || return 1
    if [ "$_API_STATUS" = "200" ]; then
      echo "✅ $(_api_name "$k"): new address created"
      ok=$((ok + 1))
    else
      printf '%s  ' "$(_api_name "$k"):"; _api_fail
    fi
  done
  [ "$ok" -gt 0 ] || return 1
  _API_LOADED=0
  echo "ℹ️  Use  c-N  to copy the new link (numbers can change after a refresh)."
  return 0
}

# k-N [link] : remember the key of an existing link (for links made before keys were stored)
_api_cmd_key() {
  local arg="$1" num link="" key
  num="${arg%%[[:space:]]*}"
  [ "$num" != "$arg" ] && link="${arg#*[[:space:]]}"
  _api_pick "$num" || return 1
  local k="$_api_k" id="${_API_ID[$_api_k]}"
  echo "🔑 Link $((k + 1)): $(_api_name "$k")"
  if [ -z "$link" ]; then
    read -e -r -p "   Paste the full link (with #k=…), or just the key (blank = cancel): " link
  fi
  link="${link#"${link%%[![:space:]]*}"}"; link="${link%"${link##*[![:space:]]}"}"
  [ -z "$link" ] && { echo "🚫 Skipped"; return 1; }
  if [[ "$link" == *"#k="* ]]; then
    key="${link#*#k=}"
    local base="${link%%#*}"; base="${base%/}"
    if [ "${base##*/}" != "$id" ]; then echo "⚠️  That link is for a different upload — not saved."; return 1; fi
  else
    key="$link"
  fi
  if [[ ! "$key" =~ $_BB_KEY_RE ]]; then echo "⚠️  Not a valid key (43 characters: letters, digits, - and _)."; return 1; fi
  _bb_key_store "$id" "$key" || { echo "❌ Could not save"; return 1; }
  echo "✅ Key saved on this computer — c-$((k + 1)) now copies this link."
  if [ "${FILEAPI_BASHBASICS_STORE_KEYS:-1}" != "0" ] && _bb_link_secret_put "$id" "${WORKER_URL%/}/${_API_PUB[$_api_k]:-$id}#k=$key"; then
    _API_LENC[$_api_k]="$_BB_LAST_SECRET_ENC"; echo "☁️  Also kept (encrypted) in the cloud — other devices can copy it too."
  fi
}

_api_cmd_alias() {       # a-N [alias]      a-1-3 and a-1,3 not supported here: one link at a time
  local arg="$1" num name=""
  num="${arg%%[[:space:]]*}"
  [ "$num" != "$arg" ] && name="${arg#*[[:space:]]}"
  _api_pick "$num" || return 1
  _api_do_alias "$_api_k" "$name"
}

# ── formatting ────────────────────────────────────────────────────────────────
_api_hsize() {           # bytes → "3.2 MB"
  awk -v b="${1:-0}" 'BEGIN {
    split("B KB MB GB TB", u, " "); i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

_api_trunc() {
  local t="$1" m="$2"
  if [ "${#t}" -gt "$m" ]; then printf '%s…' "${t:0:$((m-1))}"; else printf '%s' "$t"; fi
}

# what to call link idx (0-based): its alias, else the start of its id. Never the full link.
_api_name() {
  local i="$1"
  if [ -n "${_API_ALIAS[$i]}" ]; then printf '%s' "${_API_ALIAS[$i]}"; else printf '(no alias) %s…' "${_API_ID[$i]:0:8}"; fi
}

# server "now" in ms, kept live from this computer's clock (no network, no fork)
_api_now_ms() {
  local t="${EPOCHSECONDS:-}"; [ -n "$t" ] || printf -v t '%(%s)T' -1
  _API_CUR=$(( _API_NOW + (t - _API_LOCAL) * 1000 ))
}

_api_left() {            # seconds left for link idx (0-based), counting down live
  _api_now_ms
  echo $(( (${_API_EXPIRES[$1]} - _API_CUR) / 1000 ))
}

# duration → $_api_dur, same wording as _bb_fmt_duration but without a subshell (runs every second)
_api_dur_v() {
  local s="$1" d h m
  (( s < 0 )) && s=0
  d=$((s / 86400)); h=$(( (s % 86400) / 3600 )); m=$(( (s % 3600) / 60 ))
  if   (( d > 0 )); then _api_dur="${d}d ${h}h ${m}m"                       # days: minutes tick
  elif (( h > 0 )); then _api_dur="${h}h ${m}m $(( s % 60 ))s"              # hours: seconds tick too
  elif (( m > 0 )); then _api_dur="${m}m $(( s % 60 ))s"
  else _api_dur="${s}s"; fi
}

# ── rows ──────────────────────────────────────────────────────────────────────
_api_rowtext() {
  local i="$1" k=$(( $1 - 1 )) icon="📦" left
  if [ -z "${_API_PRE[$k]+x}" ]; then          # the parts that never change are built once per refresh
    [ "${_API_KIND[$k]}" = copy ] && icon="📄"
    printf -v "_API_PRE[$k]"  ' %2d) %s %-28s %9s ' "$i" "$icon" "$(_api_trunc "$(_api_name "$k")" 28)" "$(_api_hsize "${_API_BYTES[$k]}")"
    printf -v "_API_POST[$k]" ' left   until %s' "$(_bb_fmt_when "${_API_EXPIRES[$k]}")"
  fi
  _api_now_ms
  left=$(( (${_API_EXPIRES[$k]} - _API_CUR) / 1000 ))
  if (( left <= 0 )); then _api_dur="expired"; else _api_dur_v "$left"; fi
  printf -v _vp_line '%s%11s%s' "${_API_PRE[$k]}" "$_api_dur" "${_API_POST[$k]}"
}

# once a second: refresh the countdown of the rows on screen (cursor and typed text stay where they are)
_api_tick() {
  local i
  [ "${_vp_rowtext_fn:-}" = _api_rowtext ] || return 0     # only while the Links list itself is on screen
  _vp_poll_active                                  # keep the 1 s rhythm — never drop to the slow idle poll
  for (( i=_vp_start; i<=_vp_end; i++ )); do
    unset "_vp_rowcache[$i]"
    _vp_repaint_row "$i"
  done
}

_api_menu_header() {
  echo
  case "$_API_SVC" in
    backup)
      printf '🗄️  BACKUP (bk)   💳 balance: %s credits\n' "${_API_BAL:-?}"
      printf '   copies taken just before you deleted something · soonest expiry first · r-N restores here · c-N copies its link\n' ;;
    saved)
      printf '💾 SAVED SURF (sv)   💳 balance: %s credits\n' "${_API_BAL:-?}"
      printf '   things you stored with  save-  · no link exists · opens from any device with your e-mail, diseps and API key · r-N restores here\n' ;;
    *)
      printf '🔗 LINKS (api)   💳 balance: %s credits\n' "${_API_BAL:-?}"
      printf '   soonest expiry first · shown by alias (up-1-3 as <alias>) · c-N copies a link · the key never leaves your machine\n' ;;
  esac
  [ -n "$_API_ERR" ] && printf '   ⚠️  %s — rf to retry\n' "$_API_ERR"
  if [ -z "$_API_ERR" ] && [ "${#items[@]}" -eq 0 ]; then
    case "$_API_SVC" in
      backup) printf '   No backups. They are made automatically when you delete (Settings → File API → Backup).\n' ;;
      saved)  printf '   Nothing saved yet. Try  save-1-3  or  save-2 as notes.\n' ;;
      *)      printf '   No active links. Make one with  up-1-3 as notes  or  c2c-2 as snippet.\n' ;;
    esac
  fi
  _vp_filter_header_line
}

_api_menu_footer() {
  case "$_API_SVC" in
    backup) _mc_footer "#[Backup]  ${#items[@]} active   🕐 times in $(_tz_label 2>/dev/null || date +%Z)  (change: s → Timezone)" \
      "N:Open" "r-N:Restore here" "c-N:Copy link" "a-N:Alias" "e-N:Expiry" "x-N:Nuke" "|" "rf:Refresh" "u:Exit" "bk:Close" ;;
    saved)  _mc_footer "#[Saved]  ${#items[@]} saved   🕐 times in $(_tz_label 2>/dev/null || date +%Z)  (change: s → Timezone)" \
      "N:Open" "r-N:Restore here" "a-N:Alias" "e-N:Expiry" "x-N:Nuke" "|" "rf:Refresh" "u:Exit" "sv:Close" ;;
    *)      _mc_footer "#[Links]  ${#items[@]} active   🕐 times in $(_tz_label 2>/dev/null || date +%Z)  (change: s → Timezone)" \
      "N:Open" "c-N:Copy link (c-1,3-5)" "g-N:New address" "a-N:Alias" "e-N:Expiry" "x-N:Nuke" "|" \
      "rf:Refresh" "u:Exit" "api:Close" ;;
  esac
}

_api_set_viewport() {
  _vp_mode="items"
  _vp_rowtext_fn=_api_rowtext
  _vp_header_fn=_api_menu_header
  _vp_footer_fn=_api_menu_footer
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  _vp_cache_reset
}

_api_build_items() {
  imaginary_mode=false
  _filter_reset_state
  items=()
  _hl_index=0
  if [ "$_API_LOADED" -eq 0 ]; then
    if declare -F _lb_run >/dev/null 2>&1; then _lb_run "Fetching your links" _api_load || true
    else echo "⏳ Fetching your links…"; _api_load; fi
  fi
  items=("${_API_ID[@]}")
  _all_items=("${items[@]}")
}

_api_redraw_fresh() {
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  _api_build_items
  _api_set_viewport
  _vp_render_from_top
}

# ── commands ──────────────────────────────────────────────────────────────────
_api_pick() {            # _api_pick <N>  → _api_k (0-based index)
  local num="$1"
  if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#items[@]}" ]; then
    echo "⚠️  Invalid link number: $num"; return 1
  fi
  _api_k=$((num - 1))
  return 0
}

_api_show() {            # details of link idx
  local k="$1"
  local _kind_txt='file upload' _kind_ico=📦
  [ "${_API_KIND[$k]}" = copy ] && { _kind_txt='text paste'; _kind_ico=📄; }
  [ "$_API_SVC" = backup ] && { _kind_txt='backup'; _kind_ico=🗄️; }
  [ "$_API_SVC" = saved ]  && { _kind_txt='saved item'; _kind_ico=💾; }
  echo "$_kind_ico $(_api_name "$k")   ($_kind_txt, $(_api_hsize "${_API_BYTES[$k]}"))"
  echo "   created : $(_bb_fmt_when "${_API_CREATED[$k]}")"
  echo "   expires : $(_bb_fmt_when "${_API_EXPIRES[$k]}")   ($(_bb_fmt_duration "$(_api_left "$k")") left)"
  echo "   life    : $(_bb_fmt_duration $(( (${_API_EXPIRES[$k]} - ${_API_CREATED[$k]}) / 1000 ))) in total · $(_bb_fmt_duration $(( (_API_NOW - ${_API_CREATED[$k]}) / 1000 ))) used · paid for ${_API_PAID[$k]} hour(s)"
  if [ "${_API_RFND[$k]}" -gt 0 ]; then
    echo "   nuke now: refunds ${_API_RFND[$k]} credit(s) (${_API_RFND_D[$k]} whole day(s))"
  else
    echo "   nuke now: no refund (whole days only — nothing unused is worth a full day)"
  fi
}

_api_cmd_open() {
  _api_pick "$1" || return 1
  _api_show "$_api_k"
  local ans
  case "$_API_SVC" in
    backup) read -e -r -p "   r) restore here   c) copy link   e) edit expiry   a) alias/rename   x) nuke   Enter) back: " ans ;;
    saved)  read -e -r -p "   r) restore here   e) edit expiry   a) alias/rename   x) nuke   Enter) back: " ans ;;
    *)      read -e -r -p "   c) copy link   g) regenerate link   e) edit expiry   a) alias/rename   x) nuke   Enter) back: " ans ;;
  esac
  case "${ans,,}" in
    r) [ -n "$_API_SVC" ] && _api_cmd_restore "$((_api_k + 1))" ;;
    c) [ "$_API_SVC" = saved ] || _api_cmd_copy "$((_api_k + 1))" ;;
    g) [ -z "$_API_SVC" ] && _api_cmd_regen "$((_api_k + 1))" ;;
    k) [ -z "$_API_SVC" ] && _api_cmd_key "$((_api_k + 1))" ;;
    a) _api_do_alias "$_api_k" "" ;;
    e) _api_do_edit "$_api_k" "" ;;
    x) _api_do_nuke "$_api_k" ;;
  esac
}

# new TOTAL life (seconds) from "2d" / "+12h" / "-1d" for link idx.  stdout: seconds.  Returns 1 with a message.
_api_resolve_time() {
  local k="$1" spec="$2" sign="" base cur secs
  spec="${spec#"${spec%%[![:space:]]*}"}"
  case "$spec" in
    +*|-*) sign="${spec:0:1}"; spec="${spec:1}" ;;
  esac
  if ! secs=$(_bb_parse_duration "$spec"); then
    echo "⚠️  Could not read '$spec' — use a number with a unit (s, m, h, d, w), e.g. 2d, 36h, +12h, -1d." >&2
    return 1
  fi
  cur=$(( (${_API_EXPIRES[$k]} - ${_API_CREATED[$k]}) / 1000 ))
  case "$sign" in
    +) base=$((cur + secs)) ;;
    -) base=$((cur - secs)) ;;
    *) base=$secs ;;
  esac
  if [ "$base" -lt "$_BB_NUKE_MIN" ] || [ "$base" -gt "$_BB_NUKE_MAX" ]; then
    echo "⚠️  Total life must be between 1 minute and 30 days (that would be $(_bb_fmt_duration "$base"))." >&2
    return 1
  fi
  if [ $(( ${_API_CREATED[$k]} + base * 1000 )) -le "$_API_NOW" ]; then
    echo "⚠️  That ends before now (the link is already $(_bb_fmt_duration $(( (_API_NOW - ${_API_CREATED[$k]}) / 1000 ))) old). Use  x-N  to nuke it instead." >&2
    return 1
  fi
  printf '%s' "$base"
}

_api_do_edit() {         # _api_do_edit <idx> [spec]
  local k="$1" spec="$2" total ans id="${_API_ID[$k]}"
  if [ -z "$spec" ]; then
    _api_show "$k"
    echo "   Enter the NEW TOTAL life counted from creation (2d · 36h · 1 week), or +12h to extend / -1d to shorten."
    echo "   Extending charges the extra time now; shortening refunds whole days only (time used rounds UP to a day)."
    read -e -r -p "   New time (u = back): " spec
    case "${spec,,}" in u|q|"") echo "↩️  Back"; return 0 ;; esac
  fi
  total=$(_api_resolve_time "$k" "$spec") || return 1
  local nexp=$(( ${_API_CREATED[$k]} + total * 1000 )) dir="extends"
  [ "$nexp" -lt "${_API_EXPIRES[$k]}" ] && dir="shortens"
  [ "$nexp" -eq "${_API_EXPIRES[$k]}" ] && dir="keeps"
  local costnote=""
  if [ "$dir" = extends ] && [ "$(_bb_cfg_val credit_prompts show)" != skip ]; then
    _api_http POST "/links/$id/expiry" "{\"totalSeconds\":$total,\"dryRun\":true}" || return 1
    if [ "$_API_STATUS" = 200 ]; then
      local ch0 bal0 mx0
      ch0=$(_bb_json_get "$_API_BODY" charge); bal0=$(_bb_json_get "$_API_BODY" balance); mx0=$(_bb_json_get "$_API_BODY" maxTotalSeconds)
      if [[ "$ch0" =~ ^[0-9]+$ && "$bal0" =~ ^[0-9]+$ ]]; then
        if [ "$ch0" -gt "$bal0" ]; then
          local cur0=$(( (${_API_EXPIRES[$k]} - ${_API_CREATED[$k]}) / 1000 ))
          if [[ "$mx0" =~ ^[0-9]+$ ]] && [ "$mx0" -gt "$cur0" ]; then
            echo "💳 Not enough credits: that extension costs $ch0, you have $bal0."
            read -e -r -p "   Longest you can afford: total life $(_bb_fmt_duration "$mx0"). Use that instead? (y/N): " ans
            case "$ans" in [yY]|[yY][eE][sS]) total="$mx0"; nexp=$(( ${_API_CREATED[$k]} + total * 1000 )) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
          else
            echo "❌ Not enough credits: that extension costs $ch0, you have $bal0 — and there is nothing you can afford to add."; return 1
          fi
        else
          costnote=" Costs $ch0 credit(s) (balance $bal0 → $((bal0 - ch0)))."
        fi
      fi
    fi
  fi
  read -e -r -p "   $(_api_name "$k"): total life → $(_bb_fmt_duration "$total") (gone at $(_bb_fmt_when "$nexp")) — this $dir it.$costnote Continue? (y/N): " ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
  _api_http POST "/links/$id/expiry" "{\"totalSeconds\":$total}" || return 1
  if [ "$_API_STATUS" != "200" ]; then _api_fail; return 1; fi
  local ch rf rd bal ex
  ch=$(_bb_json_get "$_API_BODY" charged); rf=$(_bb_json_get "$_API_BODY" refunded)
  rd=$(_bb_json_get "$_API_BODY" refundedDays); bal=$(_bb_json_get "$_API_BODY" balance); ex=$(_bb_json_get "$_API_BODY" expiresAt)
  echo "✅ Now gone at $(_bb_fmt_when "$ex")."
  if [ "${ch:-0}" -gt 0 ] 2>/dev/null; then echo "💳 Charged $ch credit(s)   |   Balance: $bal"
  elif [ "${rf:-0}" -gt 0 ] 2>/dev/null; then echo "💰 Refunded $rf credit(s) ($rd whole day(s))   |   Balance: $bal"
  else echo "💳 No credit change   |   Balance: $bal"; fi
  _API_LOADED=0
}

_api_do_nuke() {         # _api_do_nuke <idx>...
  local -a ks=("$@")
  local k total=0 ans
  echo "💥 Nuke ${#ks[@]} link(s) — the data is deleted immediately:"
  for k in "${ks[@]}"; do
    if [ "${_API_RFND[$k]}" -gt 0 ]; then
      printf '   • %s   (%s left, refund %s credit(s) / %s day(s))\n' "$(_api_name "$k")" "$(_bb_fmt_duration "$(_api_left "$k")")" "${_API_RFND[$k]}" "${_API_RFND_D[$k]}"
    else
      printf '   • %s   (%s left, no refund)\n' "$(_api_name "$k")" "$(_bb_fmt_duration "$(_api_left "$k")")"
    fi
    total=$((total + ${_API_RFND[$k]}))
  done
  echo "   Refund is in whole days only; time already used rounds up to a full day."
  read -e -r -p "   Nuke now and refund about $total credit(s)? (y/N): " ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
  local ok=0 bal="" rf rd
  for k in "${ks[@]}"; do
    _api_http DELETE "/links/${_API_ID[$k]}" || return 1
    if [ "$_API_STATUS" = "200" ]; then
      rf=$(_bb_json_get "$_API_BODY" refunded); rd=$(_bb_json_get "$_API_BODY" refundedDays); bal=$(_bb_json_get "$_API_BODY" balance)
      echo "✅ Nuked $(_api_name "$k")$( [ "${rf:-0}" -gt 0 ] 2>/dev/null && printf '  — refunded %s credit(s) (%s day(s))' "$rf" "$rd" )"
      ok=$((ok + 1))
    else
      printf '%s  ' "$(_api_name "$k"):"; _api_fail
    fi
  done
  [ -n "$bal" ] && echo "💳 Balance: $bal"
  _API_LOADED=0
  [ "$ok" -gt 0 ]
}

_api_cmd_edit() {        # e-N [spec]
  local arg="$1" num spec=""
  num="${arg%%[[:space:]]*}"
  [ "$num" != "$arg" ] && spec="${arg#*[[:space:]]}"
  _api_pick "$num" || return 1
  _api_do_edit "$_api_k" "$spec"
}

_api_cmd_restore() {     # r-N
  _api_pick "$1" || return 1
  _svc_restore "$_API_SVC" "${_API_ID[$_api_k]}" "$(_api_name "$_api_k")"
}

_api_cmd_nuke() {        # x-LIST
  local list="$1" idx
  local -a ks=()
  for idx in $(parse_selection "$list" "${#items[@]}"); do ks+=("$((idx - 1))"); done
  if [ "${#ks[@]}" -eq 0 ]; then echo "⚠️  Usage: x-3   or   x-1,3-5"; return 1; fi
  _api_do_nuke "${ks[@]}"
}

_api_help() {
  case "$_API_SVC" in
    backup) cat <<'HLP'
🗄️  BACKUP  (bk)
 A copy of what you deleted, taken just before it was deleted (Settings → File API → Backup). Named DDMMYYYY HHMM NAME.
 N open · r-N restore into the current folder (never overwrites: "name (1)") · c-N copy its link · a-N [name] rename · e-N [time] extend / shorten · x-N nuke
 time rules, credits and refunds are exactly those of Links (api). Default keep time: Settings → File API → Backup.
 Backups are client-side encrypted like Saved Surf: restore them from ANY device where you have your dinons.
HLP
      return ;;
    saved) cat <<'HLP'
💾 SAVED SURF  (sv)
 Things stored with  save-1-3  or  save-2 as tax papers  — no link exists. Named DDMMYYYY HHMM NAME.
 N open · r-N restore into the current folder · a-N [name] rename · e-N [time] extend / shorten · x-N nuke
 Open from any device with your e-mail + diseps + API key + dinons. Client-side encrypted (like ux-): the key is wrapped with your
 FEK on your computer, so the server never holds a key it can open. The data is served to you alone; the wrapped key is destroyed when the item expires.
HLP
      return ;;
  esac
  cat <<'HLP'
🔗 LINKS  (api)
 Every active link you made with up- / c2c-, soonest expiry first. Shown by ALIAS:
   up-1-3 as user data      c2c-2 as snippet      (no alias → the start of the id)
 N open · c-N copy link (c-1,3-5 several; rebuilt from the key kept on this computer) · g-N new address (old one dies, no re-upload) · k-N attach key of an older link · a-N [name] set/rename alias, saved on the server (a-N - removes it) · e-N [time] edit expiry · x-N nuke (x-1,3-5 several) · rf refresh · u exit · api close
 time = the NEW TOTAL life from creation:  2d · 36h · 1 week     or  +12h extend / -1d shorten
   limits 1 minute – 30 days
 extend  → the extra time is charged now (1 credit per GB per hour, size-bucket minimums, as an upload)
 shorten / nuke → refunded in WHOLE DAYS only; time already used rounds UP to a full day
   (30 days, nuked after 1 day + 1 minute → 28 days refunded)
 Keys of NEW links are kept on this computer (~/.bashbasicsbyvk/link_keys, never sent to the server), so c-N can
 rebuild a link without uploading anything. Older links: k-N once. Disable storing with FILEAPI_BASHBASICS_STORE_KEYS=0.
 Change the default lifetime of new links in Settings → Nuke time.
HLP
}

# ── the loop ──────────────────────────────────────────────────────────────────
api_menu() {
  local _ap_saved_prefix="$group_prefix" _ap_saved_force="$force_show"
  local _ap_saved_all=("${_all_items[@]}")
  group_prefix=""
  force_show=false
  _fx_in_mode=1
  _sw_in_mode=1                    # keeps the ←/→ sentinels from leaking out as text (no tabs here)
  _API_LOADED=0
  local _ap_saved_fast="$_vp_poll_fast" _ap_saved_tick="${_vp_tick_fn:-}"
  _vp_poll_fast=1; _vp_poll_cur=1; _vp_tick_fn=_api_tick

  local _ap_choice _ap_fresh
  shopt -s nullglob

  _api_redraw_fresh

  while true; do
    _read_choice_filtered
    _ap_choice="$choice"
    shopt -s nocasematch

    case "$_ap_choice" in
      __sw_tab_right__|__sw_tab_left__) shopt -u nocasematch; continue ;;
    esac

    _ap_fresh=true
    case "$_ap_choice" in
      api|bk|sv|u) echo "↩️  Closing the $( [ "$_API_SVC" = backup ] && echo backup || { [ "$_API_SVC" = saved ] && echo saved || echo links; } ) loop"; break ;;

      fx) _inner_next=fx;  break ;;
      sw) _inner_next=sw;  break ;;
      .r) _inner_next=r;   break ;;
      -u) _inner_next=upg; break ;;

      q) _fx_in_mode=0; _sw_in_mode=0; _bvk_quit ;;

      -h) _api_help; _ap_fresh=false ;;

      rf) _API_LOADED=0 ;;                       # rebuilt (and re-fetched) below

      r-*) if [ -n "$_API_SVC" ]; then _api_cmd_restore "${_ap_choice#[rR]-}" || true; else echo "⚠️  r-N restores a Backup / Saved item — open them with  bk  or  sv."; _ap_fresh=false; fi ;;
      c-*) if [ "$_API_SVC" = saved ]; then echo "ℹ️  Saved items have no link — that is the point. Use r-N to restore."; _ap_fresh=false; else _api_cmd_copy "${_ap_choice#[cC]-}" || true; fi ;;
      g-*) if [ -n "$_API_SVC" ]; then echo "ℹ️  Only plain links can get a new address."; _ap_fresh=false; else _api_cmd_regen "${_ap_choice#[gG]-}" || true; fi ;;
      k-*) if [ -n "$_API_SVC" ]; then echo "ℹ️  Keys of Backup / Saved items are managed for you."; _ap_fresh=false; else _api_cmd_key "${_ap_choice#[kK]-}" || true; fi ;;
      a-*) _api_cmd_alias "${_ap_choice#[aA]-}" || true ;;
      e-*) _api_cmd_edit "${_ap_choice#[eE]-}" || true ;;
      x-*) _api_cmd_nuke "${_ap_choice#[xX]-}" || true ;;

      # (no  f  here: find works on a folder, and this loop does not show one — falls through to Invalid selection)
      disk) df -h; _ap_fresh=false ;;
      ram)  free -h; _ap_fresh=false ;;

      _*) _ap_fresh=false ;;

      *)
        if ! [[ "$_ap_choice" =~ ^[0-9]+$ ]] || [ "$_ap_choice" -lt 1 ] || [ "$_ap_choice" -gt "${#items[@]}" ]; then
          _bvk_invalid _ap_fresh
        else
          _api_cmd_open "$_ap_choice" || true
        fi ;;
    esac

    shopt -u nocasematch
    # after an edit / nuke the list is re-fetched (_API_LOADED=0), so numbers and times are current
    $_ap_fresh && _api_redraw_fresh
  done

  shopt -u nocasematch
  _vp_poll_fast="$_ap_saved_fast"; _vp_poll_cur="$_ap_saved_fast"; _vp_tick_fn="$_ap_saved_tick"
  _fx_in_mode=0
  _sw_in_mode=0
  _vp_rowtext_fn=""
  group_prefix="$_ap_saved_prefix"
  force_show="$_ap_saved_force"
  _all_items=("${_ap_saved_all[@]}")
}


# Backup (bk) and Saved Surf (sv): the same list manager, filtered by service.
# Backup keys live in their own file so the Links screen never prunes them (and vice versa).
backup_menu() { local _API_SVC=backup _BB_KEY_FILE="${HOME}/.bashbasicsbyvk/backup_keys"; api_menu; }
saved_menu()  { local _API_SVC=saved; api_menu; }
