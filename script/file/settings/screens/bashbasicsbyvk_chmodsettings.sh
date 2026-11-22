# bashbasicsbyvk_chmodsettings.sh — Settings → Change mode  (used by the chmod-N screen: bashbasicsbyvk_chmod.sh)
# ════════════════════════════════════════════════════════════════════════════
#     Folders : when R / W / X is switched on a FOLDER, does the change reach only the folder (off), everything inside it too (on),
#               or is the question asked each time (ask)?
#  Needs: bashbasicsbyvk_settings_groups.sh (_st_choice_open _st_run _st_add), bashbasicsbyvk_settings.sh (save_settings), _find_lbl (bashbasicsbyvk_findsettings.sh).
# ════════════════════════════════════════════════════════════════════════════

_st_cm_build() {
  _st_reset
  _st_add a "Folders (recursive)" 0 "$(_find_lbl "$chmod_recursive_mode" off "the folder only" on "everything inside too" ask "ask every time")" rec
  _st_add a "Reset to defaults"   0 ""                                                                                                              reset
}
_st_cm_act() {
  case "${_st_tag[$1]}" in
    rec)   _st_choice_open "Folders (recursive)" chmod_recursive_mode "Change mode: a switch on a folder" "💫 Saved" \
             off "Only the folder itself (default)" on "The folder and everything inside it" ask "Ask every time" ;;
    reset) chmod_recursive_mode=$DEFAULT_CHMOD_RECURSIVE_MODE; save_settings ;;
  esac
}
chmod_group_settings() { _st_run "Change mode" _st_cm_build _st_cm_act; }
