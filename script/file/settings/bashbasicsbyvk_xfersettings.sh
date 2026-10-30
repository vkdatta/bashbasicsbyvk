# bashbasicsbyvk_xfersettings.sh — Settings → File API → Transfer speed  (chunk size x streams for up- / do- / Pending)
# Variables: xfer_chunk_mb (MB of plain data per encrypted blob) and xfer_streams (blobs sent / fetched at the same time).
# Limits (XFER_* in bashbasicsbyvk_settings.sh) are the same as the worker's TRANSFER_LIMITS and bvk-xfer's netx.go.
_ST_XFER_PRESETS=(4x64 8x32 16x16)
_ST_XFER_LABELS=("4 MB x 64 streams   many small pieces" "8 MB x 32 streams   the middle way" "16 MB x 16 streams   (recommended)")

# _xfer_check <mb> <streams>  → 0 when inside every limit, else 1 with the reason in _XFER_WHY
_xfer_check() {
  _XFER_WHY=""
  local a="${1:-}" b="${2:-}"
  [[ "$a" =~ ^[0-9]{1,4}$ && "$b" =~ ^[0-9]{1,4}$ ]] || { _XFER_WHY="Use whole numbers only."; return 1; }
  local mb=$((10#$a)) st=$((10#$b))
  if [ "$mb" -lt "$XFER_MIN_CHUNK_MB" ] || [ "$mb" -gt "$XFER_MAX_CHUNK_MB" ]; then
    _XFER_WHY="Chunk size must be between $XFER_MIN_CHUNK_MB and $XFER_MAX_CHUNK_MB MB."; return 1
  fi
  if [ "$st" -lt 1 ] || [ "$st" -gt "$XFER_MAX_STREAMS" ]; then
    _XFER_WHY="Streams must be between 1 and $XFER_MAX_STREAMS."; return 1
  fi
  if [ $((mb * st)) -gt "$XFER_MAX_INFLIGHT_MB" ]; then
    _XFER_WHY="$mb MB x $st streams = $((mb * st)) MB in flight at once; the most allowed is $XFER_MAX_INFLIGHT_MB MB."; return 1
  fi
  return 0
}
# _xfer_set <mb> <streams>  → checks, stores, saves, applies to the running app
_xfer_set() {
  _xfer_check "${1:-}" "${2:-}" || { _st_note "🔴  $_XFER_WHY"; return 1; }
  xfer_chunk_mb=$((10#$1)); xfer_streams=$((10#$2))
  save_settings
  _bb_xfer_apply
  _st_note "💫 Transfers now use $xfer_chunk_mb MB pieces, $xfer_streams at a time ($((xfer_chunk_mb * xfer_streams)) MB in flight)."
}

_st_xfer_build() {
  local i custom=1
  _st_reset
  _st_add h "Pick a ready combination  (MB per piece x pieces at the same time)"
  for i in "${!_ST_XFER_PRESETS[@]}"; do
    _st_eq "${_ST_XFER_PRESETS[$i]}" "${xfer_chunk_mb}x${xfer_streams}"
    [ "$_o" = 1 ] && custom=0
    _st_add r "${_ST_XFER_LABELS[$i]}" "$_o" "" "p:${_ST_XFER_PRESETS[$i]}"
  done
  _st_add h "Anything else  (1-$XFER_MAX_CHUNK_MB MB, 1-$XFER_MAX_STREAMS streams, at most $XFER_MAX_INFLIGHT_MB MB at once)"
  if [ "$custom" = 1 ]; then
    _st_add r "Custom" 1 "${xfer_chunk_mb} MB x ${xfer_streams} streams" custom
  else
    _st_add a "Custom…" 0 "" custom
  fi
}
_st_xfer_act() {
  local tag="${_st_tag[$1]}" mb st
  case "$tag" in
    p:*) mb="${tag#p:}"; st="${mb#*x}"; mb="${mb%%x*}"; _xfer_set "$mb" "$st" ;;
    custom)
      _st_ask "Chunk size in MB ($XFER_MIN_CHUNK_MB-$XFER_MAX_CHUNK_MB)" "$xfer_chunk_mb" || return
      mb="$_st_in"
      _st_ask "Streams at the same time (1-$XFER_MAX_STREAMS)" "$xfer_streams" || return
      st="$_st_in"
      _xfer_set "$mb" "$st" ;;
  esac
}
xfer_speed_settings() { _st_run "Transfer speed" _st_xfer_build _st_xfer_act; }
