source "bashbasicsbyvk_staging_fileapi.sh"
source "bashbasicsbyvk_staging_helpers.sh"
source "bashbasicsbyvk_staging_move.sh"
source "bashbasicsbyvk_staging_copy.sh"
source "bashbasicsbyvk_staging_shortcut.sh"
source "bashbasicsbyvk_staging_shortcut_registry.sh"
source "bashbasicsbyvk_staging_map.sh"
source "bashbasicsbyvk_staging_bookmark.sh"

# ─────────────────────────────────────────────
#  Public entry points (called from 'o')
# ─────────────────────────────────────────────

# Route a raw staging command (c-*, m-*, s-*, b-*, c--*, m--*, s--*, b--*) to
# the correct operation/buffer.
# Path-map commands (p-*) are stagingd to handle_staging_map (staging_map.sh).
#
# Syntax supported for the item-list portion:
#   1,3,5          → items 1, 3 and 5
#   1-7            → items 1 through 7
#   a-1-5,7        → ALL items EXCEPT 1–5 and 7
#   (any combo)
handle_staging_stage() {
  local raw="$1"
  local prefix persistent label file itemlist

  case "$raw" in
    c--*) prefix="c--"; persistent=true;  label="COPY (persistent)";        file="$_SP_CP_FILE" ;;
    m--*) prefix="m--"; persistent=true;  label="MOVE (persistent)";        file="$_SP_MV_FILE" ;;
    s--*) prefix="s--"; persistent=true;  label="SHORTCUT (persistent)";    file="$_SP_SC_FILE" ;;
    b--*) prefix="b--"; persistent=true;  label="BOOKMARK (persistent)";    file="$_SP_BM_FILE" ;;
    c-*)  prefix="c-";  persistent=false; label="COPY (once)";              file="$_SP_CP_ONCE_FILE" ;;
    m-*)  prefix="m-";  persistent=false; label="MOVE (once)";              file="$_SP_MV_ONCE_FILE" ;;
    s-*)  prefix="s-";  persistent=false; label="SHORTCUT (once)";          file="$_SP_SC_ONCE_FILE" ;;
    b-*)  prefix="b-";  persistent=false; label="BOOKMARK (once)";          file="$_SP_BM_ONCE_FILE" ;;
    *) return 1 ;;
  esac

  itemlist="${raw:${#prefix}}"

  case "$raw" in
    c--*|c-*) staging_copy_stage     "$persistent" "$itemlist" ;;
    m--*|m-*) staging_move_stage     "$persistent" "$itemlist" ;;
    s--*|s-*) staging_shortcut_stage "$persistent" "$itemlist" ;;
    b--*|b-*) staging_bookmark_stage "$persistent" "$itemlist" ;;
  esac
}

# Apply all non-empty buffers to the current path destination.
handle_staging_dispatch() {
  _sp_ensure_store
  local dest="$path"

  local -a cp_list=() mv_list=() sc_list=() bm_list=()
  local -a cp_once=() mv_once=() sc_once=() bm_once=()
  _sp_load cp_list "$_SP_CP_FILE"
  _sp_load mv_list "$_SP_MV_FILE"
  _sp_load sc_list "$_SP_SC_FILE"
  _sp_load bm_list "$_SP_BM_FILE"
  _sp_load cp_once "$_SP_CP_ONCE_FILE"
  _sp_load mv_once "$_SP_MV_ONCE_FILE"
  _sp_load sc_once "$_SP_SC_ONCE_FILE"
  _sp_load bm_once "$_SP_BM_ONCE_FILE"

  if [ ${#cp_list[@]} -eq 0 ] && [ ${#mv_list[@]} -eq 0 ] && [ ${#sc_list[@]} -eq 0 ] && [ ${#bm_list[@]} -eq 0 ] \
     && [ ${#cp_once[@]} -eq 0 ] && [ ${#mv_once[@]} -eq 0 ] && [ ${#sc_once[@]} -eq 0 ] && [ ${#bm_once[@]} -eq 0 ]; then
    echo "ℹ️  All buffers are empty — nothing to apply. Use c-/m-/s-/b- (once) or c--/m--/s--/b-- (persistent) to stage items first."
    return 0
  fi

  echo "📦 Destination: $dest"

  [ ${#cp_list[@]} -gt 0 ] && staging_copy_apply     "$_SP_CP_FILE" "$dest"
  [ ${#mv_list[@]} -gt 0 ] && staging_move_apply     "$_SP_MV_FILE" "$dest"
  [ ${#sc_list[@]} -gt 0 ] && staging_shortcut_apply "$_SP_SC_FILE" "$dest"
  [ ${#bm_list[@]} -gt 0 ] && staging_bookmark_apply "$_SP_BM_FILE" "$dest"

  if [ ${#cp_once[@]} -gt 0 ]; then
    staging_copy_apply "$_SP_CP_ONCE_FILE" "$dest"
    : > "$_SP_CP_ONCE_FILE"
  fi
  if [ ${#mv_once[@]} -gt 0 ]; then
    staging_move_apply "$_SP_MV_ONCE_FILE" "$dest"
    : > "$_SP_MV_ONCE_FILE"
  fi
  if [ ${#sc_once[@]} -gt 0 ]; then
    staging_shortcut_apply "$_SP_SC_ONCE_FILE" "$dest"
    : > "$_SP_SC_ONCE_FILE"
  fi
  if [ ${#bm_once[@]} -gt 0 ]; then
    staging_bookmark_apply "$_SP_BM_ONCE_FILE" "$dest"
    : > "$_SP_BM_ONCE_FILE"
  fi

  echo "✅ Buffer apply complete. Persistent (--) buffers were kept. One-time (-) buffers were cleared."
}

# ─────────────────────────────────────────────
#  Buffer viewer (v-)
# ─────────────────────────────────────────────

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

handle_staging_view() {
  _sp_ensure_store
  while true; do
    local -a cp_list=() mv_list=() sc_list=() bm_list=()
    local -a cp_once=() mv_once=() sc_once=() bm_once=()
    _sp_load cp_list "$_SP_CP_FILE"
    _sp_load mv_list "$_SP_MV_FILE"
    _sp_load sc_list "$_SP_SC_FILE"
    _sp_load bm_list "$_SP_BM_FILE"
    _sp_load cp_once "$_SP_CP_ONCE_FILE"
    _sp_load mv_once "$_SP_MV_ONCE_FILE"
    _sp_load sc_once "$_SP_SC_ONCE_FILE"
    _sp_load bm_once "$_SP_BM_ONCE_FILE"

    echo
    echo "🗂️  Shortpath buffers"
    echo "  1) Copy      persistent (--)  (${#cp_list[@]} item(s))"
    echo "  2) Move      persistent (--)  (${#mv_list[@]} item(s))"
    echo "  3) Shortcut  persistent (--)  (${#sc_list[@]} item(s))"
    echo "  4) Bookmark  persistent (--)  (${#bm_list[@]} item(s))"
    echo "  5) Copy      once (-)         (${#cp_once[@]} item(s))"
    echo "  6) Move      once (-)         (${#mv_once[@]} item(s))"
    echo "  7) Shortcut  once (-)         (${#sc_once[@]} item(s))"
    echo "  8) Bookmark  once (-)         (${#bm_once[@]} item(s))"
    echo "  a) Clear ALL buffers"
    echo "  q) Back"
    read -p "View buffer: " v_choice

    case "$v_choice" in
      1) _sp_view_one_buffer "Copy (persistent)"     "$_SP_CP_FILE" ;;
      2) _sp_view_one_buffer "Move (persistent)"     "$_SP_MV_FILE" ;;
      3) _sp_view_one_buffer "Shortcut (persistent)" "$_SP_SC_FILE" ;;
      4) _sp_view_one_buffer "Bookmark (persistent)" "$_SP_BM_FILE" ;;
      5) _sp_view_one_buffer "Copy (once)"           "$_SP_CP_ONCE_FILE" ;;
      6) _sp_view_one_buffer "Move (once)"           "$_SP_MV_ONCE_FILE" ;;
      7) _sp_view_one_buffer "Shortcut (once)"       "$_SP_SC_ONCE_FILE" ;;
      8) _sp_view_one_buffer "Bookmark (once)"       "$_SP_BM_ONCE_FILE" ;;
      a|A)
        read -p "Clear ALL eight buffers? This can't be undone. (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$_SP_CP_FILE"
          : > "$_SP_MV_FILE"
          : > "$_SP_SC_FILE"
          : > "$_SP_BM_FILE"
          : > "$_SP_CP_ONCE_FILE"
          : > "$_SP_MV_ONCE_FILE"
          : > "$_SP_SC_ONCE_FILE"
          : > "$_SP_BM_ONCE_FILE"
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
