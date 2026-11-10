#!/usr/bin/env bash
# bashbasicsbyvk_xui_cs_ppmenucommands.sh — commands of the Cloud Surf people-on-a-share screen (it runs inside _xui_loop, handler _pp_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here and every key _pp_cmd handles is here: tests/xui_wiring.sh fails on a gap.
cmd_def r-     prefix  -  local  "Revoke these people" "r-1,3"
cmd_def g      exact   -  local  "Offer this share to more people"
cmd_def t      exact   -  local  "All my files (the share as a tree)"
cmd_def rf     exact   -  local  "Reload the people"
