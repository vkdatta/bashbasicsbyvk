# ux-  —  client-side encrypted (CSE) sharing with people you already linked in RBAM.
# ════════════════════════════════════════════════════════════════════════════
#  ux-<items> [as <alias>]      e.g.  ux-1-5   ·   ux-a-1-5 as project files
#
#  It is  up-  with three differences (packing, encrypting, uploading, downloading and unpacking are the SAME
#  method and the SAME echoes as up- / do-: tar.gz streamed → 16 MiB encrypted chunks; no limit on how many files):
#    • no link is ever made — the recipients are people you set up in  rbam  (a "pre-shared preset")
#    • no end-to-end link key: client-side encryption (CSE) with your File Encryption Key (FEK)
#    • you choose WHO gets it; they get a notification and accept it into their Cloud Surf (cs)
#
#  Crypto (see _3bvk_ux_core):
#    FEK      256-bit key made when the user was created. The server only ever stores it encrypted with your 29 dinons.
#    K        a fresh random key for every share. Encrypts every file chunk and every file NAME.
#    kdk      K encrypted with your FEK — the only thing about K the server keeps.
#  A receiver who holds your dinons (sent to them SEALED, so the server cannot read them) opens your FEK, then K.
#  Regenerate your dinons in -auth and every holder of the old ones is locked out.
#
#  Price + nuke time: same price list as up-, whole period paid up front. Default life 30 days (Settings → Nuke time (ux-)).
#  Refund only when the data is really gone from our storage and database: you nuke the share (cs), or shorten it.
#
#  Shared helpers here (_ux_*) are also used by rbam, nf and cs.
# ════════════════════════════════════════════════════════════════════════════

_UX_STATUS=""; _UX_BODY=""; _UX_FEK=""; _UX_K=""
declare -gA _UX_RFEK=()      # sender rel id -> that sender's FEK (hex), for this session only
_UX_FEK_SELF=""; _UX_FEK_SELF_FOR=""
_UX_SEAL_FOR=""
_UX_CORE=""

# ── plumbing ─────────────────────────────────────────────────────────────────
_ux_core() {
  if [ -z "$_UX_CORE" ]; then
    _UX_CORE="$(command -v _3bvk_ux_core 2>/dev/null)"
    if [ -z "$_UX_CORE" ]; then
      local d; d="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null)")/.." 2>/dev/null && pwd)"
      [ -r "$d/_3bvk_ux_core" ] && _UX_CORE="$d/_3bvk_ux_core"
    fi
    [ -n "$_UX_CORE" ] || { echo "❌ _3bvk_ux_core not found (reinstall bashbasicsbyvk)." >&2; return 127; }
  fi
  node "$_UX_CORE" "$@"
}

# the ux- nuke time (Settings), falling back to the config file, then 30 days
_bb_ux_nuke_seconds() {
  local v="${ux_nuke_time_seconds:-}"
  if [ -z "$v" ]; then
    local cf="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/config"
    [ -r "$cf" ] && v=$(sed -n 's/^ux_nuke_time_seconds=\([0-9]\{1,9\}\)$/\1/p' "$cf" 2>/dev/null | tail -n 1)
  fi
  if [[ "$v" =~ ^[0-9]{1,9}$ ]] && [ "$v" -ge "$_BB_NUKE_MIN" ] && [ "$v" -le "$_BB_NUKE_MAX" ]; then printf '%s' "$v"
  else printf '%s' 2592000; fi
}

# _ux_http METHOD PATH [json-body] -> _UX_STATUS / _UX_BODY. Credentials go to curl on stdin, never argv.
_ux_http() {
  local method="$1" path="$2" body="${3:-}" cfg out
  _bb_get_credentials || return 1
  cfg=$({ _bb_auth_cfg; [ -n "$body" ] && _bb_cfg_header Content-Type application/json; true; })
  if [ -n "$body" ]; then
    out=$(curl -s --max-time 60 "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X "$method" --data-binary "$body" "$WORKER_URL$path" <<<"$cfg")
  else
    out=$(curl -s --max-time 60 "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X "$method" "$WORKER_URL$path" <<<"$cfg")
  fi
  _UX_STATUS="${out##*$'\n'}"
  _UX_BODY="${out%$'\n'*}"
  [[ "$_UX_STATUS" =~ ^[0-9]{3}$ ]] || _UX_STATUS=000
  return 0
}
_ux_ok() { [ "$_UX_STATUS" = 200 ] || [ "$_UX_STATUS" = 201 ]; }
_ux_fail() {
  case "$_UX_STATUS" in
    000) echo "❌ Could not reach the server (offline?)." ;;
    401) echo "❌ $(_bb_json_get "$_UX_BODY" message)"; echo "🔁 Fix the active user with  -auth  inside 'o', then try again." ;;
    *)   echo "❌ $(_bb_fail_reason "$_UX_BODY" "$_UX_STATUS")" ;;
  esac
}
# JSON path -> value ("share.kdk")
_ux_jget() { _ux_core jget "$1" <<<"$2"; }

_ux_profile_file() {
  local id; id=$(cat "$_BVK_AUTH_DIR/active" 2>/dev/null)
  [[ "$id" =~ ^p_[0-9a-f]{16}$ ]] || return 1
  printf '%s' "$_BVK_AUTH_DIR/profiles/$id"
}

# node + an active user (loads P_* of the profile). need_dinons=1 also demands the dinons.
_ux_need() {
  _crypto_check || return 1
  _bb_get_credentials || return 1
  if [ "${1:-0}" = 1 ] && [ -z "$P_DINONS" ]; then
    echo "❌ The active user has no dinons on this machine. They are needed to encrypt / open shares." >&2
    echo "   Import your credentials file (-auth → ui) — it must contain the dinons line." >&2
    return 1
  fi
  return 0
}

# ── sealing key: lets a sender seal their dinons for you; the server cannot open them ──────────
_ux_ensure_seal() {
  _ux_need || return 1
  [ "$_UX_SEAL_FOR" = "$FILEAPI_BASHBASICS_DISEPS" ] && return 0
  local f out pub
  f=$(_ux_profile_file) || { echo "❌ No active user." >&2; return 1; }
  if [ -z "$P_SEALKEY" ]; then
    out=$(_ux_core seal-keygen) || { echo "❌ Could not create a sealing key." >&2; return 1; }
    P_SEALKEY="${out%%$'\n'*}"
    _bvk_auth_write "$f"
  fi
  pub=$(BB_PRIV="$P_SEALKEY" _ux_core seal-pub) || { echo "❌ The saved sealing key is unreadable." >&2; return 1; }
  _ux_http POST /rbam/seal-key "{\"pub\":\"$pub\"}" || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  _UX_SEAL_FOR="$FILEAPI_BASHBASICS_DISEPS"
  return 0
}

# ── dinons → receivers (sealed) ─────────────────────────────────────────────
# _ux_sync_dinons auto             send to active receivers who never had them (not the ones "held" after a regeneration)
# _ux_sync_dinons force [rid...]   send to every active receiver without them (or just the listed ones)
_ux_sync_dinons() {
  local mode="${1:-auto}"; shift
  local -a only=("$@")
  _ux_ensure_seal || return 1
  [ -n "$P_DINONS" ] || return 0
  _ux_http GET /rbam/rels || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local rows rid mail d3 st mine din seal held pub sealed sent=0 skipped=0 want
  rows=$(_ux_core tsv gives <<<"$_UX_BODY")
  while IFS=$'\x1f' read -r rid mail d3 st mine din seal held; do
    [ -n "$rid" ] || continue
    [ "$st" = active ] && [ "$din" = 0 ] || continue
    if [ "${#only[@]}" -gt 0 ]; then
      want=0; local o; for o in "${only[@]}"; do [ "$o" = "$rid" ] && want=1; done
      [ "$want" = 1 ] || continue
    elif [ "$mode" = auto ] && [ "$held" = 1 ]; then continue; fi
    if [ "$seal" != 1 ]; then
      echo "   ⏳ $mail has not opened RBAM yet (no sealing key) — their dinons will be sent next time." >&2
      skipped=$((skipped+1)); continue
    fi
    _ux_http GET "/rbam/pub/$rid" || continue
    _ux_ok || { _ux_fail >&2; continue; }
    pub=$(_bb_json_get "$_UX_BODY" pub)
    sealed=$(printf '%s' "$P_DINONS" | BB_PUB="$pub" _ux_core seal) || continue
    _ux_http POST /rbam/dinons "{\"rid\":$rid,\"sealed\":\"$sealed\"}" || continue
    if _ux_ok; then sent=$((sent+1)); echo "   🔑 Sent your dinons (sealed) to $mail"; else _ux_fail >&2; fi
  done <<<"$rows"
  return 0
}

# ── key chain: dinons -> FEK -> K ────────────────────────────────────────────
_ux_self_fek() {                              # -> _UX_FEK  (hex)
  _ux_need 1 || return 1
  if [ -n "$_UX_FEK_SELF" ] && [ "$_UX_FEK_SELF_FOR" = "$FILEAPI_BASHBASICS_DISEPS" ]; then _UX_FEK="$_UX_FEK_SELF"; return 0; fi
  local blob fek
  _ux_http GET /auth/fek || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  blob=$(_bb_json_get "$_UX_BODY" fek_wrapped)
  fek=$(_bvk_auth_fek_unwrap "$blob" "$P_DINONS") || { echo "❌ Your dinons on this machine cannot open your key (wrong or outdated dinons)." >&2; return 1; }
  _UX_FEK_SELF="$fek"; _UX_FEK_SELF_FOR="$FILEAPI_BASHBASICS_DISEPS"; _UX_FEK="$fek"
}

_ux_recv_fek() {                              # $1 = rbam rel id of the sender -> _UX_FEK
  local rid="$1"
  if [ -n "${_UX_RFEK[$rid]:-}" ]; then _UX_FEK="${_UX_RFEK[$rid]}"; return 0; fi
  _ux_ensure_seal || return 1
  _ux_http GET "/rbam/keys/$rid" || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local sealed wrapped dinons fek
  sealed=$(_bb_json_get "$_UX_BODY" sealed_dinons); wrapped=$(_bb_json_get "$_UX_BODY" fek_wrapped)
  dinons=$(printf '%s' "$sealed" | BB_PRIV="$P_SEALKEY" _ux_core unseal) || {
    echo "❌ Cannot open the dinons they sent you: they were sealed to a different key than the one on this machine." >&2
    echo "   Import your full credentials (with sealkey) here, or ask them to send the dinons again." >&2
    return 1; }
  fek=$(_bvk_auth_fek_unwrap "$wrapped" "$dinons") || {
    echo "❌ The dinons you hold no longer open the sender's key — they regenerated their dinons." >&2
    echo "   Ask them to send you the new ones (rbam → Give access → sd)." >&2
    return 1; }
  _UX_RFEK[$rid]="$fek"; _UX_FEK="$fek"
}
_ux_forget_keys() { _UX_RFEK=(); _UX_FEK=""; _UX_K=""; _UX_FEK_SELF=""; _UX_FEK_SELF_FOR=""; }

# share-detail JSON (from GET /ux/<id>) -> _UX_K (the share's data key)
_ux_K_of() {
  local json="$1" role kdk rid
  role=$(_ux_jget role "$json"); kdk=$(_ux_jget share.kdk "$json")
  if [ "$role" = owner ]; then _ux_self_fek || return 1
  else rid=$(_ux_jget from.rid "$json"); _ux_recv_fek "$rid" || return 1; fi
  _UX_K=$(printf '%s' "$kdk" | BB_FEK="$_UX_FEK" _ux_core dk-unwrap) || { echo "❌ The share key failed its integrity check." >&2; return 1; }
}

# ── people picker (the "with whom to share" menu) ────────────────────────────
declare -ga _UX_PK_RID=() _UX_PK_MAIL=() _UX_PK_D3=()
declare -ga _UX_PICKED=()

ux_pk_build() { _xui_begin_items "${_UX_PK_MAIL[@]}"; }
ux_pk_row() { _xui_slot "$1"; printf -v _vp_line ' %2d) 👤 %s   [%s…]' "$1" "${_UX_PK_MAIL[$_XUI_SLOT]}" "${_UX_PK_D3[$_XUI_SLOT]:0:6}"; }
ux_pk_header() { echo; echo "📨 Share with whom?   (only people you linked in rbam → Give access)"; _vp_filter_header_line; }
ux_pk_footer() { printf '\n1,3-5) several   a) everyone   Enter) send   (u = cancel)\n'; }

# active receivers -> arrays ; returns 1 when there is nobody
_ux_load_people() {
  _UX_PK_RID=(); _UX_PK_MAIL=(); _UX_PK_D3=()
  _ux_http GET /rbam/rels || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local rows rid mail d3 st mine din seal held
  rows=$(_ux_core tsv gives <<<"$_UX_BODY")
  while IFS=$'\x1f' read -r rid mail d3 st mine din seal held; do
    [ "$st" = active ] || continue
    _UX_PK_RID+=("$rid"); _UX_PK_MAIL+=("$mail"); _UX_PK_D3+=("$d3")
  done <<<"$rows"
  [ "${#_UX_PK_RID[@]}" -gt 0 ]
}

# -> _UX_PICKED (rbam rel ids). Returns 1 on cancel / nobody.
_ux_pick_people() {
  _UX_PICKED=()
  if ! _ux_load_people; then
    echo "ℹ️  You have nobody to share with yet. Open  rbam → Give access  and add people first (ui)."
    return 1
  fi
  _xui_enter
  items=("${_UX_PK_MAIL[@]}"); _hl_index=0
  _xui_screen ux_pk
  _xui_set ux_pk
  local rc=1 r
  if _xui_select_rows "SHARE WITH" "📨 Share with — which people?"; then
    for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; _UX_PICKED+=("${_UX_PK_RID[$_XUI_SLOT]}"); done
    rc=0
  fi
  _xui_leave
  return $rc
}

# ── the init step (auth + credit precheck), like _bb_upload_init ─────────────
# prints "<id>\n<token>" ; messages on stderr
_ux_init() {
  local est="$1" confirmed=false cfg response status body err msg ans
  _bb_get_credentials || return 1
  while :; do
    cfg=$({ _bb_auth_cfg
            _bb_cfg_header X-Estimated-Size "$est"
            _bb_cfg_header X-Nuke-Seconds "$(_bb_ux_nuke_seconds)"
            [ -n "$_BB_LINK_ALIAS" ] && _bb_cfg_header X-Link-Alias "$_BB_LINK_ALIAS"
            $confirmed && _bb_cfg_header X-Confirm-Oversized yes
            true; })
    response=$(curl -s --max-time 60 "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X PUT "$WORKER_URL/ux/init" <<<"$cfg")
    status="${response##*$'\n'}"; body="${response%$'\n'*}"
    if [ "$status" = 200 ]; then
      local id token; id=$(_bb_json_get "$body" id); token=$(_bb_json_get "$body" token)
      [ -n "$id" ] && [ -n "$token" ] || { echo "❌ Server did not return a share id/token" >&2; return 1; }
      printf '%s\n%s\n' "$id" "$token"; return 0
    fi
    err=$(_bb_json_get "$body" error); msg=$(_bb_json_get "$body" message)
    if [ "$status" = 401 ]; then echo "❌ ${msg:-Authentication failed.}" >&2; echo "🔁 Fix the active user with  -auth  inside 'o', then try again." >&2; return 1; fi
    if [ "$status" = 409 ] && [ "$err" = oversized_confirmation_required ] && ! $confirmed; then
      echo "⚠️  ${msg}" >&2
      read -r -p "   Proceed at 1.2x credit cost? (y/n): " ans
      if [[ "$ans" == y || "$ans" == Y ]]; then confirmed=true; continue; fi
      echo "🚫 Cancelled." >&2; return 1
    fi
    echo "❌ $(_bb_fail_reason "$body" "$status")" >&2
    return 1
  done
}

# ── the share ────────────────────────────────────────────────────────────────
_ux_do_share() {
  local -a paths=("$@")
  _ux_need 1 || return 1

  # 1) recipients + make sure they can read what we send (dinons, sealed)
  _ux_ensure_seal || return 1
  _ux_sync_dinons auto
  _ux_pick_people || { echo "↩️  Nothing was shared."; return 1; }
  local -a rids=("${_UX_PICKED[@]}")
  local rid_csv; rid_csv=$(IFS=,; echo "${rids[*]}")

  # 2) keys
  _ux_self_fek || return 1
  local K kdk
  K=$(_ux_core newkey) && kdk=$(printf '' | BB_FEK="$_UX_FEK" BB_K="$K" _ux_core dk-wrap) || { echo "❌ Key generation failed."; return 1; }

  if ! command -v tar &>/dev/null || ! command -v gzip &>/dev/null; then
    echo "❌ 'tar' and 'gzip' are required for ux- (pkg install tar gzip)."
    return 1
  fi
  local -a gz=(gzip)
  command -v pigz &>/dev/null && gz=(pigz)          # parallel gzip when available
  local lvl="${FILEAPI_BASHBASICS_GZIP_LEVEL:-6}"
  [[ "$lvl" =~ ^[1-9]$ ]] || lvl=6

  echo "🔎 Scanning selection..."
  local stage tmpdir rcfile errfile
  stage=$(mktemp -d) && tmpdir=$(mktemp -d) && rcfile=$(mktemp) && errfile=$(mktemp) \
    || { echo "❌ Could not create temp files."; return 1; }
  chmod 700 "$stage" "$tmpdir"
  _ux_cleanup() { rm -rf "$stage" "$tmpdir" "$rcfile" "$errfile"; K=""; }

  local -a rel_items=()
  local p bn cand n
  for p in "${paths[@]}"; do
    p="${p%/}"; [[ "$p" == /* ]] || p="$PWD/$p"
    if [ ! -f "$p" ] && [ ! -d "$p" ]; then echo "  ⚠️  Skipping missing item: $p" >&2; continue; fi
    bn="${p##*/}"; cand="$bn"; n=1
    while [ -e "$stage/$cand" ] || [ -L "$stage/$cand" ]; do n=$((n + 1)); cand="${bn}_$n"; done
    ln -s "$p" "$stage/$cand"
    rel_items+=("./$cand")                            # "./" so a name starting with "-" is never an option
  done
  [ ${#rel_items[@]} -gt 0 ] || { echo "❌ No valid files found in selection"; _ux_cleanup; return 1; }

  # hidden files inside the chosen folders: Settings → Hidden files (ux-)
  _hidden_decide "${ux_hidden_mode:-follow}" "the share" "${paths[@]}" || { _ux_cleanup; return 1; }
  local hid_inc="$_hid_inc"

  local arcname="files.tar.gz"
  [ ${#rel_items[@]} -eq 1 ] && arcname="${rel_items[0]#./}.tar.gz"
  arcname=$(printf '%s' "$arcname" | LC_ALL=C tr -c 'A-Za-z0-9._ -' '_' | cut -c1-120)

  # 3) pack tar.gz → encrypt, streamed (plaintext archive never touches the disk) — exactly like up-
  echo "📦 Packing tar.gz → 🔐 encrypting (streamed: the unencrypted archive never touches the disk)"
  local packout
  packout=$(
    cd "$stage" || exit 1
    _hid_find0 "$hid_inc" 1 "${rel_items[@]}" 2>> "$errfile" \
      | { tar --null --no-recursion -h -T - -cf - 2>> "$errfile"; echo $? > "$rcfile"; } \
      | "${gz[@]}" "-$lvl" -c \
      | BB_K="$K" BB_KDK="$kdk" _ux_core pack "$tmpdir" "$arcname"
  )

  local total_size nitems nblobs tar_rc
  total_size=$(printf '%s' "$packout" | sed -n '1p'); nitems=$(printf '%s' "$packout" | sed -n '2p')
  nblobs=$(printf '%s' "$packout" | sed -n '3p')
  tar_rc=$(cat "$rcfile" 2>/dev/null)

  if [[ ! "$total_size" =~ ^[0-9]+$ ]] || [[ ! "$nblobs" =~ ^[0-9]+$ ]]; then
    echo "❌ Packing/encryption failed"
    [ -s "$errfile" ] && head -n 3 "$errfile" | sed 's/^/   /'
    _ux_cleanup; return 1
  fi
  if [ -z "$tar_rc" ] || [ "$tar_rc" -ge 2 ]; then
    echo "❌ tar failed (exit ${tar_rc:-?}) — upload aborted."
    [ -s "$errfile" ] && head -n 3 "$errfile" | sed 's/^/   /'
    _ux_cleanup; return 1
  fi
  if [ "$tar_rc" -eq 1 ]; then
    echo "⚠️  Some files changed or were unreadable while packing (they may be missing/partial):"
    head -n 3 "$errfile" | sed 's/^/   /'
  fi
  echo "   $((total_size/1024/1024)) MB after tar.gz + encryption, in $nblobs blob(s)."

  if [ "$total_size" -gt "$_SP_HARD_LIMIT_BYTES" ]; then
    echo "❌ Packed size is $((total_size/1024/1024/1024))GB — exceeds the absolute upload ceiling"
    _ux_cleanup; return 1
  fi
  if [ "$total_size" -gt "$_SP_SOFT_UPLOAD_BYTES" ]; then
    echo "ℹ️  Packed size is over the 10GB soft limit — the server will ask you to confirm at 1.2x credit cost."
  fi

  # 4) init (auth + credit precheck) → parallel blob uploads → commit
  local init_out id token
  init_out=$(_ux_init "$total_size") || { _ux_cleanup; return 1; }
  id=$(printf '%s' "$init_out" | sed -n '1p'); token=$(printf '%s' "$init_out" | sed -n '2p')
  if [ -z "$id" ] || [ -z "$token" ]; then
    echo "❌ Upload init failed (no id returned)"; _ux_cleanup; return 1
  fi

  [ -t 2 ] || echo "☁️  Uploading $nblobs encrypted blob(s) — up to $_BB_MAX_PAR in parallel..."
  local upres
  upres=$(BB_UTOKEN="$token" BB_CONC="$_BB_MAX_PAR" _ux_core upload "$WORKER_URL" "$id" "$tmpdir")
  if [ "$upres" != OK ]; then
    _ux_cleanup
    echo "❌ One or more parts failed to upload. Nothing was finalized; partial objects are removed automatically within a few hours."
    return 1
  fi

  local cfg hdrfile response status body
  cfg=$({ _bb_cfg_header X-Upload-Token "$token"; _bb_cfg_header X-Ux-Recipients "$rid_csv"; })
  hdrfile=$(mktemp)
  response=$(curl -s --max-time 120 "${_BB_CURL_OPTS[@]}" -K - -D "$hdrfile" -w "\n%{http_code}" -H "Expect:" -H "Content-Type: application/json" -X PUT \
    --data-binary "@$tmpdir/commit.json" "$WORKER_URL/ux/$id/commit" <<<"$cfg")
  status="${response##*$'\n'}"; body="${response%$'\n'*}"
  local deducted balance expires
  deducted=$(grep -i '^X-Credits-Deducted:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
  balance=$(grep -i '^X-Credits-Balance:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
  expires=$(grep -i '^X-Link-Expires:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
  rm -f "$hdrfile"; _ux_cleanup
  if [ "$status" != 201 ]; then echo "❌ $(_bb_fail_reason "$body" "$status")"; return 1; fi

  echo "✅ Shared with ${#rids[@]} person(s). No link exists — each of them gets a notification and accepts it into their Cloud Surf."
  [ -n "$deducted" ] && echo "💳 Credits deducted: $deducted   |   Balance: $balance"
  local secs; secs=$(_bb_ux_nuke_seconds)
  local label="🕐 Nuke time: $(_bb_fmt_duration "$secs")"
  [ "$secs" -lt 3600 ] && label+=" (billed as 1 hour)"
  [ -n "$expires" ] && label+="  →  gone at $(_bb_fmt_when "$expires")"
  [ -n "$_BB_LINK_ALIAS" ] && label+="   |   alias: $_BB_LINK_ALIAS"
  echo "$label"
  echo "   Manage who can see what — or nuke it for everyone — in  cs  (Home → Cloud Surf)."
  return 0
}

# ux-<items> [as <alias>]
handle_ux_upload() {
  local raw="$1"
  _bb_split_alias "${raw#ux-}" || return
  local itemlist="$_BB_ITEMLIST" rc
  _sp_guard_and_resolve "$itemlist" "ux-" || { _BB_LINK_ALIAS=""; return; }
  _ux_do_share "${sp_resolved[@]}"; rc=$?
  _BB_LINK_ALIAS=""
  return $rc
}
