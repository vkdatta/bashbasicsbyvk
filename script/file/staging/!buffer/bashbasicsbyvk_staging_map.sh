source "bashbasicsbyvk_staging_helpers.sh"

# ─────────────────────────────────────────────
#  map_directory  —  p- prefix entry point
#
#  Syntax (mirrors c- / m- / s- conventions):
#
#    p-a          Create path of ALL items in current view
#    p-1,6        Create path for items 1 and 6 only
#    p-1-5        Create path for items 1 through 5
#    p-a-1,6      Create path for ALL items EXCEPT 1 and 6
#    p-a-1-5,7    Create path for ALL items EXCEPT 1–5 and 7
#
#  After generating the tree, the user chooses:
#    1) Copy to clipboard
#    2) Save to txt file
# ─────────────────────────────────────────────

handle_route_map() {
  local raw="$1"         # the full token typed by the user, e.g. "p-a" or "p-1,6"
  local itemlist="${raw:2}"   # strip leading "p-"

  # ── Guard: need something after p- ──────────────────────────────────
  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage:"
    echo "     p-a          → map all items"
    echo "     p-1,6        → map items 1 and 6"
    echo "     p-1-5        → map items 1 through 5"
    echo "     p-a-1,6      → map all items EXCEPT 1 and 6"
    return 0
  fi

  # ── Guard: imaginary mode has no direct indices ──────────────────────
  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view (group filter or forceshow) before using p- shortcuts."
    return 0
  fi

  # ── Resolve which items to map ───────────────────────────────────────
  local -a target_paths=()

  if [ "$itemlist" = "a" ]; then
    # p-a → all items
    target_paths=("${items[@]}")

  elif [[ "$itemlist" =~ ^a-(.+)$ ]]; then
    # p-a-<exclusions> → all except
    local excl_spec="${BASH_REMATCH[1]}"
    local indices
    indices=($(_sp_parse_all_except "$excl_spec" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ All-except filter excluded every item (spec: '$excl_spec')"
      return 0
    fi
    for idx in "${indices[@]}"; do
      target_paths+=("${items[$((idx-1))]}")
    done

  else
    # p-<list>  →  explicit selection
    local indices
    indices=($(parse_selection "$itemlist" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ No valid item numbers in '$itemlist'"
      return 0
    fi
    for idx in "${indices[@]}"; do
      target_paths+=("${items[$((idx-1))]}")
    done
  fi

  if [ ${#target_paths[@]} -eq 0 ]; then
    echo "❌ No items resolved — nothing to map"
    return 0
  fi

  # ── Build the tree ───────────────────────────────────────────────────
  local map_output
  map_output=$(_map_generate_for_paths "${target_paths[@]}")

  # ── Output choice (same UX as the old mapper) ────────────────────────
  echo
  echo "1) Copy to clipboard"
  echo "2) Save to txt file"
  echo

  local choice
  read -p "Choose option [1-2]: " choice

  case "$choice" in
    1)
      printf "%s" "$map_output" | bashbasicsbyvk_copy
      echo "✅ Map copied to clipboard"
      ;;
    2)
      local filename
      read -p "Enter file name: " filename
      printf "%s" "$map_output" > "$path/$filename"
      echo "✅ Map saved as $path/$filename"
      ;;
    *)
      echo "⚠️  Invalid option"
      ;;
  esac
}

# ─────────────────────────────────────────────
#  Internal: generate the tree text for the
#  given list of absolute paths.
#
#  Strategy:
#    • For directory entries, recurse with `find` (same as the old mapper)
#    • For file entries, just list the basename
#    • Results are printed under a header showing the target dir
# ─────────────────────────────────────────────

_map_generate_for_paths() {
  local -a paths=("$@")
  local output=""

  for p in "${paths[@]}"; do
    local bn="${p##*/}"

    if [ -d "$p" ]; then
      # Directory → recursive tree rooted at this entry
      local subtree
      subtree=$(
        cd "$p" || exit
        local -a find_args=(".")
        $show_hidden_files || find_args+=(-not -path '*/.*')
        find "${find_args[@]}" | sed \
          -e '1d' \
          -e 's|^\./||' \
          -e 's|[^/]*/|│   |g' \
          -e 's|│   \([^│]\)|├── \1|'
      )
      if [ -n "$subtree" ]; then
        output+="${bn}/${subtree:+$'\n'$subtree}"$'\n'
      else
        output+="${bn}/"$'\n'
      fi
    else
      # Plain file → just its name
      output+="${bn}"$'\n'
    fi
  done

  # Trim trailing newline
  printf "%s" "${output%$'\n'}"
}
