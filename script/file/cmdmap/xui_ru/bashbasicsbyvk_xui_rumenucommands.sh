#!/usr/bin/env bash
# bashbasicsbyvk_xui_rumenucommands.sh — commands of the Rbam person screen (their shares) (it runs inside _xui_loop, handler _ru_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here and every key _ru_cmd handles is here: tests/xui_wiring.sh fails on a gap.
cmd_def r-     prefix  -  local  "Revoke / drop these shares" "r-1,3"
cmd_def rf     exact   -  local  "Reload the shares"
