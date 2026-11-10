#!/usr/bin/env bash
# bashbasicsbyvk_xui_gdpmenucommands.sh — commands of the Google Drive profiles screen (it runs inside _xui_loop, handler _gdp_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here and every key _gdp_cmd handles is here: tests/xui_wiring.sh fails on a gap.
cmd_def n      exact   -  local  "New profile (rclone config)"
cmd_def rf     exact   -  local  "Reload the rclone profiles"
