#!/usr/bin/env bash
# runs one REAL input loop of the app inside a pty.   usage: harness.sh <repo-root> <editor: cm|browse|multi|sm>
ROOT="$1"; ED="$2"; F="$ROOT/script/file"
export HOME="$(mktemp -d)"; SCRIPT_DIR="$F"
declare -F _lt_b >/dev/null || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }
source "$F/engine/bashbasicsbyvk_viewport.sh"
source "$F/engine/bashbasicsbyvk_cmdmap.sh"; _vp_probe_size
source "$F/engine/bashbasicsbyvk_smartmenu.sh" 2>/dev/null
source "$F/engine/bashbasicsbyvk_browse.sh" 2>/dev/null
source "$F/settings/bashbasicsbyvk_filter.sh" 2>/dev/null
_orig_stty=$(stty -g)
_vp_poll_cur=0.5
case "$ED" in
  cm)
    _cm_boot 2>/dev/null
    _cm_line_edit "Enter name: " "" v 0
    printf '\nRESULT=[%s]\nDONE\n' "$_CM_OUT" ;;
  browse)
    items=(a b c); _vp_count() { _vp_n=3; }; _vp_hint_row=0
    _read_choice_raw
    printf 'RESULT=[%s]\nDONE\n' "$choice" ;;
  multi)
    items=(a b c); _vp_count() { _vp_n=3; }
    _multi_prompt_loop_raw 2>/dev/null
    printf 'RESULT=[%s]\nDONE\n' "$_buf" ;;
esac
