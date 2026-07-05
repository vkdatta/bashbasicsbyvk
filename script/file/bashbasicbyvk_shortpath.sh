_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffer"

# Persistent buffers (c--, m--, s--) — survive after d- applies them
_SP_CP_FILE="${_SP_BUFFER_DIR}/copy.list"
_SP_MV_FILE="${_SP_BUFFER_DIR}/move.list"
_SP_SC_FILE="${_SP_BUFFER_DIR}/shortcut.list"

# One-time buffers (c-, m-, s-) — cleared immediately after d- applies them
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

# Handles c-, m-, s- (one-time) AND c--, m--, s-- (persistent)
# Longer/more-specific prefixes ("--") are matched first.
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

  local -a live=()
  local missing=0
  local p
  for p in "${list[@]}"; do
    if [ -e "$p" ]; then
      live+=("$p")
    else
      missing=$((missing+1))
      echo "  ⚠️  Skipping missing item (no longer exists): $p"
    fi
  done

  if [ ${#live[@]} -eq 0 ]; then
    echo "ℹ️  $(_sp_op_label "$kind") buffer had no valid items to apply"
    return 0
  fi

  echo "⚙️  Applying $(_sp_op_label "$kind") buffer (${#live[@]} item(s)) → $dest"
  case "$kind" in
    cp) perform_copy "$dest" "${live[@]}" ;;
    mv) perform_move "$dest" "${live[@]}" ;;
    sc) perform_shortcut "$dest" "${live[@]}" ;;
  esac
}

# d- : apply every non-empty buffer (persistent + one-time) to the current $path.
# Persistent buffers (--) are left intact. One-time buffers (-) are cleared right after applying.
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

  # Persistent buffers — applied, then left alone.
  [ ${#cp_list[@]} -gt 0 ] && _sp_apply_buffer cp "$_SP_CP_FILE" "$dest"
  [ ${#mv_list[@]} -gt 0 ] && _sp_apply_buffer mv "$_SP_MV_FILE" "$dest"
  [ ${#sc_list[@]} -gt 0 ] && _sp_apply_buffer sc "$_SP_SC_FILE" "$dest"

  # One-time buffers — applied, then wiped immediately.
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

# v- : view & manage all six buffers.
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
      local i=1
      local p
      for p in "${list[@]}"; do
        local exists_tag=""
        [ ! -e "$p" ] && exists_tag="  ⚠️ missing"
        printf "  %2d) %s%s\n" "$i" "$p" "$exists_tag"
        i=$((i+1))
      done
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
