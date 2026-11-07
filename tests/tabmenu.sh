#!/usr/bin/env bash
# The master tab-menu template (bashbasicsbyvk_tabmenu.sh): the one place that draws every tabbed menu's tab bar, description,
# count line and footer, and that steps ←/→.   bash tests/tabmenu.sh
#  (1) define + bar: the current tab is in [ ], the labels are registered for the tap hit-test
#  (2) steps: next / prev wrap round; nowrap stops at the ends; _tm_key only reacts to the two tab sentinels
#  (3) the description line: tab key, then folder (the nearest parent wins), cut to the width with …
#  (4) count line, header rows, footer: u/q/h/cc exactly as fx printed them; -b says Back; extras follow
#  (5) every tabbed screen is built from the template (no private tab bar, no private ←/→ stepping left in a menu file)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; source "$ROOT/tests/wait_lib.sh"; fail=0
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1: got [$2] want [$3]"; }

REG=(); _bvk_tabs_register() { local IFS='|'; REG+=("$*"); }
_vp_usable() { _vp_usable_w=${W:-100}; }; _vp_cells() { _vp_w=${#1}; }
source "$(bvk_need bashbasicsbyvk_menuchrome.sh)"
source "$(bvk_need bashbasicsbyvk_settings_desc.sh)"
source "$(bvk_need bashbasicsbyvk_tabmenu.sh)"

# (1)
t=a
_tm_define demo t "🎨 Demo" "Demo" a:"🪄 A" b:"🎃 B" c:"⭐ C"
eq "registered for taps" "${REG[0]}" "🪄 A|🎃 B|⭐ C"
eq "bar, first tab current" "$(_tm_bar demo)" "[🪄 A] 🎃 B ⭐ C"
t=c; eq "bar, last tab current" "$(_tm_bar demo)" "🪄 A 🎃 B [⭐ C]"
t=nonsense; eq "an unknown state shows the first tab" "$(_tm_bar demo)" "[🪄 A] 🎃 B ⭐ C"

# (2)
t=a; _tm_next demo; eq "next" "$t" b
_tm_next demo; _tm_next demo; eq "next wraps round" "$t" a
_tm_prev demo; eq "prev wraps round" "$t" c
t=c; _tm_next demo nowrap; rc=$?; eq "nowrap stops at the end (state)" "$t" c; eq "nowrap stops at the end (status)" "$rc" 1
t=a; _tm_prev demo nowrap; rc=$?; eq "nowrap stops at the start" "$t-$rc" "a-1"
t=a; _tm_key demo __sw_tab_right__; eq "right key moves" "$t" b
_tm_key demo __sw_tab_left__; eq "left key moves" "$t" a
_tm_key demo 5; rc=$?; eq "any other word is not a tab key" "$rc-$t" "1-a"
_tm_define one o "x" "X" k:"Only"; o=k; _tm_next one; rc=$?; eq "a single tab never moves" "$rc-$o" "1-k"

# (3)
_ST_DESC_LOADED=1; _ST_DESC=([Demo|a]="Tab A text for the demo screen." [Demo|a:dir]="Folder dir text for the demo." [Demo|b]="Tab B text for the demo screen.")
t=a; eq "description of the tab" "$(_tm_desc_line demo)" "Tab A text for the demo screen."
eq "description of a folder" "$(_tm_desc_line demo dir)" "Folder dir text for the demo."
eq "the nearest parent folder wins" "$(_tm_desc_line demo dir/sub/deeper)" "Folder dir text for the demo."
eq "an unknown folder falls back to the tab" "$(_tm_desc_line demo other)" "Tab A text for the demo screen."
t=c; eq "a tab without a line prints an empty row (nothing breaks)" "$(_tm_desc_line demo)" ""
t=a; W=20; eq "cut to the width with …" "$(_tm_desc_line demo)" "Tab A text for the …"; W=100

# (4)
items=(1 2 3); _all_items=(1 2 3 4 5)
eq "count line" "$(_tm_count_line)" "3 out of 5 here"
eq "count line with a total" "$(_tm_count_line 28)" "3 out of 5 here · 28 total"
t=a; hdr="$(_tm_header demo)"
eq "header: blank · title · blank · bar · blank · description" "$(printf '%s' "$hdr" | tr '\n' '~')" "~🎨 Demo~~[🪄 A] 🎃 B ⭐ C~~Tab A text for the demo screen."
eq "header with another title (a repo name)" "$(_tm_header demo '🐙 repo' | sed -n 2p)" "🐙 repo"
eq "footer" "$(_tm_footer | grep -v '^$')" "u) Up   q) Quit   h) Home   cc) Cheat codes"
eq "footer, a screen with no folders" "$(_tm_footer -b | grep -v '^$')" "u) Back   q) Quit   h) Home   cc) Cheat codes"
eq "footer with extras (the group prefix note)" "$(_tm_footer '|' u.prefix '#Group prefix now: A*' | grep -v '^$' | tr '\n' '~')" "u) Up   q) Quit   h) Home   cc) Cheat codes~u) Remove last prefix~Group prefix now: A*~"

# (5) no tabbed screen keeps a private copy of what the template does
S="$ROOT/script/file"
for f in functions switch rules upgrade rbam csurf adf_github; do
  p="$(bvk_need bashbasicsbyvk_$f.sh)"
  grep -q '^_tm_define ' "$p" && ok "$f is defined through _tm_define" || bad "$f has no _tm_define"
  if grep -nE '_bvk_tabs_register|_tab_label\(\)|_tab_next\(\)|_tab_prev\(\)|_tabbar\(\)' "$p" | grep -v '^[0-9]*:#' | grep -q .; then
    bad "$f still has a private tab bar / tab stepping: $(grep -nE '_bvk_tabs_register|_tab_label\(\)|_tab_next\(\)|_tab_prev\(\)|_tabbar\(\)' "$p" | head -2)"
  else ok "$f has no private tab bar or tab stepping"; fi
done
exit $fail
