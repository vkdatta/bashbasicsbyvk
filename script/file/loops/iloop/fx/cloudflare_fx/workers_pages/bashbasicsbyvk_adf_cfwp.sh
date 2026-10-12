#!/usr/bin/env bash
# bashbasicsbyvk_adf_cfwp.sh
# adf-staging='cloudflare_fx/workers and pages'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — cloudflare workers and pages      (the ONE button; the work lives in _3bvk_cfwp_* + _3bvk_recover_*)
#
#  fx → cloudflare_fx → workers and pages  does, in the folder the navigator is showing (the "navigation path"):
#    1. finds CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID in that folder (.dev.vars, .env, …) — asks only if missing
#    2. lists EVERY Worker and EVERY Pages project of the account:  name · type · latest deployment
#       (deployment time is shown in the app timezone: Settings → Timezone)
#    3. you pick any number of rows:   N · 1,3-5 · a (all) · a-2 (all except 2)      r / r-1,3  = live-highlight picker
#         recover   → Worker  → <nav>/<name>-recovered/          (same pipeline as before)
#                     Pages   → <nav>/<name>-pages-recovered/    (public files of the latest production deployment)
#         export    → e (all rows shown) · e-1,3-5 (picked rows)  → csv / json / both in <nav>/
#
#  Secrets never go on a command line or into a file: they are passed to python through its environment only.
#  This file replaces the old single "recover" button in functions.sh; bashbasicsbyvk_adf_recover.sh is untouched.
# ════════════════════════════════════════════════════════════════════════════

_CFW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -ga _CFW_TYPE=() _CFW_NAME=() _CFW_EPOCH=() _CFW_ERR=()
_CFW_NAV=""; _CFW_PY=""; _CFW_MAIN=""; _CFW_TOK=""; _CFW_ACC=""

# python + the entry module (installed flat next to the other scripts, or still in the source tree)
_cfw_locate() {
  _CFW_PY="$(command -v python3 || command -v python)"
  [ -n "$_CFW_PY" ] || { echo "❌ Cloudflare workers and pages needs Python 3."; return 1; }
  local d
  for d in "${SCRIPT_DIR:-}" "$_CFW_DIR" "$_CFW_DIR/workers_pages"; do
    [ -n "$d" ] && [ -f "$d/_3bvk_cfwp_main" ] && { _CFW_MAIN="$d/_3bvk_cfwp_main"; return 0; }
  done
  echo "❌ _3bvk_cfwp_main not found (looked in \$SCRIPT_DIR and $_CFW_DIR)."; return 1
}

# python for the navigation path, credentials handed over via its environment only (TZ is already exported by the app)
_cfw_cf() {
  CLOUDFLARE_API_TOKEN="$_CFW_TOK" CLOUDFLARE_ACCOUNT_ID="$_CFW_ACC" "$_CFW_PY" "$_CFW_MAIN" "$_CFW_NAV" "$@"
}

_cfw_forget() { _CFW_TOK=""; _CFW_ACC=""; _CFW_TYPE=(); _CFW_NAME=(); _CFW_EPOCH=(); _CFW_ERR=(); }

# epoch -> "2026-10-11 14:05:09 IST" in the app timezone (TZ), "Not available" when unknown
_cfw_when() {
  local e="$1"
  [[ "$e" =~ ^[0-9]+$ ]] || { printf 'Not available'; return; }
  if [ "${_BVK_HAS_TFMT:-0}" = 1 ]; then printf '%(%Y-%m-%d %H:%M:%S %Z)T' "$e"
  else date -d "@$e" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '%s' "$e"; fi
}

_cfw_fetch() {
  local out t n e er
  out="$(_cfw_cf --list)" || return 1
  _CFW_TYPE=(); _CFW_NAME=(); _CFW_EPOCH=(); _CFW_ERR=()
  while IFS=$'\t' read -r t n e er; do
    [ -n "$n" ] || continue
    _CFW_TYPE+=("$t"); _CFW_NAME+=("$n"); _CFW_EPOCH+=("$e"); _CFW_ERR+=("$er")
  done <<<"$out"
  [ "${#_CFW_NAME[@]}" -gt 0 ]
}

_cfw_load() {
  local creds
  creds="$("$_CFW_PY" "$_CFW_MAIN" "$_CFW_NAV" --print-credentials)" || { echo "❌ No usable Cloudflare credentials."; return 1; }
  _CFW_TOK="${creds%%$'\n'*}"; _CFW_ACC="${creds#*$'\n'}"; creds=""
  _lb_run "Loading workers and pages from Cloudflare" _cfw_fetch || { echo "❌ No workers or pages could be listed (see message above)."; _cfw_forget; return 1; }
}

# ── drawer screen (xui) ─────────────────────────────────────────────────────
cfw_build() {
  local i rows=()
  for i in "${!_CFW_NAME[@]}"; do rows+=("${_CFW_TYPE[$i]} ${_CFW_NAME[$i]} $(_cfw_when "${_CFW_EPOCH[$i]}")"); done
  _xui_begin_items "${rows[@]}"
}

cfw_row() {
  _xui_slot "$1"; local s="$_XUI_SLOT" tag="" icon="⚙️ " dir="${_CFW_NAME[$_XUI_SLOT]}-recovered"
  [ "${_CFW_TYPE[$s]}" = Pages ] && { icon="📄"; dir="${_CFW_NAME[$s]}-pages-recovered"; }
  [ -e "$_CFW_NAV/$dir" ] && tag="  ✅ recovered here"
  printf -v _vp_line ' %2d) %s %-6s %-30s  %s%s' "$1" "$icon" "${_CFW_TYPE[$s]}" \
    "$(_xui_trunc "${_CFW_NAME[$s]}" 30)" "$(_cfw_when "${_CFW_EPOCH[$s]}")" "$tag"
}

cfw_header() {
  local w=0 p=0 t
  for t in "${_CFW_TYPE[@]}"; do [ "$t" = Worker ] && w=$((w+1)) || p=$((p+1)); done
  echo; echo "☁️  Cloudflare Workers and Pages   (${w} workers · ${p} pages)"
  printf '📂 %s\n' "$_CFW_NAV"
  if declare -F _tz_label >/dev/null 2>&1; then printf '🕒 Latest deployment shown in: %s\n' "$(_tz_label)"; fi
  _vp_filter_header_line
}

cfw_footer() {
  _mc_footer "#Select:  N · 1,3-5 · a (all) · a-2 (all except 2)" "r:live picker" "rf:refresh" "u:back" \
    "#Recover  → $_CFW_NAV/<name>-recovered  (worker) · <name>-pages-recovered  (pages)" \
    "#Export   → e (all shown) · e-1,3-5 (picked)  as csv / json / both into the same folder"
}

# _XUI_SEL (display rows) -> confirm -> recover them
_cfw_run() {
  local r s picks=() args=() i
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; picks+=("$_XUI_SLOT"); done
  echo; echo "☁️  Recover ${#picks[@]} item(s) into $_CFW_NAV :"
  for s in "${picks[@]}"; do
    echo "     • ${_CFW_TYPE[$s]}  ${_CFW_NAME[$s]}"
    if [ "${_CFW_TYPE[$s]}" = Pages ]; then args+=(-p "${_CFW_NAME[$s]}"); else args+=(-w "${_CFW_NAME[$s]}"); fi
  done
  for s in "${picks[@]}"; do
    [ "${_CFW_TYPE[$s]}" = Pages ] && { echo "     ℹ️  Pages: only publicly reachable files of the latest production deployment can be recovered."; break; }
  done
  _xui_yes "Start recovery?" || return 1
  echo
  _cfw_cf "${args[@]}"
  echo; builtin read -e -r -p "   ↩  Press Enter to return to the list " _
  return 0
}

# e / e-SEL : write the rows (as shown, in the app timezone) to csv / json
_cfw_export() {
  local r s fmt files tsv=""
  if [[ "$1" == *-* ]]; then _xui_parse_sel "${1#*-}" || return 1
  else _XUI_SEL=($(seq 1 "${#items[@]}")); fi
  [ "${#_XUI_SEL[@]}" -gt 0 ] || { echo "ℹ️  Nothing to export."; return 1; }
  _xui_ask "Export ${#_XUI_SEL[@]} row(s) as  csv / json / both" csv || return 1
  fmt="${_XUI_IN,,}"
  case "$fmt" in csv|json|both) ;; *) echo "❌ Choose csv, json or both."; return 1 ;; esac
  for r in "${_XUI_SEL[@]}"; do
    _xui_slot "$r"; s="$_XUI_SLOT"
    tsv+="${_CFW_TYPE[$s]}"$'\t'"${_CFW_NAME[$s]}"$'\t'"${_CFW_EPOCH[$s]}"$'\n'
  done
  files="$(printf '%s' "$tsv" | "$_CFW_PY" "$_CFW_MAIN" "$_CFW_NAV" --export "$fmt")" || { echo "❌ Export failed."; return 1; }
  echo; echo "✅ Exported:"; while IFS= read -r r; do [ -n "$r" ] && echo "   $r"; done <<<"$files"
  echo; builtin read -e -r -p "   ↩  Press Enter to return to the list " _
  return 0
}

_cfw_cmd() {
  case "$1" in
    rf) _lb_run "Refreshing workers and pages" _cfw_fetch || echo "❌ Refresh failed."; return 0 ;;
    e|e-*) _cfw_export "$1"; return 0 ;;
    r|r-*)
      _xui_select_rows "RECOVER" "☁️  Recover which workers / pages?" "$1" || return 1
      _cfw_run; return 0 ;;
    [0-9]*|a|a-*)
      _xui_parse_sel "$1" || return 1
      _cfw_run; return 0 ;;
    fx|sw|api|.r|-u) echo "↩️  Go back with  u  first."; return 1 ;;   # a hop would leave a stale _inner_next behind
    *) return 9 ;;
  esac
}

# ── the button ──────────────────────────────────────────────────────────────
_fx_adf_cfwp() {
  _CFW_NAV="${_fx_outer_path:-$path}"            # the navigation path, NOT $PWD
  _cfw_locate || return 1
  _cfw_load || return 1
  _xui_enter
  _xui_screen cfw
  _xui_loop _cfw_cmd
  _xui_leave
  _cfw_forget
}
_fx_adf_register "cloudflare workers and pages" "_fx_adf_cfwp" "cloudflare_fx/workers and pages"
