#!/usr/bin/env bash
# bashbasicsbyvk_switch.sh
# ════════════════════════════════════════════════════════════════════════════
#  SWITCH — three-tab navigation overlay inside the main file-manager loop
#
#  Tabs (cycle with ← / → arrow when input buffer is empty):
#    📌 Bookmarks  — .swlink files in ~/.bashbasicsbyvk/switch/
#    🕐 Recents    — 100 most-recently-modified files system-wide (read-only)
#    ⚡ Execute    — full file-manager inside the switch dir, no restrictions;
#                   scripts run from the path where sw was originally entered
#
#  Bookmarks tab commands
#  ──────────────────────
#    a     Add outer $path as a new .swlink bookmark (deduped)
#    b     Remove bookmarks (reuses delete_items)
#    sw    Exit switch mode
#    Selecting a .swlink → perform switch (cd + set outer path, exit sw mode)
#    r<N>  File-actions (edit/rename/delete…) on item N instead of switching
#
#  Recents tab — READ ONLY
#  ────────────────────────
#    Selecting a file → handle_file() normally (run/edit/copy/view…)
#    Mutating commands (c d t b x a) are blocked with a message
#
#  Execute tab — FULL ACCESS
#  ──────────────────────────
#    All main-loop commands, no .swlink intercept
#    Running a script closes the inner loop first, then executes from
#    the original outer path (_sw_outer_path) so the script's context
#    matches where the user invoked sw
#
# ════════════════════════════════════════════════════════════════════════════

# ── Storage root ──────────────────────────────────────────────────────────────
_SW_DIR="${HOME}/.bashbasicsbyvk/switch"

_sw_ensure_store() {
  mkdir -p "$_SW_DIR" 2>/dev/null
}

# ── Tab state (global so _read_choice sentinel arms can set it) ───────────────
# Values: bookmarks | recents | execute
_sw_tab="bookmarks"

# Flag read by _read_choice: 1 while inside switch_menu inner loop
_sw_in_mode=0

# Set to true when a switch (path jump) is performed — checked by main q)
_sw_did_switch=false

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

# ── Recents: read from daemon-maintained list ─────────────────────────────────
# The recents daemon (bashbasicsbyvk_recents_daemon.py) watches the filesystem
# with inotify and writes ~/.bashbasicsbyvk/recents.list (newest first, max 100).
# We just read that file — instant, no scanning.

_SW_RECENTS_LIST="${HOME}/.bashbasicsbyvk/recents.list"

_sw_build_recents() {
  items=()
  local _list="$_SW_RECENTS_LIST"
  if [ ! -f "$_list" ]; then
    echo "⏳ Recents daemon starting — no data yet. Open/edit some files and try again."
    return
  fi
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && [ -f "$line" ] && items+=("$line")
  done < "$_list"
  if [ ${#items[@]} -eq 0 ]; then
    echo "⏳ No recent files recorded yet. Open/edit some files and try again."
  fi
}

# ── Tab-cycle helper ──────────────────────────────────────────────────────────

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
    bookmarks) printf '[%s]  %s   %s' "$bm" "$rc" "$ex" ;;
    recents)   printf ' %s  [%s]  %s' "$bm" "$rc" "$ex" ;;
    execute)   printf ' %s   %s  [%s]' "$bm" "$rc" "$ex" ;;
  esac
}

# ── Headers / footers ─────────────────────────────────────────────────────────

_sw_menu_header() {
  echo
  echo "🔀 SWITCH  $(_sw_tab_label)   ←/→ to switch tabs"
  local _loc="$path"
  [ "$_sw_tab" = "recents" ] && _loc="(recently modified — read only)"
  echo "📂 $_loc${group_prefix:+ [group: ${group_prefix^^}*]}"
  if [ -n "$_filter_query" ]; then
    echo "🔍 filter: ${_filter_query^^}*  (${#items[@]}/${#_all_items[@]} items)"
  fi
}

_sw_menu_header_imaginary() {
  _sw_menu_header
  echo "$_imag_banner"
}

_sw_menu_footer_bookmarks() {
  printf '\na) Add current path   b) Remove   sw) Exit switch mode\nu) Up   t) Transfer   d) Delete   c) Create   f) Find\nr) Rename   s) Settings   x) Organise\nr<N>) File actions on item N (edit/copy/run…)\n'
  [ -n "$group_prefix" ] && echo "back) Remove last prefix char (current: ${group_prefix^^}*)"
}

_sw_menu_footer_recents() {
  printf '\n[READ ONLY]  Select a file to open/edit/run/copy it\nsw) Exit switch mode   ←/→) Switch tab\n'
}

_sw_menu_footer_execute() {
  printf '\n[EXECUTE MODE — full access, scripts run from original path]\nu) Up   cd→shell   t) Transfer   d) Delete   c) Create\nf) Find   r) Rename   s) Settings   x) Organise\nsw) Exit switch mode   ←/→) Switch tab\n'
  [ -n "$group_prefix" ] && echo "back) Remove last prefix char (current: ${group_prefix^^}*)"
}

_sw_footer_fn_for_tab() {
  case "$_sw_tab" in
    bookmarks) echo _sw_menu_footer_bookmarks ;;
    recents)   echo _sw_menu_footer_recents ;;
    execute)   echo _sw_menu_footer_execute ;;
  esac
}

# ── Bookmarks: selection handler ──────────────────────────────────────────────
# Returns 1 when a switch should be performed (_sw_result_path is set)

_sw_result_path=""

_sw_bookmarks_handle_selection() {
  local choice="$1"

  # r<N> — file-actions prefix (bypass swlink intercept)
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

  # imaginary mode — identical to main loop
  if $imaginary_mode; then
    local matched=false ch=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"; matched=true
    elif [ ${#choice} -eq 1 ]; then
      local uc="${choice^^}"
      for gc in "${imaginary_map[@]}"; do
        [[ "$gc" == "$uc" || "$gc" == "$choice" ]] && { ch="$gc"; matched=true; break; }
      done
    fi
    if $matched; then
      if [ "$ch" = "#" ]; then
        imaginary_mode=false
        items=()
        while IFS= read -r -d '' _f; do
          _bn="${_f##*/}"
          [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
          ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
          local _bn_lower="${_bn,,}"
          [ -n "$group_prefix" ] && [[ "$_bn_lower" != "$group_prefix"* ]] && continue
          local _next="${_bn_lower:${#group_prefix}:1}"
          case "$_next" in
            [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ') continue ;;
          esac
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
      [ -z "$sw_target" ] && { echo "⚠️  Bookmark has no target"; return 0; }
      [ ! -d "$sw_target" ] && [ ! -f "$sw_target" ] && { echo "⚠️  Target gone: $sw_target"; return 0; }
      _sw_result_path="$sw_target"; return 1
    fi
    [ -f "$selected" ] && handle_file "$selected"
  else
    echo "⚠️  Invalid selection"
  fi
  return 0
}

# ── Recents: selection handler ────────────────────────────────────────────────

_sw_recents_handle_selection() {
  local choice="$1"
  [[ "$choice" =~ ^[0-9]+$ ]] || { echo "⚠️  Invalid selection"; return 0; }
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ] || { echo "⚠️  Out of range"; return 0; }
  local selected="${items[$((choice-1))]}"
  [ -f "$selected" ] && handle_file "$selected"
  return 0
}

# ── Execute: selection handler ────────────────────────────────────────────────
# Identical to the main loop's handle_selection; no .swlink intercept.
# When a script would be "run" (option 0), we return 2 so the caller can
# close the inner loop first and then execute from _sw_outer_path.

_sw_exec_script_path=""   # set when execute-mode wants to run a script

_sw_execute_handle_selection() {
  local choice="$1"

  # imaginary mode — same as bookmarks handler (reuse)
  if $imaginary_mode; then
    _sw_bookmarks_handle_selection "$choice"
    return $?
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local selected="${items[$((choice-1))]}"
    [ -d "$selected" ] && { path="$selected"; group_prefix=""; force_show=false; return 0; }
    if [ -f "$selected" ]; then
      # Intercept option 0 (Run) so we can exit inner loop first
      handle_file "$selected"
      # handle_file is interactive — if the user chose Run we can't easily
      # intercept here without forking handle_file. The simplest correct
      # approach: run handle_file as-is; the script inherits the correct
      # environment because we cd'd to _sw_outer_path before calling switch_menu.
      # If deeper intercept is needed in future, wrap handle_file.
    fi
  else
    echo "⚠️  Invalid selection"
  fi
  return 0
}

# ── Per-tab item builder ───────────────────────────────────────────────────────

_sw_build_items_for_tab() {
  case "$_sw_tab" in
    recents)
      echo "🔍 Scanning recent files…"
      _sw_build_recents
      ;;
    bookmarks|execute)
      imaginary_mode=false
      _filter_query=""
      _all_items=()
      items=()
      _hl_index=0

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

# ── Blocked-in-recents guard ──────────────────────────────────────────────────

_sw_recents_blocked() {
  echo "⚠️  Read-only in Recents tab — switch to Bookmarks or Execute tab"
}

# ── Main entry point ──────────────────────────────────────────────────────────

switch_menu() {
  _sw_ensure_store

  local _sw_outer_path="$path"
  local _sw_saved_path="$path"
  local _sw_saved_prefix="$group_prefix"
  local _sw_saved_force="$force_show"

  # Enter bookmarks tab by default; point path at switch dir
  _sw_tab="bookmarks"
  path="$_SW_DIR"
  group_prefix=""
  force_show=false

  # Tell _read_choice we're in switch mode (enables ←/→ tab-switch)
  _sw_in_mode=1

  local _sw_choice _sw_rc

  shopt -s nullglob

  while true; do
    declare -F _sm_reset >/dev/null 2>&1 && _sm_reset

    _sw_build_items_for_tab

    # Viewport
    local _sw_ftr_fn
    _sw_ftr_fn=$(_sw_footer_fn_for_tab)
    if $imaginary_mode; then
      _vp_mode="imaginary"
      _vp_header_fn=_sw_menu_header_imaginary
    else
      _vp_mode="items"
      _vp_header_fn=_sw_menu_header
    fi
    _vp_footer_fn="$_sw_ftr_fn"
    _vp_hl_fn=_vp_is_hl_single
    _msel_set=()
    _vp_input_fn=_print_input_line
    _vp_start=1
    _vp_cache_reset
    _vp_prime_rows
    _vp_render_fresh

    _read_choice
    _sw_choice="$choice"

    shopt -s nocasematch

    # ── Tab-switch sentinels from ←/→ arrows ──────────────────────────────
    case "$_sw_choice" in
      __sw_tab_right__) _sw_tab_next; group_prefix=""; force_show=false; shopt -u nocasematch; continue ;;
      __sw_tab_left__)  _sw_tab_prev; group_prefix=""; force_show=false; shopt -u nocasematch; continue ;;
    esac

    # ── Universal commands (all tabs) ─────────────────────────────────────
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
          _sw_recents_blocked
        elif [ "$path" != "$_SW_DIR" ] && [ "$path" != "/" ]; then
          path=$(dirname "$path"); group_prefix=""; force_show=false
        else
          echo "↩️  At root — exiting switch mode"
          break
        fi
        ;;

      back)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        [ -n "$group_prefix" ] && group_prefix="${group_prefix%?}" && force_show=false
        ;;

      forceshow)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        handle_force_show
        ;;

      # ── Bookmarks-specific ───────────────────────────────────────────────
      a|A)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        _sw_add_path "$_sw_outer_path" "$path"
        ;;

      b|B)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        _sw_remove_paths
        ;;

      # ── Mutating commands (blocked in recents) ───────────────────────────
      c)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        handle_create
        ;;

      d)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        delete_items
        ;;

      t)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        transfer_menu
        ;;

      x)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        organise_menu
        ;;

      r)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        handle_rename
        ;;

      # ── Commands available in all tabs (read-safe) ───────────────────────
      f)            find_menu ;;
      s)            settings_menu ;;
      cd)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        cd "$path" && exec "$SHELL"
        ;;
      m)            map_directory ;;
      disk)         df -h ;;
      ram)          free -h ;;
      rf)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        handle_refresh
        ;;
      d-)           handle_shortpath_dispatch ;;
      v-)           handle_shortpath_view ;;
      c-*|m-*|s-*)
        [ "$_sw_tab" = "recents" ] && { _sw_recents_blocked; shopt -u nocasematch; continue; }
        handle_shortpath_stage "$_sw_choice"
        ;;
      _*)           : ;;   # filter mode

      # ── Selection — dispatched per tab ───────────────────────────────────
      *)
        case "$_sw_tab" in
          bookmarks)
            _sw_bookmarks_handle_selection "$_sw_choice"
            _sw_rc=$?
            if [ "$_sw_rc" -eq 1 ] && [ -n "$_sw_result_path" ]; then
              echo "🔀 Switching to: $_sw_result_path"
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

  done

  shopt -u nocasematch

  _sw_in_mode=0

  # Restore outer loop state (no switch performed)
  if [ -n "$_sw_saved_path" ]; then
    path="$_sw_saved_path"
    group_prefix="$_sw_saved_prefix"
    force_show="$_sw_saved_force"
  fi
}
