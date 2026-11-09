#!/usr/bin/env bash
# bashbasicsbyvk_xui_nfmenucommands.sh — commands of the Notifications screen (it runs inside _xui_loop, handler _nf_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
cmd_def nf     exact   -  local  "Close notifications, back to where you came from"
cmd_def rf     exact   -  local  "Refresh the list"
cmd_def r-     prefix  -  local  "Dismiss notifications" "r-1,3"
