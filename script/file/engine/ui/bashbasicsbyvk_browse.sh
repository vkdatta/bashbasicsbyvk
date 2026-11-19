declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
get_abs_path() {
  local target="$1"
  if [ -d "$target" ]; then
    cd -- "$target" && pwd
  elif [ -f "$target" ]; then
    local dir=$(dirname -- "$target")
    local base=$(basename -- "$target")
    echo "$(cd -- "$dir" && pwd)/$base"
  else
    echo "Error: '$target' does not exist" >&2
    return 1
  fi
}

# goto [path] — move the list to a path. Asks when no path is typed. A file path opens the folder that holds it.
# ~ and relative paths work; surrounding quotes (from a paste or a drag) are dropped.
handle_goto() {
  local arg="${1#goto}" dest target
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then echo "☁️  Google Drive is open — leave it with gdx first, then use goto"; return 0; fi
  arg="${arg#"${arg%%[![:space:]]*}"}"
  dest="$arg"
  if [ -z "$dest" ]; then
    _bvk_read dest "Path to go to: " || return 0
    [ "${_CM_ABORT:-0}" = 1 ] && return 0
  fi
  dest="${dest%$'\r'}"
  dest="${dest#"${dest%%[![:space:]]*}"}"; dest="${dest%"${dest##*[![:space:]]}"}"
  case "$dest" in \"*\"|\'*\') dest="${dest:1:${#dest}-2}" ;; esac
  [ -n "$dest" ] || { echo "🚫 Cancelled — no path given."; return 0; }
  case "$dest" in "~") dest="$HOME" ;; "~/"*) dest="$HOME/${dest#"~/"}" ;; esac
  [[ "$dest" == /* ]] || dest="${path%/}/$dest"
  if [ -d "$dest" ]; then target="$dest"
  elif [ -e "$dest" ]; then target="${dest%/*}"; [ -n "$target" ] || target="/"; echo "📄 That is a file — opening the folder that holds it"
  else echo "❌ Not found: $dest"; return 0; fi
  if [ ! -r "$target" ] || [ ! -x "$target" ]; then echo "❌ No permission to open: $target"; return 0; fi
  target="$(get_abs_path "$target")" || return 0
  path="$target"; group_prefix=""; force_show=false
  echo "📂 Now in: $path"
  return 0
}


# count_items_in_path — single os.scandir, ~80ms for 200k.
count_items_in_path() {
  local p="$1"
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin; then
    local _h=0; [ "${show_hidden_files:-false}" = "true" ] && _h=1
    "$_BVK_GO_BIN" count "$p" "$_h" 2>/dev/null || echo 0
    return
  fi
  python3 - "$p" "${show_hidden_files:-false}" <<'PYEOF'
import os, sys
path = sys.argv[1]
show_hidden = sys.argv[2] == "true"
try:
    n = sum(
        1 for e in os.scandir(path)
        if e.name not in (".", "..") and (show_hidden or not e.name.startswith("."))
    )
    print(n)
except Exception:
    print(0)
PYEOF
}

# _bvk_prefix_scan — files matching group_prefix.
_bvk_prefix_scan_py() {
  local p="$1"
  local pfx="$2"
  python3 - "$p" "$pfx" "${show_hidden_files:-false}" <<'PYEOF'
import os, sys
path = sys.argv[1]
pfx  = sys.argv[2].lower()
show_hidden = sys.argv[3] == "true"
try:
    with os.scandir(path) as it:
        for e in it:
            bn = e.name
            if bn in (".", ".."): continue
            if not show_hidden and bn.startswith("."): continue
            if pfx and not bn.lower().startswith(pfx): continue
            print(e.path)
except Exception as ex:
    sys.stderr.write(f"scandir: {ex}\n")
PYEOF
}

# C first, Python if the binary is missing or fails (stdout form, legacy).
_bvk_prefix_scan() {
  local _h=0; [ "${show_hidden_files:-false}" = "true" ] && _h=1
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && "$_BVK_GO_BIN" scan "$1" raw "$_h" "$2" 2>/dev/null; then return 0; fi
  _bvk_prefix_scan_py "$1" "$2"
}

# items[] = entries starting with group prefix $2 in dir $1 (file-based read,
# records _BVK_LOAD_SRC for the header tag).
_bvk_load_prefix_items() {
  local _h=0; [ "${show_hidden_files:-false}" = "true" ] && _h=1
  local _f; _f="$(_bvk_tmp prefix)" || return 1
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && "$_BVK_GO_BIN" scan "$1" raw "$_h" "$2" >"$_f" 2>/dev/null; then
    _BVK_LOAD_SRC=c
  else
    _BVK_LOAD_SRC=py
    _bvk_prefix_scan_py "$1" "$2" >"$_f" 2>/dev/null
  fi
  _BVK_META_SRC=""
  mapfile -t items <"$_f"
  case "$_f" in "${_BVK_DSIZE_TMP:-/nonexistent}"/*) : >"$_f" ;; *) rm -f "$_f" ;; esac   # a re-used file: truncate (no process)
}

# items[] = the "#" group of prefix $2 (names whose next char is not a letter,
# digit or a known special). C `hashscan`; Python when Unicode rules are needed.
_bvk_load_hash_items() {
  local _h=0; [ "${show_hidden_files:-false}" = "true" ] && _h=1
  local _f; _f="$(_bvk_tmp hash)" || return 1
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && "$_BVK_GO_BIN" hashscan "$1" "$_h" "$2" >"$_f" 2>/dev/null; then
    _BVK_LOAD_SRC=c
  else
    _BVK_LOAD_SRC=py
    _bvk_fallback_scan "$1" "$2" >"$_f" 2>/dev/null
  fi
  _BVK_META_SRC=""
  mapfile -t items <"$_f"
  case "$_f" in "${_BVK_DSIZE_TMP:-/nonexistent}"/*) : >"$_f" ;; *) rm -f "$_f" ;; esac   # a re-used file: truncate (no process)
}

# Group-key rule — the ONE definition of "which group does this file fall in".
#   next char after the prefix: letter → UPPER, digit → itself, one of SPECIALS →
#   itself, anything else → "#".   Used by get_imaginary_groups, _bvk_fallback_scan
#   and the filter's imaginary scan (settings/bashbasicsbyvk_filter.sh).
#   _bvk_py_group <args…> <<'PYEOF' … PYEOF   runs python with SPECIALS and
#   group_key(nxt) already defined; sys.argv works exactly like `python3 - args`.
_BVK_GKEY_PY='SPECIALS = set("_.-()[]{}@!~+=^&%$,;'"'"' ")
def group_key(nxt):
    if nxt.isalpha(): return nxt.upper()
    if nxt.isdigit(): return nxt
    if nxt in SPECIALS: return nxt
    return "#"'
_bvk_py_group() { python3 -c "${_BVK_GKEY_PY}
$(cat)" "$@"; }

# _bvk_fallback_scan — the "#" branch in handle_selection.
_bvk_fallback_scan() {
  local p="$1"
  local pfx="$2"
  _bvk_py_group "$p" "$pfx" "${show_hidden_files:-false}" <<'PYEOF'
import os, sys
path = sys.argv[1]
pfx  = sys.argv[2].lower()
show_hidden = sys.argv[3] == "true"
pfx_len = len(pfx)
try:
    with os.scandir(path) as it:
        for e in it:
            bn = e.name
            if bn in (".", ".."): continue
            if not show_hidden and bn.startswith("."): continue
            bl = bn.lower()
            if pfx and not bl.startswith(pfx): continue
            if len(bl) <= pfx_len: continue
            if group_key(bl[pfx_len]) != "#":
                continue
            print(e.path)
except Exception as ex:
    sys.stderr.write(f"scandir: {ex}\n")
PYEOF
}

build_items_for_prefix() {
  build_items_with_meta "$1" "$2"
  apply_sort
}

build_all_items() {
  build_items_with_meta "$1" ""
  apply_sort
}

# get_imaginary_groups — unfiltered.
get_imaginary_groups() {
  local p="$1"
  local pfx="$2"
  declare -gA group_counts=()
  group_chars=()

  local py_out _gh=0
  [ "${show_hidden_files:-false}" = "true" ] && _gh=1
  _BVK_META_SRC=""
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && py_out=$("$_BVK_GO_BIN" groups "$p" "$_gh" "$pfx" 2>/dev/null); then
    _BVK_LOAD_SRC=c
  else
  _BVK_LOAD_SRC=py
  py_out=$(_bvk_py_group "$p" "$pfx" "${show_hidden_files:-false}" <<'PYEOF'
import os, sys
path = sys.argv[1]
pfx  = sys.argv[2].lower()
show_hidden = sys.argv[3] == "true"
pfx_len = len(pfx)

counts = {}
order  = []

try:
    with os.scandir(path) as it:
        for e in it:
            bn = e.name
            if bn in (".", ".."): continue
            if not show_hidden and bn.startswith("."): continue
            bl = bn.lower()
            if len(bl) <= pfx_len: continue
            if pfx and not bl.startswith(pfx): continue
            ch = group_key(bl[pfx_len])
            if ch not in counts:
                counts[ch] = 0
                order.append(ch)
            counts[ch] += 1
except Exception as ex:
    sys.stderr.write(f"scandir: {ex}\n")

for ch in order:
    print(f"{ch}\t{counts[ch]}")
PYEOF
  )
  fi

  while IFS=$'\t' read -r ch cnt; do
    [ -z "$ch" ] && continue
    group_counts["$ch"]="$cnt"
    group_chars+=("$ch")
  done <<< "$py_out"
}

# _rebuild_imaginary_display — sort + format block.
_rebuild_imaginary_display() {
  local total="$1"
  if [ -n "${_filter_query:-}" ]; then
    _imag_banner="📂 $total matching items (filtered). Imaginary groups by next character:"
  else
    _imag_banner="📂 Too many items ($total). Imaginary groups by next character:"
  fi

  local specials=() digits=() letters=() fallback=()
  for ch in "${group_chars[@]}"; do
    if   [[ "$ch" =~ ^[A-Z]$ ]]; then letters+=("$ch")
    elif [[ "$ch" =~ ^[0-9]$ ]]; then digits+=("$ch")
    elif [[ "$ch" == "#" ]];      then fallback+=("$ch")
    else                               specials+=("$ch")
    fi
  done

  local -a sorted_specials=() sorted_digits=() sorted_letters=()
  if [ ${#specials[@]} -gt 0 ]; then
    IFS=$'\n' sorted_specials=($(builtin printf '%s\n' "${specials[@]}" | sort))
  fi
  if [ ${#digits[@]} -gt 0 ]; then
    IFS=$'\n' sorted_digits=($(builtin printf '%s\n' "${digits[@]}" | sort))
  fi
  if [ ${#letters[@]} -gt 0 ]; then
    IFS=$'\n' sorted_letters=($(builtin printf '%s\n' "${letters[@]}" | sort))
  fi
  unset IFS

  local sorted=("${sorted_specials[@]}" "${sorted_digits[@]}" "${sorted_letters[@]}" "${fallback[@]}")

  imaginary_map=()
  imaginary_lines=()
  local idx=1
  for ch in "${sorted[@]}"; do
    [ -z "$ch" ] && continue
    local cnt="${group_counts[$ch]:-0}"
    imaginary_lines+=("$(builtin printf ' %2d) 📁 %s (%d items)' "$idx" "$ch" "$cnt")")
    imaginary_map+=("$ch")
    idx=$((idx+1))
  done
}

build_imaginary_groups() {
  local p="$1"
  local pfx="$2"
  local total="$3"
  get_imaginary_groups "$p" "$pfx"
  _rebuild_imaginary_display "$total"
}

display_imaginary_groups() {
  build_imaginary_groups "$1" "$2" "$3"
  builtin printf "%s\n" "$_imag_banner" "${imaginary_lines[@]}"
}

# Index mode (big folders) — the ONE place that decides "list it" or "show prefix groups".
# Shared by the fx / switch loops (_bvk_build_path_items) and the transfer navigator.

# _bvk_prefix_matches <dir> <prefix>  → _bvk_pfx_items[]: the visible entries of <dir> whose lower-cased name starts with <prefix>
_bvk_prefix_matches() {
  local _f _bn
  _bvk_pfx_items=()
  while IFS= read -r -d '' _f; do
    _bn="${_f##*/}"
    [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
    ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
    [[ "${_bn,,}" != "$2"* ]] && continue
    _bvk_pfx_items+=("$_f")
  done < <(find "$1" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
}

# _bvk_index_decide <dir> <prefix> <force_show: true|false>
#   sets  _bvk_ix_kind   groups = too many entries: show prefix groups (_bvk_ix_pfx / _bvk_ix_count are the arguments for
#                                 build_imaginary_groups / display_imaginary_groups)
#                        flat   = the prefix narrows it down to a listable set: _bvk_pfx_items[]
#                        none   = list the folder normally (small, or force_show) — the caller's usual builder runs
_bvk_index_decide() {
  local _dir="$1" _pfx="$2" _force="$3" _total
  local _thr="${index_mode_threshold:-200}"
  _bvk_ix_kind=none; _bvk_ix_pfx="$_pfx"; _bvk_ix_count=0; _bvk_pfx_items=()
  _total=$(count_items_in_path "$_dir")
  { [ "$_total" -gt "$_thr" ] && ! $_force; } || return 0
  _bvk_ix_kind=groups; _bvk_ix_count="$_total"
  [ -n "$_pfx" ] || return 0
  _bvk_prefix_matches "$_dir" "$_pfx"
  _bvk_ix_count="${#_bvk_pfx_items[@]}"
  [ "$_bvk_ix_count" -le "$_thr" ] && _bvk_ix_kind=flat
  return 0
}

# _bvk_build_path_items — fills items[] / imaginary_mode for the folder `path` (+ group_prefix, force_show) in the fx and switch loops.
_bvk_build_path_items() {
  _has_group_view=false
  [ "${#group_view_levels[@]}" -gt 0 ] && _has_group_view=true
  _bvk_index_decide "$path" "$group_prefix" "$force_show"
  case "$_bvk_ix_kind" in
    groups) imaginary_mode=true; build_imaginary_groups "$path" "$_bvk_ix_pfx" "$_bvk_ix_count" ;;
    flat)   imaginary_mode=false; items=("${_bvk_pfx_items[@]}"); _collect_metadata; apply_sort ;;
  esac
  if ! $imaginary_mode; then
    if [ ${#items[@]} -eq 0 ] && [ -n "$group_prefix" ]; then
      build_items_with_meta "$path" "$group_prefix"; apply_sort
    elif [ ${#items[@]} -eq 0 ]; then
      build_items_with_meta "$path" ""; apply_sort
    fi
  fi
}

# ── ONE item-picker screen for every "choose items to <action>" job in the folder view (Rename, Delete, Remove bookmark / favourite, Unorganise, Extract, Info ...)
#     <icon> <Title>
#
#     📂 cd path / ☁️ nav path        (the same rows as the folder view: _loc_rows)
#
#     Select items to <action>
#     ─────  the rows  ─────
#     u) Up   q) Close
#     Select:
# A caller passes only its title ("🗑️ Delete"); the action in the sentence is the title without the icon, in lower case.
# The layout is the template 7UH852 (templates/bashbasicsbyvk_7UH852.sh.tpl); this file only hands it the data.
_pk_header() {
  _tpl_clear; _tpl_set menu_name "$_PK_TITLE" what "$_PK_WHAT" action "$_PK_ACTION" nav_path_text "" footer_style row footer_items "u.up q.close"
  _tpl_section 7UH852 menu_header
}
_pk_footer() { _tpl_section 7UH852 menu_footer; }

# _pk_set "<icon> <Title>" items|groups   → _PK_TITLE _PK_ACTION _PK_WHAT
_pk_set() {
  _PK_TITLE="$1"; _PK_WHAT="$2"
  _PK_ACTION="${1#* }"; _PK_ACTION="${_PK_ACTION,,}"
}

# select_items_common "<icon> <Title>" [allow_a]
#   allow_a: also accept  a  (all)  and  a-<exclusions>  (all except),
#            e.g. a-1-5,7 — same grammar as the c-/m-/s- staging shortcuts.
# rc 1 = nothing chosen (u / q / blank / bad numbers).
select_items_common() {
  local _PK_TITLE _PK_ACTION _PK_WHAT
  _pk_set "$1" items
  local _multi_allow_a=false
  [ "${2:-}" == "allow_a" ] && _multi_allow_a=true
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available"
    return 1
  fi
  local _multi_header_hook=_pk_header _multi_footer_hook=_pk_footer _multi_label="Select" _multi_hdr_gap=1 _prompt="$1"
  local -A _msel_set=()
  local _buf _pos itemlist
  _vp_mode="items"
  _multi_prompt_loop
  itemlist="${_buf// /}"
  case "${itemlist,,}" in u|q|"") return 1 ;; esac
  local indices=()
  if $_multi_allow_a && [[ "$itemlist" == "a" ]]; then
    indices=($(seq 1 "${#items[@]}"))
  elif $_multi_allow_a && [[ "$itemlist" =~ ^a-(.+)$ ]]; then
    indices=($(_sp_parse_all_except "${BASH_REMATCH[1]}" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ All-except filter excluded every item"
      return 1
    fi
  else
    indices=($(parse_selection "$itemlist" "${#items[@]}"))
  fi
  selected_items=()
  for idx in "${indices[@]}"; do
    selected_items+=("${items[$((idx-1))]}")
  done
  if [ ${#selected_items[@]} -eq 0 ]; then
    echo "❌ No valid items selected"
    return 1
  fi
  return 0
}

# select_imaginary_items_common PATH PREFIX ["<icon> <Title>"]
#   a title = the shared picker screen above ("Select groups to <action>"); no title = a step inside a flow (Transfer) that has its own header
select_imaginary_items_common() {
  local p="$1"
  local pfx="$2"
  local _PK_TITLE _PK_ACTION _PK_WHAT
  local _multi_header_hook="" _multi_footer_hook="" _multi_label="" _multi_hdr_gap=0
  if [ -n "${3:-}" ]; then
    _pk_set "$3" groups
    _multi_header_hook=_pk_header _multi_footer_hook=_pk_footer _multi_label="Select" _multi_hdr_gap=1
  fi
  if [ "${#imaginary_map[@]}" -eq 0 ]; then
    echo "❌ No groups available"
    return 1
  fi
  local _prompt="${3:-GROUPS}"
  local -A _msel_set=()
  local _buf _pos
  _vp_mode="imaginary"
  _multi_prompt_loop
  case "${_buf// /}" in [uUqQ]|"") return 1 ;; esac
  local indices=($(parse_selection "$_buf" "${#imaginary_map[@]}"))
  if [ "${#indices[@]}" -eq 0 ]; then
    echo "❌ No valid groups selected"
    return 1
  fi
  selected_items=()
  for idx in "${indices[@]}"; do
    local ch="${imaginary_map[$((idx-1))]}"
    local ch_lower="${ch,,}"
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ! $show_hidden_files && [[ "$bn" == .* ]] && continue
      local bn_lower="${bn,,}"
      [[ "$bn_lower" != "$pfx"* ]] && continue
      local next_char="${bn_lower:${#pfx}:1}"
      if [ "$ch" == "#" ]; then
        case "$next_char" in
          [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ')
            continue ;;
        esac
      else
        [[ "$next_char" != "$ch_lower" ]] && continue
      fi
      selected_items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  done
  local -A _seen=()
  local unique=()
  for f in "${selected_items[@]}"; do
    [ -z "${_seen[$f]+x}" ] && unique+=("$f") && _seen["$f"]=1
  done
  selected_items=("${unique[@]}")
  if [ "${#selected_items[@]}" -eq 0 ]; then
    echo "❌ No items found for selected groups"
    return 1
  fi
  return 0
}

handle_force_show() {
  if $force_show; then
    force_show=false
    echo "🔓 Force show disabled"
  else
    force_show=true
    echo "🔓 Force show enabled — displaying all items"
  fi
}

handle_selection() {
  local choice="$1"
  # Group view crumb menu: a number picks that crumb (drill one level down)
  if ${_gv_crumb_menu:-false} && $imaginary_mode; then
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= ${#imaginary_map[@]} )); then
      _gv_crumbs+=("${imaginary_map[$((10#$choice-1))]}")
    else
      _bvk_invalid
    fi
    return
  fi
  if $imaginary_mode; then
    local matched=false
    local ch=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"
      matched=true
    elif [[ ${#choice} -eq 1 ]]; then
      local uc="${choice^^}"
      for gc in "${imaginary_map[@]}"; do
        if [[ "$gc" == "$uc" ]] || [[ "$gc" == "$choice" ]]; then
          ch="$gc"; matched=true; break
        fi
      done
    fi
    if $matched; then
      if [ "$ch" == "#" ]; then
        imaginary_mode=false
        items=()
        _bvk_load_hash_items "$path" "$group_prefix"
        _collect_metadata
        apply_sort
      elif [[ "$ch" =~ ^[A-Z]$ ]]; then
        group_prefix="${group_prefix}${ch,,}"
        force_show=false
      else
        group_prefix="${group_prefix}${ch}"
        force_show=false
      fi
    else
      _bvk_invalid
    fi
  else
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
      selected="${items[$((choice-1))]}"
      local bn="${selected##*/}"
      if [[ "$bn" == *.shortcut ]]; then
        local sc_target sc_type
        sc_target=$(_shortcut_resolve "$selected")
        if [ $? -ne 0 ]; then
          echo "💡 The shortcut file is still present — you can delete or rename it."
          return
        fi
        sc_type=$(_shortcut_read_field "$selected" "SHORTCUT_TYPE")
        if [ "$sc_type" == "dir" ] || [ -d "$sc_target" ]; then
          path="$sc_target"; group_prefix=""; force_show=false
        else
          handle_file "$sc_target"
        fi
        return
      fi
      if [ -d "$selected" ]; then
        path="$selected"; group_prefix=""; force_show=false
      elif [ -f "$selected" ]; then
        handle_file "$selected"
      fi
    else
      _bvk_invalid
    fi
  fi
}

# ── the status row:   c | ⏰ <notifications> | 📣 <unfinished uploads>
# The first field is the engine that listed this folder: c (native binary) or py (Python fallback) - the old
# "[loaded by c]" tag, moved here (BVK_SHOW_SRC=0 or nothing loaded yet shows –).  The two numbers come from tiny caches
# (_nf_cnt_get / _pn_count_cached), so drawing the header never waits for the network or scans folders.
_bvk_hdr_lang() {
  _bvk_src_tag_v
  case "$_bst_out" in *"by py]"*) _HDR_LANG=py ;; *"by c]"*) _HDR_LANG=c ;; *) _HDR_LANG="–" ;; esac
}
_bvk_hdr_status() {
  local nf="–" pn=0
  if declare -F _nf_cnt_get >/dev/null 2>&1; then _nf_cnt_get; nf="$_NF_CNT"; fi
  if declare -F _pn_count_cached >/dev/null 2>&1; then _pn_count_cached; pn="$_PN_CNT"; fi
  _bvk_hdr_lang
  printf '%s | ⏰ %s | 📣 %s' "$_HDR_LANG" "$nf" "$pn"
}

#   c | ⏰ 0 | 📣 0
#
#   📂 cd path: /data/data/com.termux/files/home          <- where the CURRENT SHELL is cd'ed ($PWD: it does not move while you browse)
#   ☁️ nav path: /data/data/com.termux/files/home         <- where you are browsing (Drive / group / filter marks go here; the loaded-by tag is now the first field of the status row)
# The layout is the template JR9TZ5 (templates/bashbasicsbyvk_JR9TZ5.sh.tpl); $1 = the function that prints the notice rows under the location rows.
_menu_header() {
  _tpl_clear; _tpl_set header_notes "${1:-}"
  _tpl_section JR9TZ5 menu_header
}

# the two location rows of the folder view (cd path / nav path, with the group and filter text): ONE printer, also used by the item picker (_pk_header)
_loc_cd_row() { echo "📂 cd path: $PWD"; }
_loc_nav_row() {
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then _gd_view_path "$path"; else _gd_vp="$path"; fi      # Google Drive open: show the Drive path, not the mirror folder
  local _hdr_loc="☁️ nav path: $_gd_vp${group_prefix:+ [group: ${group_prefix^^}*]}"
  if [ -n "${_RES_HDR:-}" ]; then
    _hdr_loc+="  $_RES_HDR"                                # a results screen (_results_view: Find hits, a preview) names itself here, in the place the "=" filter writes its own text
  elif [ -n "$_filter_query" ]; then
    if ${imaginary_mode:-false}; then
      local _itot=0 _ch
      for _ch in "${group_chars[@]}"; do
        _itot=$(( _itot + ${group_counts[$_ch]:-0} ))
      done
      _hdr_loc+="  🔍 filter: ${_filter_query^^}*  (${_itot} matches)"
    else
      local _fcnt="${#items[@]}"
      local _tcnt; _tcnt="$(_filter_total_count)"
      if [ "$_tcnt" -gt 0 ]; then
        _hdr_loc+="  🔍 filter: ${_filter_query^^}*  (${_fcnt}/${_tcnt} items)"
      else
        _hdr_loc+="  🔍 filter: ${_filter_query^^}*  (${_fcnt} matches)"
      fi
    fi
  fi
  echo "$_hdr_loc"
}
_loc_rows() { _loc_cd_row; _loc_nav_row; }

# ── ONE pick screen for every "choose items / a destination / a file" job (transfer, csv, ...) ──
# Same chrome as the main list: status row, cd path, nav path, and the rows come from the main row renderer (_item_line_text_v:
# icons, 🔒 marks, + marks), so a picker can never look different from the folder view.  A job only passes its name.
#   _pick_header [-s] WHAT JOB NAV_PATH [PREFIX] [DESC]   WHAT = Items | Destination | ...      →  🛷 Select <WHAT> for <JOB>   (WHAT empty: no title, e.g. a results screen)
#   -s  folders can be selected as they are: the line under the title is the s-N suggestion (_pick_suggest) and s-N is the picker's word
#   DESC empty → the Settings description of "Select <what in lower case>|*" (settings_desc.sh); same wrapping as every Settings screen
#   The screen is: title, one dim line, the two path rows, the rows.  No status row, no step banner above it.
#   _pick_rows [-r] PATH...                              -r = the paths are on a remote machine (no lock marks)
_desc_print_dim() {          # _desc_print_dim TEXT_OR_KEY — a dim, wrapped description (the rows-gate and wrapping of the Rename screen)
  local txt="$1" rows cols i dmax
  rows=$(_term_rows 2>/dev/null); cols=$(_term_cols 2>/dev/null)
  [ "${_vp_rows_now:-0}" -gt 0 ] 2>/dev/null && { rows=$_vp_rows_now; cols=$_vp_cols_now; }
  [[ "$rows" =~ ^[0-9]+$ ]] || rows=24; [[ "$cols" =~ ^[0-9]+$ ]] || cols=60
  if declare -F _st_desc_load >/dev/null 2>&1; then { [ -n "${_ST_DESC[Settings|*]:-}" ] || _st_desc_load; }; fi
  [ -n "${_ST_DESC[$txt]:-}" ] && txt="${_ST_DESC[$txt]}"
  [[ "$txt" == *"|*" ]] && return 1                          # still a bare key: the table is not there, so show nothing rather than the key
  [ -n "$txt" ] && (( rows >= 18 )) || return 1            # nothing printed → rc 1 (the caller then adds no blank line)
  if declare -F _st_desc_wrap >/dev/null 2>&1; then
    _st_desc_wrap "$txt" $(( cols - 2 ))
    dmax=$(( rows / 4 )); (( dmax < 2 )) && dmax=2
    for (( i=0; i<${#_ST_DESC_ALL[@]} && i<dmax; i++ )); do printf '\033[2m%s\033[0m\n' "${_ST_DESC_ALL[$i]}"; done
  else
    printf '\033[2m%s\033[0m\n' "$txt"
  fi
  return 0
}
# _pick_suggest [NOUN]   the ONE suggestion line of every picker that can select a folder / set as it is (transfer, the fx item picker):
#   it also makes s-N the picker's own word for its next prompt (_MC_PICK_SEL: cmdmap _cm_resolve, _mc_footer, cc)
_pick_suggest() {
  _MC_PICK_SEL=1
  printf '\033[2mSuggestion: Use s-N command to pick %s\033[0m\n' "${1:-folders}"
}
# The layout is the template MG2374 (templates/bashbasicsbyvk_MG2374.sh.tpl).
#   -i ICON   the icon of the title (default 🛷)        -w WORD  the word between WHAT and JOB (default for; delete says to)
#   -n NOUN   what the s-N suggestion names (default folders: "Use s-N command to pick extensions")
_pick_header() {
  local sugg=0 icon="🛷" word="for" noun=""
  while :; do
    case "${1:-}" in
      -s) sugg=1; shift ;;
      -i) icon="$2"; shift 2 ;;
      -w) word="$2"; shift 2 ;;
      -n) noun="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  _tpl_clear; _tpl_set action "" footer_style row footer_items "u.up q.close" icon "$icon" job_word "$word" what "$1" job "$2" nav_path_text "$3${4:+ [group: ${4^^}*]}" pick_suggest "$sugg" pick_suggest_noun "$noun" pick_desc "${5:-}"
  _tpl_section MG2374 menu_header
}
_pick_rows() {                # the rows of a picker WITH their rules (see _pick_rule_open); _pick_rows_raw = the bare rows, for a caller that frames them itself
  local -a _prs_a=("$@")
  [ "${1:-}" = -r ] && _prs_a=("${@:2}")
  _pick_rule_open ${#_prs_a[@]}
  _pick_rows_raw "$@"
  _pick_rule_close
}
_pick_rows_raw() {
  local remote=0
  [ "${1:-}" = -r ] && { remote=1; shift; }
  local -a items=("$@")
  local _hl_index=0 i ln
  if [ ${#items[@]} -eq 0 ]; then echo "🛑 This directory is empty"; return 0; fi
  local display_suffix_set=""                              # no size / time columns: the metadata window only covers the rows around the cursor
  if (( remote )); then
    local -A _LK_SET=()                                    # a remote path is not a local path: no 🔒
  else
    declare -F _lk_load >/dev/null && _lk_load
  fi
  for (( i=1; i<=${#items[@]}; i++ )); do
    _item_line_text_v "$i"; ln="$_ilt_out"
    if declare -F _sel_mark_v >/dev/null 2>&1 && _sel_mark_v "${items[i-1]}" "$ln"; then ln="$_smk_out"; fi     # selected with .s — green "+"
    printf '%s\n' "$ln"
  done
}

# ── ONE pick screen for "choose files by GROUP" (delete by extension, delete by date, ...) — template MG2374, same chrome as the pickers above ──
#   _pick_groups [-i ICON] [-w WORD] WHAT JOB NOUN NAV FILES KEYS LABELS OF OUT      (the last five are variable NAMES in the caller)
#     WHAT / JOB / NOUN   "extensions" "delete" "extensions"  →  🗑️ Select extensions to delete · Suggestion: Use s-N command to pick extensions
#     NAV      the path shown on the nav row            FILES  the files (array)           KEYS  the group keys in row order (array)
#     LABELS   key → the row text (assoc)               OF     file → its group key (assoc)    OUT  the picked files (array, filled)
#   Like the Transfer picker, a pick is MARKED, not final: the row shows a green + (a ~ when only some of its files are marked) and the
#   screen stays; picking a marked row again un-marks it.  c) confirms what is marked.
#   Groups screen:   s-N · s-1,3 · s-2-4 · s-a · 1,3 · 2-4 (or a key typed: py,txt)  mark WHOLE groups  ·  N  go INSIDE group N
#   Inside a group:  its files, one by one: N · 1,3 · 2-4 · s-N · s-a  mark those files  ·  u  back to the groups (the marks stay)
#   rc 0 confirmed (OUT filled) · 1 u on the groups (the caller goes one question back) · 2 q / h / cc ran (unwind) · 3 the flow was cancelled
# The rules above and below the rows.  The viewport draws them when it takes the list over (_VP_TAKEOVER_MIN rows or more, on a tty);
# an empty list or no viewport (not a tty, VK_SMART_MENUS=0) nobody does, so the list prints them itself — exactly what _mc_options does.
_PICK_RULE_OWN=0
_pick_rule_open()  { _PICK_RULE_OWN=0; { _mc_managed && (( ${1:-0} >= ${_VP_TAKEOVER_MIN:-1} )); } || { _PICK_RULE_OWN=1; echo "$_MC_RULE"; }; }
_pick_rule_close() { (( _PICK_RULE_OWN )) && echo "$_MC_RULE"; _PICK_RULE_OWN=0; return 0; }
_pick_group_rows() {          # the group rows: the main list's number column, the caller's label, the mark of the rows picked
  local _pgr_i _pgr_k _pgr_f _pgr_t _pgr_m _pgr_c
  local -A _pgr_tot=() _pgr_on=()
  for _pgr_f in "${_pg_files[@]}"; do
    _pgr_k="${_pg_of[$_pgr_f]}"; _pgr_tot["$_pgr_k"]=$(( ${_pgr_tot[$_pgr_k]:-0} + 1 ))
    [ -n "${_pg_mark[$_pgr_f]+x}" ] && _pgr_on["$_pgr_k"]=$(( ${_pgr_on[$_pgr_k]:-0} + 1 ))
  done
  _pick_rule_open ${#_pg_keys[@]}                        # ONE row (or no viewport): the viewport does not draw the rules, so print them here (same rule as _mc_options)
  for (( _pgr_i=0; _pgr_i<${#_pg_keys[@]}; _pgr_i++ )); do
    _pgr_k="${_pg_keys[$_pgr_i]}"; _pgr_t="${_pgr_tot[$_pgr_k]:-0}"; _pgr_m="${_pgr_on[$_pgr_k]:-0}"; _pgr_c=" "
    if (( _pgr_m > 0 )); then
      if (( _pgr_m >= _pgr_t )); then _pgr_c=$'\033[32m+\033[0m'; else _pgr_c=$'\033[32m~\033[0m'; fi
    fi
    printf '%s%2d) %s' "$_pgr_c" $(( _pgr_i + 1 )) "${_pg_lab[$_pgr_k]}"
    (( _pgr_m > 0 && _pgr_m < _pgr_t )) && printf '  [%d selected]' "$_pgr_m"
    printf '\n'
  done
  _pick_rule_close
}
_pick_marked_rows() {         # the files of one group: the standard picker rows (icons, 🔒) rendered ONCE, a green + on the marked ones
  local _pmr_i _pmr_ln
  local -a _pmr_rows=()
  mapfile -t _pmr_rows < <(_pick_rows_raw "${_pg_in[@]}")
  _pick_rule_open ${#_pg_in[@]}                           # the FILES counted, not the printed lines (an empty list prints one "empty" line that is not a row)
  for (( _pmr_i=0; _pmr_i<${#_pmr_rows[@]}; _pmr_i++ )); do
    _pmr_ln="${_pmr_rows[$_pmr_i]}"
    [ -n "${_pg_mark[${_pg_in[$_pmr_i]}]+x}" ] && _pmr_ln=$'\033[32m+\033[0m'"${_pmr_ln:1}"
    echo "$_pmr_ln"
  done
  _pick_rule_close
}
_pick_groups() {
  local _pg_icon="🛷" _pg_word="for"
  while :; do case "${1:-}" in -i) _pg_icon="$2"; shift 2 ;; -w) _pg_word="$2"; shift 2 ;; *) break ;; esac; done
  local _pg_what="$1" _pg_job="$2" _pg_noun="$3" _pg_nav="$4"
  local -n _pg_files="$5" _pg_keys="$6" _pg_lab="$7" _pg_of="$8" _pg_out="$9"
  local _pg_open="" _pg_ch _pg_rc _pg_n _pg_i _pg_f _pg_t _pg_k _pg_new _pg_msg
  local is_select cleaned_input
  local -a _pg_in=() _pg_idx=() _pg_tok=() _pg_hit=()
  local -A _pg_byname=() _pg_mark=()
  for _pg_k in "${_pg_keys[@]}"; do _pg_byname["${_pg_k,,}"]="$_pg_k"; done
  _pg_out=()
  while true; do
    if [ -z "$_pg_open" ]; then
      _pick_header -s -i "$_pg_icon" -w "$_pg_word" -n "$_pg_noun" "$_pg_what" "$_pg_job" "$_pg_nav"
      _pick_group_rows
      _pg_n=${#_pg_keys[@]}
    else
      _pg_in=()
      for _pg_f in "${_pg_files[@]}"; do [ "${_pg_of[$_pg_f]}" = "$_pg_open" ] && _pg_in+=("$_pg_f"); done
      _pick_header -s -i "$_pg_icon" -w "$_pg_word" -n "files" "files" "$_pg_job" "$_pg_nav  [${_pg_open}]"
      _pick_marked_rows
      _pg_n=${#_pg_in[@]}
    fi
    [ -n "$_pg_msg" ] && { echo "$_pg_msg"; _pg_msg=""; }
    _mc_footer_std -T MG2374 -l "c:Confirm"
    _mc_read _pg_ch "${_TPL_ACCEPTOR} " || { _pg_rc=$?; _mc_unwind && return 2; return "$_pg_rc"; }
    _pg_ch="${_pg_ch#"${_pg_ch%%[![:space:]]*}"}"; _pg_ch="${_pg_ch%"${_pg_ch##*[![:space:]]}"}"
    case "$_pg_ch" in
      q|Q) _bvk_quit; return 2 ;;
      h|H|cc|CC) _mc_std_key "$_pg_ch"; _mc_unwind && return 2 ;;
      u|U) if [ -n "$_pg_open" ]; then _pg_open=""; else return 1; fi ;;
      c|C)
        _pg_out=(); for _pg_f in "${_pg_files[@]}"; do [ -n "${_pg_mark[$_pg_f]+x}" ] && _pg_out+=("$_pg_f"); done
        if [ ${#_pg_out[@]} -eq 0 ]; then _pg_msg="🔴  Nothing selected yet — s-N marks a row, c confirms"; else return 0; fi ;;
      "") _bvk_invalid ;;
      *)
        _pg_idx=()
        _nav_parse_select "$_pg_ch"
        if _nav_sel_ok "$cleaned_input"; then
          if [ -z "$_pg_open" ] && ! $is_select && _nav_index_ok "$cleaned_input" "$_pg_n"; then
            _pg_open="${_pg_keys[$((cleaned_input-1))]}"; continue                 # a plain number on the groups: go INSIDE it
          fi
          _pg_idx=($(_nav_sel_expand "$cleaned_input" "$_pg_n"))
        elif [ -z "$_pg_open" ]; then                                              # a key typed: py,txt · .json
          IFS=',' read -ra _pg_tok <<< "${_pg_ch// /}"
          for _pg_t in "${_pg_tok[@]}"; do
            _pg_t="${_pg_t#.}"; _pg_t="${_pg_t,,}"; [ -z "$_pg_t" ] && continue
            [ -n "${_pg_byname[$_pg_t]+x}" ] || { _pg_idx=(); break; }
            for _pg_i in "${!_pg_keys[@]}"; do [ "${_pg_keys[$_pg_i]}" = "${_pg_byname[$_pg_t]}" ] && _pg_idx+=($((_pg_i+1))); done
          done
        fi
        if [ ${#_pg_idx[@]} -eq 0 ]; then _pg_msg="$_BVK_MSG_INVALID"; continue; fi
        # the files the picked rows stand for
        _pg_hit=()
        if [ -z "$_pg_open" ]; then
          local -A _pg_want=()
          for _pg_i in "${_pg_idx[@]}"; do _pg_want["${_pg_keys[$((_pg_i-1))]}"]=1; done
          for _pg_f in "${_pg_files[@]}"; do [ -n "${_pg_want[${_pg_of[$_pg_f]}]+x}" ] && _pg_hit+=("$_pg_f"); done
          unset _pg_want
        else
          for _pg_i in "${_pg_idx[@]}"; do _pg_hit+=("${_pg_in[$((_pg_i-1))]}"); done
        fi
        # a pick toggles: if every file of it is marked already, un-mark them, else mark them all
        _pg_new=0; for _pg_f in "${_pg_hit[@]}"; do [ -n "${_pg_mark[$_pg_f]+x}" ] || _pg_new=1; done
        if (( _pg_new )); then for _pg_f in "${_pg_hit[@]}"; do _pg_mark["$_pg_f"]=1; done; _pg_t="➕ Selected"
        else for _pg_f in "${_pg_hit[@]}"; do unset "_pg_mark[$_pg_f]"; done; _pg_t="➖ Unselected"; fi
        _pg_msg="$_pg_t ${#_pg_hit[@]} file(s) — total selected: ${#_pg_mark[@]}  (c to confirm)" ;;
    esac
  done
}

# cd: leave the app and open a shell in the folder being browsed (the main loop's  cd  and every screen whose footer prints  cd) Change directory)
_bvk_cd_shell() {
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then echo "☁️  A shell inside the Drive mirror would see empty placeholders — leave with gdx first (or use t to copy out)"; return 0; fi
  _rc_record "$path"; _lt_cleanup; cd "$path" && exec "$SHELL"      # the in-app cd: the folder joins Recents
}

# the notice rows under the location rows: the flat view, then the grouped (imaginary) view
_mh_notes_flat() {
  [ -s "${_SNAP_NOTICE:-}" ] && cat "$_SNAP_NOTICE"        # Snapshots paused: not enough credits
  declare -F _pn_hint >/dev/null 2>&1 && _pn_hint           # unfinished uploads are waiting: pn
  [ -n "${_sel_banner:-}" ] && echo "$_sel_banner"
  [ -n "${_fav_banner:-}" ] && echo "$_fav_banner"
  [ -n "${_disp_banner:-}" ] && echo "$_disp_banner"
  if $_has_group_view; then
    _gv_banner_line; echo
  fi
  return 0
}
_mh_notes_imaginary() {
  [ -n "${_sel_banner:-}" ] && echo "$_sel_banner"
  [ -n "${_fav_banner:-}" ] && echo "$_fav_banner"
  echo "$_imag_banner"
}
_menu_header_flat() { _menu_header _mh_notes_flat; }
_menu_header_imaginary() { _menu_header _mh_notes_imaginary; }

# the footer of the folder view (template JR9TZ5): the registered keys, then the group-view note
_mf_note() {
  if [ "${total:-0}" -gt "${index_mode_threshold:-200}" ] && ! $force_show && [ "${#group_view_levels[@]}" -gt 0 ]; then
    echo "Group view is set but above threshold. Press fs to enable grouped display"
  fi
  return 0
}
_menu_footer_lines() {
  _tpl_clear; _TPL_FOOTER_ARR=("@browse_$([ "${_GD_ACTIVE:-0}" = 1 ] && echo gd || echo main)")
  _tpl_set footer_style chrome footer_note _mf_note
  _tpl_section JR9TZ5 menu_footer
}


# The row UNDER the prompt (kept free by _vp_geometry) shows a dim hint for what is being typed:
#   =   "type to filter live"  (browser terminals: "type, then press Enter to filter")
#   ==  "Enter = search sub-folders"
# The line being typed on is never touched.  _hint_cur = what is on screen now ("?" = unknown).
_hint_cur=""
_hint_want=""

_print_input_line() {
  _BVK_SCR_PROMPT="${_TPL_ACCEPTOR:-Select:}"
  _bvk_draw_input "${_TPL_ACCEPTOR:-Select:} " "$_buf" "$_pos"
}

_update_highlight() {
  local old="$1" new="$2"
  if [ "$old" -ge 1 ] && [ "$old" -ne "$new" ]; then _vp_repaint_row "$old"; fi
  if [ "$new" -ge 1 ]; then _vp_repaint_row "$new"; fi
  return 0
}

_vp_goto() {
  local old="$1" new="$2"
  if _vp_ensure_visible "$new"; then
    _vp_rerender
  else
    _update_highlight "$old" "$new"
    $_vp_input_fn
  fi
}

_nav_jump_to() {
  $_can_nav || return 0
  _vp_count
  (( _vp_n == 0 )) && return 0
  local target="$1" old="${_hl_index:-0}"
  (( target < 1 )) && target=1
  (( target > _vp_n )) && target=$_vp_n
  _hl_index=$target
  _buf="$_hl_index"; _pos=${#_buf}
  if [ "$target" -eq "$old" ]; then $_vp_input_fn; else _vp_goto "$old" "$_hl_index"; fi
  return 0
}

_sync_highlight_from_buf() {
  $_can_nav || return
  (( ${_BLK_ROWS:-1} > 1 )) && return 0      # a multi-row text is never a selection (and the list repaint is row-relative)
  _vp_count
  (( _vp_n == 0 )) && return
  # prefix = letters/digits then 1-2 dashes (ux- up- z- m- c2c- ...); a trailing " as <alias>" is ignored
  local _hl_buf="$_buf"
  [[ "$_hl_buf" == *" as "* || "$_hl_buf" == *" AS "* ]] && _hl_buf="${_hl_buf%% [aA][sS] *}"
  if (( ${#_hl_buf} <= ${_CM_LIVE_MAX:-56} )) && [[ "$_hl_buf" =~ ^([A-Za-z][A-Za-z0-9]*-{1,2}|\.s[[:space:]]*|\.us[[:space:]]*|\.d[[:space:]]+)(a(-[0-9][0-9,-]*)?|[0-9][0-9,-]*)[[:space:]]*$ ]]; then
    local body="${BASH_REMATCH[2]}"
    local -A _old=()
    local k
    for k in "${!_msel_set[@]}"; do _old[$k]=1; done
    _msel_set=()
    local -a _hl_indices=()
    if [[ "$body" == "a" ]]; then
      _hl_indices=($(seq 1 "$_vp_n"))
    elif [[ "$body" =~ ^a-(.+)$ ]]; then
      _hl_indices=($(_sp_parse_all_except "${BASH_REMATCH[1]}" "$_vp_n"))
    else
      _hl_indices=($(parse_selection "$body" "$_vp_n"))
    fi
    for k in "${_hl_indices[@]}"; do _msel_set[$k]=1; done
    if [ "$_vp_hl_fn" != "_vp_is_hl_multi" ]; then
      _vp_hl_fn=_vp_is_hl_multi
      _hl_index=0
      _vp_rerender
    else
      local -A _chg=()
      for k in "${!_old[@]}";      do [ -z "${_msel_set[$k]+x}" ] && _chg[$k]=1; done
      for k in "${!_msel_set[@]}"; do [ -z "${_old[$k]+x}"      ] && _chg[$k]=1; done
      for k in "${!_chg[@]}"; do _vp_repaint_row "$k"; done
      if [[ "$body" != a* ]]; then
        local last="${body##*[,-]}"
        [[ "$last" =~ ^[0-9]+$ ]] && _vp_ensure_visible "$last" && _vp_rerender
      fi
    fi
    _print_input_line
    return
  fi
  if [ "${_vp_hl_fn:-}" = "_vp_is_hl_multi" ]; then
    _msel_set=()
    _vp_hl_fn=_vp_is_hl_single
    _hl_index=0
    _vp_rerender
    _print_input_line
  fi
  [[ "$_buf" =~ ^[0-9]+$ ]] || { _hl_typed_clear; return; }      # emptied (backspace) or not a number: drop the typed highlight
  local n=$((10#$_buf))
  if (( n < 1 || n > _vp_n )); then _hl_typed_clear; return; fi   # 0, 21 or 200 of 20 items: there is no such row — nothing highlighted
  if [ "$n" -ne "${_hl_index:-0}" ]; then
    local old="${_hl_index:-0}"
    _hl_index=$n
    _vp_goto "$old" "$_hl_index"
  fi
  _HL_TYPED=$n
}

_read_choice() {
  if declare -F _cm_read_choice >/dev/null 2>&1; then _cm_read_choice; return $?; fi
  _read_choice_raw
}

# one typed character: the live "=" filter gets it first, otherwise it goes into the buffer
_rc_type_key() {
  local key="$1"
  _is_ctrl_char "$key" && return 0
  _bvk_room 1 || { _bvk_too_large $(( ${#_buf} + 1 )) _print_input_line; return 0; }
  _rc_drop_sel                                       # typing over a selection replaces it
  if ! _filter_on_char "$key"; then
    _te_insert _buf _pos "$key"
    _print_input_line
    _sync_highlight_from_buf
  fi
  return 0
}
# a selected text is deleted before anything is typed / pasted over it; the live "=" filter follows the shorter text
_rc_drop_sel() {
  (( ${_TE_ANC:--1} >= 0 )) || return 0
  local _w=0; [[ "$_buf" == =* ]] && _w=1
  _te_del_sel _buf _pos || return 0
  (( _w )) && _filter_resync
  return 0
}
# an editing key changed the text (Backspace, Delete, cut, word delete, paste of the clipboard, undo ...): the live filter or the
# highlighted number follows it.  _rc_wasf = the line was a "=" filter BEFORE the key (set by the loop).
_rc_edited() {
  if [ "${_rc_wasf:-0}" = 1 ] || [[ "$_buf" == =* ]] || ${_imag_filter_active:-false}; then _filter_resync; return 0; fi
  _print_input_line
  _sync_highlight_from_buf
}
# a pasted text: ONE insert, ONE redraw (never key by key). "=" starts the live filter, which also gets the text in one piece.
_rc_paste_text() {
  local t="$1"
  [ -z "$t" ] && return 0
  _bvk_room "${#t}" || { _bvk_too_large $(( ${#_buf} + ${#t} )) _print_input_line drain; return 0; }   # over 512 characters: refused, redrawn
  _rc_drop_sel                                       # a paste over a selection replaces it
  if [ -z "$_buf" ] && [ "${t:0:1}" = "=" ]; then
    if _filter_on_char "="; then t="${t:1}"; fi   # the filter starts (snapshot, hint) ... (if it did not: "=" stays part of the text)
    [ -z "$t" ] && return 0
    _filter_on_char "$t" || _te_insert _buf _pos "$t"   # ... and takes the rest at once
    _print_input_line
    return 0
  fi
  if [[ "$_buf" == =* ]]; then
    _filter_on_char "$t" || _te_insert _buf _pos "$t"
    _print_input_line
    return 0
  fi
  _te_insert _buf _pos "$t"
  _print_input_line
  _sync_highlight_from_buf
}
# a whole text at once (what cc types in)
_rc_type_text() {
  _buf="$1"; _pos=${#_buf}
  _print_input_line
  _sync_highlight_from_buf
}

# ── mouse / touch (see bashbasicsbyvk_mouse.sh)
# wheel / swipe: scroll the highlight (clamped, no wrap-around: a wheel that jumps from the top to the bottom is useless)
# At the first / last row, or with the touch outside the block (above its header / below its prompt), the wheel goes back to the terminal.
_rc_wheel() {
  _bvk_blk_park
  _bvk_mouse_wheel_outside && return 0
  $_can_nav || { _bvk_mouse_pass; return 0; }
  local before="${_hl_index:-0}"
  if [ "$1" = up ]; then _nav_jump_to $(( ${_hl_index:-1} - _BVK_WHEEL_STEP ))
  else                   _nav_jump_to $(( ${_hl_index:-0} + _BVK_WHEEL_STEP )); fi
  (( ${_BLK_ROWS:-1} > 1 )) && _print_input_line
  [ "${_hl_index:-0}" = "$before" ] && _bvk_mouse_pass
  return 0
}
# a left click / tap at (_MS_X, _MS_Y).   returns 2 = double click: accept the line now (Enter)
#                                         3 = a header tap: the line (_buf) is already set, accept it
#                                         0 = handled
_rc_click() {      # called by _bvk_edit_run for a press that is not on the typed text (the tap on the text is the engine's)
  local rc=0
  case "$_MS_KIND" in
    item)
      _bvk_mouse_dbl "i:$_MS_ITEM" && rc=2
      _nav_jump_to "$_MS_ITEM" ;;                            # highlight + type its number in the prompt (exactly what the arrow keys do)
    pgup) _BVK_LAST_ITEM=""; _nav_jump_to $(( ${_hl_index:-1} - _vp_page_step )) ;;
    pgdn) _BVK_LAST_ITEM=""; _nav_jump_to $(( ${_hl_index:-0} + _vp_page_step )) ;;
    *)
      if _bvk_mouse_other "$_MS_Y" "$_BVK_CROW"; then            # a footer key (double tap only) or the prompt row (hands the touch back)
        case "$_MS_FACT" in
          run)  _buf="$_MS_FTEXT"; _pos=${#_buf}; rc=3 ;;        # u) Up  →  "u" typed and Enter, as if pressed
          type) _buf="$_MS_FTEXT"; _pos=${#_buf}; _sync_highlight_from_buf ;;   # x-N  →  "x-" typed, the number is yours
        esac
      elif _bvk_mouse_hdr_hit "$_MS_Y" "$_BVK_CROW"; then
        _BVK_LAST_ITEM=""
        case "$_MS_HKIND" in
          cmd) _bvk_mouse_hdr_ok && { _buf="$_MS_CMD"; _pos=${#_buf}; rc=3; } ;;        # py | ⏰ 0 | 📣 0  →  lang | nf | pn, as if typed
          tab) [ "${_sw_in_mode:-0}" = 1 ] && { _BVK_TAB_STEPS=$_MS_TABDELTA; _BVK_TAB_SCREEN="${_vp_header_fn:-}"; } ;;   # consumed at the top of the key loop
          nav) _bvk_mouse_nav_ok && [ -d "$_MS_NAV" ] && { _BVK_NAV_TARGET="$_MS_NAV"; _buf="__navpath__"; _pos=${#_buf}; rc=3; } ;;
        esac
      else _BVK_LAST_ITEM=""; fi ;;
  esac
  (( ${_BLK_ROWS:-1} > 1 )) && _print_input_line
  (( rc == 3 )) && [ "$_buf" != "__navpath__" ] && _print_input_line     # show the command that was "typed"
  return $rc
}

_rc_start() {
  _print_input_line
  _lt_ready menu
  # cc: the command picked from the cheat-code list is typed in for you (it does not run until Enter)
  [ -n "${_CC_PREFILL:-}" ] && _cc_replay _rc_type_key _rc_type_text
  return 0
}
_rc_pre() { _rc_wasf=0; [[ "$_buf" == =* ]] && _rc_wasf=1; return 0; }
# a tab was tapped (bashbasicsbyvk_mouse.sh): feed the ←/→ sentinel once per turn, exactly as if the arrow key had been pressed
_rc_turn() {
  if (( ${_BVK_TAB_STEPS:-0} != 0 )); then
    if [ "${_sw_in_mode:-0}" = 1 ] && [ "${_BVK_TAB_SCREEN:-}" = "${_vp_header_fn:-}" ]; then
      if (( _BVK_TAB_STEPS > 0 )); then choice="__sw_tab_right__"; _BVK_TAB_STEPS=$(( _BVK_TAB_STEPS - 1 ))
      else choice="__sw_tab_left__"; _BVK_TAB_STEPS=$(( _BVK_TAB_STEPS + 1 )); fi
      _buf=""; _pos=0; _hl_index=0
      return 1
    fi
    _BVK_TAB_STEPS=0                                      # not this screen any more: forget it
  fi
  return 0
}
_rc_tick() {
  # a screen can ask for a callback on every idle tick (e.g. Links → live "time left" column)
  [ -n "${_vp_tick_fn:-}" ] && "$_vp_tick_fn"
  if declare -F _dir_size_job_poll >/dev/null 2>&1; then
    if _dir_size_job_poll; then _vp_cache_reset; _vp_prime_rows; _vp_redraw_in_place; _vp_poll_active; fi
  fi
  if _vp_check_resize; then _vp_cache_reset; _vp_prime_rows; _vp_redraw_in_place; _vp_poll_active; fi
  return 0
}
_rc_nav() {         # rc 1 = leave the prompt (a tab switch)
  local old
  case "$1" in
    up)
      if $_can_nav; then
        old="$_hl_index"
        if [ "$_hl_index" -lt 1 ]; then _hl_index="$_vp_n"
        else
          _hl_index=$(( _hl_index - 1 ))
          [ "$_hl_index" -lt 1 ] && _hl_index="$_vp_n"
        fi
        _buf="$_hl_index"; _pos=${#_buf}
        _vp_goto "$old" "$_hl_index"
      fi ;;
    down)
      if $_can_nav; then
        old="$_hl_index"
        if [ "$_hl_index" -lt 1 ]; then _hl_index=1
        else
          _hl_index=$(( _hl_index + 1 ))
          [ "$_hl_index" -gt "$_vp_n" ] && _hl_index=1
        fi
        _buf="$_hl_index"; _pos=${#_buf}
        _vp_goto "$old" "$_hl_index"
      fi ;;
    pgup)   _nav_jump_to $(( _hl_index - _vp_page_step )) ;;
    pgdn)   _nav_jump_to $(( _hl_index + _vp_page_step )) ;;
    home)   _nav_jump_to 1 ;;
    end)    _nav_jump_to "$_vp_n" ;;
    right) [ -z "$_buf" ] && [ "${_sw_in_mode:-0}" = "1" ] && { choice="__sw_tab_right__"; return 1; } ;;
    left)  [ -z "$_buf" ] && [ "${_sw_in_mode:-0}" = "1" ] && { choice="__sw_tab_left__"; return 1; } ;;
  esac
  return 0
}
_rc_byte() {        # Ctrl-A / Ctrl-E on an empty line (with text they select all / move: bashbasicsbyvk_textedit.sh)
  case "$1" in
    $'\x01') _nav_jump_to 1; return 0 ;;
    $'\x05') _nav_jump_to "$_vp_n"; return 0 ;;
  esac
  return 2
}

_read_choice_raw() {
  choice=""
  # SCRIPTED INPUT (tests, pipes): stdin is not a terminal → ONE line per prompt, no key reader.  A closed stdin answers q, so no loop can spin on it.
  if [ ! -t 0 ]; then IFS= builtin read -r choice || choice=q; choice="${choice%$'\r'}"; return 0; fi
  _can_nav=false
  _vp_count
  if [ "$_vp_n" -gt 0 ]; then
    _can_nav=true
    [ "${_hl_index:-0}" -gt "$_vp_n" ] && _hl_index="$_vp_n"
  else
    _hl_index=0
  fi

  _buf=""
  _pos=0
  local _rc_wasf=0
  local $_BVK_ED_HOOKS
  local _ED_BUF=_buf _ED_POS=_pos _ED_MODE=list _ED_REDRAW=_print_input_line _ED_EDITED=_rc_edited _ED_PASTE=_rc_paste_text
  local _ED_START=_rc_start _ED_TURN=_rc_turn _ED_TICK=_rc_tick _ED_WINCH=1 _ED_PRE=_rc_pre _ED_CLICK=_rc_click _ED_WHEEL=_rc_wheel
  local _ED_NAV=_rc_nav _ED_NAVPARK=1 _ED_BYTE=_rc_byte _ED_TYPE=_rc_type_key _ED_STTY="$_orig_stty"
  _bvk_edit_run
  _bvk_blk_leave
  # prompt is being left: wipe the hint row (the cursor-hide from a loader, if any, is undone too)
  if [ "${_vp_hint_row:-0}" = 1 ] && [ -n "$_hint_cur" ]; then
    _hint_cur=""; _bvk_hint_leave
  fi
  echo

  if [ -n "$_buf" ]; then choice="$_buf"
  elif $_can_nav && [ "$_hl_index" -ge 1 ]; then choice="$_hl_index"
  fi
  # loadtime: Enter was pressed — a screen change starts here (numbers get the item's name as a label)
  if [ "${_LT_ON:-0}" = 1 ] || [ -n "${_SL_ON:-}" ]; then
    local _ltl=""
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "${#items[@]}" -ge "$choice" ] && [ "$choice" -ge 1 ] && _ltl="${items[$((choice-1))]##*/}"
    _lt_enter "$choice" "$_ltl"
  fi
}

_BVK_LASTDIR_FILE="${HOME}/.bashbasicsbyvk/lastdir"
path="$(pwd -P)"
export BVK_FILEMANAGER_BOUNDARY="$path"
selected_items=()
group_prefix=""
force_show=false
_has_group_view=false
_gv_chain=""
declare -ga imaginary_map=()
declare -ga imaginary_lines=()
_imag_banner=""
declare -ga group_chars=()
declare -gA group_counts=()
nav_result_path=""
nav_selected_items=()
gcloud_nav_result_path=""
gcloud_nav_selected_items=()
_sw_did_switch=false