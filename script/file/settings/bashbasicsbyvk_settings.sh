CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk"
SETTINGS_FILE="$CONFIG_DIR/config"
mkdir -p "$CONFIG_DIR"

DEFAULT_SHOW_HIDDEN_FILES=false
DEFAULT_INDEX_MODE_THRESHOLD=200
DEFAULT_RENAME_CSV_ABOVE=5          # r: more selected items than this are handed to the CSV rename (rename.select.items.csv); 0 = never
DEFAULT_RENAME_NOEXT_MODE="ask"      # r: a new name typed WITHOUT an extension: old (keep the old one) · none (create without) · ask
DEFAULT_NANO_WRAP="nowrap"         # nano long lines:  wrap (soft-wrap on screen, at blanks) | nowrap (one line, scroll sideways); written to nanorc by bvk_nano_wrap_apply
DEFAULT_TERMINAL_BG_COLOR="000000"
DEFAULT_TERMINAL_TEXT_COLOR_NORMAL="FFFFFF"
DEFAULT_TERMINAL_TEXT_COLOR_CODER="00D000"

DEFAULT_SORT_MODE="az"
DEFAULT_MENU_SORT_STR=""          # menu-specific sort orders ("links=az backup=exp_long"); see bashbasicsbyvk_menu_sort.sh
DEFAULT_DISPLAY_SUFFIX_SET=""
DEFAULT_DISPLAY_TIME_FORMAT="full"
DEFAULT_GROUP_VIEW_LEVELS=""
DEFAULT_COMPRESS_FORMAT="ask"
DEFAULT_UPLOAD_HIDDEN_MODE="follow"   # up- : follow | always | never | ask
DEFAULT_ZIP_HIDDEN_MODE="follow"      # z-  : follow | always | never | ask
DEFAULT_UX_HIDDEN_MODE="follow"       # ux- : follow | always | never | ask
DEFAULT_FILTER_MODE="partial"
DEFAULT_FILTER_HIDDEN_MODE="respect"
DEFAULT_FILTER_RECURSIVE=false      # = filter looks only in the folder you are viewing
DEFAULT_DISPLAY_FILTER_PERSIST=false
DEFAULT_ANIM_OUTER="pop"       # outer loop: whole screen appears at once
DEFAULT_MOUSE_MODE="on"         # click / tap an item number, double click / double tap = open it:  on | off  (see bashbasicsbyvk_mouse.sh)
DEFAULT_ANIM_INNER="carpet"    # inner loops (fx / sw)  (draws instantly, same as pop)
DEFAULT_NUKE_TIME_SECONDS=3600   # up- / c2c-: how long a new link lives (1 hour). 60 s .. 30 days
DEFAULT_UX_NUKE_TIME_SECONDS=2592000   # ux-: how long a new share lives (30 days). 60 s .. 30 days
DEFAULT_APP_TIMEZONE=""          # "" = follow the system clock; else an IANA name, e.g. Asia/Kolkata
# ── fileapi services ─────────────────────────────────────────────────────────
DEFAULT_CREDIT_PROMPTS="show"             # show = price check before every upload (cost 1 stays silent) · skip = never ask, just go
DEFAULT_BACKUP_MODE="yes"                 # back up to the cloud before a delete:  yes | no | ask
DEFAULT_BACKUP_NUKE_TIME_SECONDS=2592000  # how long a backup is kept (30 days). 60 s .. 30 days
DEFAULT_SAVED_NUKE_TIME_SECONDS=2592000   # save-: how long a saved item is kept (30 days). 60 s .. 30 days
DEFAULT_SNAPSHOT_ENABLED="on"             # background snapshots while o runs:  on | off
DEFAULT_SNAPSHOT_INTERVAL_SECONDS=3600    # how often (1 hour). 1 minute .. 30 days
DEFAULT_SNAPSHOT_KEEP_SECONDS=604800      # how long each snapshot is kept (7 days). 60 s .. 30 days

# Buffers (c- m- k- b- s-): what to do when  c-1,3 as set1  names a set that is already in that buffer:  add | replace | deny | ask
DEFAULT_BUFFER_CONFLICT_CP="ask"
DEFAULT_BUFFER_CONFLICT_MV="ask"
DEFAULT_BUFFER_CONFLICT_SC="ask"
DEFAULT_BUFFER_CONFLICT_BM="ask"
DEFAULT_BUFFER_CONFLICT_SL="ask"

# Find & replace (f): see bashbasicsbyvk_findsettings.sh
DEFAULT_FIND_CASE_MODE="ask"
DEFAULT_FIND_REGEX_MODE="off"
DEFAULT_FIND_DEPTH_MODE="ask"
DEFAULT_FIND_WORD_MODE="off"
DEFAULT_FIND_HIDDEN_MODE="follow"
DEFAULT_FIND_TARGET_MODE="both"
DEFAULT_FIND_BINARY_MODE="skip"
DEFAULT_FIND_VCS_MODE="skip"
DEFAULT_FIND_CONFIRM_MODE="preview"
DEFAULT_FIND_INPUT_MODE="ask"
DEFAULT_FIND_MAXSIZE_MB="200"
DEFAULT_FIND_SHOW_LIMIT="300"
DEFAULT_FIND_THREADS="auto"
# Transfer speed (up- / do- / pending): MB per encrypted chunk x parallel streams.  Limits are the same in the worker (TRANSFER_LIMITS) and bvk-xfer (netx.go).
DEFAULT_XFER_CHUNK_MB="4"
DEFAULT_XFER_STREAMS="16"
XFER_MIN_CHUNK_MB=1; XFER_MAX_CHUNK_MB=64; XFER_MAX_STREAMS=64; XFER_MAX_INFLIGHT_MB=512

unset show_hidden_files
unset index_mode_threshold
unset terminal_bg_color
unset terminal_text_color
unset sort_mode
unset menu_sort_str
unset display_suffix_set
unset display_time_format
unset group_view_levels_str
unset compress_format
unset upload_hidden_mode
unset zip_hidden_mode
unset ux_hidden_mode
unset filter_mode
unset filter_hidden_mode
unset filter_recursive
unset display_filter_persist
unset anim_outer
unset anim_inner
unset mouse_mode
unset nano_wrap
unset nuke_time_seconds
unset ux_nuke_time_seconds
unset app_timezone
unset credit_prompts
unset backup_mode
unset backup_nuke_time_seconds
unset saved_nuke_time_seconds
unset snapshot_enabled
unset snapshot_interval_seconds
unset snapshot_keep_seconds
unset buffer_conflict_cp
unset buffer_conflict_mv
unset buffer_conflict_sc
unset buffer_conflict_bm
unset buffer_conflict_sl
unset find_case_mode
unset find_regex_mode
unset find_depth_mode
unset find_word_mode
unset find_hidden_mode
unset find_target_mode
unset find_binary_mode
unset find_vcs_mode
unset find_confirm_mode
unset find_input_mode
unset find_maxsize_mb
unset find_show_limit
unset find_threads
unset xfer_chunk_mb
unset xfer_streams
unset rename_csv_above
unset rename_noext_mode

# Reads a settings file written by save_settings (key=value or key="value", one per line).
# It is DATA, not code: nothing in the file is ever executed, and only lower-case keys are assigned.
_bvk_settings_read() {
  local _f="$1" _line _k _v
  [ -f "$_f" ] || return 1
  while IFS= read -r _line || [ -n "$_line" ]; do
    [[ "$_line" =~ ^([a-z][a-z0-9_]*)=(.*)$ ]] || continue
    _k="${BASH_REMATCH[1]}"; _v="${BASH_REMATCH[2]}"
    if [[ "$_v" == \"*\" && ${#_v} -ge 2 ]]; then _v="${_v:1:${#_v}-2}"; fi
    printf -v "$_k" '%s' "$_v"
  done < "$_f"
  return 0
}

[ -f "$SETTINGS_FILE" ] && _bvk_settings_read "$SETTINGS_FILE"

: "${show_hidden_files:=$DEFAULT_SHOW_HIDDEN_FILES}"
: "${index_mode_threshold:=$DEFAULT_INDEX_MODE_THRESHOLD}"
: "${terminal_bg_color:=$DEFAULT_TERMINAL_BG_COLOR}"
: "${terminal_text_color:=$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL}"
: "${sort_mode:=$DEFAULT_SORT_MODE}"
: "${menu_sort_str=$DEFAULT_MENU_SORT_STR}"
[[ "$menu_sort_str" =~ ^[a-z0-9_=\ ]*$ ]] || menu_sort_str=$DEFAULT_MENU_SORT_STR
: "${display_suffix_set:=$DEFAULT_DISPLAY_SUFFIX_SET}"
: "${display_time_format:=$DEFAULT_DISPLAY_TIME_FORMAT}"
: "${group_view_levels_str:=$DEFAULT_GROUP_VIEW_LEVELS}"
: "${compress_format:=$DEFAULT_COMPRESS_FORMAT}"
: "${upload_hidden_mode:=$DEFAULT_UPLOAD_HIDDEN_MODE}"
: "${zip_hidden_mode:=$DEFAULT_ZIP_HIDDEN_MODE}"
: "${ux_hidden_mode:=$DEFAULT_UX_HIDDEN_MODE}"
[[ "$upload_hidden_mode" =~ ^(follow|always|never|ask)$ ]] || upload_hidden_mode=$DEFAULT_UPLOAD_HIDDEN_MODE
[[ "$zip_hidden_mode" =~ ^(follow|always|never|ask)$ ]] || zip_hidden_mode=$DEFAULT_ZIP_HIDDEN_MODE
[[ "$ux_hidden_mode" =~ ^(follow|always|never|ask)$ ]] || ux_hidden_mode=$DEFAULT_UX_HIDDEN_MODE
: "${buffer_conflict_cp:=$DEFAULT_BUFFER_CONFLICT_CP}"
: "${buffer_conflict_mv:=$DEFAULT_BUFFER_CONFLICT_MV}"
: "${buffer_conflict_sc:=$DEFAULT_BUFFER_CONFLICT_SC}"
: "${buffer_conflict_bm:=$DEFAULT_BUFFER_CONFLICT_BM}"
: "${buffer_conflict_sl:=$DEFAULT_BUFFER_CONFLICT_SL}"
for _bc in cp mv sc bm sl; do
  _bcv="buffer_conflict_$_bc"; _bcd="DEFAULT_BUFFER_CONFLICT_${_bc^^}"
  [[ "${!_bcv}" =~ ^(add|replace|deny|ask)$ ]] || printf -v "$_bcv" '%s' "${!_bcd}"
done
unset _bc _bcv _bcd
: "${filter_mode:=$DEFAULT_FILTER_MODE}"
: "${filter_hidden_mode:=$DEFAULT_FILTER_HIDDEN_MODE}"
: "${filter_recursive:=$DEFAULT_FILTER_RECURSIVE}"
[[ "$filter_recursive" == true || "$filter_recursive" == false ]] || filter_recursive=$DEFAULT_FILTER_RECURSIVE
: "${display_filter_persist:=$DEFAULT_DISPLAY_FILTER_PERSIST}"
: "${anim_outer:=$DEFAULT_ANIM_OUTER}"
: "${anim_inner:=$DEFAULT_ANIM_INNER}"
: "${mouse_mode:=$DEFAULT_MOUSE_MODE}"
: "${nano_wrap:=$DEFAULT_NANO_WRAP}"
: "${nuke_time_seconds:=$DEFAULT_NUKE_TIME_SECONDS}"
: "${ux_nuke_time_seconds:=$DEFAULT_UX_NUKE_TIME_SECONDS}"
: "${app_timezone=$DEFAULT_APP_TIMEZONE}"
: "${credit_prompts:=$DEFAULT_CREDIT_PROMPTS}"
: "${backup_mode:=$DEFAULT_BACKUP_MODE}"
: "${backup_nuke_time_seconds:=$DEFAULT_BACKUP_NUKE_TIME_SECONDS}"
: "${saved_nuke_time_seconds:=$DEFAULT_SAVED_NUKE_TIME_SECONDS}"
: "${snapshot_enabled:=$DEFAULT_SNAPSHOT_ENABLED}"
: "${snapshot_interval_seconds:=$DEFAULT_SNAPSHOT_INTERVAL_SECONDS}"
: "${snapshot_keep_seconds:=$DEFAULT_SNAPSHOT_KEEP_SECONDS}"
[[ "$credit_prompts" =~ ^(show|skip)$ ]] || credit_prompts=$DEFAULT_CREDIT_PROMPTS
[[ "$backup_mode" =~ ^(yes|no|ask)$ ]] || backup_mode=$DEFAULT_BACKUP_MODE
[[ "$snapshot_enabled" =~ ^(on|off)$ ]] || snapshot_enabled=$DEFAULT_SNAPSHOT_ENABLED
for _sv in backup_nuke_time_seconds saved_nuke_time_seconds snapshot_keep_seconds; do
  if ! [[ "${!_sv}" =~ ^[0-9]{1,9}$ ]] || [ "${!_sv}" -lt 60 ] || [ "${!_sv}" -gt 2592000 ]; then
    case "$_sv" in
      backup_nuke_time_seconds) backup_nuke_time_seconds=$DEFAULT_BACKUP_NUKE_TIME_SECONDS ;;
      saved_nuke_time_seconds)  saved_nuke_time_seconds=$DEFAULT_SAVED_NUKE_TIME_SECONDS ;;
      snapshot_keep_seconds)    snapshot_keep_seconds=$DEFAULT_SNAPSHOT_KEEP_SECONDS ;;
    esac
  fi
done
unset _sv
if ! [[ "$snapshot_interval_seconds" =~ ^[0-9]{1,9}$ ]] || [ "$snapshot_interval_seconds" -lt 60 ] || [ "$snapshot_interval_seconds" -gt 2592000 ]; then
  snapshot_interval_seconds=$DEFAULT_SNAPSHOT_INTERVAL_SECONDS
fi
if ! [[ "$nuke_time_seconds" =~ ^[0-9]{1,9}$ ]] || [ "$nuke_time_seconds" -lt 60 ] || [ "$nuke_time_seconds" -gt 2592000 ]; then
  nuke_time_seconds=$DEFAULT_NUKE_TIME_SECONDS
fi
if ! [[ "$ux_nuke_time_seconds" =~ ^[0-9]{1,9}$ ]] || [ "$ux_nuke_time_seconds" -lt 60 ] || [ "$ux_nuke_time_seconds" -gt 2592000 ]; then
  ux_nuke_time_seconds=$DEFAULT_UX_NUKE_TIME_SECONDS
fi
[[ "$anim_outer" == pop || "$anim_outer" == carpet ]] || anim_outer=$DEFAULT_ANIM_OUTER
[[ "$anim_inner" == pop || "$anim_inner" == carpet ]] || anim_inner=$DEFAULT_ANIM_INNER
[[ "$mouse_mode" == on || "$mouse_mode" == off ]] || mouse_mode=$DEFAULT_MOUSE_MODE
[[ "$nano_wrap" == wrap || "$nano_wrap" == nowrap ]] || nano_wrap=$DEFAULT_NANO_WRAP

# ════════════════════════════════════════════════════════════════════════════
#  Timezone  (Settings → Timezone)
#  One setting, used everywhere: the app exports it as  TZ , so every  date  call, every python3 / node
#  helper and every child process the app starts shows and parses local time in that zone. The recents
#  daemon is a separate long-running process, so it reads  app_timezone  from the config file itself.
#  Machine-readable stamps stay in UTC on purpose (CREATED=…Z, telemetry day) and epochs are zone-free.
#  Empty = follow the system clock exactly as before.
# ════════════════════════════════════════════════════════════════════════════
if [ -z "${_BVK_TZ_CAPTURED+x}" ]; then       # remember what the shell came with (first load only)
  _BVK_TZ_CAPTURED=1
  if [ -n "${TZ+x}" ]; then _BVK_TZ_ORIG_SET=1; _BVK_TZ_ORIG="$TZ"; else _BVK_TZ_ORIG_SET=0; _BVK_TZ_ORIG=""; fi
fi

_TZ_DIRS=("${TZDIR:-}" /usr/share/zoneinfo /usr/lib/zoneinfo /usr/share/lib/zoneinfo /etc/zoneinfo "${PREFIX:-}/share/zoneinfo")

# "UTC+05:30" → POSIX "<+0530>-5:30".  This fixed-offset form (no daylight saving) is the manual fallback
# used when the computer has no tz database and the person declined to install one; it needs no files.
_tz_posix() {
  local z="$1" sg hh mm inv
  [[ "$z" =~ ^UTC([+-])([0-9]{2}):([0-9]{2})$ ]] || return 1
  sg="${BASH_REMATCH[1]}"; hh="${BASH_REMATCH[2]}"; mm="${BASH_REMATCH[3]}"
  (( 10#$hh > 14 || 10#$mm > 59 )) && return 1
  if (( 10#$hh == 0 && 10#$mm == 0 )); then printf 'UTC0'; return 0; fi
  [ "$sg" = + ] && inv=- || inv=+
  printf '<%s%s%s>%s%d:%s' "$sg" "$hh" "$mm" "$inv" "$((10#$hh))" "$mm"
}

# _tz_valid NAME → 0 when NAME is a real zone on this machine (no paths, no '..', must exist in the tz database)
# or a fixed offset like UTC+05:30
_tz_valid() {
  local z="$1" d
  _tz_posix "$z" >/dev/null && return 0
  [[ "$z" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$ ]] || return 1
  for d in "${_TZ_DIRS[@]}"; do
    [ -n "$d" ] && [ -f "$d/$z" ] && return 0
  done
  # tz data kept somewhere unusual (e.g. Android's single tzdata blob): trust the zone if date resolves it
  # to a real abbreviation instead of echoing the name back
  [[ "$z" == */* ]] && [ "$(TZ="$z" date +%Z 2>/dev/null)" != "${z%%/*}" ] && return 0
  return 1
}

# put the chosen zone into effect for this shell and everything it starts
_apply_timezone() {
  local _p
  if [ -n "${app_timezone:-}" ] && _tz_valid "$app_timezone"; then
    _p=$(_tz_posix "$app_timezone") && export TZ="$_p" || export TZ="$app_timezone"
  elif [ "$_BVK_TZ_ORIG_SET" = 1 ]; then
    export TZ="$_BVK_TZ_ORIG"
  else
    unset TZ
  fi
}

# "IST (UTC+05:30)" — what the clock is showing right now
_tz_short() { local a o; a=$(date +%Z 2>/dev/null); o=$(date +%z 2>/dev/null); printf '%s (UTC%s:%s)' "${a:-?}" "${o:0:3}" "${o:3:2}"; }
# "Asia/Kolkata · IST (UTC+05:30)" / "system default · UTC (UTC+00:00)"
_tz_label() {
  local z="${app_timezone:-system default}"
  if [ -n "${app_timezone:-}" ] && ! _tz_valid "$app_timezone"; then z="system default (unknown zone '${app_timezone:0:40}' ignored)"; fi
  printf '%s · %s' "$z" "$(_tz_short)"
}

_apply_timezone

: "${rename_csv_above:=$DEFAULT_RENAME_CSV_ABOVE}"
[[ "$rename_csv_above" =~ ^[0-9]{1,6}$ ]] || rename_csv_above=$DEFAULT_RENAME_CSV_ABOVE
: "${rename_noext_mode:=$DEFAULT_RENAME_NOEXT_MODE}"
[[ "$rename_noext_mode" =~ ^(old|none|ask)$ ]] || rename_noext_mode=$DEFAULT_RENAME_NOEXT_MODE
: "${find_case_mode:=$DEFAULT_FIND_CASE_MODE}"
[[ "$find_case_mode" =~ ^(ask|exact|any)$ ]] || find_case_mode=$DEFAULT_FIND_CASE_MODE
: "${find_regex_mode:=$DEFAULT_FIND_REGEX_MODE}"
[[ "$find_regex_mode" =~ ^(off|on|ask)$ ]] || find_regex_mode=$DEFAULT_FIND_REGEX_MODE
: "${find_depth_mode:=$DEFAULT_FIND_DEPTH_MODE}"
[[ "$find_depth_mode" =~ ^(ask|flat|recursive)$ ]] || find_depth_mode=$DEFAULT_FIND_DEPTH_MODE
: "${find_word_mode:=$DEFAULT_FIND_WORD_MODE}"
[[ "$find_word_mode" =~ ^(off|on|ask)$ ]] || find_word_mode=$DEFAULT_FIND_WORD_MODE
: "${find_hidden_mode:=$DEFAULT_FIND_HIDDEN_MODE}"
[[ "$find_hidden_mode" =~ ^(follow|include|exclude)$ ]] || find_hidden_mode=$DEFAULT_FIND_HIDDEN_MODE
: "${find_target_mode:=$DEFAULT_FIND_TARGET_MODE}"
[[ "$find_target_mode" =~ ^(both|files|folders)$ ]] || find_target_mode=$DEFAULT_FIND_TARGET_MODE
: "${find_binary_mode:=$DEFAULT_FIND_BINARY_MODE}"
[[ "$find_binary_mode" =~ ^(skip|include)$ ]] || find_binary_mode=$DEFAULT_FIND_BINARY_MODE
: "${find_vcs_mode:=$DEFAULT_FIND_VCS_MODE}"
[[ "$find_vcs_mode" =~ ^(skip|include)$ ]] || find_vcs_mode=$DEFAULT_FIND_VCS_MODE
: "${find_confirm_mode:=$DEFAULT_FIND_CONFIRM_MODE}"
[[ "$find_confirm_mode" =~ ^(preview|direct)$ ]] || find_confirm_mode=$DEFAULT_FIND_CONFIRM_MODE
: "${find_input_mode:=$DEFAULT_FIND_INPUT_MODE}"
[[ "$find_input_mode" =~ ^(ask|single|csv)$ ]] || find_input_mode=$DEFAULT_FIND_INPUT_MODE
: "${find_maxsize_mb:=$DEFAULT_FIND_MAXSIZE_MB}"
[[ "$find_maxsize_mb" =~ ^[0-9]{1,6}$ ]] || find_maxsize_mb=$DEFAULT_FIND_MAXSIZE_MB
: "${find_show_limit:=$DEFAULT_FIND_SHOW_LIMIT}"
[[ "$find_show_limit" =~ ^[0-9]{1,6}$ ]] || find_show_limit=$DEFAULT_FIND_SHOW_LIMIT
: "${find_threads:=$DEFAULT_FIND_THREADS}"
[[ "$find_threads" =~ ^(auto|1|2|4|8)$ ]] || find_threads=$DEFAULT_FIND_THREADS
: "${xfer_chunk_mb:=$DEFAULT_XFER_CHUNK_MB}"
: "${xfer_streams:=$DEFAULT_XFER_STREAMS}"
# a hand-edited file must not get past the limits: anything odd resets BOTH values
if ! [[ "$xfer_chunk_mb" =~ ^[0-9]{1,3}$ && "$xfer_streams" =~ ^[0-9]{1,3}$ ]] \
   || [ "$((10#$xfer_chunk_mb))" -lt "$XFER_MIN_CHUNK_MB" ] || [ "$((10#$xfer_chunk_mb))" -gt "$XFER_MAX_CHUNK_MB" ] \
   || [ "$((10#$xfer_streams))" -lt 1 ] || [ "$((10#$xfer_streams))" -gt "$XFER_MAX_STREAMS" ] \
   || [ "$(( 10#$xfer_chunk_mb * 10#$xfer_streams ))" -gt "$XFER_MAX_INFLIGHT_MB" ]; then
  xfer_chunk_mb=$DEFAULT_XFER_CHUNK_MB; xfer_streams=$DEFAULT_XFER_STREAMS
fi
xfer_chunk_mb=$((10#$xfer_chunk_mb)); xfer_streams=$((10#$xfer_streams))

declare -ga group_view_levels=()
if [ -n "$group_view_levels_str" ]; then
  read -ra group_view_levels <<< "$group_view_levels_str"
fi

save_settings() {
  {
    echo "show_hidden_files=$show_hidden_files"
    echo "index_mode_threshold=$index_mode_threshold"
    echo "terminal_bg_color=$terminal_bg_color"
    echo "terminal_text_color=$terminal_text_color"
    echo "sort_mode=$sort_mode"
    echo "menu_sort_str=\"$menu_sort_str\""
    echo "display_suffix_set=\"$display_suffix_set\""
    echo "display_time_format=$display_time_format"
    echo "group_view_levels_str=\"${group_view_levels[*]}\""
    echo "compress_format=$compress_format"
    echo "upload_hidden_mode=$upload_hidden_mode"
    echo "zip_hidden_mode=$zip_hidden_mode"
    echo "ux_hidden_mode=$ux_hidden_mode"
    echo "buffer_conflict_cp=$buffer_conflict_cp"
    echo "buffer_conflict_mv=$buffer_conflict_mv"
    echo "buffer_conflict_sc=$buffer_conflict_sc"
    echo "buffer_conflict_bm=$buffer_conflict_bm"
    echo "buffer_conflict_sl=$buffer_conflict_sl"
    echo "filter_mode=$filter_mode"
    echo "filter_hidden_mode=$filter_hidden_mode"
    echo "filter_recursive=$filter_recursive"
    echo "display_filter_persist=$display_filter_persist"
    echo "anim_outer=$anim_outer"
    echo "anim_inner=$anim_inner"
    echo "mouse_mode=$mouse_mode"
    echo "nano_wrap=$nano_wrap"
    echo "nuke_time_seconds=$nuke_time_seconds"
    echo "ux_nuke_time_seconds=$ux_nuke_time_seconds"
    echo "app_timezone=\"$app_timezone\""
    echo "credit_prompts=$credit_prompts"
    echo "backup_mode=$backup_mode"
    echo "backup_nuke_time_seconds=$backup_nuke_time_seconds"
    echo "saved_nuke_time_seconds=$saved_nuke_time_seconds"
    echo "snapshot_enabled=$snapshot_enabled"
    echo "snapshot_interval_seconds=$snapshot_interval_seconds"
    echo "snapshot_keep_seconds=$snapshot_keep_seconds"
    echo "find_case_mode=$find_case_mode"
    echo "find_regex_mode=$find_regex_mode"
    echo "find_depth_mode=$find_depth_mode"
    echo "find_word_mode=$find_word_mode"
    echo "find_hidden_mode=$find_hidden_mode"
    echo "find_target_mode=$find_target_mode"
    echo "find_binary_mode=$find_binary_mode"
    echo "find_vcs_mode=$find_vcs_mode"
    echo "find_confirm_mode=$find_confirm_mode"
    echo "find_input_mode=$find_input_mode"
    echo "find_maxsize_mb=$find_maxsize_mb"
    echo "find_show_limit=$find_show_limit"
    echo "find_threads=$find_threads"
    echo "xfer_chunk_mb=$xfer_chunk_mb"
    echo "xfer_streams=$xfer_streams"
    echo "rename_csv_above=$rename_csv_above"
    echo "rename_noext_mode=$rename_noext_mode"
  } > "$SETTINGS_FILE"
}

_GREEN='\033[0;32m'
_RESET='\033[0m'
_BOLD='\033[1m'


# ════════════════════════════════════════════════════════════════════════════
#  Settings menu  (s)
#     type a number to choose · ↑↓ move · space/enter change · u back · q close
#  Every screen below is a  build  function (rows) + an  act  function (what a
#  row does) run by _st_run in bashbasicsbyvk_settings_ui.sh.
# ════════════════════════════════════════════════════════════════════════════

# ── top level ────────────────────────────────────────────────────────────────
_ST_SORT_MODES=(az za new old big small)
_ST_SORT_LABELS=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")

# (the top-level menu is built from groups: see bashbasicsbyvk_settings_groups.sh)

settings_menu() {
  builtin printf '\n'          # breathing space between the main menu and Settings
  _st_run "Settings" _st_top_build _st_top_act
  _st_quit=0
  builtin printf '\n'
}

# ── sort order ───────────────────────────────────────────────────────────────
_st_sort_build() {
  local i
  _st_reset
  for i in "${!_ST_SORT_MODES[@]}"; do
    _st_eq "${_ST_SORT_MODES[$i]}" "$sort_mode"
    _st_add r "${_ST_SORT_LABELS[$i]}" "$_o" "" "${_ST_SORT_MODES[$i]}"
  done
}
_st_sort_act() {
  sort_mode="${_st_tag[$1]}"
  _items_presorted=false
  save_settings
}
sort_order_settings() { _st_run "Sort order" _st_sort_build _st_sort_act; }

# ── file details (what is shown after each name) + time format ───────────────
_ST_SFX_TOKENS=(ext size time children)
_ST_SFX_LABELS=("Extension" "Size" "Modified time" "Item count (folders)")
_ST_TF_KEYS=(year month date datetime monthdate full)
_ST_TF_LABELS=("Year" "Month" "Day" "Day + time" "Month-day + time" "Full date + time")
_ST_TF_EXAMPLES=("2023" "Mar" "15" "15 14:32" "Mar-15 14:32" "2023-Mar-15 14:32")

_st_sfx_build() {
  local i
  _st_reset
  _st_add h "Show after each name"
  for i in "${!_ST_SFX_TOKENS[@]}"; do
    [[ " $display_suffix_set " == *" ${_ST_SFX_TOKENS[$i]} "* ]] && _o=1 || _o=0
    _st_add t "${_ST_SFX_LABELS[$i]}" "$_o" "" "sfx:${_ST_SFX_TOKENS[$i]}"
  done
  _st_add h "Time format"
  for i in "${!_ST_TF_KEYS[@]}"; do
    _st_eq "${_ST_TF_KEYS[$i]}" "$display_time_format"
    _st_add r "${_ST_TF_LABELS[$i]}" "$_o" "${_ST_TF_EXAMPLES[$i]}" "tf:${_ST_TF_KEYS[$i]}"
  done
}
_st_sfx_act() {
  local tag="${_st_tag[$1]}" tok new="" t
  case "$tag" in
    tf:*) display_time_format="${tag#tf:}" ;;
    sfx:*)
      tok="${tag#sfx:}"
      if [[ " $display_suffix_set " == *" $tok "* ]]; then
        for t in $display_suffix_set; do [ "$t" = "$tok" ] || new+="${new:+ }$t"; done
      else
        new="${display_suffix_set:+$display_suffix_set }$tok"
      fi
      display_suffix_set="$new" ;;
  esac
  save_settings
}
display_suffix_settings() { _st_run "File details" _st_sfx_build _st_sfx_act; }

# ── group view (check = level is used; ←/→ changes its position) ─────────────
_ST_GV_LEVELS=(ext year month date)
_ST_GV_LABELS=("Extension" "Year" "Month" "Date")
_ST_ORD=(1st 2nd 3rd 4th)

_st_gv_build() {
  local i j pos
  _st_reset
  for i in "${!_ST_GV_LEVELS[@]}"; do
    pos=""
    for j in "${!group_view_levels[@]}"; do
      [ "${group_view_levels[$j]}" = "${_ST_GV_LEVELS[$i]}" ] && pos="${_ST_ORD[$j]}"
    done
    [ -n "$pos" ] && _o=1 || _o=0
    _st_add t "${_ST_GV_LABELS[$i]}" "$_o" "$pos" "${_ST_GV_LEVELS[$i]}"
  done
}
_st_gv_act() {
  local lvl="${_st_tag[$1]}" key="$2" j pos=-1 other
  local -a new=()
  for j in "${!group_view_levels[@]}"; do
    [ "${group_view_levels[$j]}" = "$lvl" ] && pos=$j
  done
  case "$key" in
    toggle)
      if (( pos >= 0 )); then
        for j in "${!group_view_levels[@]}"; do (( j == pos )) || new+=("${group_view_levels[$j]}"); done
        group_view_levels=("${new[@]}")
      else
        group_view_levels+=("$lvl")
      fi ;;
    left|right)
      (( pos < 0 )) && return
      [ "$key" = left ] && other=$(( pos - 1 )) || other=$(( pos + 1 ))
      (( other < 0 || other >= ${#group_view_levels[@]} )) && return
      new=("${group_view_levels[@]}")
      new[$pos]="${group_view_levels[$other]}"; new[$other]="$lvl"
      group_view_levels=("${new[@]}") ;;
  esac
  group_view_levels_str="${group_view_levels[*]}"
  save_settings
}
# typed commands:  clr = clear all levels · "3,4,2" (or "3 4 2") = use exactly these levels in this order
_st_gv_cmd() {
  local t="${1//,/ }" x
  local -a new=()
  if [ "$1" = clr ]; then
    group_view_levels=()
  elif [[ "$1" == *[,\ ]* && "$t" =~ ^[0-9\ ]+$ ]]; then
    for x in $t; do
      (( 10#$x >= 1 && 10#$x <= ${#_ST_GV_LEVELS[@]} )) || return 1
      [[ " ${new[*]} " == *" ${_ST_GV_LEVELS[$((10#$x-1))]} "* ]] || new+=("${_ST_GV_LEVELS[$((10#$x-1))]}")
    done
    group_view_levels=("${new[@]}")
  else
    return 1
  fi
  group_view_levels_str="${group_view_levels[*]}"
  save_settings
  return 0
}
group_view_settings() {
  _st_run "Group by" _st_gv_build _st_gv_act "←/→ change order" _st_gv_cmd
}

# ── animation ────────────────────────────────────────────────────────────────
_st_anim_build() {
  _st_reset
  _st_add h "Main screens"
  _st_eq "$anim_outer" pop;    _st_add r "pop      (appears at once)"   "$_o" "" o:pop
  _st_eq "$anim_outer" carpet; _st_add r "carpet   (instant too — no delay)" "$_o" "" o:carpet
  _st_add h "Inner loops  (fx / sw)"
  _st_eq "$anim_inner" pop;    _st_add r "pop      (appears at once)"   "$_o" "" i:pop
  _st_eq "$anim_inner" carpet; _st_add r "carpet   (instant too — no delay)" "$_o" "" i:carpet
}
_st_anim_act() {
  case "${_st_tag[$1]}" in
    o:*) anim_outer="${_st_tag[$1]#o:}" ;;
    i:*) anim_inner="${_st_tag[$1]#i:}" ;;
  esac
  save_settings
  declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
}
animation_settings() { _st_run "Animation" _st_anim_build _st_anim_act; }

# ── nuke time (how long a new up- / c2c- link lives) ─────────────────────────
#  Charged UP FRONT for the whole period, so 1 GB for 7 days needs 168 credits in the ledger first.
#  Rate: 1 credit per GB per hour, with a minimum charge by size (0-5 MB: 1 per month, 6-50 MB: 1 per
#  week, 51-500 MB: 1 per day, >500 MB: 1 per hour). Under 1 hour is billed as 1 hour.
#  Change or nuke a link later from  api  (extending charges, shortening / nuking refunds whole days).
# The up- and ux- nuke-time screens are the same screen with other presets / other variable: the two generic functions below do the work,
# _st_nuke_* and _st_uxnuke_* only say which variable (nuke_time_seconds / ux_nuke_time_seconds), presets, labels and wording to use.
# _st_nuke_build_for <var> <presets-array> <labels-array> <"link" | "ux- share">
_st_nuke_build_for() {
  local -n _nv="$1" _np="$2" _nl="$3"
  local i custom=1
  _st_reset
  _st_add h "How long a new $4 lives before it is nuked"
  for i in "${!_np[@]}"; do
    _st_eq "${_np[$i]}" "$_nv"
    [ "$_o" = 1 ] && custom=0
    _st_add r "${_nl[$i]}" "$_o" "" "p:${_np[$i]}"
  done
  _st_add h "Anything else  (1 minute – 30 days; under 1 hour is billed as 1 hour)"
  if [ "$custom" = 1 ]; then
    _st_add r "Custom" 1 "$(_bb_fmt_duration "$_nv")" custom
  else
    _st_add a "Custom…" 0 "" custom
  fi
}
# _st_nuke_act_for <var> <"links" | "ux- shares"> <row>
_st_nuke_act_for() {
  local -n _nv="$1"
  local tag="${_st_tag[$3]}" secs
  case "$tag" in
    p:*) _nv="${tag#p:}"; save_settings ;;
    custom)
      _st_ask "Nuke time, e.g. 90m · 1 day · 2d12h · 1 week" "$(_bb_fmt_duration "$_nv")" || return
      if ! secs=$(_bb_parse_duration "$_st_in"); then
        _st_note "🔴  Could not read '$_st_in' — use a number with a unit (s, m, h, d, w), e.g. 90m or 3 days."
        return
      fi
      if [ "$secs" -lt 60 ] || [ "$secs" -gt 2592000 ]; then
        _st_note "🔴  Nuke time must be between 1 minute and 30 days."
        return
      fi
      _nv="$secs"; save_settings
      if [ "$secs" -lt 3600 ]; then _st_note "💫 $(_bb_fmt_duration "$secs") — billed as 1 hour (the minimum)."
      else _st_note "💫 New $2 will live $(_bb_fmt_duration "$secs")."; fi ;;
  esac
}

_ST_NUKE_PRESETS=(3600 21600 86400 604800 2592000)
_ST_NUKE_LABELS=("1 hour  (default)" "6 hours" "1 day" "7 days" "30 days  (maximum)")

_st_nuke_build() { _st_nuke_build_for nuke_time_seconds _ST_NUKE_PRESETS _ST_NUKE_LABELS "link"; }
_st_nuke_act() { _st_nuke_act_for nuke_time_seconds "links" "$1"; }
nuke_time_settings() { _st_run "Nuke time" _st_nuke_build _st_nuke_act; }

# ── nuke time for ux- shares (default 30 days) ───────────────────────────────
#  Same price list and refund rules as up- links. The whole period is paid up front; the refund (whole days only)
#  happens only when the data is really gone: you nuke the share, or you shorten its nuke time from cloud surf (cs).
_ST_UXNUKE_PRESETS=(86400 604800 1209600 2592000)
_ST_UXNUKE_LABELS=("1 day" "7 days" "14 days" "30 days  (default, maximum)")

_st_uxnuke_build() { _st_nuke_build_for ux_nuke_time_seconds _ST_UXNUKE_PRESETS _ST_UXNUKE_LABELS "ux- share"; }
_st_uxnuke_act() { _st_nuke_act_for ux_nuke_time_seconds "ux- shares" "$1"; }
ux_nuke_time_settings() { _st_run "Nuke time (ux-)" _st_uxnuke_build _st_uxnuke_act; }

# ── reset ────────────────────────────────────────────────────────────────────
_st_reset_build() {
  _st_reset
  _st_add h "Reset every setting to its default"
  _st_add a "Reset  ·  white text"         0 "" normal
  _st_add a "Reset  ·  green (coder) text" 0 "" coder
}
_st_reset_act() {
  show_hidden_files=$DEFAULT_SHOW_HIDDEN_FILES
  index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD
  sort_mode=$DEFAULT_SORT_MODE
  menu_sort_str=$DEFAULT_MENU_SORT_STR
  display_suffix_set=$DEFAULT_DISPLAY_SUFFIX_SET
  display_time_format=$DEFAULT_DISPLAY_TIME_FORMAT
  group_view_levels=(); group_view_levels_str=""
  compress_format=$DEFAULT_COMPRESS_FORMAT
  upload_hidden_mode=$DEFAULT_UPLOAD_HIDDEN_MODE
  zip_hidden_mode=$DEFAULT_ZIP_HIDDEN_MODE
  ux_hidden_mode=$DEFAULT_UX_HIDDEN_MODE
  buffer_conflict_cp=$DEFAULT_BUFFER_CONFLICT_CP
  buffer_conflict_mv=$DEFAULT_BUFFER_CONFLICT_MV
  buffer_conflict_sc=$DEFAULT_BUFFER_CONFLICT_SC
  buffer_conflict_bm=$DEFAULT_BUFFER_CONFLICT_BM
  buffer_conflict_sl=$DEFAULT_BUFFER_CONFLICT_SL
  filter_mode=$DEFAULT_FILTER_MODE
  filter_hidden_mode=$DEFAULT_FILTER_HIDDEN_MODE
  filter_recursive=$DEFAULT_FILTER_RECURSIVE
  display_filter_persist=$DEFAULT_DISPLAY_FILTER_PERSIST
  anim_outer=$DEFAULT_ANIM_OUTER
  anim_inner=$DEFAULT_ANIM_INNER
  mouse_mode=$DEFAULT_MOUSE_MODE
  nano_wrap=$DEFAULT_NANO_WRAP; bvk_nano_wrap_apply --if-present   # only touches a nanorc that already carries our wrap block
  nuke_time_seconds=$DEFAULT_NUKE_TIME_SECONDS
  ux_nuke_time_seconds=$DEFAULT_UX_NUKE_TIME_SECONDS
  app_timezone=$DEFAULT_APP_TIMEZONE; _apply_timezone
  credit_prompts=$DEFAULT_CREDIT_PROMPTS
  backup_mode=$DEFAULT_BACKUP_MODE
  backup_nuke_time_seconds=$DEFAULT_BACKUP_NUKE_TIME_SECONDS
  saved_nuke_time_seconds=$DEFAULT_SAVED_NUKE_TIME_SECONDS
  snapshot_enabled=$DEFAULT_SNAPSHOT_ENABLED
  snapshot_interval_seconds=$DEFAULT_SNAPSHOT_INTERVAL_SECONDS
  snapshot_keep_seconds=$DEFAULT_SNAPSHOT_KEEP_SECONDS
  find_case_mode=$DEFAULT_FIND_CASE_MODE
  find_regex_mode=$DEFAULT_FIND_REGEX_MODE
  find_depth_mode=$DEFAULT_FIND_DEPTH_MODE
  find_word_mode=$DEFAULT_FIND_WORD_MODE
  find_hidden_mode=$DEFAULT_FIND_HIDDEN_MODE
  find_target_mode=$DEFAULT_FIND_TARGET_MODE
  find_binary_mode=$DEFAULT_FIND_BINARY_MODE
  find_vcs_mode=$DEFAULT_FIND_VCS_MODE
  find_confirm_mode=$DEFAULT_FIND_CONFIRM_MODE
  find_input_mode=$DEFAULT_FIND_INPUT_MODE
  find_maxsize_mb=$DEFAULT_FIND_MAXSIZE_MB
  find_show_limit=$DEFAULT_FIND_SHOW_LIMIT
  find_threads=$DEFAULT_FIND_THREADS
  xfer_chunk_mb=$DEFAULT_XFER_CHUNK_MB; xfer_streams=$DEFAULT_XFER_STREAMS
  rename_csv_above=$DEFAULT_RENAME_CSV_ABOVE
  rename_noext_mode=$DEFAULT_RENAME_NOEXT_MODE
  _items_presorted=false
  _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR"
  case "${_st_tag[$1]}" in
    coder) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
    *)     _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
  esac
  save_settings
  _st_note "💫 All settings reset"
  _st_back=1
}
restore_all_defaults() { _st_run "Reset all settings" _st_reset_build _st_reset_act; }

# warm up the carpet writer in the background (no cost when both loops use pop)
declare -F _vp_anim_start >/dev/null 2>&1 && _vp_anim_start
