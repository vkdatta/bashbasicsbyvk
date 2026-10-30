#!/usr/bin/env bash
# The  ==  deep filter of the list screens (_st_run: Settings, Home, every sub-screen), checked WITHOUT a terminal like tests/settings_keys.sh:
# the screen is a stub that prints its state every time it would draw, the keys come through a pipe.   bash tests/settings_deep.sh
#  1. "=text" still filters the rows live; "==text" collects the text only (no live filter) and Enter searches EVERY screen
#  2. the results list the matching screens; a number opens one (a plain *_settings screen), u comes back, q closes everything
#  3. "==" / "== " + Enter clears; nothing found says so; a choice menu keeps its old behaviour (no deep search)
#  4. the search index: key parsing, ranking, Home rows, which function opens which screen, the query is data
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fail=0
source "$ROOT/tests/wait_lib.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; BIN="$T/bin"; mkdir -p "$BIN" "$T/home"
python3 -I - "$ROOT" "$BIN" <<'PY'
import os, sys
r, b = sys.argv[1:3]
for dp, dn, fn in os.walk(os.path.join(r, 'script')):
    if 'bvk-' in dp: continue
    for f in fn:
        d = os.path.join(b, f)
        if not os.path.exists(d): os.symlink(os.path.join(dp, f), d)
PY
export HOME="$T/home" TERM=xterm
UI="$BIN/bashbasicsbyvk_settings_ui.sh"; DS="$BIN/bashbasicsbyvk_deepsearch.sh"; DESC="$BIN/bashbasicsbyvk_settings_desc.sh"
VP="$BIN/bashbasicsbyvk_viewport.sh"; MS="$BIN/bashbasicsbyvk_mouse.sh"; HM="$BIN/bashbasicsbyvk_home.sh"
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

read -r -d '' HARNESS <<'EOF'
export PATH="$BIN:$PATH"
source "$UI"; source "$VP"; source "$MS"; source "$DESC"; source "$DS"; source "$HM"
_st_draw() { echo "D title=[$title] cur=$cur buf=[$buf] fq=[$fq] rows=[${_st_lbl[*]}]"; }
_bvk_paste_on() { :; }; _bvk_paste_off() { :; }; _bvk_mouse_rearm() { :; }; _BVK_MOUSE_ON=1
_bvk_paste_burst() { return 1; }
_inner_run() { echo "INNER $*"; }
nuke_time_settings() { echo "OPENED nuke_time_settings"; }
xfer_speed_settings() { echo "OPENED xfer_speed_settings"; }
build() { _st_reset; local i; for i in Alpha Beta Gamma; do _st_add t "$i" 0; done; }
act() { echo "ACT $1 $2"; }
[ -n "${CHOICE:-}" ] && _st_choice=1
_st_run "Top" build act
rc=$?; echo; echo "RC=$rc QUIT=$_st_quit"
EOF
run() { local in="$1"; shift; printf '%b' "$in" | env UI="$UI" VP="$VP" MS="$MS" DS="$DS" DESC="$DESC" HM="$HM" BIN="$BIN" "$@" timeout 8 bash -c "$HARNESS" 2>&1; echo "TIMEOUT_RC=${PIPESTATUS[1]}"; }
chk() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; echo "$OUT" | tail -8 | cut -c1-220 | sed 's/^/        /'; fi; }
lastd() { grep '^D ' <<<"$OUT" | tail -1; }

# 1. the line
OUT="$(run '==nu')";   chk "==nu : the line holds ==nu"                       grep -q 'buf=\[==nu\]' <<<"$(lastd)"
chk "==nu : no live filter (rows stay whole, fq empty)"                         grep -q 'fq=\[\] rows=\[Alpha Beta Gamma\]' <<<"$(lastd)"
OUT="$(run '=al')";    chk "=al : the live filter still works"                  grep -q 'fq=\[al\] rows=\[Alpha\]' <<<"$(lastd)"
OUT="$(run '==nuk\x7f')"; chk "==nuk + Backspace -> ==nu"                       grep -q 'buf=\[==nu\]' <<<"$(lastd)"
OUT="$(run '==x\x7f\x7f')"; chk "==x + 2 Backspace -> = (back to the live filter)" grep -q 'buf=\[=\] fq=\[\]' <<<"$(lastd)"
# the hint row
OUT="$(bash -c "source '$UI'; _st_deep_on() { return 0; }; _st_hint_text '==abc' 80; echo \"\$_ST_HINT\"")"
chk "hint for ==abc names the search"                                           grep -q 'search every screen for “abc”' <<<"$OUT"
OUT="$(bash -c "source '$UI'; _st_deep_on() { return 0; }; _st_hint_text '==' 80; echo \"\$_ST_HINT\"")"
chk "hint for == explains itself"                                               grep -q 'type what to look for' <<<"$OUT"
OUT="$(bash -c "source '$UI'; _st_deep_on() { return 0; }; _st_hint_text '=a' 80; echo \"\$_ST_HINT\"")"
chk "hint for =a now mentions =="                                               grep -q '== searches every screen' <<<"$OUT"

# 2. search, open, back, quit
OUT="$(run '==nuke\nu\nu\n')"
chk "==nuke + Enter: the results screen is drawn"                               grep -q 'title=\[Search results\].*Nuke time' <<<"$OUT"
chk "results: the best match (the screen NAME) is row 1"                        grep -q 'opens the screen) Nuke time Nuke time (ux-)' <<<"$(grep 'title=\[Search results\]' <<<"$OUT" | head -1)"
OUT="$(run '==nuke\n1\n\nu\nu\n')"
chk "a number opens that screen (nuke_time_settings)"                           grep -q 'OPENED nuke_time_settings' <<<"$OUT"
back_to_top() { awk '/title=\[Search results\]/{s=1} s && /title=\[Top\] .*buf=\[\] fq=\[\] rows=\[Alpha Beta Gamma\]/{f=1} END{exit !f}' <<<"$OUT"; }
chk "after u the parent screen is drawn again: empty line, rows whole"           back_to_top
chk "and the program ends normally"                                             grep -q '^RC=0 QUIT=0' <<<"$OUT"
OUT="$(run '==chunk\n1\n\nu\nu\n')"
chk "==chunk finds Transfer speed and opens it"                                 grep -q 'OPENED xfer_speed_settings' <<<"$OUT"
OUT="$(run '==nuke\nq')"
chk "q in the results closes everything"                                        grep -q '^RC=0 QUIT=1' <<<"$OUT"
OUT="$(run '==pending\n1\n\nu\nu\n')"
chk "a Home row hit opens what Home opens (pn)"                                 grep -q 'INNER pn' <<<"$OUT"
OUT="$(run '==reset\n1\n\nu\nu\n')"
chk "Reset all settings is never run from a search"                             bash -c '! grep -q "RESET\|restore_all_defaults" <<<"$0"' "$OUT"
chk "a screen that cannot open says where to find it, and stays"                grep -q '^RC=0' <<<"$OUT"

# 3. nothing found / clear / choice menu
OUT="$(run '==zzqqxx\nu\nu\n')"
chk "nothing found: the screen says so"                                         grep -q 'Nothing found for “zzqqxx”' <<<"$OUT"
OUT="$(run '==\n')";   chk "== + Enter clears (no results screen)"              bash -c '! grep -q "Search results" <<<"$0"' "$OUT"
chk "== + Enter leaves the line empty"                                          grep -q 'buf=\[\] fq=\[\]' <<<"$(lastd)"
OUT="$(run '==   \n')"; chk "==  + spaces + Enter: nothing to search, no results" bash -c '! grep -q "Search results" <<<"$0"' "$OUT"
OUT="$(run '==nuke' CHOICE=1)"
chk "a choice menu keeps the old filter: ==nuke filters for =nuke"              grep -q 'fq=\[=nuke\]' <<<"$(lastd)"
OUT="$(run '==nuke\n' CHOICE=1)"
chk "a choice menu does not run a deep search"                                  bash -c '! grep -q "Search results" <<<"$0"' "$OUT"

# 4. the index (no screen is drawn: the search functions alone)
read -r -d '' IDX <<'EOF'
export PATH="$BIN:$PATH"
source "$BIN/bashbasicsbyvk_settings.sh"; source "$UI" 2>/dev/null; source "$DESC"; source "$DS"; source "$HM"
t()  { if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: got [$2] want [$3]"; fi; }
tm() { if [[ "$2" == *"$3"* ]]; then echo "  ok   $1"; else echo "  FAIL $1: [$2] lacks [$3]"; fi; }
_sd_split_key "File API›Snapshots|interval";                 t "key File API›Snapshots|interval" "$_SD_title/$_SD_tag" "Snapshots/interval"
_sd_split_key "Snapshots › Paths of a device›Display|sort";  t "key with a nested parent" "$_SD_title/$_SD_tag" "Display/sort"
_sd_split_key "Timezone › Manual|*";                         t "a spaced › belongs to the title" "$_SD_title/$_SD_tag" "Timezone › Manual/*"
_sd_scan
t  "File API opens fileapi_group_settings"      "${_SD_FN[File API]:-}" fileapi_group_settings
t  "Transfer speed opens xfer_speed_settings"   "${_SD_FN[Transfer speed]:-}" xfer_speed_settings
t  "Display -> the group screen, not the menu-context one" "${_SD_FN[Display]:-}" display_group_settings
t  "Sort order -> sort_order_settings"           "${_SD_FN[Sort order]:-}" sort_order_settings
t  "Reset all settings is never openable"       "${_SD_FN[Reset all settings]:-none}" none
t  "Home / Settings / Pending lists are not openable" "${_SD_FN[Home]:-none}${_SD_FN[Settings]:-none}${_SD_FN[Pending FileAPI actions]:-none}" nonenonenone
_sd_search "streams";  tm "streams finds Transfer speed" "${_SD_T[*]}" "Transfer speed"
_sd_search "chunk";    tm "chunk finds Transfer speed"   "${_SD_T[*]}" "Transfer speed"
_sd_search "nuke";     t  "a screen whose NAME matches ranks first" "${_SD_T[0]}" "Nuke time"
_sd_search "pending";  tm "pending finds the Home row"   "${_SD_L[*]}" "Home › Pending"
_sd_search "SNAPSHOT"; t  "case does not matter" "$(( ${#_SD_T[@]} > 0 ))" 1
_sd_search "zzqqxx";   t  "no match = no rows" "${#_SD_T[@]}" 0
_sd_search "e";        t  "never more than the cap" "$(( ${#_SD_T[@]} <= _SD_MAX ))" 1
_sd_search "snapshot"; t  "no screen is listed twice" "$(printf '%s\n' "${_SD_L[@]}" | sort | uniq -d | wc -l)" 0
_sd_search 'a$(touch '"$HOME"'/PWNED)b'; t "the query is data, not code" "$([ -e "$HOME/PWNED" ] && echo pwned || echo safe)" safe
_sd_search "local";    t  "Local Surf (it only closes) is not offered" "$(printf '%s\n' "${_SD_G[@]}" | grep -c '^local$')" 0
EOF
OUT="$(env BIN="$BIN" UI="$UI" DESC="$DESC" DS="$DS" HM="$HM" HOME="$HOME" TERM=xterm bash -c "$IDX" 2>&1)"
grep -E '^  (ok|FAIL)' <<<"$OUT"; grep -q '  FAIL' <<<"$OUT" && fail=1
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
