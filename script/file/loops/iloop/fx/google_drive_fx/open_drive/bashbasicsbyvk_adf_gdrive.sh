#!/usr/bin/env bash
# bashbasicsbyvk_adf_gdrive.sh
# adf-staging='google_drive_fx/open google drive'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — google_drive_fx → open google drive
#
#  Shows the rclone profiles (remotes of type "drive") and opens the one you pick as the main screen:
#  your files in Google Drive, listed like a local folder, with every native command working on them.
#  The work lives in bashbasicsbyvk_gdrive.sh (session) and bashbasicsbyvk_gd (python / rclone).
# ════════════════════════════════════════════════════════════════════════════

declare -ga _GDP_NAME=() _GDP_TYPE=() _GDP_LAST=()

_gdp_when() {            # epoch -> "2026-10-13 10:21 IST" (app timezone)
  local e="$1"
  [[ "$e" =~ ^[0-9]+$ ]] || { printf 'never opened'; return; }
  printf '%(%Y-%m-%d %H:%M %Z)T' "$e"
}

_gdp_fetch() {
  local out n t safe last
  out="$("$_GD_PY" "$_GD_MAIN" remotes)" || return 1
  _GDP_NAME=(); _GDP_TYPE=(); _GDP_LAST=()
  while IFS=$'\t' read -r n t; do
    [ -n "$n" ] || continue
    safe="$(_gd_safe_name "$n")"
    last="$(cat "$_GD_BASE/$safe/.last" 2>/dev/null)"
    _GDP_NAME+=("$n"); _GDP_TYPE+=("$t"); _GDP_LAST+=("$last")
  done <<<"$out"
  return 0
}

gdp_build() {
  local i rows=()
  for i in "${!_GDP_NAME[@]}"; do rows+=("${_GDP_NAME[$i]} ${_GDP_TYPE[$i]}"); done
  _xui_begin_items "${rows[@]}"
}

gdp_row() {
  _xui_slot "$1"; local s="$_XUI_SLOT" tag=""
  [ "$_GD_ACTIVE" = 1 ] && [ "$_GD_REMOTE" = "${_GDP_NAME[$s]}" ] && tag="  💫 open now"
  printf -v _vp_line ' %2d) ☁️  %-24s  %s%s' "$1" "$(_xui_trunc "${_GDP_NAME[$s]}" 24)" "$(_gdp_when "${_GDP_LAST[$s]}")" "$tag"
}

gdp_header() {
  echo; echo "☁️  Google Drive profiles   (${#_GDP_NAME[@]} found in rclone)"
  printf '📂 each profile keeps its own settings, buffers and selections in %s/<profile>/\n' "$_GD_BASE"
  _vp_filter_header_line
}

gdp_footer() {
  _mc_footer "#Select a number to open that Google Drive" "n:New profile (rclone config)" "rf:Reload" "u:Back"
}

_gdp_cmd() {
  case "$1" in
    rf) _lb_run "Reading rclone profiles" _gdp_fetch || echo "❌ Reload failed."; return 0 ;;
    n)  echo; echo "📜  rclone config → n (new remote) → name → Google Drive → scope 1 → auto config y"
        command rclone config
        _lb_run "Reading rclone profiles" _gdp_fetch; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { _bvk_invalid; return 1; }
      if _gd_enter "${_GDP_NAME[$_XUI_SLOT]}"; then return 2; fi
      echo
      return 0 ;;
    fx|sw|api|.r|-u) echo "↩️  Go back with  u  first."; return 1 ;;
    *) return 9 ;;
  esac
}

# ── the button ──────────────────────────────────────────────────────────────
_fx_adf_gdrive() {
  _gd_locate || return 1
  _gd_need_rclone || return 1
  if ! _lb_run "Reading rclone profiles" _gdp_fetch; then
    echo "❌ Could not read the rclone profiles (see message above)."; return 1
  fi
  if [ "${#_GDP_NAME[@]}" -eq 0 ]; then
    echo "📜  rclone has no Google Drive profile yet."
    echo "   Create one:  rclone config → n (new remote) → name → Google Drive → scope 1 (full access) → auto config y"
    _xui_yes "Run 'rclone config' now?" || return 1
    command rclone config
    _lb_run "Reading rclone profiles" _gdp_fetch
    [ "${#_GDP_NAME[@]}" -gt 0 ] || { echo "❌ Still no Google Drive profile."; return 1; }
  fi
  _xui_enter
  _xui_screen gdp
  _xui_loop _gdp_cmd
  _xui_leave
}

gdrive_profiles_menu() { _fx_adf_gdrive; }

_fx_adf_register "open google drive" "_fx_adf_gdrive" "google_drive_fx/open google drive"
