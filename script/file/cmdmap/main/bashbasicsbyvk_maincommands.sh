#!/usr/bin/env bash
# bashbasicsbyvk_maincommands.sh — EVERY main-menu command, defined once.
#
#   cmd_def ID  KIND  HANDLER  CLASS  "description"  ["example"]
#
#   KIND    exact | prefix | word      (see bashbasicsbyvk_cmdmap.sh)
#   HANDLER bvk_main_exec  → can be run from any menu / prompt (nav, util)
#           -              → handled by the list loop itself (act, filter)
#   CLASS   nav | util | tool | act | filter | danger
#           tool = works at EVERY prompt, even inside a flow (print, loadtime)
#
# Menus never copy these. A menu's .map either wires an ID from here
# ("p-  .mapto()  p-  from bashbasicsbyvk_maincommands.sh"), replaces it with its own, or blocks it.

# ── go somewhere ───────────────────────────────────────────────
cmd_def q        exact  bvk_main_exec  nav    "Close the app"
cmd_def u        exact  -              act    "Up one folder / back"
cmd_def h        exact  bvk_main_exec  nav    "Home — recents, bookmarks, favourites"
cmd_def s        exact  bvk_main_exec  nav    "Settings"
cmd_def i        exact  bvk_main_exec  nav    "Infinity stones — extra tools"
cmd_def -h       exact  bvk_main_exec  nav    "Help"
cmd_def -u       exact  -              act    "Upgrade loop"
cmd_def -auth    exact  bvk_main_exec  nav    "Account, billing, credits"
cmd_def cd       exact  -              act    "Open a shell in this folder"
cmd_def goto     word   -              act    "Go to a path — asks where; the list moves there"  "goto /sdcard/Download"
# ── inner loops ────────────────────────────────────────────────
cmd_def sw       exact  -              act    "Switch — recents & tabs"
cmd_def fx       exact  -              act    "Functions (fx) — CSV-driven actions"
cmd_def api      exact  -              act    "Links manager (FileAPI)"
cmd_def bk       exact  -              act    "Backups"
cmd_def sv       exact  -              act    "Saved surf"
cmd_def sn       exact  -              act    "Snapshots"
cmd_def pn       exact  -              act    "Pending uploads — continue, pause, resume, stop"
cmd_def rbam     exact  -              act    "Roles & access"
cmd_def nf       exact  -              act    "Notifications"
cmd_def cs       exact  -              act    "Cloud surf"
cmd_def gd       word   -              act    "Google Drive"
cmd_def gdx      exact  -              act    "Leave Google Drive"
# ── act on the files listed here ───────────────────────────────
cmd_def c        exact  -              act    "Create files / folders"
cmd_def d        exact  -              act    "Delete items"
cmd_def r        exact  -              act    "Rename items"
cmd_def t        exact  -              act    "Transfer — copy / move, Google Drive"
cmd_def f        exact  -              act    "Find"
cmd_def z        exact  -              act    "Organise by year, month, extension…"
cmd_def fs       exact  -              act    "Force-show every item (big folder)"
cmd_def forceshow exact -              act    "Force-show every item (big folder)"
cmd_def ns       exact  -              act    "Back to the normal listing"
cmd_def fa       word   -              act    "Favourite — add an alias"  "fa 3"
cmd_def rf       exact  bvk_main_exec  util   "Refresh — the main list reloads the shell, every other screen redraws"
cmd_def l-       prefix -              act    "Lock items"               "l-1,3"
cmd_def ul-      prefix -              act    "Unlock items"             "ul-1,3"
cmd_def z-       prefix -              act    "Zip items"                "z-1,3"
cmd_def uz-      prefix -              act    "Unzip items"              "uz-2"
cmd_def p-       prefix -              act    "Project map of a path"    "p-1"
cmd_def eb-      prefix -              act    "Exact bytes of items (binary + data units) — copy or save to Excel"  "eb-1-5"
cmd_def xtr-     prefix -              act    "Extract lines / words / characters / bytes from files (files only)"  "xtr-1,3"
cmd_def i-       prefix -              act    "Info of files (size, words, lines, dates…) — files only, copy or save to Excel"  "i-1,3"
# ── staging ────────────────────────────────────────────────────
cmd_def c-       prefix -              act    "Stage COPY"               "c-1,3"
cmd_def m-       prefix -              act    "Stage MOVE"               "m-1,3"
cmd_def k-       prefix -              act    "Stage SHORTCUT"           "k-1,3"
cmd_def b-       prefix -              act    "Stage BOOKMARK"           "b-1,3"
cmd_def s-       prefix -              act    "Stage SELECT (a set for fx → <action>.selected.items)" "s-1,3 as set1"
cmd_def d-       word   -              act    "Apply staged items HERE   (d- set1 = only that set)" "d- set1"
cmd_def v-       exact  -              act    "View staged items and sets"
# ── FileAPI ────────────────────────────────────────────────────
cmd_def do-      exact  -              act    "Download from a link"
cmd_def c2c-     prefix -              act    "Cloud-to-cloud upload"    "c2c-1"
cmd_def up-      prefix -              act    "Upload — expiring link"   "up-1"
cmd_def ux-      prefix -              act    "Share with a user"        "ux-1"
cmd_def save-    prefix -              act    "Save upload"              "save-1"
cmd_def snap-    prefix -              act    "Add to snapshots"         "snap-1"
cmd_def scr-sync exact  -              act    "Sync the shortcut registry"
# ── selection & display rules ──────────────────────────────────
cmd_def =        prefix -              filter "Filter the list live (== searches sub-folders)" "=png"
cmd_def .s       word   -              act    "Select by expression"     ".s.ext png"
cmd_def .us      word   -              act    "Un-select by expression"  ".us.ext png"
cmd_def .r       word   -              act    "Rule book"
cmd_def .d       word   -              act    "Display only what matches" ".d.ext py"
cmd_def .dm      word   -              act    "Background daemon"
cmd_def .ai      word   -              act    "Ask the AI for a command" ".ai delete all pyc"
# ── tools ──────────────────────────────────────────────────────
cmd_def health   exact  bvk_main_exec  util   "What is active on this machine"
cmd_def lang     exact  bvk_main_exec  util   "Which engines run: Drill (C or Python) · FileAPI (Go or Node) · Find & Replace (C or Python)"
cmd_def disk     exact  bvk_main_exec  util   "Disk usage"
cmd_def ram      exact  bvk_main_exec  util   "Memory usage"
cmd_def clear    exact  bvk_main_exec  util   "Forget the command cache (hash -r)"
cmd_def sast     exact  bvk_main_exec  util   "Static security scan"
cmd_def print    exact  bvk_main_exec  tool   "Print what is on screen — copy it or save as txt"
cmd_def loadtime word   bvk_main_exec  tool   "Load time: what each screen change cost (loadtime 2 · loadtime all)"
cmd_def cc       exact  bvk_main_exec  tool   "Cheat codes — pick a command, it lands in the prompt"
cmd_def kl       exact  bvk_main_exec  util   "Kill every process of this user (kill -9 -1)"
