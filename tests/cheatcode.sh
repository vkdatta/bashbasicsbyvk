#!/usr/bin/env bash
# cc (cheat codes).     bash tests/cheatcode.sh
# (1) the list: what cc offers is exactly what the command map would accept in that prompt
# (2) the prompt side: a pick is typed in, never run; a pick nobody took does not leak
# (3) end to end inside tmux when tmux is installed: main prompt, filter, c- then numbers,
#     Settings screen, item picker, text prompt, cancel
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$ROOT/script/file"
T="$(mktemp -d)"; trap 'tmux kill-session -t bvkcc 2>/dev/null; rm -rf "$T"' EXIT
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
has() { grep -qF -- "$2" <<<"$1"; }
keys() { local i; for i in "${!_CC_KEY[@]}"; do printf '%s\n' "${_CC_KEY[i]}"; done; }
inlist() { keys | grep -qxF -- "$1"; }

# ---- (1) the list ----------------------------------------------------------------------
SCRIPT_DIR="$F"
# the installed app has every map / commands file flat on PATH; here they sit in per-menu folders
for d in "$F"/cmdmap/*/; do PATH="$PATH:${d%/}"; done
source "$F/engine/bashbasicsbyvk_cmdmap.sh"
source "$F/engine/bashbasicsbyvk_cheatcode.sh"
for f in "$F"/cmdmap/*/*commands.sh; do source "$f"; done
_cm_boot

_CM_MAP=main; _CM_RUN_MODE=menu; _cc_collect
for k in c- m- = loadtime print cc s h q d; do
  inlist "$k" && ok "main menu lists $k" || bad "main menu should list $k"
done
[ "$(keys | sort | uniq -d | wc -l)" = 0 ] && ok "no command is listed twice" || bad "duplicates"

_CM_MAP=main; _CM_RUN_MODE=text; _cc_collect
for k in loadtime print cc s h q; do inlist "$k" && ok "a prompt inside a flow lists $k" || bad "text prompt should list $k"; done
for k in c- m- = d z; do inlist "$k" && bad "a prompt inside a flow must NOT list $k (it would answer Invalid command)" || ok "a prompt inside a flow hides $k"; done

# every listed key really is accepted by the resolver (no "❌ Invalid command" can come out of cc)
for mp in main upgrade switch fx rules api home settings find; do
  for md in menu text; do
    _CM_MAP="$mp"; _CM_RUN_MODE="$md"; _cc_collect; _cm_table_build "$mp"
    badk=""
    for k in "${_CC_KEY[@]}"; do
      _cm_resolve "$md" "$k"
      case "$_CM_ACT" in run|local|back) ;; *) badk+=" $k" ;; esac
    done
    [ -z "$badk" ] && ok "$mp/$md: all ${#_CC_KEY[@]} listed keys are accepted" || bad "$mp/$md: not accepted:$badk"
  done
done

_CM_MAP=upgrade; _CM_RUN_MODE=menu; _cc_collect
_cm_table_build upgrade; own="$(for i in "${!_ct_key[@]}"; do [ "${_ct_tgt[i]%%:*}" = bashbasicsbyvk_upgrademenucommands.sh ] && echo "${_ct_key[i]}"; done | head -1)"
[ -z "$own" ] || { inlist "$own" && ok "a menu's own command ($own) is listed" || bad "own command $own missing"; }

_CC_CTX=st; _cc_collect; _CC_CTX=""
[ "$(keys | paste -sd' ')" = "u q = print loadtime" ] && ok "Settings / Home screens list their own grammar" || { bad "settings list"; keys | paste -sd' '; }

# ---- (2) the prompt side ---------------------------------------------------------------
_CC_PREFILL="loadtime"; _cc_take; [ "$_CC_TAKEN" = loadtime ] && [ -z "$_CC_PREFILL" ] && ok "a pick is consumed once" || bad "take"
_cc_take && bad "second take must be empty" || ok "second take is empty"
_CC_PREFILL="stale"; choice="x"; _cm_gate_choice >/dev/null 2>&1; [ -z "$_CC_PREFILL" ] && ok "a gate drops a pick nobody took" || bad "stale pick leaked"
got=""; kf() { got+="[$1]"; }; bf() { got+="<$1>"; }
_CC_PREFILL="c-"; _cc_replay kf bf; [ "$got" = "<c->" ] && ok "plain text goes in as one piece" || bad "bulk replay: $got"
got=""; _CC_PREFILL="=lo"; _cc_replay kf bf; [ "$got" = "[=][l][o]" ] && ok "= goes in key by key so the live filter starts" || bad "key replay: $got"

# ---- (3) tmux end to end ---------------------------------------------------------------
if ! command -v tmux >/dev/null 2>&1; then echo "  skip tmux not installed"; [ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"; exit "$fail"; fi
BIN="$T/bin"; mkdir -p "$BIN" "$T/home/.bashbasicsbyvk" "$T/play/docs"
find "$ROOT/script" -type f -not -path '*/bvk-ls/*' -not -name '*.pyc' -exec cp {} "$BIN"/ \;
chmod +x "$BIN"/*; touch "$T/play"/{a.txt,b.py,c.png,notes.md}
run() { tmux kill-session -t bvkcc 2>/dev/null
        tmux new-session -d -s bvkcc -x 110 -y 40 -c "$T/play" "env HOME=$T/home VK_TELEMETRY=0 PATH=$BIN:$PATH bash $BIN/o"; sleep 4; }
k() { tmux send-keys -t bvkcc "$@"; }
scr() { sleep "${1:-0.8}"; tmux capture-pane -t bvkcc -p; }
lastsel() { grep -a '^Select:\|Item numbers:\|Enter folder names' <<<"$1" | tail -1; }

run
s="$(scr 0.3)"; has "$s" "a.txt" && ok "e2e: app starts" || { bad "app did not start"; echo "$s"; }

k "cc" Enter; sleep 1.2; k "=lo" Enter; sleep 0.6; s="$(scr 0.3)"
has "$s" "Cheat codes" && has "$s" "1) loadtime" && ok "e2e: cc opens a list, =lo narrows it to loadtime" || { bad "cc list"; echo "$s"; }
k 1 Enter; s="$(scr 1.5)"
[ "$(lastsel "$s")" = "Select: loadtime" ] && ok "e2e: the pick sits in the prompt" || { bad "pick not in prompt"; lastsel "$s"; }
has "$s" "RECENT SCREEN CHANGES" && bad "e2e: loadtime ran before Enter" || ok "e2e: nothing ran before Enter"
k Enter; s="$(scr 1.5)"; has "$s" "RECENT SCREEN CHANGES" && ok "e2e: Enter runs it" || bad "Enter did not run loadtime"
k u Enter; sleep 1; k u Enter; sleep 1

k "cc" Enter; sleep 1.2; k "=c-" Enter; sleep 0.5; k 1 Enter; s="$(scr 1.2)"
[ "$(lastsel "$s")" = "Select: c-" ] && ok "e2e: c- waits for its numbers (running c- alone is invalid)" || { bad "c- pick"; lastsel "$s"; }
k "1-2"; s="$(scr 0.8)"; [ "$(lastsel "$s")" = "Select: c-1-2" ] && ok "e2e: finished as c-1-2" || { bad "c-1-2"; lastsel "$s"; }
k Enter; s="$(scr 1.5)"; has "$s" "Buffered 2 item(s)" && ok "e2e: Enter ran c-1-2" || { bad "c-1-2 did not run"; echo "$s" | tail -8; }

k "cc" Enter; sleep 1.2; k u Enter; s="$(scr 1)"
[ "$(lastsel "$s")" = "Select:" ] && ok "e2e: u cancels, prompt stays empty" || { bad "cancel"; lastsel "$s"; }

k "s" Enter; sleep 1.5; k "cc" Enter; sleep 1.2; s="$(scr 0.3)"
has "$s" "Cheat codes · this screen" && has "$s" "Close Settings" && ok "e2e: Settings screen lists its own commands" || { bad "settings cc"; echo "$s"; }
k 2 Enter; s="$(scr 1.2)"; [ "$(lastsel "$s")" = "Select: q" ] && ok "e2e: pick lands in the Settings prompt" || { bad "settings pick"; lastsel "$s"; }
k Enter; sleep 1

k "d" Enter; sleep 1.5; k "cc" Enter; sleep 1.2; s="$(scr 0.3)"
{ has "$s" "loadtime" && ! has "$s" ") c- "; } && ok "e2e: item picker lists only what it accepts" || { bad "picker list"; echo "$s" | tail -20; }
k u Enter; sleep 1; k "u" Enter; sleep 1

k "c" Enter; sleep 1.2; k 1 Enter; sleep 1.2; k "cc" Enter; sleep 1.2; k "=dis" Enter; sleep 0.5; k 1 Enter; s="$(scr 1.2)"
[ "$(lastsel "$s")" = "📂 Enter folder names (separated by ,): disk" ] && ok "e2e: a text prompt gets the pick too" || { bad "text prompt pick"; lastsel "$s"; }

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
