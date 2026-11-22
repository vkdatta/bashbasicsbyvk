#!/usr/bin/env bash
# bashbasicsbyvk_cslib.sh — the Google Cloud Shell helpers behind  fx → cloudshell → launch.cloudshell.
# ════════════════════════════════════════════════════════════════════════════
#  All the gcloud work lives here; the screens (bashbasicsbyvk_adf_cloudshell.sh) only ask and show.
#
#    _CS_ACCOUNTS[]            the saved profiles (Google account e-mails), one line each in  ~/.config/bashbasicsbyvk/cloudshell/accounts.txt
#                              (read as DATA, never sourced)
#    _cs_accounts_load / _save / _add "a@x.com, b@y.com"     keep that file (valid e-mails only, no case-insensitive duplicates)
#    _cs_locate                finds the gcloud program ($_CS_BIN); rc 1 = not installed  (the installer is the `gcloud` recipe of the deps engine)
#    _cs_status_load           ONE gcloud call: which accounts hold a login ($_CS_AUTHED) and which one is active ($_CS_ACTIVE)
#    _cs_is_authed ACCOUNT     does gcloud hold a login for it
#    _cs_use ACCOUNT           gcloud config set account ACCOUNT           (done on EVERY switch of profile)
#    _cs_login ACCOUNT b|l     gcloud auth login ACCOUNT   b = browser on this device, l = a link to open anywhere + paste the code back
#    _cs_launch                opens Cloud Shell for the active account with the connect bar; returns ssh's exit code
#    _cs_kill                  switches Cloud Shell off for the active account (tmux kill-server, else every process of the user): the cure for a hung session
#
#  The connect bar is the app's own progress-bar shape  [███░░] 45%  (a wait of known length, so smartload stays out of the way:
#  _bb_progress_begin / _bb_progress_end).  The terminal colours are NOT touched: the app already applies the person's colours (Settings → colours).
#  No source here (AGENTS rule 3): this file is loaded through the load mapper.
# ════════════════════════════════════════════════════════════════════════════

_CS_BIN=""
_CS_AUTHED=" "
_CS_ACTIVE=""
declare -ga _CS_ACCOUNTS=()
declare -ga _CS_NEW=()                       # what the last _cs_accounts_add really added (the caller offers to sign them in)

# the ssh options both the session and the kill command use (a phone on a weak network: keep-alives, no GSSAPI, compression)
# StrictHostKeyChecking=no / UserKnownHostsFile=/dev/null: a Cloud Shell machine gets a new address and host key all the time
declare -ga _CS_SSH_OPTS=(
  "-o ServerAliveInterval=5" "-o ServerAliveCountMax=24" "-o TCPKeepAlive=yes" "-o IPQoS=throughput"
  "-o GSSAPIAuthentication=no" "-o Compression=yes" "-o StrictHostKeyChecking=no" "-o UserKnownHostsFile=/dev/null"
  "-o LogLevel=ERROR" "-o ConnectTimeout=15"
)

# ── gcloud itself
_cs_locate() {
  [ -n "$_CS_BIN" ] && [ -x "$_CS_BIN" ] && return 0
  _CS_BIN="$(type -P gcloud 2>/dev/null)"                      # type -P: a file only (a shell function called gcloud does not count)
  [ -x "$_CS_BIN" ] || _CS_BIN="$HOME/google-cloud-sdk/bin/gcloud"   # where the installer recipe unpacks it
  [ -x "$_CS_BIN" ] && return 0
  _CS_BIN=""; return 1
}

_cs_gc() { _cs_locate || return 127; "$_CS_BIN" "$@"; }

# ── the saved profiles
_cs_cfg_file() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/cloudshell/accounts.txt"; }

_cs_accounts_load() {
  _CS_ACCOUNTS=(); local f l; f="$(_cs_cfg_file)"
  [ -f "$f" ] || return 0
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"; [ -n "$l" ] && _CS_ACCOUNTS+=("$l")
  done < "$f"
}

_cs_accounts_save() {
  local f; f="$(_cs_cfg_file)"
  mkdir -p "${f%/*}" 2>/dev/null || { echo "❌ cannot write ${f%/*}"; return 1; }
  if [ "${#_CS_ACCOUNTS[@]}" -gt 0 ]; then printf '%s\n' "${_CS_ACCOUNTS[@]}" > "$f"; else : > "$f"; fi
}

# _cs_accounts_add "a@x.com, b@y.com"  → adds every valid new e-mail, says what it did; rc 0 when something was added; _CS_NEW = the added ones
_cs_accounts_add() {
  local raw="$1" n u have added=0 bad=() dup=()
  local re='^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
  local -a want=()
  _CS_NEW=()
  IFS=',' read -r -a want <<<"${raw//$'\n'/,}"
  for n in "${want[@]}"; do
    _csv_trim n
    n="${n,,}"
    [ -n "$n" ] || continue
    if [[ ! "$n" =~ $re ]]; then bad+=("$n"); continue; fi
    have=0; for u in "${_CS_ACCOUNTS[@]}"; do [ "${u,,}" = "$n" ] && have=1; done
    if [ "$have" = 1 ]; then dup+=("$n"); continue; fi
    _CS_ACCOUNTS+=("$n"); _CS_NEW+=("$n"); added=$((added+1))
  done
  [ "$added" -gt 0 ] && echo "   ✅ added $added profile(s)"
  [ "${#dup[@]}" -gt 0 ] && echo "   (already saved: ${dup[*]})"
  [ "${#bad[@]}" -gt 0 ] && echo "   ❌ not an e-mail address, skipped: ${bad[*]}"
  [ "$added" -gt 0 ]
}

# ── who is signed in, who is active (one gcloud call: python starts once, which is the slow part on a phone)
_cs_status_load() {
  local a s out
  _CS_AUTHED=" "; _CS_ACTIVE=""
  out="$(_cs_gc auth list --format='value(account,status)' 2>/dev/null)" || return 1
  while IFS=$'\t' read -r a s; do
    [ -n "$a" ] || continue
    a="${a,,}"; _CS_AUTHED+="$a "
    [ "$s" = ACTIVE ] && _CS_ACTIVE="$a"
  done <<<"$out"
  return 0
}

_cs_is_authed() { case "$_CS_AUTHED" in *" ${1,,} "*) return 0 ;; esac; return 1; }

# gcloud config set account ACCOUNT — exactly this command, on every switch
_cs_use() { _cs_gc config set account "$1" --quiet >/dev/null 2>&1; }

# gcloud auth login ACCOUNT : b = browser on this device (Termux hands the link to termux-open-url), l = print a link, paste the code back
_cs_login() {
  local acct="$1" how="${2:-b}" br="${BROWSER:-}"
  case "$how" in
    l) _cs_gc auth login "$acct" --no-launch-browser ;;
    *) [ -z "$br" ] && command -v termux-open-url >/dev/null 2>&1 && br="termux-open-url"
       BROWSER="$br" _cs_gc auth login "$acct" ;;
  esac
}

# ── the connect bar: runs in the background and draws on the terminal while ssh starts.
#   _cs_bar OK_FILE PID_FILE   ends by itself: ssh touched OK_FILE (connected) · ssh died (aborted) · 100 % reached (still trying)
_cs_bar() {
  local ok="$1" pidf="$2" total=15 cols=30 start now pct last=-1 filled i bar pid=""
  printf -v start '%(%s)T' -1
  while :; do
    printf -v now '%(%s)T' -1
    pct=$(( (now - start) * 100 / total )); (( pct > 100 )) && pct=100
    pid=""; [ -f "$pidf" ] && pid="$(<"$pidf")"
    if [ -f "$ok" ]; then pct=100; fi
    if [ "$pct" -ne "$last" ] || [ -f "$ok" ]; then
      last=$pct; filled=$(( pct * cols / 100 )); bar=""
      for ((i=0; i<filled; i++)); do bar+="█"; done
      for ((i=filled; i<cols; i++)); do bar+="░"; done
      if [ -f "$ok" ]; then printf '\r[%s] %3d%%  ✅ Connected        \n\n' "$bar" "$pct"; return 0; fi
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then printf '\r[%s] %3d%%  ❌ Aborted          \n\n' "$bar" "$pct"; return 0; fi
      if [ "$pct" -ge 100 ]; then printf '\r[%s] %3d%%  ⏳ Still connecting…\n\n' "$bar" "$pct"; return 0; fi
      if [ "$pct" -ge 78 ]; then printf '\r[%s] %3d%%  ⚠️  Weak connection…' "$bar" "$pct"
      else                       printf '\r[%s] %3d%%  🔄 Connecting…      ' "$bar" "$pct"; fi
    elif [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      printf '\r[%s] %3d%%  ❌ Aborted          \n\n' "$bar" "$pct"; return 0
    fi
    sleep 0.1
  done
}

# ── the session
_cs_launch() {
  local d ok pidf bar_pid="" bar=1 rc=0 keyfile="$HOME/.ssh/google_compute_engine"
  _cs_locate || { echo "❌ gcloud is not installed."; return 127; }
  d="$(mktemp -d "${TMPDIR:-${PREFIX:-}/tmp}/bvk-cloudshell.XXXXXX" 2>/dev/null)" || d=""
  [ -n "$d" ] || { d="${TMPDIR:-/tmp}/bvk-cloudshell.$$"; mkdir -p "$d" 2>/dev/null; }
  ok="$d/ok"; pidf="$d/pid"
  [ -f "$keyfile" ] || bar=0                    # the very first run: gcloud asks for an ssh key passphrase, so no bar over its question
  case "$d" in *[[:space:]]*) bar=0 ;; esac      # the "connected" signal is one word: it cannot hold a path with spaces
  command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null
  _bb_progress_begin
  if [ "$bar" = 1 ]; then
    bar_pid="$( set +m; ( _cs_bar "$ok" "$pidf" ) >/dev/tty 2>/dev/null & echo $! )"
  fi
  (
    printf '%s' "$BASHPID" > "$pidf"
    exec "$_CS_BIN" cloud-shell ssh --authorize-session \
      --ssh-flag="-t" --ssh-flag="-t" \
      "${_CS_SSH_OPTS[@]/#/--ssh-flag=}" \
      --ssh-flag="-o PermitLocalCommand=yes" \
      --ssh-flag="-o LocalCommand=:>$ok"
  )
  rc=$?
  if [ -n "$bar_pid" ] && kill -0 "$bar_pid" 2>/dev/null; then kill "$bar_pid" 2>/dev/null; printf '\r\033[K'; fi
  _bb_progress_end
  command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock 2>/dev/null
  rm -rf "$d"
  return $rc
}

# switch Cloud Shell off: tmux first, else every process of the user.  The connection closing under it is the expected end.
_cs_kill() {
  _cs_locate || { echo "❌ gcloud is not installed."; return 127; }
  _bb_progress_begin
  "$_CS_BIN" cloud-shell ssh --authorize-session \
    "${_CS_SSH_OPTS[@]/#/--ssh-flag=}" \
    --command='tmux kill-server || pkill -u $USER'
  local rc=$?
  _bb_progress_end
  return $rc
}
