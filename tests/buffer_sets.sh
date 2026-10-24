#!/usr/bin/env bash
# Named buffer sets:  c-1,3 as set1 · k-/s- prefixes · conflict rules (add/replace/deny/ask) · d- <name> · v- views · the fx select picker.   bash tests/buffer_sets.sh
# Runs the REAL staging helpers / buffer / select / adf_selection code with stubs only for the screen (menus, read).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/wait_lib.sh"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
_fx_adf_register() { :; }
for n in bashbasicsbyvk_choose.sh bashbasicsbyvk_fileapi_lib.sh bashbasicsbyvk_staging_helpers.sh bashbasicsbyvk_staging_buffer.sh bashbasicsbyvk_staging_copy.sh \
         bashbasicsbyvk_staging_move.sh bashbasicsbyvk_staging_shortcut.sh bashbasicsbyvk_staging_bookmark.sh bashbasicsbyvk_select.sh bashbasicsbyvk_adf_selection.sh; do
  f="$(bvk_need "$n")" || exit 1; source "$f"
done
eval "$(sed -n '/^_nav_parse_select()/,/^}/p;/^_nav_index_ok()/,/^}/p' "$(bvk_need bashbasicsbyvk_transfer.sh)")"
# ---- stubs: the screen and the answers
_mc_header() { echo "$@"; }; _mc_options() { local n="$1"; shift; local l; for l in "$@"; do echo "${n}) $l"; n=$((n+1)); done; }; _mc_footer() { :; }
_bvk_quit() { :; }; _bvk_invalid() { echo "INVALID"; }
parse_selection() { local spec="$1" max="$2" p i; for p in ${spec//,/ }; do if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then for ((i=BASH_REMATCH[1]; i<=BASH_REMATCH[2]; i++)); do [ "$i" -le "$max" ] && echo "$i"; done; elif [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -le "$max" ]; then echo "$p"; fi; done; }
ANS=(); read() { case " $* " in *" -p "*) local v="${@: -1}"; builtin printf -v "$v" '%s' "${ANS[0]:-}"; ANS=("${ANS[@]:1}") ;; *) builtin read "$@" ;; esac; }   # prompts take the next answer; file reads stay real
_view_selections_menu() { return 0; }; perform_shortcut() { :; }
imaginary_mode=false; _sp_ensure_store
mkdir -p "$T/w/sub"; for f in a b c d; do echo "$f" > "$T/w/$f.txt"; done; echo x > "$T/w/sub/in.txt"
items=("$T/w/a.txt" "$T/w/b.txt" "$T/w/c.txt" "$T/w/d.txt" "$T/w/sub"); path="$T/w"
CPO="$_SP_CP_ONCE_FILE"; set1="" 
cnt() { _sp_count "$1" "${2:-}"; }

# ---- 1  as + once/persistent + names
handle_staging_stage "c-1,2 as set1" >/dev/null; handle_staging_stage "c-a-1-4 as set2" >/dev/null; handle_staging_stage "c-3" >/dev/null
[ "$(cnt "$CPO" set1)" = 2 ] && [ "$(cnt "$CPO" set2)" = 1 ] && [ "$(cnt "$CPO")" = 4 ] && ok "c-1,2 as set1 / c-a-1-4 as set2 / c-3 keep their own lines" || bad "named stage: $(cat "$CPO" | tr '\t' '~')"
_sp_load_set L "$CPO" ""; [ "${#L[@]}" = 1 ] && ok "unnamed item stays flat" || bad "flat set"
handle_staging_stage "k--1 as keep" >/dev/null; [ "$(cnt "$_SP_SC_FILE" keep)" = 1 ] && ok "k-- stages SHORTCUT (persistent), named" || bad "k--"
handle_staging_stage "s-1,2" >/dev/null; [ "$(cnt "$_SP_SL_ONCE_FILE")" = 2 ] && [ "$(cnt "$_SP_SC_ONCE_FILE")" = 0 ] && ok "s- stages SELECT, not shortcut" || bad "s- routing"
handle_staging_stage "c-1 as bad!name" | grep -q "Alias may use" && ok "a bad name is refused by the shared as-parser" || bad "bad alias accepted"

# ---- 2  conflicts: add / replace / deny / ask
buffer_conflict_cp=add;     handle_staging_stage "c-4 as set1" >/dev/null; [ "$(cnt "$CPO" set1)" = 3 ] && ok "conflict add: joins the set" || bad "add: $(cnt "$CPO" set1)"
buffer_conflict_cp=replace; handle_staging_stage "c-5 as set1" >/dev/null; _sp_load_set L "$CPO" set1; [ "${#L[@]}" = 1 ] && [ "${L[0]}" = "$T/w/sub" ] && ok "conflict replace: new items take the place" || bad "replace: ${L[*]}"
buffer_conflict_cp=deny;    handle_staging_stage "c-1 as set1" | grep -q "nothing changed" ; [ "$(cnt "$CPO" set1)" = 1 ] && ok "conflict deny: nothing changed" || bad "deny"
buffer_conflict_cp=ask; ANS=(1); handle_staging_stage "c-1 as set1" >/dev/null; [ "$(cnt "$CPO" set1)" = 2 ] && ok "ask → 1 add" || bad "ask 1"
ANS=(2); handle_staging_stage "c-2 as set1" >/dev/null; [ "$(cnt "$CPO" set1)" = 1 ] && ok "ask → 2 replace" || bad "ask 2"
ANS=(3); handle_staging_stage "c-1 as set1" >/dev/null; [ "$(cnt "$CPO" set1)" = 1 ] && ok "ask → 3 deny" || bad "ask 3"
ANS=(n "set9"); handle_staging_stage "c-1 as set1" >/dev/null; [ "$(cnt "$CPO" set9)" = 1 ] && [ "$(cnt "$CPO" set1)" = 1 ] && ok "ask → n: another name" || bad "ask n"
# the setting is saved / read back
buffer_conflict_mv=replace; grep -q 'buffer_conflict_' "$(bvk_need bashbasicsbyvk_settings.sh)" && ok "settings file knows buffer_conflict_*" || bad "settings"

# ---- 3  d- <name> applies only that set, clears only it
perform_copy() { echo "COPY $*" >> "$T/log"; }; perform_move() { echo "MOVE $*" >> "$T/log"; }
: > "$T/log"; handle_staging_dispatch " set2" >/dev/null
[ "$(wc -l < "$T/log")" = 1 ] && grep -q "COPY $T/w $T/w/a.txt" "$T/log" 2>/dev/null; ok_line=$?
_sp_load_set L "$CPO" set2; [ "${#L[@]}" = 0 ] && [ "$(cnt "$CPO" set1)" = 1 ] && [ "$(cnt "$CPO" set9)" = 1 ] && ok "d- set2 applied and cleared only set2" || bad "d- set2 left: $(tr '\t' '~' < "$CPO")"
grep -q "^COPY $T/w " "$T/log" && ok "d- set2 → perform_copy ran once" || bad "perform_copy log: $(cat "$T/log")"
handle_staging_dispatch " nosuch" | grep -q "No set named" && ok "d- unknown name says so" || bad "unknown name"
: > "$T/log"; handle_staging_dispatch "" >/dev/null; [ "$(cnt "$CPO")" = 0 ] && ok "bare d- applies everything and clears once buffers" || bad "bare d-"

# ---- 4  v- views
: > "$CPO"
handle_staging_stage "c-1,2 as v1" >/dev/null; handle_staging_stage "c-3" >/dev/null
ANS=(u); out=$(_sp_view_one_buffer "Copy (once)" "$CPO" cp); echo "$out" | grep -q "1) v1 >  (2)" && echo "$out" | grep -q "2) flat items (no name) >  (1)" && ok "v- lists sets + flat items as rows" || bad "view rows: $out"
ANS=(1 u u); out=$(_sp_view_one_buffer "Copy (once)" "$CPO" cp); echo "$out" | grep -q "Copy (once) buffer › v1 (2)" && ok "number opens the set" || bad "open set: $out"
ANS=(n 1 renamed u); _sp_view_one_buffer "Copy (once)" "$CPO" cp >/dev/null; [ "$(cnt "$CPO" renamed)" = 2 ] && ok "n renames a set" || bad "rename"
ANS=(x 1 u); _sp_view_one_buffer "Copy (once)" "$CPO" cp >/dev/null; [ "$(cnt "$CPO" renamed)" = 0 ] && [ "$(cnt "$CPO")" = 1 ] && ok "x removes a whole set" || bad "remove set"
: > "$CPO"; handle_staging_stage "c-1,2" >/dev/null; ANS=(u); out=$(_sp_view_one_buffer "Copy (once)" "$CPO" cp); echo "$out" | grep -q "1) $T/w/a.txt" && ok "no sets → the plain path list as before" || bad "plain view"

# ---- 5  fx picker
_sel_load_live() { _sel_load "$1"; _SEL_VANISHED=0; }
: > "$_SP_SL_ONCE_FILE"; : > "$_SEL_FILE"; printf '%s\n' "$T/w/d.txt" > "$_SEL_FILE"
sel=(); ANS=(); _fx_sel_need >/dev/null; [ "${sel[*]}" = "$T/w/d.txt" ] && ok "no named set → the .s selection, as before (no picker)" || bad "legacy: ${sel[*]}"
handle_staging_stage "s-1,2 as pick1" >/dev/null; handle_staging_stage "s--3,4 as keep1" >/dev/null
# entries are listed: s-- sets (keep1), s- sets (pick1), flat items
sel=(); ANS=(1 2 c); _fx_sel_need >/dev/null; [ "${sel[*]}" = "$T/w/d.txt" ] && [ "$(cnt "$_SP_SL_FILE")" = 2 ] && [ "$(cnt "$_SP_SL_ONCE_FILE")" = 2 ] && ok "N opens a set, a file number selects it; nothing leaves s-- / untouched sets" || bad "drill: ${sel[*]}"
sel=(); ANS=(w2 c); _fx_sel_need >/dev/null; [ "${#sel[@]}" = 2 ] && [ "$(cnt "$_SP_SL_ONCE_FILE")" = 0 ] && ok "w2 takes the whole once set, which then leaves" || bad "w2: ${sel[*]} / $(cnt "$_SP_SL_ONCE_FILE")"
sel=(); ANS=(w1 c); _fx_sel_need >/dev/null; [ "${#sel[@]}" = 2 ] && [ "$(cnt "$_SP_SL_FILE")" = 2 ] && ok "a taken s-- set stays" || bad "w1 persistent: $(cnt "$_SP_SL_FILE")"
sel=(); ANS=(w2 c); _fx_sel_need >/dev/null; [ "${sel[0]}" = "$T/w/d.txt" ] && ok "flat items are the last row of the picker" || bad "flat row: ${sel[*]}"
sel=(); ANS=(z); _fx_sel_need >/dev/null && bad "z must cancel" || ok "z cancels (return 1)"
# folder convention: N enters a folder, wN takes it whole
: > "$_SP_SL_FILE"; printf '@fold\t%s\n' "$T/w/sub" > "$_SP_SL_FILE"
sel=(); ANS=(1 1 1 c); _fx_sel_need >/dev/null; [ "${sel[0]}" = "$T/w/sub/in.txt" ] && ok "N on a folder goes inside; a file there is selected" || bad "inside: ${sel[*]}"
sel=(); ANS=(1 w1 c); _fx_sel_need >/dev/null; [ "${sel[0]}" = "$T/w/sub" ] && ok "w1 on a folder selects the folder itself" || bad "w-folder: ${sel[*]}"
# prefix convention
is_select=; cleaned_input=; _nav_parse_select "w3"; { $is_select && [ "$cleaned_input" = 3 ]; } && ok "transfer prefix is w" || bad "w prefix"
_nav_parse_select "s3"; { ! $is_select; } && ok "s is no longer the select prefix" || bad "s prefix still select"

# ---- 6  unnamed s- / s-- items are the "flat items" of the picker (no `as` needed); the row is hidden when empty
: > "$_SP_SL_FILE"; : > "$_SP_SL_ONCE_FILE"; : > "$_SEL_FILE"
handle_staging_stage "s-1,2" >/dev/null
sel=(); ANS=(w1 c); _fx_sel_need >/dev/null; [ "${#sel[@]}" = 2 ] && [ "$(cnt "$_SP_SL_ONCE_FILE")" = 0 ] && ok "plain s-1,2 (no name) reaches fx as flat items, and leaves s- once taken" || bad "unnamed s-: ${sel[*]} / $(cnt "$_SP_SL_ONCE_FILE")"
handle_staging_stage "s--1" >/dev/null; sel=(); ANS=(w1 c); _fx_sel_need >/dev/null; [ "${#sel[@]}" = 1 ] && [ "$(cnt "$_SP_SL_FILE")" = 1 ] && ok "unnamed s-- item is taken and stays" || bad "unnamed s--"
handle_staging_stage "s-2 as only" >/dev/null; : > "$_SP_SL_FILE"; : > "$_SEL_FILE"
out=$(ANS=(z); _fx_sel_need 2>&1); echo "$out" | grep -q "flat items" && bad "empty flat row shown" || ok "empty flat items row is hidden"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
