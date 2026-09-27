#!/usr/bin/env bash
# bashbasicsbyvk_filter.sh — live name-prefix filter
#
# Prefix key: = (type = then letters to filter)
#
# Two code paths:
#   • Flat mode    — filters items[] using _all_items[] snapshot
#   • Imaginary    — re-scans the directory in Python with the query applied
#                    (items[] is empty in imaginary mode; display comes
#                    from imaginary_map[] / imaginary_lines[])

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

# ── Imaginary-mode filter state ───────────────────────────────────────────────

declare -g _imag_filter_active=false
declare -g _imag_filter_query=""

_imag_filter_apply() {
  local q="${_imag_filter_query,,}"
  get_imaginary_groups_filtered "$path" "$group_prefix" "$q"
  local tot=0
  for ch in "${group_chars[@]}"; do
    tot=$(( tot + ${group_counts[$ch]:-0} ))
  done
  _rebuild_imaginary_display "$tot"
  _hl_index=0
  _vp_cache_reset
  _vp_prime_rows
  _vp_redraw_in_place
}

_imag_filter_restore() {
  get_imaginary_groups "$path" "$group_prefix"
  local tot=0
  for ch in "${group_chars[@]}"; do
    tot=$(( tot + ${group_counts[$ch]:-0} ))
  done
  _rebuild_imaginary_display "$tot"
  _hl_index=0
  _vp_cache_reset
  _vp_prime_rows
  _vp_redraw_in_place
}

# ── Input handlers ────────────────────────────────────────────────────────────

_filter_on_backspace() {
  # ── Imaginary branch ────────────────────────────────────────────────────
  if ${imaginary_mode:-false} && ${_imag_filter_active:-false}; then
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

  # ── Flat branch ─────────────────────────────────────────────────────────
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

  # ── Imaginary branch ────────────────────────────────────────────────────
  if ${imaginary_mode:-false}; then
    if ! ${_imag_filter_active:-false}; then
      if [ -z "$_buf" ] && [ "$key" = "=" ]; then
        _imag_filter_active=true
        _imag_filter_query=""
        _buf="="; _pos=1
        _print_input_line
        return 0
      fi
      return 1
    fi
    if [[ "$_buf" == =* ]]; then
      _buf="${_buf:0:_pos}${key}${_buf:_pos}"
      _pos=$(( _pos + 1 ))
      _imag_filter_query="${_buf:1}"
      _imag_filter_apply
      return 0
    fi
    return 1
  fi

  # ── Flat branch ─────────────────────────────────────────────────────────
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