#!/usr/bin/env bash
# runs the real line editor of the app inside a pty.  usage: harness.sh <repo-root> <editor: cm|sm|browse|multi>
ROOT="$1"; ED="$2"; F="$ROOT/script/file"
export HOME="$(mktemp -d)"; SCRIPT_DIR="$F"
declare -F _lt_b >/dev/null || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }
source "$F/engine/bashbasicsbyvk_viewport.sh"
source "$F/engine/bashbasicsbyvk_cmdmap.sh"; _vp_probe_size
case "$ED" in
  cm)
    _cm_boot 2>/dev/null
    _cm_line_edit "🔗 Paste link to import (include the #k=... part): " "" v 0
    printf '\nRESULT=[%s]\n' "$_CM_OUT" ;;
  browse)
    source "$F/engine/bashbasicsbyvk_smartmenu.sh" 2>/dev/null; source "$F/engine/bashbasicsbyvk_browse.sh" 2>/dev/null
    _buf=""; _pos=0; _vp_hint_row=0
    stty -icanon -echo min 1 time 0; printf 'READY\n'
    while IFS= builtin read -rsn1 k; do [ -z "$k" ] && break; _buf="${_buf:0:_pos}${k}${_buf:_pos}"; _pos=$((_pos+1)); _print_input_line; done
    printf '\nRESULT=[%s]\n' "$_buf" ;;
esac
