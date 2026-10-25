#!/usr/bin/env bash
# The loading bar appears by itself and nothing wires it by hand (AGENTS rule 7).   bash tests/smartload.sh
# (1) static: no _lb_* wrapper, no loadingbar file, smartload loaded first, every screen-drawing engine ends the wait before it draws
# (2) behaviour in a real pty: tests/smartload/pty_test.py
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/script"; fail=0
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

hits="$(grep -rnE '(^|[^A-Za-z_])_lb_[a-z]+|bashbasicsbyvk_loadingbar' "$S" "$ROOT/tests" --include='*' -I 2>/dev/null | grep -v "tests/smartload" | head -3)"
[ -z "$hits" ] && ok "no _lb_* call and no loadingbar file (smartload draws every bar)" || bad "a hand-wired loading bar is back: $hits"
[ -f "$S/file/engine/bashbasicsbyvk_smartload.sh" ] && [ ! -e "$S/file/engine/bashbasicsbyvk_loadingbar.sh" ] && ok "smartload.sh exists, loadingbar.sh is gone" || bad "smartload.sh missing or loadingbar.sh back"

imp="$S/file/engine/_3bvk_import_engine.sh"
a=$(grep -n 'bashbasicsbyvk_smartload.sh' "$imp" | head -1 | cut -d: -f1); b=$(grep -n 'bashbasicsbyvk_print.sh' "$imp" | head -1 | cut -d: -f1); c=$(grep -n 'bashbasicsbyvk_smartmenu.sh' "$imp" | head -1 | cut -d: -f1)
[ -n "$a" ] && [ "$a" -lt "${b:-0}" ] && [ "$a" -lt "${c:-0}" ] && ok "smartload loads before print and smartmenu (their shims call it)" || bad "smartload is not loaded before print / smartmenu in _3bvk_import_engine.sh"

# each of these ends the wait BEFORE it draws, so a bar on the screen is wiped while the cursor is still where the bar was drawn
for pair in "_st_draw:settings/bashbasicsbyvk_settings_ui.sh" "_vp_render_fresh:engine/bashbasicsbyvk_viewport.sh" "_cm_text_read:engine/bashbasicsbyvk_cmdmap.sh"; do
  fn="${pair%%:*}"; file="$S/file/${pair#*:}"
  grep -A2 "^${fn}()" "$file" | grep -q '_sl_ready' && ok "$fn ends the wait before it draws" || bad "$fn does not call _sl_ready first (a bar would be left on the screen)"
done

[ -f "$ROOT/tests/smartload/pty_test.py" ] && { python3 -I "$ROOT/tests/smartload/pty_test.py" "$ROOT" || fail=1; }

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
