#!/usr/bin/env bash
# bashbasicsbyvk_select.sh — the  .s  select commands and  .r  rule commands
# ════════════════════════════════════════════════════════════════════════════
#  .s <expression>       select (ADDS; persists across folders)
#  .us <expression>      unselect matches
#  .s.set <expression>   replace the whole selection
#  .s.add / .s.sub       aliases of .s / .us
#  .s.show [all]  .s.clr  .s.shown
#  .r  .r.save  .r.run  .r.edit  .r.rename  .r.del
#
#  Matching is done by _3bvk_select_core (python3).  This file only handles
#  the prompts, the CSV pickers (existing open_csv_menu), storage and output.
#
#  Storage (plain text, user-editable, same style as buffers / swlinks):
#    ~/.bashbasicsbyvk/selection.list        one absolute path per line
#    ~/.bashbasicsbyvk/rules/NAME.rule       KEY=VALUE lines
#    ~/.bashbasicsbyvk/rules/.last           last select expression (for .r.save)
# ════════════════════════════════════════════════════════════════════════════

_SEL_FILE="${HOME}/.bashbasicsbyvk/selection.list"
_SEL_RULES_DIR="${HOME}/.bashbasicsbyvk/rules"
_SEL_LAST_FILE="${_SEL_RULES_DIR}/.last"

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
LOGIC  space or &  = AND      |  = OR      !  = NOT      ( )  groups
 -r  at the end = search subfolders
AFTER  .s.add EXPR  .s.sub EXPR  .s.show  .s.clr  .s.shown
       then fx → <action>/<action>.selected.items  (copy move shortcut bookmark
       upload upload.text map zip unzip delete);  file_fx/selection = view only
RULES  .r  .r.save NAME [EXPR]  .r.run NAME  .r.edit  .r.rename  .r.del
DISPLAY  .d <same expressions>   .d.clr   .d.save   .d.run   (see .d)
FAVOURITES  fa <numbers | sel | .s expression>   ns   (see: fa help)
HLP
}

# ── evaluate an expression → _SEL_FOUND (shared by .s, .d and fa) ─────────────
# Runs one existing CSV picker per .csv clause. Returns 1 on error / cancel
# (message already printed).
declare -ga _SEL_FOUND=()
_sel_eval() {
  local expr="$1"
  _SEL_FOUND=()
  _sel_ensure_store

  # 0) index selection by displayed number:  1-5   1,2,3-7,11   a-5 (all except 5)
  #    (optionally written with the .s prefix)
  local _ix="${expr#.us}"; _ix="${_ix#.s}"
  _ix="${_ix//[[:space:]]/}"
  if [[ "$_ix" =~ ^(a-[0-9][0-9,-]*|[0-9][0-9,-]*)$ ]]; then
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
    .r|.r.*|.r\ *) handle_rule_cmd "$raw"; return ;;
    .s.show|.s.show\ *)  _sel_cmd_show "${raw#.s.show}"; return ;;
    .s.clr) _sel_ensure_store; : > "$_SEL_FILE"; _sel_bump; echo "🧹 Selection cleared"; return ;;
    .s.shown)            _sel_cmd_shown; return ;;
    .s|.s\ help|.s.help|-h) _sel_help; return ;;
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
  local -a found=("${_SEL_FOUND[@]}")
  printf '%s' "$expr" > "$_SEL_LAST_FILE" 2>/dev/null

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

# ══════════════════════════════════════════════════════════════════════════════
#  Rules  (.r)
# ══════════════════════════════════════════════════════════════════════════════
_rule_field() {                     # _rule_field <file> <KEY>
  local v
  v=$(grep -m1 -i "^$2=" "$1" 2>/dev/null)
  printf '%s' "${v#*=}"
}

_rule_valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

_rule_list() {
  _sel_ensure_store
  local f n=0
  for f in "$_SEL_RULES_DIR"/*.rule; do
    [ -f "$f" ] || continue
    n=$((n+1))
    local nm; nm=$(basename "$f" .rule)
    local d; d=$(_rule_field "$f" DESC)
    printf '%3d) %s   [%s]\n      %s%s\n' "$n" "$nm" "$(_rule_field "$f" SCOPE)" "$(_rule_field "$f" EXPR)" "${d:+   — $d}"
  done
  if [ "$n" -eq 0 ]; then
    echo "ℹ️  No rules yet.  Run a .s command, then:  .r.save NAME"
  else
    echo "Files: $_SEL_RULES_DIR/NAME.rule  (edit with .r.edit NAME)"
  fi
}

_rule_save() {
  local args="$1" name expr
  name="${args%% *}"
  expr=""; [[ "$args" == *" "* ]] && expr="${args#* }"
  if [ -z "$name" ]; then echo "⚠️  Usage: .r.save NAME [expression]   (no expression = last .s command)"; return; fi
  if [ -z "$expr" ]; then
    [ -f "$_SEL_LAST_FILE" ] && expr=$(cat "$_SEL_LAST_FILE")
    [ -z "$expr" ] && { echo "ℹ️  No previous .s command to save — give an expression"; return; }
  fi
  _rule_save_as select "$name" "$expr"
}

# _rule_save_as <scope: select|display> <name> <expr>
_rule_save_as() {
  local scope="$1" name="$2" expr="$3"
  if ! _rule_valid_name "$name"; then echo "❌ Rule names: letters, digits, _ and - only"; return; fi
  local errf; errf=$(mktemp)
  local scan
  if ! scan=$(_sel_core scan "$expr" 2>"$errf"); then
    echo "❌ $(sed 's/^ERR: //' "$errf")"; rm -f "$errf"; return
  fi
  rm -f "$errf"
  local rec=false
  [[ "$scan" == *"RECURSIVE=1"* ]] && rec=true
  local file="$_SEL_RULES_DIR/$name.rule" ans desc
  if [ -f "$file" ]; then
    read -p "Rule '$name' exists — overwrite? (y/n): " ans
    [[ "$ans" == [yY] ]] || { echo "🚫 Cancelled"; return; }
  fi
  read -p "Description (optional): " desc
  _sel_ensure_store
  {
    echo "NAME=$name"
    echo "SCOPE=$scope"
    echo "EXPR=$expr"
    echo "RECURSIVE=$rec"
    echo "DESC=$desc"
  } > "$file"
  if [ "$scope" = "display" ]; then
    echo "💾 Saved display preset '$name'  →  .d.run $name"
  else
    echo "💾 Saved rule '$name'  →  .r.run $name   or   .s.rule $name"
  fi
}

_rule_editor() {
  local ed="${EDITOR:-}"
  [ -z "$ed" ] && { command -v nano >/dev/null 2>&1 && ed=nano || ed=vi; }
  "$ed" "$1"
}

handle_rule_cmd() {
  local raw="$1" cmd rest=""
  cmd="${raw%% *}"
  [[ "$raw" == *" "* ]] && rest="${raw#* }"
  local name="${rest%% *}"
  case "$cmd" in
    .r)        _rule_list ;;
    .r.save)   _rule_save "$rest" ;;
    .r.run)
      [ -z "$name" ] && { echo "⚠️  Usage: .r.run NAME"; return; }
      handle_select_cmd ".s.rule $name" ;;
    .r.edit)
      [ -z "$name" ] && { echo "⚠️  Usage: .r.edit NAME"; return; }
      [ -f "$_SEL_RULES_DIR/$name.rule" ] || { echo "❌ Rule '$name' not found"; return; }
      _rule_editor "$_SEL_RULES_DIR/$name.rule"
      local ex; ex=$(_rule_field "$_SEL_RULES_DIR/$name.rule" EXPR)
      local msg
      if ! msg=$(_sel_core scan "$ex" 2>&1 >/dev/null); then
        echo "⚠️  Rule saved but its expression has a problem: ${msg#ERR: }"
      else
        echo "✅ Rule '$name' updated"
      fi ;;
    .r.rename)
      local new="${rest#* }"
      if [ -z "$name" ] || [ "$new" = "$rest" ] || [ -z "$new" ]; then echo "⚠️  Usage: .r.rename OLD NEW"; return; fi
      _rule_valid_name "$new" || { echo "❌ Rule names: letters, digits, _ and - only"; return; }
      [ -f "$_SEL_RULES_DIR/$name.rule" ] || { echo "❌ Rule '$name' not found"; return; }
      [ -e "$_SEL_RULES_DIR/$new.rule" ] && { echo "❌ '$new' already exists"; return; }
      mv -- "$_SEL_RULES_DIR/$name.rule" "$_SEL_RULES_DIR/$new.rule"
      sed -i "s/^NAME=.*/NAME=$new/" "$_SEL_RULES_DIR/$new.rule"
      echo "✅ Renamed '$name' → '$new'" ;;
    .r.del)
      [ -z "$name" ] && { echo "⚠️  Usage: .r.del NAME"; return; }
      [ -f "$_SEL_RULES_DIR/$name.rule" ] || { echo "❌ Rule '$name' not found"; return; }
      local ans; read -p "Delete rule '$name'? (y/n): " ans
      if [[ "$ans" == [yY] ]]; then rm -f -- "$_SEL_RULES_DIR/$name.rule"; echo "🗑️  Deleted rule '$name'"; else echo "🚫 Cancelled"; fi ;;
    *) echo "⚠️  Rule commands: .r  .r.save  .r.run  .r.edit  .r.rename  .r.del" ;;
  esac
}
