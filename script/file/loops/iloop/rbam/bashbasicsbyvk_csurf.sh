#!/usr/bin/env bash
# cs — Cloud Surf  (Home → Cloud Surf / Shared, or type  cs)
# ════════════════════════════════════════════════════════════════════════════
#  The interim portal for ux- shares.  Two tabs (←/→):   [📤 Given]   [📥 Received]
#
#  GIVEN (I am the sender)      share → people → folders → files, with a way to take access away at EVERY level
#    share list    N people of a share · x-N nuke for everyone (refund) · e-N [+2d|-1d|3d] change the nuke time
#    people        N what that person sees · r-N revoke the person · g offer it to more people · t all my files
#    files         N open folder · r-N revoke those files/folders for this person · d-N download · u up
#
#  RECEIVED (I am the receiver) share → folders → files
#    share list    N open (or answer the offer) · r-N drop a share from my Cloud Surf
#    files         N open folder · d-N download into the folder you are surfing · r-N drop · u up
#
#  Revoking, or a nuke by the sender, before a download takes the receiver's access away; nothing is left to download.
#  Refunds only when the data is completely gone: a nuke, or a shorter nuke time (whole days). Revoking never refunds.
#  Files and names are decrypted here, on this machine; the server only holds ciphertext.
#
#  Uses: bashbasicsbyvk_xui.sh, bashbasicsbyvk_staging_ux.sh
# ════════════════════════════════════════════════════════════════════════════

_CS_TAB=0
_CS_LOADED=0
declare -ga _CG_ID=() _CG_ALIAS=() _CG_BYTES=() _CG_CREATED=() _CG_EXP=() _CG_ACC=() _CG_OFF=() _CG_REF=() _CG_REFD=() _CG_PAID=()
declare -ga _CR_ID=() _CR_ALIAS=() _CR_BYTES=() _CR_EXP=() _CR_OFFER=() _CR_FROM=() _CR_FROMD3=() _CR_RID=()

_cs_idjson() { local o="" i; for i in "$@"; do o+="${o:+,}\"$i\""; done; printf '[%s]' "$o"; }
_cs_name() { printf '%s' "${1:-$2}"; }

_cs_load() {
  _CG_ID=(); _CG_ALIAS=(); _CG_BYTES=(); _CG_CREATED=(); _CG_EXP=(); _CG_ACC=(); _CG_OFF=(); _CG_REF=(); _CG_REFD=(); _CG_PAID=()
  _CR_ID=(); _CR_ALIAS=(); _CR_BYTES=(); _CR_EXP=(); _CR_OFFER=(); _CR_FROM=(); _CR_FROMD3=(); _CR_RID=()
  _ux_http GET /ux/shares || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local list="$_UX_BODY" id al by cr ex ac of rf rd pd offer from fd rid
  while IFS=$'\x1f' read -r id al by cr ex ac of rf rd pd; do
    [ -n "$id" ] || continue
    _CG_ID+=("$id"); _CG_ALIAS+=("$al"); _CG_BYTES+=("$by"); _CG_CREATED+=("$cr"); _CG_EXP+=("$ex")
    _CG_ACC+=("$ac"); _CG_OFF+=("$of"); _CG_REF+=("$rf"); _CG_REFD+=("$rd"); _CG_PAID+=("$pd")
  done < <(_ux_core tsv given <<<"$list")
  while IFS=$'\x1f' read -r id al by ex offer from fd rid; do
    [ -n "$id" ] || continue
    _CR_ID+=("$id"); _CR_ALIAS+=("$al"); _CR_BYTES+=("$by"); _CR_EXP+=("$ex"); _CR_OFFER+=("$offer"); _CR_FROM+=("$from"); _CR_FROMD3+=("$fd"); _CR_RID+=("$rid")
  done < <(_ux_core tsv received <<<"$list")
  _CS_LOADED=1
}

_cs_answer_offer() {                         # share id, alias
  echo "   📨 “${2:-$1}” was offered to you.   1. Yes   2. No"
  local a; builtin read -r -p "   Select: " a
  case "$a" in
    1|y|Y) a=true ;; 2|n|N) a=false ;; *) echo "🕒 Left for later."; return 0 ;;
  esac
  _ux_http POST "/ux/$1/respond" "{\"accept\":$a}" || return 1
  if _ux_ok; then [ "$a" = true ] && echo "✅ Accepted." || echo "✅ Declined."; else _ux_fail; fi
}

# ═════════════════════════ share list (the two tabs) ═════════════════════════
cs_build() {
  [ "$_CS_LOADED" = 1 ] || _cs_load
  local -a lab=() i
  if [ "$_CS_TAB" = 0 ]; then for i in "${!_CG_ID[@]}"; do lab+=("${_CG_ALIAS[$i]:-${_CG_ID[$i]}}"); done
  else                        for i in "${!_CR_ID[@]}"; do lab+=("${_CR_ALIAS[$i]:-${_CR_ID[$i]}} ${_CR_FROM[$i]}"); done; fi
  _xui_begin_items "${lab[@]}"
}
cs_row() {
  _xui_slot "$1"; local k=$_XUI_SLOT
  if [ "$_CS_TAB" = 0 ]; then
    printf -v _vp_line ' %2d) 📦 %-22s %9s  %-14s ✅%s ⏳%s' "$1" "$(_xui_trunc "${_CG_ALIAS[$k]:-${_CG_ID[$k]}}" 22)" \
      "$(_xui_hsize "${_CG_BYTES[$k]}")" "$(_xui_left "${_CG_EXP[$k]}")" "${_CG_ACC[$k]}" "${_CG_OFF[$k]}"
  else
    local tag=""; [ "${_CR_OFFER[$k]}" = offered ] && tag="  ⏳ answer me"
    printf -v _vp_line ' %2d) 📦 %-22s %9s  %-14s from %s%s' "$1" "$(_xui_trunc "${_CR_ALIAS[$k]:-${_CR_ID[$k]}}" 22)" \
      "$(_xui_hsize "${_CR_BYTES[$k]}")" "$(_xui_left "${_CR_EXP[$k]}")" "$(_xui_trunc "${_CR_FROM[$k]}" 26)" "$tag"
  fi
}
cs_header() {
  local a=" 📤 Given " b=" 📥 Received "
  [ "$_CS_TAB" = 0 ] && a="[📤 Given]" || b="[📥 Received]"
  echo; printf '☁️  Cloud Surf   %s  %s     (←/→ switch tab)\n' "$a" "$b"
  if [ "${#items[@]}" -eq 0 ]; then
    [ "$_CS_TAB" = 0 ] && echo "   Nothing shared yet — use  ux-<items>  in the file surf." || echo "   Nothing received yet."
  fi
  _vp_filter_header_line
}
cs_footer() {
  if [ "$_CS_TAB" = 0 ]; then printf '\nN) people   x-N) nuke for everyone (refund)   e-N [time]) nuke time   rf) refresh   u) back\n'
  else                        printf '\nN) open   r-N) drop from my list   rf) refresh   u) back\n'; fi
}

_cs_nuke() {                                 # x-LIST
  _xui_select_rows "NUKE" "💥 Nuke which shares — for EVERYONE?" "$1" || return 1
  local r k tot=0
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; k=$_XUI_SLOT
    echo "   • ${_CG_ALIAS[$k]:-${_CG_ID[$k]}}  ($(_xui_hsize "${_CG_BYTES[$k]}"))  refund now: ${_CG_REF[$k]} credits (${_CG_REFD[$k]} full day(s) unused)"
    tot=$(( tot + ${_CG_REF[$k]:-0} ))
  done
  echo "   The data is deleted from our storage and database; every receiver loses access. Refund total: $tot credits."
  _xui_yes "Nuke ${#_XUI_SEL[@]} share(s)?" || return 1
  local ok=0 ref bal
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; k=$_XUI_SLOT
    _ux_http DELETE "/ux/${_CG_ID[$k]}" || continue
    if _ux_ok; then
      ref=$(_ux_jget refunded "$_UX_BODY"); bal=$(_ux_jget balance "$_UX_BODY"); ok=$((ok+1))
      echo "   💥 ${_CG_ALIAS[$k]:-${_CG_ID[$k]}} — refunded ${ref:-0}  (balance ${bal:-?})"
    else echo "   ❌ ${_CG_ALIAS[$k]:-${_CG_ID[$k]}}: $(_bb_json_get "$_UX_BODY" message)"; fi
  done
  echo "✅ Nuked $ok share(s)."
}

_cs_expiry() {                               # e-N [spec]
  local rest="${1#[eE]-}" n spec secs cur sign="" base k
  n="${rest%% *}"; spec=""; [[ "$rest" == *" "* ]] && spec="${rest#* }"
  _xui_row "$n" || { echo "⚠️  Invalid selection"; return 1; }
  k=$_XUI_SLOT
  cur=$(( (${_CG_EXP[$k]} - ${_CG_CREATED[$k]}) / 1000 ))
  echo "   “${_CG_ALIAS[$k]:-${_CG_ID[$k]}}” now lives $(_bb_fmt_duration "$cur") in total  ($(_xui_left "${_CG_EXP[$k]}"))."
  if [ -z "$spec" ]; then _xui_ask "New TOTAL life (e.g. 7d, 36h, +2d, -1d)" || return 1; spec="$_XUI_IN"; fi
  case "$spec" in +*|-*) sign="${spec:0:1}"; spec="${spec:1}" ;; esac
  secs=$(_bb_parse_duration "$spec") || { echo "⚠️  Use a number with a unit (s, m, h, d, w), e.g. 2d, +12h, -1d." ; return 1; }
  case "$sign" in +) base=$((cur+secs)) ;; -) base=$((cur-secs)) ;; *) base=$secs ;; esac
  if [ "$base" -lt "$_BB_NUKE_MIN" ] || [ "$base" -gt "$_BB_NUKE_MAX" ]; then
    echo "⚠️  Total life must be between 1 minute and 30 days (that would be $(_bb_fmt_duration "$base"))."; return 1
  fi
  echo "   New total life: $(_bb_fmt_duration "$base").  Longer = charged the difference; shorter = refund of whole unused days only."
  _xui_yes "Apply?" || return 1
  _ux_http POST "/ux/${_CG_ID[$k]}/expiry" "{\"totalSeconds\":$base}" || return 1
  if _ux_ok; then
    local ch rf; ch=$(_ux_jget charged "$_UX_BODY"); rf=$(_ux_jget refunded "$_UX_BODY")
    echo "✅ Updated.${ch:+ Charged: $ch.}${rf:+ Refunded: $rf.}  Balance: $(_ux_jget balance "$_UX_BODY")"
  else _ux_fail; fi
}

_cs_drop() {                                 # r-LIST on the received tab
  _xui_select_rows "DROP" "🗑️  Drop which shares from your Cloud Surf?" "$1" || return 1
  echo "   They disappear from your list (the sender keeps them; they may offer again)."
  _xui_yes "Continue?" || return 1
  local r k
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; k=$_XUI_SLOT
    _ux_http POST "/ux/${_CR_ID[$k]}/leave" "{}"
    if _ux_ok; then echo "   ✅ ${_CR_ALIAS[$k]:-${_CR_ID[$k]}}"; else echo "   ❌ $(_bb_json_get "$_UX_BODY" message)"; fi
  done
}

_cs_cmd() {
  case "$1" in
    __sw_tab_right__) [ "$_CS_TAB" = 1 ] && return 1; _CS_TAB=1; _CS_LOADED=0; return 3 ;;
    __sw_tab_left__)  [ "$_CS_TAB" = 0 ] && return 1; _CS_TAB=0; _CS_LOADED=0; return 3 ;;
    cs) echo "↩️  Closing Cloud Surf"; return 2 ;;
    rf) _CS_LOADED=0; return 0 ;;
    x-*) [ "$_CS_TAB" = 0 ] || { echo "ℹ️  Only the sender can nuke. Use r-N to drop it from your list."; return 1; }
         _cs_nuke "$1"; _CS_LOADED=0; return 0 ;;
    e-*) [ "$_CS_TAB" = 0 ] || { echo "ℹ️  Only the sender can change the nuke time."; return 1; }
         _cs_expiry "$1"; _CS_LOADED=0; return 0 ;;
    r-*) if [ "$_CS_TAB" = 1 ]; then _cs_drop "$1"; _CS_LOADED=0; return 0
         else echo "ℹ️  Open a share (N) to revoke people or files; x-N nukes it for everyone."; return 1; fi ;;
    [0-9]*)
      _xui_row "$1" || { echo "⚠️  Invalid selection"; return 1; }
      local k=$_XUI_SLOT
      if [ "$_CS_TAB" = 0 ]; then _cs_people_open "$k"
      elif [ "${_CR_OFFER[$k]}" = accepted ]; then _cs_tree_open "${_CR_ID[$k]}" receiver
      else _cs_answer_offer "${_CR_ID[$k]}" "${_CR_ALIAS[$k]}"; fi
      _CS_LOADED=0; return 0 ;;
    *) return 9 ;;
  esac
}

# ═════════════════════════ people of one share (sender) ══════════════════════
_PP_ID=""; _PP_ALIAS=""; _PP_LOADED=0
declare -ga _PP_RID=() _PP_MAIL=() _PP_D3=() _PP_ST=()

_pp_load() {
  _PP_RID=(); _PP_MAIL=(); _PP_D3=(); _PP_ST=()
  _ux_http GET "/ux/$_PP_ID" || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  local rid mail d3 st
  while IFS=$'\x1f' read -r rid mail d3 st; do
    [ -n "$mail" ] || continue
    _PP_RID+=("$rid"); _PP_MAIL+=("$mail"); _PP_D3+=("$d3"); _PP_ST+=("$st")
  done < <(_ux_core tsv people <<<"$_UX_BODY")
  _PP_LOADED=1
}
cs_pp_build() { [ "$_PP_LOADED" = 1 ] || _pp_load; _xui_begin_items "${_PP_MAIL[@]}"; }
cs_pp_row() {
  _xui_slot "$1"; local k=$_XUI_SLOT tag="✅ accepted"
  [ "${_PP_ST[$k]}" = offered ] && tag="⏳ not accepted yet"
  [ -n "${_PP_RID[$k]}" ] || tag="⚠️ link removed"
  printf -v _vp_line ' %2d) 👤 %-28s [%s…]  %s' "$1" "$(_xui_trunc "${_PP_MAIL[$k]}" 28)" "${_PP_D3[$k]:0:6}" "$tag"
}
cs_pp_header() {
  echo; echo "📦 “${_PP_ALIAS:-$_PP_ID}” — who can see it"
  [ "${#items[@]}" -eq 0 ] && echo "   Nobody (everyone was revoked)."
  _vp_filter_header_line
}
cs_pp_footer() { printf '\nN) their files   r-N) revoke person   g) offer to more people   t) all my files   u) back\n'; }

_pp_revoke() {
  _xui_select_rows "REVOKE" "🚫 Revoke which people from this share?" "$1" || return 1
  echo "   They lose access at once — even if they have not downloaded yet. (No refund: the data is still stored.)"
  _xui_yes "Revoke ${#_XUI_SEL[@]} person/people?" || return 1
  local r k
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; k=$_XUI_SLOT
    [ -n "${_PP_RID[$k]}" ] || { echo "   ℹ️  ${_PP_MAIL[$k]}: the link is already removed."; continue; }
    _ux_http POST "/ux/$_PP_ID/revoke" "{\"rid\":${_PP_RID[$k]}}"
    if _ux_ok; then echo "   ✅ ${_PP_MAIL[$k]}"; else echo "   ❌ ${_PP_MAIL[$k]}: $(_bb_json_get "$_UX_BODY" message)"; fi
  done
}

_pp_grant() {
  _ux_pick_people || return 1
  local csv; csv=$(IFS=,; echo "${_UX_PICKED[*]}")
  _ux_http POST "/ux/$_PP_ID/grant" "{\"rids\":[$csv]}" || return 1
  if _ux_ok; then echo "✅ Offered to $(_ux_jget offered "$_UX_BODY") new person/people (already-shared ones are untouched)."; else _ux_fail; fi
}

_pp_cmd() {
  case "$1" in
    rf) _PP_LOADED=0; return 0 ;;
    r-*) _pp_revoke "$1"; _PP_LOADED=0; return 0 ;;
    g) _pp_grant; _PP_LOADED=0; return 0 ;;
    t) _cs_tree_open "$_PP_ID" owner ""; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { echo "⚠️  Invalid selection"; return 1; }
      local k=$_XUI_SLOT
      [ -n "${_PP_RID[$k]}" ] || { echo "ℹ️  The link to ${_PP_MAIL[$k]} was removed in RBAM."; return 1; }
      [ "${_PP_ST[$k]}" = accepted ] || echo "ℹ️  ${_PP_MAIL[$k]} has not accepted yet — this is what they would see."
      _cs_tree_open "$_PP_ID" owner "${_PP_RID[$k]}"; _PP_LOADED=0; return 0 ;;
    *) return 9 ;;
  esac
}

_cs_people_open() {
  local k="$1"
  _PP_ID="${_CG_ID[$k]}"; _PP_ALIAS="${_CG_ALIAS[$k]}"; _PP_LOADED=0
  _xui_enter
  _xui_screen cs_pp
  _xui_loop _pp_cmd
  _xui_leave
}

# ═════════════════════════ files and folders ═════════════════════════════════
_CT_ID=""; _CT_ROLE=""; _CT_RID=""; _CT_LOADED=0; _CT_MAILS=""; _CT_ALIAS=""
_CT_DETAIL=""; _CT_ITEMS=""; _CT_FROM=""; _CT_EXP=0
declare -ga _CT_IID=() _CT_PAR=() _CT_KIND=() _CT_BYTES=() _CT_CHUNKS=() _CT_NAME=() _CT_ARC=()   # everything (unfiltered); _CT_ARC=1 → a tar.gz archive share
declare -ga _CT_ROWS=()                                                                 # slots shown in the current folder
declare -gA _CT_VIS=()
declare -ga _CT_STACK=() _CT_CRUMB=()
_CT_CUR="-"

_ct_load() {
  _CT_IID=(); _CT_PAR=(); _CT_KIND=(); _CT_BYTES=(); _CT_CHUNKS=(); _CT_NAME=(); _CT_ARC=(); _CT_VIS=()
  _ux_http GET "/ux/$_CT_ID" || return 1
  if ! _ux_ok; then _ux_fail >&2; return 1; fi
  _CT_DETAIL="$_UX_BODY"
  _CT_ALIAS=$(_ux_jget share.alias "$_CT_DETAIL")
  _CT_ITEMS=$(_ux_jget items "$_CT_DETAIL")
  _CT_FROM=$(_ux_jget from.mail "$_CT_DETAIL"); _CT_EXP=$(_ux_jget share.expiresAt "$_CT_DETAIL")
  _ux_K_of "$_CT_DETAIL" || return 1
  local iid par kind by ch nm arc
  while IFS=$'\t' read -r iid par kind by ch nm arc; do
    [ -n "$iid" ] || continue
    _CT_IID+=("$iid"); _CT_PAR+=("$par"); _CT_KIND+=("$kind"); _CT_BYTES+=("$by"); _CT_CHUNKS+=("$ch"); _CT_NAME+=("$nm"); _CT_ARC+=("${arc:-0}")
  done < <(printf '%s' "$_CT_DETAIL" | BB_K="$_UX_K" _ux_core items-decrypt)
  if [ "$_CT_ROLE" = owner ] && [ -n "$_CT_RID" ]; then
    _ux_http GET "/ux/$_CT_ID/access/$_CT_RID" || return 1
    if _ux_ok; then
      local v; v=$(_ux_jget visible "$_UX_BODY"); v="${v//[\[\]\"]/}"
      local x; for x in ${v//,/ }; do _CT_VIS[$x]=1; done
      _CT_MAILS=$(_ux_core tsv people <<<"$_CT_DETAIL" | awk -F'\037' -v r="$_CT_RID" '$1==r{print $2}')
    fi
  fi
  _CT_LOADED=1
}

ct_build() {
  [ "$_CT_LOADED" = 1 ] || _ct_load
  _CT_ROWS=(); local -a lab=() i
  for i in "${!_CT_IID[@]}"; do
    [ "${_CT_PAR[$i]}" = "$_CT_CUR" ] || continue
    if [ "$_CT_ROLE" = owner ] && [ -n "$_CT_RID" ] && [ -z "${_CT_VIS[${_CT_IID[$i]}]:-}" ]; then continue; fi
    _CT_ROWS+=("$i"); lab+=("${_CT_NAME[$i]}")
  done
  _xui_begin_items "${lab[@]}"
}
ct_row() {
  _xui_slot "$1"; local i="${_CT_ROWS[$_XUI_SLOT]}"
  if [ "${_CT_KIND[$i]}" = d ]; then printf -v _vp_line ' %2d) 📁 %s/' "$1" "$(_xui_trunc "${_CT_NAME[$i]}" 60)"
  elif [ "${_CT_ARC[$i]:-0}" = 1 ]; then printf -v _vp_line ' %2d) 📦 %-50s %9s' "$1" "$(_xui_trunc "${_CT_NAME[$i]}" 50)" "$(_xui_hsize "${_CT_BYTES[$i]}")"
  else printf -v _vp_line ' %2d) 📄 %-50s %9s' "$1" "$(_xui_trunc "${_CT_NAME[$i]}" 50)" "$(_xui_hsize "${_CT_BYTES[$i]}")"; fi
}
ct_header() {
  local crumb="“${_CT_ALIAS:-$_CT_ID}”" c
  for c in "${_CT_CRUMB[@]}"; do crumb+=" › $c"; done
  echo; echo "📂 $crumb"
  if   [ "$_CT_ROLE" = receiver ]; then echo "   from $_CT_FROM  ·  $(_xui_left "$_CT_EXP")"
  elif [ -n "$_CT_RID" ];          then echo "   what ${_CT_MAILS:-this person} can see"
  else                                  echo "   all files in this share (yours)"; fi
  [ "${#items[@]}" -eq 0 ] && echo "   (empty)"
  _vp_filter_header_line
}
ct_footer() {
  local rv="r-N) revoke"
  [ "$_CT_ROLE" = receiver ] && rv="r-N) drop"
  [ "$_CT_ROLE" = owner ] && [ -z "$_CT_RID" ] && rv=""
  printf '\nN) open   d-N) download here   %s   rf) refresh   u) up/back\n' "$rv"
}

_ct_dest() { local d="${path:-$PWD}"; [ -d "$d" ] && [ -w "$d" ] || d="$PWD"; printf '%s' "$d"; }

_ct_download() {                             # d-LIST
  _xui_select_rows "DOWNLOAD" "📥 Download which? (folders include everything inside)" "$1" || return 1
  local -a ids=() r
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; ids+=("${_CT_IID[${_CT_ROWS[$_XUI_SLOT]}]}"); done
  local dest; dest=$(_ct_dest)
  echo "   Into: $dest"
  _xui_yes "Download ${#ids[@]} item(s) here?" || return 1
  _ux_http POST "/ux/$_CT_ID/dl-token" "{}" || return 1
  if ! _ux_ok; then _ux_fail; echo "   (Access may have been removed or the share nuked.)"; return 1; fi
  local tok; tok=$(_ux_jget token "$_UX_BODY")
  # archive shares (made by ux- like up-: one tar.gz) take the do- path; older per-file shares take the tree path
  local -a arc_idx=() old_ids=() ; local id i
  for id in "${ids[@]}"; do
    for i in "${!_CT_IID[@]}"; do
      [ "${_CT_IID[$i]}" = "$id" ] || continue
      if [ "${_CT_ARC[$i]:-0}" = 1 ]; then arc_idx+=("$i"); else old_ids+=("$id"); fi
    done
  done
  local rc=0
  for i in "${arc_idx[@]}"; do _ct_fetch_archive "$tok" "$i" "$dest" || rc=1; done
  if [ "${#old_ids[@]}" -gt 0 ]; then
    local out
    out=$(printf '{"items":%s,"ids":%s}' "$_CT_ITEMS" "$(_cs_idjson "${old_ids[@]}")" \
          | BB_DLTOKEN="$tok" BB_K="$_UX_K" BB_CONC="${_BB_MAX_PAR:-4}" _ux_core download "$WORKER_URL" "$_CT_ID" "$dest")
    local status n bytes tops; IFS=$'\t' read -r status n bytes tops <<<"$out"
    if [ "$status" = OK ]; then
      echo "✅ $n file(s), $(_xui_hsize "$bytes") decrypted into $dest"
      echo "   ${tops//|/, }"
    else
      echo "❌ Download failed: ${n:-unknown error}"
      echo "   Nothing partial was left behind."
      rc=1
    fi
  fi
  tok=""
  return $rc
}

# archive share → download + decrypt (same as do-) → safe unpack (same as do-)
_ct_fetch_archive() {                          # <dl token> <slot in _CT_*> <dest>
  local tok="$1" i="$2" dest="$3"
  echo "📦 Archive share detected."
  mkdir -p "$dest"
  local arc; arc=$(mktemp "$dest/.bbvk_dl.XXXXXX") || { echo "❌ Cannot write to $dest"; return 1; }
  local res
  res=$(BB_DLTOKEN="$tok" BB_K="$_UX_K" BB_CONC="${_BB_MAX_PAR:-8}" _ux_core fetch-arc "$WORKER_URL" "$_CT_ID" "${_CT_IID[$i]}" "${_CT_CHUNKS[$i]}" "${_CT_BYTES[$i]}" "$arc")
  case "${res%%$'\t'*}" in
    OK) ;;
    *)  echo "❌ Download failed — some chunks could not be fetched or failed their integrity check. Nothing was unpacked."
        [ -n "${res#*$'\t'}" ] && [ "$res" != "${res#*$'\t'}" ] && echo "   ${res#*$'\t'}"
        rm -f "$arc"; return 1 ;;
  esac
  _unpack_targz_safe "$arc" "$dest"
  local rc=$?
  rm -f "$arc"
  [ $rc -eq 0 ] && echo "ℹ️  The share stays in your Cloud Surf until its nuke time runs out (or the sender nukes it)."
  return $rc
}

_ct_revoke() {                               # r-LIST
  if [ "$_CT_ROLE" = owner ] && [ -z "$_CT_RID" ]; then echo "ℹ️  Revoking is per person: go back and open a person first."; return 1; fi
  _xui_select_rows "REVOKE" "🚫 Take away which?" "$1" || return 1
  local -a ids=() r
  for r in "${_XUI_SEL[@]}"; do _xui_slot "$r"; ids+=("${_CT_IID[${_CT_ROWS[$_XUI_SLOT]}]}"); done
  if [ "$_CT_ROLE" = owner ]; then echo "   ${_CT_MAILS:-They} lose these at once (folders include everything inside). No refund: the data is still stored."
  else echo "   These leave your Cloud Surf (the sender keeps them)."; fi
  _xui_yes "Continue with ${#ids[@]} item(s)?" || return 1
  if [ "$_CT_ROLE" = owner ]; then _ux_http POST "/ux/$_CT_ID/revoke" "{\"rid\":$_CT_RID,\"items\":$(_cs_idjson "${ids[@]}")}"
  else _ux_http POST "/ux/$_CT_ID/leave" "{\"items\":$(_cs_idjson "${ids[@]}")}"; fi
  if _ux_ok; then echo "✅ Done."; else _ux_fail; fi
}

_ct_cmd() {
  case "$1" in
    rf) _CT_LOADED=0; return 0 ;;
    u)  if [ "${#_CT_STACK[@]}" -gt 0 ]; then
          _CT_CUR="${_CT_STACK[-1]}"; unset '_CT_STACK[-1]' '_CT_CRUMB[-1]'; return 0
        fi
        return 2 ;;
    d-*) _ct_download "$1"; return 1 ;;
    r-*) _ct_revoke "$1" && _CT_LOADED=0; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { echo "⚠️  Invalid selection"; return 1; }
      local i="${_CT_ROWS[$_XUI_SLOT]}"
      if [ "${_CT_KIND[$i]}" = d ]; then
        _CT_STACK+=("$_CT_CUR"); _CT_CRUMB+=("${_CT_NAME[$i]}"); _CT_CUR="${_CT_IID[$i]}"; return 0
      fi
      echo "   📄 ${_CT_NAME[$i]}  ·  $(_xui_hsize "${_CT_BYTES[$i]}")   (d-$1 downloads it)"; return 1 ;;
    *) return 9 ;;
  esac
}

# _cs_tree_open <share id> <owner|receiver> [rid]   rid: the person the sender is looking at
_cs_tree_open() {
  _CT_ID="$1"; _CT_ROLE="$2"; _CT_RID="${3:-}"
  _CT_LOADED=0; _CT_CUR="-"; _CT_STACK=(); _CT_CRUMB=(); _CT_MAILS=""
  _xui_enter
  _xui_screen ct
  _xui_loop _ct_cmd
  _xui_leave
  _UX_K=""
}

# ── the loop ─────────────────────────────────────────────────────────────────
csurf_menu() {
  _ux_need || return 1
  _CS_TAB="${1:-0}"; _CS_LOADED=0
  _xui_enter
  _xui_screen cs
  _xui_loop _cs_cmd
  _xui_leave
}
