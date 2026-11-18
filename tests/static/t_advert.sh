#!/usr/bin/env bash
# ADVERT registry unit test (ported from cc_footer_truth.sh): the registry, the budget, the two advertisers.  No terminal.  Silent unless something fails.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib/load.sh"; bvk_load cc || exit $?
fail=0; n=0; ok(){ n=$((n+1)); }; bad(){ echo "  NEW  advert:$1"; fail=$((fail+1)); }
has(){ local k; for k in "${_AD_CC_KEY[@]}"; do [ "$k" = "$1" ] && return 0; done; return 1; }
infooter(){ local c; for c in "${_AD_FT_FREE[@]}" "${_AD_FT_PAID[@]}"; do [[ "$c" == "$1) "* ]] && return 0; done; return 1; }
_ad_open t; _ad_free u Back; _ad_free q Close
for i in 1 2 3 4 5 6 7; do _ad_accept "k$i" "command $i" $(( 100 - i )); done
_ad_accept zero "cc only" 0
_ad_cc_rows; _ad_footer_cells
[ "${#_AD_CC_KEY[@]}" = 10 ] && ok || bad "cc-count: lists ${#_AD_CC_KEY[@]}, not 10"
[ "${#_AD_FT_PAID[@]}" = 5 ] && [ "$_AD_SPENT" = 50 ] && ok || bad "budget: footer paid ${#_AD_FT_PAID[@]} spent $_AD_SPENT (want 5 / 50)"
infooter k1 && infooter k5 && ! infooter k6 && ok || bad "priority: footer must take k1..k5, not k6"
infooter u && infooter q && ok || bad "free-keys: u q must be in the footer on top of the paid ones"
for k in k6 k7 zero; do has $k && ok || bad "cc-missing:$k is not in cc"; done
for c in "${_AD_FT_FREE[@]}" "${_AD_FT_PAID[@]}"; do k="${c%%) *}"; has "$k" && ok || bad "footer-subset:$k shown in the footer, not in cc"; done
_ad_open s; _ad_from_map settings st; _ad_cc_rows
for k in h s i -h -auth disk ram health lang; do has "$k" && ok || bad "settings-declares:$k is wired in the settings map but not declared"; done
for k in fx sw cd up- z c d; do has "$k" && bad "settings-blocked:$k is declared although the map blocks it" || ok; done
_ad_open f; _ad_from_footer_items "N:Open" "r-N:Restore here" "n:New" "1,3-5:Pick" "u.up" "z"; _ad_cc_rows
has r- && has n && has u && has z && ! has N && ! has '1,3-5' && ok || bad "footer-items: r- n u z are commands; N and 1,3-5 are not"
echo "advert: $n checks, $fail new"; [ "$fail" = 0 ]
