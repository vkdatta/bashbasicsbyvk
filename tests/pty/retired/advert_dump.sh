#!/usr/bin/env bash
# One process, no terminal: what every menu DECLARES (what its cc lists).   → lines:  map<TAB>key<TAB>prio<TAB>how
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; F="$ROOT/script/file"; SCRIPT_DIR="$F"
for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
source "$F/engine/commands/bashbasicsbyvk_cmdmap.sh" 2>/dev/null; for f in "$F"/cmdmap/*/*commands.sh; do source "$f" 2>/dev/null; done; _cm_boot 2>/dev/null
declare -gA _MC_KEYLABEL=(); source "$F/engine/commands/bashbasicsbyvk_advert.sh"
while IFS='|' read -r m fn kind back; do
  m="${m// /}"; case "$m" in ''|\#*) continue ;; esac
  kind="${kind// /}"; mode=menu; [ "$kind" = prompt ] && mode=text
  _ad_open "$m"; _ad_from_map "$m" "" "$mode"; _ad_cc_rows
  _CM_MAP="$m"
  for i in "${!_AD_CC_KEY[@]}"; do _cm_resolve "$mode" "${_AD_CC_KEY[i]}" 2>/dev/null; printf '%s\t%s\t%s\t%s\t%s\n' "$m" "${_AD_CC_KEY[i]}" "${_AD_PRIO[i]}" "${_AD_ISFREE[i]}" "${_CM_HANDLER:--}"; done
done < "$F/cmdmap/bashbasicsbyvk_menus.list"
