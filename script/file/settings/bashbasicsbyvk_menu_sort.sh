# bashbasicsbyvk_menu_sort.sh — menu-specific  Display › Sort order
# ════════════════════════════════════════════════════════════════════════════
#  The general "Sort order" (A→Z, newest, largest …) is for FILES in a folder. Screens that list cloud things
#  (links, backups, shares, snapshots, pending uploads) have other columns — expiry, date modified, progress — so each
#  of them gets its OWN sort list, saved separately:
#
#     menu            sort choices                                                       default
#     links  (api)    A-Z · Z-A · created ↑↓ · modified ↑↓ · size ↓↑ · time to expiry ↓↑     soonest expiry first
#     backup (bk)     same as links
#     saved  (sv)     same as links
#     shares_given    A-Z · Z-A · created ↑↓ · size ↓↑ · time to expiry ↓↑                   soonest expiry first
#     shares_recv     A-Z · Z-A · sender A-Z/Z-A · size ↓↑ · time to expiry ↓↑                soonest expiry first
#     snap_devices    A-Z · Z-A · last seen ↑↓ · number of snapshots ↓↑                       last seen first
#     snap_targets    A-Z · Z-A · last snapshot ↑↓                                            order they were added
#     snapshots       date taken ↑↓ · size ↓↑ · time to expiry ↓↑                             newest first
#     pending         A-Z · Z-A · progress ↑↓                                                 this computer first (as before)
#
#  Two ways in:
#    * inside one of those screens type  s  →  Settings › Display › Sort order  shows THAT screen's list
#      (and nothing from the general settings).  A screen announces itself with  local _MS_CTX=<menu>.
#    * from anywhere:  Settings › Menu specific › <menu> › Display › Sort order
#
#  Storage: ONE config value,  menu_sort_str="links=az backup=exp_long …"  (only menus changed from the default are
#  listed). A value that is not valid for its menu falls back to the default, so an old or hand-edited file is safe.
#
#  Needs: bashbasicsbyvk_settings_ui.sh (_st_run _st_add _st_eq _st_reset), bashbasicsbyvk_settings.sh (save_settings).
# ════════════════════════════════════════════════════════════════════════════

declare -ga _MS_ORDER=(links backup saved shares_given shares_recv snap_devices snap_targets snapshots pending)
declare -gA _MS_NAME=(
  [links]="Links (api)"            [backup]="Backup (bk)"           [saved]="Saved Surf (sv)"
  [shares_given]="Cloud Surf › Given" [shares_recv]="Cloud Surf › Received"
  [snap_devices]="Snapshots › Devices" [snap_targets]="Snapshots › Paths of a device" [snapshots]="Snapshots › Snapshots of a path"
  [pending]="Pending uploads (pn)")

# the tokens each menu offers, in the order shown
declare -gA _MS_MODES=(
  [links]="az za cr_old cr_new mo_old mo_new size_big size_small exp_long exp_short"
  [backup]="az za cr_old cr_new mo_old mo_new size_big size_small exp_long exp_short"
  [saved]="az za cr_old cr_new mo_old mo_new size_big size_small exp_long exp_short"
  [shares_given]="az za cr_old cr_new size_big size_small exp_long exp_short"
  [shares_recv]="az za from_az from_za size_big size_small exp_long exp_short"
  [snap_devices]="az za seen_old seen_new snaps_most snaps_few"
  [snap_targets]="az za last_old last_new srv"
  [snapshots]="cr_old cr_new size_big size_small exp_long exp_short"
  [pending]="srv az za pct_high pct_low")
declare -gA _MS_DEFAULT=(
  [links]=exp_short [backup]=exp_short [saved]=exp_short [shares_given]=exp_short [shares_recv]=exp_short
  [snap_devices]=seen_new [snap_targets]=srv [snapshots]=cr_new [pending]=srv)

# labels (one set for every menu; a menu can word one differently with _MS_LBL[<menu>:<token>])
declare -gA _MS_BASE=(
  [az]="A → Z"  [za]="Z → A"
  [cr_old]="Date created · oldest to newest"   [cr_new]="Date created · newest to oldest"
  [mo_old]="Date modified · oldest to newest"  [mo_new]="Date modified · newest to oldest"
  [size_big]="Size · large to small"           [size_small]="Size · small to large"
  [exp_long]="Time to expiry · largest to smallest"  [exp_short]="Time to expiry · smallest to largest"
  [from_az]="Sender A → Z"  [from_za]="Sender Z → A"
  [seen_old]="Last seen · oldest first"  [seen_new]="Last seen · newest first"
  [snaps_most]="Most snapshots first"    [snaps_few]="Fewest snapshots first"
  [last_old]="Last snapshot · oldest first"  [last_new]="Last snapshot · newest first"
  [pct_high]="Progress · most done first"    [pct_low]="Progress · least done first"
  [srv]="As listed (default order)")
declare -gA _MS_LBL=(
  [snapshots:cr_old]="Date taken · oldest to newest"  [snapshots:cr_new]="Date taken · newest to oldest"
  [pending:srv]="This computer first (default)")

# token → what to sort on:  field  numeric(1/0)  reverse(1/0)
_ms_tok() {
  case "$1" in
    az)         _ms_f=name     _ms_n=0 _ms_r=0 ;;   za)        _ms_f=name     _ms_n=0 _ms_r=1 ;;
    from_az)    _ms_f=from     _ms_n=0 _ms_r=0 ;;   from_za)   _ms_f=from     _ms_n=0 _ms_r=1 ;;
    cr_old)     _ms_f=created  _ms_n=1 _ms_r=0 ;;   cr_new)    _ms_f=created  _ms_n=1 _ms_r=1 ;;
    mo_old)     _ms_f=modified _ms_n=1 _ms_r=0 ;;   mo_new)    _ms_f=modified _ms_n=1 _ms_r=1 ;;
    size_big)   _ms_f=size     _ms_n=1 _ms_r=1 ;;   size_small) _ms_f=size     _ms_n=1 _ms_r=0 ;;
    exp_long)   _ms_f=expiry   _ms_n=1 _ms_r=1 ;;   exp_short)  _ms_f=expiry   _ms_n=1 _ms_r=0 ;;
    seen_old)   _ms_f=seen     _ms_n=1 _ms_r=0 ;;   seen_new)   _ms_f=seen     _ms_n=1 _ms_r=1 ;;
    snaps_most) _ms_f=snaps    _ms_n=1 _ms_r=1 ;;   snaps_few)  _ms_f=snaps    _ms_n=1 _ms_r=0 ;;
    last_old)   _ms_f=last     _ms_n=1 _ms_r=0 ;;   last_new)   _ms_f=last     _ms_n=1 _ms_r=1 ;;
    pct_high)   _ms_f=pct      _ms_n=1 _ms_r=1 ;;   pct_low)    _ms_f=pct      _ms_n=1 _ms_r=0 ;;
    *)          _ms_f=srv      _ms_n=0 _ms_r=0 ;;
  esac
}

# ── value of one menu ─────────────────────────────────────────────────────────
# _ms_valid <menu> <token>  → 0 when the menu offers that token
_ms_valid() { [[ " ${_MS_MODES[$1]:-} " == *" $2 "* ]]; }

# _ms_get <menu>  → $_ms_v   (the saved choice, else the menu's default; never invalid)
_ms_get() {
  local m="$1" s=" ${menu_sort_str:-} "
  _ms_v="${_MS_DEFAULT[$m]:-az}"
  if [[ "$s" =~ [[:space:]]"$m"=([a-z_]+)[[:space:]] ]] && _ms_valid "$m" "${BASH_REMATCH[1]}"; then _ms_v="${BASH_REMATCH[1]}"; fi
}

# _ms_label <menu> [token]  → $_ms_l   (token defaults to the saved choice)
_ms_label() {
  local m="$1" t="${2:-}"
  if [ -z "$t" ]; then _ms_get "$m"; t="$_ms_v"; fi
  _ms_l="${_MS_LBL[$m:$t]:-${_MS_BASE[$t]:-$t}}"
}

# _ms_set <menu> <token>  → saved at once. Choosing the default removes the entry (the file stays short).
_ms_set() {
  local m="$1" t="$2" w out=""
  _ms_valid "$m" "$t" || return 1
  for w in ${menu_sort_str:-}; do [[ "$w" == "$m="* ]] || out+="${out:+ }$w"; done
  [ "$t" = "${_MS_DEFAULT[$m]:-az}" ] || out+="${out:+ }$m=$t"
  menu_sort_str="$out"
  save_settings
}

# ── the sorter ────────────────────────────────────────────────────────────────
#  _ms_perm <menu> <n> <field>=<array-name> …   →  _MS_PERM = the 0-based indexes in the wanted order.
#  Only the arrays a screen really has are passed; a choice whose field is not among them (or "as listed") keeps the
#  order as it is. Ties keep their old order. Text sorts case-insensitively, numbers numerically (blank = 0).
declare -ga _MS_PERM=()
_ms_perm() {
  local m="$1" n="$2" i kv f a ref key lines="" fa="" k1 k2="-k2,2n"; shift 2
  _MS_PERM=(); for (( i=0; i<n; i++ )); do _MS_PERM+=("$i"); done
  (( n > 1 )) || return 0
  _ms_get "$m"; _ms_tok "$_ms_v"
  [ "$_ms_f" = srv ] && return 0
  for kv in "$@"; do f="${kv%%=*}"; [ "$f" = "$_ms_f" ] && { fa="${kv#*=}"; break; }; done
  [ -n "$fa" ] || return 0
  for (( i=0; i<n; i++ )); do
    ref="$fa[$i]"; key="${!ref-}"
    if [ "$_ms_n" = 1 ]; then [[ "$key" =~ ^[0-9]+$ ]] || key=0
    else key="${key,,}"; key="${key//[$'\t\n\r']/ }"; [ -n "$key" ] || key=" "; fi
    lines+="$key"$'\t'"$i"$'\n'
  done
  if [ "$_ms_n" = 1 ]; then k1="-k1,1n"; else k1="-k1,1"; fi
  [ "$_ms_r" = 1 ] && k1+="r"
  _MS_PERM=()
  while IFS=$'\t' read -r _ i; do [ -n "$i" ] && _MS_PERM+=("$i"); done < <(printf '%s' "$lines" | LC_ALL=C sort -t$'\t' -s "$k1" $k2)
  (( ${#_MS_PERM[@]} == n )) || { _MS_PERM=(); for (( i=0; i<n; i++ )); do _MS_PERM+=("$i"); done; }
}

# _ms_reorder <array-name> …   puts those arrays into the order of _MS_PERM (they must all have n entries)
_ms_reorder() {
  local a i ref; local -a tmp
  for a in "$@"; do
    tmp=()
    for i in "${_MS_PERM[@]}"; do ref="$a[$i]"; tmp+=("${!ref-}"); done
    eval "$a=(\"\${tmp[@]}\")"
  done
}

# ── Settings screens ─────────────────────────────────────────────────────────
_MS_SEL=""      # the menu a Settings screen below is about

# the choice itself (radio list)
_st_ms_sort_build() {
  local t; _ms_get "$_MS_SEL"
  _st_reset
  _st_add h "Sort for:  ${_MS_NAME[$_MS_SEL]}"
  for t in ${_MS_MODES[$_MS_SEL]}; do
    _ms_label "$_MS_SEL" "$t"
    _st_eq "$t" "$_ms_v"
    _st_add r "$_ms_l" "$_o" "" "$t"
  done
}
_st_ms_sort_act() { _ms_set "$_MS_SEL" "${_st_tag[$1]}"; }
_st_ms_sort_open() { _MS_SEL="$1"; _st_run "Sort order" _st_ms_sort_build _st_ms_sort_act; }

# the settings groups of one menu (today: Display)
_st_ms_group_build() {
  _ms_label "$_MS_SEL"
  _st_reset
  _st_add h "${_MS_NAME[$_MS_SEL]}"
  _st_add a "Display" 0 "$_ms_l" display
}
_st_ms_group_act() { case "${_st_tag[$1]}" in display) _st_ms_display_open "$_MS_SEL" ;; esac; }

# Display of one menu: only its own settings (no file-browser ones)
_st_ms_display_build() {
  _ms_label "$_MS_SEL"
  _st_reset
  _st_add a "Sort order" 0 "$_ms_l" sort
}
_st_ms_display_act() { case "${_st_tag[$1]}" in sort) _st_ms_sort_open "$_MS_SEL" ;; esac; }
_st_ms_display_open() { _MS_SEL="$1"; _st_run "Display" _st_ms_display_build _st_ms_display_act; }

# Settings › Menu specific: the list of menus
_st_ms_top_build() {
  local m
  _st_reset
  _st_add h "Settings that belong to one screen only"
  for m in "${_MS_ORDER[@]}"; do _ms_label "$m"; _st_add a "${_MS_NAME[$m]}" 0 "$_ms_l" "$m"; done
}
_st_ms_top_act() {
  local m="${_st_tag[$1]}"
  [ -n "$m" ] || return 0
  _MS_SEL="$m"; _st_run "${_MS_NAME[$m]}" _st_ms_group_build _st_ms_group_act
  _st_quit=0
}
menu_specific_settings() { _st_run "Menu specific" _st_ms_top_build _st_ms_top_act; }

# Settings › Display, seen from INSIDE a menu-specific screen: its own sort and nothing else
_st_ms_ctx_build() {
  _ms_label "$_MS_CTX"
  _st_reset
  _st_add h "You are in:  ${_MS_NAME[$_MS_CTX]}"
  _st_add a "Sort order" 0 "$_ms_l" sort
}
_st_ms_ctx_act() { case "${_st_tag[$1]}" in sort) _st_ms_sort_open "$_MS_CTX" ;; esac; }
menu_context_display_settings() { _st_run "Display" _st_ms_ctx_build _st_ms_ctx_act; }
