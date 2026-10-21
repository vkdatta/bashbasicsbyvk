#!/usr/bin/env bash
# bashbasicsbyvk_pending.sh — the  pn  menu: PENDING FILEAPI ACTIONS (Home → Pending, or type  pn)
# ════════════════════════════════════════════════════════════════════════════
#   ⏸ Pending FileAPI actions
#    1) Upload (up-)          2 pending ›
#    2) RBAM share (ux-)      ›
#    3) Backup                ›
#    4) Save (save-)          ›
#    5) Snapshots             1 pending ›
#    6) Continue all interrupted
#    7) Refresh
#
#   service → the unfinished items of that service (unique id · name · % · state) → one item:
#       Continue now      send only the blobs the server does not hold yet (interrupted)
#       Resume            same, for an item you paused
#       Pause             keep everything, send nothing (also reaches a transfer running in ANOTHER terminal)
#       Stop for good     delete the incomplete blobs on the server and on this computer (asks first)
#   Items made on another computer are listed too; from here you can only STOP them (their data lives on that computer).
#
#   The engine is bashbasicsbyvk_staging_pending.sh; the server side is fileapi/src/pending.js.
#   Uses (from the main app): _st_run/_st_add (settings_ui), _bb_* helpers, _pn_* (the engine).
# ════════════════════════════════════════════════════════════════════════════

_PN_KINDS=(upload ux backup saved snapshot)
_PN_NAMES=("Upload (up-)" "RBAM share (ux-)" "Backup" "Save (save-)" "Snapshots")
declare -gA _PN_SRV=()          # id → "kind<TAB>status<TAB>blobsDone<TAB>nBlobs<TAB>bytesDone<TAB>estBytes<TAB>keepUntil" from the server
_PN_SRV_OK=0                    # 1 = the server answered at the last refresh
_PN_CUR_KIND=""; _PN_CUR_ID=""
declare -ga _PN_IDS=()

_pn_srv_load() {
  _PN_SRV=(); _PN_SRV_OK=0
  _bb_get_credentials >/dev/null 2>&1 || return 1
  _crypto_check >/dev/null 2>&1 || return 1
  _bb_call GET /pending || return 1
  [ "$_BB_STATUS" = 200 ] || return 1
  local line id rest
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    id="${line%%$'\t'*}"; rest="${line#*$'\t'}"
    _PN_SRV["$id"]="$rest"
  done < <(node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{let o;try{o=JSON.parse(d)}catch(e){process.exit(2)}
    for(const r of o.ops||[])console.log([r.id,r.kind,r.status,r.blobsDone??"",r.nBlobs??"",r.bytesDone??"",r.estBytes??"",r.keepUntil??""].join("\t"))})' <<<"$_BB_BODY")
  _PN_SRV_OK=1
  return 0
}

# every call that asks the server shows the same back-and-forth loading bar as the other menus (api, upgrade, workers…).
# _lb_run runs _pn_srv_load in THIS shell (no subshell), so _PN_SRV / _PN_SRV_OK are filled as usual; it draws only if the call takes > 0.15 s.
_pn_srv_load_bar() {
  if declare -F _lb_run >/dev/null 2>&1; then _lb_run "Checking the server for pending uploads" _pn_srv_load || true
  else _pn_srv_load; fi
}

# the ids of one service: this computer's items first, then the ones only the server knows
_pn_ids_of() {
  local kind="$1" id d f
  _PN_IDS=()
  while read -r id; do
    [ -n "$id" ] || continue
    [ "$(_pn_get "$(_pn_dir "$id")" kind)" = "$kind" ] && _PN_IDS+=("$id")
  done < <(_pn_local_ids)
  for id in "${!_PN_SRV[@]}"; do
    [ -d "$(_pn_dir "$id")" ] && continue
    f="${_PN_SRV[$id]}"; [ "${f%%$'\t'*}" = "$kind" ] && _PN_IDS+=("$id")
  done
}

# _pn_info <id> → _I_* : origin (here|other) status name done nb pct keep
_pn_info() {
  local id="$1" d f; d=$(_pn_dir "$id")
  _I_origin=other; _I_status=""; _I_name=""; _I_done=0; _I_nb=0; _I_pct=0; _I_keep=""; _I_last=-1; _I_kind=""
  local sk sst sdone snb sbytes sest skeep
  f="${_PN_SRV[$id]:-}"
  [ -n "$f" ] && IFS=$'\t' read -r sk sst sdone snb sbytes sest skeep <<<"$f"
  if [ -s "$d/state" ]; then
    local ldone="" lnb llast="" lsent="" ltot
    _I_origin=here; _I_kind=$(_pn_get "$d" kind); _I_name=$(_pn_get "$d" name); _I_status=$(_pn_status "$d")
    _I_nb=$(_pn_get "$d" nblobs); ltot=$(_pn_get "$d" total)
    [ -r "$d/progress" ] && read -r ldone _ llast lsent _ < "$d/progress"
    _I_done=${ldone:-0}; _I_last=${llast:--1}
    [ -n "$sdone" ] && _I_done="$sdone"                          # the server's own count wins
    [ "${_I_nb:-0}" -gt 0 ] && _I_pct=$(( _I_done * 100 / _I_nb ))
    [ "$_I_status" = interrupted ] && [ "$sst" = paused ] && _I_status=paused
  else
    _I_kind="$sk"; _I_status="${sst:-?}"; _I_name="(started on another computer)"
    _I_nb="${snb:-0}"; _I_done="${sdone:-0}"
    [ "${sest:-0}" -gt 0 ] && _I_pct=$(( ${sbytes:-0} * 100 / sest ))
  fi
  [ -n "$skeep" ] && _I_keep="$skeep"
  return 0
}
_pn_state_word() {
  case "$1" in
    running) printf 'running' ;;
    paused) printf 'paused' ;;
    interrupted) printf 'interrupted' ;;
    active) printf 'on server' ;;
    *) printf '%s' "$1" ;;
  esac
}
_pn_pause_enter() { local _a; read -r -s -n1 -p "  Press any key to go back… " _a; echo; }

# ── screen 3: one item ───────────────────────────────────────────────────────
_pn_item_build() {
  _st_reset
  _pn_info "$_PN_CUR_ID"
  local short="${_PN_CUR_ID:0:10}" st="$_I_status"
  _st_add h "${short}…  ${_I_name}"
  _st_add h "$(_pn_state_word "$st") · ${_I_done}/${_I_nb} blobs (${_I_pct}%)$([ "${_I_last:--1}" -ge 0 ] && printf ' · bookmark: blob %s' "$_I_last")"
  if [ "$_I_origin" = here ]; then
    case "$st" in
      interrupted) _st_add a "Continue now" 0 "" continue; _st_add a "Pause" 0 "" pause ;;
      paused)      _st_add a "Resume" 0 "" continue ;;
      running)     _st_add a "Pause" 0 "" pause ;;
    esac
  fi
  _st_add a "Stop for good (delete the incomplete blobs)" 0 "" stop
}
_pn_item_act() {
  local tag="${_st_tag[$1]}" d ans; d=$(_pn_dir "$_PN_CUR_ID")
  case "$tag" in
    continue)
      echo
      if [ "$_I_status" = running ]; then echo "⚠️  It is already running in another terminal."; else _pn_continue "$d"; fi
      _pn_pause_enter; _st_back=1 ;;
    pause)
      echo; _pn_pause "$_PN_CUR_ID"; _pn_pause_enter; _st_back=1 ;;
    stop)
      echo
      read -e -r -p "  Stop ${_PN_CUR_ID:0:10}… for good and DELETE its incomplete blobs? Nothing is charged. [y/N]: " ans || ans=n
      case "${ans,,}" in
        y|yes) _pn_stop "$_PN_CUR_ID" && _pn_pause_enter; _st_back=1 ;;
        *) echo "  🚫 Nothing was stopped."; _pn_pause_enter ;;
      esac ;;
  esac
}

# ── screen 2: the items of one service ──────────────────────────────────────
_pn_kind_build() {
  _st_reset
  _pn_ids_of "$_PN_CUR_KIND"
  if [ ${#_PN_IDS[@]} -eq 0 ]; then _st_add h "Nothing is pending here."; return; fi
  [ "$_PN_SRV_OK" = 1 ] || _st_add h "⚠️  Server not reachable — showing this computer only."
  local id i
  # Settings › Display › Sort order of this list (s): A-Z · Z-A · progress. Default "as listed" = this computer's items first.
  local -a _nm=() _pc=()
  for id in "${_PN_IDS[@]}"; do _pn_info "$id"; _nm+=("$_I_name"); _pc+=("$_I_pct"); done
  _ms_perm pending "${#_PN_IDS[@]}" name=_nm pct=_pc
  _ms_reorder _PN_IDS
  _ms_label pending; _st_add h "sorted: $_ms_l   (s = change)"
  for id in "${_PN_IDS[@]}"; do
    _pn_info "$id"
    _st_add a "${id:0:10}…  ${_I_name}  ${_I_pct}%" 0 "$(_pn_state_word "$_I_status")" "$id"
  done
}
# typed on the list of one service: s → Settings, where Display › Sort order is this list's own
_pn_kind_cmd() {
  case "$1" in
    s) local _MS_CTX=pending; settings_menu; return 0 ;;
  esac
  return 1
}
_pn_kind_act() {
  local id="${_st_tag[$1]}"
  [ -n "$id" ] || return 0
  _PN_CUR_ID="$id"
  _st_run "${id:0:10}…" _pn_item_build _pn_item_act
  echo; _pn_srv_load_bar
  _st_quit=0
}

# ── screen 1: the five services ─────────────────────────────────────────────
_pn_top_build() {
  _st_reset
  local i n id k
  for i in "${!_PN_KINDS[@]}"; do
    k="${_PN_KINDS[$i]}"; _pn_ids_of "$k"; n=${#_PN_IDS[@]}
    _st_add a "${_PN_NAMES[$i]}" 0 "$([ "$n" -gt 0 ] && printf '%s pending' "$n")" "$k"
  done
  _st_add a "Continue all interrupted (this computer)" 0 "" all
  _st_add a "Refresh" 0 "" refresh
  [ "$_PN_SRV_OK" = 1 ] || _st_add h "⚠️  Server not reachable — showing this computer only."
}
_pn_top_act() {
  local tag="${_st_tag[$1]}" id d n=0
  case "$tag" in
    refresh) echo; _pn_srv_load_bar ;;
    all)
      echo
      while read -r id; do
        d=$(_pn_dir "$id"); [ "$(_pn_status "$d")" = interrupted ] || continue
        n=$((n + 1)); echo "▶️  ${id:0:10}…  $(_pn_get "$d" name)"
        _pn_continue "$d"
      done < <(_pn_local_ids)
      [ $n -eq 0 ] && echo "  Nothing interrupted on this computer."
      _pn_pause_enter; echo; _pn_srv_load_bar ;;
    *)
      _PN_CUR_KIND="$tag"
      local i; for i in "${!_PN_KINDS[@]}"; do [ "${_PN_KINDS[$i]}" = "$tag" ] && break; done
      _st_run "${_PN_NAMES[$i]}" _pn_kind_build _pn_kind_act "" _pn_kind_cmd
      _st_quit=0 ;;
  esac
}

pending_menu() {
  local _icon_keep="${_st_icon:-}" _st_crumb="Pending"
  _st_icon="⏸"
  _pn_gc
  builtin printf '\n'
  _pn_srv_load_bar          # opening the menu asks the server: show the bar (it used to sit there silent)
  _st_run "Pending FileAPI actions" _pn_top_build _pn_top_act
  _st_quit=0
  _st_icon="$_icon_keep"
  builtin printf '\n'
}
