#!/usr/bin/env bash
# The suggestion row must not be drawn twice on Home / Settings style screens after another screen was opened from them.   bash tests/hint_leak.sh
#  _st_run keeps _vp_hint_row / _vp_hint_n as LOCALS (0): the screen paints its suggestion inside its own block.  Bash dynamic scope lets a screen opened
#  from it (an xui screen: Cloud Surf, Links, RBAM ... -> _vp_geometry -> _bvk_hint_area_on) assign THROUGH that local; if the value stays 1, the shared
#  drawer (_bvk_draw_input -> _input_hint_sync) paints a second copy of the suggestion on the blank row.
#  1. _xui_enter / _xui_leave give the flag back as they found it     2. _st_draw says "this screen paints its own hint" on every draw
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fail=0
source "$ROOT/tests/wait_lib.sh"
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
XUI="$(bvk_need bashbasicsbyvk_xui.sh)"; UI="$(bvk_need bashbasicsbyvk_settings_ui.sh)"
out="$(XUI="$XUI" bash -c '
  source "$XUI" 2>/dev/null
  _filter_reset_state() { :; }; _vp_cache_reset() { :; }
  home() { local _vp_hint_row=0 _vp_hint_n=0; child; echo "$_vp_hint_row $_vp_hint_n"; }
  child() { _xui_enter; _vp_hint_row=1; _vp_hint_n=2; _xui_leave; }      # what the viewport does inside an xui screen
  home' 2>&1)"
[ "$out" = "0 0" ] && ok "an xui screen gives the suggestion-area flag back" || bad "xui leaves the flag on in the screen that opened it (got: $out)"
awk '/^_st_draw\(\) \{/{f=1} f&&/_vp_hint_row=0; _vp_hint_n=0/{found=1} f&&/^}/{exit} END{exit !found}' "$UI" \
  && ok "_st_draw resets the flag on every draw" || bad "_st_draw does not reset _vp_hint_row / _vp_hint_n"
[ "$fail" = 0 ] && echo "PASS" || echo "FAILED"; exit "$fail"
