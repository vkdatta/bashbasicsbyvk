#!/usr/bin/env bash
# bashbasicsbyvk_adf_map_select.sh
# adf-route='map/map.select.items'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — map.select.items
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
_fx_adf_register "map.select.items" "_fx_adf_map_select" "map/map.select.items"
