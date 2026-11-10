#!/usr/bin/env bash
# bashbasicsbyvk_xui_ctmenucommands.sh — commands of the Cloud Surf file tree (it runs inside _xui_loop, handler _ct_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here and every key _ct_cmd handles is here: tests/xui_wiring.sh fails on a gap.
cmd_def d-     prefix  -  local  "Download these rows here" "d-1,3-5"
cmd_def r-     prefix  -  local  "Revoke / drop these rows" "r-1,3"
cmd_def rf     exact   -  local  "Reload this folder"
