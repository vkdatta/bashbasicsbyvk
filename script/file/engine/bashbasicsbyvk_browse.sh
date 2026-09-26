#!/usr/bin/env bash
# _3bvk_import_browse.sh
# File-manager navigation utilities: item/group selection helpers,
# path utilities, force-show toggle, entry dispatch, and daemon bootstrap.
# Sourced by the main script.

# ── Item selection ────────────────────────────────────────────────────────────

select_items_common() {
  local prompt="$1"
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available"
    return 1
  fi

  local _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos itemlist

  _vp_mode="items"
  _multi_prompt_loop

  itemlist="$_buf"
  local indices=($(parse_selection "$itemlist" "${#items[@]}"))
  selected_items=()
  for idx in "${indices[@]}"; do
    selected_items+=("${items[$((idx-1))]}")
  done
  if [ ${#selected_items[@]} -eq 0 ]; then
    echo "❌ No valid items selected"
    return 1
  fi
  return 0
}

select_imaginary_items_common() {
  local p="$1"
  local pfx="$2"
  local prompt="${3:-DELETE}"

  if [ "${#imaginary_map[@]}" -eq 0 ]; then
    echo "❌ No groups available"
    return 1
  fi

  local _prompt="$prompt"
  local -A _msel_set=()
  local _buf _pos

  _vp_mode="imaginary"
  _multi_prompt_loop

  local indices=($(parse_selection "$_buf" "${#imaginary_map[@]}"))
  if [ "${#indices[@]}" -eq 0 ]; then
    echo "❌ No valid groups selected"
    return 1
  fi
  selected_items=()
  for idx in "${indices[@]}"; do
    local ch="${imaginary_map[$((idx-1))]}"
    local ch_lower="${ch,,}"
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ! $show_hidden_files && [[ "$bn" == .* ]] && continue
      local bn_lower="${bn,,}"
      [[ "$bn_lower" != "$pfx"* ]] && continue
      local next_char="${bn_lower:${#pfx}:1}"
      if [ "$ch" == "#" ]; then
        case "$next_char" in
          [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ')
            continue ;;
        esac
      else
        [[ "$next_char" != "$ch_lower" ]] && continue
      fi
      selected_items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  done
  local -A _seen=()
  local unique=()
  for f in "${selected_items[@]}"; do
    [ -z "${_seen[$f]+x}" ] && unique+=("$f") && _seen["$f"]=1
  done
  selected_items=("${unique[@]}")
  if [ "${#selected_items[@]}" -eq 0 ]; then
    echo "❌ No items found for selected groups"
    return 1
  fi
  return 0
}

# ── Path utilities ────────────────────────────────────────────────────────────

get_abs_path() {
  local target="$1"
  if [ -d "$target" ]; then
    cd -- "$target" && pwd
  elif [ -f "$target" ]; then
    local dir=$(dirname -- "$target")
    local base=$(basename -- "$target")
    echo "$(cd -- "$dir" && pwd)/$base"
  else
    echo "Error: '$target' does not exist" >&2
    return 1
  fi
}

fast_count() {
  local pattern="$1"
  local arr=("$pattern")
  echo "${#arr[@]}"
}

count_items_in_path() {
  local p="$1"
  local total
  if $show_hidden_files; then
    local a=("$p"/*)
    local b=("$p"/.[^.]*)
    local count_a="${#a[@]}"
    local filtered=0
    for x in "${b[@]}"; do
      local bn; bn=$(basename "$x")
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ((filtered++))
    done
    [[ "${a[0]}" == "$p/*" ]] && count_a=0
    total=$((count_a + filtered))
  else
    local a=("$p"/*)
    total="${#a[@]}"
    [[ "${a[0]}" == "$p/*" ]] && total=0
  fi
  echo "$total"
}

# ── Force-show toggle ─────────────────────────────────────────────────────────

handle_force_show() {
  if $force_show; then
    force_show=false
    echo "🔓 Force show disabled"
  else
    force_show=true
    echo "🔓 Force show enabled — displaying all items"
  fi
}

# ── Entry dispatch ────────────────────────────────────────────────────────────

handle_selection() {
  local choice="$1"
  if $imaginary_mode; then
    local matched=false
    local ch=""

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"
      matched=true
    elif [[ ${#choice} -eq 1 ]]; then
      local uc="${choice^^}"
      for gc in "${imaginary_map[@]}"; do
        if [[ "$gc" == "$uc" ]] || [[ "$gc" == "$choice" ]]; then
          ch="$gc"
          matched=true
          break
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
            [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ')
              continue ;;
          esac
          items+=("$_f")
        done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
        _collect_metadata
        apply_sort
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
  else
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
      selected="${items[$((choice-1))]}"
      local bn="${selected##*/}"

      if [[ "$bn" == *.shortcut ]]; then
        local sc_target sc_type
        sc_target=$(_shortcut_resolve "$selected")
        if [ $? -ne 0 ]; then
          echo "💡 The shortcut file is still present — you can delete or rename it."
          return
        fi
        sc_type=$(_shortcut_read_field "$selected" "SHORTCUT_TYPE")

        if [ "$sc_type" == "dir" ] || [ -d "$sc_target" ]; then
          path="$sc_target"
          group_prefix=""
          force_show=false
        else
          handle_file "$sc_target"
        fi
        return
      fi

      if [ -d "$selected" ]; then
        path="$selected"
        group_prefix=""
        force_show=false
      elif [ -f "$selected" ]; then
        handle_file "$selected"
      fi
    else
      echo "⚠️  Invalid selection"
    fi
  fi
}

# ── Recents daemon bootstrap ──────────────────────────────────────────────────

_bvk_wake_recents_daemon() {
  local _candidates=(
    "$SCRIPT_DIR/file/bashbasicsbyvk_recents_daemon.py"
    "$SCRIPT_DIR/file/bashbasicsbyvk_recents_daemon"
    "$SCRIPT_DIR/bashbasicsbyvk_recents_daemon.py"
    "$SCRIPT_DIR/bashbasicsbyvk_recents_daemon"
  )
  local _daemon_script=""
  local _c
  for _c in "${_candidates[@]}"; do
    if [ -f "$_c" ]; then
      _daemon_script="$_c"
      break
    fi
  done
  [ -n "$_daemon_script" ] || return

  local _pid
  _pid=$(cat "$_BVK_RECENTS_PID_FILE" 2>/dev/null)
  kill -0 "$_pid" 2>/dev/null && return   # already alive

  if [ -x "$_daemon_script" ]; then
    "$_daemon_script" </dev/null >/dev/null 2>&1 &
  elif command -v python3 >/dev/null 2>&1; then
    python3 "$_daemon_script" </dev/null >/dev/null 2>&1 &
  else
    python "$_daemon_script" </dev/null >/dev/null 2>&1 &
  fi
  disown
}
