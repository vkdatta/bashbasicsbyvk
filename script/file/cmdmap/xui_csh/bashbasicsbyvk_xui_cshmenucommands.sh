#!/usr/bin/env bash
# bashbasicsbyvk_xui_cshmenucommands.sh — commands of the Cloud Shell profiles screen (it runs inside _xui_loop, handler _csh_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# Every key the footer prints is here and every key _csh_cmd handles is here: tests/pty/fast/menus/xui_wiring.sh fails on a gap.
cmd_def c      exact   -  local  "Create Cloud Shell profiles: type Google e-mails or choose file(s)"
cmd_def x      exact   -  local  "Remove"
cmd_def k      exact   -  local  "Switch off Cloud Shell (cure for a hung session)"
cmd_def rf     exact   -  local  "Reload who is signed in"
