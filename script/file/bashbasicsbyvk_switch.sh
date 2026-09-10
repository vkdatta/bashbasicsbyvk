#!/usr/bin/env bash
# bashbasicsbyvk_switch.sh
# ════════════════════════════════════════════════════════════════════════════
#  SWITCH — three-tab overlay inside the main file-manager loop
#
#  Tabs (← / → to cycle when input is empty):
#    📌 Bookmarks  ~/.bashbasicsbyvk/switch/   — .swlink bookmark files
#    🕐 Recents    ~/.bashbasicsbyvk/recents.list — daemon-maintained, read-only
#    ⚡ Execute    ~/.bashbasicsbyvk/execute/   — user scripts, full access
#
#  Tab switch is in-place: the block redraws inside the existing terminal
#  block — no scroll, no new container.
# ════════════════════════════════════════════════════════════════════════════

# ── Storage roots ─────────────────────────────────────────────────────────────
_SW_DIR="${HOME}/.bashbasicsbyvk/switch"
_SW_EXEC_DIR="${HOME}/.bashbasicsbyvk/execute"
_SW_RECENTS_LIST="${HOME}/.bashbasicsbyvk/recents.list"

_sw_ensure_store() {
  mkdir -p "$_SW_DIR" "$_SW_EXEC_DIR" 2>/dev/null
}

# ── Tab state ─────────────────────────────────────────────────────────────────
_sw_tab="bookmarks"   # bookmarks | recents | execute
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
    recents)   _sw_tab=execute ;;
    execute)   _sw_tab=bookmarks ;;
  esac
}

_sw_tab_prev() {
  case "$_sw_tab" in
    bookmarks) _sw_tab=execute ;;
    recents)   _sw_tab=bookmarks ;;
    execute)   _sw_tab=recents ;;
  esac
}

_sw_tab_label() {
  local bm="📌 Bookmarks" rc="🕐 Recents" ex="⚡ Execute"
  case "$_sw_tab" in
    bookmarks) printf '[%s]   %s    %s'  "$bm" "$rc" "$ex" ;;
    recents)   printf ' %s  [%s]   %s'  "$bm" "$rc" "$ex" ;;
    execute)   printf ' %s   %s   [%s]' "$bm" "$rc" "$ex" ;;
  esac
}

# ── Headers / footers ─────────────────────────────────────────────────────────

_sw_menu_header() {
  echo
  printf '🔀 SWITCH  %s   ←/→ tabs\n' "$(_sw_tab_label)"
  local _loc
  case "$_sw_tab" in
    recents)   _loc="(recently modified — read only)" ;;
    *)         _loc="$path${group_prefix:+ [group: ${group_prefix^^}*]}" ;;
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
  printf '\n[READ ONLY]   Select a file → open/edit/run/copy\nsw) Exit switch mode\n'
}

_sw_menu_footer_execute() {
  printf '\n[EXECUTE]  All commands available — scripts run from launch path\nu) Up   t) Transfer   d) Delete   c) Create   f) Find\nr) Rename   s) Settings   x) Organise   sw) Exit\n'
  [ -n "$group_prefix" ] && printf 'back) Remove last prefix (%s*)\n' "${group_prefix^^}"
}

_sw_set_viewport_for_tab() {
  local ftr
  case "$_sw_tab" in
    bookmarks) ftr=_sw_menu_footer_bookmarks ;;
    recents)   ftr=_sw_menu_footer_recents   ;;
    execute)   ftr=_sw_menu_footer_execute   ;;
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

    bookmarks|execute)
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
  printf '⚠️  Read-only in Recents — use Bookmarks or Execute tab\n'
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

# ── Execute selection — plain file-manager, no .swlink intercept ──────────────

_sw_execute_handle_selection() {
  local choice="$1"

  if $imaginary_mode; then
    _sw_bookmarks_handle_selection "$choice"   # imaginary logic is identical
    return $?
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local selected="${items[$((choice-1))]}"
    [ -d "$selected" ] && { path="$selected"; group_prefix=""; force_show=false; return 0; }
    [ -f "$selected" ] && handle_file "$selected"
  else
    echo "⚠️  Invalid selection"
  fi
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
    execute)   path="$_SW_EXEC_DIR" ;;
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
  (( _up > 0 )) && builtin printf '\033[%dA' "$_up"
  builtin printf '\r\033[J'
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

      q)
        path="$_sw_saved_path"
        _sw_in_mode=0
        exit 0
        ;;

      -h) open_help ;;

      u)
        if [ "$_sw_tab" = "recents" ]; then
          _sw_recents_blocked; _sw_do_fresh=false
        elif [ "$path" != "$_SW_DIR" ] && [ "$path" != "$_SW_EXEC_DIR" ] && [ "$path" != "/" ]; then
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
          execute)
            _sw_execute_handle_selection "$_sw_choice"
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