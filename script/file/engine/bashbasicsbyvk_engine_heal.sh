#!/usr/bin/env bash
# _bvk_engine_heal — start-up check: does this install carry the engines of THIS machine?
# A pip install ships only the bvk-ls / bvk-fr / bvk-xfer binaries of the CPU and OS it was built on (setup.py).  When the
# install is later carried to another machine (a copied home folder or prefix, a restored Termux backup, a docker image run
# on another CPU) those binaries do not fit.  Then:  say so, offer to reinstall, build fresh for this machine, restart.
#   BVK_NO_HEAL=1 turns the check off.   It asks once a day at most per machine type, never without a terminal, never twice in a row.
# Needs _bvk_engine_target (engine_target.sh) and _bvk_yn (choose.sh, loaded before the app calls this).
_bvk_engine_heal() {
  [ "${BVK_NO_HEAL:-0}" = 1 ] && return 0
  [ "${BVK_HEALED:-0}" = 1 ] && return 0                       # we just reinstalled and restarted: never loop
  [ -t 0 ] && [ -t 1 ] || return 0                             # no terminal: nobody to ask
  local _o _d _bin _e _f _t _have="" _want _ts _eh_ans _core _mark _now _last
  _bvk_engine_target
  [ -n "$_bet_m" ] || return 0                                 # a CPU / OS with no prebuilt engine: nothing to fetch
  _o="$(command -v o 2>/dev/null)"; _d="${_o%/*}"
  _bin="$_d/../bashbasicsbyvk/bin"
  [ -d "$_bin" ] || return 0                                   # run from a source checkout, not a pip install
  _want="$_bet_os-$_bet_m"
  for _e in ls fr xfer; do [ -f "$_bin/bvk-$_e-$_want" ] || _have=missing; done
  [ -z "$_have" ] && return 0                                  # all three engines of this machine are there
  # which machine was this install made for?  (names the engines found, e.g. bvk-ls-linux-amd64 -> linux-amd64)
  for _f in "$_bin"/bvk-*-*-*; do
    [ -e "$_f" ] || continue
    _t="${_f##*/}"; _t="${_t#bvk-}"; _t="${_t#*-}"
    case " $_ts " in *" $_t "*) ;; *) _ts="${_ts:+$_ts }$_t" ;; esac
  done
  _mark="${CONFIG_DIR:-$HOME/.config/bashbasicsbyvk}/engine_heal_asked"
  _now="$(date +%s 2>/dev/null)"
  if [ -f "$_mark" ]; then
    read -r _t _last < "$_mark" 2>/dev/null
    [ "$_t" = "$_want" ] && [ -n "$_last" ] && [ -n "$_now" ] && [ $((_now - _last)) -lt 86400 ] && return 0
  fi
  echo
  echo "⚠️  This install was made for ${_ts:-another machine}, but this machine is $_want."
  echo "   The fast engines (list, find & replace, file transfer) need the $_want build; until then the app uses its slower fallbacks."
  _eh_ans=""
  _bvk_yn _eh_ans "Reinstall bashbasicsbyvk for this machine now?" -t "Engines" -i "🔧" || _eh_ans=n
  mkdir -p "${_mark%/*}" 2>/dev/null; printf '%s %s\n' "$_want" "${_now:-0}" > "$_mark" 2>/dev/null
  [ "$_eh_ans" = y ] || { echo "   Skipped. Reinstall any time with  -u  (or: pip install --force-reinstall --no-cache-dir git+https://github.com/vkdatta/bashbasicsbyvk.git)"; return 0; }
  _core="$(command -v bashbasicsbyvk_upgrade_install 2>/dev/null)"
  if [ -z "$_core" ]; then echo "❌ bashbasicsbyvk_upgrade_install not found; use  -u"; return 0; fi
  if BVK_REINSTALL_FRESH=1 bash "$_core"; then
    echo "✅ Reinstalled for $_want. Restarting..."
    rm -f "$_mark" 2>/dev/null
    export BVK_HEALED=1
    exec "$_o" "$@"
  fi
  echo "❌ The reinstall did not finish. The app keeps running on its fallbacks; run  health  for details."
  return 0
}
