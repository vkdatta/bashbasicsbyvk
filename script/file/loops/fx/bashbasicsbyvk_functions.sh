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
#  Tree-based registry.  Each ADF file can declare a staging at its top:
#    adf-staging='navigation/other/currentfile'
#  which places the function at that path in the ADF tree.
#  Functions without a staging go into the root level.
#
#  Internal parallel arrays (one element per registered function):
#    _fx_adf_labels[]   — display label
#    _fx_adf_fns[]      — bash function name to invoke
#    _fx_adf_stagings[]   — folder part of staging, e.g. "navigation/other"
#    _fx_adf_names[]    — leaf segment (last part of staging, or label if no staging)
#
#  Runtime navigation:
#    _fx_adf_cur_staging  — current folder the user is browsing ('' = root)

_fx_adf_labels=()
_fx_adf_fns=()
_fx_adf_stagings=()
_fx_adf_names=()
_fx_adf_cur_staging=""   # current folder inside ADF tree

_fx_adf_register() {
  # Usage: _fx_adf_register "Display Label" function_name [staging]
  # staging = full adf-staging value, e.g. "navigation/other/myfile"
  local label="$1" fn="$2" staging="${3:-}"
  local folder="" leaf=""
  if [ -n "$staging" ]; then
    staging="${staging#/}"; staging="${staging%/}"   # strip leading/trailing slashes
    if [[ "$staging" == */* ]]; then
      folder="${staging%/*}"
      leaf="${staging##*/}"
    else
      folder=""
      leaf="$staging"
    fi
  else
    folder=""
    leaf="$label"
  fi
  _fx_adf_labels+=("$label")
  _fx_adf_fns+=("$fn")
  _fx_adf_stagings+=("$folder")
  _fx_adf_names+=("$leaf")
}

# ── ADF tree helpers ──────────────────────────────────────────────────────────

# Print unique immediate sub-folder names at _fx_adf_cur_staging
_fx_adf_list_subfolders() {
  local cur="$_fx_adf_cur_staging" i folder seen=()
  for i in "${!_fx_adf_stagings[@]}"; do
    folder="${_fx_adf_stagings[$i]}"
    local child=""
    if [ -z "$cur" ]; then
      [ -z "$folder" ] && continue          # this fn is at root, no sub-folder
      child="${folder%%/*}"                 # first path segment (e.g. "file_fx" from "file_fx/copy")
    else
      [[ "$folder" != "$cur/"* ]] && continue
      local rest="${folder#$cur/}"
      [[ "$rest" == */* ]] && continue      # deeper than one level below cur
      [ -z "$rest" ] && continue
      child="$rest"
    fi
    local already=false
    for s in "${seen[@]:-}"; do [ "$s" = "$child" ] && already=true && break; done
    $already && continue
    seen+=("$child")
    echo "$child"
  done
}

# Build items[] for the ADF tab: sub-folders first, then functions at this level
_fx_adf_build_items() {
  items=()
  _fx_adf_item_type=()   # parallel: "folder" or "fn"
  _fx_adf_item_idx=()    # parallel: sub-folder name (folder) or index into _fx_adf_fns[] (fn)

  local cur="$_fx_adf_cur_staging"

  # 1. immediate sub-folders (sorted)
  local sub
  while IFS= read -r sub; do
    items+=("$sub")
    _fx_adf_item_type+=("folder")
    _fx_adf_item_idx+=("$sub")
  done < <(_fx_adf_list_subfolders | sort)

  # 2. functions whose folder == cur exactly
  local i
  for i in "${!_fx_adf_stagings[@]}"; do
    local folder="${_fx_adf_stagings[$i]}"
    if [ -z "$cur" ]; then
      [ -n "$folder" ] && continue   # lives in a sub-folder, skip
    else
      [ "$folder" != "$cur" ] && continue
    fi
    items+=("${_fx_adf_labels[$i]}")
    _fx_adf_item_type+=("fn")
    _fx_adf_item_idx+=("$i")
  done

  _all_items=("${items[@]}")
}

# Breadcrumb string shown in the ADF header
_fx_adf_breadcrumb() {
  if [ -z "$_fx_adf_cur_staging" ]; then echo "/"; else echo "/$_fx_adf_cur_staging"; fi
}

# ════════════════════════════════════════════════════════════════════════════
#  ADF function files — each file declares its own adf-staging and calls
#  _fx_adf_register.  Source them all here in load order.
#  To add a new ADF function: create bashbasicsbyvk_adf_<folder>_<name>.sh
#  alongside this file and add a source line below.
# ════════════════════════════════════════════════════════════════════════════

_FX_ADF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_rename_csv.sh"
source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_move_csv.sh"
source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_copy_csv.sh"
source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_shortcut_csv.sh"
source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_upload_csv.sh"
source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_map_csv.sh"
source "${_FX_ADF_DIR}/bashbasicsbyvk_adf_bookmark_csv.sh"

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
  case "$_fx_tab" in
    adf)
      printf '🛠️  ADF %s\n' "$(_fx_adf_breadcrumb)"
      [ -n "$_fx_adf_cur_staging" ] && printf '  u) Up   (in: /%s)\n' "$_fx_adf_cur_staging"
      ;;
    *)
      printf '📂 %s%s\n' "$path" "${group_prefix:+ [group: ${group_prefix^^}*]}"
      ;;
  esac
  if [ -n "$_filter_query" ]; then
    printf '🔍 filter: %s*  (%d/%d)\n' "${_filter_query^^}" "${#items[@]}" "${#_all_items[@]}"
  fi
}

_fx_menu_header_imaginary() {
  _fx_menu_header
  echo "$_imag_banner"
}

_fx_menu_footer_adf() {
  local total="${#_fx_adf_labels[@]}"
  local here="${#items[@]}"
  printf '\n[ADF — Admin Defined]  %d item(s) here  (%d total)\n' "$here" "$total"
  if [ -n "$_fx_adf_cur_staging" ]; then
    printf 'Select to open folder or run function   u) Up   fx) Exit\n'
  else
    printf 'Select to open folder or run function   fx) Exit\n'
  fi
}

_fx_menu_footer_udf() {
  printf '\n[UDF — User Defined]  Scripts in execute dir — run from current path\n'
  printf 'u) Up   t) Transfer   d) Delete   c) Create   f) Find\n'
  printf 'r) Rename   s) Settings   x) Organise   fx) Exit\n'
  [ -n "$group_prefix" ] && printf 'back) Remove last prefix (%s*)\n' "${group_prefix^^}"
}

# Custom row renderer for the ADF tab.
# Reads _fx_adf_item_type[] to pick the right icon, so folders always get 📁
# and functions always get 📄 — exactly once, with no file-path resolution.
_fx_adf_rowtext() {
  local i="$1"
  local label="${items[$((i-1))]}"
  local typ="${_fx_adf_item_type[$((i-1))]:-fn}"
  if [ "$typ" = "folder" ]; then
    printf -v _vp_line " %2d) 📁 %s" "$i" "$label"
  else
    printf -v _vp_line " %2d) 📄 %s" "$i" "$label"
  fi
}

_fx_set_viewport_for_tab() {
  local ftr
  case "$_fx_tab" in
    adf)
      ftr=_fx_menu_footer_adf
      _vp_rowtext_fn=_fx_adf_rowtext   # bypass file-path displayer for ADF items
      ;;
    udf)
      ftr=_fx_menu_footer_udf
      _vp_rowtext_fn=                   # clear so UDF uses the normal _item_line_text path
      ;;
  esac
  _vp_mode="items"
  _vp_header_fn=_fx_menu_header
  _vp_footer_fn="$ftr"
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  # Always wipe the row cache here — _vp_rowtext_fn just changed, so any
  # rows cached by _item_line_text (all 📄) must not survive into the next render.
  _vp_cache_reset
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
      _fx_adf_build_items   # populates items[], _fx_adf_item_type[], _fx_adf_item_idx[]
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
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#items[@]}" ]; then
    echo "⚠️  Invalid selection"
    return 0
  fi
  local slot=$(( choice - 1 ))
  local itype="${_fx_adf_item_type[$slot]}"
  local iidx="${_fx_adf_item_idx[$slot]}"

  case "$itype" in
    folder)
      # Navigate into sub-folder
      if [ -z "$_fx_adf_cur_staging" ]; then
        _fx_adf_cur_staging="$iidx"
      else
        _fx_adf_cur_staging="$_fx_adf_cur_staging/$iidx"
      fi
      ;;
    fn)
      local fn="${_fx_adf_fns[$iidx]}"
      local lbl="${_fx_adf_labels[$iidx]}"
      echo ""
      echo "▶  Running: $lbl"
      echo "   (in: $_fx_outer_path)"
      echo ""
      "$fn"
      ;;
    *)
      echo "⚠️  Unknown item type"
      ;;
  esac
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
  _fx_adf_cur_staging=""   # always start at ADF root
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
        [ "$_fx_tab" = "adf" ] && _fx_adf_cur_staging=""
        _fx_tab_redraw
        shopt -u nocasematch; continue
        ;;
      __sw_tab_left__)
        _fx_tab_prev
        [ "$_fx_tab" = "adf" ] && _fx_adf_cur_staging=""
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
        if [ "$_fx_tab" = "adf" ]; then
          if [ -n "$_fx_adf_cur_staging" ]; then
            if [[ "$_fx_adf_cur_staging" == */* ]]; then
              _fx_adf_cur_staging="${_fx_adf_cur_staging%/*}"
            else
              _fx_adf_cur_staging=""
            fi
          else
            echo "↩️  Already at ADF root"
            _fx_do_fresh=false
          fi
        elif [ "$_fx_tab" = "udf" ]; then
          if [ "$path" != "$_FX_EXEC_DIR" ] && [ "$path" != "/" ]; then
            path=$(dirname "$path"); group_prefix=""; force_show=false
          else
            echo "↩️  At execute root — exiting functions mode"; break
          fi
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
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_c="$path"
          path="$_FX_EXEC_DIR"
          handle_create
          path="$_saved_path_c"
        else
          echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false
        fi
        ;;

      d)
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_d="$path"; path="$_FX_EXEC_DIR"
          delete_items
          path="$_saved_path_d"
        else
          echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false
        fi
        ;;

      t)
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_t="$path"; path="$_FX_EXEC_DIR"
          transfer_menu
          path="$_saved_path_t"
        else
          echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false
        fi
        ;;

      x)
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_x="$path"; path="$_FX_EXEC_DIR"
          organise_menu
          path="$_saved_path_x"
        else
          echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false
        fi
        ;;

      r)
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_r="$path"; path="$_FX_EXEC_DIR"
          handle_rename
          path="$_saved_path_r"
        else
          echo "⚠️  Not available in ADF tab"; _fx_do_fresh=false
        fi
        ;;

      f)   find_menu ;;
      s)   settings_menu ;;
      m)   map_directory ;;
      disk) df -h ;;
      ram)  free -h ;;

      rf)
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_rf="$path"; path="$_FX_EXEC_DIR"
          handle_refresh
          path="$_saved_path_rf"
        else
          _fx_do_fresh=false
        fi
        ;;

      d-) handle_staging_dispatch ;;
      v-) handle_staging_view ;;

      c-*|m-*|s-*)
        if [ "$_fx_tab" = "udf" ]; then
          local _saved_path_rs="$path"; path="$_FX_EXEC_DIR"
          handle_staging_stage "$_fx_choice"
          path="$_saved_path_rs"
        else
          _fx_do_fresh=false
        fi
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
