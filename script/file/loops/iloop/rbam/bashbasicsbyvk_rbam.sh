#!/usr/bin/env bash
# rbam — Role Based Access Management  (Home → RBAM, or type  rbam)
# ════════════════════════════════════════════════════════════════════════════
#  An inner loop with two tabs (←/→):   [📤 Give access]   [📥 Receive access]
#
#    Give access      people who may receive MY files   (I am their sender)
#    Receive access   people whose files I may receive  (I am their receiver)
#
#  Commands (same on both tabs)
#    ui [file]   import a user: paste their card (mail + d30). From a file: one card per line.
#                On Give access it says "I give you receive access"; on Receive access it says "please give me access".
#    ux          export MY card (mail + my d30, the 30 shareable diseps codes) to hand to someone
#    r-N         remove users  (r-1,3 · r-a · r-a-2). Removing a receiver ends their access to my whole cloud;
#                removing a sender ends my access to theirs.
#    sd | sd-N   (Give access) send my 290 dinons, sealed, to receivers who do not have them (needed after -auth regenerates them)
#    N           open a user: the shares they can reach, with removal (r-N) and a drill-down into files/folders
#
#  The other side is asked in their Notifications (nf):  "a person with mail … and diseps … has given you receive access …
#  Do you want to become receiver? 1. Yes 2. No".   The SENDER shares all 290 dinons with the receiver — never the reverse.
#  Dinons travel sealed to the receiver's own sealing key: the server only ever holds blobs it cannot open.
#
#  Uses: bashbasicsbyvk_xui.sh (screens), bashbasicsbyvk_staging_ux.sh (_ux_*), bashbasicsbyvk_csurf.sh (_cs_*)
# ════════════════════════════════════════════════════════════════════════════

_RB_TAB=0
_RB_LOADED=0
declare -ga _RB_RID=() _RB_MAIL=() _RB_D30=() _RB_ST=() _RB_MINE=() _RB_DIN=() _RB_SEAL=() _RB_HELD=()

_rb_load() {
  _RB_RID=(); _RB_MAIL=(); _RB_D30=(); _RB_ST=(); _RB_MINE=(); _RB_DIN=(); _RB_SEAL=(); _RB_HELD=()
  _ux_http GET /rbam/rels || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local kind=gives rid mail d30 st mine din seal held
  [ "$_RB_TAB" = 1 ] && kind=receives
  while IFS=$'\x1f' read -r rid mail d30 st mine din seal held; do
    [ -n "$rid" ] || continue
    _RB_RID+=("$rid"); _RB_MAIL+=("$mail"); _RB_D30+=("$d30"); _RB_ST+=("$st")
    _RB_MINE+=("$mine"); _RB_DIN+=("$din"); _RB_SEAL+=("$seal"); _RB_HELD+=("$held")
  done < <(_ux_core tsv "$kind" <<<"$_UX_BODY")
  _RB_LOADED=1
  return 0
}

_rb_state() {                                # slot -> _RB_S
  local k="$1"
  if [ "${_RB_ST[$k]}" = pending ]; then
    if [ "${_RB_MINE[$k]}" = 1 ]; then _RB_S="⏳ waiting for their answer"
    else _RB_S="📨 they asked you — open it to answer"; fi
  elif [ "$_RB_TAB" = 0 ]; then
    if   [ "${_RB_DIN[$k]}" = 1 ]; then _RB_S="💫 active · 🔑 dinons sent"
    elif [ "${_RB_HELD[$k]}" = 1 ]; then _RB_S="💫 active · ⏸ dinons held (sd-N sends)"
    else _RB_S="💫 active · ⏳ dinons not sent yet"; fi
  else
    if [ "${_RB_DIN[$k]}" = 1 ]; then _RB_S="💫 active · 🔑 you can open their files"
    else _RB_S="💫 active · ⏳ waiting for their dinons"; fi
  fi
}

rb_build() {
  [ "$_RB_LOADED" = 1 ] || _rb_load
  _xui_begin_items "${_RB_MAIL[@]}"
}
rb_row() {
  _xui_slot "$1"; local k=$_XUI_SLOT
  _rb_state "$k"
  printf -v _vp_line ' %2d) 👤 %-28s [%s…]  %s' "$1" "$(_xui_trunc "${_RB_MAIL[$k]}" 28)" "${_RB_D30[$k]:0:6}" "$_RB_S"
}
# ── Tabs: defined once in the master template (bashbasicsbyvk_tabmenu.sh), which also draws the bar and builds the footer ──
_tm_define rb _RB_TAB "🤝 RBAM" "RBAM" 0:"📤 Give access" 1:"📥 Receive access"
rb_header() {
  _tm_header rb                                    # blank · title · tab bar · description (RBAM|0 · RBAM|1)
  _tm_count_line
  echo
  [ "${#items[@]}" -eq 0 ] && echo "Nobody here yet — type  ui  to add someone."
  _vp_filter_header_line
}
rb_footer() { _tm_footer -b; }                     # u q h cc: every other key (ui ux r-N sd N …) is listed by cc

# ── commands ─────────────────────────────────────────────────────────────────
_rb_mail_ok() { [[ "$1" =~ ^[^[:space:]\"\\]+@[^[:space:]\"\\]+$ ]] && [ "${#1}" -le 256 ]; }
_rb_d30_ok()   { local s; read -ra s <<<"$(_bvk_share_spec)"; [[ "$1" =~ ^[A-Za-z0-9]{16}(-[A-Za-z0-9]{16})*$ ]] && [ "$(awk -F- '{print NF}' <<<"$1")" -eq $(( ${#s[@]} - 1 )) ]; }

_rb_request_one() {                          # mail d30
  local mail="$1" d30="$2" role=give note
  [ "$_RB_TAB" = 1 ] && role=ask
  _rb_mail_ok "$mail" || { echo "🔴  '$mail' is not a valid mail." >&2; return 1; }
  _rb_d30_ok "$d30"     || { echo "🔴  The d30 must be their 30 shareable diseps codes (16 characters each) joined with '-', exactly as printed on their RBAM card." >&2; return 1; }
  _ux_http POST /rbam/request "{\"role\":\"$role\",\"mail\":\"$mail\",\"d30\":\"$d30\"}" || return 1
  if ! _ux_ok; then echo "   ❌ $mail — $(_bb_json_get "$_UX_BODY" message)"; return 1; fi
  note=$(_bb_json_get "$_UX_BODY" note)
  if [ -n "$note" ]; then echo "   💫 $mail — $note"
  elif [ "$role" = give ]; then echo "   💫 $mail — asked to become your receiver. They will see it in their Notifications (nf)."
  else echo "   💫 $mail — asked to become your sender. They will see it in their Notifications (nf)."; fi
  return 0
}

_rb_import() {
  local arg="${1# }" mail d30 junk n=0 bad=0
  _ux_ensure_seal || return 1
  if [ -n "$arg" ] && [ -f "$arg" ]; then
    while read -r mail d30 junk; do
      case "$mail" in ''|\#*) continue ;; esac
      if _rb_request_one "$mail" "$d30"; then n=$((n+1)); else bad=$((bad+1)); fi
    done < "$arg"
    echo "   Done: $n sent, $bad failed."
    return 0
  fi
  if [ -n "$arg" ]; then read -r mail d30 junk <<<"$arg"
  else
    echo "   Paste their card:  <mail> <diseps 13-24-7>     (they get it from  rbam → ux)"
    _xui_ask "Their card, or just their mail" || return 1
    read -r mail d30 junk <<<"$_XUI_IN"
  fi
  if [ -z "$d30" ]; then
    _xui_ask "Their d30 (30 codes joined with -)" || return 1
    d30="$_XUI_IN"
  fi
  _rb_request_one "$mail" "$d30"
}

_rb_export() {
  _ux_need || return 1
  local d30; d30=$(_bb_d30 "$P_DISEPS")
  [ -n "$d30" ] || { echo "❌ The active user has no usable diseps."; return 1; }
  echo
  echo "📇 Your RBAM card — give it to the people you want to link with."
  echo "   (your mail + your d30, the shareable part of your diseps; everything else stays secret)"
  echo
  echo "   $P_MAIL $d30"
  echo
  local ans f
  _bvk_yn ans "Save it to a file in this folder too?"
  case "$ans" in [yY]*)
    f="$PWD/rbam-card.txt"
    [ -e "$f" ] && f="$PWD/rbam-card-$(date +%s).txt"
    ( umask 077; printf '%s %s\n' "$P_MAIL" "$d30" > "$f" ) && echo "   💾 Saved: $f" ;;
  esac
}

_rb_remove() {                               # r-LIST
  _xui_select_rows "REMOVE" "🗑️  Remove which users?" "$1" || return 1
  local r k rid n=0 txt
  [ "$_RB_TAB" = 0 ] && txt="They lose access to everything you shared." || txt="You lose access to everything they shared."
  echo "   $txt"
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; echo "   • ${_RB_MAIL[$_XUI_SLOT]}"; done
  _xui_yes "Remove ${#_XUI_SEL[@]} user(s)?" || return 1
  for r in "${_XUI_SEL[@]}"; do
    _xui_slot "$r"; k=$_XUI_SLOT; rid="${_RB_RID[$k]}"
    _ux_http POST "/rbam/rel/$rid/remove" "{}" || continue
    if _ux_ok; then n=$((n+1)); else echo "   ❌ ${_RB_MAIL[$k]}: $(_bb_json_get "$_UX_BODY" message)"; fi
  done
  echo "💫 Removed $n user(s)."
}

_rb_senddinons() {                           # sd | sd-LIST
  [ "$_RB_TAB" = 0 ] || { echo "📜  Dinons are sent from the Give access tab."; return 1; }
  local -a rids=() r
  if [[ "$1" == sd-* ]]; then
    _xui_parse_sel "${1#sd-}" || return 1
    for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; rids+=("${_RB_RID[$_XUI_SLOT]}"); done
    _ux_sync_dinons force "${rids[@]}"
  else
    _ux_sync_dinons force
  fi
  echo "💫 Done."
}

# answer a pending request from the list (the same question nf asks)
_rb_answer() {
  local k="$1" q
  if [ "$_RB_TAB" = 0 ]; then q="has asked to receive your files. Become their sender and share your dinons with them?"
  else q="has offered to give you receive access. Become their receiver?"; fi
  echo "   📨 ${_RB_MAIL[$k]} [${_RB_D30[$k]}] $q"
  echo "      1. Yes   2. No"
  local a; _bvk_read a "   Select: "
  case "$a" in 1|y|Y) _nf_rbam_respond "${_RB_RID[$k]}" true ;; 2|n|N) _nf_rbam_respond "${_RB_RID[$k]}" false ;; *) echo "🚫 No answer given." ;; esac
}

_rb_cmd() {
  case "$1" in
    __sw_tab_right__|__sw_tab_left__) _tm_key rb "$1" nowrap || return 1; _RB_LOADED=0; return 3 ;;
    rbam) echo "↩️  Closing RBAM"; return 2 ;;
    ui|ui\ *) _rb_import "${1#ui}"; _RB_LOADED=0; return 0 ;;
    ux)  _rb_export; return 1 ;;
    r-*) _rb_remove "$1"; _RB_LOADED=0; return 0 ;;
    rf)  _RB_LOADED=0; return 0 ;;
    sd|sd-*) _rb_senddinons "$1"; _RB_LOADED=0; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { _bvk_invalid; return 0; }
      local k=$_XUI_SLOT
      if [ "${_RB_ST[$k]}" = pending ]; then
        if [ "${_RB_MINE[$k]}" = 1 ]; then echo "📜  Waiting for ${_RB_MAIL[$k]} to answer."; return 1; fi
        _rb_answer "$k"; _RB_LOADED=0; return 0
      fi
      _rb_user_open "$k"; _RB_LOADED=0; return 0 ;;
    *) return 9 ;;
  esac
}

# ── one user: the shares they can reach ──────────────────────────────────────
declare -ga _RU_ID=() _RU_ALIAS=() _RU_BYTES=() _RU_EXP=() _RU_ST=()
_RU_RID=""; _RU_MAIL=""; _RU_LOADED=0

_rb_user_load() {
  _RU_ID=(); _RU_ALIAS=(); _RU_BYTES=(); _RU_EXP=(); _RU_ST=()
  _ux_http GET /ux/shares || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local list="$_UX_BODY" id alias bytes c1 exp acc off x1 x2 x3 offer from fd rid
  if [ "$_RB_TAB" = 0 ]; then
    while IFS=$'\x1f' read -r id alias bytes c1 exp acc off x1 x2 x3; do
      [ -n "$id" ] || continue
      _ux_http GET "/ux/$id" || continue
      _ux_ok || continue
      while IFS=$'\x1f' read -r rid _ _ offer; do
        [ "$rid" = "$_RU_RID" ] || continue
        _RU_ID+=("$id"); _RU_ALIAS+=("$alias"); _RU_BYTES+=("$bytes"); _RU_EXP+=("$exp"); _RU_ST+=("$offer")
      done < <(_ux_core tsv people <<<"$_UX_BODY")
    done < <(_ux_core tsv given <<<"$list")
  else
    while IFS=$'\x1f' read -r id alias bytes exp offer from fd rid; do
      [ -n "$id" ] && [ "$rid" = "$_RU_RID" ] || continue
      _RU_ID+=("$id"); _RU_ALIAS+=("$alias"); _RU_BYTES+=("$bytes"); _RU_EXP+=("$exp"); _RU_ST+=("$offer")
    done < <(_ux_core tsv received <<<"$list")
  fi
  _RU_LOADED=1
}

ru_build() {
  [ "$_RU_LOADED" = 1 ] || _rb_user_load
  local -a lab=() i
  for i in "${!_RU_ID[@]}"; do lab+=("${_RU_ALIAS[$i]:-${_RU_ID[$i]}}"); done
  _xui_begin_items "${lab[@]}"
}
ru_row() {
  _xui_slot "$1"; local k=$_XUI_SLOT st="${_RU_ST[$k]}" tag=""
  [ "$st" = offered ] && tag="  ⏳ not accepted yet"
  printf -v _vp_line ' %2d) 📦 %-24s %9s  %s%s' "$1" "$(_xui_trunc "${_RU_ALIAS[$k]:-${_RU_ID[$k]}}" 24)" "$(_xui_hsize "${_RU_BYTES[$k]}")" "$(_xui_left "${_RU_EXP[$k]}")" "$tag"
}
ru_header() {
  echo
  if [ "$_RB_TAB" = 0 ]; then echo "👤 $_RU_MAIL can reach these of your shares:"; else echo "👤 $_RU_MAIL has shared these with you:"; fi
  [ "${#items[@]}" -eq 0 ] && echo "   (nothing)"
  _vp_filter_header_line
}
ru_footer() {
  if [ "$_RB_TAB" = 0 ]; then _mc_footer_std -b "N:files" "r-N:revoke this person from a share"
  else                        _mc_footer_std -b "N:files" "r-N:drop a share from my Cloud Surf"; fi
}

_ru_remove() {
  _xui_select_rows "REMOVE" "🗑️  Remove which shares?" "$1" || return 1
  local r k id
  if [ "$_RB_TAB" = 0 ]; then echo "   $_RU_MAIL will no longer see these (the stored data is NOT refunded — only a nuke or a shorter nuke time refunds)."
  else echo "   These disappear from your Cloud Surf (the sender keeps them)."; fi
  _xui_yes "Continue?" || return 1
  for r in "${_XUI_SEL[@]}"; do
    _xui_slot "$r"; k=$_XUI_SLOT; id="${_RU_ID[$k]}"
    if [ "$_RB_TAB" = 0 ]; then _ux_http POST "/ux/$id/revoke" "{\"rid\":$_RU_RID}"
    else _ux_http POST "/ux/$id/leave" "{}"; fi
    if _ux_ok; then echo "   💫 ${_RU_ALIAS[$k]:-$id}"; else echo "   ❌ ${_RU_ALIAS[$k]:-$id}: $(_bb_json_get "$_UX_BODY" message)"; fi
  done
}

_ru_cmd() {
  case "$1" in
    r-*) _ru_remove "$1"; _RU_LOADED=0; return 0 ;;
    rf)  _RU_LOADED=0; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { _bvk_invalid; return 0; }
      local k=$_XUI_SLOT
      if [ "$_RB_TAB" = 0 ]; then _cs_tree_open "${_RU_ID[$k]}" owner "$_RU_RID"
      elif [ "${_RU_ST[$k]}" = accepted ]; then _cs_tree_open "${_RU_ID[$k]}" receiver
      else _cs_answer_offer "${_RU_ID[$k]}" "${_RU_ALIAS[$k]}"; fi
      _RU_LOADED=0; return 0 ;;
    *) return 9 ;;
  esac
}

_rb_user_open() {
  local k="$1"
  _RU_RID="${_RB_RID[$k]}"; _RU_MAIL="${_RB_MAIL[$k]}"; _RU_LOADED=0
  _xui_enter
  _xui_screen ru
  _xui_loop _ru_cmd
  _xui_leave
}

# ── the loop ─────────────────────────────────────────────────────────────────
rbam_menu() {
  _ux_need || return 1
  _RB_TAB="${1:-0}"; _RB_LOADED=0
  _ux_ensure_seal || true                       # makes sure senders can seal their dinons to us
  _ux_sync_dinons auto 2>/dev/null || true      # receivers who just accepted get our dinons now
  _xui_enter
  _xui_screen rb
  _xui_loop _rb_cmd
  _xui_leave
}
