#!/usr/bin/env bash
# bashbasicsbyvk_switch.sh
# ════════════════════════════════════════════════════════════════════════════
#  SWITCH — two-tab overlay inside the main file-manager loop
#
#  Tabs (← / → to cycle when input is empty):
#    📌 Bookmarks  ~/.bashbasicsbyvk/switch/   — .swlink bookmark files
#    🕐 Recents    ~/.bashbasicsbyvk/recents.list — daemon-maintained, read-only
#
#  Execute / scripting has moved to bashbasicsbyvk_functions.sh (fx tab).
#  Tab switch is in-place: the block redraws inside the existing terminal
#  block — no scroll, no new container.
# ════════════════════════════════════════════════════════════════════════════

# ── Storage roots ─────────────────────────────────────────────────────────────
_SW_DIR="${HOME}/.bashbasicsbyvk/switch"
_SW_RECENTS_LIST="${HOME}/.bashbasicsbyvk/recents.list"
_SW_EXCLUDE_FILE="${HOME}/.bashbasicsbyvk/recents_exclude.conf"

_sw_ensure_store() {
  mkdir -p "$_SW_DIR" 2>/dev/null
}

# ── Exclude list helpers ───────────────────────────────────────────────────────

# Ensure the exclude file exists (daemon also creates it, but defence-in-depth)
_sw_excl_ensure() {
  if [ ! -f "$_SW_EXCLUDE_FILE" ]; then
    cat > "$_SW_EXCLUDE_FILE" << 'EXCL_TEMPLATE'
# recents_exclude.conf — files/folders to hide from recents
#
# Syntax:  <type>  <value>
#   filename   NAME      — hides NAME everywhere (any directory)
#   foldername NAME      — hides everything inside any folder named NAME
#   filepath   /abs/path — hides this exact file only
#   dirpath    /abs/path — hides everything under this directory
#
# Examples:
#   filename   .env
#   foldername .git
#   foldername node_modules
#   foldername __pycache__
#   filepath   /home/user/notes/secret.txt
#   dirpath    /home/user/work/private
EXCL_TEMPLATE
  fi
}

# Print a numbered, human-readable view of active (non-comment) exclude rules
_sw_excl_list() {
  _sw_excl_ensure
  local idx=0 line kind value
  echo "━━━ Exclude rules ($( grep -cv '^\s*#\|^\s*$' "$_SW_EXCLUDE_FILE" 2>/dev/null || echo 0 ) active) ━━━"
  while IFS= read -r line; do
    [[ "$line" =~ ^\s*# || -z "${line// }" ]] && continue
    idx=$(( idx + 1 ))
    read -r kind value <<< "$line"
    case "$kind" in
      filename)   printf '  %2d)  📄 filename   %s\n'  "$idx" "$value" ;;
      foldername) printf '  %2d)  📁 foldername %s\n'  "$idx" "$value" ;;
      filepath)   printf '  %2d)  🔒 filepath   %s\n'  "$idx" "$value" ;;
      dirpath)    printf '  %2d)  🚫 dirpath    %s\n'  "$idx" "$value" ;;
      *)          printf '  %2d)  ❓ %-10s %s\n' "$idx" "$kind" "$value" ;;
    esac
  done < "$_SW_EXCLUDE_FILE"
  [ "$idx" -eq 0 ] && echo "  (no rules yet)"
}

# Add one rule interactively
_sw_excl_add() {
  _sw_excl_ensure
  echo "━━━ Add exclude rule ━━━"
  echo "  1) filename   — hide a filename everywhere"
  echo "  2) foldername — hide a folder name everywhere (universal)"
  echo "  3) filepath   — hide one exact file"
  echo "  4) dirpath    — hide an entire directory tree"
  printf "Type (1-4) or Enter to cancel: "
  local t_choice
  IFS= read -r t_choice
  local kind
  case "$t_choice" in
    1) kind="filename"   ;;
    2) kind="foldername" ;;
    3) kind="filepath"   ;;
    4) kind="dirpath"    ;;
    *) echo "Cancelled."; return 0 ;;
  esac
  printf "Value: "
  local value
  IFS= read -r value
  value="${value// /}"          # strip leading/trailing spaces
  [ -z "$value" ] && { echo "Cancelled — empty value."; return 0; }
  # For filepath/dirpath: resolve ~ and make absolute if path-like
  if [[ "$kind" == filepath || "$kind" == dirpath ]]; then
    value="${value/#\~/$HOME}"  # expand leading ~
  fi
  # Duplicate check
  if grep -qE "^\s*${kind}\s+${value}\s*$" "$_SW_EXCLUDE_FILE" 2>/dev/null; then
    echo "ℹ️  Rule already exists: $kind  $value"
    return 0
  fi
  printf '%s  %s\n' "$kind" "$value" >> "$_SW_EXCLUDE_FILE"
  echo "✅ Added: $kind  $value"
  echo "   (daemon picks it up automatically — no restart needed)"
}

# Remove rule(s) by number (shown via _sw_excl_list)
_sw_excl_remove() {
  _sw_excl_ensure
  _sw_excl_list
  local total
  total=$( grep -cv '^\s*#\|^\s*$' "$_SW_EXCLUDE_FILE" 2>/dev/null || echo 0 )
  [ "$total" -eq 0 ] && return 0
  printf "Remove rule number(s) (e.g. 1 or 1 3 5), or Enter to cancel: "
  local nums
  IFS= read -r nums
  [ -z "$nums" ] && { echo "Cancelled."; return 0; }
  # Build list of 1-based indices to delete (sorted descending so sed line
  # numbers stay stable as we delete)
  local sorted_nums
  sorted_nums=$(echo "$nums" | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -rn)
  if [ -z "$sorted_nums" ]; then echo "⚠️  No valid numbers."; return 0; fi
  # Map rule numbers → actual file line numbers
  local line_nums=()
  local idx=0 lineno=0 line
  while IFS= read -r line; do
    lineno=$(( lineno + 1 ))
    [[ "$line" =~ ^\s*# || -z "${line// }" ]] && continue
    idx=$(( idx + 1 ))
    for n in $sorted_nums; do
      [ "$n" -eq "$idx" ] && line_nums+=( "$lineno" )
    done
  done < "$_SW_EXCLUDE_FILE"
  if [ "${#line_nums[@]}" -eq 0 ]; then echo "⚠️  No matching rules."; return 0; fi
  # Delete lines from file (descending order keeps line numbers valid)
  local tmp
  tmp=$(mktemp)
  cp "$_SW_EXCLUDE_FILE" "$tmp"
  for ln in $(echo "${line_nums[@]}" | tr ' ' '\n' | sort -rn); do
    sed -i "${ln}d" "$_SW_EXCLUDE_FILE"
  done
  rm -f "$tmp"
  echo "🗑️  Removed ${#line_nums[@]} rule(s)."
}

# Open the config file in $EDITOR / nano / vi
_sw_excl_edit() {
  _sw_excl_ensure
  local ed="${EDITOR:-}"
  if [ -z "$ed" ]; then
    command -v nano &>/dev/null && ed="nano" || ed="vi"
  fi
  echo "📝 Opening $_SW_EXCLUDE_FILE in $ed"
  "$ed" "$_SW_EXCLUDE_FILE"
  echo "   (daemon reloads automatically on save)"
}

# Main exclude manager — called by 'xe' inside recents tab
_sw_excl_menu() {
  while true; do
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚫 RECENTS EXCLUDE LIST"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    _sw_excl_list
    echo
    echo "  a) Add rule    r) Remove rule"
    echo "  e) Edit file   q) Back to recents"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "Choice: "
    local xc
    IFS= read -r xc
    case "${xc,,}" in
      a)  _sw_excl_add    ;;
      r)  _sw_excl_remove ;;
      e)  _sw_excl_edit   ;;
      q|"") echo "↩️  Back to recents"; return 0 ;;
      *)  echo "⚠️  Invalid: $xc" ;;
    esac
  done
}

# ── Tab state ─────────────────────────────────────────────────────────────────
_sw_tab="bookmarks"   # bookmarks | recents
_sw_in_mode=0         # 1 while inside switch_menu — enables ←/→ sentinel
_sw_did_switch=false  # set true on successful path jump — changes q behaviour

# ── .swlink helpers ───────────────────────────────────────────────────────────

_swlink_read_target() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -m1 '^SWLINK_TARGET=' "$f" 2>/dev/null | cut -d'=' -f2-
}

_swlink_write() {
  local dest_dir="$1" target="$2" display_name="$3"
  _sw_ensure_store
  mkdir -p "$dest_dir" 2>/dev/null
  local sc_path="${dest_dir}/${display_name}.swlink" count=1
  while [ -e "$sc_path" ]; do
    sc_path="${dest_dir}/${display_name}${count}.swlink"
    count=$(( count + 1 ))
  done
  {
    printf 'SWLINK_TARGET=%s\n' "$target"
    printf 'SWLINK_NAME=%s\n'   "$display_name"
    printf 'SWLINK_CREATED=%s\n' "$(date +%s)"
  } > "$sc_path"
  printf '%s' "$sc_path"
}

# ── Bookmarks: add / remove ───────────────────────────────────────────────────

_sw_add_path() {
  local outer_path="$1" sw_cur_dir="$2"
  _sw_ensure_store
  local dup t
  while IFS= read -r -d '' dup; do
    t=$(_swlink_read_target "$dup")
    if [ "$t" = "$outer_path" ]; then
      echo "ℹ️  Already in switch: $outer_path"
      return 0
    fi
  done < <(find "$_SW_DIR" -name '*.swlink' -print0 2>/dev/null)
  local display_name
  display_name=$(basename "$outer_path")
  _swlink_write "$sw_cur_dir" "$outer_path" "$display_name" >/dev/null
  echo "✅ Added: $display_name  →  $outer_path"
}

_sw_remove_paths() {
  echo "🗑️  Select bookmark(s) to remove:"
  delete_items
}

# ── Recents: read daemon list ─────────────────────────────────────────────────

_sw_build_recents() {
  items=()
  if [ ! -f "$_SW_RECENTS_LIST" ]; then
    return
  fi
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && [ -f "$line" ] && items+=("$line")
  done < "$_SW_RECENTS_LIST"
}

# ── Tab cycle ─────────────────────────────────────────────────────────────────

_sw_tab_next() {
  case "$_sw_tab" in
    bookmarks) _sw_tab=recents ;;
    recents)   _sw_tab=bookmarks ;;
  esac
}

_sw_tab_prev() {
  case "$_sw_tab" in
    bookmarks) _sw_tab=recents ;;
    recents)   _sw_tab=bookmarks ;;
  esac
}

_sw_tab_label() {
  local bm="📌 Bookmarks" rc="🕐 Recents"
  case "$_sw_tab" in
    bookmarks) printf '[%s]   %s'  "$bm" "$rc" ;;
    recents)   printf ' %s  [%s]' "$bm" "$rc" ;;
  esac
}

# ── Headers / footers ─────────────────────────────────────────────────────────

_sw_menu_header() {
  echo
  printf '🔀 SWITCH  %s   ←/→ tabs\n' "$(_sw_tab_label)"
  local _loc
  case "$_sw_tab" in
    recents) _loc="(recently modified — read only)" ;;
    *)       _loc="$path${group_prefix:+ [group: ${group_prefix^^}*]}" ;;
  esac
  printf '📂 %s\n' "$_loc"
  if [ -n "$_filter_query" ]; then
    printf '🔍 filter: %s*  (%d/%d)\n' "${_filter_query^^}" "${#items[@]}" "${#_all_items[@]}"
  fi
}

_sw_menu_header_imaginary() {
  _sw_menu_header
  echo "$_imag_banner"
}

_sw_menu_footer_bookmarks() {
  printf '\na) Add current path   b) Remove   sw) Exit\nu) Up   t) Transfer   d) Delete   c) Create   f) Find\nr) Rename   s) Settings   x) Organise\nr<N>) File actions on item N\n'
  [ -n "$group_prefix" ] && printf 'back) Remove last prefix (%s*)\n' "${group_prefix^^}"
}

_sw_menu_footer_recents() {
  printf '\n[READ ONLY]   Select a file → open/edit/run/copy\nxe) Exclude list   clr) Clear list   sw) Exit switch mode\n'
}

_sw_set_viewport_for_tab() {
  local ftr
  case "$_sw_tab" in
    bookmarks) ftr=_sw_menu_footer_bookmarks ;;
    recents)   ftr=_sw_menu_footer_recents   ;;
  esac
  if $imaginary_mode; then
    _vp_mode="imaginary"
    _vp_header_fn=_sw_menu_header_imaginary
  else
    _vp_mode="items"
    _vp_header_fn=_sw_menu_header
  fi
  _vp_footer_fn="$ftr"
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
}

# ── Item builder per tab ──────────────────────────────────────────────────────

_sw_build_items_for_tab() {
  imaginary_mode=false
  _filter_query=""
  _all_items=()
  items=()
  _hl_index=0

  case "$_sw_tab" in

    recents)
      _sw_build_recents
      ;;

    bookmarks)
      local total
      total=$(count_items_in_path "$path")
      _has_group_view=false
      [ "${#group_view_levels[@]}" -gt 0 ] && _has_group_view=true

      if [ "$total" -gt "${index_mode_threshold:-200}" ] && ! $force_show; then
        imaginary_mode=true
        if [ -n "$group_prefix" ]; then
          local local_arr=()
          while IFS= read -r -d '' _f; do
            _bn="${_f##*/}"
            [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
            ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
            [[ "${_bn,,}" != "$group_prefix"* ]] && continue
            local_arr+=("$_f")
          done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
          local pfx_count="${#local_arr[@]}"
          if [ "$pfx_count" -le "${index_mode_threshold:-200}" ]; then
            imaginary_mode=false; items=("${local_arr[@]}")
            _collect_metadata; apply_sort
          else
            build_imaginary_groups "$path" "$group_prefix" "$pfx_count"
          fi
        else
          build_imaginary_groups "$path" "" "$total"
        fi
      elif [ "$total" -gt "${index_mode_threshold:-200}" ] && $force_show; then
        imaginary_mode=false
        build_items_with_meta "$path" "${group_prefix:-}"
        apply_sort
      fi

      if ! $imaginary_mode; then
        if [ ${#items[@]} -eq 0 ] && [ -n "$group_prefix" ]; then
          build_items_with_meta "$path" "$group_prefix"; apply_sort
        elif [ ${#items[@]} -eq 0 ]; then
          build_items_with_meta "$path" ""; apply_sort
        fi
      fi
      ;;
  esac
}

# ── Read-only guard ───────────────────────────────────────────────────────────

_sw_recents_blocked() {
  printf '⚠️  Read-only in Recents — use Bookmarks tab or fx (functions) for scripts\n'
}

# ── Bookmarks selection ───────────────────────────────────────────────────────
# Returns 1 when a switch should be performed (_sw_result_path set)

_sw_result_path=""

_sw_bookmarks_handle_selection() {
  local choice="$1"

  # r<N> — bypass .swlink intercept, call handle_file directly
  if [[ "$choice" =~ ^r([0-9]+)$ ]]; then
    local n="${BASH_REMATCH[1]}"
    $imaginary_mode && { echo "⚠️  Navigate into a group first, then use r<N>"; return 0; }
    if [ "$n" -ge 1 ] && [ "$n" -le "${#items[@]}" ]; then
      local t="${items[$((n-1))]}"
      [ -d "$t" ] && { path="$t"; group_prefix=""; force_show=false; return 0; }
      [ -f "$t" ] && handle_file "$t"
    else
      echo "⚠️  Invalid: $choice"
    fi
    return 0
  fi

  # imaginary mode
  if $imaginary_mode; then
    local matched=false ch=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"; matched=true
    elif [ ${#choice} -eq 1 ]; then
      for gc in "${imaginary_map[@]}"; do
        [[ "$gc" == "${choice^^}" || "$gc" == "$choice" ]] && { ch="$gc"; matched=true; break; }
      done
    fi
    if $matched; then
      if [ "$ch" = "#" ]; then
        imaginary_mode=false; items=()
        while IFS= read -r -d '' _f; do
          _bn="${_f##*/}"
          [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
          ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
          local _bn_lower="${_bn,,}"
          [ -n "$group_prefix" ] && [[ "$_bn_lower" != "$group_prefix"* ]] && continue
          local _next="${_bn_lower:${#group_prefix}:1}"
          case "$_next" in [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ') continue ;; esac
          items+=("$_f")
        done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
        _collect_metadata; apply_sort
      elif [[ "$ch" =~ ^[A-Z]$ ]]; then
        group_prefix="${group_prefix}${ch,,}"; force_show=false
      else
        group_prefix="${group_prefix}${ch}"; force_show=false
      fi
    else
      echo "⚠️  Invalid selection"
    fi
    return 0
  fi

  # flat mode
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local selected="${items[$((choice-1))]}" bn
    bn="${selected##*/}"
    [ -d "$selected" ] && { path="$selected"; group_prefix=""; force_show=false; return 0; }
    if [[ "$bn" == *.swlink ]]; then
      local sw_target
      sw_target=$(_swlink_read_target "$selected")
      [ -z "$sw_target" ]   && { echo "⚠️  Bookmark has no target"; return 0; }
      [ ! -d "$sw_target" ] && [ ! -f "$sw_target" ] && { echo "⚠️  Target gone: $sw_target"; return 0; }
      _sw_result_path="$sw_target"; return 1
    fi
    [ -f "$selected" ] && handle_file "$selected"
  else
    echo "⚠️  Invalid selection"
  fi
  return 0
}

# ── Recents selection ─────────────────────────────────────────────────────────

_sw_recents_handle_selection() {
  local choice="$1"
  [[ "$choice" =~ ^[0-9]+$ ]] || { echo "⚠️  Invalid"; return 0; }
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ] || { echo "⚠️  Out of range"; return 0; }
  handle_file "${items[$((choice-1))]}"
}

# ── In-place tab redraw ───────────────────────────────────────────────────────
# Rebuilds items + chrome, then repaints the existing terminal block.
# Does NOT scroll or emit a new block.

_sw_tab_redraw() {
  # Snapshot _blk_h NOW — before geometry changes with the new tab's chrome.
  # _vp_redraw_in_place recalculates _blk_h internally which causes drift when
  # header/footer line counts differ between tabs. We do the cursor-up ourselves
  # with the old value, then let _vp_render_fresh compute fresh geometry cleanly.
  local _old_blk_h="${_blk_h:-0}"

  # Switch path context to new tab
  case "$_sw_tab" in
    bookmarks) path="$_SW_DIR" ;;
    recents)   : ;;
  esac
  group_prefix=""
  force_show=false

  _sw_build_items_for_tab
  _sw_set_viewport_for_tab
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows

  # _read_choice terminated with a trailing `echo`, so the cursor currently
  # sits one row BELOW the block. To reach the top of the same block we must
  # move up the FULL old block height — not _old_blk_h - 1, which leaves a
  # one-line residual each switch and accumulates drift.
  local _up=$(( _old_blk_h ))
  local _rows; _rows=$(_term_rows)
  (( _up > _rows - 1 )) && _up=$(( _rows - 1 ))
  (( _up < 0 )) && _up=0
  (( _up > 0 )) && printf '\033[%dA' "$_up"
  printf '\r\033[J'
  # Emit WITHOUT input line: _read_choice prints it fresh each loop.
  # Calling _vp_render_fresh here adds an extra input-line print
  # causing +1 line drift per tab switch.
  _vp_build_chrome
  _vp_geometry
  _vp_ensure_visible "${_hl_index:-1}"
  _vp_emit
}

# ── Main entry point ──────────────────────────────────────────────────────────

switch_menu() {
  _sw_ensure_store

  local _sw_outer_path="$path"
  local _sw_saved_path="$path"
  local _sw_saved_prefix="$group_prefix"
  local _sw_saved_force="$force_show"

  _sw_tab="bookmarks"
  path="$_SW_DIR"
  group_prefix=""
  force_show=false
  _sw_in_mode=1
  # Execute / scripting → use fx (functions_menu) instead

  local _sw_choice _sw_rc

  shopt -s nullglob

  # ── First render ────────────────────────────────────────────────────────────
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  _sw_build_items_for_tab
  _sw_set_viewport_for_tab
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows
  _vp_render_fresh

  while true; do

    _read_choice
    _sw_choice="$choice"

    shopt -s nocasematch

    # ── Tab-switch sentinels ─────────────────────────────────────────────────
    case "$_sw_choice" in
      __sw_tab_right__)
        local _prev="$_sw_tab"; _sw_tab_next
        _sw_tab_redraw "$_prev"
        shopt -u nocasematch; continue
        ;;
      __sw_tab_left__)
        local _prev="$_sw_tab"; _sw_tab_prev
        _sw_tab_redraw "$_prev"
        shopt -u nocasematch; continue
        ;;
    esac

    # ── After any real action, do a full fresh render at top of loop ─────────
    local _sw_do_fresh=true

    case "$_sw_choice" in

      sw|SW)
        echo "↩️  Exiting switch mode"
        break
        ;;

      xe|XE)
        # Exclude list — accessible from either tab, most useful in recents
        _sw_excl_menu
        ;;

 clr|CLR)
        if [ "$_sw_tab" = "recents" ]; then
          printf 'Clear all recents? This only clears the list, not your files. [y/N] '
          local _clr_ans
          IFS= read -r _clr_ans
          if [[ "${_clr_ans,,}" == "y" ]]; then
            : > "$_SW_RECENTS_LIST"
            echo "✅ Recents list cleared."
          else
            echo "Cancelled."
          fi
        else
          _sw_recents_blocked
          _sw_do_fresh=false
        fi
        ;;
        
      q)
        path="$_sw_saved_path"
        _sw_in_mode=0
        exit 0
        ;;

      -h) open_help ;;

      u)
        if [ "$_sw_tab" = "recents" ]; then
          _sw_recents_blocked; _sw_do_fresh=false
        elif [ "$path" != "$_SW_DIR" ] && [ "$path" != "/" ]; then
          path=$(dirname "$path"); group_prefix=""; force_show=false
        else
          echo "↩️  At root — exiting switch mode"; break
        fi
        ;;

      back)
        if [ "$_sw_tab" = "recents" ]; then
          _sw_recents_blocked; _sw_do_fresh=false
        else
          [ -n "$group_prefix" ] && group_prefix="${group_prefix%?}" && force_show=false
        fi
        ;;

      forceshow)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_force_show
        ;;

      a|A)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || _sw_add_path "$_sw_outer_path" "$path"
        ;;

      b|B)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || _sw_remove_paths
        ;;

      c)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_create
        ;;

      d)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || delete_items
        ;;

      t)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || transfer_menu
        ;;

      x)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || organise_menu
        ;;

      r)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_rename
        ;;

      f)            find_menu ;;
      s)            settings_menu ;;

      cd)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || { cd "$path" && exec "$SHELL"; }
        ;;

      m)            map_directory ;;
      disk)         df -h ;;
      ram)          free -h ;;

      rf)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_refresh
        ;;

      d-)           handle_shortpath_dispatch ;;
      v-)           handle_shortpath_view ;;

      c-*|m-*|s-*)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_shortpath_stage "$_sw_choice"
        ;;

      _*)           _sw_do_fresh=false ;;   # filter: viewport handles it live

      *)
        case "$_sw_tab" in
          bookmarks)
            _sw_bookmarks_handle_selection "$_sw_choice"
            _sw_rc=$?
            if [ "$_sw_rc" -eq 1 ] && [ -n "$_sw_result_path" ]; then
              # Perform the switch
              group_prefix="$_sw_saved_prefix"
              force_show="$_sw_saved_force"
              local _sw_cd_target="$_sw_result_path"
              [ -f "$_sw_cd_target" ] && _sw_cd_target="$(dirname "$_sw_cd_target")"
              cd -- "$_sw_cd_target" 2>/dev/null || true
              path="$_sw_cd_target"
              _sw_did_switch=true
              _sw_result_path=""
              _sw_saved_path=""
              _sw_in_mode=0
              printf '🔀 → %s\n' "$_sw_cd_target"
              return 0
            fi
            ;;
          recents)
            _sw_recents_handle_selection "$_sw_choice"
            ;;
        esac
        ;;
    esac

    shopt -u nocasematch

    # ── Re-render after action ───────────────────────────────────────────────
    if $_sw_do_fresh; then
      declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
      _sw_build_items_for_tab
      _sw_set_viewport_for_tab
      _vp_start=1
      _vp_cache_reset
      _vp_prime_rows
      _vp_render_fresh
    fi

  done

  shopt -u nocasematch
  _sw_in_mode=0

  if [ -n "$_sw_saved_path" ]; then
    path="$_sw_saved_path"
    group_prefix="$_sw_saved_prefix"
    force_show="$_sw_saved_force"
  fi
}