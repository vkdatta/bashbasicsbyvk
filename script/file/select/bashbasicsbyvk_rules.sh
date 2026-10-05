#!/usr/bin/env bash
# bashbasicsbyvk_rules.sh — the  .r  rule book (an inner loop, like fx / sw)
# ════════════════════════════════════════════════════════════════════════════
#  .r   opens the rule book.  Everything is done with the loop's own commands
#       (no .r.save / .r.run / .r.edit / .r.rename / .r.del any more).
#
#  Tabs (← / → to cycle when input is empty):
#    🧩 Rules      the rule book:   select/  display/   (two built-in folders)
#    🕘 Last used  the last 100 expressions you used that are NOT in the book
#
#  Rules tab                                     Last used tab
#    N      open folder / run rule N               N    save expression N as a rule
#    c      create a rule here                     clr  clear the list
#    d      delete rules (multi-select)
#    r      rename a rule
#    e-N    edit rule N's expression (.rule)       Both
#    em-N   edit rule N's description (.meta)        u     up / exit at the top
#    i-N    show rule N (status, why it is broken)   .r    close      fx / sw  switch loop
#    ux     export ALL rules to one zip              p-…   path map of the listed items
#    ui     import ALL rules from a zip              (same p- as every other loop)
#
#  Storage  (plain text, hand-editable)
#    ~/.bashbasicsbyvk/rules/select/NAME/NAME.rule   the expression — the file IS the rule
#    ~/.bashbasicsbyvk/rules/select/NAME/NAME.meta   description (free text)
#    ~/.bashbasicsbyvk/rules/display/NAME/...        same, for .d rules
#    ~/.bashbasicsbyvk/rules/.history                last used, unsaved (newest first)
#
#  • A rule has no NAME= / SCOPE= / EXPR= / RECURSIVE= / DESC= fields any more:
#    the name is the folder, the scope is the folder it sits in, the expression
#    is the .rule file, and recursion is just a -r written in the expression.
#  • select/ and display/ cannot be deleted or renamed.
#  • c inside select/ makes a select rule, inside display/ a display rule.
#  • A select rule that uses .d clauses (or the reverse), has an expression that
#    does not parse, or has no .rule file is shown with the suffix  [broken rule].
#
#  Uses (from the main app): _sel_core, _sel_ensure_store, handle_select_cmd,
#  _disp_set, select_items_common, parse_selection, _vp_* viewport, _inner_run
# ════════════════════════════════════════════════════════════════════════════

_RL_HIST_MAX=100
_RL_ICON="🧩"

_rl_tab="rules"      # rules | last
_rl_cur=""           # "" = book root,  else  select | display

declare -gA _RL_ST=() _RL_EX=() _RL_DS=() _RL_RS=()      # "kind/name" → status / expr / desc / reason
declare -ga _RL_NAMES_select=() _RL_NAMES_display=()

_rule_valid_name() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

_rl_hist_file() { printf '%s/.history' "$_SEL_RULES_DIR"; }
_rl_dir()       { printf '%s/%s/%s' "$_SEL_RULES_DIR" "$1" "$2"; }       # kind name

_rl_editor() {
  local ed="${EDITOR:-}"
  [ -z "$ed" ] && { command -v nano >/dev/null 2>&1 && ed=nano || ed=vi; }
  "$ed" "$1"
}

_rule_editor() { _rl_editor "$@"; }         # kept: favourites / daemon settings use this name

# ── ux / ui : export / import ALL rules (same engine as the fx UDF tab) ───────
# Only select/ and display/ travel (not .history). Layout is enforced on import:
# select|display / NAME / file — nothing may land anywhere else in the rule store.
_RL_MANIFEST="bvk_rules_manifest.txt"
_RL_FORMAT=1
_RL_ENTRY_RE='^(select|display)/([^/]+/([^/]+)?)?$'

_rl_export() {
  _bz_need zip || return 1
  _rl_ensure_store
  _bz_export "$_SEL_RULES_DIR" "$(_bz_dest "${path:-}" "$_SEL_RULES_DIR")" \
    rules_export "$_RL_MANIFEST" BVK_RULES_EXPORT "$_RL_FORMAT" rules select display
}

_rl_import() {
  _bz_need unzip || return 1
  _rl_ensure_store
  _bz_import "$_SEL_RULES_DIR" "${path:-$PWD}" \
    "$_RL_MANIFEST" BVK_RULES_EXPORT "$_RL_FORMAT" rules rules "$_RL_ENTRY_RE"
}

# "mango" / "mango.txt" / "mango.rule" → mango
_rl_clean_name() {
  local n="$1"
  n="${n#"${n%%[![:space:]]*}"}"; n="${n%"${n##*[![:space:]]}"}"
  [[ "$n" == *.* && "$n" != .* ]] && n="${n%.*}"
  printf '%s' "$n"
}

# ── store ─────────────────────────────────────────────────────────────────────
_rl_ensure_store() {
  _sel_ensure_store
  mkdir -p "$_SEL_RULES_DIR/select" "$_SEL_RULES_DIR/display" 2>/dev/null
  _rl_migrate_legacy
}

# One-time: rules/NAME.rule (KEY=VALUE format) → rules/<scope>/NAME/NAME.rule + .meta
_rl_migrate_legacy() {
  local f nm scope expr desc rec k v n=0 skipped=0 dir
  local old="$_SEL_RULES_DIR/.legacy"
  for f in "$_SEL_RULES_DIR"/*.rule; do
    [ -f "$f" ] || continue
    nm="${f##*/}"; nm="${nm%.rule}"
    scope=select; expr=""; desc=""; rec=""
    while IFS= read -r line || [ -n "$line" ]; do
      k="${line%%=*}"; v="${line#*=}"
      case "${k^^}" in
        SCOPE)     [ "${v,,}" = display ] && scope=display ;;
        EXPR)      expr="${v%%  #*}" ;;
        RECURSIVE) rec="${v,,}" ;;
        DESC)      desc="$v" ;;
      esac
    done < "$f"
    if [ "$scope" = select ] && [[ "$rec" == true || "$rec" == 1 || "$rec" == yes ]] \
       && ! [[ " $expr " == *" -r "* || "$expr" == *count\<* ]]; then
      expr="$expr -r"                    # the old RECURSIVE flag now lives in the expression
    fi
    dir="$(_rl_dir "$scope" "$nm")"
    if _rule_valid_name "$nm" && [ ! -e "$dir" ]; then
      mkdir -p "$dir" && printf '%s\n' "$expr" > "$dir/$nm.rule" && printf '%s\n' "$desc" > "$dir/$nm.meta" \
        && { mkdir -p "$old"; mv -f -- "$f" "$old/"; n=$((n+1)); continue; }
    fi
    skipped=$((skipped+1))
  done
  rm -f -- "$_SEL_RULES_DIR/.last" 2>/dev/null
  [ "$n" -gt 0 ] && echo "📦 Rule book upgraded: $n rule(s) moved into select/ and display/  (originals kept in rules/.legacy)"
  [ "$skipped" -gt 0 ] && echo "⚠️  $skipped old rule file(s) could not be moved (name clash / bad name) — left in $_SEL_RULES_DIR"
  return 0
}

# Fill the _RL_* tables (both kinds, 2 python runs total).
_rl_audit_all() {
  _RL_ST=(); _RL_EX=(); _RL_DS=(); _RL_RS=()
  _RL_NAMES_select=(); _RL_NAMES_display=()
  local kind name st ex ds rs
  for kind in select display; do
    while IFS=$'\x1f' read -r name st ex ds rs; do
      [ -n "$name" ] || continue
      _RL_ST["$kind/$name"]="$st"; _RL_EX["$kind/$name"]="$ex"
      _RL_DS["$kind/$name"]="$ds"; _RL_RS["$kind/$name"]="$rs"
      if [ "$kind" = select ]; then _RL_NAMES_select+=("$name"); else _RL_NAMES_display+=("$name"); fi
    done < <(_sel_core rules "$kind" 2>/dev/null)
  done
}

# Write a rule bundle.  _rl_write_bundle <kind> <name> <expr> <desc>
_rl_write_bundle() {
  local dir; dir="$(_rl_dir "$1" "$2")"
  mkdir -p "$dir" || return 1
  printf '%s\n' "$3" > "$dir/$2.rule" || return 1
  printf '%s\n' "$4" > "$dir/$2.meta" || return 1
}

# Is <path> a deletable / renamable bundle (rules/select/X or rules/display/X)?
_rl_is_bundle() {
  local p="$1" parent
  [ -d "$p" ] || return 1
  parent="${p%/*}"
  [ "$parent" = "$_SEL_RULES_DIR/select" ] || [ "$parent" = "$_SEL_RULES_DIR/display" ]
}

# Other rules in <kind> that mention  .s.rule NAME / .d.rule NAME
_rl_refs_to() {
  local kind="$1" name="$2" f n=0
  for f in "$_SEL_RULES_DIR/$kind"/*/*.rule; do
    [ -f "$f" ] || continue
    [ "${f%/*}" = "$_SEL_RULES_DIR/$kind/$name" ] && continue
    grep -qE "^[^#]*\.[sd]\.rule[[:space:]]+$name([[:space:]]|\$)" "$f" 2>/dev/null && n=$((n+1))
  done
  echo "$n"
}

# ── save entry points (also used by  .d.save) ────────────────────────────────
# _rule_save_as <select|display> <name> <expr>  — validate, confirm overwrite, write
_rule_save_as() {
  local scope="$1" name="$2" expr="$3" ans desc
  _rl_ensure_store
  if ! _rule_valid_name "$name"; then echo "❌ Rule names: letters, digits, _ and - only"; return 1; fi
  local errf scan; errf=$(mktemp)
  if ! scan=$(_sel_core scan "$expr" 2>"$errf"); then
    echo "❌ $(sed 's/^ERR: //' "$errf")"; rm -f "$errf"; return 1
  fi
  rm -f "$errf"
  local want=s; [ "$scope" = display ] && want=d
  local heads; heads=$(sed -n 's/^HEADS=//p' <<<"$scan")
  if [ "$heads" != "$want" ]; then
    echo "❌ That expression uses .${heads//[^sd]/} clauses — it can't be a $scope rule (use .$want ...)"; return 1
  fi
  local dir; dir="$(_rl_dir "$scope" "$name")"
  if [ -e "$dir" ]; then
    read -r -p "Rule '$name' exists in $scope — overwrite the expression? (y/n): " ans
    [[ "$ans" == [yY] ]] || { echo "🚫 Cancelled"; return 1; }
    printf '%s\n' "$expr" > "$dir/$name.rule"
    echo "💾 Updated $scope rule '$name'"; return 0
  fi
  read -r -p "📝 Description (optional): " desc
  _rl_write_bundle "$scope" "$name" "$expr" "$desc" || { echo "❌ Could not write the rule"; return 1; }
  echo "💾 Saved $scope rule '$name'   (.r to manage it)"
}

_rule_delete_bundle() {          # _rule_delete_bundle <kind> <name>   (asks y/n)
  local kind="$1" name="$2" ans dir; dir="$(_rl_dir "$kind" "$name")"
  _rl_is_bundle "$dir" || { echo "❌ $kind rule '$name' not found"; return 1; }
  read -r -p "Delete $kind rule '$name'? (y/n): " ans
  if [[ "$ans" == [yY] ]]; then rm -rf -- "$dir"; echo "🗑️  Deleted rule '$name'"; else echo "🚫 Cancelled"; fi
}

# ── last used (unsaved) ──────────────────────────────────────────────────────
# Called after every successful .s / .d expression.  Newest first, no dupes, max 100.
_rule_hist_add() {
  local expr="$1" h tmp
  expr="${expr#"${expr%%[![:space:]]*}"}"; expr="${expr%"${expr##*[![:space:]]}"}"
  [[ "$expr" == .[sd]* ]] || return 0
  [[ "$expr" =~ ^\.[sd]\.rule[[:space:]]+[A-Za-z0-9_-]+$ ]] && return 0      # just running a saved rule
  h="$(_rl_hist_file)"
  mkdir -p "$_SEL_RULES_DIR" 2>/dev/null
  tmp="$h.tmp.$$"
  { printf '%s\n' "$expr"; [ -f "$h" ] && grep -vxF -- "$expr" "$h"; } | head -n "$_RL_HIST_MAX" > "$tmp" \
    && mv -f -- "$tmp" "$h"
  return 0
}

declare -ga _rl_hist=()
_rl_hist_build() {               # → _rl_hist[]  (history minus anything already in the book)
  _rl_hist=()
  local h; h="$(_rl_hist_file)"
  [ -s "$h" ] || return 0
  local -A saved=()
  local k
  for k in "${!_RL_EX[@]}"; do [ -n "${_RL_EX[$k]}" ] && saved["${_RL_EX[$k]}"]=1; done
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    [ -n "${saved[$line]+x}" ] && continue
    _rl_hist+=("$line")
  done < "$h"
}

# ── rows ──────────────────────────────────────────────────────────────────────
_rl_trunc() {                    # _rl_trunc <text> <max>
  local t="$1" m="$2"
  if [ "${#t}" -gt "$m" ]; then printf '%s…' "${t:0:$((m-1))}"; else printf '%s' "$t"; fi
}

_rl_rowtext() {
  local i="$1" p="${items[$((i-1))]}" name key
  if [ "$_rl_tab" = last ]; then
    printf -v _vp_line " %2d) 🕘 %s" "$i" "$(_rl_trunc "$p" 70)"; return
  fi
  if [ -z "$_rl_cur" ]; then                       # book root: the two built-in folders
    local kind="${p##*/}" n=0 d lbl=".s rules"
    [ "$kind" = display ] && lbl=".d rules"
    for d in "$p"/*/; do [ -d "$d" ] && n=$((n+1)); done
    printf -v _vp_line " %2d) 📁 %s   (%s · %d)" "$i" "$kind" "$lbl" "$n"; return
  fi
  name="${p##*/}"; key="$_rl_cur/$name"
  local line; printf -v line " %2d) %s %s" "$i" "$_RL_ICON" "$name"
  [ "${_RL_ST[$key]:-broken}" = broken ] && line+="  [broken rule]"
  [ -n "${_RL_EX[$key]:-}" ] && line+="   $(_rl_trunc "${_RL_EX[$key]}" 36)"
  [ -n "${_RL_DS[$key]:-}" ] && line+="  — $(_rl_trunc "${_RL_DS[$key]}" 28)"
  _vp_line="$line"
}

# ── tabs ──────────────────────────────────────────────────────────────────────
_rl_tab_next() { if [ "$_rl_tab" = rules ]; then _rl_tab=last; else _rl_tab=rules; fi; }
_rl_tab_label() {
  local a="🧩 Rules" b="🕘 Last used"
  if [ "$_rl_tab" = rules ]; then printf '[%s]   %s' "$a" "$b"; else printf ' %s  [%s]' "$a" "$b"; fi
}

_rl_menu_header() {
  echo
  printf '📚 RULE BOOK  %s   ←/→ tabs\n' "$(_rl_tab_label)"
  if [ "$_rl_tab" = rules ]; then
    printf '🗂️  /%s\n' "$_rl_cur"
    [ -n "$_rl_cur" ] && printf '  u) Up   (in: /%s)\n' "$_rl_cur"
  else
    printf '🕘 Last %d expressions not in the rule book — type a number to save one\n' "$_RL_HIST_MAX"
  fi
  _vp_filter_header_line
}

_rl_menu_footer() {
  if [ "$_rl_tab" = last ]; then
    printf '\n[Last used]  %d unsaved expression(s)\n' "${#items[@]}"
    printf 'N) Save as rule   clr) Clear list   u) Exit   .r) Close\n'
  elif [ -z "$_rl_cur" ]; then
    printf '\n[Rules]  select = .s rules · display = .d rules  (built in — cannot be deleted)\n'
    printf 'N) Open folder   ux) Export all   ui) Import all   u) Exit   .r) Close\n'
  else
    printf '\n[%s rules]  %d here\n' "$_rl_cur" "${#items[@]}"
    printf 'N) Run   c) Create   d) Delete   r) Rename   u) Up\n'
    printf 'e-N) Edit rule   em-N) Edit description   i-N) Info   .r) Close\n'
    printf 'ux) Export all   ui) Import all\n'
  fi
}

_rl_set_viewport() {
  _vp_mode="items"
  _vp_rowtext_fn=_rl_rowtext
  _vp_header_fn=_rl_menu_header
  _vp_footer_fn=_rl_menu_footer
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  _vp_cache_reset
}

_rl_build_items() {
  imaginary_mode=false
  _filter_reset_state
  items=()
  _hl_index=0
  _rl_audit_all
  if [ "$_rl_tab" = last ]; then
    _rl_hist_build
    items=("${_rl_hist[@]}")
  elif [ -z "$_rl_cur" ]; then
    items=("$_SEL_RULES_DIR/select" "$_SEL_RULES_DIR/display")
  else
    local -n _nm="_RL_NAMES_$_rl_cur"
    local n
    for n in "${_nm[@]}"; do items+=("$_SEL_RULES_DIR/$_rl_cur/$n"); done
  fi
  _all_items=("${items[@]}")
}

_rl_redraw_fresh() {
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  _rl_build_items
  _rl_set_viewport
  _vp_render_from_top
}

_rl_tab_redraw() {
  local _old_blk_h="${_blk_h:-0}"
  _rl_build_items
  _rl_set_viewport
  _vp_tab_repaint "$_old_blk_h"
}

# ── helpers for commands that take a row number ──────────────────────────────
# _rl_pick <N> → sets _rl_p (path) _rl_n (name) ; only valid inside select/ or display/
_rl_p=""; _rl_n=""
_rl_pick() {
  local num="$1"
  if [ "$_rl_tab" != rules ] || [ -z "$_rl_cur" ]; then
    echo "⚠️  Open select/ or display/ first, then use this on a rule number"; return 1
  fi
  if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#items[@]}" ]; then
    echo "⚠️  Invalid rule number: $num"; return 1
  fi
  _rl_p="${items[$((num-1))]}"; _rl_n="${_rl_p##*/}"
  return 0
}

_rl_report() {                   # re-audit and say how <kind>/<name> stands
  local kind="$1" name="$2" key="$1/$2"
  _rl_audit_all
  if [ "${_RL_ST[$key]:-broken}" = ok ]; then echo "✅ Rule '$name' is OK   ${_RL_EX[$key]}"
  else echo "⚠️  Rule '$name' is a [broken rule]: ${_RL_RS[$key]:-unknown problem}"; fi
}

# ── commands ──────────────────────────────────────────────────────────────────
_rl_cmd_run() {                  # N inside select/ or display/ → apply the rule
  _rl_pick "$1" || return 1
  local key="$_rl_cur/$_rl_n"
  if [ "${_RL_ST[$key]:-broken}" != ok ]; then
    echo "⚠️  '$_rl_n' is a [broken rule]: ${_RL_RS[$key]:-unknown problem}"
    echo "   e-$1 to fix it"
    return 1
  fi
  if [ "$_rl_cur" = select ]; then
    _SEL_EVAL_OK=0
    handle_select_cmd ".s.rule $_rl_n"
    [ "$_SEL_EVAL_OK" = 1 ]
  else
    _disp_set ".d.rule $_rl_n"
  fi
}

_rl_cmd_create() {
  local kind="$_rl_cur" ans name raw expr desc
  if [ -z "$kind" ]; then
    echo; echo "Create a rule:"; echo "1) select rule  (.s ...)"; echo "2) display rule (.d ...)"
    read -r -p "Choice [1-2]: " ans
    case "$ans" in
      u|U) return 1 ;;
      q|Q) _bvk_quit ;;
      1) kind=select ;;
      2) kind=display ;;
      *) echo "Invalid choice"; return 1 ;;
    esac
  fi
  local head=.s; [ "$kind" = display ] && head=.d
  read -r -p "📄 Rule name (e.g. mango or mango.txt): " raw
  case "$raw" in u|U) return 1 ;; q|Q) _bvk_quit ;; esac
  name="$(_rl_clean_name "$raw")"
  if [ -z "$name" ]; then echo "🚫 Cancelled"; return 1; fi
  if ! _rule_valid_name "$name"; then echo "❌ Rule names: letters, digits, _ and - only"; return 1; fi
  if [ -e "$(_rl_dir "$kind" "$name")" ]; then echo "❌ A $kind rule called '$name' already exists"; return 1; fi
  read -r -p "✏️  Expression (e.g. $head.ext png ; blank = open editor): " expr
  case "$expr" in u|U) return 1 ;; q|Q) _bvk_quit ;; esac
  read -r -p "📝 Description (optional): " desc
  _rl_write_bundle "$kind" "$name" "$expr" "$desc" || { echo "❌ Could not create the rule"; return 1; }
  if [ -z "$expr" ]; then
    printf '# %s — %s rule.  Write ONE expression below; this file is the rule.\n# e.g.  %s.ext png,jpg    %s.size >3mb -r    %s.rule other_rule\n' \
      "$name" "$kind" "$head" "$head" "$head" > "$(_rl_dir "$kind" "$name")/$name.rule"
    _rl_editor "$(_rl_dir "$kind" "$name")/$name.rule"
  fi
  echo "✅ Created $kind rule '$name'  ${_RL_ICON}"
  _rl_report "$kind" "$name"
}

_rl_cmd_delete() {
  if [ "$_rl_tab" != rules ]; then echo "⚠️  Not available in the Last used tab"; return 1; fi
  if [ -z "$_rl_cur" ]; then
    echo "🔒 'select' and 'display' are built in and can't be deleted — open one and delete rules inside it"
    return 1
  fi
  if [ "${#items[@]}" -eq 0 ]; then echo "ℹ️  No rules here"; return 1; fi
  select_items_common "DELETE" allow_a || return 1
  local -a doomed=(); local p
  for p in "${selected_items[@]}"; do
    if _rl_is_bundle "$p"; then doomed+=("$p"); else echo "🔒 Skipping protected item: ${p##*/}"; fi
  done
  [ "${#doomed[@]}" -gt 0 ] || return 1
  local refs=0 r
  for p in "${doomed[@]}"; do r=$(_rl_refs_to "$_rl_cur" "${p##*/}"); refs=$((refs + r)); done
  [ "$refs" -gt 0 ] && echo "⚠️  $refs other rule(s) refer to what you are deleting — they will become [broken rule]"
  local ans
  read -r -p "Delete ${#doomed[@]} rule(s)? This can't be undone. (y/n): " ans
  if [[ "$ans" != [yY] ]]; then echo "🚫 Deletion cancelled"; return 1; fi
  for p in "${doomed[@]}"; do rm -rf -- "$p"; done
  echo "✅ Deleted ${#doomed[@]} rule(s)"
}

_rl_cmd_rename() {
  if [ "$_rl_tab" != rules ]; then echo "⚠️  Not available in the Last used tab"; return 1; fi
  if [ -z "$_rl_cur" ]; then
    echo "🔒 'select' and 'display' are built in and can't be renamed"; return 1
  fi
  if [ "${#items[@]}" -eq 0 ]; then echo "ℹ️  No rules here"; return 1; fi
  local num raw new
  read -r -p "✏️  Rename which rule number? " num
  case "$num" in u|U|"") return 1 ;; q|Q) _bvk_quit ;; esac
  _rl_pick "$num" || return 1
  _rl_is_bundle "$_rl_p" || { echo "🔒 Protected item"; return 1; }
  read -r -p "📝 New name for '$_rl_n': " raw
  case "$raw" in u|U|"") echo "🚫 Cancelled"; return 1 ;; q|Q) _bvk_quit ;; esac
  new="$(_rl_clean_name "$raw")"
  _rule_valid_name "$new" || { echo "❌ Rule names: letters, digits, _ and - only"; return 1; }
  [ "$new" = "$_rl_n" ] && { echo "ℹ️  Same name — nothing to do"; return 1; }
  [ -e "$(_rl_dir "$_rl_cur" "$new")" ] && { echo "❌ '$new' already exists"; return 1; }
  local refs; refs=$(_rl_refs_to "$_rl_cur" "$_rl_n")
  local old="$_rl_p" dst; dst="$(_rl_dir "$_rl_cur" "$new")"
  mv -- "$old" "$dst" || { echo "❌ Rename failed"; return 1; }
  local ext
  for ext in rule meta; do
    [ -f "$dst/$_rl_n.$ext" ] && mv -- "$dst/$_rl_n.$ext" "$dst/$new.$ext"
  done
  echo "✅ Renamed '$_rl_n' → '$new'"
  [ "$refs" -gt 0 ] && echo "⚠️  $refs other rule(s) still say '$_rl_n' — edit them (e-N) or they become [broken rule]"
  return 0
}

_rl_cmd_edit() {                 # _rl_cmd_edit <rule|meta> <N>
  local what="$1"; _rl_pick "$2" || return 1
  local f="$_rl_p/$_rl_n.$what"
  if [ ! -f "$f" ]; then
    mkdir -p "$_rl_p"; : > "$f"
  fi
  _rl_editor "$f"
  [ "$what" = rule ] && _rl_report "$_rl_cur" "$_rl_n" || echo "✅ Description updated"
}

_rl_cmd_info() {
  _rl_pick "$1" || return 1
  local key="$_rl_cur/$_rl_n"
  echo "🧩 $_rl_n   ($_rl_cur rule)"
  echo "   expression : ${_RL_EX[$key]:-(none)}"
  echo "   description: ${_RL_DS[$key]:-(none)}"
  if [ "${_RL_ST[$key]:-broken}" = ok ]; then echo "   status     : ✅ OK"
  else echo "   status     : ⚠️  [broken rule] — ${_RL_RS[$key]:-unknown problem}"; fi
  echo "   files      : $_rl_p/$_rl_n.rule  ·  $_rl_n.meta"
}

# Last used tab: N → save expression N as a rule
_rl_cmd_save_hist() {
  local num="$1"
  if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#items[@]}" ]; then
    echo "⚠️  Invalid number: $num"; return 1
  fi
  local expr="${items[$((num-1))]}" scan heads kind errf raw name desc
  errf=$(mktemp)
  if ! scan=$(_sel_core scan "$expr" 2>"$errf"); then
    echo "❌ $(sed 's/^ERR: //' "$errf")"; rm -f "$errf"; return 1
  fi
  rm -f "$errf"
  heads=$(sed -n 's/^HEADS=//p' <<<"$scan")
  case "$heads" in
    s) kind=select ;;
    d) kind=display ;;
    *) echo "❌ This expression mixes .s and .d clauses — it can't be one rule"; return 1 ;;
  esac
  echo "💾 $expr   → will be a $kind rule"
  read -r -p "📄 Rule name (u = cancel): " raw
  case "$raw" in u|U|"") echo "🚫 Cancelled"; return 1 ;; q|Q) _bvk_quit ;; esac
  name="$(_rl_clean_name "$raw")"
  _rule_valid_name "$name" || { echo "❌ Rule names: letters, digits, _ and - only"; return 1; }
  [ -e "$(_rl_dir "$kind" "$name")" ] && { echo "❌ A $kind rule called '$name' already exists"; return 1; }
  read -r -p "📝 Description (optional): " desc
  _rl_write_bundle "$kind" "$name" "$expr" "$desc" || { echo "❌ Could not save"; return 1; }
  local h tmp; h="$(_rl_hist_file)"; tmp="$h.tmp.$$"
  grep -vxF -- "$expr" "$h" > "$tmp" 2>/dev/null; mv -f -- "$tmp" "$h"
  echo "✅ Saved $kind rule '$name' ${_RL_ICON}   (open the Rules tab → $kind)"
}

_rl_help() {
  cat <<'HLP'
📚 RULE BOOK  (.r)   ← / → switch tabs
 Rules tab:  N open folder / run rule · c create · d delete · r rename
             e-N edit expression · em-N edit description · i-N info · u up
 Last used:  N save that expression as a rule · clr clear list
 ux export all rules to a zip · ui import rules from a zip (Rules tab) · p-… path map of items
 select/ holds .s rules, display/ holds .d rules (built in, can't be deleted).
 A rule is a folder:  NAME/NAME.rule (the expression)  +  NAME/NAME.meta (description)
 -r inside the expression makes a rule recursive.  Rules may use  .s.rule OTHER  (5 levels).
 [broken rule] = wrong kind (.d in select / .s in display), bad expression, or missing file.
 fx / sw switch loop · .r or u at the top closes.
HLP
}

# ── entry from the main loop ─────────────────────────────────────────────────
#  main loop:   .r | .r.* | .r <anything>  → handle_select_cmd → here
handle_rule_cmd() {
  local raw="$1"
  if [ "$raw" != ".r" ]; then
    echo "ℹ️  Rules are managed inside the rule book now — c create · d delete · r rename · e-N edit"
  fi
  _inner_run r
}

# ── the loop ──────────────────────────────────────────────────────────────────
rules_menu() {
  _rl_ensure_store

  local _rl_saved_prefix="$group_prefix" _rl_saved_force="$force_show"
  local _rl_saved_all=("${_all_items[@]}")
  _rl_tab="rules"
  _rl_cur=""
  group_prefix=""
  force_show=false
  _fx_in_mode=1
  _sw_in_mode=1                    # enables the ←/→ tab sentinels

  local _rl_choice _rl_fresh
  shopt -s nullglob

  _rl_redraw_fresh

  while true; do
    _read_choice_filtered
    _rl_choice="$choice"
    shopt -s nocasematch

    case "$_rl_choice" in
      __sw_tab_right__|__sw_tab_left__)
        _rl_tab_next; _rl_cur=""
        _rl_tab_redraw
        shopt -u nocasematch; continue ;;
    esac

    _rl_fresh=true
    case "$_rl_choice" in

      .r|.R)
        echo "↩️  Closing the rule book"; break ;;

      fx|FX) _inner_next=fx; break ;;
      sw|SW) _inner_next=sw; break ;;

      q) _fx_in_mode=0; _sw_in_mode=0; _bvk_quit ;;

      -h) _rl_help; _rl_fresh=false ;;

      u)
        if [ "$_rl_tab" = rules ] && [ -n "$_rl_cur" ]; then _rl_cur=""
        else echo "↩️  Closing the rule book"; break; fi ;;

      c)
        if [ "$_rl_tab" = rules ]; then _rl_cmd_create || _rl_fresh=false
        else echo "⚠️  Not available in the Last used tab — type a number to save an expression"; _rl_fresh=false; fi ;;

      d)  _rl_cmd_delete || _rl_fresh=false ;;
      r)  _rl_cmd_rename || _rl_fresh=false ;;

      e-*)  _rl_cmd_edit rule "${_rl_choice#[eE]-}" || _rl_fresh=false ;;
      em-*) _rl_cmd_edit meta "${_rl_choice#[eE][mM]-}" || _rl_fresh=false ;;
      i-*)  _rl_cmd_info "${_rl_choice#[iI]-}"; _rl_fresh=false ;;

      clr)
        if [ "$_rl_tab" = last ]; then
          local _a; read -r -p "Clear the last-used list? Your saved rules are not touched. (y/N): " _a
          if [[ "$_a" == [yY] ]]; then : > "$(_rl_hist_file)"; echo "✅ Last-used list cleared"; else echo "🚫 Cancelled"; _rl_fresh=false; fi
        else echo "⚠️  clr works in the Last used tab"; _rl_fresh=false; fi ;;

      ux|rules.export)
        if [ "$_rl_tab" = rules ]; then _rl_export; else echo "⚠️  Not available in the Last used tab"; fi
        _rl_fresh=false ;;

      ui|rules.import)
        if [ "$_rl_tab" = rules ]; then _rl_import || _rl_fresh=false      # list is rebuilt below (new rules appear)
        else echo "⚠️  Not available in the Last used tab"; _rl_fresh=false; fi ;;

      p-*)  handle_staging_map "$_rl_choice" ;;

      f)    find_menu; _rl_fresh=false ;;
      disk) df -h; _rl_fresh=false ;;
      ram)  free -h; _rl_fresh=false ;;

      _*) _rl_fresh=false ;;

      *)
        if ! [[ "$_rl_choice" =~ ^[0-9]+$ ]] || [ "$_rl_choice" -lt 1 ] || [ "$_rl_choice" -gt "${#items[@]}" ]; then
          echo "⚠️  Invalid selection"; _rl_fresh=false
        elif [ "$_rl_tab" = last ]; then
          _rl_cmd_save_hist "$_rl_choice" || _rl_fresh=false
        elif [ -z "$_rl_cur" ]; then
          _rl_cur="${items[$((_rl_choice-1))]##*/}"          # open select/ or display/
        else
          if _rl_cmd_run "$_rl_choice"; then
            shopt -u nocasematch
            break                                              # applied → back to the file view
          fi
          _rl_fresh=false
        fi ;;
    esac

    shopt -u nocasematch
    $_rl_fresh && _rl_redraw_fresh
  done

  shopt -u nocasematch
  _fx_in_mode=0
  _sw_in_mode=0
  _vp_rowtext_fn=""
  group_prefix="$_rl_saved_prefix"
  force_show="$_rl_saved_force"
  _all_items=("${_rl_saved_all[@]}")
}
