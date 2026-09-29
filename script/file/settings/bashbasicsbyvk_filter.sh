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

# ── Core filter primitives (flat mode) ────────────────────────────────────────

_filter_snapshot() {
  _all_items=("${items[@]}")
}

_filter_apply() {
  local q="${_filter_query,,}"
  items=()
  local f bn
  for f in "${_all_items[@]}"; do
    bn="${f##*/}"
    local bn_lower="${bn,,}"
    if [ "${filter_mode:-partial}" = "exact" ]; then
      [[ "$bn_lower" == "$q"* ]] && items+=("$f")
    else
      [[ "$bn_lower" == *"$q"* ]] && items+=("$f")
    fi
  done
}

_filter_clear() {
  items=("${_all_items[@]}")
  _filter_query=""
  _all_items=()
}

# ── Imaginary-origin filter state ─────────────────────────────────────────────

declare -g _imag_filter_active=false
declare -g _imag_filter_query=""

# Single Python scan returns groups AND matching file paths together.
# Emits "G\t<char>\t<count>" lines, then "F\t<path>" lines.
_imag_filter_apply() {
  local q="${_imag_filter_query,,}"
  local threshold="${index_mode_threshold:-200}"

  declare -gA group_counts=()
  group_chars=()
  local -a _paths=()
  local line tag a b

  while IFS=$'\t' read -r tag a b; do
    case "$tag" in
      G) group_counts["$a"]="$b"; group_chars+=("$a") ;;
      F) _paths+=("$a") ;;
    esac
  done < <(python3 - "$path" "$group_prefix" "$q" \
                    "${filter_mode:-partial}" "${show_hidden_files:-false}" <<'PYEOF'
import os, sys
path   = sys.argv[1]
pfx    = sys.argv[2].lower()
query  = sys.argv[3].lower()
mode   = sys.argv[4]
show_hidden = sys.argv[5] == "true"
pfx_len = len(pfx)
SPECIALS = set("_.-()[]{}@!~+=^&%$,;' ")

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
            nxt = tail[0] if tail else ""
            if   nxt.isalpha(): ch = nxt.upper()
            elif nxt.isdigit(): ch = nxt
            elif nxt in SPECIALS: ch = nxt
            else: ch = "#"
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
  )

  local tot="${#_paths[@]}"
  _filter_query="$_imag_filter_query"

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
  _filter_query=""
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
      mapfile -t items < <(_bvk_prefix_scan "$path" "$group_prefix")
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
  if ${imaginary_mode:-false}; then
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
      _filter_snapshot
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

filter_mode_settings() {
  echo ""
  echo "Filter mode (used by = filter):"
  echo "1) partial — match anywhere in name  (=config → longword_xdconfig ✔)"
  echo "2) exact   — prefix match only       (=config → config_file ✔)"
  read -r -p "Choice [1-2]: " fm_choice
  fm_choice="${fm_choice%$'\r'}"
  case "$fm_choice" in
    1) filter_mode="partial" ;;
    2) filter_mode="exact"   ;;
    *) echo "Invalid choice — no changes made." ; return ;;
  esac
  save_settings
  echo "✅ Filter mode set to: $filter_mode"
}