#!/usr/bin/env bash
# bashbasicsbyvk_xui_csmenucommands.sh — commands of the Cloud Surf screen (it runs inside _xui_loop, handler _cs_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
cmd_def cs     exact   -  local  "Close Cloud Surf, back to where you came from"
cmd_def rf     exact   -  local  "Refresh the list"
cmd_def x-     prefix  -  local  "Nuke a share for everyone (sender only)" "x-1"
cmd_def e-     prefix  -  local  "Change the nuke time of a share (sender only)" "e-1"
cmd_def r-     prefix  -  local  "Drop a received share from your list" "r-1,3"
