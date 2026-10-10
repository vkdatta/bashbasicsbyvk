#!/usr/bin/env bash
# bashbasicsbyvk_api.sh — the  api  loop: manage the links you have created (an inner loop, like fx / sw / .r / -u)
# ════════════════════════════════════════════════════════════════════════════
#  api   opens the link manager (also: Home → Links).   Every ACTIVE link you made with up- / c2c- is
#  listed, soonest expiry first. A link is shown by its ALIAS (up-1-3 as user data); without one you see
#  the start of its id. The full link is never shown here: its decryption key lives only in the link you
#  were given when you made it — the server never sees it.
#
#  Commands
#    N          open link N (details, then  e  edit  /  x  nuke)
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
#  Server routes used:  GET /links · POST /links/<id>/expiry · DELETE /links/<id>   (full credentials)
#
#  Uses (from the main app): _vp_* viewport, _read_choice_filtered, _inner_run, _filter_reset_state,
#  _bvk_quit, parse_selection, and _bb_* helpers from _3bvk_fileapi_lib.sh
# ════════════════════════════════════════════════════════════════════════════

declare -ga _API_ID=() _API_KIND=() _API_ALIAS=() _API_BYTES=() _API_CREATED=() _API_EXPIRES=()
declare -ga _API_PAID=() _API_RFND=() _API_RFND_D=()
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
_api_load() {
  _API_ID=(); _API_KIND=(); _API_ALIAS=(); _API_BYTES=(); _API_CREATED=(); _API_EXPIRES=()
  _API_PAID=(); _API_RFND=(); _API_RFND_D=()
  _API_ERR=""; _API_LOADED=1; _API_BAL=""
  if ! _crypto_check >/dev/null 2>&1; then _API_ERR="node is required (used to read the server's answer)"; return 1; fi
  _api_http GET /links || { _API_ERR="no active user — run  -auth  inside 'o'"; return 1; }
  if [ "$_API_STATUS" != "200" ]; then _API_ERR="$(_api_fail | head -n 1 | sed 's/^❌ //')"; return 1; fi
  local out
  out=$(node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const US = "\x1f";
      let o; try { o = JSON.parse(d); } catch (e) { process.exit(2); }
      if (!o || !Array.isArray(o.links)) process.exit(2);
      const clean = (v) => String(v ?? "").replace(/[\x00-\x1f\x7f]/g, " ");
      console.log(["META", o.balance, o.now].join(US));
      for (const l of o.links) {
        console.log(["L", l.id, l.kind, clean(l.alias), l.bytes, l.createdAt, l.expiresAt, l.paidHours, l.nukeRefund, l.nukeRefundDays].join(US));
      }
    });' <<<"$_API_BODY") || { _API_ERR="the server answered, but not with a link list"; return 1; }
  local tag a b c d e f g h i
  while IFS="$_API_US" read -r tag a b c d e f g h i; do
    case "$tag" in
      META) _API_BAL="$a"; _API_NOW="$b"; _API_LOCAL="${EPOCHSECONDS:-$(date +%s)}"; _API_PRE=(); _API_POST=() ;;
      L)    _API_ID+=("$a"); _API_KIND+=("$b"); _API_ALIAS+=("$c"); _API_BYTES+=("$d")
            _API_CREATED+=("$e"); _API_EXPIRES+=("$f"); _API_PAID+=("$g"); _API_RFND+=("$h"); _API_RFND_D+=("$i") ;;
    esac
  done <<<"$out"
  return 0
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
  printf '🔗 LINKS (api)   💳 balance: %s credits\n' "${_API_BAL:-?}"
  printf '   soonest expiry first · shown by alias (up-1-3 as <alias>) · the key never leaves your machine\n'
  [ -n "$_API_ERR" ] && printf '   ⚠️  %s — rf to retry\n' "$_API_ERR"
  if [ -z "$_API_ERR" ] && [ "${#items[@]}" -eq 0 ]; then
    printf '   No active links. Make one with  up-1-3 as notes  or  c2c-2 as snippet.\n'
  fi
  _vp_filter_header_line
}

_api_menu_footer() {
  printf '\n[Links]  %d active   🕐 times in %s  (change: s → Timezone)\n' "${#items[@]}" "$(_tz_label 2>/dev/null || date +%Z)"
  printf 'N) Open   e-N) Edit expiry   x-N) Nuke (x-1,3-5 for several)\n'
  printf 'rf) Refresh   u) Exit   api) Close\n'
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
  if [ "$_API_LOADED" -eq 0 ]; then echo "⏳ Fetching your links…"; _api_load; fi
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
  echo "$( [ "${_API_KIND[$k]}" = copy ] && echo 📄 || echo 📦 ) $(_api_name "$k")   ($( [ "${_API_KIND[$k]}" = copy ] && echo 'text paste' || echo 'file upload' ), $(_api_hsize "${_API_BYTES[$k]}"))"
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
  read -r -p "   e) edit expiry   x) nuke   Enter) back: " ans
  case "${ans,,}" in
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
    read -r -p "   New time (u = back): " spec
    case "${spec,,}" in u|q|"") echo "↩️  Back"; return 0 ;; esac
  fi
  total=$(_api_resolve_time "$k" "$spec") || return 1
  local nexp=$(( ${_API_CREATED[$k]} + total * 1000 )) dir="extends"
  [ "$nexp" -lt "${_API_EXPIRES[$k]}" ] && dir="shortens"
  [ "$nexp" -eq "${_API_EXPIRES[$k]}" ] && dir="keeps"
  read -r -p "   $(_api_name "$k"): total life → $(_bb_fmt_duration "$total") (gone at $(_bb_fmt_when "$nexp")) — this $dir it. Continue? (y/N): " ans
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
  read -r -p "   Nuke now and refund about $total credit(s)? (y/N): " ans
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

_api_cmd_nuke() {        # x-LIST
  local list="$1" idx
  local -a ks=()
  for idx in $(parse_selection "$list" "${#items[@]}"); do ks+=("$((idx - 1))"); done
  if [ "${#ks[@]}" -eq 0 ]; then echo "⚠️  Usage: x-3   or   x-1,3-5"; return 1; fi
  _api_do_nuke "${ks[@]}"
}

_api_help() {
  cat <<'HLP'
🔗 LINKS  (api)
 Every active link you made with up- / c2c-, soonest expiry first. Shown by ALIAS:
   up-1-3 as user data      c2c-2 as snippet      (no alias → the start of the id)
 N open · e-N [time] edit expiry · x-N nuke (x-1,3-5 several) · rf refresh · u exit · api close
 time = the NEW TOTAL life from creation:  2d · 36h · 1 week     or  +12h extend / -1d shorten
   limits 1 minute – 30 days
 extend  → the extra time is charged now (1 credit per GB per hour, size-bucket minimums, as an upload)
 shorten / nuke → refunded in WHOLE DAYS only; time already used rounds UP to a full day
   (30 days, nuked after 1 day + 1 minute → 28 days refunded)
 The full link (with its key) is not stored anywhere but in the copy you were given.
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
      api|u) echo "↩️  Closing the links loop"; break ;;

      fx) _inner_next=fx;  break ;;
      sw) _inner_next=sw;  break ;;
      .r) _inner_next=r;   break ;;
      -u) _inner_next=upg; break ;;

      q) _fx_in_mode=0; _sw_in_mode=0; _bvk_quit ;;

      -h) _api_help; _ap_fresh=false ;;

      rf) _API_LOADED=0 ;;                       # rebuilt (and re-fetched) below

      e-*) _api_cmd_edit "${_ap_choice#[eE]-}" || true ;;
      x-*) _api_cmd_nuke "${_ap_choice#[xX]-}" || true ;;

      f)    find_menu; _ap_fresh=false ;;
      disk) df -h; _ap_fresh=false ;;
      ram)  free -h; _ap_fresh=false ;;

      _*) _ap_fresh=false ;;

      *)
        if ! [[ "$_ap_choice" =~ ^[0-9]+$ ]] || [ "$_ap_choice" -lt 1 ] || [ "$_ap_choice" -gt "${#items[@]}" ]; then
          echo "⚠️  Invalid selection"; _ap_fresh=false
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
