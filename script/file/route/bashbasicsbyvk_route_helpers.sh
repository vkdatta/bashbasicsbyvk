_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffer"

_SP_CP_FILE="${_SP_BUFFER_DIR}/copy.list"
_SP_MV_FILE="${_SP_BUFFER_DIR}/move.list"
_SP_SC_FILE="${_SP_BUFFER_DIR}/shortcut.list"

_SP_CP_ONCE_FILE="${_SP_BUFFER_DIR}/copy.once.list"
_SP_MV_ONCE_FILE="${_SP_BUFFER_DIR}/move.once.list"
_SP_SC_ONCE_FILE="${_SP_BUFFER_DIR}/shortcut.once.list"

_sp_ensure_store() {
  mkdir -p "$_SP_BUFFER_DIR" 2>/dev/null
  [ -f "$_SP_CP_FILE" ]      || : > "$_SP_CP_FILE"
  [ -f "$_SP_MV_FILE" ]      || : > "$_SP_MV_FILE"
  [ -f "$_SP_SC_FILE" ]      || : > "$_SP_SC_FILE"
  [ -f "$_SP_CP_ONCE_FILE" ] || : > "$_SP_CP_ONCE_FILE"
  [ -f "$_SP_MV_ONCE_FILE" ] || : > "$_SP_MV_ONCE_FILE"
  [ -f "$_SP_SC_ONCE_FILE" ] || : > "$_SP_SC_ONCE_FILE"
}

_sp_load() {
  local -n _sp_out="$1"
  local file="$2"
  _sp_out=()
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    _sp_out+=("$line")
  done < "$file"
}

_sp_save() {
  local -n _sp_in="$1"
  local file="$2"
  : > "$file"
  local entry
  for entry in "${_sp_in[@]}"; do
    [ -n "$entry" ] && printf '%s\n' "$entry" >> "$file"
  done
}

_sp_append() {
  local file="$1"; shift
  local -a existing=()
  _sp_load existing "$file"
  local added=0 dupes=0
  local p
  for p in "$@"; do
    if _in_selection "$p" "${existing[@]}"; then
      dupes=$((dupes+1))
    else
      existing+=("$p")
      added=$((added+1))
    fi
  done
  _sp_save existing "$file"
  echo "$added|$dupes|${#existing[@]}"
}

_sp_op_label() {
  case "$1" in
    cp) echo "Copy" ;;
    mv) echo "Move" ;;
    sc) echo "Shortcut" ;;
  esac
}

# Parse an "all-except" itemlist of the form  a-<exclusions>
# e.g.  a-1-5,7  → all indices except 1,2,3,4,5,7
# Returns a space-separated list of 1-based indices.
_sp_parse_all_except() {
  local spec="$1"    # the part after "a-", e.g. "1-5,7"
  local total="$2"   # total number of items

  local -a excluded=()
  IFS=',' read -ra parts <<< "$spec"
  local part
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}"
      local i
      for (( i=lo; i<=hi; i++ )); do
        excluded+=("$i")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      excluded+=("$part")
    fi
  done

  # Build exclusion lookup
  local -A excl_set=()
  local e
  for e in "${excluded[@]}"; do
    excl_set["$e"]=1
  done

  local result=()
  local i
  for (( i=1; i<=total; i++ )); do
    [ -z "${excl_set[$i]+x}" ] && result+=("$i")
  done

  echo "${result[*]}"
}

# ─────────────────────────────────────────────
#  Guard helpers (shared by stage + fileapi handlers)
# ─────────────────────────────────────────────

# Guard: reject empty itemlist or imaginary_mode, then resolve.
# Usage: _sp_guard_and_resolve "$itemlist" "$pfx"  || return 0
# On success, sp_resolved is populated.
_sp_guard_and_resolve() {
  local itemlist="$1" pfx="$2"
  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: ${pfx}1,3,5  or  ${pfx}1-7  or  ${pfx}a-1-5,7"
    return 1
  fi
  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view (group filter or forceshow) before using ${pfx} shortcuts."
    return 1
  fi
  _sp_resolve_itemlist "$itemlist"
}

# ─────────────────────────────────────────────
#  Shared stage / apply logic
# ─────────────────────────────────────────────

# Stage items into any op buffer.
# Usage: _sp_stage_buffer <op> <persistent> <itemlist>
#   op: cp | mv | sc
_sp_stage_buffer() {
  local op="$1" persistent="$2" itemlist="$3"
  local label file_persistent file_once pfx_persistent pfx_once

  case "$op" in
    cp) label="COPY";     file_persistent="$_SP_CP_FILE"; file_once="$_SP_CP_ONCE_FILE"
        pfx_persistent="c--"; pfx_once="c-" ;;
    mv) label="MOVE";     file_persistent="$_SP_MV_FILE"; file_once="$_SP_MV_ONCE_FILE"
        pfx_persistent="m--"; pfx_once="m-" ;;
    sc) label="SHORTCUT"; file_persistent="$_SP_SC_FILE"; file_once="$_SP_SC_ONCE_FILE"
        pfx_persistent="s--"; pfx_once="s-" ;;
  esac

  local file pfx
  if $persistent; then
    label="$label (persistent)"; file="$file_persistent"; pfx="$pfx_persistent"
  else
    label="$label (once)";       file="$file_once";       pfx="$pfx_once"
  fi

  _sp_ensure_store
  _sp_guard_and_resolve "$itemlist" "$pfx" || return 0

  local result
  result=$(_sp_append "$file" "${sp_resolved[@]}")
  local added="${result%%|*}"
  local rest="${result#*|}"
  local dupes="${rest%%|*}"
  local total="${rest#*|}"

  local msg="📌 Buffered $added item(s) → $label"
  [ "$dupes" -gt 0 ] && msg="$msg (skipped $dupes already buffered)"

  local behavior
  if $persistent; then behavior="kept after d- applies it"
  else                  behavior="cleared automatically after d- applies it"
  fi

  echo "$msg — $label buffer now holds $total item(s). Use v- to review, d- to apply ($behavior)."
}

# Apply any op buffer to a destination directory.
# Usage: _sp_apply_buffer <op> <file> <dest>
#   op: cp | mv | sc
_sp_apply_buffer() {
  local op="$1" file="$2" dest="$3"
  local label
  label=$(_sp_op_label "$op")   # "Copy" | "Move" | "Shortcut"

  local -a list=()
  _sp_load list "$file"
  [ ${#list[@]} -eq 0 ] && return 0

  local -a live=()
  local missing=0 p
  for p in "${list[@]}"; do
    if [ -e "$p" ]; then
      live+=("$p")
    else
      missing=$((missing+1))
      echo "  ⚠️  Skipping missing item (no longer exists): $p"
    fi
  done

  if [ ${#live[@]} -eq 0 ]; then
    echo "ℹ️  $label buffer had no valid items to apply"
    return 0
  fi

  echo "⚙️  Applying $label buffer (${#live[@]} item(s)) → $dest"
  case "$op" in
    cp) perform_copy     "$dest" "${live[@]}" ;;
    mv) perform_move     "$dest" "${live[@]}" ;;
    sc) perform_shortcut "$dest" "${live[@]}" ;;
  esac
}

# Resolve an itemlist string (supports "a-<spec>" for all-except) against
# the global $items array.  Populates the global sp_resolved array.
_sp_resolve_itemlist() {
  local itemlist="$1"
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available in current view to reference"
    return 1
  fi

  local indices=()

  # Bare "a" = select all items
  if [[ "$itemlist" == "a" ]]; then
    indices=($(seq 1 "${#items[@]}"))

  # All-except syntax:  a-<exclusion-spec>
  elif [[ "$itemlist" =~ ^a-(.+)$ ]]; then
    local excl_spec="${BASH_REMATCH[1]}"
    indices=($(_sp_parse_all_except "$excl_spec" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ All-except filter excluded every item (spec: '$excl_spec')"
      return 1
    fi
  else
    indices=($(parse_selection "$itemlist" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ No valid item numbers in '$itemlist'"
      return 1
    fi
  fi

  sp_resolved=()
  local idx
  for idx in "${indices[@]}"; do
    sp_resolved+=("${items[$((idx-1))]}")
  done
  return 0
}
