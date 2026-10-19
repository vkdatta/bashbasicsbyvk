#!/usr/bin/env bash
# usage: harness.sh <script_root> <stale_rows>
R="$1"; STALE="$2"
_lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }
source "$R/file/engine/bashbasicsbyvk_viewport.sh"
source "$R/file/settings/bashbasicsbyvk_settings_ui.sh"
# the cache goes stale: the real terminal is smaller than what the app last measured
_vp_rows_now=$STALE; _vp_cols_now=80
b(){ _st_reset; local i; for i in $(seq 1 40); do _st_add a "cmd$i" 0 "Description $i" "cmd$i"; done; }
a(){ _st_back=1; }
_st_icon="🎮" _st_crumb="" _st_f1_custom="u) Back   ↑↓) Move"
printf 'Action: cc\n'
_st_depth=1
_st_run "Cheat codes · find" b a
printf '\nDONE\n'
