#!/usr/bin/env bash
# One template for every typed-line prompt (see prompt_test.py).  A loop that draws or clicks its own prompt line WITHOUT the template
# is exactly the drift this guards against:
#   1. every file that draws a prompt line (_bvk_fit_input / _bvk_row_multi / _cm_edit_draw) calls _te_cursor (no block cursor over a selection)
#   2. every file whose read loop handles a tap (_bvk_mouse_hit) calls _bvk_prompt_tap for the tap on the typed text
#   (cmdmap: its typed-line prompt has no mouse reports on, so a tap never reaches it: exempt from 2, by name, not by default)
cd "$(dirname "$0")/../.." || exit 1
fail=0
code() { grep -v '^[[:space:]]*#' "$1"; }                   # the file without its comment lines
while IFS= read -r f; do
  case "$f" in */bashbasicsbyvk_textedit.sh) continue ;; esac
  code "$f" | grep -qE '_bvk_fit_input |_bvk_row_multi |_cm_edit_draw\(\)' || continue
  if code "$f" | grep -q '_te_cursor '; then echo "  ok   ${f##*/}: its prompt line draws through _te_cursor"
  else echo "  FAIL ${f##*/}: draws a prompt line but never calls _te_cursor (a selection would hide under the block cursor)"; fail=1; fi
done < <(grep -rlE '_bvk_fit_input|_bvk_row_multi|_cm_edit_draw' script --include='bashbasicsbyvk_*' | sort)
while IFS= read -r f; do
  case "$f" in */bashbasicsbyvk_mouse.sh|*/bashbasicsbyvk_cmdmap.sh) continue ;; esac
  code "$f" | grep -q '_bvk_mouse_hit ' || continue
  if code "$f" | grep -q '_bvk_prompt_tap '; then echo "  ok   ${f##*/}: a tap on the typed text goes through _bvk_prompt_tap"
  else echo "  FAIL ${f##*/}: reads taps but never calls _bvk_prompt_tap (a tap on the typed text would not move the cursor)"; fail=1; fi
done < <(grep -rlE '_bvk_mouse_hit|_st_click' script --include='bashbasicsbyvk_*' | sort)
# the settings engine (Settings, every choice box, Confirm delete) has its own click handler, not _bvk_mouse_hit
code script/file/settings/bashbasicsbyvk_settings_ui.sh | grep -q '_bvk_prompt_tap ' && echo "  ok   settings_ui.sh: _st_click uses _bvk_prompt_tap" || { echo "  FAIL settings_ui.sh: _st_click does not call _bvk_prompt_tap"; fail=1; }
(( fail )) && { echo FAILED; exit 1; }
echo "ALL OK"
