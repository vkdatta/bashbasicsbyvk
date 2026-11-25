# bashbasicsbyvk_home.sh — the Home menu  (h in the main loop)
# ════════════════════════════════════════════════════════════════════════════
#     🏠 Home
#      1) Local Surf       back to the normal file browser (what you had before)
#      2) File API Surf  › the online part, one row each:
#                            1) Shared      opens  cs   (Cloud Surf: Given / Received tabs; one row, the two used to be separate)
#                            2) Links       opens  api  (your up-/c2c- links: edit expiry, nuke, refunds)
#                            3) RBAM        opens  rbam (who may receive your files / whose files you may receive)
#                            4) Backup      opens  bk   (copies taken just before a delete: restore, rename, extend, nuke)
#                            5) Saved Surf  opens  sv   (things stored with save-: no link, opens from any device)
#                            6) Snapshots   opens  sn   (watched files/folders of every device, and their snapshots)
#                            7) Pending     opens  pn   (unfinished uploads of the 5 services: continue, pause, resume, stop)
#      3) Loops          › the helpers that do work for you:
#                            1) Switch      opens  sw
#                            2) Functions   opens  fx
#                            3) Rules       opens  r    (the .r rule book)
#      4) Notifications    opens  nf
#      5) Help             opens  -h
#      6) Authenticate     opens  -auth
#
#  Built on the same menu engine as Settings (type a number · ↑↓ · u back · q close), and grouped the way Settings is: a row with a ›
#  opens a smaller screen ("Home › File API Surf").  u there comes back to Home; q closes everything to the main loop.
#  Needs: _st_run/_st_add (settings_ui), _inner_run (o), open_help, auth_menu, recovery_bin_screen / offline_snapshots_screen (recovery.sh).
# ════════════════════════════════════════════════════════════════════════════

_home_build() {
  _st_reset
  _st_add a "Local Surf"    0 "" local
  _st_add a "File API Surf" 0 "" fileapi
  _st_add a "Recovery Bin"  0 "" recoverybin
  _st_add a "Offline Snapshots" 0 "" offlinesnaps
  _st_add a "Loops"         0 "" loops
  _st_add a "Notifications" 0 "" notify
  _st_add a "Help"          0 "" help
  _st_add a "Authenticate"  0 "" auth
}

_home_fapi_build() {
  _st_reset
  _st_add a "Shared"     0 "" shared
  _st_add a "Links"      0 "" links
  _st_add a "RBAM"       0 "" rbam
  _st_add a "Backup"     0 "" backup
  _st_add a "Saved Surf" 0 "" saved
  _st_add a "Snapshots"  0 "" snapshots
  _st_add a "Pending"    0 "" pending
}

_home_loops_build() {
  _st_reset
  _st_add a "Switch"    0 "" switch
  _st_add a "Functions" 0 "" functions
  _st_add a "Rules"     0 "" rules
}

# the rows of both sub screens (File API Surf, Loops) open their menu here
_home_sub_act() {
  case "${_st_tag[$1]}" in
    shared)    _inner_run cs ;;
    links)     _inner_run api ;;
    rbam)      _inner_run rbam ;;
    backup)    _inner_run bk ;;
    saved)     _inner_run sv ;;
    snapshots) _inner_run sn ;;
    pending)   _inner_run pn ;;
    switch)    _inner_run sw ;;
    functions) _inner_run fx ;;
    rules)     _inner_run r ;;
  esac
  [ "${_BVK_TO_MAIN:-0}" = 1 ] && _st_back=1
  return 0
}

_home_fapi_open()  { _st_run "File API Surf" _home_fapi_build  _home_sub_act; }
_home_loops_open() { _st_run "Loops"         _home_loops_build _home_sub_act; }

# u inside a screen opened from Home comes BACK HERE (Home stays open and is redrawn).
# q inside it (_BVK_TO_MAIN, see _bvk_quit) closes Home too: straight to the main loop.
_home_act() {
  case "${_st_tag[$1]}" in
    local)   _st_back=1 ;;                                     # plain file surf = the main loop
    fileapi) _home_fapi_open ;;
    recoverybin)   recovery_bin_screen ;;                      # offline copies made before destructive actions (bashbasicsbyvk_recovery.sh)
    offlinesnaps)  offline_snapshots_screen ;;                 # offline snapshots
    loops)   _home_loops_open ;;
    notify)  _inner_run nf ;;
    help)    open_help ;;
    auth)    auth_menu ;;
    shared|links|rbam|backup|saved|snapshots|pending|switch|functions|rules)
             _home_sub_act "$1" ;;                              # the == search opens a sub screen's row straight from here
  esac
  [ "${_BVK_TO_MAIN:-0}" = 1 ] && _st_back=1
  return 0
}

home_menu() {
  local _icon_keep="${_st_icon:-}" _st_crumb="Home"
  _st_icon="🏠"
  builtin printf '\n'
  _st_run "Home" _home_build _home_act
  _st_quit=0
  _st_icon="$_icon_keep"
  builtin printf '\n'
}
