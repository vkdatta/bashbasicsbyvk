#!/usr/bin/env bash
# bashbasicsbyvk_findrun.sh — the find & replace ENGINE side of the Find menu (the menu itself: bashbasicsbyvk_find.sh)
# ════════════════════════════════════════════════════════════════════════════
#  Everything that touches files is done by ONE small program, bvk-fr (C, static, no extra 30 MB like a second Go engine):
#     find     what matches        preview   what would change        apply   do it
#  names · contents · both, flat or recursive, text or regex, exact or any case, whole words, hidden / .git handling,
#  conflicts (never overwrites), atomic file writes, many files in parallel.
#  When no bvk-fr binary runs here, the Python twin  bashbasicsbyvk_findrep  (same command line, same output) is used.
#
#  Needs: _bvk_engine_target (displayer.sh), the find_* settings (bashbasicsbyvk_settings.sh), _sel_mark_v (optional).
#  Used by: find_menu.
# ════════════════════════════════════════════════════════════════════════════

declare -g _FR_KIND="" _FR_WHY="" _FR_TMP=""
declare -ga _FR_RUN=() _FR_LIST=()
declare -gA _FRS=()
declare -ga _fr_finds=() _fr_reps=() _fr_excl=()
declare -g _fr_only="" _fr_scope="" _fr_root=""

# _fr_engine  → 0 when an engine is ready:  _FR_RUN = the command (array),  _FR_KIND = c | py.  Otherwise _FR_WHY says why not.
_fr_engine() {
  [ "${#_FR_RUN[@]}" -gt 0 ] && return 0
  _FR_WHY=""
  local _b _o _d _os _m
  local -a _cand=()
  if [ "${BVK_NO_GO:-0}" = "1" ]; then
    _FR_WHY="BVK_NO_GO=1 is set — the C engine is switched off on purpose"
  else
    _bvk_engine_target; _m="$_bet_m"; _os="$_bet_os"
    _o="$(command -v o 2>/dev/null)"; _d="${_o%/*}"
    _cand=("$(command -v bvk-fr 2>/dev/null)")
    if [ -n "$_m" ]; then
      _cand+=("$_d/../bashbasicsbyvk/bin/bvk-fr-$_os-$_m" "$(command -v "bvk-fr-$_os-$_m" 2>/dev/null)")
    else
      _FR_WHY="no prebuilt bvk-fr for CPU '$(uname -m)'"
    fi
    [ -n "$_FR_WHY" ] || _FR_WHY="no bvk-fr binary found (looked next to 'o' and on PATH)"
    for _b in "${_cand[@]}"; do
      [ -n "$_b" ] && [ -f "$_b" ] || continue
      [ -x "$_b" ] || chmod +x "$_b" 2>/dev/null
      [ -x "$_b" ] || { _FR_WHY="$_b exists but is not executable"; continue; }
      if [ "$("$_b" selftest 2>/dev/null)" = "bvk-fr ok" ] && [ "$("$_b" proto 2>/dev/null)" = 1 ]; then
        _FR_RUN=("$_b"); _FR_KIND=c; _FR_WHY=""; return 0
      fi
      _FR_WHY="$_b failed its self-test (run: health)"
    done
  fi
  _b="$(command -v bashbasicsbyvk_findrep 2>/dev/null)"
  if [ -n "$_b" ] && command -v python3 >/dev/null 2>&1; then
    if [ "$(python3 "$_b" selftest 2>/dev/null)" = "bvk-fr ok" ]; then
      _FR_RUN=(python3 "$_b"); _FR_KIND=py; return 0
    fi
  fi
  [ -n "$_FR_WHY" ] || _FR_WHY="no engine"
  return 1
}

_fr_tmpdir() {
  [ -n "$_FR_TMP" ] && [ -d "$_FR_TMP" ] && return 0
  _FR_TMP="$(mktemp -d "${TMPDIR:-/tmp}/bvkfr.XXXXXX" 2>/dev/null)" || _FR_TMP="$(mktemp -d)"
}

_fr_cleanup() { [ -n "$_FR_TMP" ] && rm -rf -- "$_FR_TMP"; _FR_TMP=""; }

# _fr_stats_read → _FRS[key]=value from the engine's stats file
_fr_stats_read() {
  local k v
  _FRS=()
  [ -f "$_FR_TMP/stats" ] || return 0
  while IFS='=' read -r k v; do _FRS[$k]="$v"; done < "$_FR_TMP/stats"
}

# _fr_exec <find|preview|apply>
#   in : _fr_finds[] _fr_reps[]  (the rules, applied in this order)  _fr_root  _fr_scope (names|contents|both)
#        _fr_only (one path)  _fr_excl[]  and the options _fo_*  filled by _find_resolve_options
#   out: _FR_TMP/lines (the numbered result lines)  _FR_LIST[] (the listed paths, same order)  _FRS[] (counts)
#        _FR_TMP/log (renames done: "old<TAB>new")
#   rc : 0 ran · 1 could not run / bad pattern (message already printed)
_fr_exec() {
  local mode="$1" i rc msg
  _fr_engine || { echo "❌ No find & replace engine could be started: $_FR_WHY"; return 1; }
  _fr_tmpdir
  rm -f -- "$_FR_TMP/out" "$_FR_TMP/stats" "$_FR_TMP/log" "$_FR_TMP/lines" "$_FR_TMP/err"
  { for i in "${!_fr_finds[@]}"; do printf '%s\0%s\0' "${_fr_finds[$i]}" "${_fr_reps[$i]-}"; done; } > "$_FR_TMP/rules"
  local -a a=(--root "${_fr_root:-$path}" --rules "$_FR_TMP/rules" --scope "$_fr_scope" --depth "$_fo_depth" --case "$_fo_case"
              --regex "$_fo_regex" --word "$_fo_word" --hidden "$_fo_hidden" --vcs "$_fo_vcs" --target "$_fo_target"
              --binary "$_fo_binary" --maxsize "$_fo_maxsize" --threads "$_fo_threads" --limit "$_fo_limit"
              --out "$_FR_TMP/out" --stats "$_FR_TMP/stats" --log "$_FR_TMP/log")
  [ -n "$_fr_only" ] && a+=(--only "$_fr_only")
  for i in "${_fr_excl[@]}"; do a+=(--exclude "$i"); done
  "${_FR_RUN[@]}" "$mode" "${a[@]}" > "$_FR_TMP/lines" 2> "$_FR_TMP/err"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    msg="$(head -c 400 "$_FR_TMP/err" 2>/dev/null)"; msg="${msg#bvk-fr: }"
    echo "❌ ${msg:-the find & replace engine stopped (exit $rc)}"
    return 1
  fi
  _fr_stats_read
  _FR_LIST=()
  [ -s "$_FR_TMP/out" ] && mapfile -d '' -t _FR_LIST < "$_FR_TMP/out"
  return 0
}

# _fr_show  — prints the engine's numbered lines; an item selected with .s keeps its green "+"
_fr_show() {
  local line n
  [ -s "$_FR_TMP/lines" ] || return 0
  if declare -F _sel_mark_v >/dev/null 2>&1 && [ "${#_FR_LIST[@]}" -gt 0 ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^\ *([0-9]+)\)\  ]]; then
        n="${BASH_REMATCH[1]}"
        if [ -n "${_FR_LIST[n-1]:-}" ] && _sel_mark_v "${_FR_LIST[n-1]}" "$line"; then printf '%s\n' "$_smk_out"; continue; fi
      fi
      printf '%s\n' "$line"
    done < "$_FR_TMP/lines"
  else
    cat "$_FR_TMP/lines"
  fi
}

# _fr_notes — one-line warnings the person must not miss (things that were skipped / failed)
_fr_notes() {
  local n
  n="${_FRS[skipped_binary]:-0}";  [ "$n" -gt 0 ] && echo "ℹ️  $n binary file(s) skipped (Settings → Find & replace → Binary files)"
  n="${_FRS[skipped_large]:-0}";   [ "$n" -gt 0 ] && echo "ℹ️  $n file(s) over the size limit skipped (Settings → Find & replace → Big files)"
  n="${_FRS[content_errors]:-0}";  [ "$n" -gt 0 ] && echo "⚠️  $n file(s) could not be read or edited (listed above with the reason)"
  n="${_FRS[unreadable]:-0}";      [ "$n" -gt 0 ] && echo "⚠️  $n folder(s) could not be opened (permission?)"
  return 0
}

# _fr_changes_log  — hands the renames to locks + shortcuts (they follow the renamed items), then forgets the log
_fr_changes_log() {
  if [ -s "$_FR_TMP/log" ]; then
    local _mvlog; _mvlog="$(mktemp)"
    cp -- "$_FR_TMP/log" "$_mvlog" && _carry_apply_mv_log "$_mvlog"
  fi
}
