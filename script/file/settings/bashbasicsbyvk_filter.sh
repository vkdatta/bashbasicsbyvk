#!/usr/bin/env bash
# bashbasicsbyvk_filter.sh — live name-prefix filter
#
# Prefix key: = (type = then letters to filter)
# Move _filter_snapshot / _filter_apply / _filter_clear here
# from whichever sourced file currently defines them.

# ── Core filter primitives ────────────────────────────────────────────────────

# Save the full unfiltered list the moment the user enters filter mode.
_filter_snapshot() {
  _all_items=("${items[@]}")
}

# Rebuild items[] from _all_items[] using _filter_query and filter_mode.
#   filter_mode=exact   → filename must START with the query (prefix match)
#   filter_mode=partial → filename must CONTAIN the query anywhere (default)
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

# Restore the full list and reset filter state.
_filter_clear() {
  items=("${_all_items[@]}")
  _filter_query=""
  _all_items=()
}

# ── Input handlers (called from _read_choice) ─────────────────────────────────

# _filter_on_backspace
#   Called on every backspace keypress.
#   Returns 0 (handled) if the buffer was in filter mode; 1 otherwise,
#   so the caller can fall through to normal backspace behaviour.
_filter_on_backspace() {
  if [[ "$_buf" == =?* ]]; then
    # Buffer is "=de…" — strip one char before the cursor, re-filter
    _buf="${_buf:0:_pos-1}${_buf:_pos}"
    _pos=$(( _pos - 1 ))
    _filter_query="${_buf:1}"
    _filter_apply
    _hl_index=0
    _vp_count
    _vp_cache_reset
    _vp_prime_rows
    _vp_redraw_in_place
    _print_input_line
    return 0
  elif [[ "$_buf" == = ]]; then
    # Buffer is just "=" — exit filter mode, restore full list
    _filter_clear
    _buf=""; _pos=0; _hl_index=0
    _vp_count
    _vp_cache_reset
    _vp_prime_rows
    _vp_redraw_in_place
    _print_input_line
    return 0
  fi
  return 1  # not in filter mode — let caller handle normally
}

# _filter_on_char KEY
#   Called for every printable keypress.
#   Returns 0 (handled) when the character was consumed by filter mode;
#   1 otherwise, so the caller can do normal buffer insertion.
_filter_on_char() {
  local key="$1"
  if [[ "$_buf" == =* ]] || { [ -z "$_buf" ] && [ "$key" = "=" ]; }; then
    # Snapshot the full list the moment the user presses the first "="
    if [ -z "$_buf" ] && [ "$key" = "=" ]; then
      _filter_snapshot
    fi
    _buf="${_buf:0:_pos}${key}${_buf:_pos}"
    _pos=$(( _pos + 1 ))
    # Query = everything after the leading =
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
  return 1  # not in filter mode
}
