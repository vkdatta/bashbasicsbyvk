_GCLOUD_SOCKET=""
_GCLOUD_SSH_HOST=""
_GCLOUD_SSH_PORT=""
_GCLOUD_SSH_USER=""
_GCLOUD_SSH_KEY=""

_gcloud_init_master() {
  if [ -n "$_GCLOUD_SOCKET" ] && ssh -O check -o ControlPath="$_GCLOUD_SOCKET" dummy 2>/dev/null; then
    return 0
  fi

  echo "☁️  Connecting to Cloud Shell (one-time)..."

  local raw_ssh_cmd
  raw_ssh_cmd=$(gcloud cloud-shell ssh --authorize-session --dry-run 2>/dev/null | tail -1)

  if [ -z "$raw_ssh_cmd" ]; then
    echo "❌ Could not determine SSH connection details"
    return 1
  fi

  local _tmp_dir="${TMPDIR:-${PREFIX:-}/tmp}"
  _GCLOUD_SOCKET="${_tmp_dir}/gcloud_cm_$(date +%s).sock"

  _GCLOUD_SSH_HOST=$(echo "$raw_ssh_cmd" | grep -oP '(?<=@)[^ ]+')
  _GCLOUD_SSH_PORT=$(echo "$raw_ssh_cmd" | grep -oP '(?<=-p )\d+')
  _GCLOUD_SSH_USER=$(echo "$raw_ssh_cmd" | grep -oP '\w+(?=@)')
  _GCLOUD_SSH_KEY=$(echo "$raw_ssh_cmd" | grep -oP '(?<=-i )[^ ]+')

  [ -z "$_GCLOUD_SSH_PORT" ] && _GCLOUD_SSH_PORT=22

  ssh -fNM \
    -o ControlMaster=yes \
    -o ControlPath="$_GCLOUD_SOCKET" \
    -o ControlPersist=120 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=24 \
    -o TCPKeepAlive=yes \
    -o IPQoS=throughput \
    -o GSSAPIAuthentication=no \
    -o Compression=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=15 \
    ${_GCLOUD_SSH_KEY:+-i "$_GCLOUD_SSH_KEY"} \
    -p "$_GCLOUD_SSH_PORT" \
    "$_GCLOUD_SSH_USER@$_GCLOUD_SSH_HOST" 2>/dev/null

  if [ $? -ne 0 ]; then
    echo "❌ ControlMaster failed to start"
    _GCLOUD_SOCKET=""
    return 1
  fi

  echo "💫 SSH tunnel established"
  return 0
}

_gcloud_cmd() {
  if [ -n "$_GCLOUD_SOCKET" ] && ssh -O check -o ControlPath="$_GCLOUD_SOCKET" dummy 2>/dev/null; then
    ssh \
      -o ControlMaster=no \
      -o ControlPath="$_GCLOUD_SOCKET" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      ${_GCLOUD_SSH_KEY:+-i "$_GCLOUD_SSH_KEY"} \
      -p "$_GCLOUD_SSH_PORT" \
      "$_GCLOUD_SSH_USER@$_GCLOUD_SSH_HOST" "$1" 2>/dev/null
  else
    gcloud cloud-shell ssh --authorize-session \
      --ssh-flag="-o ServerAliveInterval=5" \
      --ssh-flag="-o ServerAliveCountMax=24" \
      --ssh-flag="-o TCPKeepAlive=yes" \
      --ssh-flag="-o IPQoS=throughput" \
      --ssh-flag="-o GSSAPIAuthentication=no" \
      --ssh-flag="-o Compression=yes" \
      --ssh-flag="-o StrictHostKeyChecking=no" \
      --ssh-flag="-o UserKnownHostsFile=/dev/null" \
      --ssh-flag="-o LogLevel=ERROR" \
      --ssh-flag="-o ConnectTimeout=15" \
      --command "$1" 2>/dev/null
  fi
}

_in_selection() {
  local item="$1"; shift
  # 'existing' MUST be local. Bash uses dynamic scoping, so without this the
  # loop writes into any caller variable of the same name -- _sp_append() in
  # bashbasicbyvk_staging.sh keeps its buffer in `local -a existing`, and
  # this loop was silently overwriting existing[0] on every call, dropping the
  # first staged item whenever 3+ items were staged at once.
  local existing
  for existing in "$@"; do
    [[ "$existing" == "$item" ]] && return 0
  done
  return 1
}

nav_last_browsed_path=""

_view_selections_menu() {
  local -n _sel_ref="$1"
  local -a _view_history=()

  while true; do
    echo
    if [ ${#_sel_ref[@]} -eq 0 ]; then
      echo "📋 No items selected yet."
    else
      echo "📋 Current selections (${#_sel_ref[@]}):"
      local i=1
      for s in "${_sel_ref[@]}"; do
        printf "  %2d) %s\n" "$i" "$(basename "$s")"
        i=$((i+1))
      done
    fi
    _mc_footer "c:Confirm" "x:Remove" "u:Back" "q:Quit"
    read -e -p "Selection view: " sv_choice

    case "$sv_choice" in
      c|C)
        if [ ${#_sel_ref[@]} -eq 0 ]; then
          echo "🔴  Nothing selected — add items before confirming."
        else
          echo "💫 Selections confirmed (${#_sel_ref[@]} item(s))"
          return 0
        fi
        ;;
      x|X)
        if [ ${#_sel_ref[@]} -eq 0 ]; then
          echo "🔴  Nothing to remove."
          continue
        fi
        echo "Enter item number(s) to remove (e.g. 1,3 or 2-5):"
        read -e -p "Remove: " rm_input
        local rm_indices
        rm_indices=($(parse_selection "$rm_input" "${#_sel_ref[@]}"))
        if [ ${#rm_indices[@]} -eq 0 ]; then
          echo "❌ No valid numbers entered"
          continue
        fi
        local -A _to_remove=()
        for ri in "${rm_indices[@]}"; do
          _to_remove["$ri"]=1
        done
        local new_sel=()
        local j=1
        for s in "${_sel_ref[@]}"; do
          [ -z "${_to_remove[$j]+x}" ] && new_sel+=("$s")
          j=$((j+1))
        done
        _sel_ref=("${new_sel[@]}")
        echo "💫 Removed ${#rm_indices[@]} item(s). Remaining: ${#_sel_ref[@]}"
        ;;
      u|U)
        echo "↩️  Back to navigation"
        return 1
        ;;
      q|Q)
        _bvk_quit; return 1
        ;;
      *)
        _bvk_invalid
        ;;
    esac
  done
}

# ── input helpers shared by the local and the gcloud navigator ────────────────────────────────────────────
# _nav_parse_select <typed>  → is_select (true when it starts with s, or has a , or - : "pick several") and cleaned_input (the typed text
# without the s) in the CALLER's variables.
_nav_parse_select() {
  is_select=false
  [[ "$1" =~ ^[sS] ]] && is_select=true
  cleaned_input=$(printf '%s' "$1" | sed 's/[Ss]\([0-9]\)/\1/g; s/^[Ss]//')
  [[ "$cleaned_input" =~ [,\-] ]] && is_select=true
  return 0
}
# _nav_index_ok <typed> <count>  → 0 when <typed> is a row number 1..<count>
_nav_index_ok() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le "$2" ]; }

# _nav_add_range <cleaned-input like "1,3-5"> <items-array> <selected-array> [<dir>]
# The multi-select of both navigators (local and GCloud): appends every picked item that is not selected yet to <selected-array>
# and prints the summary.  With <dir> the stored path is  <dir>/<item without its trailing />  (GCloud: names are relative), else the item itself.
_nav_add_range() {
  local -n _ar_items="$2" _ar_sel="$3"
  local indices idx item added=0 skipped=0 msg
  indices=($(parse_selection "$1" "${#_ar_items[@]}"))
  if [ ${#indices[@]} -eq 0 ]; then echo "🔴  No valid numbers"; return 0; fi
  for idx in "${indices[@]}"; do
    item="${_ar_items[$((idx-1))]}"
    [ $# -ge 4 ] && item="$4/${item%/}"
    if _in_selection "$item" "${_ar_sel[@]}"; then
      skipped=$((skipped+1))
    else
      _ar_sel+=("$item")
      added=$((added+1))
    fi
  done
  msg="➕ Added $added item(s)"
  [ $skipped -gt 0 ] && msg="$msg (skipped $skipped duplicate(s))"
  echo "$msg — total selected: ${#_ar_sel[@]}  (v to review)"
}

local_navigator() {
  local mode="$1"
  local start_path="${2:-$HOME}"
  local nav_path="$start_path"
  local nav_prefix=""
  local nav_force_show=false
  nav_result_path=""
  nav_selected_items=()

  while true; do
    nav_last_browsed_path="$nav_path"
    echo
    if [ "$mode" == "source" ]; then
      echo "📂 SELECT SOURCE — Location: $nav_path${nav_prefix:+ [filter: ${nav_prefix^^}*]}"
    else
      echo "📂 SELECT DESTINATION — Location: $nav_path${nav_prefix:+ [filter: ${nav_prefix^^}*]}"
    fi

    local nav_imaginary=false
    local nav_items=()

    _bvk_index_decide "$nav_path" "$nav_prefix" "$nav_force_show"
    case "$_bvk_ix_kind" in
      groups) nav_imaginary=true; display_imaginary_groups "$nav_path" "$_bvk_ix_pfx" "$_bvk_ix_count" ;;
      flat)   nav_items=("${_bvk_pfx_items[@]}") ;;
    esac

    if ! $nav_imaginary; then
      if [ ${#nav_items[@]} -eq 0 ] && [ -n "$nav_prefix" ]; then
        build_items_for_prefix "$nav_path" "$nav_prefix"
        nav_items=("${items[@]}")
      elif [ ${#nav_items[@]} -eq 0 ]; then
        build_all_items "$nav_path"
        nav_items=("${items[@]}")
      fi
      if [ ${#nav_items[@]} -eq 0 ]; then
        echo "🛑 This directory is empty"
      else
        local idx=1
        for item in "${nav_items[@]}"; do
          local _nav_icon _nav_bn
          _nav_bn="${item##*/}"
          if [[ "$_nav_bn" == *.shortcut ]]; then
            local _sc_type
            _sc_type=$(_shortcut_read_field "$item" "SHORTCUT_TYPE")
            local _sc_name
            _sc_name=$(_shortcut_read_field "$item" "SHORTCUT_NAME")
            [ -z "$_sc_name" ] && _sc_name="${_nav_bn%.shortcut}"
            [ "$_sc_type" == "dir" ] && _nav_icon="🔑" || _nav_icon="🗝️"
            printf "%2d) %s %s\n" "$idx" "$_nav_icon" "$_sc_name"
          else
            [ -d "$item" ] && _nav_icon="📁" || _nav_icon="📄"
            local _nav_ln; printf -v _nav_ln "%2d) %s %s" "$idx" "$_nav_icon" "$_nav_bn"
            if declare -F _sel_mark_v >/dev/null 2>&1 && _sel_mark_v "$item" "$_nav_ln"; then
              printf '%s\n' "$_smk_out"     # selected with .s — green "+"
            else
              printf '%s\n' "$_nav_ln"
            fi
          fi
          idx=$((idx+1))
        done
      fi
    fi

    if [ "$mode" == "source" ]; then
      _mc_footer "u:Up" "v:View selections" "z:Cancel" "q:Quit" "#tip: use prefix 's' to select a folder"
    else
      _mc_footer "u:Up" "n:New folder" "c:Confirm destination" "z:Cancel" "q:Quit"
    fi

    read -e -p "Nav: " nav_choice

    case "$nav_choice" in
      q|Q) _bvk_quit; return 1 ;;
      z|Z)
        echo "🚫 Navigation cancelled"
        return 1
        ;;
      u|U)
        if [ "$nav_path" != "/" ]; then
          nav_path=$(dirname "$nav_path")
          nav_prefix=""
          nav_force_show=false
        fi
        ;;
      n|N)
        if [ "$mode" == "dest" ]; then
          read -e -p "📂 New folder name: " new_dir_name
          if [ -n "$new_dir_name" ] && _bvk_name_too_long "$new_dir_name"; then
            _bvk_name_refuse "$new_dir_name" "Folder"
          elif [ -n "$new_dir_name" ]; then
            mkdir -p "$nav_path/$new_dir_name"
            echo "💫 Created: $nav_path/$new_dir_name"
            nav_path="$nav_path/$new_dir_name"
          fi
        else
          _bvk_invalid
        fi
        ;;
      v|V)
        if [ "$mode" == "source" ]; then
          _view_selections_menu nav_selected_items
          [ $? -eq 0 ] && return 0
        else
          _bvk_invalid
        fi
        ;;
      c|C)
        if [ "$mode" == "dest" ]; then
          nav_result_path="$nav_path"
          echo "💫 Destination confirmed: $nav_result_path"
          return 0
        else
          echo "🔴  Use v) to view and confirm your selections"
        fi
        ;;
      *)
        if $nav_imaginary; then
          local matched=false
          local ch=""
          if _nav_index_ok "$nav_choice" "${#imaginary_map[@]}"; then
            ch="${imaginary_map[$((nav_choice-1))]}"
            matched=true
          elif [[ ${#nav_choice} -eq 1 ]]; then
            ch="${nav_choice^^}"
            for gc in "${group_chars[@]}"; do
              [[ "$gc" == "$ch" ]] && matched=true && break
            done
            [[ "$matched" == false && "$nav_choice" == "#" ]] && ch="#" && matched=true
          fi
          if $matched; then
            [ "$ch" == "#" ] && nav_prefix="${nav_prefix}#" || nav_prefix="${nav_prefix}${ch,,}"
            nav_force_show=false
          else
            _bvk_invalid
          fi
        else
          if [ "$mode" == "source" ]; then
            local is_select cleaned_input
            _nav_parse_select "$nav_choice"

            if [[ "$cleaned_input" =~ ^[0-9,\-]+$ ]]; then
              if $is_select; then
                _nav_add_range "$cleaned_input" nav_items nav_selected_items
              else
                if _nav_index_ok "$cleaned_input" "${#nav_items[@]}"; then
                  local sel="${nav_items[$((cleaned_input-1))]}"
                  if [ -d "$sel" ]; then
                    nav_path="$sel"
                    nav_prefix=""
                    nav_force_show=false
                  else
                    if _in_selection "$sel" "${nav_selected_items[@]}"; then
                      echo "🔴  Already selected: $(basename "$sel") — skipped"
                    else
                      nav_selected_items+=("$sel")
                      echo "➕ Selected: $(basename "$sel") — total: ${#nav_selected_items[@]}  (v to review)"
                    fi
                  fi
                else
                  _bvk_invalid
                fi
              fi
            else
              echo "🔴  Invalid input"
            fi
          else
            if _nav_index_ok "$nav_choice" "${#nav_items[@]}"; then
              local sel="${nav_items[$((nav_choice-1))]}"
              if [ -d "$sel" ]; then
                nav_path="$sel"
                nav_prefix=""
                nav_force_show=false
              else
                echo "🔴  Select a folder (📁) to navigate into, or c) to confirm this location"
              fi
            else
              _bvk_invalid
            fi
          fi
        fi
        ;;
    esac
  done
}

gcloud_navigator() {
  local mode="$1"
  gcloud_nav_result_path=""
  gcloud_nav_selected_items=()
  local -a _nav_history=()

  _gcloud_init_master || return 1

  local remote_path
  remote_path=$(_gcloud_cmd "echo \$HOME" | tail -1)
  [ -z "$remote_path" ] && remote_path="$HOME"

  while true; do
    echo
    if [ "$mode" == "source" ]; then
      echo "☁️  GCLOUD SOURCE — Location: $remote_path"
    else
      echo "☁️  GCLOUD DESTINATION — Location: $remote_path"
    fi

    local listing
    listing=$(_gcloud_cmd "ls -1Ap '$remote_path' 2>/dev/null")

    local -a remote_items=()
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      remote_items+=("$line")
    done <<< "$listing"

    if [ ${#remote_items[@]} -eq 0 ]; then
      echo "🛑 Remote directory is empty or inaccessible"
    else
      local idx=1
      for item in "${remote_items[@]}"; do
        if [[ "$item" == */ ]]; then
          printf "%2d) 📁 %s\n" "$idx" "${item%/}"
        else
          printf "%2d) 📄 %s\n" "$idx" "$item"
        fi
        idx=$((idx+1))
      done
    fi

    if [ "$mode" == "source" ]; then
      _mc_footer "u:Up" "v:View selections" "z:Cancel" "q:Quit" "#tip: use prefix 's' to select a folder"
    else
      _mc_footer "u:Up" "n:New folder" "c:Confirm destination" "z:Cancel" "q:Quit"
    fi

    read -e -p "GCloud Nav: " gnav_choice

    case "$gnav_choice" in
      q|Q)
        gcloud_nav_selected_items=()
        echo "🗑️  All selections cleared. Closing."
        _bvk_quit; return 1
        ;;
      z|Z)
        echo "🚫 GCloud navigation cancelled"
        return 1
        ;;
      u|U)
        remote_path=$(dirname "$remote_path")
        ;;
      n|N)
        if [ "$mode" == "dest" ]; then
          read -e -p "📂 New remote folder name: " new_rdir
          if [ -n "$new_rdir" ]; then
            _gcloud_cmd "mkdir -p '$remote_path/$new_rdir'"
            echo "💫 Created remote: $remote_path/$new_rdir"
            remote_path="$remote_path/$new_rdir"
          fi
        else
          _bvk_invalid
        fi
        ;;
      v|V)
        if [ "$mode" == "source" ]; then
          _view_selections_menu gcloud_nav_selected_items
          [ $? -eq 0 ] && return 0
        else
          _bvk_invalid
        fi
        ;;
      c|C)
        if [ "$mode" == "dest" ]; then
          gcloud_nav_result_path="$remote_path"
          echo "💫 GCloud destination confirmed: $gcloud_nav_result_path"
          return 0
        else
          echo "🔴  Use v) to view and confirm your selections"
        fi
        ;;
      *)
        if [ "$mode" == "source" ]; then
          local is_select cleaned_input
          _nav_parse_select "$gnav_choice"

          if [[ "$cleaned_input" =~ ^[0-9,\-]+$ ]]; then
            if $is_select; then
              _nav_add_range "$cleaned_input" remote_items gcloud_nav_selected_items "$remote_path"
            else
              if _nav_index_ok "$cleaned_input" "${#remote_items[@]}"; then
                local sel="${remote_items[$((cleaned_input-1))]}"
                if [[ "$sel" == */ ]]; then
                  _nav_history+=("$remote_path")
                  remote_path="$remote_path/${sel%/}"
                else
                  local full_path="$remote_path/$sel"
                  if _in_selection "$full_path" "${gcloud_nav_selected_items[@]}"; then
                    echo "🔴  Already selected: $sel — skipped"
                  else
                    gcloud_nav_selected_items+=("$full_path")
                    echo "➕ Selected: $sel — total: ${#gcloud_nav_selected_items[@]}  (v to review)"
                  fi
                fi
              else
                _bvk_invalid
              fi
            fi
          else
            echo "🔴  Invalid input"
          fi
        else
          if _nav_index_ok "$gnav_choice" "${#remote_items[@]}"; then
            local sel="${remote_items[$((gnav_choice-1))]}"
            if [[ "$sel" == */ ]]; then
              _nav_history+=("$remote_path")
              remote_path="$remote_path/${sel%/}"
            else
              echo "🔴  Select a folder (📁) to navigate into, or c) to confirm this location"
            fi
          else
            _bvk_invalid
          fi
        fi
        ;;
    esac
  done
}

# Compact result line for copy/move: "Moved x out of n item(s)" + failed items only.
# Usage: _transfer_report <Verb> <ok> <total> <dest> [failed-line ...]
_transfer_report() {
  local verb="$1" ok="$2" total="$3" dest="$4"
  shift 4
  local icon="💫"
  [ $# -gt 0 ] && icon="🔴 "
  echo "$icon $verb $ok out of $total item(s) → $dest"
  if [ $# -gt 0 ]; then
    echo "❌ Failed ($#):"
    local f
    for f in "$@"; do echo "  • $f"; done
  fi
}

perform_copy() {
  local dest="$1"
  shift
  local src_items=("$@")
  local total=${#src_items[@]} ok=0
  local -a failed=()
  local item err
  _lk_load
  for item in "${src_items[@]}"; do
    if [ ! -e "$item" ]; then
      failed+=("$(basename -- "$item") — not found")
      continue
    fi
    local base name ext count newbase
    base=$(basename -- "$item")
    name="${base%.*}"
    ext="${base##*.}"
    [[ "$base" == "$ext" ]] && ext=""
    count=1
    newbase="$base"
    while [ -e "$dest/$newbase" ]; do
      if [ -n "$ext" ]; then
        newbase="${name}${count}.${ext}"
      else
        newbase="${name}${count}"
      fi
      count=$((count+1))
    done
    if err=$(cp -r -- "$item" "$dest/$newbase" 2>&1); then
      ok=$((ok+1))
      _carry_copy "$item" "$dest/$newbase"    # copy of a locked item is locked; copied shortcuts are indexed
    else
      failed+=("$base — ${err:-cp returned $?}")
    fi
  done
  _transfer_report "Copied" "$ok" "$total" "$dest" "${failed[@]}"
}

perform_move() {
  local dest="$1"
  shift
  local src_items=("$@")
  local total=${#src_items[@]} ok=0
  local -a failed=()
  local item err tgt
  _carry_begin                              # locks + shortcuts: synced once after the loop
  for item in "${src_items[@]}"; do
    if [ ! -e "$item" ]; then
      failed+=("$(basename -- "$item") — not found")
      continue
    fi
    tgt="$dest/$(basename -- "$item")"
    # mv would silently overwrite an existing destination — never a locked one
    if { [ -e "$tgt" ] || [ -L "$tgt" ]; } && _lk_is_protected "$tgt"; then
      failed+=("$(basename -- "$item") — 🔒 a locked item of that name is at the destination, not overwritten")
      continue
    fi
    if err=$(mv -- "$item" "$dest/" 2>&1); then
      ok=$((ok+1))
      _carry_move "$item" "$tgt"              # lock moves; shortcuts to it re-point
    else
      failed+=("$(basename -- "$item") — ${err:-mv returned $?}")
    fi
  done
  _carry_end
  _transfer_report "Moved" "$ok" "$total" "$dest" "${failed[@]}"
}

_shortcut_read_field() {
  local sc_file="$1"
  local field="$2"
  [ ! -f "$sc_file" ] && return 1
  local val
  val=$(grep -m1 "^${field}=" "$sc_file" 2>/dev/null | cut -d'=' -f2-)
  printf '%s' "$val"
}

_shortcut_write() {
  local dest_dir="$1"
  local target="$2"
  local display_name="$3"

  local sc_type="file"
  [ -d "$target" ] && sc_type="dir"

  local sc_base="${display_name}.shortcut"
  local sc_path="$dest_dir/$sc_base"
  local count=1
  while [ -e "$sc_path" ]; do
    sc_path="$dest_dir/${display_name}${count}.shortcut"
    count=$((count+1))
  done

  {
    printf 'SHORTCUT_TARGET=%s\n' "$target"
    printf 'SHORTCUT_TYPE=%s\n'   "$sc_type"
    printf 'SHORTCUT_NAME=%s\n'   "$display_name"
    printf 'SHORTCUT_CREATED=%s\n' "$(date +%s)"
  } > "$sc_path"

  _scr_add "$sc_path"            # index it, so later renames / moves of the target are carried
  printf '%s' "$sc_path"
}

_shortcut_resolve() {
  local sc_file="$1"
  local target
  target=$(_shortcut_read_field "$sc_file" "SHORTCUT_TARGET")
  if [ -z "$target" ]; then
    echo "❌ Shortcut has no target recorded" >&2
    return 1
  fi
  if [ ! -e "$target" ]; then
    echo "🔴  Shortcut target no longer exists: $target" >&2
    return 1
  fi
  printf '%s' "$target"
  return 0
}

perform_shortcut() {
  local dest="$1"
  shift
  local src_items=("$@")

  if [ ! -d "$dest" ]; then
    echo "❌ Destination is not a directory: $dest"
    return 1
  fi

  for item in "${src_items[@]}"; do
    if [ ! -e "$item" ]; then
      echo "  🔴  Skipped (not found): $item"
      continue
    fi

    local abs_target
    if [ -d "$item" ]; then
      abs_target=$(cd -- "$item" && pwd)
    else
      abs_target=$(cd -- "$(dirname "$item")" && pwd)/$(basename -- "$item")
    fi

    local display_name
    display_name=$(basename -- "$abs_target")

    local sc_path
    sc_path=$(_shortcut_write "$dest" "$abs_target" "$display_name")

    local sc_icon
    [ -d "$item" ] && sc_icon="🔑" || sc_icon="🗝️"
    echo "  💫 Shortcut created: ${sc_icon} ${display_name} → $dest/$(basename "$sc_path")"
  done
}

_get_mime_type() {
  local file="$1"
  local base ext mime
  base="${file##*/}"

  # Dotfile rule: an extension only exists if there is a non-empty prefix
  # before the LAST dot, and that prefix is not itself made up entirely of
  # leading dots. e.g.:
  #   name        -> no dot at all          -> no extension
  #   .name       -> leading dot, no prefix -> no extension (whole thing is the filename)
  #   ..name      -> still no real prefix   -> no extension
  #   prefix.ext  -> real prefix before dot -> extension is "ext"
  #   archive.tar.gz -> prefix "archive.tar", extension "gz"
  local stripped="$base"
  while [[ "$stripped" == .* ]]; do
    stripped="${stripped#.}"
  done
  if [[ "$stripped" != *.* ]]; then
    ext=""
  else
    ext="${base##*.}"
  fi
  ext="${ext,,}"

  case "$ext" in
    js|mjs)       mime="application/javascript" ;;
    ts)           mime="application/typescript" ;;
    py)           mime="application/x-python" ;;
    sh|bash)      mime="text/x-shellscript" ;;
    json)         mime="application/json" ;;
    html|htm)     mime="application/html" ;;
    css)          mime="application/css" ;;
    md|markdown)  mime="text/markdown" ;;
    txt)          mime="text/plain" ;;
    csv)          mime="text/csv" ;;
    xml)          mime="application/xml" ;;
    pdf)          mime="application/pdf" ;;
    png)          mime="image/png" ;;
    jpg|jpeg)     mime="image/jpeg" ;;
    gif)          mime="image/gif" ;;
    svg)          mime="image/svg+xml" ;;
    webp)         mime="image/webp" ;;
    mp3)          mime="audio/mpeg" ;;
    mp4)          mime="video/mp4" ;;
    zip)          mime="application/zip" ;;
    tar)          mime="application/x-tar" ;;
    gz|tgz)       mime="application/gzip" ;;
    sql)          mime="application/sql" ;;
    java)         mime="text/x-java-source" ;;
    c)            mime="application/x-c" ;;
    cpp|cc|cxx)   mime="application/x-c++" ;;
    wasm)         mime="application/wasm" ;;
    wat)          mime="application/wat" ;;
    asm|s)        mime="application/x-asm" ;;
    go)           mime="text/x-go" ;;
    rs)           mime="text/x-rust" ;;
    php)          mime="application/x-httpd-php" ;;
    rb)           mime="text/x-ruby" ;;
    kt|kts)       mime="text/x-kotlin" ;;
    dart)         mime="application/dart" ;;
    lua)          mime="text/x-lua" ;;
    r)            mime="text/x-r" ;;
    yaml|yml)     mime="text/yaml" ;;
    toml)         mime="text/x-toml" ;;
    ini|cfg|conf) mime="text/plain" ;;
    "")
      # No extension at all (covers .name, ..name, and plain "name").
      if [ -d "$file" ]; then
        mime="inode/directory"
      else
        mime="application/octet-stream"
      fi
      ;;
    *)
      if command -v file >/dev/null 2>&1; then
        mime=$(file --mime-type -b "$file" 2>/dev/null)
      fi
      [ -z "$mime" ] && mime="application/octet-stream"
      ;;
  esac

  echo "$mime"
}

transfer_menu() {
  _mc_menu "📦 TRANSFER — Step 1: Choose mode" -- \
    "Intra-location (Current CLI → Current CLI [Up Down])" \
    "Intra-location (Current CLI → Current CLI [Down Up])" \
    "Current CLI To Drive (Via rclone)" \
    "Local To GCloud (Run from Local)" \
    "GCloud To Local (Run from Local)" -- @back_quit
  read -e -p "Select: " t_mode

  case "$t_mode" in
  u|U) return ;;
  q|Q) _bvk_quit; return 1 ;;
    1|2|3|4|5) ;;
    *)
      echo "❌ Invalid mode"
      return
      ;;
  esac

  echo
  echo "📦 TRANSFER — Step 2: Select source items"

  local step2_ok=false

  if [ "$t_mode" == "5" ]; then
    if ! command -v gcloud >/dev/null 2>&1; then
      echo "❌ gcloud not found in PATH."
      return
    fi
    gcloud_navigator "source"
    if [ $? -ne 0 ] || [ ${#gcloud_nav_selected_items[@]} -eq 0 ]; then
      echo "🚫 Transfer cancelled"
      return
    fi
    step2_ok=true
  else
    if $imaginary_mode; then
      select_imaginary_items_common "$path" "$group_prefix" && step2_ok=true
    else
      local_navigator "source" "$path"
      if [ $? -eq 0 ] && [ ${#nav_selected_items[@]} -gt 0 ]; then
        selected_items=("${nav_selected_items[@]}")
        step2_ok=true
      fi
    fi
  fi

  if ! $step2_ok; then
    echo "🚫 Transfer cancelled — no items selected"
    return
  fi

  echo
  echo "📦 TRANSFER — Step 3: Choose destination"

  local dest_ok=false
  local final_dest=""

  case "$t_mode" in
  u|U) return ;;
  q|Q) _bvk_quit; return 1 ;;
    1)
      local_navigator "dest" "$HOME"
      if [ $? -eq 0 ]; then
        final_dest="$nav_result_path"
        dest_ok=true
      fi
      ;;
    2)
      local_navigator "dest" "${nav_last_browsed_path:-$path}"
      if [ $? -eq 0 ]; then
        final_dest="$nav_result_path"
        dest_ok=true
      fi
      ;;
    3)
      if ! command -v rclone >/dev/null 2>&1; then
        echo "❌ rclone not found in PATH."
        return
      fi
      final_dest="gdrive:/rclone"
      echo "📍 Destination: Google Drive ($final_dest)"
      dest_ok=true
      ;;
    4)
      if ! command -v gcloud >/dev/null 2>&1; then
        echo "❌ gcloud not found in PATH."
        return
      fi
      gcloud_navigator "dest"
      if [ $? -eq 0 ]; then
        final_dest="$gcloud_nav_result_path"
        dest_ok=true
      fi
      ;;
    5)
      local_navigator "dest" "$HOME"
      if [ $? -eq 0 ]; then
        final_dest="$nav_result_path"
        dest_ok=true
      fi
      ;;
  esac

  if ! $dest_ok || [ -z "$final_dest" ]; then
    echo "🚫 Transfer cancelled — no destination chosen"
    return
  fi

  _mc_header "📦 TRANSFER — Step 4: Action"
  if [[ "$t_mode" == "1" || "$t_mode" == "2" ]]; then
    _mc_keyed "c:Copy" "m:Move" "s:Shortcut"
  else
    _mc_keyed "c:Copy" "m:Move"
  fi
  _mc_footer "u:Back" "q:Quit"
  read -e -p "Select: " t_action

  local t_op
  case "$t_action" in
  u|U) return ;;
  q|Q) _bvk_quit; return 1 ;;
    c|C) t_op="copy" ;;
    m|M) t_op="move" ;;
    s|S)
      if [[ "$t_mode" == "1" || "$t_mode" == "2" ]]; then
        t_op="shortcut"
      else
        echo "❌ Shortcut is only available for intra-location transfers. Transfer cancelled."
        return
      fi
      ;;
    *)
      echo "❌ Invalid action. Transfer cancelled."
      return
      ;;
  esac

  echo
  echo "⚙️  Executing $t_op..."

  case "$t_mode" in
  u|U) return ;;
  q|Q) _bvk_quit; return 1 ;;
    1|2)
      if [ "$t_op" == "copy" ]; then
        perform_copy "$final_dest" "${selected_items[@]}"
      elif [ "$t_op" == "move" ]; then
        perform_move "$final_dest" "${selected_items[@]}"
      else
        perform_shortcut "$final_dest" "${selected_items[@]}"
        echo "💫 Shortcuts created → $final_dest"
      fi
      ;;
    3)
      local _mapper_script="${TMPDIR:-/tmp}/_rclone_mime_mapper.py"
      cat > "$_mapper_script" << 'MAPPER_EOF'
#!/usr/bin/env python3
import sys, json

# Mirrors _get_mime_type()'s extension table and dotfile rule:
#   name        -> no dot at all          -> no extension
#   .name       -> leading dot, no prefix -> no extension (whole thing is filename)
#   ..name      -> still no real prefix   -> no extension
#   prefix.ext  -> real prefix before dot -> extension is "ext"
EXT_MAP = {
    "js": "application/javascript", "mjs": "application/javascript",
    "ts": "application/typescript",
    "py": "application/x-python",
    "sh": "text/x-shellscript", "bash": "text/x-shellscript",
    "json": "application/json",
    "html": "application/html", "htm": "application/html",
    "css": "application/css",
    "md": "text/markdown", "markdown": "text/markdown",
    "txt": "text/plain",
    "csv": "text/csv",
    "xml": "application/xml",
    "pdf": "application/pdf",
    "png": "image/png",
    "jpg": "image/jpeg", "jpeg": "image/jpeg",
    "gif": "image/gif",
    "svg": "image/svg+xml",
    "webp": "image/webp",
    "mp3": "audio/mpeg",
    "mp4": "video/mp4",
    "zip": "application/zip",
    "tar": "application/x-tar",
    "gz": "application/gzip", "tgz": "application/gzip",
    "sql": "application/sql",
    "java": "text/x-java-source",
    "c": "application/x-c",
    "cpp": "application/x-c++", "cc": "application/x-c++", "cxx": "application/x-c++",
    "wasm": "application/wasm",
    "wat": "application/wat",
    "asm": "application/x-asm", "s": "application/x-asm",
    "go": "text/x-go",
    "rs": "text/x-rust",
    "php": "application/x-httpd-php",
    "rb": "text/x-ruby",
    "kt": "text/x-kotlin", "kts": "text/x-kotlin",
    "dart": "application/dart",
    "lua": "text/x-lua",
    "r": "text/x-r",
    "yaml": "text/yaml", "yml": "text/yaml",
    "toml": "text/x-toml",
    "ini": "text/plain", "cfg": "text/plain", "conf": "text/plain",
}

def mime_for(name, is_dir):
    if is_dir:
        return "inode/directory"
    base = name.rsplit("/", 1)[-1]
    stripped = base.lstrip(".")
    if "." not in stripped:
        return "application/octet-stream"
    ext = base.rsplit(".", 1)[-1].lower()
    return EXT_MAP.get(ext, "application/octet-stream")

def main():
    data = json.load(sys.stdin)
    is_dir = bool(data.get("IsDir", False))
    name = data.get("Remote") or data.get("Name") or ""
    mt = mime_for(name, is_dir)
    meta = data.get("Metadata") or {}
    if not is_dir:
        meta["content-type"] = mt
    data["Metadata"] = meta
    json.dump(data, sys.stdout)

if __name__ == "__main__":
    main()
MAPPER_EOF
      chmod +x "$_mapper_script"

      _lk_load
      for item in "${selected_items[@]}"; do
        local base
        base=$(basename "$item")
        local is_dir=false
        [ -d "$item" ] && is_dir=true

        if $is_dir; then
          local dir_root="$final_dest/$base"
          if rclone lsf "$dir_root" --files-only 2>/dev/null | grep -qx "$base"; then
            echo "🔴  Skipping $base — a file with this name already exists at destination, refusing to nest."
            continue
          fi
          local _op="$t_op"
          if [ "$_op" == "move" ] && _lk_is_protected "$item"; then
            _op=copy; echo "🔒 $base is locked (or holds locked items) — copying, local original kept"
          fi
          echo "📤 rclone $_op (dir, single call): $base → $dir_root/"
          if [ "$_op" == "copy" ]; then
            rclone copy "$item" "$dir_root" --progress \
              --metadata \
              --metadata-mapper "python3 $_mapper_script"
          else
            rclone move "$item" "$dir_root" --progress \
              --metadata \
              --metadata-mapper "python3 $_mapper_script"
          fi
        else
          local target_path="$final_dest/$base"
          if rclone lsf "$target_path" --dirs-only 2>/dev/null | grep -q .; then
            echo "🔴  Skipping $base — a folder with this exact name already exists at destination."
            continue
          fi
          local _op="$t_op"
          if [ "$_op" == "move" ] && _lk_is_protected "$item"; then
            _op=copy; echo "🔒 $base is locked — copying, local original kept"
          fi
          echo "📤 rclone $_op (file): $base → $target_path"
          if [ "$_op" == "copy" ]; then
            rclone copyto "$item" "$target_path" --progress \
              --metadata \
              --metadata-mapper "python3 $_mapper_script"
          else
            rclone moveto "$item" "$target_path" --progress \
              --metadata \
              --metadata-mapper "python3 $_mapper_script"
          fi
        fi
      done

      rm -f "$_mapper_script"
      echo "💫 Drive transfer complete"
      ;;
    4)
      echo "☁️  Transferring to GCloud Shell..."
      for item in "${selected_items[@]}"; do
        local base
        base=$(basename "$item")
        echo "📤 Sending $base → GCloud:$final_dest/"
        gcloud cloud-shell scp --recurse "localhost:$item" "cloudshell:$final_dest/"
        if [ $? -eq 0 ] && [ "$t_op" == "move" ]; then
          _lk_load
          if _lk_is_protected "$item"; then
            echo "  🔒 Kept local (locked, or holds locked items): $item  — copied, not moved"
          else
            rm -rf -- "$item" && _carry_forget "$item"
            echo "  🗑️  Removed local: $item"
          fi
        fi
      done
      echo "💫 Transfer to GCloud complete"
      ;;
    5)
      echo "☁️  Transferring from GCloud Shell to local..."
      for remote_item in "${gcloud_nav_selected_items[@]}"; do
        local base
        base=$(basename "$remote_item")
        echo "📥 Pulling $base → $final_dest/"
        gcloud cloud-shell scp --recurse "cloudshell:$remote_item" "localhost:$final_dest/"
        if [ $? -eq 0 ] && [ "$t_op" == "move" ]; then
          _gcloud_cmd "rm -rf '$remote_item'"
          echo "  🗑️  Removed from GCloud: $remote_item"
        fi
      done
      echo "💫 Transfer from GCloud complete"
      ;;
  esac

  selected_items=()
}
