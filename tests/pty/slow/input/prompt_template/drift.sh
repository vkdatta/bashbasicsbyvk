#!/usr/bin/env bash
# One template for every typed-line prompt (see prompt_test.py).  A loop that draws or clicks its own prompt line WITHOUT the template
# is exactly the drift this guards against:
#   1. ONE DRAWER: the typed line is painted by _bvk_draw_input (viewport.sh): the cursor / selection, the rows of a long text, the tap geometry
#   2. ONE TAP: a tap on the typed text is handled by the engine (_bvk_edit_press); no loop re-implements it
#   3. ONE LOOP: every typed-line loop runs _bvk_edit_run (viewport.sh); nothing outside it may set up its own raw keys / paste / mouse reports
#      (_te_begin with a registered editor, _bvk_paste_on, _bvk_mouse_on).  PENDING lists loops not moved onto the engine yet, BY NAME: it is EMPTY
#      (Settings was the last) and a new loop never goes on it (AGENTS.md rule 17).
cd "$(dirname "$0")/../../../../.." || exit 1
fail=0
code() { grep -v '^[[:space:]]*#' "$1"; }                   # the file without its comment lines
# 1. ONE DRAWER: the typed line is painted by _bvk_draw_input (viewport.sh) and nowhere else.  Every loop's draw function calls it; nothing outside it
#    calls the row painters (_bvk_fit_input / _bvk_row_multi) or _te_cursor (no block cursor over a selection) itself.
for need in browse smartmenu cmdmap; do
  code "script/file/engine/bashbasicsbyvk_$need.sh" | grep -q '_bvk_draw_input ' && echo "  ok   $need.sh: its prompt line is drawn by _bvk_draw_input" || { echo "  FAIL $need.sh: draws its own prompt line (use _bvk_draw_input)"; fail=1; }
done
code script/file/engine/bashbasicsbyvk_viewport.sh | grep -q '_multi_print_input_line() {' && code script/file/engine/bashbasicsbyvk_viewport.sh | grep -q '_bvk_draw_input "\$_mp"' && echo "  ok   viewport.sh: the picker's prompt line is drawn by _bvk_draw_input" || { echo "  FAIL viewport.sh: the picker draws its own prompt line"; fail=1; }
code script/file/settings/bashbasicsbyvk_settings_ui.sh | grep -q '_bvk_draw_input ' && echo "  ok   settings_ui.sh: its prompt line is drawn by _bvk_draw_input" || { echo "  FAIL settings_ui.sh: draws its own prompt line (use _bvk_draw_input)"; fail=1; }
while IFS= read -r f; do
  b="${f##*/}"
  case "$b" in bashbasicsbyvk_viewport.sh|bashbasicsbyvk_textedit.sh|bashbasicsbyvk_loadmap_stubs.sh) continue ;; esac     # (the stubs only forward a call to the file that defines the function)
  # settings_ui.sh may keep _bvk_fit_input for the screen it leaves on the terminal (the typed text of the closed top screen), not for a live prompt
  if code "$f" | grep -qE '_bvk_row_multi |_te_cursor '; then echo "  FAIL $b: paints the typed line itself (_bvk_row_multi / _te_cursor): that is _bvk_draw_input's job"; fail=1; fi
done < <(grep -rlE '_bvk_row_multi|_te_cursor' script --include='bashbasicsbyvk_*' | sort)
# 2. ONE TAP: a tap on the typed text is handled in the engine (_bvk_edit_press -> _bvk_prompt_tap); no loop re-implements it
while IFS= read -r f; do
  b="${f##*/}"
  case "$b" in bashbasicsbyvk_viewport.sh|bashbasicsbyvk_mouse.sh) continue ;; esac
  if code "$f" | grep -q '_bvk_prompt_tap '; then echo "  FAIL $b: handles a tap on the typed text itself (_bvk_prompt_tap): the engine does that for every loop"; fail=1; fi
done < <(grep -rl '_bvk_prompt_tap' script --include='bashbasicsbyvk_*' | sort)
code script/file/engine/bashbasicsbyvk_viewport.sh | grep -q '_bvk_prompt_tap "\${!_ED_BUF}"' && echo "  ok   viewport.sh: the tap on the typed text is handled in _bvk_edit_press" || { echo "  FAIL viewport.sh: _bvk_edit_press no longer handles the tap on the typed text"; fail=1; }
# 3. one loop
# every loop starts from a clean set of hooks (dynamically scoped: a loop that runs inside another's hook would inherit what it does not set)
for need in engine/bashbasicsbyvk_browse engine/bashbasicsbyvk_viewport engine/bashbasicsbyvk_smartmenu engine/bashbasicsbyvk_cmdmap settings/bashbasicsbyvk_settings_ui; do
  code "script/file/$need.sh" | grep -q 'local \$_BVK_ED_HOOKS' && echo "  ok   ${need##*/}.sh: starts from a clean set of hooks" || { echo "  FAIL ${need##*/}.sh: sets _ED_* hooks without  local \$_BVK_ED_HOOKS  first (a nested loop would inherit the outer one's hooks)"; fail=1; }
done
# ONE WORDING for "too large": _bvk_too_large_text (viewport.sh) is the only place the sentence ("Too large: N characters ...") is written; every typed-line prompt shows it
# through _bvk_notice / the suggestion row
for f in browse viewport smartmenu cmdmap textedit; do
  n=$(code "script/file/engine/bashbasicsbyvk_$f.sh" | grep -ciE '[Tt]oo large:')
  if [ "$f" = viewport ]; then (( n == 1 )) || { echo "  FAIL viewport.sh: the \"Too large:\" sentence is written $n times (exactly once, in _bvk_too_large_text)"; fail=1; }
  else (( n == 0 )) || { echo "  FAIL $f.sh: writes its own \"Too large:\" sentence (use _bvk_too_large_text)"; fail=1; }; fi
done
code script/file/settings/bashbasicsbyvk_settings_ui.sh | grep -qiE '[Tt]oo large:' && { echo "  FAIL settings_ui.sh: writes its own \"Too large:\" sentence (use _bvk_too_large_text)"; fail=1; }
PENDING=""      # every typed-line loop runs _bvk_edit_run now (Settings was the last): this list is empty and stays empty
for need in engine/bashbasicsbyvk_browse engine/bashbasicsbyvk_viewport engine/bashbasicsbyvk_smartmenu engine/bashbasicsbyvk_cmdmap settings/bashbasicsbyvk_settings_ui; do
  code "script/file/$need.sh" | grep -q '_bvk_edit_run' && echo "  ok   ${need##*/}.sh: its typed-line loop is _bvk_edit_run" || { echo "  FAIL ${need##*/}.sh: no longer runs its typed-line prompt through _bvk_edit_run"; fail=1; }
done
while IFS= read -r f; do
  b="${f##*/}"
  case "$b" in bashbasicsbyvk_viewport.sh|bashbasicsbyvk_mouse.sh|bashbasicsbyvk_textedit.sh) continue ;; esac     # the engine, the mouse and the key helpers themselves
  case " $PENDING " in *" $b "*) echo "  warn $b: still its own loop (PENDING)"; continue ;; esac
  echo "  FAIL $b: sets up raw keys / paste / mouse reports itself (_te_begin with a registered editor, _bvk_paste_on or _bvk_mouse_on): a copy of the loop. Use _bvk_edit_run."; fail=1
done < <(grep -rlE '_te_begin [^ ]+ [^ ]+ [^ ]+ [^ ]+|_bvk_paste_on|_bvk_mouse_on' script --include='bashbasicsbyvk_*' | sort)
# 4. a stand-alone tool that chains questions (2+ calls of bashbasicsbyvk_ask / _yn) is a step list on _mc_steps: u = ONE QUESTION BACK (never a commit message / a "no")
#    PENDING_CHAIN names the tools not converted yet, BY NAME: it only ever shrinks, a new tool never goes on it.
PENDING_CHAIN=""      # EMPTY: gitpush, localhost and recover_creds.py are steps now; a new tool never goes on this list
while IFS= read -r f; do
  b="${f##*/}"
  n=$(grep -v '^[[:space:]]*#' "$f" | grep -c 'bashbasicsbyvk_ask "\|bashbasicsbyvk_yn "\|bashbasicsbyvk_ask \$\|bashbasicsbyvk_yn \$\|ask(\|yn(')
  (( n >= 2 )) || continue
  if grep -qE '_mc_steps|[^_a-z]steps\(' "$f"; then echo "  ok   $b: $n questions, chained as steps"; continue; fi
  case " $PENDING_CHAIN " in *" $b "*) echo "  warn $b: $n chained questions without u = back (PENDING_CHAIN)"; continue ;; esac
  echo "  FAIL $b: $n questions chained without _mc_steps: u would be taken as an answer. Make each question a step (see bashbasicsbyvk_gitpush, bashbasicsbyvk_delete)."; fail=1
done < <(grep -rlE 'bashbasicsbyvk_(ask|yn) ' script/cmd script/file/infinity/tools script/file/loops --include='bashbasicsbyvk_*' 2>/dev/null | sort)
(( fail )) && { echo FAILED; exit 1; }
echo "ALL OK"
