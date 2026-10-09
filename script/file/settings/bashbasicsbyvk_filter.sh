#!/usr/bin/env bash
# bashbasicsbyvk_filter.sh — live name-prefix filter
#
# Prefix key: = (type = then letters to filter)
#
# Three code paths:
#   • Flat filter        — filters items[] using _all_items[] snapshot
#   • Imaginary → flat   — filter shrinks result ≤ threshold: drop to flat
#                          showing the actual matching files
#   • Imaginary → groups — filter keeps result > threshold: rebuild groups

# ── Filter state ──────────────────────────────────────────────────────────────
#   _all_items   what the loop was showing before "=" (restored on clear)
#   _filter_src  what the filter searches (== _all_items, except in
#                "include hidden" mode where hidden files are added)
#   _filter_map  for each filtered row, its 0-based position in _filter_src.
#                Loops that keep arrays parallel to items[] (fx ADF tab) use
#                it so row N of the FILTERED list resolves to the right entry.
declare -g  _filter_query=""
declare -ga _all_items=()
declare -ga _filter_src=()
declare -ga _filter_map=()
declare -g  _filter_map_active=false
declare -gA _REC_LABEL=()          # full path → "sub/dir/name" shown for recursive hits
declare -g  _filter_rec_active=false   # the rows on screen are recursive search results

# filter_recursive: false | true   (Settings → Search filter → Search depth)
#   false  the filter only looks at what the current folder lists (default)
#   true   the filter looks through every sub-folder below the folder you have
#          navigated to ($path — NOT the shell's startup/cd directory). Rows then
#          show the path relative to that folder (see _REC_LABEL).

# filter_hidden_mode: respect | include | exclude   (Settings → Search filter)
#   respect  filter whatever the folder view currently shows
#   include  filter also matches hidden files, even if they are not shown
#   exclude  filter never shows hidden files, even if they are shown

# true/false: should the imaginary (grouped) scan look at hidden files?
_filter_effective_hidden() {
  case "${filter_hidden_mode:-respect}" in
    include) echo true ;;
    exclude) echo false ;;
    *)       echo "${show_hidden_files:-false}" ;;
  esac
}

# Reset every piece of filter state (called whenever a loop rebuilds its list).
_filter_reset_state() {
  _filter_query=""
  _all_items=()
  _filter_src=()
  _filter_map=()
  _filter_map_active=false
  _REC_LABEL=(); _filter_rec_active=false
  _imag_filter_active=false
  _imag_filter_query=""
  _imag_filter_committed=false
}

# display row N (1-based) → 0-based index into the unfiltered list
_filter_orig_slot() {
  if $_filter_map_active; then
    echo "${_filter_map[$(( $1 - 1 ))]:-0}"
  else
    echo $(( $1 - 1 ))
  fi
}

# Only the plain folder view of the main loop can be re-scanned from disk.
# Virtual lists (fx ADF, favourites, recents, bookmarks) keep what they show.
_filter_can_rescan_hidden() {
  [ "${_sw_in_mode:-0}" = "1" ] && return 1
  [ "${_fx_in_mode:-0}" = "1" ] && return 1
  ${_fav_on:-false} && return 1
  ${imaginary_mode:-false} && return 1
  [ -d "$path" ] || return 1
  return 0
}


# Recursive mode is on AND this screen is a real folder view we can walk.
_filter_is_recursive() {
  [ "${filter_recursive:-false}" = "true" ] || return 1
  _filter_can_rescan_hidden
}

# Walk every sub-folder below $path (the navigation path) and print the full
# paths whose NAME matches $1 (same partial/exact rule as the flat filter),
# sorted like the folder view. Folder symlinks are not followed (no loops);
# hidden folders are not entered unless hidden files are in play.
_filter_rec_scan() {
  local q="$1" hid
  hid="$(_filter_effective_hidden)"
  python3 - "$path" "$q" "${filter_mode:-partial}" "$hid" "${sort_mode:-az}" <<'PYEOF'
import os, sys
root, q, mode, hid, sm = sys.argv[1:6]
q = q.lower(); show_hidden = hid == "true"
hits = []
def match(n):
    n = n.lower()
    return n.startswith(q) if mode == "exact" else q in n
for dp, dns, fns in os.walk(root, followlinks=False):
    if not show_hidden:
        dns[:] = [d for d in dns if not d.startswith(".")]
        fns = [f for f in fns if not f.startswith(".")]
    for n in dns + fns:
        if match(n):
            hits.append(os.path.join(dp, n))
def key_stat(p, f):
    try:
        st = os.stat(p)
        return f(st, p)
    except OSError:
        return 0
rel = lambda p: os.path.relpath(p, root).lower()
if   sm == "za":    hits.sort(key=rel, reverse=True)
elif sm == "new":   hits.sort(key=lambda p: key_stat(p, lambda s, _: s.st_mtime), reverse=True)
elif sm == "old":   hits.sort(key=lambda p: key_stat(p, lambda s, _: s.st_mtime))
elif sm == "big":   hits.sort(key=lambda p: key_stat(p, lambda s, q: 0 if os.path.isdir(q) else s.st_size), reverse=True)
elif sm == "small": hits.sort(key=lambda p: key_stat(p, lambda s, q: 0 if os.path.isdir(q) else s.st_size))
else:               hits.sort(key=rel)
out = sys.stdout
for p in hits:
    out.write(p + "\n")
PYEOF
}

# Fill items[] (+ _REC_LABEL) with the recursive hits for query $1.
_filter_rec_fill() {
  local f _tmp
  _tmp="$(_bvk_tmp)"
  _filter_rec_scan "$1" >"$_tmp" 2>/dev/null
  mapfile -t items <"$_tmp"
  rm -f "$_tmp"
  _REC_LABEL=()
  local base="${path%/}"
  for f in "${items[@]}"; do _REC_LABEL["$f"]="${f#"$base"/}"; done
  _filter_rec_active=true
  _items_presorted=true; _items_presorted_mode="${sort_mode:-az}"
  _meta_loaded=false; _win_lo=0; _win_hi=0
}

_filter_snapshot() {
  _all_items=("${items[@]}")
  _filter_src=("${items[@]}")
  [ "${filter_hidden_mode:-respect}" = "include" ] || return 0
  [ "${show_hidden_files:-false}" = "true" ] && return 0
  _filter_can_rescan_hidden || return 0
  # Re-list the folder WITH hidden files (same sort, same group prefix) and use
  # that as the search source. items[] is restored afterwards, so clearing the
  # filter brings back exactly the view you had.
  local -a _keep=("${items[@]}")
  local _keep_hidden="$show_hidden_files"
  show_hidden_files=true
  build_items_with_meta "$path" "${group_prefix:-}"
  apply_sort
  _filter_src=("${items[@]}")
  show_hidden_files="$_keep_hidden"
  items=("${_keep[@]}")
  _meta_loaded=false; _win_lo=0; _win_hi=0
}

_filter_apply() {
  local q="${_filter_query,,}"
  local hm="${filter_hidden_mode:-respect}"
  # Recursive: search every sub-folder below the navigation path. With nothing
  # typed yet there is nothing to search for, so the normal list stays.
  if [ -n "$q" ] && _filter_is_recursive; then
    _filter_rec_fill "$q"
    _filter_map=(); _filter_map_active=false
    return 0
  fi
  _REC_LABEL=(); _filter_rec_active=false
  items=()
  _filter_map=()
  _filter_map_active=true
  local f bn bl i=0
  for f in "${_filter_src[@]}"; do
    bn="${f##*/}"
    if [ "$hm" = "exclude" ] && [[ "$bn" == .* ]]; then i=$(( i + 1 )); continue; fi
    bl="${bn,,}"
    if [ "${filter_mode:-partial}" = "exact" ]; then
      [[ "$bl" == "$q"* ]] && { items+=("$f"); _filter_map+=("$i"); }
    else
      [[ "$bl" == *"$q"* ]] && { items+=("$f"); _filter_map+=("$i"); }
    fi
    i=$(( i + 1 ))
  done
  _meta_loaded=false; _win_lo=0; _win_hi=0
}

_filter_clear() {
  items=("${_all_items[@]}")
  _REC_LABEL=(); _filter_rec_active=false
  _filter_query=""
  _all_items=()
  _filter_src=()
  _filter_map=()
  _filter_map_active=false
  _meta_loaded=false; _win_lo=0; _win_hi=0
}

# "(shown/total)" denominator for the header
_filter_total_count() {
  # recursive hits have no "total" (it would be the whole tree): header says "N matches"
  if ${_filter_rec_active:-false}; then echo 0; return; fi
  if [ "${#_filter_src[@]}" -gt 0 ]; then echo "${#_filter_src[@]}"
  else echo "${#_all_items[@]}"; fi
}

# ── Imaginary-origin filter state ─────────────────────────────────────────────

declare -g _imag_filter_active=false
declare -g _imag_filter_query=""
declare -g _imag_filter_committed=false   # an imaginary-origin filter result is on screen

# Single Python scan returns groups AND matching file paths together.
# Emits "G\t<char>\t<count>" lines, then "F\t<path>" lines.
# Group-menu "=" filter scan: "G<TAB>ch<TAB>n" lines then "F<TAB>path" lines.
# C `gfilter` first; Python when the binary is missing/fails or Unicode rules
# are needed (it prints nothing in that case, so there is no duplicate output).
_imag_filter_scan() {
  local q="$1" hid _h=0
  hid="$(_filter_effective_hidden)"; [ "$hid" = "true" ] && _h=1
  _BVK_META_SRC=""
  if declare -F _bvk_go_bin >/dev/null 2>&1 && _bvk_go_bin \
     && "$_BVK_GO_BIN" gfilter "$path" "$_h" "$group_prefix" "$q" "${filter_mode:-partial}" 2>/dev/null; then
    _BVK_LOAD_SRC=c
    return 0
  fi
  _BVK_LOAD_SRC=py
  _bvk_py_group "$path" "$group_prefix" "$q" "${filter_mode:-partial}" "$hid" <<'PYEOF'
import os, sys
path   = sys.argv[1]
pfx    = sys.argv[2].lower()
query  = sys.argv[3].lower()
mode   = sys.argv[4]
show_hidden = sys.argv[5] == "true"
pfx_len = len(pfx)

counts = {}
order  = []
paths  = []

try:
    with os.scandir(path) as it:
        for e in it:
            bn = e.name
            if bn in (".", ".."): continue
            if not show_hidden and bn.startswith("."): continue
            bl = bn.lower()
            if pfx and not bl.startswith(pfx): continue
            if len(bl) <= pfx_len: continue
            tail = bl[pfx_len:]
            if query:
                if mode == "exact":
                    if not tail.startswith(query): continue
                else:
                    if query not in tail: continue
            ch = group_key(tail[0] if tail else "")
            if ch not in counts:
                counts[ch] = 0
                order.append(ch)
            counts[ch] += 1
            paths.append(e.path)
except Exception as ex:
    sys.stderr.write(f"scandir: {ex}\n")

for ch in order:
    print(f"G\t{ch}\t{counts[ch]}")
for p in paths:
    print(f"F\t{p}")
PYEOF
}

_imag_filter_apply() {
  local q="${_imag_filter_query,,}"
  local threshold="${index_mode_threshold:-200}"

  # ── Recursive: matches from all sub-folders, always listed flat ────────
  # (a group menu cannot drill into hits that live in different folders)
  if [ -n "$q" ] && [ "${filter_recursive:-false}" = "true" ] && [ -d "$path" ]; then
    _filter_query="$_imag_filter_query"
    _imag_filter_committed=true
    imaginary_mode=false
    _all_items=()
    _imag_banner=""
    _filter_rec_fill "$q"
    _vp_mode="items"
    _vp_header_fn=_menu_header_flat
    _vp_footer_fn=_menu_footer_lines
    _hl_index=0
    _vp_cache_reset
    _vp_prime_rows
    _vp_redraw_in_place
    _print_input_line
    return 0
  fi
  _REC_LABEL=(); _filter_rec_active=false

  declare -gA group_counts=()
  group_chars=()
  local -a _paths=()
  local line tag a b

  local _gf; _gf="$(_bvk_tmp)"
  _imag_filter_scan "$q" >"$_gf"
  while IFS=$'\t' read -r tag a b; do
    case "$tag" in
      G) group_counts["$a"]="$b"; group_chars+=("$a") ;;
      F) _paths+=("$a") ;;
    esac
  done <"$_gf"
  rm -f "$_gf"

  local tot="${#_paths[@]}"
  _filter_query="$_imag_filter_query"
  _imag_filter_committed=true

  # ── Below threshold: drop out of imaginary, show the real files ────────
  if [ "$tot" -le "$threshold" ]; then
    imaginary_mode=false
    items=("${_paths[@]}")
    _all_items=()
    _win_lo=0; _win_hi=0
    _meta_loaded=false
    _imag_banner=""
    _vp_mode="items"
    _vp_header_fn=_menu_header_flat
    _vp_footer_fn=_menu_footer_lines

  # ── Still above threshold: stay imaginary, groups reflect the filter ───
  else
    imaginary_mode=true
    _all_items=()
    items=()
    _rebuild_imaginary_display "$tot"
    _vp_mode="imaginary"
    _vp_header_fn=_menu_header_imaginary
    _vp_footer_fn=_menu_footer_lines
  fi

  _hl_index=0
  _vp_cache_reset
  _vp_prime_rows
  _vp_redraw_in_place
  _print_input_line
}

# Called when the leading "=" is backspaced away. Re-checks the base state;
# may return to imaginary, or drop to flat if the base is already small.
_imag_filter_restore() {
  _REC_LABEL=(); _filter_rec_active=false
  _filter_query=""
  _imag_filter_committed=false
  _imag_banner=""
  local threshold="${index_mode_threshold:-200}"
  local total
  total=$(count_items_in_path "$path")
  total="${total:-0}"

  if [ "$total" -gt "$threshold" ] && ! $force_show; then
    imaginary_mode=true
    items=()
    _all_items=()
    get_imaginary_groups "$path" "$group_prefix"
    local tot=0
    for ch in "${group_chars[@]}"; do
      tot=$(( tot + ${group_counts[$ch]:-0} ))
    done
    _rebuild_imaginary_display "$tot"
    _vp_mode="imaginary"
    _vp_header_fn=_menu_header_imaginary
  else
    imaginary_mode=false
    if [ -n "$group_prefix" ]; then
      _bvk_load_prefix_items "$path" "$group_prefix"
      _all_items=("${items[@]}")
    else
      build_items_with_meta "$path" ""
      apply_sort
    fi
    _vp_mode="items"
    _vp_header_fn=_menu_header_flat
  fi
  _vp_footer_fn=_menu_footer_lines

  _hl_index=0
  _vp_cache_reset
  _vp_prime_rows
  _vp_redraw_in_place
  _print_input_line
}

# ── Input handlers ────────────────────────────────────────────────────────────

_filter_on_backspace() {
  # ── Imaginary-origin filter ─────────────────────────────────────────────
  if ${_imag_filter_active:-false}; then
    if [[ "$_buf" != =* ]]; then
      _imag_filter_active=false
      _imag_filter_query=""
      return 1
    fi
    if [ "$_buf" = "=" ]; then
      _imag_filter_active=false
      _imag_filter_query=""
      _buf=""; _pos=0
      _imag_filter_restore
      return 0
    fi
    if [ "$_pos" -gt 0 ]; then
      _buf="${_buf:0:_pos-1}${_buf:_pos}"
      _pos=$(( _pos - 1 ))
      _imag_filter_query="${_buf:1}"
      _imag_filter_apply
      return 0
    fi
    return 1
  fi

  # ── Flat filter ─────────────────────────────────────────────────────────
  if [[ "$_buf" == =?* ]]; then
    _buf="${_buf:0:_pos-1}${_buf:_pos}"
    _pos=$(( _pos - 1 ))
    _filter_query="${_buf:1}"
    _filter_apply
    _hl_index=0
    _vp_count
    _vp_cache_reset
    _vp_prime_rows
    _vp_redraw_in_place
    return 0
  elif [[ "$_buf" == = ]]; then
    _filter_clear
    _buf=""; _pos=0; _hl_index=0
    _vp_count
    _vp_cache_reset
    _vp_prime_rows
    _vp_redraw_in_place
    return 0
  fi
  return 1
}

_filter_on_char() {
  local key="$1"

  # ── Imaginary-origin filter already active ──────────────────────────────
  if ${_imag_filter_active:-false}; then
    if [[ "$_buf" == =* ]]; then
      _buf="${_buf:0:_pos}${key}${_buf:_pos}"
      _pos=$(( _pos + 1 ))
      _imag_filter_query="${_buf:1}"
      _imag_filter_apply
      return 0
    fi
    _imag_filter_active=false
    _imag_filter_query=""
    _filter_query=""
  fi

  # ── Enter imaginary-origin filter (type = at empty buffer) ──────────────
  if ${imaginary_mode:-false} || ${_imag_filter_committed:-false}; then
    if [ -z "$_buf" ] && [ "$key" = "=" ]; then
      _imag_filter_active=true
      _imag_filter_query=""
      _buf="="; _pos=1
      _print_input_line
      return 0
    fi
    return 1
  fi

  # ── Flat filter ─────────────────────────────────────────────────────────
  if [[ "$_buf" == =* ]] || { [ -z "$_buf" ] && [ "$key" = "=" ]; }; then
    if [ -z "$_buf" ] && [ "$key" = "=" ]; then
      # A committed filter (Enter on =text) already holds the original list in
      # _filter_src — re-filter from that instead of from the filtered rows.
      [ "${#_filter_src[@]}" -eq 0 ] && _filter_snapshot
    fi
    _buf="${_buf:0:_pos}${key}${_buf:_pos}"
    _pos=$(( _pos + 1 ))
    _filter_query="${_buf:1}"
    _filter_apply
    _hl_index=0
    _vp_count
    _vp_cache_reset
    _vp_prime_rows
    _vp_redraw_in_place
    _print_input_line
    return 0
  fi
  return 1
}

# ── Enter on "=text": keep the filter, redraw, ask again ────────────────────
# The loops used to treat "=text"+Enter as an unknown command and rebuild the
# full list, so the next number picked from the UNFILTERED list. Now the
# filtered rows stay put and the next number resolves against what you see.
#   =text + Enter   keep the filter (redraw clean, prompt again)
#   =      + Enter   clear the filter
_filter_commit() {
  _imag_filter_active=false          # leave the typed query; result stays
  if [ "$choice" = "=" ]; then
    if ${_imag_filter_committed:-false}; then
      _imag_filter_query=""
      _imag_filter_restore           # redraws by itself
      return 0
    fi
    if [ "${#_filter_src[@]}" -gt 0 ] || [ -n "$_filter_query" ]; then _filter_clear; fi
  fi
  _hl_index=0
  _vp_render_from_top
}

# Drop-in replacement for _read_choice in every loop.
_read_choice_filtered() {
  while true; do
    _read_choice
    case "$choice" in
      =*) _filter_commit ;;
      *)  return 0 ;;
    esac
  done
}

_st_fm_build() {
  _st_reset
  _st_add h "Match"
  _st_eq "$filter_mode" partial; _st_add r "Partial" "$_o" "=config → longword_xdconfig" m:partial
  _st_eq "$filter_mode" exact;   _st_add r "Exact"   "$_o" "=config → config_file"       m:exact
  _st_add h "Hidden files"
  _st_eq "$filter_hidden_mode" respect; _st_add r "Follow the hidden-files setting" "$_o" "" h:respect
  _st_eq "$filter_hidden_mode" include; _st_add r "Always include"                  "$_o" "" h:include
  _st_eq "$filter_hidden_mode" exclude; _st_add r "Always exclude"                  "$_o" "" h:exclude
  _st_add h "Recursive"
  _st_eq "$filter_recursive" false; _st_add r "Off  (this folder only)"                "$_o" "" r:false
  _st_eq "$filter_recursive" true;  _st_add r "On   (all sub-folders from this path)"  "$_o" "" r:true
}
_st_fm_act() {
  case "${_st_tag[$1]}" in
    m:*) filter_mode="${_st_tag[$1]#m:}" ;;
    h:*) filter_hidden_mode="${_st_tag[$1]#h:}" ;;
    r:*) filter_recursive="${_st_tag[$1]#r:}" ;;
  esac
  save_settings
}
filter_mode_settings() { _st_run "Search filter  (=)" _st_fm_build _st_fm_act; }
