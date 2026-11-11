# handle_version <tag> — the run loop for a VERSION picked in the upgrade menu (-u), the sibling of handle_file.
#   📄 Version selected: v0.0.149
#   0) Install   1) Info        u) Up   q) Quit   h) Home
# It reuses the upgrade loop's own pieces (_upg_do_install, _upg_info_one, _upg_fetch_commit), the menu chrome (_mc_*)
# and the file menu's footer (@file_menu), so nothing is written twice.
# Install does not ask "Continue?": picking 0 here IS the confirmation. After a good install _upg_do_install ends the program (exit 0):
# the running copy is the old version, so the next thing to do is start  o  again anyway.
handle_version() {
    local tag="$1" action
    while true; do
        _mc_header "📄 Version selected: $tag" \
                   "What would you like to do with the version?"
        _mc_options 0 "Install" "Info"
        _mc_footer @file_menu

        read -e -p "Select: " action || return 1          # EOF (the terminal closed): leave, never spin on "invalid"

        case "$action" in
            0) _upg_do_install "$tag" "$tag" yes; return 1 ;;   # a good install exits (0) inside it
            1) _hv_info "$tag"; return 1 ;;
            u|U) return 1 ;;
            h|H) home_menu; return 1 ;;
            q|Q) _bvk_quit; return 1 ;;
            *) _bvk_invalid ;;
        esac
    done
}

# Info for ONE version: the same screen as i-N in the upgrade menu (printed, then save in Excel / copy it).
_hv_info() {
    _upg_cmd_info_many "$_UPG_PICK_N"
}
