# bashbasicsbyvk_home.sh — the Home menu  (h in the main loop)
# ════════════════════════════════════════════════════════════════════════════
#     🏠 Home
#      1) Local Surf       back to the normal file browser (what you had before)
#      2) Cloud Surf       opens  cs   (ux- shares: Given / Received)
#      3) Shared           opens  cs   on the Received tab
#      4) Notifications    opens  nf
#      5) Switch           opens  sw
#      6) Functions        opens  fx
#      7) Rules            opens  r  (the .r rule book)
#      8) Help             opens  -h
#      9) Authenticate     opens  -auth
#     10) Links            opens  api  (your up-/c2c- links: edit expiry, nuke, refunds)
#     11) RBAM             opens  rbam (who may receive your files / whose files you may receive)
#     12) Backup           opens  bk   (copies taken just before a delete: restore, rename, extend, nuke)
#     13) Saved Surf       opens  sv   (things stored with save-: no link, opens from any device)
#     14) Snapshots        opens  sn   (watched files/folders of every device, and their snapshots)
#     15) Pending          opens  pn   (unfinished uploads of the 5 services: continue, pause, resume, stop)
#
#  Built on the same menu engine as Settings (type a number · ↑↓ · u back · q close).
#  Needs: _st_run/_st_add (settings_ui), _inner_run (o), open_help, auth_menu.
# ════════════════════════════════════════════════════════════════════════════

_home_build() {
  _st_reset
  _st_add a "Local Surf"    0 "" local
  _st_add a "Cloud Surf"    0 "" cloud
  _st_add a "Shared"        0 "" shared
  _st_add a "Notifications" 0 "" notify
  _st_add a "Switch"        0 "" switch
  _st_add a "Functions"     0 "" functions
  _st_add a "Rules"         0 "" rules
  _st_add a "Help"          0 "" help
  _st_add a "Authenticate"  0 "" auth
  _st_add a "Links"         0 "" links
  _st_add a "RBAM"          0 "" rbam
  _st_add a "Backup"        0 "" backup
  _st_add a "Saved Surf"    0 "" saved
  _st_add a "Snapshots"     0 "" snapshots
  _st_add a "Pending"       0 "" pending
}

# u inside a screen opened from Home comes BACK HERE (Home stays open and is redrawn).
# q inside it (_BVK_TO_MAIN, see _bvk_quit) closes Home too: straight to the main loop.
_home_act() {
  case "${_st_tag[$1]}" in
    local)     _st_back=1 ;;                                   # plain file surf = the main loop
    cloud)     _inner_run cs ;;
    shared)    _inner_run cs-recv ;;
    notify)    _inner_run nf ;;
    switch)    _inner_run sw ;;
    functions) _inner_run fx ;;
    rules)     _inner_run r ;;
    help)      open_help ;;
    auth)      auth_menu ;;
    links)     _inner_run api ;;
    rbam)      _inner_run rbam ;;
    backup)    _inner_run bk ;;
    saved)     _inner_run sv ;;
    snapshots) _inner_run sn ;;
    pending)   _inner_run pn ;;
  esac
  [ "${_BVK_TO_MAIN:-0}" = 1 ] && _st_back=1
  return 0
}

home_menu() {
  local _icon_keep="${_st_icon:-}"
  _st_icon="🏠"
  builtin printf '\n'
  _st_run "Home" _home_build _home_act
  _st_quit=0
  _st_icon="$_icon_keep"
  builtin printf '\n'
}
