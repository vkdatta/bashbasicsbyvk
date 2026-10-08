# -auth  --  profile manager (create / remove / import / export users, act as a user).
#
# Local store:  ${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/   (dir 700, files 600)
#   profiles/<id>   one profile per file, KEY=VALUE lines (never `source`d -- parsed with a whitelist)
#   active          id of the profile used by upload / copy / .ai
#
# Credentials per profile:
#   MAIL    e-mail (max 256 chars)
#   DISEPS  27 unique codes x 16 chars, joined with "-"   (sent with every request, shareable with admin)
#   APIKEY  secret, never shared; only its SHA-256 is sent to the server at creation / regeneration
#   DINONS  29 unique codes x 16 chars, joined with "-"   (NEVER sent to the server; wraps the FEK)
# The 64-hex file-encryption-key (FEK) is created locally, wrapped with DINONS (scrypt + AES-256-GCM)
# and only the wrapped form is uploaded.  DINONS/FEK are for the future RBAC layer, NOT for up-/c2c-/do-/copy.

_BVK_AUTH_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth"
_BVK_AUTH_URL="${BVK_AUTH_URL:-https://fileapi.bashbasics.workers.dev}"
_BVK_SUPPORT_MAIL="vkd.codes@gmail.com"
_BVK_DISEPS_N=27; _BVK_DINONS_N=29; _BVK_CODE_LEN=16

# ---------------------------------------------------------------- storage helpers
_bvk_auth_init() {
  ( umask 077; mkdir -p "$_BVK_AUTH_DIR/profiles" ) 2>/dev/null || return 1
  chmod 700 "$_BVK_AUTH_DIR" "$_BVK_AUTH_DIR/profiles" 2>/dev/null
}

# Parse a KEY=VALUE file into P_* globals. Whitelisted keys only; values validated. Never sources.
_bvk_auth_parse() {  # $1=file ; sets P_MAIL P_DISEPS P_APIKEY P_DINONS P_CREATED
  P_MAIL=""; P_DISEPS=""; P_APIKEY=""; P_DINONS=""; P_CREATED=""
  [ -r "$1" ] || return 1
  local line k v
  while IFS= builtin read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    k="${line%%=*}"; v="${line#*=}"
    k="${k^^}"; k="${k//[[:space:]]/}"
    case "$k" in
      MAIL)    _bvk_auth_mail_ok "$v"   && P_MAIL="$v" ;;
      DISEPS)  _bvk_auth_codes_ok "$v" "$_BVK_DISEPS_N" && P_DISEPS="$v" ;;
      DINONS)  _bvk_auth_codes_ok "$v" "$_BVK_DINONS_N" && P_DINONS="$v" ;;
      APIKEY)  [[ "$v" =~ ^[A-Za-z0-9_-]{32,128}$ ]] && P_APIKEY="$v" ;;
      CREATED) [[ "$v" =~ ^[0-9T:Z-]{8,32}$ ]] && P_CREATED="$v" ;;
    esac
  done < "$1"
  return 0
}

_bvk_auth_write() {  # $1=file  (uses P_*)
  ( umask 077
    { printf 'MAIL=%s\n' "$P_MAIL"
      printf 'DISEPS=%s\n' "$P_DISEPS"
      printf 'APIKEY=%s\n' "$P_APIKEY"
      printf 'DINONS=%s\n' "$P_DINONS"
      printf 'CREATED=%s\n' "${P_CREATED:-$(date -u +%FT%TZ)}"; } > "$1.tmp" && mv -f "$1.tmp" "$1" )
  chmod 600 "$1" 2>/dev/null
}

# ---------------------------------------------------------------- validation
# No "is this a real e-mail" check (by design) -- only length and injection-safety.
_bvk_auth_mail_ok() {
  local m="$1"
  [ -n "$m" ] && [ "${#m}" -le 256 ] || return 1
  [[ "$m" =~ [[:cntrl:][:space:]] ]] && return 1
  case "$m" in *[\<\>\"\'\`\$\\\;\|\&\(\)\{\}/]*) return 1 ;; esac
  return 0
}
_bvk_auth_codes_ok() {  # $1=value $2=count : N unique codes of 16 [A-Za-z0-9] joined by '-'
  local IFS='-' c n=0; local -A seen=()
  for c in $1; do
    [[ "$c" =~ ^[A-Za-z0-9]{16}$ ]] || return 1
    [ -n "${seen[$c]:-}" ] && return 1
    seen[$c]=1; n=$((n+1))
  done
  [ "$n" -eq "$2" ]
}

# ---------------------------------------------------------------- crypto (node; already a dependency)
_bvk_auth_gen_codes() {  # $1=count -> joined by '-'
  node -e '
    const c=require("crypto"),A="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    const n=+process.argv[1],L=+process.argv[2],s=new Set();
    while(s.size<n){let x="";for(let i=0;i<L;i++)x+=A[c.randomInt(A.length)];s.add(x);}
    process.stdout.write([...s].join("-"));' "$1" "$_BVK_CODE_LEN"
}
_bvk_auth_gen_apikey() { node -e 'process.stdout.write(require("crypto").randomBytes(36).toString("base64url"))'; }
_bvk_auth_gen_fek()    { node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))'; }
_bvk_auth_sha256()     { printf '%s' "$1" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>process.stdout.write(require("crypto").createHash("sha256").update(d).digest("hex")))'; }

# Wrap / unwrap the FEK with DINONS. Secrets go via env, never argv.
_bvk_auth_fek_wrap() {   # $1=fek(hex) $2=dinons -> base64url blob
  BVK_P="$2" BVK_D="$1" node -e '
    const c=require("crypto"),salt=c.randomBytes(16),iv=c.randomBytes(12);
    const k=c.scryptSync(process.env.BVK_P,salt,32,{N:16384,r:8,p:1});
    const e=c.createCipheriv("aes-256-gcm",k,iv);e.setAAD(Buffer.from("bbvk2|fek"));
    const ct=Buffer.concat([e.update(process.env.BVK_D,"utf8"),e.final()]);
    process.stdout.write(Buffer.concat([salt,iv,ct,e.getAuthTag()]).toString("base64url"));'
}
_bvk_auth_fek_unwrap() { # $1=blob $2=dinons -> fek(hex), non-zero on wrong dinons
  BVK_P="$2" BVK_B="$1" node -e '
    try{const c=require("crypto"),b=Buffer.from(process.env.BVK_B,"base64url");
    const salt=b.subarray(0,16),iv=b.subarray(16,28),tag=b.subarray(b.length-16),ct=b.subarray(28,b.length-16);
    const k=c.scryptSync(process.env.BVK_P,salt,32,{N:16384,r:8,p:1});
    const d=c.createDecipheriv("aes-256-gcm",k,iv);d.setAAD(Buffer.from("bbvk2|fek"));d.setAuthTag(tag);
    process.stdout.write(Buffer.concat([d.update(ct),d.final()]).toString("utf8"));}catch(e){process.exit(1)}'
}

# ---------------------------------------------------------------- server calls
# _bvk_auth_call METHOD PATH JSON [with-creds]   -> _AUTH_HTTP, _AUTH_BODY.  Secrets only via curl -K stdin.
_bvk_auth_call() {
  local method="$1" path="$2" json="$3" withcreds="${4:-}" body resp
  body=$(mktemp) || return 1; chmod 600 "$body"; printf '%s' "$json" > "$body"
  local cfg; cfg=$({
    [ -n "$withcreds" ] && { _bb_cfg_header X-User-Email "$P_MAIL"; _bb_cfg_header X-User-Diseps "$P_DISEPS"; _bb_cfg_header X-User-Key "$P_APIKEY"; }
    _bb_cfg_header X-Telemetry-Id "$(cat "$_BVK_TELEMETRY_DIR/uuid" 2>/dev/null)"
    _bb_cfg_header X-Telemetry-Sig "$(cat "$_BVK_TELEMETRY_DIR/sig" 2>/dev/null)"; })
  resp=$(curl -s --max-time 30 "${_BB_CURL_OPTS[@]}" -K - -w '\n%{http_code}' -X "$method" \
          -H 'Content-Type: application/json' --data-binary @"$body" "$_BVK_AUTH_URL$path" <<<"$cfg" 2>/dev/null)
  rm -f "$body"
  _AUTH_HTTP="${resp##*$'\n'}"; _AUTH_BODY="${resp%$'\n'*}"
  [[ "$_AUTH_HTTP" =~ ^[0-9]{3}$ ]] || { _AUTH_HTTP=0; _AUTH_BODY=""; return 1; }
  [ "$_AUTH_HTTP" -ge 200 ] && [ "$_AUTH_HTTP" -lt 300 ]
}
_bvk_auth_err() {
  case "$_AUTH_HTTP" in
    0)   echo "❌ Could not reach the server." ;;
    429) echo "⏳ Limit reached: $(_bb_json_get "$_AUTH_BODY" message)" ;;
    403) echo "⛔ $(_bb_json_get "$_AUTH_BODY" message)"; echo "   Only the admin can lift a block (${_BVK_SUPPORT_MAIL})." ;;
    *)   echo "❌ $(_bb_fail_reason "$_AUTH_BODY" "$_AUTH_HTTP")" ;;
  esac
}
_bvk_auth_jstr() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

# ---------------------------------------------------------------- profile list / selection
# Data only -- the screens are drawn by the shared viewport engine (see "screens" below).
_BVK_AUTH_IDS=()      # profile id per row (UNFILTERED order)
_BVK_AUTH_MAILS=()    # mail per row        (what the = filter searches)
_BVK_AUTH_TAGS=()     # "[abc123…]" per row
_BVK_AUTH_ACTIVE=""   # id of the active profile
_bvk_auth_list() {
  _BVK_AUTH_IDS=(); _BVK_AUTH_MAILS=(); _BVK_AUTH_TAGS=()
  local f
  _BVK_AUTH_ACTIVE=$(cat "$_BVK_AUTH_DIR/active" 2>/dev/null)
  for f in "$_BVK_AUTH_DIR"/profiles/p_*; do
    [ -f "$f" ] || continue
    [[ "$f" == *.prev || "$f" == *.tmp ]] && continue
    _bvk_auth_parse "$f" || continue
    [ -n "$P_MAIL" ] && [ -n "$P_DISEPS" ] || continue
    _BVK_AUTH_IDS+=("${f##*/}"); _BVK_AUTH_MAILS+=("$P_MAIL"); _BVK_AUTH_TAGS+=("[${P_DISEPS:0:6}…]")
  done
  return 0
}
_bvk_auth_new_id() { echo "p_$(node -e 'process.stdout.write(require("crypto").randomBytes(8).toString("hex"))')"; }

# Load the active profile into the env vars the file API uses. Called by _bb_get_credentials.
_bvk_auth_load_active() {
  local id f; id=$(cat "$_BVK_AUTH_DIR/active" 2>/dev/null)
  [[ "$id" =~ ^p_[0-9a-f]{16}$ ]] || return 1
  f="$_BVK_AUTH_DIR/profiles/$id"; _bvk_auth_parse "$f" || return 1
  [ -n "$P_MAIL" ] && [ -n "$P_DISEPS" ] && [ -n "$P_APIKEY" ] || return 1
  export FILEAPI_BASHBASICS_EMAIL="$P_MAIL" FILEAPI_BASHBASICS_DISEPS="$P_DISEPS" FILEAPI_BASHBASICS_KEY="$P_APIKEY"
}

# ---------------------------------------------------------------- create
_bvk_auth_create() {
  echo; echo "🆕 Create user"
  cat <<'TXT'

⚠️  IMPORTANT — use your OWN, real e-mail.
   Admins will not block spam / other people's addresses, and welcome it —
   but at a heavy price: no paid services, no premium support, lost
   non-refundable subscriptions and other heavy penalties.
   For any help with paid services ONLY a receipt from the e-mail used here
   is accepted. Anything else is rejected outright, with no reply.
TXT
  local mail; builtin read -r -p $'\n   Enter email: ' mail
  [ -z "$mail" ] && { echo "↩️  Cancelled."; return; }
  _bvk_auth_mail_ok "$mail" || { echo "❌ Invalid input (max 256 chars; no spaces, quotes, < > \` \$ \\ ; | & ( ) { })."; return; }
  [ -r "$_BVK_TELEMETRY_DIR/uuid" ] || { echo "❌ No telemetry id found (is BVK_TELEMETRY=off?). Creating a user needs it for abuse protection. Restart 'o' once with telemetry on."; return; }
  command -v node >/dev/null 2>&1 || { echo "❌ node is required."; return; }

  P_MAIL="$mail"; P_DISEPS=$(_bvk_auth_gen_codes $_BVK_DISEPS_N); P_DINONS=$(_bvk_auth_gen_codes $_BVK_DINONS_N)
  P_APIKEY=$(_bvk_auth_gen_apikey); local fek wrapped hash
  fek=$(_bvk_auth_gen_fek); wrapped=$(_bvk_auth_fek_wrap "$fek" "$P_DINONS"); hash=$(_bvk_auth_sha256 "$P_APIKEY")
  fek=""
  [ -n "$wrapped" ] && [ -n "$hash" ] && _bvk_auth_codes_ok "$P_DISEPS" $_BVK_DISEPS_N || { echo "❌ Local key generation failed."; return; }

  echo "☁️  Registering…"
  local json; json=$(printf '{"mail":%s,"diseps":%s,"apikey_hash":"%s","fek_wrapped":"%s"}' \
        "$(_bvk_auth_jstr "$P_MAIL")" "$(_bvk_auth_jstr "$P_DISEPS")" "$hash" "$wrapped")
  if ! _bvk_auth_call POST /auth/create "$json"; then _bvk_auth_err; return; fi

  local id; id=$(_bvk_auth_new_id); P_CREATED=$(date -u +%FT%TZ)
  _bvk_auth_write "$_BVK_AUTH_DIR/profiles/$id"
  [ -f "$_BVK_AUTH_DIR/active" ] || printf '%s' "$id" > "$_BVK_AUTH_DIR/active"

  local out="${path:-$PWD}/bashbasicsbyvk_credentials_$(date +%Y%m%d_%H%M%S).txt"
  ( umask 077; { printf 'bashbasicsbyvk credentials — KEEP SECRET\n\n'
      printf 'mail=%s\ndiseps=%s\ndinons=%s\napikey=%s\n' "$P_MAIL" "$P_DISEPS" "$P_DINONS" "$P_APIKEY"; } > "$out" )
  echo "✅ User created: $P_MAIL"
  echo "📄 Credentials saved to: $out"
  echo "   ➜ SAVE THIS FILE NOW (move it somewhere safe). The apikey cannot be recovered."
  echo "   ⚠️  Trying to create this mail id again will get you BLOCKED."
  echo "   If you already have credentials, use 'ui' to import them — or wait 1 day to create new ones."
}

# ---------------------------------------------------------------- export / import (local only, no server, no limits)
_bvk_auth_export() {  # $1=profile id
  _bvk_auth_parse "$_BVK_AUTH_DIR/profiles/$1" || return
  echo "📤 Export — what to include?"
  echo "   1) Mail"
  echo "   2) Diseps"
  echo "   3) apikey"
  echo "   4) Dinons"
  echo "   a) all"
  local sel; builtin read -r -p "   Items (e.g. 1 3 4, or a for all; Enter = cancel): " sel; [ -z "$sel" ] && { echo "↩️  Cancelled."; return; }
  sel="${sel//,/ }"; sel="${sel,,}"
  case " $sel " in *" a "*) sel="1 2 3 4" ;; esac
  local out="${path:-$PWD}/bashbasicsbyvk_export_$(date +%Y%m%d_%H%M%S).txt" n wrote=0
  ( umask 077; : > "$out"
    for n in $sel; do case "$n" in
      1) printf 'mail=%s\n'   "$P_MAIL"   >> "$out" ;;
      2) printf 'diseps=%s\n' "$P_DISEPS" >> "$out" ;;
      3) printf 'apikey=%s\n' "$P_APIKEY" >> "$out" ;;
      4) printf 'dinons=%s\n' "$P_DINONS" >> "$out" ;;
    esac; done )
  [ -s "$out" ] || { rm -f "$out"; echo "❌ Nothing selected."; return; }
  echo "✅ Exported to $out  (keep it private — it contains secrets)"
}

_bvk_auth_import() {
  echo "📥 Import — path to a credentials / export file:"
  local f; builtin read -r -e -p "   > " f; f="${f/#\~/$HOME}"
  [ -f "$f" ] || { echo "❌ File not found."; return; }
  [ "$(wc -c < "$f")" -le 8192 ] || { echo "❌ File too large to be a credentials file."; return; }
  _bvk_auth_parse "$f"
  local nm="$P_MAIL" nd="$P_DISEPS" na="$P_APIKEY" nn="$P_DINONS"
  [ -n "$nm" ] && [ -n "$nd" ] || { echo "❌ File must contain at least a valid mail= and diseps= line."; return; }
  local pf id="" cur
  for pf in "$_BVK_AUTH_DIR"/profiles/p_*; do               # same diseps => same user: merge
    [ -f "$pf" ] || continue; _bvk_auth_parse "$pf"
    [ "$P_DISEPS" = "$nd" ] && { id="${pf##*/}"; break; }
  done
  if [ -n "$id" ]; then
    P_MAIL="$nm"; [ -n "$na" ] && P_APIKEY="$na"; [ -n "$nn" ] && P_DINONS="$nn"
    echo "🔄 Existing user updated."
  else
    id=$(_bvk_auth_new_id); P_MAIL="$nm"; P_DISEPS="$nd"; P_APIKEY="$na"; P_DINONS="$nn"; P_CREATED=$(date -u +%FT%TZ)
    echo "✅ User imported."
  fi
  _bvk_auth_write "$_BVK_AUTH_DIR/profiles/$id"
  [ -f "$_BVK_AUTH_DIR/active" ] || printf '%s' "$id" > "$_BVK_AUTH_DIR/active"
  [ -z "$na" ] && echo "ℹ️  No apikey in file — file transfers need it (import another file with apikey=)."
}


# ---------------------------------------------------------------- link an existing (pre-diseps) account
_bvk_auth_link() {
  echo; echo "🔗 Link existing account (one-time upgrade)"
  echo "   Use the e-mail and API key you used before this update. A diseps + dinons will be added to it."
  local mail key; builtin read -r -p "   Email: " mail; builtin read -r -s -p "   API key: " key; echo
  _bvk_auth_mail_ok "$mail" && [ -n "$key" ] || { echo "❌ Invalid input."; return; }
  P_MAIL="$mail"; P_APIKEY="$key"; P_DISEPS=""                      # no diseps yet => server treats it as legacy login
  P_DINONS=$(_bvk_auth_gen_codes $_BVK_DINONS_N); local nd fek wrapped
  nd=$(_bvk_auth_gen_codes $_BVK_DISEPS_N); fek=$(_bvk_auth_gen_fek); wrapped=$(_bvk_auth_fek_wrap "$fek" "$P_DINONS"); fek=""
  [ -n "$wrapped" ] || { echo "❌ Local key generation failed."; return; }
  local json; json=$(printf '{"diseps":%s,"fek_wrapped":"%s"}' "$(_bvk_auth_jstr "$nd")" "$wrapped")
  if ! _bvk_auth_call POST /auth/upgrade "$json" creds; then _bvk_auth_err; return; fi
  P_DISEPS="$nd"; P_CREATED=$(date -u +%FT%TZ); local id; id=$(_bvk_auth_new_id)
  _bvk_auth_write "$_BVK_AUTH_DIR/profiles/$id"; printf '%s' "$id" > "$_BVK_AUTH_DIR/active"
  local out="${path:-$PWD}/bashbasicsbyvk_credentials_$(date +%Y%m%d_%H%M%S).txt"
  ( umask 077; printf 'bashbasicsbyvk credentials — KEEP SECRET\n\nmail=%s\ndiseps=%s\ndinons=%s\napikey=%s\n' "$P_MAIL" "$P_DISEPS" "$P_DINONS" "$P_APIKEY" > "$out" )
  echo "✅ Account linked and set active (credits and history are unchanged)."
  echo "📄 Credentials saved to: $out  — SAVE IT NOW (it holds your new diseps and dinons)."
}

# ---------------------------------------------------------------- acting as a user
_bvk_auth_mailto() {  # $1=subject $2=body
  local url="mailto:$_BVK_SUPPORT_MAIL?subject=$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$1")&body=$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$2")"
  echo "✉️  To: $_BVK_SUPPORT_MAIL"; echo "   Subject: $1"; printf '   %s\n' "$2"
  if   command -v termux-open-url >/dev/null 2>&1; then termux-open-url "$url"
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1
  elif command -v open >/dev/null 2>&1; then open "$url"
  else echo "   (Could not open a mail app — send the message above manually.)"; fi
}

_bvk_auth_regen() {  # $1=what: diseps|apikey|dinons|mail   (P_* = current profile; $2=file)
  local what="$1" file="$2" json newmail="" old_diseps="$P_DISEPS" old_key="$P_APIKEY" old_dinons="$P_DINONS"
  cp -f "$file" "$file.prev" 2>/dev/null && chmod 600 "$file.prev"        # lock-out safety net
  case "$what" in
    mail)
      builtin read -r -p "   New email: " newmail
      _bvk_auth_mail_ok "$newmail" || { echo "❌ Invalid input."; return; }
      json=$(printf '{"action":"change_mail","new_mail":%s}' "$(_bvk_auth_jstr "$newmail")") ;;
    diseps)
      local nd; nd=$(_bvk_auth_gen_codes $_BVK_DISEPS_N)
      json=$(printf '{"action":"regen_diseps","new_diseps":%s}' "$(_bvk_auth_jstr "$nd")") ;;
    apikey)
      local nk nh; nk=$(_bvk_auth_gen_apikey); nh=$(_bvk_auth_sha256 "$nk")
      json=$(printf '{"action":"regen_apikey","new_apikey_hash":"%s"}' "$nh") ;;
    dinons)
      [ -n "$P_DINONS" ] || { echo "❌ This profile has no dinons to re-wrap with. Import them first."; return; }
      _bvk_auth_call GET /auth/fek '{}' creds || { _bvk_auth_err; return; }
      local blob fek nn nw; blob=$(_bb_json_get "$_AUTH_BODY" fek_wrapped)
      fek=$(_bvk_auth_fek_unwrap "$blob" "$old_dinons") || { echo "❌ Current dinons cannot decrypt the key — nothing changed."; return; }
      nn=$(_bvk_auth_gen_codes $_BVK_DINONS_N); nw=$(_bvk_auth_fek_wrap "$fek" "$nn"); fek=""
      json=$(printf '{"action":"rewrap_fek","fek_wrapped":"%s"}' "$nw") ;;
  esac
  if ! _bvk_auth_call POST /auth/update "$json" creds; then _bvk_auth_err; return; fi
  case "$what" in
    mail)   P_MAIL="$newmail" ;;
    diseps) P_DISEPS="$nd" ;;
    apikey) P_APIKEY="$nk" ;;
    dinons) P_DINONS="$nn" ;;
  esac
  _bvk_auth_write "$file"
  echo "✅ ${what} updated and saved locally."
  [ "$what" != mail ] && echo "   New value: $(case $what in diseps) echo "$P_DISEPS";; apikey) echo "$P_APIKEY";; dinons) echo "$P_DINONS";; esac)" && echo "   📝 Use 'ux' to export it to a file and keep it safe."
  [ "$what" = diseps ] && echo "   ℹ️  Tell the admin your new diseps for support requests."
}

# ================================================================ screens
# Both screens are drawn by the SAME viewport engine as `o`, fx, sw and .r, so they look and
# behave identically:  header · rule · numbered rows · rule · footer · "Select:" prompt,
# arrow-key highlight, u = back, q = close, "=" = live filter, bad input -> message + redraw.
# (No `cat`/raw `read -p` menus here: the smart-menu shim cannot see those, which is what
#  broke highlighting, header/footer detection and the prompt.)
#
#   list screen   items[] = the users' mails   (the = filter searches these)
#   user screen   items[] = the action labels

_AU_SCREEN="list"      # list | user
_AU_UID=""             # profile id shown on the user screen
_AU_QUIT=0             # set by q on the user screen: close -auth entirely
_AU_MAIL=""            # mail shown in the user-screen header

# display row N (1-based, filtered or not) -> 0-based slot in the unfiltered arrays
_au_slot() {
  if $_filter_map_active; then _AU_SLOT="${_filter_map[$(( $1 - 1 ))]:-0}"; else _AU_SLOT=$(( $1 - 1 )); fi
}

# ---- list screen
_au_list_rowtext() {
  _au_slot "$1"
  local mark=""
  [ "${_BVK_AUTH_IDS[$_AU_SLOT]}" = "$_BVK_AUTH_ACTIVE" ] && mark="  ★ active"
  printf -v _vp_line ' %2d) 👤 %s  %s%s' "$1" "${items[$(( $1 - 1 ))]}" "${_BVK_AUTH_TAGS[$_AU_SLOT]}" "$mark"
}
_au_list_header() {
  echo
  echo "🔐 -auth — select user"
  [ "${#_BVK_AUTH_IDS[@]}" -eq 0 ] && echo "   (no users yet — press c to create one, or ui to import)"
  _vp_filter_header_line
}
_au_list_footer() {
  printf '\nc) Create user   r) Remove user   l) Link old account\n'
  printf 'ux) Export users   ui) Import users   =) Filter\n'
  printf 'u) Back to main menu   q) Close\n'
}
_au_list_build() {
  _bvk_auth_list
  _filter_reset_state
  items=("${_BVK_AUTH_MAILS[@]}")
  _hl_index=0
}

# ---- user screen
_AU_ACTIONS=("Change Mail ID" "Regenerate diseps" "Regenerate apikey" "Regenerate dinons" "Report Issue" "Recharge" "Set as active user")
_au_user_rowtext() {
  _au_slot "$1"
  local mark=""
  [ "$_AU_SLOT" -eq 6 ] && [ "$_AU_UID" = "$_BVK_AUTH_ACTIVE" ] && mark="  ★ active"
  printf -v _vp_line ' %2d) %s%s' "$1" "${items[$(( $1 - 1 ))]}" "$mark"
}
_au_user_header() {
  echo
  echo "👤 Acting as: $_AU_MAIL"
  _vp_filter_header_line
}
_au_user_footer() {
  printf '\nux) Export   ui) Import   =) Filter\n'
  printf 'u) Back   q) Close\n'
}
_au_user_build() {                       # returns 1 if the profile vanished
  _bvk_auth_list
  _bvk_auth_parse "$_BVK_AUTH_DIR/profiles/$_AU_UID" || return 1
  [ -n "$P_MAIL" ] || return 1
  _AU_MAIL="$P_MAIL"
  _filter_reset_state
  items=("${_AU_ACTIONS[@]}")
  _hl_index=0
}

# ---- shared plumbing
_au_set_viewport() {
  _vp_mode="items"
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  case "$_AU_SCREEN" in
    user) _vp_rowtext_fn=_au_user_rowtext; _vp_header_fn=_au_user_header; _vp_footer_fn=_au_user_footer ;;
    *)    _vp_rowtext_fn=_au_list_rowtext; _vp_header_fn=_au_list_header; _vp_footer_fn=_au_list_footer ;;
  esac
  _vp_cache_reset
}
# rebuild the current screen and draw it fresh (this is what puts the "Select:" menu back
# after every action, bad input or message)
_au_fresh() {
  _buf=""; _pos=0
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  case "$_AU_SCREEN" in
    user) _au_user_build || return 1 ;;
    *)    _au_list_build ;;
  esac
  _au_set_viewport
  _vp_render_from_top
  return 0       # (the draw's own status is the input line's, not a failure)
}
_au_pause() {
  builtin printf '\n  ↵ press any key to continue'
  builtin read -rsn1 _ </dev/tty 2>/dev/null
  builtin printf '\n'
}
# resolve a typed row number against what is on screen -> _AU_SLOT ; 1 = invalid
_au_row() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  local n=$(( 10#$1 ))
  [ "$n" -ge 1 ] && [ "$n" -le "${#items[@]}" ] || return 1
  _au_slot "$n"
}
# number for r / ux : taken from "r-2" / "ux-2", else asked
_au_ask_row() {  # $1=typed command  $2=prompt  -> _AU_SLOT
  local arg="" n
  [[ "$1" == *-* ]] && arg="${1#*-}"
  if [ -z "$arg" ]; then
    builtin read -r -p "   $2 " arg
    [ -z "$arg" ] && { echo "↩️  Cancelled."; return 1; }
  fi
  _au_row "$arg" || { echo "⚠️  Invalid selection"; return 1; }
}

_au_user_action() {  # $1 = 0-based action slot
  local file="$_BVK_AUTH_DIR/profiles/$_AU_UID"
  case "$1" in
    0) _bvk_auth_regen mail   "$file" ;;
    1) _bvk_auth_regen diseps "$file" ;;
    2) _bvk_auth_regen apikey "$file" ;;
    3) _bvk_auth_regen dinons "$file" ;;
    4) _bvk_auth_mailto "bashbasicsbyvk: support" "mail: $P_MAIL" ;;
    5) _bvk_auth_mailto "bashbasicsbyvk: recharge" "mail: $P_MAIL
diseps: $P_DISEPS
(see -h → pricing for the charge break-up)" ;;
    6) printf '%s' "$_AU_UID" > "$_BVK_AUTH_DIR/active"; echo "★ Active user set." ;;
  esac
}

_bvk_auth_user_menu() {  # $1=profile id
  _AU_SCREEN="user"; _AU_UID="$1"
  _au_fresh || { _AU_SCREEN="list"; return 0; }
  local quiet
  while :; do
    _read_choice_filtered
    quiet=false
    case "${choice,,}" in
      u)  break ;;
      q)  _AU_QUIT=1; break ;;
      "") quiet=true ;;
      ux) _bvk_auth_export "$_AU_UID"; _au_pause ;;
      ui) _bvk_auth_import;            _au_pause ;;
      *[!0-9]*) echo "❓ Unknown option." ;;
      *)  if _au_row "$choice"; then _au_user_action "$_AU_SLOT"; _au_pause
          else echo "⚠️  Invalid selection"; fi ;;
    esac
    _au_fresh || break          # profile vanished -> back to the list
  done
  _AU_SCREEN="list"
  return 0
}

# ---------------------------------------------------------------- entry point: -auth
auth_menu() {
  _bvk_auth_init || { echo "❌ Cannot create $_BVK_AUTH_DIR"; return 1; }

  # borrow the shared list/viewport state, give it back untouched on the way out
  local -a _au_keep_items=("${items[@]}")
  local _au_keep_hl="${_hl_index:-0}" _au_keep_mode="${_vp_mode:-items}" _au_keep_hdr="${_vp_header_fn:-}" \
        _au_keep_ftr="${_vp_footer_fn:-}" _au_keep_row="${_vp_rowtext_fn:-}" _au_keep_inp="${_vp_input_fn:-}" \
        _au_keep_hlf="${_vp_hl_fn:-}" _au_keep_fx="${_fx_in_mode:-0}" _au_keep_imag="${imaginary_mode:-false}" \
        _au_keep_fq="${_filter_query:-}"
  local -a _au_keep_all=("${_all_items[@]}") _au_keep_src=("${_filter_src[@]}") _au_keep_map=("${_filter_map[@]}")
  local _au_keep_mapact="${_filter_map_active:-false}"

  _fx_in_mode=1          # virtual list: never re-scan the folder for hidden files; inner-loop animation
  imaginary_mode=false   # a big folder in grouped view must not hijack the = filter
  _AU_SCREEN="list"; _AU_QUIT=0

  _au_fresh
  local quiet
  while :; do
    _read_choice_filtered
    quiet=false
    case "${choice,,}" in
      u|q) break ;;
      "")  quiet=true ;;
      c)   _bvk_auth_create; _au_pause ;;
      l)   _bvk_auth_link;   _au_pause ;;
      ui)  _bvk_auth_import; _au_pause ;;
      r|r-*)
        if [ "${#items[@]}" -eq 0 ]; then echo "ℹ️  No users to remove."
        elif _au_ask_row "$choice" "Remove which number?"; then
          local rid="${_BVK_AUTH_IDS[$_AU_SLOT]}" ans
          echo "   ⚠️  Removes this user from THIS machine only. Without an export you lose the apikey/dinons."
          builtin read -r -p "   Type yes to confirm: " ans
          if [ "$ans" = yes ]; then
            rm -f "$_BVK_AUTH_DIR/profiles/$rid" "$_BVK_AUTH_DIR/profiles/$rid.prev"
            [ "$(cat "$_BVK_AUTH_DIR/active" 2>/dev/null)" = "$rid" ] && rm -f "$_BVK_AUTH_DIR/active"
            echo "🗑️  Removed."
          else echo "↩️  Cancelled."; fi
        fi
        _au_pause ;;
      ux|ux-*)
        if [ "${#items[@]}" -eq 0 ]; then echo "ℹ️  No users to export."
        elif _au_ask_row "$choice" "Export which number?"; then _bvk_auth_export "${_BVK_AUTH_IDS[$_AU_SLOT]}"; fi
        _au_pause ;;
      *[!0-9]*) echo "❓ Unknown option." ;;
      *)
        if _au_row "$choice"; then
          _bvk_auth_user_menu "${_BVK_AUTH_IDS[$_AU_SLOT]}"
          [ "$_AU_QUIT" = 1 ] && break
        else echo "⚠️  Invalid selection"; fi ;;
    esac
    _au_fresh
  done

  # leave tidy
  _AU_QUIT=0
  _filter_reset_state
  items=("${_au_keep_items[@]}"); _hl_index="$_au_keep_hl"
  _vp_mode="$_au_keep_mode"; _vp_header_fn="$_au_keep_hdr"; _vp_footer_fn="$_au_keep_ftr"
  _vp_rowtext_fn="$_au_keep_row"; _vp_input_fn="$_au_keep_inp"; _vp_hl_fn="$_au_keep_hlf"
  _fx_in_mode="$_au_keep_fx"; imaginary_mode="$_au_keep_imag"
  _filter_query="$_au_keep_fq"; _all_items=("${_au_keep_all[@]}"); _filter_src=("${_au_keep_src[@]}")
  _filter_map=("${_au_keep_map[@]}"); _filter_map_active="$_au_keep_mapact"
  _vp_cache_reset
  return 0
}
