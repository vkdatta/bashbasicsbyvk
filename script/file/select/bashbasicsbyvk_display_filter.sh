#!/usr/bin/env bash
# bashbasicsbyvk_display_filter.sh — the  .d  display-filter commands
# ════════════════════════════════════════════════════════════════════════════
#  .d <expression>      only DISPLAY items matching the expression (THIS folder only)
#  .d                   show the active filter
#  .d.clr               back to showing everything
#  .d.save NAME [expr]  keep the filter (or expr) as a display rule
#  .d.run NAME          apply a preset          (also:  .d .d.rule NAME)
#  .d.refresh           re-scan (filters are cached per folder until it changes)
#
#  Same grammar / engine as  .s  (see .s help) — just  .d.ext csv & .d.size <3mb
#  -r is ignored: the display only ever looks at the folder you are in.
#
#  Active filter is one small file (edit it by hand if you like):
#    ~/.bashbasicsbyvk/display/active
#        DIR=/folder/it/was/set/in
#        EXPR=.d.ext.csv & .d.size <3mb
#        CSV=/path/to/exts.csv            ← one line per .csv clause, in order
#  Presets are display rules:  ~/.bashbasicsbyvk/rules/display/NAME/NAME.rule  (manage them in  .r)
#
#  Setting (Settings → Display filter):  display_filter_persist  true|false
#     false (default) = the filter is cleared when the app starts.
#
#  Precedence: the filter applies on top of whatever the folder would show,
#  and it lifts the "too many items → grouped view" switch, like fs does.
# ════════════════════════════════════════════════════════════════════════════

_DISP_DIR="${HOME}/.bashbasicsbyvk/display"
_DISP_ACTIVE="${_DISP_DIR}/active"

: "${display_filter_persist:=false}"

# per-folder result cache
_disp_cache_key=""
declare -gA _DISP_HIT=()
_disp_banner=""
_disp_on=false
_disp_expr=""
_disp_dir=""
declare -ga _disp_csvs=()

_disp_startup() {                  # call once when the app starts
  [ "${display_filter_persist:-false}" = "true" ] || rm -f "$_DISP_ACTIVE" 2>/dev/null
}

_disp_cache_reset() { _disp_cache_key=""; _DISP_HIT=(); }

# Read the active file into _disp_expr / _disp_csvs. Returns 1 if none.
_disp_load() {
  _disp_expr=""; _disp_csvs=(); _disp_dir=""
  [ -f "$_DISP_ACTIVE" ] || return 1
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      DIR=*)  _disp_dir="${line#DIR=}" ;;
      EXPR=*) _disp_expr="${line#EXPR=}" ;;
      CSV=*)  _disp_csvs+=("${line#CSV=}") ;;
    esac
  done < "$_DISP_ACTIVE"
  [ -n "$_disp_expr" ]
}

_disp_store() {                    # _disp_store <expr> [csv ...]
  mkdir -p "$_DISP_DIR" 2>/dev/null
  local expr="$1"; shift
  { printf 'DIR=%s\n' "$path"; printf 'EXPR=%s\n' "$expr"; local c; for c in "$@"; do printf 'CSV=%s\n' "$c"; done; } > "$_DISP_ACTIVE"
  _disp_cache_reset
}

_disp_clear() { rm -f "$_DISP_ACTIVE" 2>/dev/null; _disp_cache_reset; _disp_banner=""; }

_disp_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Run the engine for the active filter in $path → fills _DISP_HIT. 0 ok / 1 error
# (error text in _disp_err).
_disp_err=""
_disp_run() {
  local hidden=0 errf key
  [ "${show_hidden_files:-false}" = "true" ] && hidden=1
  key="$path|$(_disp_mtime "$path")|$(_disp_mtime "$_DISP_ACTIVE")|$hidden"
  if [ "$key" = "$_disp_cache_key" ]; then return 0; fi
  errf=$(mktemp) || return 1
  local -a found=()
  mapfile -d '' -t found < <(BVK_NO_RECURSIVE=1 _sel_core run "$_disp_expr" "$path" "$hidden" "${_disp_csvs[@]}" 2>"$errf")
  if [ -s "$errf" ]; then
    _disp_err="$(sed 's/^ERR: //' "$errf")"
    rm -f "$errf"
    return 1
  fi
  rm -f "$errf"
  _DISP_HIT=()
  local p
  for p in "${found[@]}"; do _DISP_HIT["$p"]=1; done
  _disp_cache_key="$key"
  _disp_err=""
  return 0
}

# ── main-loop hooks ───────────────────────────────────────────────────────────
# _disp_begin : sets _disp_on (true when a usable filter is active)
_disp_begin() {
  _disp_on=false; _disp_banner=""
  _disp_load || return 0
  # folder-specific: the filter belongs to the folder it was set in
  # (it stays stored, and comes back when you return to that folder)
  [ -n "$_disp_dir" ] && [ "$_disp_dir" != "$path" ] && return 0
  _disp_on=true
}

# _disp_apply : narrow the already built+sorted $items to the filter's matches.
_disp_apply() {
  $_disp_on || return 0
  local before=${#items[@]}
  if ! _disp_run; then
    _disp_banner="⚠️  Display filter error: ${_disp_err} — showing everything  (.d.clr to clear)"
    return 0
  fi
  local -a kept=()
  local f
  for f in "${items[@]}"; do
    [ -n "${_DISP_HIT[$f]+x}" ] && kept+=("$f")
  done
  items=("${kept[@]}")
  _win_lo=0; _win_hi=0
  _meta_loaded=false
  local shown_expr="$_disp_expr"
  [ ${#shown_expr} -gt 60 ] && shown_expr="${shown_expr:0:57}..."
  _disp_banner="🔎 Display filter: ${shown_expr}  — ${#items[@]} shown  (.d.clr to clear)"
  [ "${#items[@]}" -eq 0 ] && _disp_banner="🔎 Display filter: ${shown_expr}  — nothing matches here  (.d.clr to clear)"
}

# ── commands ──────────────────────────────────────────────────────────────────
_disp_help() {
  cat <<'HLP'
🔎 DISPLAY FILTER  (.d)   same grammar as .s
 .d.ext csv & .d.size <3mb     show only small csv files
 .d.ext.csv                    extensions from a CSV (picker opens)
 .d.time 2024  .d.sw icon_ ...  everything from .s works with .d
 .d.clr                        show everything again
 .d.save NAME [expr]           keep as preset   .d.run NAME  applies it
 .d.refresh                    re-scan this folder
Applies only in the folder where it was set (other folders show everything). Settings → Display filter for presets/persistence.
HLP
}

_disp_status() {
  if _disp_load; then
    echo "🔎 Display filter ON: $_disp_expr   (folder: ${_disp_dir:-any})"
    local i; for i in "${!_disp_csvs[@]}"; do echo "   CSV $((i+1)): ${_disp_csvs[$i]}"; done
    echo "   .d.clr to clear   .d.save NAME to keep it"
  else
    echo "🔎 Display filter OFF"
  fi
}

# Set the filter from an expression (runs pickers, validates, stores).
_disp_set() {
  local expr="$1" errf scanf
  errf=$(mktemp) || return 1
  scanf=$(mktemp) || { rm -f "$errf"; return 1; }
  if ! _sel_core scan "$expr" >"$scanf" 2>"$errf"; then
    echo "❌ $(sed 's/^ERR: //' "$errf")"; rm -f "$errf" "$scanf"; return 1
  fi
  local -a labels=() csvs=()
  local line
  while IFS= read -r line; do
    case "$line" in
      CSV$'\t'*) labels+=("${line#CSV$'\t'}") ;;
      RECURSIVE=1) echo "ℹ️  -r is ignored for display (one folder at a time)" ;;
    esac
  done < "$scanf"
  rm -f "$scanf"
  local i n=${#labels[@]}
  for (( i=0; i<n; i++ )); do
    echo ""
    echo "📂 Select CSV for: ${labels[$i]}  ($((i+1)) of $n)"
    if ! open_csv_menu; then
      echo "🚫 Display filter unchanged"; rm -f "$errf"; return 1
    fi
    csvs+=("$csv_file")
  done
  # dry run in the current folder so mistakes show up now, not on redraw
  local hidden=0 cnt=0
  [ "${show_hidden_files:-false}" = "true" ] && hidden=1
  local -a found=()
  mapfile -d '' -t found < <(BVK_NO_RECURSIVE=1 _sel_core run "$expr" "$path" "$hidden" "${csvs[@]}" 2>"$errf")
  if [ -s "$errf" ]; then
    echo "❌ $(sed 's/^ERR: //' "$errf")"; rm -f "$errf"; return 1
  fi
  rm -f "$errf"
  cnt=${#found[@]}
  _disp_store "$expr" "${csvs[@]}"
  [ -z "${_DISP_NOHIST:-}" ] && _rule_hist_add "$expr"        # → .r › Last used
  echo "🔎 Display filter set — $cnt item(s) match here"
  [ "$cnt" -eq 0 ] && echo "ℹ️  Nothing matches in this folder (filter stays on; .d.clr to clear)"
  return 0
}

handle_display_cmd() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"; raw="${raw%"${raw##*[![:space:]]}"}"
  local cmd="${raw%% *}" rest=""
  [[ "$raw" == *" "* ]] && rest="${raw#* }"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$cmd" in
    .d)          if [ -z "$rest" ]; then _disp_status; _disp_help
                 elif [[ "${rest//[[:space:]]/}" =~ ^[0-9][0-9,-]*$ ]]; then
                   # bare numbers (.d 1,5,7-10): show just those displayed rows, in this folder
                   if ${imaginary_mode:-false}; then echo "⚠️  This folder is grouped — numbers mean groups. Use fs first"; return; fi
                   local -a _dn=($(parse_selection "${rest//[[:space:]]/}" "${#items[@]}")) _dx=()
                   local _k
                   for _k in "${_dn[@]}"; do _dx+=("\"${items[$((_k-1))]##*/}\""); done
                   [ ${#_dx[@]} -eq 0 ] && { echo "❌ No valid item numbers (1-${#items[@]})"; return; }
                   local _de; _de=$(IFS=,; echo "${_dx[*]}")
                   _DISP_NOHIST=1 _disp_set ".d $_de"
                 else _disp_set "$raw"; fi ;;
    .d.clr) if _disp_load; then _disp_clear; echo "🔎 Display filter cleared — showing everything"; else echo "🔎 Display filter is already off"; fi ;;
    .d.refresh)  _disp_cache_reset; echo "🔄 Display filter will re-scan" ;;
    .d.help)     _disp_help ;;
    .d.run)
      [ -z "$rest" ] && { echo "⚠️  Usage: .d.run NAME"; return; }
      _rule_valid_name "${rest%% *}" || { echo "❌ Rule names: letters, digits, _ and - only"; return; }
      _DISP_NOHIST=1 _disp_set ".d.rule ${rest%% *}" ;;
    .d.save)
      local name="${rest%% *}" expr=""
      [[ "$rest" == *" "* ]] && expr="${rest#* }"
      [ -z "$name" ] && { echo "⚠️  Usage: .d.save NAME [expression]   (no expression = the active filter)"; return; }
      if [ -z "$expr" ]; then
        _disp_load || { echo "ℹ️  No active display filter to save — give an expression"; return; }
        expr="$_disp_expr"
      fi
      _rule_save_as display "$name" "$expr" ;;
    .d.*)        # a clause like .d.ext csv  → treat the whole thing as an expression
                 _disp_set "$raw" ;;
    *)           echo "⚠️  Display commands: .d  .d.clr  .d.save  .d.run  .d.refresh" ;;
  esac
}

# ── Settings → Display filter ─────────────────────────────────────────────────
declare -ga _dfs_presets=()
_dfs_pick_mode=""          # run | delete

_dfs_pre_build() {
  local nm
  _st_reset
  _dfs_presets=()
  _rl_ensure_store 2>/dev/null
  _rl_audit_all
  for nm in "${_RL_NAMES_display[@]}"; do
    [ "${_RL_ST[display/$nm]}" = ok ] || continue
    _st_add a "$nm" 0 "${_RL_EX[display/$nm]}" "$nm"
  done
  (( ${#_st_lbl[@]} )) || _st_add h "No presets yet — set a filter, then Save as preset"
}
_dfs_pre_act() {
  local nm="${_st_tag[$1]}"
  [ -n "$nm" ] || return
  if [ "$_dfs_pick_mode" = delete ]; then _rule_delete_bundle display "$nm"
  else handle_display_cmd ".d.run $nm"; fi
  _st_back=1
}

_dfs_build() {
  local v="off"
  _disp_load && v="$_disp_expr"
  _st_reset
  _st_add a "Set filter…"         0 "$v"  set
  _st_add a "Clear filter"        0 ""    clear
  _st_add a "Apply a preset"      0 ""    run
  _st_add a "Save as preset…"     0 ""    save
  _st_add a "Delete a preset"     0 ""    del
  [ "$display_filter_persist" = true ] && _o=1 || _o=0
  _st_add t "Keep between sessions" "$_o" "" persist
  _st_add a "Help"                0 ""    help
}
_dfs_act() {
  local ex nm
  case "${_st_tag[$1]}" in
    set)
      if _st_ask "Expression (e.g. .d.ext csv & .d.size <3mb)"; then handle_display_cmd "$_st_in"; fi ;;
    clear) handle_display_cmd ".d.clr" ;;
    run)   _dfs_pick_mode=run;    _st_run "Apply a preset"  _dfs_pre_build _dfs_pre_act "↑↓ move · enter apply · u back · q close" ;;
    del)   _dfs_pick_mode=delete; _st_run "Delete a preset" _dfs_pre_build _dfs_pre_act "↑↓ move · enter delete · u back · q close" ;;
    save)
      if _st_ask "Preset name (letters, digits, _ -)"; then handle_display_cmd ".d.save $_st_in"; fi ;;
    persist)
      if [ "$display_filter_persist" = true ]; then display_filter_persist=false; else display_filter_persist=true; fi
      save_settings ;;
    help) _disp_help ;;
  esac
}
display_filter_settings() { _st_run "Display filter  (.d)" _dfs_build _dfs_act; }
