# bashbasicsbyvk_firstscreen.sh — saves the finished main screen of a folder, so the next start of `o` in it can show it at once.
# Replayed by _fs_replay at the top of `o` (it must run before anything is loaded, so it lives in `o`).  Format of the file
# ~/.bashbasicsbyvk/firstscreen/<folder with / as %>:
#   line 1:  v1 <rows> <cols> <block height> <frame length>      then the frame: exactly the bytes _vp_emit wrote (_BVK_SCR_RAW)
# Called after the first paint (@call of the load mapper) and after every later main-loop paint.  Builtins only; one mkdir the very first time.
_FS_LAST=""
_fs_save() {
  [ "${BVK_FIRSTSCREEN:-1}" = 0 ] && return 0
  [ "${_GD_ACTIVE:-0}" = 1 ] && return 0                      # a Google Drive mirror: placeholders, not a real folder
  [ -n "${path:-}" ] && [ -n "${_BVK_SCR_RAW:-}" ] && [ -z "${_vp_rowtext_fn:-}" ] || return 0
  local d="${HOME}/.bashbasicsbyvk/firstscreen" f="" rows="${_vp_rows_now:-0}" cols="${_vp_cols_now:-0}" bh="${_blk_h:-0}" out
  [ ! -e "$d.off" ] || return 0
  [ "$rows" -gt 0 ] 2>/dev/null && [ "$cols" -gt 0 ] 2>/dev/null && [ "$bh" -gt 0 ] 2>/dev/null || return 0
  (( bh > rows )) && bh=$rows                                  # a block taller than the window: the cursor row is the last one
  f="${path//\//%}"; [ "${#f}" -le 200 ] || return 0
  out="v1 $rows $cols $bh ${#_BVK_SCR_RAW}"$'\n'"$_BVK_SCR_RAW"
  [ "$out" = "$_FS_LAST" ] && return 0                         # the same screen as the last save: no write
  if [ ! -d "$d" ]; then mkdir -p "$d" 2>/dev/null || return 0; fi
  f="$d/$f"
  if [ ! -e "$f" ]; then local -a _a=("$d"/*); (( ${#_a[@]} > 60 )) && rm -f "$d"/* 2>/dev/null; fi   # a few dozen folders are enough
  builtin printf '%s' "$out" > "$f" 2>/dev/null && _FS_LAST="$out"
  return 0
}
