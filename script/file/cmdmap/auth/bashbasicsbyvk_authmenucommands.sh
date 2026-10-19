#!/usr/bin/env bash
# bashbasicsbyvk_authmenucommands.sh — commands that exist ONLY in the 'auth' menu (handler '-' = its own loop).
# Edit the descriptions: they are the live suggestion text.
cmd_def u        exact   -  local  "Back"
cmd_def q        exact   -  local  "Close"
cmd_def c        exact   -  local  "Create user"
cmd_def l        exact   -  local  "Link old account"
cmd_def ui       exact   -  local  "Import users"
cmd_def r        exact   -  local  "Remove user"
cmd_def r-       prefix  -  local  "Remove user"
cmd_def ux       exact   -  local  "Export users"
cmd_def ux-      prefix  -  local  "Export users" "ux-1"
