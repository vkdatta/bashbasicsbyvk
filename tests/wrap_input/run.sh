#!/usr/bin/env bash
# Pasting a long link into a typed-line prompt on a NARROW screen (a phone) must not wrap the row: a wrapped row made every
# keystroke print the prompt again ("Paste link to import ..." x60). Runs the real editors in a pty with a tiny VT emulator.
#   bash tests/wrap_input/run.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; D="$(dirname "${BASH_SOURCE[0]}")"
command -v python3 >/dev/null || { echo "python3 missing - skipped"; exit 0; }
LINK="https://fileapi.bashbasics.workers.dev/tzB7G5nVzCYuR_2ZwpbUUzl430zJwn_tD14KuaupxDc#k=riSYY8OLiBHHqOilpwJiWHpGJhHZaqgxNiK3QZ2r8R4"
fail=0
for ed in cm browse; do for cols in 30 40 50 80; do
  out="$(python3 "$D/emu.py" "$ROOT" "$ed" "$cols" "$LINK" 2>&1)"
  rows="$(grep -o 'PROMPT_ROWS=[0-9]*' <<<"$out" | cut -d= -f2)"
  got="$(grep -o '^RESULT_JOINED=.*' <<<"$out" | sed 's/^RESULT_JOINED=//')"
  # cm = the free-text editor: the text WRAPS onto following rows like `read -e`, so the whole link must be visible on screen.
  # browse = the fixed-layout "Select:" row: it stays ONE row (text scrolls inside it), so only the prompt-row count matters.
  vis=yes; [ "$ed" = cm ] && { grep -o '^SCREEN_JOINED=.*' <<<"$out" | grep -qF "$LINK" || vis=no; }
  if [ "${rows:-9}" -le 1 ] && [ "$got" = "$LINK" ] && [ "$vis" = yes ]; then echo "  ok   $ed @ ${cols} cols (prompt rows=$rows, text intact$([ "$ed" = cm ] && echo ", whole link visible, wrapped"))"
  else echo "  FAIL $ed @ ${cols} cols: prompt rows=${rows:-?} (want <=1), text intact=$([ "$got" = "$LINK" ] && echo yes || echo NO), whole link visible=$vis"; fail=1; fi
done; done
exit $fail
