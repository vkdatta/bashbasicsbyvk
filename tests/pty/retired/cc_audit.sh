#!/usr/bin/env bash
# Exhaustive footer / cc / handled-commands audit.  Run from repo root.
set -u
ROOT="$(pwd)"; F="$ROOT/script/file"
SCRIPT_DIR="$F"
for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
source "$F/engine/commands/bashbasicsbyvk_cmdmap.sh" 2>/dev/null
for f in "$F"/cmdmap/*/*commands.sh; do source "$f" 2>/dev/null; done
_cm_boot 2>/dev/null
source "$F/engine/ui/bashbasicsbyvk_menuchrome.sh" 2>/dev/null

echo "=== PART 1: Settings/Home engine (_st_run) — what cc lists vs what the screen accepts ==="
# cc list for ctx=st is hard-coded in _cc_collect
CC_ST="u q = print loadtime"
echo "cc (st ctx) lists: $CC_ST"
for m in settings home pending; do
  _CM_TBL_MAP=""; _cm_table_build "$m"
  run=""
  for k in "${_ct_key[@]}"; do
    _cm_resolve menu "$k" 2>/dev/null
    case "$_CM_ACT" in run|local) run+="$k " ;; esac
  done
  echo "--- map '$m': typed words the screen RUNS (via _st_cm_gate) but cc (st) does not list:"
  for k in $run; do case " $CC_ST " in *" $k "*) ;; *) printf '   %s' "$k" ;; esac; done; echo
done

echo
echo "=== PART 2: footer keys printed by each screen vs the owning map (real _cm_resolve) ==="
# screen | map | footer keys   (N / 1,3-5 / a-N patterns are reduced to their typed prefix)
STD_BACK="u q h cc"; STD_UP="u q h cc"
SCREENS=(
"auth users|auth|c r ux ui = $STD_BACK"
"auth sub|auth_sub|= $STD_BACK"
"auth user|auth_user|ux ui = $STD_BACK"
"cloud surf people|xui_cs_pp|r- g t $STD_BACK"
"cloud surf|xui_cs|d- rf $STD_UP"
"notifications|xui_nf|r- rf $STD_BACK"
"rbam|xui_rb|r- $STD_BACK"
"github repos|xui_ghp|= rf $STD_BACK"
"cloudflare workers|xui_cfw|r rf e e- a- $STD_BACK"
"google drive profiles|xui_gdp|n rf $STD_BACK"
"api backup|api|r- c- a- e- x- rf u bk"
"api saved|api|r- a- e- x- rf u sv"
"api links|api|c- g- a- e- x- rf u api"
"transfer picker|transfer|v n c z $STD_UP"
"item selection (adf)|prompt|v c z $STD_BACK"
"buffer view (staging)|main|x n clr $STD_BACK"
"buffer view (staging)|prompt|x n clr $STD_BACK"
"browse main footer|main|u q h s -h -u cd"
"browse gdrive footer|main|u gd gdx rf q h s -h -u"
"rename pick|rename|u q"
"switch footer|switch|b b- x clr e- r"
"rules footer|rules|clr"
"snapshot|snapshot|u q"
"settings footer f1/f2|settings|u q clr ?"
)
for s in "${SCREENS[@]}"; do
  IFS='|' read -r name map keys <<<"$s"
  _CM_TBL_MAP=""; _cm_table_build "$map" 2>/dev/null; _CM_MAP="$map"
  bad=""
  for k in $keys; do
    _cm_resolve menu "$k" 2>/dev/null
    case "$_CM_ACT" in run|local|back) ;; *) bad+="$k($_CM_ACT) " ;; esac
  done
  [ -n "$bad" ] && printf '%-26s [%s]  NOT accepted by its own map: %s\n' "$name" "$map" "$bad"
done
