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
    read -e -r -p "Path to go to: " dest || return 0
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

fast_count() {
  local pattern="$1"
  local arr=("$pattern")
  echo "${#arr[@]}"
}

# ═══════════════════════════════════════════════════════════════════════════
# count_items_in_path — single os.scandir, ~80ms for 200k.
# ═══════════════════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════════════════
# _bvk_prefix_scan — files matching group_prefix.
# ═══════════════════════════════════════════════════════════════════════════
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
  local _f; _f="$(_bvk_tmp)" || return 1
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && "$_BVK_GO_BIN" scan "$1" raw "$_h" "$2" >"$_f" 2>/dev/null; then
    _BVK_LOAD_SRC=c
  else
    _BVK_LOAD_SRC=py
    _bvk_prefix_scan_py "$1" "$2" >"$_f" 2>/dev/null
  fi
  _BVK_META_SRC=""
  mapfile -t items <"$_f"
  rm -f "$_f"
}

# items[] = the "#" group of prefix $2 (names whose next char is not a letter,
# digit or a known special). C `hashscan`; Python when Unicode rules are needed.
_bvk_load_hash_items() {
  local _h=0; [ "${show_hidden_files:-false}" = "true" ] && _h=1
  local _f; _f="$(_bvk_tmp)" || return 1
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && "$_BVK_GO_BIN" hashscan "$1" "$_h" "$2" >"$_f" 2>/dev/null; then
    _BVK_LOAD_SRC=c
  else
    _BVK_LOAD_SRC=py
    _bvk_fallback_scan "$1" "$2" >"$_f" 2>/dev/null
  fi
  _BVK_META_SRC=""
  mapfile -t items <"$_f"
  rm -f "$_f"
}

# ═══════════════════════════════════════════════════════════════════════════
# Group-key rule — the ONE definition of "which group does this file fall in".
#   next char after the prefix: letter → UPPER, digit → itself, one of SPECIALS →
#   itself, anything else → "#".   Used by get_imaginary_groups, _bvk_fallback_scan
#   and the filter's imaginary scan (settings/bashbasicsbyvk_filter.sh).
#   _bvk_py_group <args…> <<'PYEOF' … PYEOF   runs python with SPECIALS and
#   group_key(nxt) already defined; sys.argv works exactly like `python3 - args`.
# ═══════════════════════════════════════════════════════════════════════════
_BVK_GKEY_PY='SPECIALS = set("_.-()[]{}@!~+=^&%$,;'"'"' ")
def group_key(nxt):
    if nxt.isalpha(): return nxt.upper()
    if nxt.isdigit(): return nxt
    if nxt in SPECIALS: return nxt
    return "#"'
_bvk_py_group() { python3 -c "${_BVK_GKEY_PY}
$(cat)" "$@"; }

# ═══════════════════════════════════════════════════════════════════════════
# _bvk_fallback_scan — the "#" branch in handle_selection.
# ═══════════════════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════════════════
# get_imaginary_groups — unfiltered.
# ═══════════════════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════════════════
# _rebuild_imaginary_display — sort + format block.
# ═══════════════════════════════════════════════════════════════════════════
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

# ═══════════════════════════════════════════════════════════════════════════
# Index mode (big folders) — the ONE place that decides "list it" or "show prefix groups".
# Shared by the fx / switch loops (_bvk_build_path_items) and the transfer navigator.
# ═══════════════════════════════════════════════════════════════════════════

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

# select_items_common <PROMPT> [allow_a]
#   allow_a: also accept  a  (all)  and  a-<exclusions>  (all except),
#            e.g. a-1-5,7 — same grammar as the c-/m-/s- staging shortcuts.
select_items_common() {
  local prompt="$1"
  local _multi_allow_a=false
  [ "${2:-}" == "allow_a" ] && _multi_allow_a=true
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available"
    return 1
  fi
  local _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos itemlist
  _vp_mode="items"
  _multi_prompt_loop
  itemlist="${_buf// /}"
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

select_imaginary_items_common() {
  local p="$1"
  local pfx="$2"
  local prompt="${3:-DELETE}"
  if [ "${#imaginary_map[@]}" -eq 0 ]; then
    echo "❌ No groups available"
    return 1
  fi
  local _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos
  _vp_mode="imaginary"
  _multi_prompt_loop
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

# ── the status row:   c | ⏰ <notifications> | 📣 <unfinished uploads> ─────────────────────────────────────────
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
_menu_header() {
  echo
  _bvk_hdr_status; echo
  echo
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then _gd_view_path "$path"; else _gd_vp="$path"; fi      # Google Drive open: show the Drive path, not the mirror folder
  local _hdr_loc="☁️ nav path: $_gd_vp${group_prefix:+ [group: ${group_prefix^^}*]}"
  if [ -n "$_filter_query" ]; then
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
  echo "📂 cd path: $PWD"
  echo "$_hdr_loc"
}

_menu_header_flat() {
  _menu_header
  [ -s "${_SNAP_NOTICE:-}" ] && cat "$_SNAP_NOTICE"        # Snapshots paused: not enough credits
  declare -F _pn_hint >/dev/null 2>&1 && _pn_hint           # unfinished uploads are waiting: pn
  [ -n "${_sel_banner:-}" ] && echo "$_sel_banner"
  [ -n "${_fav_banner:-}" ] && echo "$_fav_banner"
  [ -n "${_disp_banner:-}" ] && echo "$_disp_banner"
  if $_has_group_view; then
    _gv_banner_line; echo
  fi
}

_menu_header_imaginary() {
  _menu_header
  [ -n "${_sel_banner:-}" ] && echo "$_sel_banner"
  [ -n "${_fav_banner:-}" ] && echo "$_fav_banner"
  echo "$_imag_banner"
}

_menu_body_flat() {
  if $_has_group_view; then
    _gv_banner_line; echo
  fi
  display_items
}

_menu_footer_lines() {
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then _mc_footer @browse_gd; else _mc_footer @browse_main; fi
 if [ "${total:-0}" -gt "${index_mode_threshold:-200}" ] && ! $force_show && [ "${#group_view_levels[@]}" -gt 0 ]; then
    echo "Group view is set but above threshold. Press fs to enable grouped display"
  fi
}

_render_items_with_highlight() {
  local -A hl=()
  local x
  for x in "$@"; do hl["$x"]=1; done
  local i line
  for ((i=1; i<=${#items[@]}; i++)); do
    line=$(_item_line_text "$i")
    if [ -n "${hl[$i]+x}" ]; then
      builtin printf '%s\n' "$(_highlight "$line")"
    else
      builtin printf '%s\n' "$line"
    fi
  done
}

# The row UNDER the prompt (kept free by _vp_geometry) shows a dim hint for what is being typed:
#   =   "type to filter live"  (browser terminals: "type, then press Enter to filter")
#   ==  "Enter = search sub-folders"
# The line being typed on is never touched.  _hint_cur = what is on screen now ("?" = unknown).
_hint_cur=""
_hint_want=""
_input_hint_sync() {
  _hint_want=""
  if [ "${_vp_hint_row:-0}" = 1 ]; then
    # "=" has its own hint (live filter); everything else is the command map's live suggestion
    [ "${_vp_input_fn:-}" = "_print_input_line" ] && declare -F _filter_hint_text >/dev/null 2>&1 && _filter_hint_text
    if [ -z "$_hint_want" ] && declare -F _cm_hint >/dev/null 2>&1; then if [ "${_vp_input_fn:-}" = _multi_print_input_line ]; then _cm_hint "${_buf:-}" text; else _cm_hint "${_buf:-}" menu; fi; fi
  fi
  [ "$_hint_want" = "$_hint_cur" ] && return 0
  _hint_cur="$_hint_want"
  if [ -n "$_hint_want" ]; then
    _bvk_hint_paint "$_hint_want"                      # the painter expands a long suggestion onto the next row (_bvk_hint_wrap)
  else
    _bvk_hint_paint ""
  fi
}

_print_input_line() {
  _BVK_SCR_PROMPT="Select:"
  # a text that does not fit one row (a paste, line breaks) is shown in full as a block of rows (see _bvk_row_multi)
  if declare -F _bvk_row_multi >/dev/null 2>&1 && _bvk_row_multi "Select: " "$_buf" "$_pos"; then return 0; fi
  _input_hint_sync
  builtin printf '\r\033[K'
  local back
  if declare -F _bvk_fit_input >/dev/null 2>&1; then
    _bvk_fit_input "Select: " "$_buf" "$_pos"            # one row only (see _bvk_fit_input in viewport.sh)
    builtin printf '%s%s' "$_BVK_FIT_PROMPT" "$_BVK_FIT"; back="$_BVK_FIT_BACK"
  else
    builtin printf "Select: %s" "$_buf"; back=$(( ${#_buf} - _pos ))
  fi
  [ "$back" -gt 0 ] && builtin printf '\033[%dD' "$back"
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
  if ! _filter_on_char "$key"; then
    _buf="${_buf:0:_pos}${key}${_buf:_pos}"
    _pos=$(( _pos + 1 ))
    _print_input_line
    _sync_highlight_from_buf
  fi
  return 0
}
# a pasted text: ONE insert, ONE redraw (never key by key). "=" starts the live filter, which also gets the text in one piece.
_rc_paste_text() {
  local t="$1"
  [ -z "$t" ] && return 0
  _bvk_room "${#t}" || { _bvk_too_large $(( ${#_buf} + ${#t} )) _print_input_line drain; return 0; }   # over 512 characters: refused, redrawn
  if [ -z "$_buf" ] && [ "${t:0:1}" = "=" ]; then
    if _filter_on_char "="; then t="${t:1}"; fi   # the filter starts (snapshot, hint) ... (if it did not: "=" stays part of the text)
    [ -z "$t" ] && return 0
    _filter_on_char "$t" || { _buf="${_buf:0:_pos}${t}${_buf:_pos}"; _pos=$(( _pos + ${#t} )); }   # ... and takes the rest at once
    _print_input_line
    return 0
  fi
  if [[ "$_buf" == =* ]]; then
    _filter_on_char "$t" || { _buf="${_buf:0:_pos}${t}${_buf:_pos}"; _pos=$(( _pos + ${#t} )); }
    _print_input_line
    return 0
  fi
  _buf="${_buf:0:_pos}${t}${_buf:_pos}"
  _pos=$(( _pos + ${#t} ))
  _print_input_line
  _sync_highlight_from_buf
}
# a whole text at once (what cc types in)
_rc_type_text() {
  _buf="$1"; _pos=${#_buf}
  _print_input_line
  _sync_highlight_from_buf
}

# ── mouse / touch (see bashbasicsbyvk_mouse.sh) ──────────────────────────────────────────────────────────────────────
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
_rc_click() {
  _bvk_blk_park                                              # cursor onto the first prompt row, so its screen row IS the prompt row
  if ! _bvk_mouse_prow; then (( ${_BLK_ROWS:-1} > 1 )) && _print_input_line; return 0; fi
  _bvk_mouse_hit "$_MS_Y" "$_BVK_CROW"
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

_read_choice_raw() {
  choice=""
  _can_nav=false
  _vp_count
  if [ "$_vp_n" -gt 0 ]; then
    _can_nav=true
    [ "${_hl_index:-0}" -gt "$_vp_n" ] && _hl_index="$_vp_n"
  else
    _hl_index=0
  fi

  stty -icanon -echo min 1 time 0 2>/dev/null
  trap '_vp_on_resize' WINCH
  _bvk_paste_on
  declare -F _bvk_mouse_on >/dev/null 2>&1 && _bvk_mouse_on; _BVK_LAST_ITEM=""

  _buf=""
  _pos=0
  local key seq _rc
  _print_input_line
  _lt_ready menu
  # cc: the command picked from the cheat-code list is typed in for you (it does not run until Enter)
  [ -n "${_CC_PREFILL:-}" ] && _cc_replay _rc_type_key _rc_type_text

  while true; do
    # a tab was tapped (bashbasicsbyvk_mouse.sh): feed the ←/→ sentinel once per turn, exactly as if the arrow key had been pressed
    if (( ${_BVK_TAB_STEPS:-0} != 0 )); then
      if [ "${_sw_in_mode:-0}" = 1 ] && [ "${_BVK_TAB_SCREEN:-}" = "${_vp_header_fn:-}" ]; then
        if (( _BVK_TAB_STEPS > 0 )); then choice="__sw_tab_right__"; _BVK_TAB_STEPS=$(( _BVK_TAB_STEPS - 1 ))
        else choice="__sw_tab_left__"; _BVK_TAB_STEPS=$(( _BVK_TAB_STEPS + 1 )); fi
        _buf=""; _pos=0; _hl_index=0
        break
      fi
      _BVK_TAB_STEPS=0                                      # not this screen any more: forget it
    fi
    IFS= read -rsn1 -t "$_vp_poll_cur" key
    _rc=$?
    if [ "$_rc" -gt 128 ]; then
      _vp_poll_tick
      # a screen can ask for a callback on every idle tick (e.g. Links → live "time left" column)
      [ -n "${_vp_tick_fn:-}" ] && "$_vp_tick_fn"
      if declare -F _dir_size_job_poll >/dev/null 2>&1; then
        if _dir_size_job_poll; then
          _vp_cache_reset
          _vp_prime_rows
          _vp_redraw_in_place
          _vp_poll_active
        fi
      fi
      if _vp_check_resize; then
        _vp_cache_reset
        _vp_prime_rows
        _vp_redraw_in_place
        _vp_poll_active
      fi
      continue
    fi
    [ "$_rc" -ne 0 ] && break
    _vp_poll_active
    if [[ "$key" == $'\x1b' ]]; then
      _read_key_seq || continue
      if [ "$_esc" = "[200~" ]; then _bvk_paste_bracketed; _rc_paste_text "$_BVK_PASTE"; continue; fi
      if declare -F _bvk_mouse_decode >/dev/null 2>&1 && _bvk_mouse_decode "$_esc"; then
        case "$_MS_ACT" in
          press)     _rc_click; case $? in 2|3) break ;; esac ;;    # double click / double tap = Enter · a header tap = the command is typed
          wheelup)   _rc_wheel up ;;
          wheeldown) _rc_wheel down ;;
        esac
        continue
      fi
      _key_name "$_esc"
      case "$_kname" in up|down|pgup|pgdn|home|end) _bvk_blk_park ;; esac   # list moves repaint rows relative to the first input row
      case "$_kname" in
        up)
          if $_can_nav; then
            local old="$_hl_index"
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
            local old="$_hl_index"
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
        right)
          if [ -z "$_buf" ] && [ "${_sw_in_mode:-0}" = "1" ]; then
            choice="__sw_tab_right__"; break
          elif [ "$_pos" -lt "${#_buf}" ]; then
            _bvk_cursor_to $(( _pos + 1 )) _print_input_line
          fi ;;
        left)
          if [ -z "$_buf" ] && [ "${_sw_in_mode:-0}" = "1" ]; then
            choice="__sw_tab_left__"; break
          elif [ "$_pos" -gt 0 ]; then
            _bvk_cursor_to $(( _pos - 1 )) _print_input_line
          fi ;;
        *) : ;;
      esac
      case "$_kname" in up|down|pgup|pgdn|home|end) (( ${_BLK_ROWS:-1} > 1 )) && _print_input_line ;; esac
      continue
    fi

    # a paste that came without the bracketed-paste markers: the bytes already waiting are part of it (see viewport.sh)
    if [ -z "$key" ] || [[ "$key" == [[:print:]] ]]; then
      if _bvk_paste_burst "${key:-$'\n'}"; then
        _rc_paste_text "$_BVK_PASTE"
        [ "$_BVK_PASTE_ENTER" = 1 ] && break
        continue
      fi
    fi

    case "$key" in
      ""|$'\r') break ;;
      $'\x7f'|$'\x08')
        if ! _filter_on_backspace; then
          if [ "$_pos" -gt 0 ]; then
            _buf="${_buf:0:_pos-1}${_buf:_pos}"
            _pos=$(( _pos - 1 ))
            _print_input_line
            _sync_highlight_from_buf
          fi
        fi ;;
      $'\x01') _nav_jump_to 1 ;;
      $'\x05') _nav_jump_to "$_vp_n" ;;
      *)
        _rc_type_key "$key" ;;
    esac
  done

  trap - WINCH
  _bvk_paste_off
  declare -F _bvk_mouse_off >/dev/null 2>&1 && _bvk_mouse_off
  stty "$_orig_stty" 2>/dev/null
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
_BVK_RECENTS_PID_FILE="${HOME}/.bashbasicsbyvk/recents.pid"
_BVK_DAEMON_VERSION=2      # must match DAEMON_VERSION in bashbasicsbyvk_recents_daemon

_bvk_wake_recents_daemon() {
  local _candidates=(
    "$SCRIPT_DIR/file/bashbasicsbyvk_recents_daemon.py"
    "$SCRIPT_DIR/file/bashbasicsbyvk_recents_daemon"
    "$SCRIPT_DIR/bashbasicsbyvk_recents_daemon.py"
    "$SCRIPT_DIR/bashbasicsbyvk_recents_daemon"
  )
  local _daemon_script=""
  local _c
  for _c in "${_candidates[@]}"; do
    if [ -f "$_c" ]; then _daemon_script="$_c"; break; fi
  done
  [ -n "$_daemon_script" ] || return
  local _pid
  _pid=$(cat "$_BVK_RECENTS_PID_FILE" 2>/dev/null)
  # alive AND current version → nothing to do.  Alive but older (pre-upgrade) →
  # fall through: the daemon script itself replaces the old process.
  local _ver; _ver=$(cat "${HOME}/.bashbasicsbyvk/daemon.version" 2>/dev/null)
  kill -0 "$_pid" 2>/dev/null && [ "$_ver" = "$_BVK_DAEMON_VERSION" ] && return
  if [ -x "$_daemon_script" ]; then
    "$_daemon_script" </dev/null >/dev/null 2>&1 &
  elif command -v python3 >/dev/null 2>&1; then
    python3 "$_daemon_script" </dev/null >/dev/null 2>&1 &
  else
    python "$_daemon_script" </dev/null >/dev/null 2>&1 &
  fi
  disown
}

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