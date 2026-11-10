#!/usr/bin/env bash
# bashbasicsbyvk_xui_cfwmenucommands.sh — commands of the Cloudflare workers and pages recover screen (it runs inside _xui_loop, handler _cfw_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here and every key _cfw_cmd handles is here: tests/xui_wiring.sh fails on a gap.
cmd_def r      exact   -  local  "Recover: pick rows in the live picker"
cmd_def r-     prefix  -  local  "Recover these rows" "r-1,3-5"
cmd_def e      exact   -  local  "Export all shown rows as csv / json"
cmd_def e-     prefix  -  local  "Export these rows" "e-1,3-5"
cmd_def rf     exact   -  local  "Reload workers and pages"
