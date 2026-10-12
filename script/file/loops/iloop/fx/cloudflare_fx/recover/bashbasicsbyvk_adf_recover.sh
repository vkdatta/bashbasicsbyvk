#!/usr/bin/env bash
# bashbasicsbyvk_adf_recover.sh
# adf-staging='cloudflare_fx/recover_workers'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — recover      (the ONE button; everything else lives in _3bvk_recover_*.py)
#
#  fx → recover  does, in the folder the navigator is showing (the "navigation path"):
#    1. finds CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID in that folder (.dev.vars, .env, …) — asks only if missing
#    2. lists EVERY worker of the account as rows in the drawer
#    3. you pick any number of them:   N · 1,3-5 · a (all) · a-2 (all except 2)      r / r-1,3  = live-highlight picker
#    4. each pick is recovered into  <navigation path>/<worker>-recovered/
#
#  Secrets never go on a command line or into a file: they are passed to python through its environment only.
# ════════════════════════════════════════════════════════════════════════════

_RCV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -ga _RCV_NAMES=()
_RCV_NAV=""; _RCV_PY=""; _RCV_MAIN=""; _RCV_TOK=""; _RCV_ACC=""

# python + the entry module (installed flat next to the other scripts, or still in the source tree)
_rcv_locate() {
  _RCV_PY="$(command -v python3 || command -v python)"
  [ -n "$_RCV_PY" ] || { echo "❌ recover needs Python 3."; return 1; }
  local d
  for d in "${SCRIPT_DIR:-}" "$_RCV_DIR" "$_RCV_DIR/recover"; do
    [ -n "$d" ] && [ -f "$d/_3bvk_recover_main" ] && { _RCV_MAIN="$d/_3bvk_recover_main"; return 0; }
  done
  echo "❌ _3bvk_recover_main not found (looked in \$SCRIPT_DIR and $_RCV_DIR)."; return 1
}

# run the python entry for the navigation path, credentials handed over via its environment only
_rcv_cf() {
  CLOUDFLARE_API_TOKEN="$_RCV_TOK" CLOUDFLARE_ACCOUNT_ID="$_RCV_ACC" "$_RCV_PY" "$_RCV_MAIN" "$_RCV_NAV" "$@"
}

_rcv_forget() { _RCV_TOK=""; _RCV_ACC=""; _RCV_NAMES=(); }

_rcv_fetch_names() {
  local out l
  out="$(_rcv_cf --list)" || return 1
  _RCV_NAMES=()
  while IFS= read -r l; do [ -n "$l" ] && _RCV_NAMES+=("$l"); done <<<"$out"
  return 0
}

_rcv_load() {
  local creds
  creds="$("$_RCV_PY" "$_RCV_MAIN" "$_RCV_NAV" --print-credentials)" || { echo "❌ No usable Cloudflare credentials."; return 1; }
  _RCV_TOK="${creds%%$'\n'*}"; _RCV_ACC="${creds#*$'\n'}"; creds=""
  echo "☁️  Loading workers…"
  _rcv_fetch_names || { echo "❌ Could not list workers (see message above)."; _rcv_forget; return 1; }
  [ "${#_RCV_NAMES[@]}" -gt 0 ] || { echo "ℹ️  No workers in this account."; _rcv_forget; return 1; }
}

# ── drawer screen (xui) ─────────────────────────────────────────────────────
rcv_build() { _xui_begin_items "${_RCV_NAMES[@]}"; }

rcv_row() {
  _xui_slot "$1"; local n="${_RCV_NAMES[$_XUI_SLOT]}" tag=""
  [ -e "$_RCV_NAV/${n}-recovered" ] && tag="   ✅ already recovered here"
  printf -v _vp_line ' %2d) ☁️  %s%s' "$1" "$n" "$tag"
}

rcv_header() {
  echo; echo "☁️  Cloudflare Workers — recover   (${#_RCV_NAMES[@]} in account)"
  printf '📂 %s\n' "$_RCV_NAV"
  _vp_filter_header_line
}

rcv_footer() {
  printf '\nSelect workers:  N · 1,3-5 · a (all) · a-2 (all except 2)      r) live picker   rf) refresh   u) back\n'
  printf 'Recovered into  %s/<worker>-recovered\n' "$_RCV_NAV"
}

# _XUI_SEL (display rows) -> confirm -> recover them
_rcv_run() {
  local r picks=() n args=()
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; picks+=("${_RCV_NAMES[$_XUI_SLOT]}"); done
  echo; echo "☁️  Recover ${#picks[@]} worker(s) into $_RCV_NAV :"
  for n in "${picks[@]}"; do echo "     • $n"; args+=(-w "$n"); done
  _xui_yes "Start recovery?" || return 1
  echo
  _rcv_cf "${args[@]}"
  echo; builtin read -e -r -p "   ↩  Press Enter to return to the worker list " _
  return 0
}

_rcv_cmd() {
  case "$1" in
    rf) _rcv_fetch_names || echo "❌ Refresh failed."; return 0 ;;
    r|r-*)
      _xui_select_rows "RECOVER" "☁️  Recover which workers?" "$1" || return 1
      _rcv_run; return 0 ;;
    [0-9]*|a|a-*)
      _xui_parse_sel "$1" || return 1
      _rcv_run; return 0 ;;
    fx|sw|api|.r|-u) echo "↩️  Go back with  u  first."; return 1 ;;   # a hop would leave a stale _inner_next behind
    *) return 9 ;;
  esac
}

# ── the button ──────────────────────────────────────────────────────────────
_fx_adf_recover() {
  _RCV_NAV="${_fx_outer_path:-$path}"            # the navigation path, NOT $PWD
  _rcv_locate || return 1
  _rcv_load || return 1
  _xui_enter
  _xui_screen rcv
  _xui_loop _rcv_cmd
  _xui_leave
  _rcv_forget
}
_fx_adf_register "recover" "_fx_adf_recover" "recover"
