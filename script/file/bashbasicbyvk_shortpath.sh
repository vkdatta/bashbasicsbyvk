# bashbasicbyvk_shortpath.sh
#
# Fast in-place copy / move / shortcut buffer commands.
# These sit ALONGSIDE the existing `t) Transfer` flow — that flow is untouched
# and remains the full-featured guide for cross-location transfers (Drive,
# GCloud, etc). This module only exists to remove the friction of the common
# case: "copy/move/shortcut a few items that are already right here."
#
# Commands typed straight at the main prompt (no submenu, no navigator):
#
#   c-1,3,5      stage items 1,3,5 (from the currently displayed `items` list)
#                into the COPY buffer
#   c-1-7        stage items 1 through 7 into the COPY buffer
#   m-2,4        stage items into the MOVE buffer
#   s-6          stage items into the SHORTCUT buffer
#   d-           paste/flush ALL staged buffers into the CURRENT path ($path)
#   v-           view/manage the three buffers (remove items, clear, etc.)
#
# Buffers are plain text files on disk (one absolute path per line) so they
# survive `q`uitting the script or the shell dying. They are only ever
# cleared by explicit user action inside `v-` (remove/clear), never
# automatically.

_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffer"
_SP_CP_FILE="${_SP_BUFFER_DIR}/copy.list"
_SP_MV_FILE="${_SP_BUFFER_DIR}/move.list"
_SP_SC_FILE="${_SP_BUFFER_DIR}/shortcut.list"

_sp_ensure_store() {
  mkdir -p "$_SP_BUFFER_DIR" 2>/dev/null
  [ -f "$_SP_CP_FILE" ] || : > "$_SP_CP_FILE"
  [ -f "$_SP_MV_FILE" ] || : > "$_SP_MV_FILE"
  [ -f "$_SP_SC_FILE" ] || : > "$_SP_SC_FILE"
}

# Read a buffer file into the named array variable (nameref), skipping blanks.
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

# Write an array variable (nameref) back to a buffer file.
_sp_save() {
  local -n _sp_in="$1"
  local file="$2"
  : > "$file"
  local entry
  for entry in "${_sp_in[@]}"; do
    [ -n "$entry" ] && printf '%s\n' "$entry" >> "$file"
  done
}

# Append unique paths to a buffer file. Reports added/duplicate counts.
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

# Resolve a c-/m-/s- style item list ("1,3,5" or "1-7" or mixed) against the
# currently displayed `items` array, returning absolute paths.
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

# Entry point for c-/m-/s- prefixed commands. Returns 0 if it handled the
# input (whether successfully or not), 1 if the input wasn't one of ours.
handle_shortpath_stage() {
  local raw="$1"
  local prefix="${raw:0:2}"
  local itemlist="${raw:2}"
  local label file

  case "$prefix" in
    c-) label="COPY";     file="$_SP_CP_FILE" ;;
    m-) label="MOVE";     file="$_SP_MV_FILE" ;;
    s-) label="SHORTCUT"; file="$_SP_SC_FILE" ;;
    *)  return 1 ;;
  esac

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
  echo "$msg — $label buffer now holds $total item(s). Use v- to review, d- to apply."
  return 0
}

_sp_op_label() {
  case "$1" in
    cp) echo "Copy" ;;
    mv) echo "Move" ;;
    sc) echo "Shortcut" ;;
  esac
}

# Apply one buffer (copy/move/shortcut) to $dest. Filters out entries that no
# longer exist on disk, warning about each. Leaves the buffer file untouched
# on failure-to-resolve-dest; only clears entries that were actually applied
# is NOT done automatically — buffer persists until user clears it via v-.
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

# d- : apply every non-empty buffer to the current $path.
handle_shortpath_dispatch() {
  _sp_ensure_store
  local dest="$path"

  local -a cp_list=() mv_list=() sc_list=()
  _sp_load cp_list "$_SP_CP_FILE"
  _sp_load mv_list "$_SP_MV_FILE"
  _sp_load sc_list "$_SP_SC_FILE"

  if [ ${#cp_list[@]} -eq 0 ] && [ ${#mv_list[@]} -eq 0 ] && [ ${#sc_list[@]} -eq 0 ]; then
    echo "ℹ️  All buffers are empty — nothing to apply. Use c-/m-/s- to stage items first."
    return 0
  fi

  echo "📦 Destination: $dest"
  [ ${#cp_list[@]} -gt 0 ] && _sp_apply_buffer cp "$_SP_CP_FILE" "$dest"
  [ ${#mv_list[@]} -gt 0 ] && _sp_apply_buffer mv "$_SP_MV_FILE" "$dest"
  [ ${#sc_list[@]} -gt 0 ] && _sp_apply_buffer sc "$_SP_SC_FILE" "$dest"

  echo "✅ Buffer apply complete. Buffers are NOT auto-cleared — clear via v- if you're done with them."
}

# v- : view & manage all three buffers.
_sp_view_one_buffer() {
  local kind="$1" file="$2"
  local label
  label=$(_sp_op_label "$kind")

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
    echo "r) Remove item(s)   x) Clear entire $label buffer   b) Back"
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
      b|B|"")
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
    _sp_load cp_list "$_SP_CP_FILE"
    _sp_load mv_list "$_SP_MV_FILE"
    _sp_load sc_list "$_SP_SC_FILE"

    echo
    echo "🗂️  Shortpath buffers"
    echo "  1) Copy buffer      (${#cp_list[@]} item(s))"
    echo "  2) Move buffer      (${#mv_list[@]} item(s))"
    echo "  3) Shortcut buffer  (${#sc_list[@]} item(s))"
    echo "  a) Clear ALL buffers"
    echo "  b) Back"
    read -p "View buffer: " v_choice

    case "$v_choice" in
      1) _sp_view_one_buffer cp "$_SP_CP_FILE" ;;
      2) _sp_view_one_buffer mv "$_SP_MV_FILE" ;;
      3) _sp_view_one_buffer sc "$_SP_SC_FILE" ;;
      a|A)
        read -p "Clear ALL three buffers? This can't be undone. (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$_SP_CP_FILE"
          : > "$_SP_MV_FILE"
          : > "$_SP_SC_FILE"
          echo "🗑️  All buffers cleared"
        else
          echo "🚫 Cancelled"
        fi
        ;;
      b|B|"")
        return 0
        ;;
      *)
        echo "⚠️  Invalid choice"
        ;;
    esac
  done
}
