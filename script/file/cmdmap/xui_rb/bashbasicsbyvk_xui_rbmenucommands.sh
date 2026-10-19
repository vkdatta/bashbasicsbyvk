#!/usr/bin/env bash
# bashbasicsbyvk_xui_rbmenucommands.sh — commands of the RBAM screen (it runs inside _xui_loop, handler _rb_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
cmd_def rbam   exact   -  local  "Close RBAM, back to where you came from"
cmd_def ui     word    -  local  "Import people (CSV / text)"
cmd_def ux     exact   -  local  "Export people"
cmd_def r-     prefix  -  local  "Remove people from the list" "r-1,3"
cmd_def rf     exact   -  local  "Refresh the list"
cmd_def sd     exact   -  local  "Send my dinons to everyone"
cmd_def sd-    prefix  -  local  "Send my dinons to the chosen rows" "sd-1,3"
