#!/usr/bin/env bash
# ADVERT unit test (fast, no terminal): the registry, the budget, the two advertisers.   bash tests/cc_footer_truth.sh
# The real-app score (types the words into a pty) is tests/advert_pty.py.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; F="$ROOT/script/file"; SCRIPT_DIR="$F"
for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
source "$F/engine/bashbasicsbyvk_cmdmap.sh"; for f in "$F"/cmdmap/*/*commands.sh; do source "$f"; done; _cm_boot
declare -gA _MC_KEYLABEL=([u.up]="Up" [z]="Cancel"); source "$F/engine/bashbasicsbyvk_advert.sh"
fail=0; ok(){ echo "  ok   $*"; }; bad(){ echo "  FAIL $*"; fail=1; }
has(){ local k; for k in "${_AD_CC_KEY[@]}"; do [ "$k" = "$1" ] && return 0; done; return 1; }
infooter(){ local c; for c in "${_AD_FT_FREE[@]}" "${_AD_FT_PAID[@]}"; do [[ "$c" == "$1) "* ]] && return 0; done; return 1; }

_ad_open t; _ad_free u Back; _ad_free q Close
for i in 1 2 3 4 5 6 7; do _ad_accept "k$i" "command $i" $(( 100 - i )); done
_ad_accept zero "cc only" 0
_ad_cc_rows; _ad_footer_cells
[ "${#_AD_CC_KEY[@]}" = 10 ] && ok "cc lists every declared command (cost 0): 10" || bad "cc lists ${#_AD_CC_KEY[@]}, not 10"
[ "${#_AD_FT_PAID[@]}" = 5 ] && [ "$_AD_SPENT" = 50 ] && ok "footer buys 5 paid commands, spends 50 of 50" || bad "footer paid ${#_AD_FT_PAID[@]} spent $_AD_SPENT"
infooter k1 && infooter k5 && ! infooter k6 && ok "footer takes the highest priorities (k1..k5), not k6" || bad "footer priority order"
infooter u && infooter q && ok "free keys u q are in the footer on top of the 5" || bad "free keys"
for k in k6 k7 zero; do has $k && ok "$k is in cc though not in the footer" || bad "$k missing from cc"; done
# every footer cell is a subset of cc
for c in "${_AD_FT_FREE[@]}" "${_AD_FT_PAID[@]}"; do k="${c%%) *}"; has "$k" || bad "footer shows $k, cc does not"; done; ok "footer ⊆ cc"
# _ad_from_map: a list screen declares what _st_cm_gate runs, nothing blocked
_ad_open s; _ad_from_map settings st; _ad_cc_rows
for k in h s i -h -auth disk ram health lang; do has "$k" && ok "settings map declares $k" || bad "settings map misses $k"; done
for k in fx sw cd up- z c d; do has "$k" && bad "settings map declares blocked $k" || ok "blocked $k not declared"; done
# typed-key rules of the footer items
_ad_open f; _ad_from_footer_items "N:Open" "r-N:Restore here" "n:New" "1,3-5:Pick" "u.up" "z"; _ad_cc_rows
has r- && has n && has u && has z && ! has N && ! has '1,3-5' && ok "footer items: r- n u z are commands, N and 1,3-5 are not" || bad "typed-key rules"
[ "$fail" = 0 ] && echo ALL OK || echo FAILED; exit "$fail"
