#!/usr/bin/env bash
# ============================================================
#  ADVERT  —  the one list of what a menu accepts.   (self-service model)
#
#  A menu DECLARES the commands it accepts, once, into a registry:
#
#      _ad_open  <menu>                         start declaring (the old declaration is gone)
#      _ad_accept KEY "description" [PRIO] [SHOWN]
#                    KEY    what is typed ("clr", "r-", "a-2")        PRIO  footer priority, higher first (0 = cc only)
#                    SHOWN  how the footer writes it ("r-N")          default KEY
#      _ad_free   KEY "description" [SHOWN]     a standard key (u q rf h cc): always in the footer, costs nothing
#
#  and two advertisers RENDER that list, as it is.  They do no lookup, no crawling, no judging:
#
#      cc      lists EVERY declared command                       cost per command = 0   (_AD_COST_CC)
#      footer  lists the declared commands the budget buys        cost per command = 10  (_AD_COST_FOOTER)
#              budget of every menu = 50  (_AD_BUDGET)  → five paid commands, highest PRIO first; free keys come on top
#
#  So the footer is always a subset of cc, and cc is always everything the menu declared.  Declaring is the ONLY way to be advertised.
#  The tests that keep a declaration honest: tests/static (footer, arms, intent, advert). They read the real declarations and score every menu without a terminal;
#      coverage = accepted ∩ cc / accepted × 100        (< 100  → that menu needs an urgent fix)
#      phantom in cc      = −100 each      phantom in footer = −1000 each      (advertised, but the menu does not take it)
#
#  Declaring helpers (a menu calls the ones it needs; they only DECLARE):
#      _ad_from_map MAP [st]     the commands the menu's .map wires and the menu accepts (st = a list screen: only what _st_cm_gate runs)
#      _ad_from_cmdfn            the screen's own typed commands:  "$cmdfn --cc"  prints  key|description|prio|shown  lines
#      _ad_from_footer_items …   the "key:Label" items of a footer call (what _mc_footer was handed)
# ============================================================

_AD_BUDGET=50
_AD_COST_CC=0
_AD_COST_FOOTER=10
_AD_FREE_KEYS=" u q rf h cc "         # standard keys: printed on every menu, cost nothing

declare -g  _AD_MENU=""
declare -ga _AD_KEY=() _AD_DESC=() _AD_PRIO=() _AD_SHOWN=() _AD_ISFREE=() _AD_SHORT=()
declare -gA _AD_AT=()                   # key -> index in the arrays (a key is declared once)

# ── THE DISPATCHER'S ACCEPTOR ─────────────────────────────────
# A menu tells the dispatcher, once, what it accepts — the dispatcher notes it, cc lists it, the footer is told what to show:
#
#   _dp_accept MENU KEY HANDLER "description" [FOOT_PRIO] [SHOWN] [WHEN_FN]
#        MENU     the menu's map name (fx, api, settings ...)          KEY      what is typed ("clr", "r-")
#        HANDLER  the function that runs it ("-" = the menu's own loop handles it)
#        FOOT_PRIO  0 = cc only · >0 = "please show this in the footer" (the budget decides how many fit)
#        WHEN_FN  a function that says whether the menu takes it RIGHT NOW (a tab, a mode); omitted = always
#   _dp_when   MENU WHEN_FN KEY…       the keys of a map-wired menu that exist only while WHEN_FN is true  (fx: the UDF tab)
#   _dp_accepts MENU KEY               the one judge: declared (and its WHEN_FN is true)?      _dp_run MENU KEY [args…] runs its handler
#
# Everything a menu declares reaches cc and the footer through _ad_open/_ad_accept (below) — nobody looks anything up.
declare -gA _DP_HANDLER=() _DP_DESC=() _DP_FOOT=() _DP_SHOWN=() _DP_WHENFN=()      # key "menu|key"
declare -gA _DP_KEYS=()                                                              # menu -> " key key …"
_dp_accept() {
  local m="$1" k="${2,,}" h="${3:--}" d="${4:-}" fp="${5:-0}" sh="${6:-}" w="${7:-}"
  _DP_HANDLER["$m|$k"]="$h"; _DP_DESC["$m|$k"]="$d"; _DP_FOOT["$m|$k"]="$fp"; _DP_SHOWN["$m|$k"]="${sh:-$2}"; [ -n "$w" ] && _DP_WHENFN["$m|$k"]="$w"
  case "${_DP_KEYS[$m]-} " in *" $k "*) ;; *) _DP_KEYS[$m]="${_DP_KEYS[$m]-} $k" ;; esac
}
_dp_when() { local m="$1" fn="$2" k; shift 2; for k in "$@"; do _DP_WHENFN["$m|${k,,}"]="$fn"; done; }
_dp_now() {   # MENU KEY -> 0 when the menu takes KEY right now
  local w="${_DP_WHENFN[$1|${2,,}]-}"
  [ -z "$w" ] || "$w" 2>/dev/null
}
_dp_accepts() { local m="$1" k="${2,,}"; [ -n "${_DP_HANDLER[$m|$k]+x}" ] && _dp_now "$m" "$k"; }
_dp_run() { local m="$1" k="${2,,}"; shift 2; _dp_accepts "$m" "$k" || return 1; local h="${_DP_HANDLER[$m|$k]}"; [ "$h" = - ] && return 2; "$h" "$@"; }
# the menu's own declarations -> the registry (cc + footer)
_ad_from_dispatcher() {
  local m="${1:-}" k
  for k in ${_DP_KEYS[$m]-}; do
    _dp_now "$m" "$k" || continue
    _ad_accept "$k" "${_DP_DESC[$m|$k]}" "${_DP_FOOT[$m|$k]}" "${_DP_SHOWN[$m|$k]}"
  done
}

_ad_open() {
  _AD_MENU="${1:-}"
  _AD_KEY=(); _AD_DESC=(); _AD_PRIO=(); _AD_SHOWN=(); _AD_ISFREE=(); _AD_SHORT=(); _AD_AT=()
}

# _ad_accept KEY DESC [PRIO] [SHOWN] [FREE] [SHORT]   SHORT = the few words the footer prints (default: DESC up to its first "  (")
#   (a second declaration of a key keeps the first text, takes the higher priority)
_ad_accept() {
  local k="${1,,}" d="${2:-}" p="${3:-0}" s="${4:-}" f="${5:-0}" sh="${6:-}" i
  [ -n "$k" ] || return 0
  [ -n "$_AD_MENU" ] && ! _dp_now "$_AD_MENU" "$k" && return 0        # the menu does not take it right now (_dp_when)
  [ -n "$s" ] || s="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  if [ -n "${_AD_AT[$k]+x}" ]; then
    i="${_AD_AT[$k]}"
    (( p > _AD_PRIO[i] )) && { _AD_PRIO[i]=$p; _AD_SHOWN[i]="$s"; }
    [ "$f" = 1 ] && _AD_ISFREE[i]=1
    [ -z "${_AD_DESC[i]}" ] && _AD_DESC[i]="$d"
    return 0
  fi
  _AD_AT[$k]=${#_AD_KEY[@]}
  _AD_KEY+=("$k"); _AD_DESC+=("$d"); _AD_PRIO+=("$p"); _AD_SHOWN+=("$s"); _AD_ISFREE+=("$f"); _AD_SHORT+=("$sh")
}
_ad_free() { _ad_accept "$1" "$2" 0 "${3:-$1}" 1 "${4:-}"; }

# a footer item "r-N" / "d-N" is the typed key "r-" / "d-"; "N", "1,3-5", "Enter" are not commands
_ad_typed_of() {   # shown -> _AD_T (empty = not a command)
  local s="$1"
  _AD_T=""
  case "$s" in
    N|Enter|*[0-9,]*) [[ "$s" =~ ^[a-z]+-[0-9]+$ ]] && { _AD_T="${s%%[0-9]*}"; return 0; }; return 0 ;;
  esac
  [[ "$s" =~ ^(.+-)N$ ]] && { _AD_T="${BASH_REMATCH[1]}"; return 0; }
  _AD_T="$s"
}


# the commands a map wires and the menu takes.   $2 = st: a list screen (_st_run) — it runs the main nav / util words (_st_cm_gate), not the act keys
# (worked out once per map and kept: a footer is drawn on every redraw)
declare -gA _AD_MAPMEMO=()
# lite (the footer): it buys only commands with a priority > 0, and those are the menu's OWN commands (a word inherited from main has priority 0),
#   so the main menu needs no lookup at all and the other menus skip the inherited words.  cc asks without lite and still gets every command.
# _ad_map_memo works the list out and keeps it in _AD_MAPMEMO.  The footer runs inside $( ) / mapfile < <( ), where a kept list is lost the moment the
#   subshell ends — so the drawing code calls _ad_map_warm in the PARENT shell first and every footer draw after that only reads the list.
_ad_map_memo() {
  local m="${1:-main}" st="${2:-}" mode="${3:-menu}" lite="${4:-}" i key tgt p rec k d memo_key="$1|${2:-}|${3:-menu}|${4:-}|${#_CM_DEF[@]}"   # the number of loaded command definitions is part of the key: a list worked out before they were all loaded is never reused
  _AD_MEMOKEY="$memo_key"
  [ -n "$lite" ] && [ "$m" = main ] && { _AD_MAPMEMO[$memo_key]=""; return 0; }
  if [ -z "${_AD_MAPMEMO[$memo_key]+x}" ]; then
    [ "${_CM_BOOTED:-0}" = 1 ] || _cm_boot
    local sv_tbl="$_CM_TBL_MAP" sv_map="${_CM_MAP:-}" memo=""
    _cm_table_build "$m"
    local -a tk=("${_ct_key[@]}") tt=("${_ct_tgt[@]}") tm=("${_ct_map[@]}")
    _CM_MAP="$m"
    for (( i=0; i<${#tk[@]}; i++ )); do
      key="${tk[i]}"; tgt="${tt[i]}"
      [ "$tgt" = BLOCK ] && continue
      [ -n "$lite" ] && [ "${tm[i]}" = main ] && continue
      _cm_resolve "$mode" "$key"
      case "$_CM_ACT" in
        run) ;;
        local|back) [ "$st" = st ] && continue ;;
        *) continue ;;
      esac
      p=0; [ "${tm[i]}" != main ] && [ "$_CM_ACT" = local ] && p=40      # a command of the menu itself outranks the inherited main words
      memo+="${key}"$'\x1f'"${p}"$'\x1f'"${_CM_DESC}${_CM_EX:+  (e.g. $_CM_EX)}"$'\n'
    done
    _CM_MAP="$sv_map"; _CM_TBL_MAP=""
    [ -n "$sv_tbl" ] && _cm_table_build "$sv_tbl"
    _AD_MAPMEMO[$memo_key]="$memo"
  fi
}
_ad_map_warm() {                      # the PARENT shell, before a footer is drawn in a subshell: work the list out here so it is kept
  declare -F _ad_menu_now >/dev/null 2>&1 || return 0
  local sv="$_AD_MENU"; _ad_menu_now; _ad_map_memo "${_AD_MENU:-main}" "" menu lite; _AD_MENU="$sv"
}
_ad_from_map() {
  local k p d memo_key
  _ad_map_memo "$@"; memo_key="$_AD_MEMOKEY"
  while IFS=$'\x1f' read -r k p d; do
    [ -n "$k" ] || continue
    [ -n "${_AD_AT[$k]+x}" ] && continue
    _ad_accept "$k" "$d" "$p"
  done <<< "${_AD_MAPMEMO[$memo_key]}"
  return 0
}

# the map of the menu that is drawing right now (what _cm_ctx_find would tell a gate), declared without disturbing the gates' own state
_ad_menu_now() {                      # → _AD_MENU = the map of the menu that is drawing (no state of the gates is disturbed)
  declare -F _cm_on >/dev/null 2>&1 && _cm_on || return 0
  local sm="${_CM_MAP:-}" sd="${_CM_MDEPTH:-0}" sf="${_CM_FLOW:-0}"
  _cm_ctx_find; _AD_MENU="$_CM_MAP"
  _CM_MAP="$sm"; _CM_MDEPTH="$sd"; _CM_FLOW="$sf"
}

# the screen's own typed commands: "$1 --cc" prints  key|description|prio|shown  (prio and shown optional) and returns 1 (nothing runs)
_ad_from_cmdfn() {
  local fn="${1:-}" l k d p s sh
  [ -n "$fn" ] && declare -F "$fn" >/dev/null 2>&1 || return 0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    IFS='|' read -r k d p s sh <<< "$l"
    [ -n "$p" ] || p=50
    _ad_accept "$k" "$d" "$p" "$s" 0 "$sh"
  done < <("$fn" --cc 2>/dev/null)
}

# the "key:Label" items of a footer call (a footer declares what its menu takes)
_ad_from_footer_items() {
  local it shown lab k
  for it in "$@"; do
    [ "$it" = "|" ] && continue
    [[ "$it" == "#"* ]] && continue
    if [[ "$it" == *:* ]]; then shown="${it%%:*}"; lab="${it#*:}"; lab="${lab//_/ }"
    elif [ -n "${_MC_KEYLABEL[$it]-}" ]; then { [[ "$it" == .* ]] && shown="$it" || shown="${it%%.*}"; }; lab="${_MC_KEYLABEL[$it]}"
    else shown="$it"; lab="$it"; fi
    _ad_typed_of "$shown"; k="$_AD_T"
    [ -n "$k" ] || continue
    case "$_AD_FREE_KEYS" in *" ${k,,} "*) _ad_accept "$k" "$lab" 0 "$shown" 1 ;; *) _ad_accept "$k" "$lab" 30 "$shown" ;; esac
  done
}

# ── the two advertisers ───────────────────────────────────────
# cc: every declared command.  → _AD_CC_KEY / _AD_CC_DESC  (nothing else: no lookup)
_ad_cc_rows() {
  _AD_CC_KEY=(); _AD_CC_DESC=()
  local i
  for (( i=0; i<${#_AD_KEY[@]}; i++ )); do _AD_CC_KEY+=("${_AD_KEY[i]}"); _AD_CC_DESC+=("${_AD_DESC[i]}"); done
}

# footer: the free keys, then the paid commands the budget buys, highest priority first.  → _AD_FT_FREE / _AD_FT_PAID  (arrays of "shown) desc")
#   a second call is a pure function of the registry: the same budget, the same cells
_ad_footer_cells() {
  _AD_FT_FREE=(); _AD_FT_PAID=(); _AD_SPENT=0
  local i j best bp spent=0
  local -a done_=()
  for (( i=0; i<${#_AD_KEY[@]}; i++ )); do
    [ "${_AD_ISFREE[i]}" = 1 ] && _AD_FT_FREE+=("${_AD_SHOWN[i]}) ${_AD_SHORT[i]:-${_AD_DESC[i]%%  (*}}")
  done
  while (( spent + _AD_COST_FOOTER <= _AD_BUDGET )); do
    best=-1; bp=0
    for (( j=0; j<${#_AD_KEY[@]}; j++ )); do
      [ "${_AD_ISFREE[j]}" = 1 ] && continue
      [[ " ${done_[*]} " == *" $j "* ]] && continue
      (( _AD_PRIO[j] > bp )) && { best=$j; bp=${_AD_PRIO[j]}; }
    done
    (( best < 0 )) && break
    done_+=("$best"); spent=$(( spent + _AD_COST_FOOTER ))
    _AD_FT_PAID+=("${_AD_SHOWN[best]}) ${_AD_SHORT[best]:-${_AD_DESC[best]%%  (*}}")
  done
  _AD_SPENT=$spent
}

# the footer budget gate of a footer call that prints its items itself (_mc_footer): which key items may print?
#   _ad_footer_allow SHOWN → 0 = print it, 1 = the budget is spent (it stays in cc)
_AD_FT_SPENT=0
_ad_footer_reset() { _AD_FT_SPENT=0; }
_ad_footer_allow() {
  local s="$1" k
  [[ "$s" == .* ]] || s="${s%%.*}"
  _ad_typed_of "$s"; k="$_AD_T"
  [ -n "$k" ] || return 0                                  # N · 1,3-5 · Enter: an instruction, not a command
  case "$_AD_FREE_KEYS" in *" ${k,,} "*) return 0 ;; esac  # standard keys cost nothing
  (( _AD_FT_SPENT + _AD_COST_FOOTER > _AD_BUDGET )) && return 1
  _AD_FT_SPENT=$(( _AD_FT_SPENT + _AD_COST_FOOTER ))
  return 0
}
