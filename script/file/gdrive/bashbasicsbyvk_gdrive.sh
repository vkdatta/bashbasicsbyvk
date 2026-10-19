#!/usr/bin/env bash
# bashbasicsbyvk_gdrive.sh — Google Drive inside the file manager (the session layer)
# ════════════════════════════════════════════════════════════════════════════
#  fx → google_drive_fx → open google drive   picks an rclone profile and opens it here.
#
#  While a Drive is open the main screen shows it exactly like a local folder:
#    • the Drive is mirrored into  ~/.bashbasicsbyvk/gdrive/<profile>/tree/
#      (folders = real folders, files = free placeholders of the right size and date; see bashbasicsbyvk_gd)
#    • every native command works on it:  c  d  r  l-  m-  c-  s-  b-  d-  v-  p-  z  z-  uz-  t  f  up-  ux-  .s  .r  .d  fa
#    • content is downloaded the moment something reads it (open, copy out, zip, upload link ...)
#    • whatever you did is pushed to Google Drive right after (create · delete · rename · move · edit · zip ...)
#    • each profile has its OWN settings, buffers, selection, favourites, locks, rules, bookmarks, shortcut registry,
#      search index and link keys — all under  ~/.bashbasicsbyvk/gdrive/<profile>/  (swapped in on open, back on leave)
#
#  Commands inside an open Drive
#     gd            Drive menu (status · quota · commands)       gdx   leave Google Drive
#     rf            list this Drive folder again from Google     gd.rf same, explicitly
#     gd.scan       list the WHOLE Drive below this folder (folder item counts become real)
#     gd.clean      free disk: downloaded, unchanged files become placeholders again
#     gd.push       push pending changes now                     gd.sw switch to another profile
#
#  Uses: bashbasicsbyvk_loadingbar.sh (_lb_run), bashbasicsbyvk_gd (python), rclone
# ════════════════════════════════════════════════════════════════════════════

_bvk_d="${BASH_SOURCE[0]}"; case "$_bvk_d" in */*) _bvk_d="${_bvk_d%/*}" ;; *) _bvk_d=. ;; esac   # no dirname process
_GD_SRC_DIR="$(cd -- "$_bvk_d" && pwd)"; unset _bvk_d
_GD_BASE="${HOME}/.bashbasicsbyvk/gdrive"

_GD_ACTIVE=0          # 1 while a Drive is open
_GD_PROFILE=""        # folder name of the profile  (safe form of the rclone remote name)
_GD_REMOTE=""         # rclone remote name
_GD_HOME=""           # ~/.bashbasicsbyvk/gdrive/<profile>
_GD_ROOT=""           # <home>/tree   (the mirror)
_GD_ORIG_PATH=""      # where the person was before opening the Drive
_GD_PY=""; _GD_MAIN=""
_GD_FX_LEAVE=0        # set by _gd_enter inside fx: leave the fx menu so the main screen shows the Drive
_GD_HYD_RESOLVE=0     # 1 while an upload handler runs: items it resolves are downloaded first
_gd_vp=""             # result of _gd_view_path
declare -gA _GD_SAVED=()      # state variables swapped out while a Drive is open (name → original value)
declare -gA _GD_SETSAVE=()    # settings swapped out
declare -gA _GD_SYNCED=()     # folder → epoch it was last listed in this session
declare -g  _GD_ENV_HOME_WAS="" _GD_ENV_RULES_WAS=""
_GD_TTL="${BVK_GD_TTL:-120}"

# settings that live in the config file (see save_settings in bashbasicsbyvk_settings.sh)
_GD_SET_VARS=(show_hidden_files index_mode_threshold terminal_bg_color terminal_text_color sort_mode display_suffix_set
  display_time_format group_view_levels_str compress_format upload_hidden_mode zip_hidden_mode ux_hidden_mode filter_mode
  filter_hidden_mode filter_recursive display_filter_persist anim_outer anim_inner nuke_time_seconds
  ux_nuke_time_seconds app_timezone credit_prompts backup_mode backup_nuke_time_seconds saved_nuke_time_seconds
  snapshot_enabled snapshot_interval_seconds snapshot_keep_seconds)

# state kept GLOBAL on purpose (not swapped per profile): upgrades, UDF scripts, the recents daemon, logs
_GD_GLOBAL_TOPS="gdrive upgrade execute recents.list recents.pid recents.log recents_exclude.conf daemon.version daemon.status lastdir health.log index_roots.conf .watchdog_install_attempted"

_mc_footer_register browse_gd u:Up gd:Drive_menu gdx:Leave_Drive rf:Refresh_Drive q:Quit '|' h:Home s:Settings -h:Help -u:Upgrade 2>/dev/null

# ── small helpers ────────────────────────────────────────────────────────────
_gd_safe_name() {
  local s="${1//[^A-Za-z0-9_.-]/_}"
  [ -n "$s" ] || s="_"
  case "$s" in .|..) s="p_$s" ;; esac
  printf '%s' "$s"
}

_gd_in_tree() {            # _gd_in_tree PATH → is PATH inside the open Drive?
  [ "$_GD_ACTIVE" = 1 ] || return 1
  [[ "$1" == "$_GD_ROOT" || "$1" == "$_GD_ROOT"/* ]]
}

_gd_at_root() { [ "$_GD_ACTIVE" = 1 ] && [ "$path" = "$_GD_ROOT" ] && [ -z "$group_prefix" ]; }

# header text for a path: the Drive path instead of the mirror folder
_gd_view_path() {
  _gd_vp="$1"
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then
    case "$1" in
      "$_GD_ROOT")   _gd_vp="☁️  $_GD_REMOTE:/  (Google Drive)" ;;
      "$_GD_ROOT"/*) _gd_vp="☁️  $_GD_REMOTE:/${1#"$_GD_ROOT"/}" ;;
    esac
  fi
}

_gd_locate() {
  [ -n "$_GD_PY" ] && [ -n "$_GD_MAIN" ] && [ -f "$_GD_MAIN" ] && return 0
  _GD_PY="$(command -v python3 || command -v python)"
  [ -n "$_GD_PY" ] || { echo "❌ Google Drive needs Python 3."; return 1; }
  local d
  for d in "${SCRIPT_DIR:-}" "$_GD_SRC_DIR" "$_GD_SRC_DIR/../loops/iloop/fx/google_drive_fx/open_drive"; do
    [ -n "$d" ] && [ -f "$d/bashbasicsbyvk_gd" ] && { _GD_MAIN="$d/bashbasicsbyvk_gd"; return 0; }
  done
  echo "❌ bashbasicsbyvk_gd not found (looked in \$SCRIPT_DIR and $_GD_SRC_DIR)."; return 1
}

_gd_need_rclone() {
  command -v rclone >/dev/null 2>&1 && return 0
  echo "❌ rclone not found in PATH."
  echo "   Install it (README → Rclone), then run  rclone config  and create a Google Drive remote."
  return 1
}

# the python engine for the OPEN profile
_gd_py() { BVK_GD_PROFILE_DIR="$_GD_HOME" BVK_GD_REMOTE="$_GD_REMOTE" "$_GD_PY" "$_GD_MAIN" "$@"; }

_gd_now() { printf '%(%s)T' -1; }

# ═════════════════════════════════════════════════════════════════════════════
#  Per-profile state: configs, buffers, selection, favourites, locks ... (everything the app keeps in
#  ~/.bashbasicsbyvk) is pointed at the profile folder while the Drive is open, and put back on leave.
#  It is generic: ANY variable that holds a path below ~/.bashbasicsbyvk is moved, so state files added
#  later are isolated too.  (Upgrades, UDF scripts and the recents daemon stay global.)
# ═════════════════════════════════════════════════════════════════════════════
_gd_state_enter() {
  local ph="$1" home="${HOME}/.bashbasicsbyvk" line rest v val top new g skip
  _GD_SAVED=()
  while IFS= read -r line; do
    case "$line" in "declare -- "*|"declare -x "*) ;; *) continue ;; esac
    rest="${line#declare -? }"; v="${rest%%=*}"
    [[ "$v" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    case "$v" in _GD_*|HOME|PWD|OLDPWD|path|selected|BASH*|_) continue ;; esac
    val="${!v-}"
    case "$val" in "$home"|"$home"/*) ;; *) continue ;; esac
    top="${val#"$home"}"; top="${top#/}"; top="${top%%/*}"
    skip=0; for g in $_GD_GLOBAL_TOPS; do [ "$top" = "$g" ] && { skip=1; break; }; done
    [ "$skip" = 1 ] && continue
    new="$ph${val#"$home"}"
    _GD_SAVED["$v"]="$val"
    printf -v "$v" '%s' "$new"
  done < <(declare -p 2>/dev/null | grep -F '/.bashbasicsbyvk')
  # python helpers read these instead of ~/.bashbasicsbyvk
  _GD_ENV_HOME_WAS="${BVK_HOME_DIR-__unset__}"; _GD_ENV_RULES_WAS="${BVK_RULES_DIR-__unset__}"
  export BVK_HOME_DIR="$ph" BVK_RULES_DIR="$ph/rules"
  mkdir -p "$ph/buffer" "$ph/rules" "$ph/favourites" "$ph/switch" "$ph/display" 2>/dev/null
}

_gd_state_leave() {
  local v
  for v in "${!_GD_SAVED[@]}"; do printf -v "$v" '%s' "${_GD_SAVED[$v]}"; done
  _GD_SAVED=()
  if [ "$_GD_ENV_HOME_WAS" = "__unset__" ]; then unset BVK_HOME_DIR; else export BVK_HOME_DIR="$_GD_ENV_HOME_WAS"; fi
  if [ "$_GD_ENV_RULES_WAS" = "__unset__" ]; then unset BVK_RULES_DIR; else export BVK_RULES_DIR="$_GD_ENV_RULES_WAS"; fi
}

_gd_settings_reparse() {
  group_view_levels=()
  [ -n "${group_view_levels_str:-}" ] && read -ra group_view_levels <<< "$group_view_levels_str"
  declare -F _apply_timezone >/dev/null 2>&1 && _apply_timezone
  return 0
}

# the profile has its own config file (first time: a copy of the current settings, then they diverge)
_gd_settings_enter() {
  local ph="$1" v
  _GD_SETSAVE=()
  for v in "${_GD_SET_VARS[@]}"; do _GD_SETSAVE["$v"]="${!v-}"; done
  _GD_SETSAVE[__file]="${SETTINGS_FILE:-}"
  SETTINGS_FILE="$ph/config"
  if [ -f "$SETTINGS_FILE" ]; then
    _bvk_settings_read "$SETTINGS_FILE"
  else
    declare -F save_settings >/dev/null 2>&1 && save_settings
  fi
  _gd_settings_reparse
}

_gd_settings_leave() {
  local v
  for v in "${_GD_SET_VARS[@]}"; do printf -v "$v" '%s' "${_GD_SETSAVE[$v]-}"; done
  SETTINGS_FILE="${_GD_SETSAVE[__file]:-$SETTINGS_FILE}"
  _GD_SETSAVE=()
  _gd_settings_reparse
}

_gd_reload_caches() {
  declare -F _lk_load >/dev/null 2>&1 && _lk_load
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  declare -F _filter_reset_state >/dev/null 2>&1 && _filter_reset_state
  _GD_SYNCED=()
}

# ═════════════════════════════════════════════════════════════════════════════
#  Open / leave
# ═════════════════════════════════════════════════════════════════════════════
# _gd_enter REMOTE  → opens the Drive; the main screen then shows it
_gd_enter() {
  local remote="$1" safe ph orig
  _gd_locate || return 1
  _gd_need_rclone || return 1
  safe="$(_gd_safe_name "$remote")"
  ph="$_GD_BASE/$safe"
  if [ "$_GD_ACTIVE" = 1 ]; then
    orig="$_GD_ORIG_PATH"
    _gd_push
    _gd_leave --quiet --nopath
  else
    orig="${_fx_outer_path:-$path}"
  fi
  mkdir -p "$ph/tree" "$ph/tmp" 2>/dev/null || { echo "❌ Cannot create $ph"; return 1; }
  chmod 700 "$_GD_BASE" "$ph" 2>/dev/null
  printf '%s\n' "$remote" > "$ph/remote"
  _GD_PROFILE="$safe"; _GD_REMOTE="$remote"; _GD_HOME="$ph"; _GD_ROOT="$ph/tree"; _GD_ORIG_PATH="$orig"
  _gd_state_enter "$ph"
  _gd_settings_enter "$ph"
  _GD_ACTIVE=1
  if ! _gd_py sync "$_GD_ROOT" --force; then
    echo "❌ Could not open Google Drive '$remote' (see message above)."
    echo "   Check it with:  rclone lsd $remote:   — if the login expired:  rclone config reconnect $remote:"
    _gd_leave --quiet
    return 1
  fi
  _GD_SYNCED["$_GD_ROOT"]="$(_gd_now)"
  _gd_reload_caches
  _GD_SYNCED["$_GD_ROOT"]="$(_gd_now)"
  printf '%s\n' "$(_gd_now)" > "$ph/.last" 2>/dev/null
  path="$_GD_ROOT"; group_prefix=""; force_show=false
  _fx_outer_path="$_GD_ROOT"      # inside fx: the outer path becomes the Drive, so closing fx lands in it
  _GD_FX_LEAVE=1
  echo "☁️  Google Drive '$remote' is open — gd: Drive menu · gdx: leave"
  return 0
}

# _gd_leave [--quiet] [--nopath]
_gd_leave() {
  local quiet=0 nopath=0 a
  for a in "$@"; do case "$a" in --quiet) quiet=1 ;; --nopath) nopath=1 ;; esac; done
  [ "$_GD_ACTIVE" = 1 ] || { [ "$quiet" = 1 ] || echo "ℹ️  No Google Drive is open."; return 0; }
  [ "$nopath" = 1 ] || _gd_push
  local remote="$_GD_REMOTE" orig="$_GD_ORIG_PATH"
  _gd_settings_leave
  _gd_state_leave
  _GD_ACTIVE=0; _GD_PROFILE=""; _GD_REMOTE=""; _GD_HOME=""; _GD_ROOT=""
  _gd_reload_caches
  if [ "$nopath" = 0 ]; then
    [ -d "$orig" ] || orig="$HOME"
    path="$orig"; group_prefix=""; force_show=false
  fi
  [ "$quiet" = 1 ] || echo "↩️  Left Google Drive '$remote' — back to $orig"
  return 0
}

# before the app execs a shell (q after a switch): push, and land in a real folder
_gd_before_exec() { [ "$_GD_ACTIVE" = 1 ] && _gd_leave --quiet; return 0; }
_gd_on_exit()     { [ "$_GD_ACTIVE" = 1 ] && _gd_push; return 0; }

# ═════════════════════════════════════════════════════════════════════════════
#  Sync with Google Drive
# ═════════════════════════════════════════════════════════════════════════════
_gd_push() {                       # make Drive match what was done in the mirror
  [ "$_GD_ACTIVE" = 1 ] || return 0
  _gd_py push
}

_gd_sync() {                       # _gd_sync PATH [force]   (list one folder; cached for _GD_TTL seconds)
  local p="$1" force="${2:-}" now last
  _gd_in_tree "$p" || return 0
  now="$(_gd_now)"; last="${_GD_SYNCED[$p]:-0}"
  if [ -z "$force" ] && [ $(( now - last )) -lt "$_GD_TTL" ]; then return 0; fi
  if _gd_py sync "$p" ${force:+--force}; then
    _GD_SYNCED["$p"]="$now"
    return 0
  fi
  return 1
}

# one turn of the main loop: push what the last command changed, then make sure this folder is listed
_gd_cycle() {
  [ "$_GD_ACTIVE" = 1 ] || return 0
  if ! _gd_in_tree "$path"; then          # left the Drive by another road (sw bookmark, h, recents ...)
    _gd_leave --quiet --nopath
    echo "↩️  Left Google Drive (you moved to a local folder)"
    return 0
  fi
  case "${choice:-}" in
    ""|u|[0-9]*|fs|ns|forceshow|=*|-h|h) ;;         # pure navigation: nothing to push (opening a file pushes itself)
    *) _gd_push ;;
  esac
  if [ ! -d "$path" ]; then               # the folder vanished (deleted in Drive / moved)
    while [ "$path" != "$_GD_ROOT" ] && [ ! -d "$path" ]; do path="$(dirname "$path")"; done
    group_prefix=""
  fi
  if ! _gd_sync "$path"; then
    if [ ! -d "$path" ]; then path="$_GD_ROOT"; group_prefix=""; fi
  fi
  return 0
}

# rf inside a Drive: list this folder again from Google
_gd_refresh() {
  _gd_push
  _GD_SYNCED=()
  _gd_sync "${1:-$path}" force
}

# download (hydrate) what is inside the Drive among the given paths; others are ignored
_gd_hydrate() {
  [ "$_GD_ACTIVE" = 1 ] || return 0
  local -a list=(); local p
  for p in "$@"; do _gd_in_tree "$p" && list+=("$p"); done
  [ "${#list[@]}" -gt 0 ] || return 0
  _gd_py hydrate "${list[@]}"
}

# fx / bookmarks: keep the folders-first order of Google Drive (folders, then files)
_gd_order_items() {
  [ "${_GD_ACTIVE:-0}" = 1 ] || return 0
  [ "${#items[@]}" -gt 1 ] || return 0
  local -a d=() f=(); local it
  for it in "${items[@]}"; do if [ -d "$it" ]; then d+=("$it"); else f+=("$it"); fi; done
  items=("${d[@]}" "${f[@]}")
}

# ═════════════════════════════════════════════════════════════════════════════
#  Wrapping the native functions that READ content (everything that only moves names needs nothing)
#    open / edit / run a file      → download first, push the edit after
#    c- copy inside the Drive      → server-side copy (nothing is downloaded)
#    copy / move OUT of the Drive  → download first
#    z- / uz- / up- / ux- / c2c- / rclone with a Drive file as the source → download first
# ═════════════════════════════════════════════════════════════════════════════
_gd_rename_fn() {          # _gd_rename_fn old new   (keeps the original callable under a new name)
  declare -F "$1" >/dev/null 2>&1 || return 1
  # no forks (the old declare|sed cost 2 processes per function — ~40 ms each on a phone):
  # declare writes into a file, $(<file) reads it without starting a process
  local _f="${TMPDIR:-/tmp}/.bvk-rn.$$" _d
  declare -f "$1" >"$_f" 2>/dev/null || return 1
  _d="$(<"$_f")"
  eval "${_d/#"$1 "/"$2 "}"
}

# server-side copy of items that are all inside the Drive into a Drive folder
_gd_copy_inside() {
  local dest="$1"; shift
  local total=$# ok=0 item base name ext count newbase err
  local -a failed=()
  declare -F _lk_load >/dev/null 2>&1 && _lk_load
  for item in "$@"; do
    if [ ! -e "$item" ]; then failed+=("$(basename -- "$item") — not found"); continue; fi
    base=$(basename -- "$item")
    if [ -d "$item" ] && { [ "$dest" = "$item" ] || [[ "$dest/" == "$item"/* ]]; }; then
      failed+=("$base — cannot copy a folder into itself"); continue
    fi
    name="${base%.*}"; ext="${base##*.}"; [[ "$base" == "$ext" ]] && ext=""
    count=1; newbase="$base"
    while [ -e "$dest/$newbase" ]; do
      if [ -n "$ext" ]; then newbase="${name}${count}.${ext}"; else newbase="${name}${count}"; fi
      count=$((count+1))
    done
    if err=$(_gd_py copy "$item" "$dest/$newbase" 2>&1); then
      ok=$((ok+1))
      declare -F _carry_copy >/dev/null 2>&1 && _carry_copy "$item" "$dest/$newbase"
    else
      failed+=("$base — ${err:-copy failed}")
    fi
  done
  _transfer_report "Copied" "$ok" "$total" "$dest" "${failed[@]}"
}

# apply this Drive's buffers (native), and offer the buffers staged OUTSIDE Drive as well
_gd_dispatch() {
  local -a names=(_SP_CP_FILE _SP_MV_FILE _SP_CP_ONCE_FILE _SP_MV_ONCE_FILE)
  local n f cnt=0 g
  for n in "${names[@]}"; do
    f="${_GD_SAVED[$n]:-}"; [ -n "$f" ] && [ -s "$f" ] && cnt=$(( cnt + $(grep -c . "$f" 2>/dev/null || echo 0) ))
  done
  if [ "$cnt" -gt 0 ]; then
    echo "📦 $cnt item(s) are staged for copy/move OUTSIDE Google Drive (your normal buffers)."
    local a; read -e -r -p "   Apply them into this Drive folder too? (y/N): " a
    case "$a" in
      [yY]|[yY][eE][sS])
        local -a keep=()
        for n in _SP_CP_FILE _SP_MV_FILE _SP_SC_FILE _SP_BM_FILE _SP_CP_ONCE_FILE _SP_MV_ONCE_FILE _SP_SC_ONCE_FILE _SP_BM_ONCE_FILE; do
          keep+=("${!n}"); printf -v "$n" '%s' "${_GD_SAVED[$n]:-${!n}}"
        done
        _gd_orig_handle_staging_dispatch
        local i=0
        for n in _SP_CP_FILE _SP_MV_FILE _SP_SC_FILE _SP_BM_FILE _SP_CP_ONCE_FILE _SP_MV_ONCE_FILE _SP_SC_ONCE_FILE _SP_BM_ONCE_FILE; do
          printf -v "$n" '%s' "${keep[$i]}"; i=$((i+1))
        done
        echo ;;
    esac
  fi
  _gd_orig_handle_staging_dispatch
}

_gd_install_wrappers() {
  [ -n "${_GD_WRAPPED:-}" ] && return 0
  _GD_WRAPPED=1

  if _gd_rename_fn handle_file _gd_orig_handle_file; then
    handle_file() {
      if _gd_in_tree "${1:-}"; then
        _gd_hydrate "$1" || return 1
        _gd_orig_handle_file "$@"; local rc=$?
        _gd_push
        return $rc
      fi
      _gd_orig_handle_file "$@"
    }
  fi

  if _gd_rename_fn perform_copy _gd_orig_perform_copy; then
    perform_copy() {
      local dest="$1"; shift
      if [ "$_GD_ACTIVE" = 1 ]; then
        local it all_in=true any_in=false
        for it in "$@"; do if _gd_in_tree "$it"; then any_in=true; else all_in=false; fi; done
        if _gd_in_tree "$dest" && $all_in; then _gd_copy_inside "$dest" "$@"; return; fi
        if $any_in; then _gd_hydrate "$@" || return 1; fi
      fi
      _gd_orig_perform_copy "$dest" "$@"
    }
  fi

  if _gd_rename_fn perform_move _gd_orig_perform_move; then
    perform_move() {
      local dest="$1"; shift
      if [ "$_GD_ACTIVE" = 1 ] && ! _gd_in_tree "$dest"; then _gd_hydrate "$@" || return 1; fi
      _gd_orig_perform_move "$dest" "$@"
    }
  fi

  if _gd_rename_fn _compress_paths _gd_orig_compress_paths; then
    _compress_paths() { _gd_hydrate "$@" || return 1; _gd_orig_compress_paths "$@"; }
  fi
  if _gd_rename_fn _decompress_paths _gd_orig_decompress_paths; then
    _decompress_paths() { _gd_hydrate "$@" || return 1; _gd_orig_decompress_paths "$@"; }
  fi

  # up- / ux- / c2c- resolve the picked rows through _sp_resolve_itemlist: download them there
  if _gd_rename_fn _sp_resolve_itemlist _gd_orig_sp_resolve_itemlist; then
    _sp_resolve_itemlist() {
      _gd_orig_sp_resolve_itemlist "$@" || return 1
      if [ "$_GD_HYD_RESOLVE" = 1 ]; then _gd_hydrate "${sp_resolved[@]}" || return 1; fi
      return 0
    }
  fi
  local fnn
  for fnn in handle_up_upload handle_ux_upload handle_c2c_upload; do
    if _gd_rename_fn "$fnn" "_gd_orig_$fnn"; then
      eval "$fnn() { _GD_HYD_RESOLVE=1; _gd_orig_$fnn \"\$@\"; local rc=\$?; _GD_HYD_RESOLVE=0; return \$rc; }"
    fi
  done

  if _gd_rename_fn handle_staging_dispatch _gd_orig_handle_staging_dispatch; then
    handle_staging_dispatch() {
      if [ "$_GD_ACTIVE" = 1 ]; then _gd_dispatch; else _gd_orig_handle_staging_dispatch "$@"; fi
    }
  fi
}

# rclone started by the app's own transfer menu with a Drive file as the SOURCE gets the real content
rclone() {
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then
    local a verb="" pos=() hyd=()
    for a in "$@"; do
      case "$a" in -*) continue ;; esac
      [ -z "$verb" ] && { verb="$a"; continue; }
      pos+=("$a")
    done
    case "$verb" in
      copy|move|sync|copyto|moveto) [ "${#pos[@]}" -gt 1 ] && unset 'pos[${#pos[@]}-1]' ;;   # the last one is the destination
      cat|md5sum|sha1sum|check|cryptcheck|hashsum) ;;
      *) pos=() ;;
    esac
    for a in "${pos[@]}"; do _gd_in_tree "$a" && hyd+=("$a"); done
    if [ "${#hyd[@]}" -gt 0 ]; then _gd_hydrate "${hyd[@]}" || return 1; fi
  fi
  command rclone "$@"
}

# ═════════════════════════════════════════════════════════════════════════════
#  gd commands (typed in the main screen while a Drive is open)
# ═════════════════════════════════════════════════════════════════════════════
_gd_info() {
  local k v remote="" files=0 dl=0 dlb=0 knb=0 folders=0
  echo
  echo "☁️  Google Drive — profile: $_GD_PROFILE   (rclone remote: $_GD_REMOTE)"
  while IFS=$'\t' read -r k v; do
    case "$k" in folders) folders="$v" ;; files) files="$v" ;; downloaded) dl="$v" ;; downloaded_bytes) dlb="$v" ;; known_bytes) knb="$v" ;; esac
  done < <(_gd_py status 2>/dev/null)
  local hs; declare -F _xui_hsize >/dev/null 2>&1 && hs=_xui_hsize || hs=echo
  echo "   Mirror folder  $_GD_ROOT"
  echo "   Listed         $folders folder(s) · $files file(s) · $($hs "$knb") in total"
  echo "   Downloaded     $dl file(s) · $($hs "$dlb") on this device   (gd.clean frees it)"
  echo "   Own state      $_GD_HOME   — settings, buffers (c- m- d-), selection, favourites, locks, rules, bookmarks"
  echo "   Quota          $(_gd_py about 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g')"
  echo
  echo "   gd.rf  list this folder again    gd.scan  list the whole Drive below here    gd.clean  free disk"
  echo "   gd.push  push pending changes    gd.sw  switch profile                        gdx  leave Google Drive"
  echo "   Everything else (c d r m- c- z uz- t f up- ux- ...) works as in any folder; changes go to Drive right after."
}

handle_gd_cmd() {
  local c="${1,,}" a
  if [ "$_GD_ACTIVE" != 1 ]; then
    echo "ℹ️  No Google Drive is open — fx → google_drive_fx → open google drive"
    return 0
  fi
  case "$c" in
    gd|gd.info|gd.i) _gd_info ;;
    gdx|gd.x|gd.exit) _gd_leave ;;
    gd.rf|gd.refresh) _gd_refresh "$path" ;;
    gd.scan)
      _gd_push
      _gd_py sync "$path" --force --recursive && echo "✅ Listed everything below $(_gd_view_path "$path"; echo "$_gd_vp")" ;;
    gd.clean)
      echo "ℹ️  Downloaded files you did not change turn back into placeholders (they download again when needed)."
      read -e -r -p "   Free the downloaded content of this whole Drive? (y/N): " a
      case "$a" in [yY]|[yY][eE][sS]) _gd_push; local r; r="$(_gd_py clean)"; echo "✅ ${r%%$'\t'*} file(s) freed (≈ ${r#*$'\t'} bytes of disk)." ;; *) echo "🚫 Cancelled" ;; esac ;;
    gd.push) _gd_push && echo "✅ Nothing pending." ;;
    gd.sw|gd.switch) _inner_run gdp ;;
    gd.q|gd.quota) _gd_py about ;;
    *) echo "❓ Unknown Drive command. gd shows the list." ;;
  esac
  return 0
}

_gd_install_wrappers
rm -f "${TMPDIR:-/tmp}/.bvk-rn.$$" 2>/dev/null
