# bashbasicsbyvk_settings_groups.sh — the Settings menu, grouped
# ════════════════════════════════════════════════════════════════════════════
#     ⚙️ Settings
#      1) Display            hidden · sort · details · group · animation
#      2) Filters            display filter · search filter
#      3) Colors             background · text
#      4) Files & archives   compress · zip hidden
#      5) File API           credits · links · shares · backup · saved · snapshots
#      6) System             timezone · nano settings
#      7) Reset all settings
#
#  Every group is one more screen of the same kind (_st_run); the leaf screens (sort order, nuke time, …) are the
#  ones that always existed. File API holds everything that talks to the cloud, in sub-groups:
#      Credits · Links (up- / c2c-) · Cloud Surf shares (ux-) · Backup · Saved Surf (save-) · Snapshots
#  The "=" filter finds a group by the words in its name, e.g.  =nuke  =sort  =snapshot.
#
#  Needs: bashbasicsbyvk_settings_ui.sh (_st_run _st_add _st_eq _st_ask _st_note), bashbasicsbyvk_settings.sh (save_settings).
# ════════════════════════════════════════════════════════════════════════════

# ── two generic leaf screens: one-of-N choice, and a duration (presets + custom) ─────────────────────────
_ST_CH_VAR=""; _ST_CH_HEAD=""; _ST_CH_VALS=(); _ST_CH_LABELS=(); _ST_CH_DONE=""
_st_ch_build() {
  local i
  _st_reset
  _st_add h "$_ST_CH_HEAD"
  for i in "${!_ST_CH_VALS[@]}"; do
    _st_eq "${_ST_CH_VALS[$i]}" "${!_ST_CH_VAR}"
    _st_add r "${_ST_CH_LABELS[$i]}" "$_o" "" "v:${_ST_CH_VALS[$i]}"
  done
}
_st_ch_act() {
  local tag="${_st_tag[$1]}"
  case "$tag" in
    v:*) printf -v "$_ST_CH_VAR" '%s' "${tag#v:}"; save_settings
         [ -n "$_ST_CH_DONE" ] && _st_note "$_ST_CH_DONE" ;;
  esac
}
# _st_choice_open <title> <variable> <heading> <note-after-change> <value> <label> [<value> <label>]...
_st_choice_open() {
  _ST_CH_VAR="$2"; _ST_CH_HEAD="$3"; _ST_CH_DONE="$4"; _ST_CH_VALS=(); _ST_CH_LABELS=()
  local t="$1"; shift 4
  while [ $# -ge 2 ]; do _ST_CH_VALS+=("$1"); _ST_CH_LABELS+=("$2"); shift 2; done
  _st_run "$t" _st_ch_build _st_ch_act
}

_ST_DU_VAR=""; _ST_DU_HEAD=""; _ST_DU_MIN=60; _ST_DU_MAX=2592000; _ST_DU_NOTE=""; _ST_DU_PRESETS=(); _ST_DU_LABELS=()
_st_du_build() {
  local i custom=1 cur="${!_ST_DU_VAR}"
  _st_reset
  _st_add h "$_ST_DU_HEAD"
  for i in "${!_ST_DU_PRESETS[@]}"; do
    _st_eq "${_ST_DU_PRESETS[$i]}" "$cur"
    [ "$_o" = 1 ] && custom=0
    _st_add r "${_ST_DU_LABELS[$i]}" "$_o" "" "p:${_ST_DU_PRESETS[$i]}"
  done
  _st_add h "Anything else  ($(_bb_fmt_duration "$_ST_DU_MIN") – $(_bb_fmt_duration "$_ST_DU_MAX"))"
  if [ "$custom" = 1 ]; then _st_add r "Custom" 1 "$(_bb_fmt_duration "$cur")" custom
  else _st_add a "Custom…" 0 "" custom; fi
}
_st_du_act() {
  local tag="${_st_tag[$1]}" secs
  case "$tag" in
    p:*) printf -v "$_ST_DU_VAR" '%s' "${tag#p:}"; save_settings ;;
    custom)
      _st_ask "Time, e.g. 90m · 1 day · 2d12h · 1 week" "$(_bb_fmt_duration "${!_ST_DU_VAR}")" || return
      if ! secs=$(_bb_parse_duration "$_st_in"); then
        _st_note "⚠️  Could not read '$_st_in' — use a number with a unit (s, m, h, d, w), e.g. 90m or 3 days."; return
      fi
      if [ "$secs" -lt "$_ST_DU_MIN" ] || [ "$secs" -gt "$_ST_DU_MAX" ]; then
        _st_note "⚠️  Must be between $(_bb_fmt_duration "$_ST_DU_MIN") and $(_bb_fmt_duration "$_ST_DU_MAX")."; return
      fi
      printf -v "$_ST_DU_VAR" '%s' "$secs"; save_settings
      _st_note "✅ $(_bb_fmt_duration "$secs")${_ST_DU_NOTE:+ — $_ST_DU_NOTE}" ;;
  esac
}
# _st_duration_open <title> <variable> <heading> <min> <max> <note> <seconds> <label> [<seconds> <label>]...
_st_duration_open() {
  local t="$1"; _ST_DU_VAR="$2"; _ST_DU_HEAD="$3"; _ST_DU_MIN="$4"; _ST_DU_MAX="$5"; _ST_DU_NOTE="$6"
  _ST_DU_PRESETS=(); _ST_DU_LABELS=()
  shift 6
  while [ $# -ge 2 ]; do _ST_DU_PRESETS+=("$1"); _ST_DU_LABELS+=("$2"); shift 2; done
  _st_run "$t" _st_du_build _st_du_act
}

# ── File API › Credits ───────────────────────────────────────────────────────────────────────────────────
#  The price check before an upload / backup / save / extension.  Cost of 1 credit is never asked about.
credit_prompt_settings() {
  _st_choice_open "Credits" credit_prompts "Before spending credits on a fileapi operation" "" \
    show "Ask first  (default) — cost 1: just go; more: continue · reduce · increase · stop" \
    skip "Don't ask — no price check (the server still stops you when short)"
}

# ── File API › Backup ────────────────────────────────────────────────────────────────────────────────────
backup_mode_settings() {
  _st_choice_open "Backup before delete" backup_mode "Copy to the cloud before anything is deleted (d, delete, fx delete functions)" "" \
    yes "Yes  (default)  —  always back up first; you can name the backup" \
    no  "No  —  delete without a backup" \
    ask "Ask every time"
}
backup_nuke_settings() {
  _st_duration_open "Backup keep time" backup_nuke_time_seconds "How long a backup is kept before it is nuked" 60 2592000 "new backups are kept this long (extend / shorten later in Backup)" \
    86400 "1 day" 604800 "7 days" 1209600 "14 days" 2592000 "30 days  (default, maximum)"
}
_st_grp_backup_build() {
  _st_reset
  _st_add a "Backup before delete" 0 "$backup_mode" mode
  _st_add a "Default nuke time"    0 "$(_bb_fmt_duration "$backup_nuke_time_seconds")" keep
}
_st_grp_backup_act() { case "${_st_tag[$1]}" in mode) backup_mode_settings ;; keep) backup_nuke_settings ;; esac; }
backup_group_settings() { _st_run "Backup" _st_grp_backup_build _st_grp_backup_act; }

# ── File API › Saved Surf ────────────────────────────────────────────────────────────────────────────────
saved_nuke_settings() {
  _st_duration_open "Saved Surf keep time" saved_nuke_time_seconds "How long an item saved with save- is kept before it is nuked" 60 2592000 "new saves are kept this long (extend / shorten later in Saved Surf)" \
    86400 "1 day" 604800 "7 days" 1209600 "14 days" 2592000 "30 days  (default, maximum)"
}

# ── File API › Snapshots ─────────────────────────────────────────────────────────────────────────────────
#  Interval: 1 minute is the floor.  Every snapshot costs credits, so a short interval on a changing folder adds up.
snapshot_enabled_settings() {
  _st_choice_open "Snapshots" snapshot_enabled "Background snapshots (only while o is running)" "" \
    on  "On  (default)  —  watched files/folders are snapshotted every interval while o runs" \
    off "Off  —  paused; your list is kept and resumes when you switch it on"
}
snapshot_interval_settings() {
  _st_duration_open "Snapshot interval" snapshot_interval_seconds "How often a changed file/folder is snapshotted while o runs  (never below 1 minute)" 60 2592000 "takes effect on the next pass" \
    60 "1 minute  (minimum)" 300 "5 minutes" 900 "15 minutes" 1800 "30 minutes" 3600 "1 hour  (default)" 86400 "1 day" 604800 "1 week"
}
snapshot_keep_settings() {
  _st_duration_open "Snapshot keep time" snapshot_keep_seconds "How long each snapshot is kept before it is nuked (paid up front, per snapshot)" 60 2592000 "new snapshots are kept this long" \
    86400 "1 day" 604800 "7 days  (default)" 1209600 "14 days" 2592000 "30 days  (maximum)"
}
_st_grp_snap_build() {
  _st_reset
  _st_add a "Snapshots"      0 "$snapshot_enabled"                                    on
  _st_add a "Interval"       0 "$(_bb_fmt_duration "$snapshot_interval_seconds")"     interval
  _st_add a "Keep time"      0 "$(_bb_fmt_duration "$snapshot_keep_seconds")"         keep
}
_st_grp_snap_act() { case "${_st_tag[$1]}" in on) snapshot_enabled_settings ;; interval) snapshot_interval_settings ;; keep) snapshot_keep_settings ;; esac; }
snapshot_group_settings() { _st_run "Snapshots" _st_grp_snap_build _st_grp_snap_act; }

# ── File API › Links / Cloud Surf shares ─────────────────────────────────────────────────────────────────
_st_grp_links_build() {
  _st_reset
  _st_add a "Nuke time (up-/c2c-)" 0 "$(_bb_fmt_duration "$nuke_time_seconds")" nuke
  _st_add a "Upload hidden (up-)"  0 "$(_hidden_mode_label "$upload_hidden_mode")" uphidden
}
_st_grp_links_act() { case "${_st_tag[$1]}" in nuke) nuke_time_settings ;; uphidden) upload_hidden_settings ;; esac; }
links_group_settings() { _st_run "Links (up- / c2c-)" _st_grp_links_build _st_grp_links_act; }

_st_grp_shares_build() {
  _st_reset
  _st_add a "Nuke time (ux-)"      0 "$(_bb_fmt_duration "$ux_nuke_time_seconds")" uxnuke
  _st_add a "Upload hidden (ux-)"  0 "$(_hidden_mode_label "$ux_hidden_mode")"     uxhidden
}
_st_grp_shares_act() { case "${_st_tag[$1]}" in uxnuke) ux_nuke_time_settings ;; uxhidden) ux_hidden_settings ;; esac; }
shares_group_settings() { _st_run "Cloud Surf shares (ux-)" _st_grp_shares_build _st_grp_shares_act; }

# ── File API ─────────────────────────────────────────────────────────────────────────────────────────────
_st_grp_api_build() {
  local cp="ask first"; [ "$credit_prompts" = skip ] && cp="don't ask"
  _st_reset
  _st_add a "Credits (price check)"   0 "$cp"                                                                   credits
  _st_add a "Links (up- / c2c-)"      0 "$(_bb_fmt_duration "$nuke_time_seconds")"                               links
  _st_add a "Cloud Surf shares (ux-)" 0 "$(_bb_fmt_duration "$ux_nuke_time_seconds")"                            shares
  _st_add a "Backup"                  0 "$backup_mode · $(_bb_fmt_duration "$backup_nuke_time_seconds")"          backup
  _st_add a "Saved Surf (save-)"      0 "$(_bb_fmt_duration "$saved_nuke_time_seconds")"                          saved
  _st_add a "Snapshots"               0 "$snapshot_enabled · every $(_bb_fmt_duration "$snapshot_interval_seconds")" snapshots
}
_st_grp_api_act() {
  case "${_st_tag[$1]}" in
    credits)   credit_prompt_settings ;;
    links)     links_group_settings ;;
    shares)    shares_group_settings ;;
    backup)    backup_group_settings ;;
    saved)     saved_nuke_settings ;;
    snapshots) snapshot_group_settings ;;
  esac
}
fileapi_group_settings() { _st_run "File API" _st_grp_api_build _st_grp_api_act; }

# ── Display ──────────────────────────────────────────────────────────────────────────────────────────────
_st_grp_display_build() {
  local i sl="$sort_mode" gv="off" sx="${display_suffix_set:-none}" hf="hide"
  for i in "${!_ST_SORT_MODES[@]}"; do [ "${_ST_SORT_MODES[$i]}" = "$sort_mode" ] && sl="${_ST_SORT_LABELS[$i]}"; done
  (( ${#group_view_levels[@]} > 0 )) && gv="${group_view_levels[*]}"
  [ "$show_hidden_files" = true ] && hf="show"
  _st_reset
  _st_add a "Hidden files"     0 "$hf"                    hidden
  _st_add a "Sort order"       0 "$sl"                    sort
  _st_add a "File details"     0 "$sx"                    details
  _st_add a "Group by"         0 "$gv"                    group
  _st_add a "Big-folder limit" 0 "$index_mode_threshold"  index
  _st_add a "Animation"        0 "$anim_outer / $anim_inner" anim
}
_st_grp_display_act() {
  case "${_st_tag[$1]}" in
    hidden) hidden_file_settings ;;   sort)  sort_order_settings ;;   details) display_suffix_settings ;;
    group)  group_view_settings ;;    index) index_mode_threshold_settings ;;   anim) animation_settings ;;
  esac
}
display_group_settings() { _st_run "Display" _st_grp_display_build _st_grp_display_act; }

# ── Filters ──────────────────────────────────────────────────────────────────────────────────────────────
_st_grp_filters_build() {
  local dv="off" fv="$filter_mode"
  if declare -F _disp_load >/dev/null 2>&1 && _disp_load; then dv="on"; fi
  [ "$filter_recursive" = true ] && fv="$filter_mode · recursive"
  _st_reset
  _st_add a "Display filter (.d)" 0 "$dv" dfilter
  _st_add a "Search filter (=)"   0 "$fv" filter
}
_st_grp_filters_act() { case "${_st_tag[$1]}" in dfilter) display_filter_settings ;; filter) filter_mode_settings ;; esac; }
filters_group_settings() { _st_run "Filters" _st_grp_filters_build _st_grp_filters_act; }

# ── Colors ───────────────────────────────────────────────────────────────────────────────────────────────
_st_grp_colors_build() {
  _st_reset
  _st_add a "Background color" 0 "#$terminal_bg_color"   bg
  _st_add a "Text color"       0 "#$terminal_text_color" fg
}
_st_grp_colors_act() { case "${_st_tag[$1]}" in bg) terminal_bg_color_settings ;; fg) terminal_text_color_settings ;; esac; }
colors_group_settings() { _st_run "Colors" _st_grp_colors_build _st_grp_colors_act; }

# ── Files & archives ─────────────────────────────────────────────────────────────────────────────────────
_st_grp_files_build() {
  _st_reset
  _st_add a "Compress format" 0 "$compress_format"                                  compress
  _st_add a "Zip hidden (z-)" 0 "$(_hidden_mode_label "$zip_hidden_mode")"          ziphidden
}
_st_grp_files_act() { case "${_st_tag[$1]}" in compress) compress_format_settings ;; ziphidden) zip_hidden_settings ;; esac; }
files_group_settings() { _st_run "Files & archives" _st_grp_files_build _st_grp_files_act; }

# ── System ───────────────────────────────────────────────────────────────────────────────────────────────
_st_grp_system_build() {
  local _tzabbr; printf -v _tzabbr '%(%Z)T' -1
  _st_reset
  _st_add a "Timezone"             0 "${app_timezone:-system} · $_tzabbr" timezone
  _st_add a "Import nano settings" 0 ""                                    nano
}
_st_grp_system_act() {
  case "${_st_tag[$1]}" in
    timezone) timezone_settings ;;
    nano)     import_nanorc_settings; _st_note "✅ nano settings added" ;;
  esac
}
system_group_settings() { _st_run "System" _st_grp_system_build _st_grp_system_act; }

# ── top level ────────────────────────────────────────────────────────────────────────────────────────────
_st_top_build() {
  local hf="hide"; [ "$show_hidden_files" = true ] && hf="show"
  _st_reset
  # the words in a group's name are what the "=" filter matches
  _st_add a "Display (hidden · sort · details · group · animation)"   0 ""                                                     display
  _st_add a "Filters (display filter · search filter)"                0 ""                                                     filters
  _st_add a "Colors (background · text)"                              0 "#$terminal_bg_color / #$terminal_text_color"          colors
  _st_add a "Files & archives (compress · zip hidden)"                0 "$compress_format"                                     files
  _st_add a "File API (credits · links · shares · backup · saved · snapshots)" 0 "$backup_mode · $snapshot_enabled"            fileapi
  _st_add a "System (timezone · nano)"                                0 "${app_timezone:-system}"                              system
  _st_add a "Reset all settings"                                      0 ""                                                     reset
}
_st_top_act() {
  case "${_st_tag[$1]}" in
    display) display_group_settings ;;
    filters) filters_group_settings ;;
    colors)  colors_group_settings ;;
    files)   files_group_settings ;;
    fileapi) fileapi_group_settings ;;
    system)  system_group_settings ;;
    reset)   restore_all_defaults ;;
  esac
}
