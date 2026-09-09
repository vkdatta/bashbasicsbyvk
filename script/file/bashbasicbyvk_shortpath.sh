_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffer"

source "bashbasicsbyvk_fileapi.sh"

_SP_CP_FILE="${_SP_BUFFER_DIR}/copy.list"
_SP_MV_FILE="${_SP_BUFFER_DIR}/move.list"
_SP_SC_FILE="${_SP_BUFFER_DIR}/shortcut.list"

_SP_CP_ONCE_FILE="${_SP_BUFFER_DIR}/copy.once.list"
_SP_MV_ONCE_FILE="${_SP_BUFFER_DIR}/move.once.list"
_SP_SC_ONCE_FILE="${_SP_BUFFER_DIR}/shortcut.once.list"

_sp_ensure_store() {
  mkdir -p "$_SP_BUFFER_DIR" 2>/dev/null
  [ -f "$_SP_CP_FILE" ] || : > "$_SP_CP_FILE"
  [ -f "$_SP_MV_FILE" ] || : > "$_SP_MV_FILE"
  [ -f "$_SP_SC_FILE" ] || : > "$_SP_SC_FILE"
  [ -f "$_SP_CP_ONCE_FILE" ] || : > "$_SP_CP_ONCE_FILE"
  [ -f "$_SP_MV_ONCE_FILE" ] || : > "$_SP_MV_ONCE_FILE"
  [ -f "$_SP_SC_ONCE_FILE" ] || : > "$_SP_SC_ONCE_FILE"
}

_sp_load() {
  local -n _sp_out="$1"
  local file="$2"
  _sp_out=()
  [ -f "$file" ] || return 0
  # Python heredoc: read all non-blank lines at once, NUL-delimited for safety
  local raw
  raw=$(python3 - "$file" <<'PYEOF'
import sys, os
p = sys.argv[1]
if os.path.isfile(p):
    with open(p) as f:
        lines = [l.rstrip('\n') for l in f if l.strip()]
    print('\x00'.join(lines), end='\x00' if lines else '')
PYEOF
)
  [ -z "$raw" ] && return 0
  IFS=$'\x00' read -r -d '' -a _sp_out <<< "$raw" || true
}

_sp_save() {
  local -n _sp_in="$1"
  local file="$2"
  # Python heredoc: join array via NUL on stdin, write non-blank lines atomically
  local joined
  printf '%s\x00' "${_sp_in[@]}" | python3 - "$file" <<'PYEOF'
import sys, os
dest = sys.argv[1]
data = sys.stdin.buffer.read()
lines = [e.decode() for e in data.split(b'\x00') if e.strip()]
tmp = dest + '.tmp'
with open(tmp, 'w') as f:
    f.write('\n'.join(lines) + ('\n' if lines else ''))
os.replace(tmp, dest)
PYEOF
}

_sp_append() {
  local file="$1"; shift
  # Python heredoc: read existing + new paths (NUL-separated), dedup preserving order, write back
  # Outputs: added|dupes|total
  local result
  result=$(
    {
      # existing lines from file
      [ -f "$file" ] && cat "$file"
      # new candidates via NUL so paths with newlines are safe
      printf '\x00NEW_BOUNDARY\x00'
      printf '%s\x00' "$@"
    } | python3 - "$file" <<'PYEOF'
import sys, os
data = sys.stdin.buffer.read()
sep = b'\x00NEW_BOUNDARY\x00'
before, _, after = data.partition(sep)

existing = [l for l in before.decode().splitlines() if l.strip()]
new_paths = [e.decode() for e in after.split(b'\x00') if e.strip()]

seen = set(existing)
added = 0
dupes = 0
for p in new_paths:
    if p in seen:
        dupes += 1
    else:
        existing.append(p)
        seen.add(p)
        added += 1

tmp = sys.argv[1] + '.tmp'
with open(tmp, 'w') as f:
    f.write('\n'.join(existing) + ('\n' if existing else ''))
os.replace(tmp, sys.argv[1])
print(f"{added}|{dupes}|{len(existing)}")
PYEOF
  )
  echo "$result"
}

_sp_resolve_itemlist() {
  local itemlist="$1"
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available in current view to reference"
    return 1
  fi
  local indices
  indices=($(parse_selection "$itemlist" "${#items[@]}"))
  if [ ${#indices[@]} -eq 0 ]; then
    echo "❌ No valid item numbers in '$itemlist'"
    return 1
  fi
  sp_resolved=()
  local idx
  for idx in "${indices[@]}"; do
    sp_resolved+=("${items[$((idx-1))]}")
  done
  return 0
}

handle_shortpath_stage() {
  local raw="$1"
  local prefix persistent label file itemlist

  case "$raw" in
    c--*) prefix="c--"; persistent=true;  label="COPY (persistent)";     file="$_SP_CP_FILE" ;;
    m--*) prefix="m--"; persistent=true;  label="MOVE (persistent)";     file="$_SP_MV_FILE" ;;
    s--*) prefix="s--"; persistent=true;  label="SHORTCUT (persistent)"; file="$_SP_SC_FILE" ;;
    c-*)  prefix="c-";  persistent=false; label="COPY (once)";           file="$_SP_CP_ONCE_FILE" ;;
    m-*)  prefix="m-";  persistent=false; label="MOVE (once)";           file="$_SP_MV_ONCE_FILE" ;;
    s-*)  prefix="s-";  persistent=false; label="SHORTCUT (once)";       file="$_SP_SC_ONCE_FILE" ;;
    *) return 1 ;;
  esac

  itemlist="${raw:${#prefix}}"

  _sp_ensure_store

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: ${prefix}1,3,5  or  ${prefix}1-7"
    return 0
  fi

  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view (group filter or forceshow) before using ${prefix} shortcuts."
    return 0
  fi

  _sp_resolve_itemlist "$itemlist" || return 0

  local result
  result=$(_sp_append "$file" "${sp_resolved[@]}")
  local added="${result%%|*}"
  local rest="${result#*|}"
  local dupes="${rest%%|*}"
  local total="${rest#*|}"

  local msg="📌 Buffered $added item(s) → $label"
  [ "$dupes" -gt 0 ] && msg="$msg (skipped $dupes already buffered)"

  local behavior
  if $persistent; then
    behavior="kept after d- applies it"
  else
    behavior="cleared automatically after d- applies it"
  fi

  echo "$msg — $label buffer now holds $total item(s). Use v- to review, d- to apply ($behavior)."
  return 0
}

_sp_op_label() {
  case "$1" in
    cp) echo "Copy" ;;
    mv) echo "Move" ;;
    sc) echo "Shortcut" ;;
  esac
}

_sp_apply_buffer() {
  local kind="$1" file="$2" dest="$3"
  local -a list=()
  _sp_load list "$file"
  [ ${#list[@]} -eq 0 ] && return 0

  # Batch existence-check via Python: partition live vs missing in one process
  local -a live=()
  local missing_summary
  {
    IFS=$'\x00' read -r -d '' -a live || true
    read -r missing_summary
  } < <(
    printf '%s\x00' "${list[@]}" | python3 <<'PYEOF'
import sys, os
paths = [e for e in sys.stdin.buffer.read().split(b'\x00') if e]
live = []
missing = []
for p in paths:
    s = p.decode()
    if os.path.exists(s):
        live.append(p)
    else:
        missing.append(s)
sys.stdout.buffer.write(b'\x00'.join(live))
if live:
    sys.stdout.buffer.write(b'\x00')
sys.stdout.buffer.write(b'\n')
sys.stdout.write(f"MISSING:{len(missing)}:{'|'.join(missing)}\n")
PYEOF
  )

  # Report missing items individually (these no longer exist on disk)
  local missing_count="${missing_summary#MISSING:}"
  missing_count="${missing_count%%:*}"
  if [ "${missing_count:-0}" -gt 0 ]; then
    local missing_paths="${missing_summary#MISSING:*:}"
    IFS='|' read -ra _mp_arr <<< "$missing_paths"
    local mp
    for mp in "${_mp_arr[@]}"; do
      [ -n "$mp" ] && echo "  ⚠️  Skipping missing item (no longer exists): $mp"
    done
  fi

  if [ ${#live[@]} -eq 0 ]; then
    echo "ℹ️  $(_sp_op_label "$kind") buffer had no valid items to apply"
    return 0
  fi

  echo "⚙️  Applying $(_sp_op_label "$kind") buffer (${#live[@]} item(s)) → $dest"
  case "$kind" in
    cp) perform_copy     "$dest" "${live[@]}" ;;
    mv) perform_move     "$dest" "${live[@]}" ;;
    sc) perform_shortcut "$dest" "${live[@]}" ;;
  esac
}

handle_shortpath_dispatch() {
  _sp_ensure_store
  local dest="$path"

  local -a cp_list=() mv_list=() sc_list=()
  local -a cp_once=() mv_once=() sc_once=()
  _sp_load cp_list "$_SP_CP_FILE"
  _sp_load mv_list "$_SP_MV_FILE"
  _sp_load sc_list "$_SP_SC_FILE"
  _sp_load cp_once "$_SP_CP_ONCE_FILE"
  _sp_load mv_once "$_SP_MV_ONCE_FILE"
  _sp_load sc_once "$_SP_SC_ONCE_FILE"

  if [ ${#cp_list[@]} -eq 0 ] && [ ${#mv_list[@]} -eq 0 ] && [ ${#sc_list[@]} -eq 0 ] \
     && [ ${#cp_once[@]} -eq 0 ] && [ ${#mv_once[@]} -eq 0 ] && [ ${#sc_once[@]} -eq 0 ]; then
    echo "ℹ️  All buffers are empty — nothing to apply. Use c-/m-/s- (once) or c--/m--/s-- (persistent) to stage items first."
    return 0
  fi

  echo "📦 Destination: $dest"

  [ ${#cp_list[@]} -gt 0 ] && _sp_apply_buffer cp "$_SP_CP_FILE" "$dest"
  [ ${#mv_list[@]} -gt 0 ] && _sp_apply_buffer mv "$_SP_MV_FILE" "$dest"
  [ ${#sc_list[@]} -gt 0 ] && _sp_apply_buffer sc "$_SP_SC_FILE" "$dest"

  if [ ${#cp_once[@]} -gt 0 ]; then
    _sp_apply_buffer cp "$_SP_CP_ONCE_FILE" "$dest"
    : > "$_SP_CP_ONCE_FILE"
  fi
  if [ ${#mv_once[@]} -gt 0 ]; then
    _sp_apply_buffer mv "$_SP_MV_ONCE_FILE" "$dest"
    : > "$_SP_MV_ONCE_FILE"
  fi
  if [ ${#sc_once[@]} -gt 0 ]; then
    _sp_apply_buffer sc "$_SP_SC_ONCE_FILE" "$dest"
    : > "$_SP_SC_ONCE_FILE"
  fi

  echo "✅ Buffer apply complete. Persistent (--) buffers were kept. One-time (-) buffers were cleared."
}

_sp_view_one_buffer() {
  local label="$1" file="$2"

  while true; do
    local -a list=()
    _sp_load list "$file"

    echo
    echo "📋 $label buffer (${#list[@]}):"
    if [ ${#list[@]} -eq 0 ]; then
      echo "  (empty)"
    else
      # Batch existence-check via Python: outputs "<idx>|<exists>|<path>" per line
      local view_lines
      view_lines=$(
        printf '%s\x00' "${list[@]}" | python3 <<'PYEOF'
import sys, os
items = [e.decode() for e in sys.stdin.buffer.read().split(b'\x00') if e]
for i, p in enumerate(items, 1):
    tag = '' if os.path.exists(p) else '  ⚠️ missing'
    print(f"  {i:2d}) {p}{tag}")
PYEOF
      )
      echo "$view_lines"
    fi

    echo
    echo "r) Remove item(s)   x) Clear entire $label buffer   q) Back"
    read -p "$label buffer: " bv_choice

    case "$bv_choice" in
      r|R)
        if [ ${#list[@]} -eq 0 ]; then
          echo "⚠️  Nothing to remove"
          continue
        fi
        read -p "Item number(s) to remove (e.g. 1,3 or 2-4): " rm_input
        local rm_indices
        rm_indices=($(parse_selection "$rm_input" "${#list[@]}"))
        if [ ${#rm_indices[@]} -eq 0 ]; then
          echo "❌ No valid numbers entered"
          continue
        fi
        local -A to_remove=()
        local ri
        for ri in "${rm_indices[@]}"; do
          to_remove["$ri"]=1
        done
        local -a kept=()
        local j=1
        local p
        for p in "${list[@]}"; do
          [ -z "${to_remove[$j]+x}" ] && kept+=("$p")
          j=$((j+1))
        done
        _sp_save kept "$file"
        echo "✅ Removed ${#rm_indices[@]} item(s) from $label buffer"
        ;;
      x|X)
        read -p "Clear the entire $label buffer? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$file"
          echo "🗑️  $label buffer cleared"
        else
          echo "🚫 Cancelled"
        fi
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo "⚠️  Invalid choice"
        ;;
    esac
  done
}

handle_shortpath_view() {
  _sp_ensure_store
  while true; do
    local -a cp_list=() mv_list=() sc_list=()
    local -a cp_once=() mv_once=() sc_once=()
    _sp_load cp_list "$_SP_CP_FILE"
    _sp_load mv_list "$_SP_MV_FILE"
    _sp_load sc_list "$_SP_SC_FILE"
    _sp_load cp_once "$_SP_CP_ONCE_FILE"
    _sp_load mv_once "$_SP_MV_ONCE_FILE"
    _sp_load sc_once "$_SP_SC_ONCE_FILE"

    echo
    echo "🗂️  Shortpath buffers"
    echo "  1) Copy      persistent (--)  (${#cp_list[@]} item(s))"
    echo "  2) Move      persistent (--)  (${#mv_list[@]} item(s))"
    echo "  3) Shortcut  persistent (--)  (${#sc_list[@]} item(s))"
    echo "  4) Copy      once (-)         (${#cp_once[@]} item(s))"
    echo "  5) Move      once (-)         (${#mv_once[@]} item(s))"
    echo "  6) Shortcut  once (-)         (${#sc_once[@]} item(s))"
    echo "  a) Clear ALL buffers"
    echo "  q) Back"
    read -p "View buffer: " v_choice

    case "$v_choice" in
      1) _sp_view_one_buffer "Copy (persistent)"     "$_SP_CP_FILE" ;;
      2) _sp_view_one_buffer "Move (persistent)"     "$_SP_MV_FILE" ;;
      3) _sp_view_one_buffer "Shortcut (persistent)" "$_SP_SC_FILE" ;;
      4) _sp_view_one_buffer "Copy (once)"           "$_SP_CP_ONCE_FILE" ;;
      5) _sp_view_one_buffer "Move (once)"           "$_SP_MV_ONCE_FILE" ;;
      6) _sp_view_one_buffer "Shortcut (once)"       "$_SP_SC_ONCE_FILE" ;;
      a|A)
        read -p "Clear ALL six buffers? This can't be undone. (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$_SP_CP_FILE"
          : > "$_SP_MV_FILE"
          : > "$_SP_SC_FILE"
          : > "$_SP_CP_ONCE_FILE"
          : > "$_SP_MV_ONCE_FILE"
          : > "$_SP_SC_ONCE_FILE"
          echo "🗑️  All buffers cleared"
        else
          echo "🚫 Cancelled"
        fi
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo "⚠️  Invalid choice"
        ;;
    esac
  done
}
