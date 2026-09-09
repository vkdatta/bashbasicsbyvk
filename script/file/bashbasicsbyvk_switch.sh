#!/usr/bin/env bash
# bashbasicsbyvk_switch.sh
# ════════════════════════════════════════════════════════════════════════════
#  SWITCH — persistent navigation bookmarks for the main file-manager loop
#
#  Storage (parallel to the shortpath buffer):
#    ~/.bashbasicsbyvk/switch/          ← root switch directory
#
#  A "switch entry" is a plain file with the extension .swlink whose content
#  follows the same key=value format as .shortcut files:
#    SWLINK_TARGET=<absolute path>
#    SWLINK_NAME=<display name>
#    SWLINK_CREATED=<epoch>
#
#  Users may freely create sub-folders inside the switch dir to group their
#  bookmarks — every command available in the main loop works identically
#  inside switch mode (navigate, create, rename, delete, transfer, find …).
#
#  Unique switch-mode commands
#  ───────────────────────────
#    a     Add current outer $path as a new bookmark
#    b     Remove one or more bookmarks (reuses delete_items / select_items)
#    sw    Exit switch mode (same key that opened it)
#
#  Selecting a .swlink file (Enter / arrow)
#  ─────────────────────────────────────────
#    • Plain selection  → perform the switch: outer $path ← swlink target,
#                         then exit switch mode
#    • r<N> selection   → treat the .swlink like any normal file: call
#                         handle_file() on it (edit, rename, delete …)
#
# ════════════════════════════════════════════════════════════════════════════

# ── Switch storage root ───────────────────────────────────────────────────────
_SW_DIR="${HOME}/.bashbasicsbyvk/switch"

_sw_ensure_store() {
  mkdir -p "$_SW_DIR" 2>/dev/null
}

# ── Low-level .swlink helpers ─────────────────────────────────────────────────

_swlink_read_target() {
  local f="$1"
  [ -f "$f" ] || return 1
  grep -m1 '^SWLINK_TARGET=' "$f" 2>/dev/null | cut -d'=' -f2-
}

# Write a new .swlink file.  Returns the created path on stdout.
_swlink_write() {
  local dest_dir="$1"
  local target="$2"
  local display_name="$3"

  _sw_ensure_store
  mkdir -p "$dest_dir" 2>/dev/null

  local base="${display_name}.swlink"
  local sc_path="${dest_dir}/${base}"
  local count=1
  while [ -e "$sc_path" ]; do
    sc_path="${dest_dir}/${display_name}${count}.swlink"
    count=$((count+1))
  done

  {
    printf 'SWLINK_TARGET=%s\n' "$target"
    printf 'SWLINK_NAME=%s\n'   "$display_name"
    printf 'SWLINK_CREATED=%s\n' "$(date +%s)"
  } > "$sc_path"

  printf '%s' "$sc_path"
}

# ── Command: add current outer path ──────────────────────────────────────────
# Called with the outer path as $1 and the current sw-mode display dir as $2.
_sw_add_path() {
  local outer_path="$1"
  local sw_cur_dir="$2"

  _sw_ensure_store

  # Check for a duplicate anywhere under the switch root
  local dup
  while IFS= read -r -d '' dup; do
    local t
    t=$(_swlink_read_target "$dup")
    if [ "$t" = "$outer_path" ]; then
      echo "ℹ️  Already in switch: $outer_path"
      return 0
    fi
  done < <(find "$_SW_DIR" -name '*.swlink' -print0 2>/dev/null)

  local display_name
  display_name=$(basename "$outer_path")

  local created
  created=$(_swlink_write "$sw_cur_dir" "$outer_path" "$display_name")
  echo "✅ Added to switch: $display_name  →  $outer_path"
}

# ── Command: remove bookmarks (reuses delete_items) ──────────────────────────
# Just an alias with a friendly message — delete_items already handles
# multi-select and confirmation.
_sw_remove_paths() {
  echo "🗑️  Select bookmark(s) to remove:"
  delete_items
}

# ── Switch-mode handle_selection ─────────────────────────────────────────────
# Mirror of handle_selection in script/o but with two differences:
#   1. .swlink files perform the switch instead of calling handle_file
#   2. the outer path is updated via the _sw_result_path nameref
#
# Returns:
#   0   keep looping in switch mode
#   1   perform switch   → caller sets outer $path = _sw_result_path and exits
#   2   r-prefixed file  → handle_file was called; keep looping

_sw_result_path=""    # set when return-code is 1

_sw_handle_selection() {
  local choice="$1"

  # ── r-prefix: treat the selected item as a normal file (0-9 actions) ──────
  if [[ "$choice" =~ ^r([0-9]+)$ ]]; then
    local inner_n="${BASH_REMATCH[1]}"
    if $imaginary_mode; then
      echo "⚠️  Navigate into a group first, then use r<N>"
      return 0
    fi
    if [[ "$inner_n" =~ ^[0-9]+$ ]] && [ "$inner_n" -ge 1 ] && [ "$inner_n" -le "${#items[@]}" ]; then
      local target_item="${items[$((inner_n-1))]}"
      if [ -d "$target_item" ]; then
        path="$target_item"
        group_prefix=""
        force_show=false
      elif [ -f "$target_item" ]; then
        handle_file "$target_item"
      fi
    else
      echo "⚠️  Invalid selection: $choice"
    fi
    return 0
  fi

  # ── imaginary (grouped) mode — identical to main loop ────────────────────
  if $imaginary_mode; then
    local matched=false ch=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"
      matched=true
    elif [[ ${#choice} -eq 1 ]]; then
      local uc="${choice^^}"
      for gc in "${imaginary_map[@]}"; do
        if [[ "$gc" == "$uc" ]] || [[ "$gc" == "$choice" ]]; then
          ch="$gc"; matched=true; break
        fi
      done
    fi

    if $matched; then
      if [ "$ch" == "#" ]; then
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
        group_prefix="${group_prefix}${ch,,}"
        force_show=false
      else
        group_prefix="${group_prefix}${ch}"
        force_show=false
      fi
    else
      echo "⚠️  Invalid selection"
    fi
    return 0
  fi

  # ── flat mode ──────────────────────────────────────────────────────────────
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local selected="${items[$((choice-1))]}"
    local bn="${selected##*/}"

    if [ -d "$selected" ]; then
      path="$selected"
      group_prefix=""
      force_show=false
      return 0
    fi

    if [[ "$bn" == *.swlink ]]; then
      local sw_target
      sw_target=$(_swlink_read_target "$selected")
      if [ -z "$sw_target" ]; then
        echo "⚠️  Bookmark has no target recorded"
        return 0
      fi
      if [ ! -d "$sw_target" ] && [ ! -f "$sw_target" ]; then
        echo "⚠️  Bookmark target no longer exists: $sw_target"
        return 0
      fi
      _sw_result_path="$sw_target"
      return 1   # signal: perform the switch
    fi

    # Regular file inside switch dir
    if [ -f "$selected" ]; then
      handle_file "$selected"
    fi
  else
    echo "⚠️  Invalid selection"
  fi
  return 0
}

# ── Switch-mode header / footer ───────────────────────────────────────────────

_sw_menu_header() {
  echo
  local _hdr="🔀 SWITCH MODE  |  📂 $path${group_prefix:+ [group: ${group_prefix^^}*]}"
  if [ -n "$_filter_query" ]; then
    local _fcnt="${#items[@]}" _tcnt="${#_all_items[@]}"
    _hdr+="  🔍 filter: ${_filter_query^^}*  (${_fcnt}/${_tcnt} items)"
  fi
  echo "$_hdr"
}

_sw_menu_header_imaginary() {
  _sw_menu_header
  echo "$_imag_banner"
}

_sw_menu_footer_lines() {
  builtin printf "\na) Add current path   b) Remove bookmarks   sw) Exit switch mode\nu) Up   cd→shell   t) Transfer   d) Delete   c) Create\nf) Find   r) Rename   s) Settings   x) Organise\nr<N>) File actions on item N (edit/copy/run…)\n"
  [ -n "$group_prefix" ] && echo "back) Remove last prefix char (current: ${group_prefix^^}*)"
}

# ── Main switch_menu entry point ──────────────────────────────────────────────
# Called from the main loop as:   sw) switch_menu ;;
# The outer loop's $path variable is updated in-place on a successful switch.

switch_menu() {
  _sw_ensure_store

  # Snapshot the outer path before entering switch mode
  local _sw_outer_path="$path"

  # Save outer loop state that we will shadow while in switch mode
  local _sw_saved_path="$path"
  local _sw_saved_prefix="$group_prefix"
  local _sw_saved_force="$force_show"

  # Point the running variables at the switch dir
  path="$_SW_DIR"
  group_prefix=""
  force_show=false

  local _sw_choice _sw_rc

  shopt -s nullglob

  while true; do
    declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
    total=$(count_items_in_path "$path")

    imaginary_mode=false
    _filter_query=""
    _all_items=()
    items=()
    _hl_index=0

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
          imaginary_mode=false
          items=("${local_arr[@]}")
          _collect_metadata; apply_sort
        else
          build_imaginary_groups "$path" "$group_prefix" "$pfx_count"
        fi
      else
        build_imaginary_groups "$path" "" "$total"
      fi
    elif [ "$total" -gt "${index_mode_threshold:-200}" ] && $force_show; then
      imaginary_mode=false
      if [ -n "$group_prefix" ]; then
        build_items_with_meta "$path" "$group_prefix"
      else
        build_items_with_meta "$path" ""
      fi
      apply_sort
    fi

    if ! $imaginary_mode; then
      if [ ${#items[@]} -eq 0 ] && [ -n "$group_prefix" ]; then
        build_items_with_meta "$path" "$group_prefix"; apply_sort
      elif [ ${#items[@]} -eq 0 ]; then
        build_items_with_meta "$path" ""; apply_sort
      fi
    fi

    # Viewport setup — same pattern as main loop
    if $imaginary_mode; then
      _vp_mode="imaginary"
      _vp_header_fn=_sw_menu_header_imaginary
    else
      _vp_mode="items"
      _vp_header_fn=_sw_menu_header
    fi
    _vp_footer_fn=_sw_menu_footer_lines
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

    case "$_sw_choice" in

      # ── Exit switch mode ────────────────────────────────────────────────────
      sw|SW)
        echo "↩️  Exiting switch mode"
        break
        ;;

      # ── Add current (outer) path to switch ─────────────────────────────────
      a|A)
        _sw_add_path "$_sw_outer_path" "$path"
        ;;

      # ── Remove bookmarks ────────────────────────────────────────────────────
      b|B)
        _sw_remove_paths
        ;;

      # ── Commands mirrored from the main loop ────────────────────────────────
      q)              # quit entirely (not just switch mode)
        # Restore outer path first so we don't leak a stale $path
        path="$_sw_saved_path"
        exit 0
        ;;
      -h)             open_help ;;
      u)
        if [ "$path" != "$_SW_DIR" ] && [ "$path" != "/" ]; then
          path=$(dirname "$path"); group_prefix=""; force_show=false
        elif [ "$path" = "$_SW_DIR" ]; then
          # Already at switch root — go up to outer path's parent, exit sw mode
          echo "↩️  At switch root — exiting switch mode"
          break
        fi
        ;;
      back)
        [ -n "$group_prefix" ] && group_prefix="${group_prefix%?}" && force_show=false
        ;;
      forceshow)    handle_force_show ;;
      c)            handle_create ;;
      t)            transfer_menu ;;
      d)            delete_items ;;
      f)            find_menu ;;
      x)            organise_menu ;;
      s)            settings_menu ;;
      r)
        # Plain 'r' without a number = rename (same as main loop)
        handle_rename
        ;;
      cd)           cd "$path" && exec "$SHELL" ;;
      m)            map_directory ;;
      disk)         df -h ;;
      ram)          free -h ;;
      rf)           handle_refresh ;;
      d-)           handle_shortpath_dispatch ;;
      v-)           handle_shortpath_view ;;
      c-*|m-*|s-*)  handle_shortpath_stage "$_sw_choice" ;;
      _*)           : ;;   # filter mode — handled by _read_choice / viewport
      *)
        # Numeric selection (item enter) or r<N> (file-actions prefix)
        _sw_handle_selection "$_sw_choice"
        _sw_rc=$?
        if [ "$_sw_rc" -eq 1 ]; then
          # A .swlink was selected — perform the switch
          if [ -n "$_sw_result_path" ]; then
            echo "🔀 Switching to: $_sw_result_path"
            # Restore outer state except path — path gets the new destination
            group_prefix="$_sw_saved_prefix"
            force_show="$_sw_saved_force"
            path="$_sw_result_path"
            _sw_result_path=""
            # Clear saved so the outer loop just uses the new path
            _sw_saved_path=""
          fi
          return 0  # return to main loop immediately after switch
        fi
        ;;
    esac

    shopt -u nocasematch

  done

  shopt -u nocasematch

  # Restore outer loop state (no switch performed)
  path="$_sw_saved_path"
  group_prefix="$_sw_saved_prefix"
  force_show="$_sw_saved_force"
}
