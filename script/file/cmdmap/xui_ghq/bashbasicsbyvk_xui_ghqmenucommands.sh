#!/usr/bin/env bash
# bashbasicsbyvk_xui_ghqmenucommands.sh — commands of one repo of another GitHub user (it runs inside _xui_loop, handler _ghq_cmd).
# READ ONLY: no create / edit / rename / delete here, so none is declared (cc and the footer never advertise one).
cmd_def g      exact   -  local  "Download (clone at the tag): pick rows"
cmd_def g-     prefix  -  local  "Download these rows (clone)" "g-1,3-5"
cmd_def i-     prefix  -  local  "Info on these rows" "i-2"
cmd_def rf     exact   -  local  "Reload releases and tags"
