# bashbasicsbyvk_home.sh — the Home menu  (h in the main loop)
# ════════════════════════════════════════════════════════════════════════════
#     🏠 Home
#      1) Local Surf       back to the normal file browser (what you had before)
#      2) Cloud Surf       coming soon
#      3) Shared           coming soon
#      4) Notifications    coming soon
#      5) Switch           opens  sw
#      6) Functions        opens  fx
#      7) Rules            opens  r  (the .r rule book)
#      8) Help             opens  -h
#      9) Authenticate     opens  -auth
#     10) Links            opens  api  (your up-/c2c- links: edit expiry, nuke, refunds)
#
#  Built on the same menu engine as Settings (type a number · ↑↓ · u back · q close).
#  Needs: _st_run/_st_add (settings_ui), _inner_run (o), open_help, auth_menu.
# ════════════════════════════════════════════════════════════════════════════

_home_build() {
  _st_reset
  _st_add a "Local Surf"    0 "" local
  _st_add a "Cloud Surf"    0 "soon" cloud
  _st_add a "Shared"        0 "soon" shared
  _st_add a "Notifications" 0 "soon" notify
  _st_add a "Switch"        0 "" switch
  _st_add a "Functions"     0 "" functions
  _st_add a "Rules"         0 "" rules
  _st_add a "Help"          0 "" help
  _st_add a "Authenticate"  0 "" auth
  _st_add a "Links"         0 "" links
}

_home_act() {
  case "${_st_tag[$1]}" in
    local)     _st_back=1 ;;                                   # plain file surf = the main loop
    cloud)     _st_note "🚧 Cloud Surf is not available yet — feature to be implemented." ;;
    shared)    _st_note "🚧 Shared is not available yet — feature to be implemented." ;;
    notify)    _st_note "🚧 Notifications is not available yet — feature to be implemented." ;;
    switch)    _inner_run sw;  _st_back=1 ;;
    functions) _inner_run fx;  _st_back=1 ;;
    rules)     _inner_run r;   _st_back=1 ;;
    help)      open_help;      _st_back=1 ;;
    auth)      auth_menu;      _st_back=1 ;;
    links)     _inner_run api; _st_back=1 ;;
  esac
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
