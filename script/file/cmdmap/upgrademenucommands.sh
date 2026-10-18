#!/usr/bin/env bash
# upgrademenucommands.sh — commands that exist ONLY in the 'upgrade' menu (handler '-' = its own loop).
# Edit the descriptions: they are the live suggestion text.
cmd_def -u       exact   -  local  "Close"
cmd_def u        exact   -  local  "Exit"
cmd_def fx       exact   -  local  "Functions (fx) — CSV-driven actions"
cmd_def sw       exact   -  local  "Switch — recents & tabs"
cmd_def .r       exact   -  local  "Rule book"
cmd_def q        exact   -  local  "Quit"
cmd_def -h       exact   -  local  "Help"
cmd_def i-       prefix  -  local  "Info about version N" "i-2"
cmd_def m        exact   -  local  "Latest main"
cmd_def main     exact   -  local  "Install the latest main branch"
cmd_def rf       exact   -  local  "Refresh"
cmd_def p-       prefix  -  local  "Project map of a path" "p-1"
cmd_def disk     exact   -  local  "Disk usage"
cmd_def ram      exact   -  local  "Memory usage"
