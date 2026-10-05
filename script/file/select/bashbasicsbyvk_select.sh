#!/usr/bin/env bash
# bashbasicsbyvk_select.sh — the  .s  select commands and  .r  rule commands
# ════════════════════════════════════════════════════════════════════════════
#  .s <expression>       select (ADDS; persists across folders)
#  .us <expression>      unselect matches
#  .s.set <expression>   replace the whole selection
#  .s.add / .s.sub       aliases of .s / .us
#  .s.show [all]  .s.clr  .s.shown
#  .r                    open the rule book (create / edit / delete / rename inside it)
#
#  Matching is done by _3bvk_select_core (python3).  This file only handles
#  the prompts, the CSV pickers (existing open_csv_menu), storage and output.
#
#  Storage (plain text, user-editable, same style as buffers / swlinks):
#    ~/.bashbasicsbyvk/selection.list        one absolute path per line
#    ~/.bashbasicsbyvk/rules/select/NAME/NAME.rule + NAME.meta   (see bashbasicsbyvk_rules.sh)
#    ~/.bashbasicsbyvk/rules/.history        last used expressions not yet in the rule book
# ════════════════════════════════════════════════════════════════════════════

_SEL_FILE="${HOME}/.bashbasicsbyvk/selection.list"
_SEL_RULES_DIR="${HOME}/.bashbasicsbyvk/rules"

_SEL_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

_sel_ensure_store() {
  mkdir -p "$(dirname "$_SEL_FILE")" "$_SEL_RULES_DIR" 2>/dev/null
  [ -f "$_SEL_FILE" ] || : > "$_SEL_FILE"
}

# Run the python engine. Usage: _sel_core <args...>
_sel_core() {
  local core
  core="$(command -v _3bvk_select_core 2>/dev/null)"
  [ -z "$core" ] && core="$_SEL_HERE/_3bvk_select_core"
  BVK_RULES_DIR="$_SEL_RULES_DIR" python3 "$core" "$@"
}

# ── selection store ───────────────────────────────────────────────────────────
_sel_load() {                       # _sel_load <array-name>
  local -n _sl_out="$1"
  _sl_out=()
  [ -f "$_SEL_FILE" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && _sl_out+=("$line")
  done < "$_SEL_FILE"
}

_sel_save() {                       # _sel_save <array-name>
  local -n _ss_in="$1"
  _sel_ensure_store
  if [ ${#_ss_in[@]} -eq 0 ]; then : > "$_SEL_FILE"; else printf '%s\n' "${_ss_in[@]}" > "$_SEL_FILE"; fi
  _sel_bump
}

# ── selection marks (used by every screen that lists real files) ─────────────
#  A selected item is drawn with a leading "+" (width-neutral: it replaces the
#  row's leading space).  No colour is used - the "+" alone marks the row.
#  Lookups are lazy + memoised per generation, so a 200k-item selection costs
#  one grep per VISIBLE row, never a full load.
_SEL_GEN=0
declare -gA _SEL_MARKC=()
_SEL_MARKC_GEN=-1
_sel_bump() { _SEL_GEN=$(( _SEL_GEN + 1 )); }

_sel_is_marked() {                  # _sel_is_marked <abs path>
  [ -s "$_SEL_FILE" ] || return 1
  if [ "$_SEL_MARKC_GEN" != "$_SEL_GEN" ]; then _SEL_MARKC=(); _SEL_MARKC_GEN=$_SEL_GEN; fi
  local f="$1"
  if [ -z "${_SEL_MARKC[$f]+x}" ]; then
    if grep -qxF -- "$f" "$_SEL_FILE" 2>/dev/null; then _SEL_MARKC[$f]=1; else _SEL_MARKC[$f]=0; fi
  fi
  [ "${_SEL_MARKC[$f]}" = 1 ]
}

# Fill the mark cache for the visible rows with ONE grep (rows start..end of
# $items), so drawing a screen never forks once per row.
_sel_prewarm() {
  [ -s "$_SEL_FILE" ] || return 0
  [ "${_vp_mode:-}" == "items" ] && [ -z "${_vp_rowtext_fn:-}" ] || return 0
  if [ "$_SEL_MARKC_GEN" != "$_SEL_GEN" ]; then _SEL_MARKC=(); _SEL_MARKC_GEN=$_SEL_GEN; fi
  local i f hit
  local -a want=()
  for (( i=$1; i<=$2; i++ )); do
    f="${items[$((i-1))]:-}"
    [ -n "$f" ] && [ -z "${_SEL_MARKC[$f]+x}" ] && { want+=("$f"); _SEL_MARKC[$f]=0; }
  done
  [ ${#want[@]} -eq 0 ] && return 0
  while IFS= read -r hit; do _SEL_MARKC[$hit]=1; done \
    < <(printf '%s\n' "${want[@]}" | grep -xF -f - "$_SEL_FILE" 2>/dev/null)
}

# _sel_mark_v <path> <line> : sets _smk_out; returns 0 when the path is selected
_smk_out=""
_sel_mark_v() {
  _smk_out="$2"
  [ -n "$1" ] || return 1
  _sel_is_marked "$1" || return 1
  local l="$2"
  if [[ "$l" == " "* ]]; then l="+${l:1}"; else l="+$l"; fi
  _smk_out="$l"
  return 0
}

# count + banner for the header (matters most in grouped view, where rows are
# groups and cannot carry a per-item mark)
_sel_banner=""
_SEL_CNT_GEN=-1
_SEL_CNT=0
_sel_begin() {
  if [ "$_SEL_CNT_GEN" != "$_SEL_GEN" ]; then
    _SEL_CNT=0
    [ -s "$_SEL_FILE" ] && _SEL_CNT=$(grep -c '' "$_SEL_FILE" 2>/dev/null)
    _SEL_CNT_GEN=$_SEL_GEN
  fi
  _sel_banner=""
  [ "${_SEL_CNT:-0}" -gt 0 ] && _sel_banner="🎯 ${_SEL_CNT} selected — marked +   (.s.show · .s.clr · fx → <action>/<action>.selected.items)"
}

# Load only paths that still exist; reports how many vanished.
_sel_load_live() {                  # _sel_load_live <array-name>
  local -n _sll_out="$1"
  local -a _all=()
  _sel_load _all
  _sll_out=()
  local p
  for p in "${_all[@]}"; do
    if [ -e "$p" ] || [ -L "$p" ]; then _sll_out+=("$p"); fi
  done
  _SEL_VANISHED=$(( ${#_all[@]} - ${#_sll_out[@]} ))
}

_sel_prune() {                      # drop vanished paths from selection.list
  local -a live=()
  _sel_load_live live
  [ "$_SEL_VANISHED" -gt 0 ] && _sel_save live
}

_sel_short() {                      # path relative to $path when possible
  local p="$1" base="${path%/}/"
  if [[ "$p" == "$base"* ]]; then printf '%s' "${p#"$base"}"; else printf '%s' "$p"; fi
}

_sel_summary() {                    # _sel_summary <array-name> <headline>
  local -n _sm="$1"
  local n=${#_sm[@]} f=0 d=0 p
  for p in "${_sm[@]}"; do if [ -d "$p" ] && [ ! -L "$p" ]; then d=$((d+1)); else f=$((f+1)); fi; done
  echo "$2 — $n item(s): $f file(s), $d folder(s)"
}

_sel_preview() {                    # first 8 items
  local -n _pv="$1"
  local i max=8
  for (( i=0; i<${#_pv[@]} && i<max; i++ )); do
    printf '   • %s\n' "$(_sel_short "${_pv[$i]}")"
  done
  [ ${#_pv[@]} -gt $max ] && echo "   … and $(( ${#_pv[@]} - max )) more  (.s.show to see all)"
}

# ── help ──────────────────────────────────────────────────────────────────────
_sel_help() {
  cat <<'HLP'
🎯 SELECT  (.s)        works in any folder, even huge ones
 .s.a  .s.a.f  .s.a.d       everything / files / folders
 .s a.png,b.png             exact names   ("quote names with spaces")
 .s.sw X  .s.ew X  .s.contains X   starts / ends / contains
 .s.ext csv,txt             extensions (noext = no extension)
 .s.size >3mb  <500kb  1mb..5mb  0  5mb
 .s.time 2024  032024  15032024  2020s  2019..2022
         <2026  >01012002 <2004  last30d
 .s.dup  .s.dup.all         duplicates (first copy kept / all copies)
 .s.empty                   empty files + folders
 .s.f  .s.d                 filter to files / folders
 .s.csv                     names listed in a CSV
 .s.ext.csv .s.sw.csv .s.ew.csv .s.contains.csv .s.time.csv
   → opens the CSV picker per clause; add (and) for AND, default (or)
 .s.rule NAME               use a saved rule
 .s 1-5   .s 1,2,3-7,11   .s a-5      by displayed number (a-5 = all except 5)
 .s ADDS to the selection and keeps it across folders (go anywhere, select more)
 .us <same expressions>     UNSELECT   e.g. .us 3   .us.a   .us.ext png   (.us.clr = empty all)
 .s.set EXPR                replace the whole selection  (.s.clr empties it)
 .s 5-8 -r count<20        select items 5-8 recursively, skipping folders with 20+ files
                            (count<=20 = skip only folders with MORE than 20; works with .us too)
 .s.rec [N]                 same on the current selection (skips folders with more than N)
LOGIC  space or &  = AND      |  = OR      !  = NOT      ( )  groups
 -r  at the end = search subfolders
AFTER  .s.add EXPR  .s.sub EXPR  .s.show  .s.clr  .s.shown
       then fx → <action>/<action>.selected.items  (copy move shortcut bookmark
       upload upload.text map zip unzip delete);  file_fx/selection = view only
RULES  .r  opens the rule book:  c create · d delete · r rename · e-N edit · ←/→ tab "last used"
       .s.rule NAME runs a select rule (rules/select)
DISPLAY  .d <same expressions>   .d.clr   .d.save   .d.run   (see .d)
FAVOURITES  fa <numbers | sel | .s expression>   ns   (see: fa help)
HLP
}

# ── evaluate an expression → _SEL_FOUND (shared by .s, .d and fa) ─────────────
# Runs one existing CSV picker per .csv clause. Returns 1 on error / cancel
# (message already printed).
declare -ga _SEL_FOUND=()
_SEL_EVAL_KIND=""      # index | expr   (what the last _sel_eval was given)
_SEL_EVAL_OK=0         # 1 once the last handle_select_cmd evaluated successfully
_sel_eval() {
  local expr="$1"
  _SEL_FOUND=()
  _SEL_EVAL_KIND=expr
  _sel_ensure_store

  # 0) index selection by displayed number:  1-5   1,2,3-7,11   a-5 (all except 5)
  #    (optionally written with the .s prefix), optionally followed by
  #       -r            expand folders recursively
  #       count<N       …but skip any folder holding N or more files (count<=N: more than N)
  #    e.g.  .s 5-8 -r count<20
  local _w _rest="" _rflag=0 _cnt="" _lim=""
  local -a _words=()
  set -f; read -r -a _words <<< "$expr"; set +f
  for _w in "${_words[@]}"; do
    if [ "$_w" = "-r" ]; then _rflag=1
    elif [[ "$_w" =~ ^count(\<=|\<)([0-9]+)$ ]]; then
      _cnt="${BASH_REMATCH[2]}"; _lim=$(( 10#$_cnt ))
      [ "${BASH_REMATCH[1]}" = "<" ] && _lim=$(( _lim - 1 ))
    else _rest+="$_w "
    fi
  done
  local _ix="${_rest#.us}"; _ix="${_ix#.s}"
  _ix="${_ix//[[:space:]]/}"
  if [[ "$_ix" =~ ^(a-[0-9][0-9,-]*|[0-9][0-9,-]*)$ ]]; then
    _SEL_EVAL_KIND=index
    if ${imaginary_mode:-false}; then
      echo "⚠️  This folder is grouped — numbers mean groups. Use fs first, or a name/.s expression"
      return 1
    fi
    local _n=${#items[@]} _i
    if [ "$_n" -eq 0 ]; then echo "ℹ️  Nothing displayed to select"; return 1; fi
    local -a _idx=()
    if [[ "$_ix" == a-* ]]; then
      _idx=($(_sp_parse_all_except "${_ix#a-}" "$_n"))
    else
      _idx=($(parse_selection "$_ix" "$_n"))
    fi
    for _i in "${_idx[@]}"; do _SEL_FOUND+=("${items[$((_i-1))]}"); done
    if [ ${#_SEL_FOUND[@]} -eq 0 ]; then echo "❌ No valid item numbers (1-$_n)"; return 1; fi
    if (( _rflag )) || [ -n "$_cnt" ]; then
      local _hid=0 _skf _roots=("${_SEL_FOUND[@]}") _sk
      [ "${show_hidden_files:-false}" = "true" ] && _hid=1
      [ -z "$_lim" ] && _lim=1000000000
      _skf=$(mktemp) || return 1
      mapfile -d '' -t _SEL_FOUND < <(BVK_SKIPFILE="$_skf" _sel_core expand "$_lim" "$_hid" "${_roots[@]}" 2>/dev/null)
      _sk=$(grep -c '' "$_skf" 2>/dev/null)
      if [ "${_sk:-0}" -gt 0 ]; then
        echo "⏭️  Skipped $_sk folder(s) over the count limit:"
        head -5 "$_skf" | while IFS=$'\t' read -r c d; do printf '   • %s  (%s files)\n' "$(_sel_short "$d")" "$c"; done
        [ "$_sk" -gt 5 ] && echo "   … and $((_sk-5)) more"
      fi
      rm -f "$_skf"
    fi
    return 0
  fi
  local errf scanf
  errf=$(mktemp) || return 1
  scanf=$(mktemp) || { rm -f "$errf"; return 1; }

  # 1) parse only → find out how many CSV pickers are needed
  if ! _sel_core scan "$expr" >"$scanf" 2>"$errf"; then
    echo "❌ $(sed 's/^ERR: //' "$errf")"
    rm -f "$errf" "$scanf"
    return 1
  fi
  local -a labels=() csvs=()
  local line
  while IFS= read -r line; do
    [[ "$line" == CSV$'\t'* ]] && labels+=("${line#CSV$'\t'}")
  done < "$scanf"

  # 2) one existing-picker run per .csv clause, left → right
  local i n=${#labels[@]}
  for (( i=0; i<n; i++ )); do
    echo ""
    echo "📂 Select CSV for: ${labels[$i]}  ($((i+1)) of $n)"
    if ! open_csv_menu; then
      echo "🚫 Selection cancelled"
      rm -f "$errf" "$scanf"
      return 1
    fi
    csvs+=("$csv_file")
  done

  # 3) evaluate
  local hidden=0
  [ "${show_hidden_files:-false}" = "true" ] && hidden=1
  mapfile -d '' -t _SEL_FOUND < <(_sel_core run "$expr" "$path" "$hidden" "${csvs[@]}" 2>"$errf")
  if [ -s "$errf" ]; then
    echo "❌ $(sed 's/^ERR: //' "$errf")"
    rm -f "$errf" "$scanf"
    _SEL_FOUND=()
    return 1
  fi
  rm -f "$errf" "$scanf"
  return 0
}

# ── main entry:  .s ... ───────────────────────────────────────────────────────
handle_select_cmd() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"; raw="${raw%"${raw##*[![:space:]]}"}"

  case "$raw" in
    .r|.r.*|.r\ *) handle_rule_cmd "$raw"; return ;;      # → bashbasicsbyvk_rules.sh
    .s.show|.s.show\ *)  _sel_cmd_show "${raw#.s.show}"; return ;;
    .s.clr) _sel_ensure_store; : > "$_SEL_FILE"; _sel_bump; echo "🧹 Selection cleared"; return ;;
    .s.shown)            _sel_cmd_shown; return ;;
    .s|.s\ help|.s.help|-h) _sel_help; return ;;
    .s.rec|.s.rec\ *)   _sel_cmd_rec "${raw#.s.rec}"; return ;;
  esac

  # .s ADDS to the selection (it persists across folders until .s.clr / .us).
  # .us removes.  .s.set replaces.  .s.add / .s.sub kept as aliases.
  local mode="add" expr="$raw"
  case "$raw" in
    .us|.us.help) echo "⚠️  Usage: .us <expression>   e.g. .us 3-5   .us .s.ext png   (.us.a = unselect everything here, .s.clr = empty the whole selection)"; return ;;
    .us.clr) _sel_ensure_store; : > "$_SEL_FILE"; _sel_bump; echo "🧹 Selection cleared"; return ;;
    .us\ *)  mode="sub"; expr="${raw#.us }" ;;
    .us.*)   mode="sub"; expr=".s.${raw#.us.}" ;;
    .s.set\ *) mode="replace"; expr="${raw#.s.set }" ;;
    .s.add\ *) mode="add"; expr="${raw#.s.add }" ;;
    .s.sub\ *) mode="sub"; expr="${raw#.s.sub }" ;;
    .s.add|.s.sub|.s.set) echo "⚠️  Usage: ${raw} <expression>   e.g. ${raw} .s.ext png"; return ;;
  esac
  expr="${expr#"${expr%%[![:space:]]*}"}"

  _sel_eval "$expr" || return
  _SEL_EVAL_OK=1
  local -a found=("${_SEL_FOUND[@]}")
  [ "$_SEL_EVAL_KIND" = expr ] && _rule_hist_add "$expr"      # → .r › Last used

  # 4) combine with the existing selection
  local -a cur=() out=()
  local p
  case "$mode" in
    replace) out=("${found[@]}") ;;
    add)
      _sel_load cur
      local -A have=()
      for p in "${cur[@]}"; do have["$p"]=1; out+=("$p"); done
      for p in "${found[@]}"; do [ -z "${have[$p]+x}" ] && { have["$p"]=1; out+=("$p"); }; done ;;
    sub)
      _sel_load cur
      local -A drop=()
      for p in "${found[@]}"; do drop["$p"]=1; done
      for p in "${cur[@]}"; do [ -z "${drop[$p]+x}" ] && out+=("$p"); done ;;
  esac
  _sel_save out

  if [ ${#found[@]} -eq 0 ] && [ "$mode" = "replace" ]; then
    echo "ℹ️  Nothing matched — selection is now empty"
    return
  fi
  case "$mode" in
    replace) _sel_summary out "🎯 Selected" ;;
    add)     _sel_summary out "➕ Added ${#found[@]} match(es) → selection now" ;;
    sub)     _sel_summary out "➖ Unselected ${#found[@]} match(es) → selection now" ;;
  esac
  _sel_preview out
  [ ${#out[@]} -gt 0 ] && echo "➡️  fx → <action>/<action>.selected.items (copy / move / zip / upload / delete / ...)"
}

# .s.rec [N]  — take the CURRENT selection and expand it recursively (every
# file and folder inside), skipping any folder that holds more than N files
# (default 20) together with everything under it.  The result replaces the
# selection.   e.g.  .s 5-8   then   .s.rec 20
_sel_cmd_rec() {
  local n="${1//[[:space:]]/}" hidden=0 skipf errf
  [ -z "$n" ] && n=20
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then echo "⚠️  Usage: .s.rec [N]   e.g. .s.rec 20  (skips folders with more than N files)"; return; fi
  [ "${show_hidden_files:-false}" = "true" ] && hidden=1
  local -a roots=() found=()
  _sel_load_live roots
  if [ ${#roots[@]} -eq 0 ]; then echo "ℹ️  Nothing selected — select items first (e.g. .s 5-8 or .s.a), then .s.rec $n"; return; fi
  skipf=$(mktemp) || return; errf=$(mktemp) || { rm -f "$skipf"; return; }
  mapfile -d '' -t found < <(BVK_SKIPFILE="$skipf" _sel_core expand "$n" "$hidden" "${roots[@]}" 2>"$errf")
  if [ -s "$errf" ]; then echo "❌ $(sed 's/^ERR: //' "$errf")"; rm -f "$skipf" "$errf"; return; fi
  _sel_save found
  _sel_summary found "🎯 Selected recursively (folders with more than $n files skipped) →"
  _sel_preview found
  local sk; sk=$(grep -c '' "$skipf" 2>/dev/null)
  if [ "${sk:-0}" -gt 0 ]; then
    echo "⏭️  Skipped $sk folder(s):"
    head -5 "$skipf" | while IFS=$'\t' read -r c d; do printf '   • %s  (%s files)\n' "$(_sel_short "$d")" "$c"; done
    [ "$sk" -gt 5 ] && echo "   … and $((sk-5)) more"
  fi
  rm -f "$skipf" "$errf"
  [ ${#found[@]} -gt 0 ] && echo "➡️  fx → <action>/<action>.selected.items (copy / move / zip / upload / delete / ...)"
}

_sel_cmd_show() {
  local arg="${1# }" all=false
  [ "$arg" = "all" ] && all=true
  local -a sel=()
  _sel_load_live sel
  if [ ${#sel[@]} -eq 0 ]; then echo "ℹ️  Selection is empty (use .s)"; return; fi
  _sel_summary sel "🎯 Selection"
  [ "$_SEL_VANISHED" -gt 0 ] && echo "⚠️  $_SEL_VANISHED selected item(s) no longer exist (hidden here)"
  local i lim=${#sel[@]}
  $all || [ "$lim" -le 100 ] || lim=100
  for (( i=0; i<lim; i++ )); do
    printf '%4d) %s\n' $((i+1)) "$(_sel_short "${sel[$i]}")"
  done
  [ "$lim" -lt ${#sel[@]} ] && echo "   … and $(( ${#sel[@]} - lim )) more  (.s.show all)"
}

_sel_cmd_shown() {
  if ${imaginary_mode:-false}; then
    echo "⚠️  Too many items to list — narrow the view (group filter or fs) first"
    return
  fi
  if [ ${#items[@]} -eq 0 ]; then echo "ℹ️  Nothing displayed"; return; fi
  local -a out=("${items[@]}")
  _sel_save out
  _sel_summary out "🎯 Selected what's displayed"
  _sel_preview out
  echo "➡️  fx → <action>/<action>.selected.items (copy / move / zip / upload / delete / ...)"
}
