#!/usr/bin/env bash
# nf — Notifications  (Home → Notifications, or type  nf)
# ════════════════════════════════════════════════════════════════════════════
#  What other people did that needs you, or that you should know about:
#
#    rbam_give      "a person with mail … and diseps … has given you receive access … Do you want to become receiver? 1. Yes 2. No"
#    rbam_ask       they ask to receive from you — Yes makes you their sender and sends them your dinons (sealed)
#    share_offer    they shared files with you via ux- — Yes puts it in your Cloud Surf (cs)
#    info only      accepted · declined · removed · access taken away · nuked      (read it, it clears itself)
#
#    N     open / answer      r-N   dismiss (1,3-5 · a)      u   back
# ════════════════════════════════════════════════════════════════════════════

declare -ga _NF_ID=() _NF_KIND=() _NF_REF=() _NF_AT=() _NF_MAIL=() _NF_D3=() _NF_ALIAS=() _NF_BYTES=() _NF_FILES=() _NF_NUKED=() _NF_ROLE=()
_NF_LOADED=0

_nf_load() {
  _NF_ID=(); _NF_KIND=(); _NF_REF=(); _NF_AT=(); _NF_MAIL=(); _NF_D3=(); _NF_ALIAS=(); _NF_BYTES=(); _NF_FILES=(); _NF_NUKED=(); _NF_ROLE=()
  _ux_http GET /notifications || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local id kind ref at mail d3 alias bytes files nuked role
  while IFS=$'\x1f' read -r id kind ref at mail d3 alias bytes files nuked role; do
    [ -n "$id" ] || continue
    _NF_ID+=("$id"); _NF_KIND+=("$kind"); _NF_REF+=("$ref"); _NF_AT+=("$at"); _NF_MAIL+=("$mail"); _NF_D3+=("$d3")
    _NF_ALIAS+=("$alias"); _NF_BYTES+=("$bytes"); _NF_FILES+=("$files"); _NF_NUKED+=("$nuked"); _NF_ROLE+=("$role")
  done < <(_ux_core tsv notifs <<<"$_UX_BODY")
  _NF_LOADED=1
}

# slot -> _NF_T (the sentence)  _NF_ACT (1 = needs an answer)
_nf_text() {
  local k="$1" who nm
  who="a person with mail ${_NF_MAIL[$k]} and diseps ${_NF_D3[$k]}"
  nm="“${_NF_ALIAS[$k]:-a share}”"
  _NF_ACT=0
  case "${_NF_KIND[$k]}" in
    rbam_give)     _NF_T="$who has given you receive access to their cloud environment. Do you want to become receiver?"; _NF_ACT=1 ;;
    rbam_ask)      _NF_T="$who is asking to receive access to your cloud environment. Do you want to become their sender (your dinons are sent to them, sealed)?"; _NF_ACT=1 ;;
    rbam_accepted) _NF_T="${_NF_MAIL[$k]} (${_NF_D3[$k]}) accepted — the link is active." ;;
    rbam_rejected) _NF_T="${_NF_MAIL[$k]} (${_NF_D3[$k]}) declined." ;;
    rbam_removed)  _NF_T="${_NF_MAIL[$k]} (${_NF_D3[$k]}) ended the link; access between you is gone." ;;
    share_offer)   _NF_T="$who has shared $nm with you (${_NF_FILES[$k]:-?} files, $(_xui_hsize "${_NF_BYTES[$k]:-0}")). Do you want to accept it into your Cloud Surf?"; _NF_ACT=1 ;;
    share_revoked) if [ "${_NF_NUKED[$k]}" = 1 ]; then _NF_T="${_NF_MAIL[$k]} nuked $nm — it is gone for everyone."
                   else _NF_T="${_NF_MAIL[$k]} took your access to $nm away."; fi ;;
    *)             _NF_T="(${_NF_KIND[$k]})" ;;
  esac
}

nf_build() {
  [ "$_NF_LOADED" = 1 ] || _nf_load
  local -a lab=() i
  for i in "${!_NF_ID[@]}"; do _nf_text "$i"; lab+=("$_NF_T"); done
  _xui_begin_items "${lab[@]}"
}
nf_row() {
  _xui_slot "$1"; local k=$_XUI_SLOT icon="ℹ️ "
  _nf_text "$k"
  [ "$_NF_ACT" = 1 ] && icon="📨"
  printf -v _vp_line ' %2d) %s %s' "$1" "$icon" "$(_xui_trunc "$_NF_T" 100)"
}
nf_header() {
  echo; echo "🔔 Notifications"
  [ "${#items[@]}" -eq 0 ] && echo "   Nothing new."
  _vp_filter_header_line
}
nf_footer() { printf '\nN) open / answer   r-N) dismiss   rf) refresh   u) back\n'; }

# ── answers ──────────────────────────────────────────────────────────────────
_nf_rbam_respond() {                         # rid true|false   (also used by the rbam list)
  local rid="$1" acc="$2"
  [ "$acc" = true ] && { _ux_ensure_seal || return 1; }
  _ux_http POST /rbam/respond "{\"rid\":$rid,\"accept\":$acc}" || return 1
  if ! _ux_ok; then _ux_fail; return 1; fi
  if [ "$acc" = true ]; then
    echo "✅ Done — the link is active."
    _ux_sync_dinons force "$rid"                # does something only when I am the sender
  else echo "✅ Declined."; fi
}

_nf_dismiss() {
  _ux_http POST "/notifications/$1/dismiss" "{}"
  _ux_ok
}

_nf_open() {
  local k="$1" a kind="${_NF_KIND[$1]}"
  _nf_text "$k"
  echo; echo "   🔔 $_NF_T"
  if [ "$_NF_ACT" = 1 ]; then
    echo "      1. Yes   2. No   (anything else: decide later)"
    builtin read -r -p "   Select: " a
    case "$a" in
      1|y|Y) a=true ;; 2|n|N) a=false ;; *) echo "🕒 Left for later."; return 0 ;;
    esac
    case "$kind" in
      rbam_give|rbam_ask) _nf_rbam_respond "${_NF_REF[$k]}" "$a" ;;
      share_offer)
        _ux_http POST "/ux/${_NF_REF[$k]}/respond" "{\"accept\":$a}" || return 1
        if _ux_ok; then
          [ "$a" = true ] && echo "✅ Accepted — find it in Cloud Surf (cs), tab “Shared with me”." || echo "✅ Declined."
        else _ux_fail; fi ;;
    esac
  else
    _nf_dismiss "${_NF_ID[$k]}" >/dev/null 2>&1
  fi
}

_nf_cmd() {
  case "$1" in
    nf) echo "↩️  Closing notifications"; return 2 ;;
    rf) _NF_LOADED=0; return 0 ;;
    r-*)
      _xui_select_rows "DISMISS" "🗑️  Dismiss which notifications?" "$1" || return 1
      local r k
      for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; k=$_XUI_SLOT; _nf_dismiss "${_NF_ID[$k]}"; done
      echo "✅ Dismissed ${#_XUI_SEL[@]}."; _NF_LOADED=0; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { echo "⚠️  Invalid selection"; return 1; }
      _nf_open "$_XUI_SLOT"; _NF_LOADED=0; return 0 ;;
    *) return 9 ;;
  esac
}

notify_menu() {
  _ux_need || return 1
  _NF_LOADED=0
  _ux_sync_dinons auto 2>/dev/null || true       # people who accepted you as sender since last time
  _xui_enter
  _xui_screen nf
  _xui_loop _nf_cmd
  _xui_leave
}
