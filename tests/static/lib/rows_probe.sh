#!/usr/bin/env bash
# tests/static/lib/rows_probe.sh — ONE process: every ROW PRINTER of the menu chrome, fed through the REAL smart-menu detector.
# No terminal, no app start, no sleeps: the printers' own output is recorded with _sm_record and judged by _sm_detect.
# Rows (TSV):   P producer mode N detect_rc rows_found rules_printed first_is_rule last_is_rule footer   (footer 0 = a line of key cells · 1 = ONE cell: u) Back)
#   producer = the function that prints the rows · mode = managed (the viewport is on: it draws the rules) | plain (no viewport: the printer draws them)
#   N = how many rows it was given (0 1 2 3) · detect_rc = _sm_detect's answer (0 = the viewport takes the list over) · rows_found = rows it took
#   rules_printed = how many rule lines the PRINTER itself emitted
# T <name> <value>   facts read from the libraries (the take-over minimum)
BVK_ROOT="${BVK_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"; F="$BVK_ROOT/script/file"
for f in engine/ui/bashbasicsbyvk_viewport.sh engine/commands/bashbasicsbyvk_advert.sh engine/ui/bashbasicsbyvk_smartmenu.sh engine/ui/bashbasicsbyvk_menuchrome.sh \
         templates/bashbasicsbyvk_tpl_defs.sh templates/bashbasicsbyvk_tpl.sh engine/ui/bashbasicsbyvk_browse.sh; do
  # shellcheck disable=SC1090
  source "$F/$f" </dev/null >/dev/null 2>&1 || { echo "LOAD FAIL: $f" >&2; exit 90; }
done
printf 'T\ttakeover_min\t%s\n' "${_VP_TAKEOVER_MIN:-UNSET}"
printf 'T\tkeyed_min\t%s\n' "${_VP_TAKEOVER_MIN_KEYED:-UNSET}"

# stand-ins for what a picker needs from the app (the row text itself is not what is under test)
_item_line_text_v() { _ilt_out=" $1) 📄 ${items[$(( $1 - 1 ))]##*/}"; }
_lk_load() { :; }
_sel_mark_v() { return 1; }

FOOTERS=($'\nu) Up   q) Quit   h) Home   cc) Cheat codes\n' $'\nu) Back\n')   # what _mc_footer prints under the rows: a blank row, one line of key cells (or ONE cell: back_only), a blank row

# the producers: each prints N rows (the picker helpers read the caller's arrays: dynamic scope, as in _pick_groups)
p_mc_options()    { local -a l=(); local i; for ((i=1;i<=$1;i++)); do l+=("choice $i"); done; _mc_options 1 "${l[@]}"; }
p_mc_keyed()      { local -a l=(); local i k=(x a b c); for ((i=1;i<=$1;i++)); do l+=("${k[$i]}:choice $i"); done; _mc_keyed "${l[@]}"; }      # LETTERED keys, as real keyed menus (c:Copy m:Move)
p_pick_group_rows() {
  local -a _pg_files=() _pg_keys=(); local -A _pg_of=() _pg_lab=() _pg_mark=(); local i
  for ((i=1;i<=$1;i++)); do _pg_keys+=("k$i"); _pg_lab[k$i]="k$i  (1 file(s))"; _pg_files+=("/x/f$i"); _pg_of[/x/f$i]="k$i"; done
  _pick_group_rows
}
p_pick_marked_rows() {
  local -a _pg_in=(); local -A _pg_mark=(); local i
  for ((i=1;i<=$1;i++)); do _pg_in+=("/x/f$i"); done
  _pick_marked_rows
}
p_pick_rows()     { local -a l=(); local i; for ((i=1;i<=$1;i++)); do l+=("/x/f$i"); done; _pick_rows "${l[@]}"; }

RULE="${_MC_RULE:-   ─────────────────────────────}"
for prod in mc_options mc_keyed pick_group_rows pick_marked_rows pick_rows; do
  declare -F "p_$prod" >/dev/null || continue
  for mode in managed plain; do
    if [ "$mode" = managed ]; then _mc_managed() { return 0; }; else _mc_managed() { return 1; }; fi
    for n in 0 1 2 3; do
      out="$("p_$prod" "$n" 2>&1)"
      rules=0; first=0; last=0; cnt=0; lastline=""
      while IFS= read -r l; do
        cnt=$((cnt+1)); [ "$l" = "$RULE" ] && rules=$((rules+1)); lastline="$l"
        (( cnt == 1 )) && [ "$l" = "$RULE" ] && first=1
      done <<< "$out"
      [ "$lastline" = "$RULE" ] && last=1
      for fi in 0 1; do
        _sm_reset; _sm_hdr=(); _sm_ftr=(); _sm_rows_text=(); _sm_rows_token=()
        _sm_prompt="Select: "
        _sm_record $'Title line\n'"$out"$'\n'"${FOOTERS[$fi]}"
        _sm_detect; rc=$?
        printf 'P\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n' "$prod" "$mode" "$n" "$rc" "${#_sm_rows_text[@]}" "$rules" "$first" "$last" "$fi"
      done
    done
  done
done
