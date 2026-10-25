#!/usr/bin/env bash
# bashbasicsbyvk_xui_ghrmenucommands.sh — commands of one GitHub repo (it runs inside _xui_loop, handler _ghr_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here (tests/github/ui_test.py types each one and checks it is accepted).
cmd_def c      exact   -  local  "Create a release / a tag"
cmd_def e      exact   -  local  "Edit: pick rows, then what to change"
cmd_def r      exact   -  local  "Rename: pick rows, then new names"
cmd_def d      exact   -  local  "Delete: pick rows"
cmd_def g      exact   -  local  "Download (clone at the tag): pick rows"
cmd_def e-     prefix  -  local  "Edit these rows" "e-1,3-5"
cmd_def r-     prefix  -  local  "Rename these rows" "r-1,3-5"
cmd_def d-     prefix  -  local  "Delete these rows" "d-1,3-5"
cmd_def g-     prefix  -  local  "Download these rows (clone)" "g-1,3-5"
cmd_def i-     prefix  -  local  "Info on these rows" "i-2"
cmd_def rf     exact   -  local  "Reload releases and tags"
