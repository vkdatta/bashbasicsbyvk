# bashbasicsbyvk_renamesettings.sh — Settings → Rename  (used by the rename screen r: bashbasicsbyvk_rename.sh)
# ════════════════════════════════════════════════════════════════════════════
#     Many items → CSV : how many selected items still use the normal one-by-one screen (more go to rename.select.items.csv)
#     No extension     : what a new name typed WITHOUT an extension becomes (old extension · none · ask every time)
#  Needs: bashbasicsbyvk_settings_groups.sh (_st_choice_open _st_run _st_add _st_ask _st_note), bashbasicsbyvk_settings.sh (save_settings).
# ════════════════════════════════════════════════════════════════════════════

_st_rn_build() {
  local lim="more than $rename_csv_above"
  [ "$rename_csv_above" = 0 ] && lim="never (always one by one)"
  _st_reset
  _st_add a "Items before CSV"   0 "$lim"                                                                                              limit
  _st_add a "No extension"       0 "$(_find_lbl "$rename_noext_mode" old "use old extension" none "create without" ask "ask every time")"  noext
  _st_add a "Reset to defaults"  0 ""                                                                                                  reset
}
_st_rn_act() {
  case "${_st_tag[$1]}" in
    limit)
      if _st_ask "Up to how many items one by one? (0 = never use the CSV)" "$rename_csv_above"; then
        if [[ "$_st_in" =~ ^[0-9]{1,6}$ ]]; then rename_csv_above=$_st_in; save_settings
        else _st_note "🔴  Not a valid number"; fi
      fi ;;
    noext) _st_choice_open "No extension" rename_noext_mode "Rename: a new name without an extension" "💫 Saved" \
             ask "Ask every time (default)" old "Use the old extension" none "Create without extension" ;;
    reset) rename_csv_above=$DEFAULT_RENAME_CSV_ABOVE; rename_noext_mode=$DEFAULT_RENAME_NOEXT_MODE; save_settings ;;
  esac
}
rename_group_settings() { _st_run "Rename" _st_rn_build _st_rn_act; }
