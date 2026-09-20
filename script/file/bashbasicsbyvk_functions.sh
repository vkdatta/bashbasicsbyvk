#!/usr/bin/env bash
# bashbasicsbyvk_functions.sh
# ════════════════════════════════════════════════════════════════════════════
#  FUNCTIONS (fx) — two-tab overlay inside the main file-manager loop
#
#  Tabs (← / → to cycle when input is empty):
#    🛠️  ADF  Admin-Defined Functions  — built-in power tools
#    👤  UDF  User-Defined Functions   — ~/.bashbasicsbyvk/execute/  scripts
#
#  All functions execute in the CURRENT path ($path) unless a function
#  internally defines its own target path.
#
#  Tab switch is in-place: the block redraws inside the existing terminal
#  block — no scroll, no new container.
# ════════════════════════════════════════════════════════════════════════════

# ── Storage root (UDF scripts live here) ──────────────────────────────────────
_FX_EXEC_DIR="${HOME}/.bashbasicsbyvk/execute"

_fx_ensure_store() {
  mkdir -p "$_FX_EXEC_DIR" 2>/dev/null
}

# ── Tab state ─────────────────────────────────────────────────────────────────
_fx_tab="adf"      # adf | udf
_fx_in_mode=0      # 1 while inside functions_menu — enables ←/→ sentinel

# ── ADF registry ─────────────────────────────────────────────────────────────
#  Each entry: parallel arrays _fx_adf_labels[] and _fx_adf_fns[]
#  Add new admin-defined functions by appending _fx_adf_register calls below.

_fx_adf_labels=()
_fx_adf_fns=()

_fx_adf_register() {
  # Usage: _fx_adf_register "Display Label" function_name
  _fx_adf_labels+=("$1")
  _fx_adf_fns+=("$2")
}

# ════════════════════════════════════════════════════════════════════════════
#  ADF 1 — rename.select.items.csv
#  CSV batch rename: col1=old_name, col2=new_name, result written to col3.
#  Identical to the old "Multi Mutation (CSV)" rename path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_rename_csv() {
  _rename_multi_mutation
}
_fx_adf_register "rename.select.items.csv" "_fx_adf_rename_csv"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 2 — move.select.items
#  Pick items interactively via viewport multi-picker, stage into move buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_move_select() {
  select_items_common "MOVE" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_MV_ONCE_FILE" "$item"
    echo "📌 Staged for move: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "move.select.items" "_fx_adf_move_select"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 3 — move.select.items.csv
#  CSV-driven move: col1 = filename or absolute path to stage into move buffer.
#  Result column written back to col2 of the CSV.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_move_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_MV_ONCE_FILE" "$item"
    echo "📌 Staged for move: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "move.select.items.csv" "_fx_adf_move_select_csv"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 4 — copy.select.items
#  Pick items interactively, stage into copy buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_copy_select() {
  select_items_common "COPY" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_CP_ONCE_FILE" "$item"
    echo "📌 Staged for copy: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "copy.select.items" "_fx_adf_copy_select"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 5 — copy.select.items.csv
#  CSV-driven copy: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_copy_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_CP_ONCE_FILE" "$item"
    echo "📌 Staged for copy: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "copy.select.items.csv" "_fx_adf_copy_select_csv"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 6 — shortcut.select.items
#  Pick items interactively, stage into shortcut buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_shortcut_select() {
  select_items_common "SHORTCUT" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_SC_ONCE_FILE" "$item"
    echo "📌 Staged for shortcut: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "shortcut.select.items" "_fx_adf_shortcut_select"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 7 — shortcut.select.items.csv
#  CSV-driven shortcut: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_shortcut_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_SC_ONCE_FILE" "$item"
    echo "📌 Staged for shortcut: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "shortcut.select.items.csv" "_fx_adf_shortcut_select_csv"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 8 — upload.select.items
#  Pick items interactively, upload immediately via fileapi.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_upload_select() {
  select_items_common "UPLOAD" || return
  _up_do_multipart_upload "${selected_items[@]}"
}
_fx_adf_register "upload.select.items" "_fx_adf_upload_select"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 9 — upload.select.items.csv
#  CSV-driven upload: col1 = filename or absolute path, uploaded immediately.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_upload_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _up_do_multipart_upload "${selected_items[@]}"
}
_fx_adf_register "upload.select.items.csv" "_fx_adf_upload_select_csv"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 10 — map.select.items
#  Pick items interactively, generate directory tree map.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_map_select() {
  select_items_common "MAP" || return
  local map_output
  map_output=$(_map_generate_for_paths "${selected_items[@]}")
  echo ""
  echo "1) Copy to clipboard"
  echo "2) Save to txt file"
  echo ""
  local _map_choice
  read -p "Choose option [1-2]: " _map_choice
  case "$_map_choice" in
    1)
      printf "%s" "$map_output" | bashbasicsbyvk_copy
      echo "✅ Map copied to clipboard"
      ;;
    2)
      local _map_fname
      read -p "Enter file name: " _map_fname
      if [ -z "$_map_fname" ]; then
        echo "🚫 Cancelled — no file name entered."
      else
        printf "%s" "$map_output" > "$path/$_map_fname"
        echo "✅ Map saved as $path/$_map_fname"
      fi
      ;;
    *)
      echo "⚠️  Invalid option"
      ;;
  esac
}
_fx_adf_register "map.select.items" "_fx_adf_map_select"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 11 — map.select.items.csv
#  CSV-driven map: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_map_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  local map_output
  map_output=$(_map_generate_for_paths "${selected_items[@]}")
  echo ""
  echo "1) Copy to clipboard"
  echo "2) Save to txt file"
  echo ""
  local _map_choice
  read -p "Choose option [1-2]: " _map_choice
  case "$_map_choice" in
    1)
      printf "%s" "$map_output" | bashbasicsbyvk_copy
      echo "✅ Map copied to clipboard"
      ;;
    2)
      local _map_fname
      read -p "Enter file name: " _map_fname
      if [ -z "$_map_fname" ]; then
        echo "🚫 Cancelled — no file name entered."
      else
        printf "%s" "$map_output" > "$path/$_map_fname"
        echo "✅ Map saved as $path/$_map_fname"
      fi
      ;;
    *)
      echo "⚠️  Invalid option"
      ;;
  esac
}
_fx_adf_register "map.select.items.csv" "_fx_adf_map_select_csv"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 12 — bookmark.select.items
#  Pick items interactively, stage into bookmark buffer.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_bookmark_select() {
  select_items_common "BOOKMARK" || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_BM_ONCE_FILE" "$item"
    echo "📌 Staged for bookmark: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "bookmark.select.items" "_fx_adf_bookmark_select"

# ════════════════════════════════════════════════════════════════════════════
#  ADF 13 — bookmark.select.items.csv
#  CSV-driven bookmark: col1 = filename or absolute path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_bookmark_select_csv() {
  open_csv_menu || return
  [ -z "$csv_file" ] && return
  _csv_resolve_items || return
  _sp_ensure_store
  local item
  for item in "${selected_items[@]}"; do
    _sp_append "$_SP_BM_ONCE_FILE" "$item"
    echo "📌 Staged for bookmark: ${item##*/}"
  done
  echo "➡️  Navigate to destination, then use d- to apply."
}
_fx_adf_register "bookmark.select.items.csv" "_fx_adf_bookmark_select_csv"

# ════════════════════════════════════════════════════════════════════════════
#  Tab cycle
# ════════════════════════════════════════════════════════════════════════════

_fx_tab_next() {
  case "$_fx_tab" in
    adf) _fx_tab=udf ;;
    udf) _fx_tab=adf ;;
  esac
}

_fx_tab_prev() {
  case "$_fx_tab" in
    adf) _fx_tab=udf ;;
    udf) _fx_tab=adf ;;
  esac
}

_fx_tab_label() {
  local ad="🛠️  ADF" ud="👤 UDF"
  case "$_fx_tab" in
    adf) printf '[%s]   %s'  "$ad" "$ud" ;;
    udf) printf ' %s  [%s]' "$ad" "$ud" ;;
  esac
}

# ── Headers / footers ─────────────────────────────────────────────────────────

_fx_menu_header() {
  echo
  printf '⚡ FUNCTIONS  %s   ←/→ tabs\n' "$(_fx_tab_label)"
  printf '📂 %s%s\n' "$path" "${group_prefix:+ [group: ${group_prefix^^}*]}"
  if [ -n "$_filter_query" ]; then
    printf '🔍 filter: %s*  (%d/%d)\n' "${_filter_query^^}" "${#items[@]}" "${#_all_items[@]}"
  fi
}

_fx_menu_header_imaginary() {
  _fx_menu_header
  echo "$_imag_banner"
}

_fx_menu_footer_adf() {
  local n="${#_fx_adf_labels[@]}"
  printf '\n[ADF — Admin Defined]  %d function(s) available\n' "$n"
  printf 'Select number to run   fx) Exit functions mode\n'
}

_fx_menu_footer_udf() {
  printf '\n[UDF — User Defined]  Scripts in execute dir — run from current path\n'
  printf 'u) Up   t) Transfer   d) Delete   c) Create   f) Find\n'
  printf 'r) Rename   s) Settings   x) Organise   fx) Exit\n'
  [ -n "$group_prefix" ] && printf 'back) Remove last prefix (%s*)\n' "${group_prefix^^}"
}

_fx_set_viewport_for_tab() {
  local ftr
  case "$_fx_tab" in
    adf) ftr=_fx_menu_footer_adf ;;
    udf) ftr=_fx_menu_footer_udf ;;
  esac
  _vp_mode="items"
  _vp_header_fn=_fx_menu_header
  _vp_footer_fn="$ftr"
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
}

# ── Item builder per tab ──────────────────────────────────────────────────────

_fx_build_items_for_tab() {
  imaginary_mode=false
  _filter_query=""
  _all_items=()
  items=()
  _hl_index=0

  case "$_fx_tab" in

    adf)
      local i
      for i in "${!_fx_adf_labels[@]}"; do
        items+=("${_fx_adf_labels[$i]}")
      done
      _all_items=("${items[@]}")
      ;;

    udf)
      local _saved_path="$path"
      path="$_FX_EXEC_DIR"

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

      path="$_saved_path"
      ;;
  esac
}

# ── ADF selection handler ─────────────────────────────────────────────────────

_fx_adf_handle_selection() {
  local choice="$1"
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#_fx_adf_labels[@]}" ]; then
    local fn="${_fx_adf_fns[$((choice-1))]}"
    local lbl="${_fx_adf_labels[$((choice-1))]}"
    echo ""
    echo "▶  Running: $lbl"
    echo "   (in: $path)"
    echo ""
    "$fn"
  else
    echo "⚠️  Invalid selection"
  fi
}

# ── UDF selection handler ─────────────────────────────────────────────────────

_fx_udf_handle_selection() {
  local choice="$1"
  local _exec_path="$_FX_EXEC_DIR"

  if $imaginary_mode; then
    _sw_bookmarks_handle_selection "$choice"
    return $?
  fi

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local selected="${items[$((choice-1))]}"
    if [ -d "$selected" ]; then
      path="$selected"; group_prefix=""; force_show=false; return 0
    fi
    if [ -f "$selected" ]; then
      echo ""
      echo "▶  Running: ${selected##*/}"
      echo "   (in: $_fx_outer_path)"
      echo ""
      (cd "$_fx_outer_path" && bash "$selected")
    fi
  else
    echo "⚠️  Invalid selection"
  fi
}

# ── In-place tab redraw ───────────────────────────────────────────────────────

_fx_tab_redraw() {
  local _old_blk_h="${_blk_h:-0}"

  _fx_build_items_for_tab
  _fx_set_viewport_for_tab
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows

  local _up=$(( _old_blk_h ))
  local _rows; _rows=$(_term_rows)
  (( _up > _rows - 1 )) && _up=$(( _rows - 1 ))
  (( _up < 0 ))         && _up=0
  (( _up > 0 ))         && printf '\033[%dA' "$_up"
  printf '\r\033[J'
  _vp_build_chrome
  _vp_geometry
  _vp_ensure_visible "${_hl_index:-1}"
  _vp_emit
}

# ── Main entry point ──────────────────────────────────────────────────────────

functions_menu() {
  _fx_ensure_store

  local _fx_outer_path="$path"
  local _fx_saved_prefix="$group_prefix"
  local _fx_saved_force="$force_show"

  _fx_tab="adf"
  group_prefix=""
  force_show=false
  _fx_in_mode=1
  _sw_in_mode=1

  _fx_outer_path="$_fx_outer_path"

  local _fx_choice

  shopt -s nullglob

  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  _fx_build_items_for_tab
  _fx_set_viewport_for_tab
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows
  _vp_render_fresh

  while true; do

    _read_choice
    _fx_choice="$choice"

    shopt -s nocasematch

    case "$_fx_choice" in
      __sw_tab_right__)
        _fx_tab_next
        _fx_tab_redraw
        shopt -u nocasematch; continue
        ;;
      __sw_tab_left__)
        _fx_tab_prev
        _fx_tab_redraw
        shopt -u nocasematch; continue
        ;;
    esac

    local _fx_do_fresh=true

    case "$_fx_choice" in

      fx|FX)
        echo "↩️  Exiting functions mode"
        break
        ;;

      q)
        _fx_in_mode=0
        _sw_in_mode=0
        exit 0
        ;;

      -h) open_help ;;

      u)
        if [ "$_fx_tab" = "udf" ]; then
          if [ "$path" != "$_FX_EXEC_DIR" ] && [ "$path" != "/" ]; then
            path=$(dirname "$path"); group_prefix=""; force_show=false
          else
            echo "↩️  At execute root — exiting functions mode"; break
          fi
        else
          echo "⚠️  Navigation not available in ADF tab"
          _fx_do_fresh=false
        fi
        ;;

      back)
        if [ "$_fx_tab" = "udf" ]; then
          [ -n "$group_prefix" ] && group_prefix="${group_prefix%?}" && force_show=false
        else
          _fx_do_fresh=false
        fi
        ;;

      forceshow)
        [ "$_fx_tab" = "udf" ] && handle_force_show || { _fx_do_fresh=false; }
        ;;

      c)
        [ "$_fx_tab" = "udf" ] && handle_create || { echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false; }
        ;;

      d)
        [ "$_fx_tab" = "udf" ] && delete_items || { echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false; }
        ;;

      t)
        [ "$_fx_tab" = "udf" ] && transfer_menu || { echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false; }
        ;;

      x)
        [ "$_fx_tab" = "udf" ] && organise_menu || { echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false; }
        ;;

      r)
        [ "$_fx_tab" = "udf" ] && handle_rename || { echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false; }
        ;;

      f)   find_menu ;;
      s)   settings_menu ;;
      m)   map_directory ;;
      disk) df -h ;;
      ram)  free -h ;;

      rf)
        [ "$_fx_tab" = "udf" ] && handle_refresh || { _fx_do_fresh=false; }
        ;;

      d-) handle_route_dispatch ;;
      v-) handle_route_view ;;

      c-*|m-*|s-*)
        [ "$_fx_tab" = "udf" ] && handle_route_stage "$_fx_choice" || { _fx_do_fresh=false; }
        ;;

      _*) _fx_do_fresh=false ;;

      *)
        case "$_fx_tab" in
          adf) _fx_adf_handle_selection "$_fx_choice" ;;
          udf) _fx_udf_handle_selection "$_fx_choice" ;;
        esac
        ;;
    esac

    shopt -u nocasematch

    if $_fx_do_fresh; then
      declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
      _fx_build_items_for_tab
      _fx_set_viewport_for_tab
      _vp_start=1
      _vp_cache_reset
      _vp_prime_rows
      _vp_render_fresh
    fi

  done

  shopt -u nocasematch
  _fx_in_mode=0
  _sw_in_mode=0

  path="$_fx_outer_path"
  group_prefix="$_fx_saved_prefix"
  force_show="$_fx_saved_force"
}
