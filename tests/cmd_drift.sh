#!/usr/bin/env bash
# Drift between  cheat codes (cc) · command map · real commands · menu footers · live suggestion.   bash tests/cmd_drift.sh
# (1) text prompts: u is always "go back"; a menu's own key means the main command (or plain text) inside a question
# (2) a prompt's own keys ([c] continue · c) copy link · [Y/n, c = cancel]) beat the map
# (3) the live suggestion ("could become: ...") never offers a key that Enter would reject — every map, both prompt kinds
# (4) switch: footer / cmdmap / loop agree — b, b-N and x all REMOVE; b-N is never a staging command there
# (5) the backup flow stops the moment a prompt is cancelled (no packing, no upload, no delete)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$ROOT/script/file"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

SCRIPT_DIR="$F"
for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
source "$F/engine/bashbasicsbyvk_cmdmap.sh"
for f in "$F"/cmdmap/*/*commands.sh; do source "$f"; done
_cm_boot

act() { _cm_table_build "$1"; _CM_MAP="$1"; _cm_resolve "$2" "$3"; echo "$_CM_ACT"; }

# ---- (1) -------------------------------------------------------------------------------
for m in main switch fx api home find upgrade; do
  [ "$(act $m text u)" = back ] && ok "$m: u inside a question = go back" || bad "$m: u inside a question must be 'back', got $(act $m text u)"
done
[ "$(act switch text s)" = run ]   && ok "switch: s inside a question opens Settings (guide rule)" || bad "switch: s in a question = $(act switch text s)"
[ "$(act switch text c)" = block ] && ok "switch: c inside a question is blocked like in main" || bad "switch: c in a question = $(act switch text c)"
[ "$(act switch text xe)" = none ] && ok "switch: its own xe (no main twin) is plain text inside a question" || bad "switch: xe in a question = $(act switch text xe)"
[ "$(act switch menu b-1)" = local ] && ok "switch list prompt: b-1 is the menu's own command" || bad "switch list: b-1 = $(act switch menu b-1)"
[ "$(act switch menu b)" = local ]   && ok "switch list prompt: b is wired (footer says b) Remove)" || bad "switch list: b = $(act switch menu b)"

# ---- (2) -------------------------------------------------------------------------------
p_cost="   [c] continue  ·  [r] reduce time  ·  [i] increase time  ·  [s] stop: "
p_link="   c) copy link   g) regenerate link   e) edit expiry   a) alias/rename   x) nuke   Enter) back: "
p_ask="Back up 2 item(s) to the cloud before deleting? [Y/n, c = cancel the delete]: "
p_name="Name this backup (Enter = just the date and time): "
_CM_MAP=main; _cm_table_build main
for k in c r i s; do _cm_prompt_collect "$p_cost"; _cm_gate_text "$k" ""; [ $? = 0 ] && [ "$_CM_ABORT" = 0 ] && ok "cost prompt: [$k] is the prompt's own key" || { bad "cost prompt: $k aborted the flow"; _cm_abort_clear; }; done
for k in c g e a x; do _cm_prompt_collect "$p_link"; _cm_gate_text "$k" ""; [ $? = 0 ] && [ "$_CM_ABORT" = 0 ] && ok "link prompt: $k) is the prompt's own key" || { bad "link prompt: $k aborted the flow"; _cm_abort_clear; }; done
_cm_prompt_has_choices "$p_ask" && ok "[Y/n, c = cancel the delete] is a prompt that lists its own answers" || bad "[Y/n, c = ...] not recognised"
_cm_prompt_collect "$p_name"; [ "${#_CM_LOCAL[@]}" = 0 ] && ok "a plain name prompt has no own keys" || bad "name prompt: own keys ${!_CM_LOCAL[*]}"
_cm_prompt_collect "$p_link"; _cm_hint c text; case "$_hint_want" in "c  →  copy link"*) ok "link prompt: hint for c says copy link";; *) bad "link hint: $_hint_want";; esac
_cm_prompt_collect "$p_name"; _cm_gate_text u ""; [ $? = 4 ] && [ "$_CM_ABORT" = 1 ] && [[ "$_CM_ABORT_MSG" == *Back* ]] && ok "name prompt: u cancels the flow with 'Back' (not 'Invalid command')" || bad "name prompt u: $_CM_ABORT_MSG"
_cm_abort_clear; _CM_LOCAL=()

# ---- (3) -------------------------------------------------------------------------------
nbad=0; ncheck=0
for m in "${_CM_MAP_NAMES[@]}"; do
  for md in menu text; do
    _CM_MAP="$m"; _CM_TBL_MAP=""; _cm_table_build "$m"
    for k in "${_ct_key[@]}"; do
      [ "${#k}" -ge 2 ] || continue
      for l in 1 2 3; do
        [ "$l" -lt "${#k}" ] || continue
        pre="${k:0:l}"; _cm_hint "$pre" "$md"; ncheck=$((ncheck+1))
        h="$_hint_want"; list=""
        case "$h" in *"could become: "*) list="${h#*could become: }" ;; *"(also: "*) list="${h#*(also: }"; list="${list%)*}" ;; esac
        [ -z "$list" ] && continue
        for c in ${list//,/ }; do
          _cm_resolve "$md" "$c"
          case "$_CM_ACT" in run|local|back) ;; *) bad "$m/$md: typing '$pre' suggests '$c' but Enter rejects it ($_CM_ACT)"; nbad=$((nbad+1)) ;; esac
        done
      done
    done
  done
done
[ "$nbad" = 0 ] && ok "no suggestion offers a rejected key ($ncheck prefixes over ${#_CM_MAP_NAMES[@]} maps, menu + text)" 

# ---- (4) -------------------------------------------------------------------------------
SW="$F/loops/iloop/switch/bashbasicsbyvk_switch.sh"
grep -qE '^\s+b\|b-\*\|x\)' "$SW" && ok "switch loop: b | b-* | x is one remove case" || bad "switch loop lost its remove case"
grep -qE '^\s+c-\*\|m-\*\|s-\*\|b-\*\)' "$SW" && bad "switch loop: b-* is staging BOOKMARK again (must remove)" || ok "switch loop: b-* is not a staging command"
grep -q 'r<N>' "$SW" && bad "switch footer advertises r<N>, which the loop does not handle (it is e-N)" || ok "switch footer: no r<N>"
grep -q '"rn:' "$SW" && bad "favourites footer advertises rn, the loop handles r" || ok "favourites footer: r (not rn)"
# run the real remove with a fake bookmark list
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
eval "$(sed -n '/^_sw_remove_paths()/,/^}/p' "$SW")"
eval "$(sed -n '/^_sp_resolve_itemlist()/,/^}/p' "$F/staging/buffer!/bashbasicsbyvk_staging_helpers.sh")"
parse_selection() { local spec="$1" max="$2" p a b i; for p in ${spec//,/ }; do if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then for ((i=BASH_REMATCH[1]; i<=BASH_REMATCH[2]; i++)); do [ "$i" -le "$max" ] && echo "$i"; done; elif [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -le "$max" ]; then echo "$p"; fi; done; }
_carry_forget() { :; }; read() { builtin printf -v "${@: -1}" '%s' "$ANS"; }
_bvk_yn() { builtin printf -v "$1" '%s' "$ANS"; }       # the yes/no menu answers with $ANS here
touch "$T/a.swlink" "$T/b.swlink" "$T/c.swlink"; mkdir "$T/target"
items=("$T/a.swlink" "$T/b.swlink" "$T/c.swlink"); imaginary_mode=false
ANS=y; _sw_remove_paths "b-2" >/dev/null
{ [ ! -e "$T/b.swlink" ] && [ -e "$T/a.swlink" ] && [ -e "$T/c.swlink" ] && [ -d "$T/target" ]; } && ok "b-2 removed exactly bookmark 2 (nothing buffered, nothing else touched)" || bad "b-2 did not remove exactly item 2"
ANS=n; _sw_remove_paths "b-1" >/dev/null; [ -e "$T/a.swlink" ] && ok "b-1 answered n: nothing removed" || bad "b-1 removed without a yes"
ANS=y; _sw_remove_paths "b-1,3" >/dev/null; { [ ! -e "$T/a.swlink" ] && [ ! -e "$T/c.swlink" ]; } && ok "b-1,3 removes both" || bad "b-1,3 failed"

# ---- (5) -------------------------------------------------------------------------------
BK="$F/staging/!buffer/fileapi/3 backup/bashbasicsbyvk_staging_backup.sh"
n=$(grep -c 'read -e -r -p "Name this backup' "$BK"); m=$(grep 'read -e -r -p "Name this backup' "$BK" | grep -c '|| return 1')
[ "$n" = "$m" ] && [ "$n" -ge 1 ] && ok "backup: every 'Name this backup' prompt returns when cancelled" || bad "backup: a name prompt ignores a cancel ($m of $n)"
grep -A2 'Name this backup' "$BK" | grep -q '_CM_ABORT' && ok "backup: checks _CM_ABORT after the name prompt" || bad "backup: no _CM_ABORT check"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
