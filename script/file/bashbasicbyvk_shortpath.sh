_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffer"

# ---------------------------------------------------------------------------
# up- / ups- / do-  — cloud upload + import, shared between local CLI and
# headless environments. Unlike copy (which prefers a local clipboard tool
# and only falls back to the cloud when headless), upload has no local
# equivalent — it always goes through the worker, so the same code path
# runs identically whether there's a TTY/clipboard available or not.
# ---------------------------------------------------------------------------
WORKER_URL="https://copy.bashbasics.workers.dev"
_SP_MAX_UPLOAD_BYTES=$((20*1024*1024))

# Copies a generated link to the clipboard (best effort, via OSC52 — works
# the same whether the terminal is local or headless/SSH'd into) and tries
# to open it in a browser. Never blocks or fails the upload if these don't work.
_announce_link() {
  local final_url="$1"
  local url_payload
  url_payload=$(printf "%s" "$final_url" | base64 | tr -d '\n')

  if [[ "$TERM" == "screen"* ]] || [[ "$TERM" == "tmux"* ]]; then
    printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$url_payload"
  else
    printf "\033]52;c;%s\a" "$url_payload"
  fi

  echo "✅ Link copied to clipboard (best effort)."
  echo "-------------------------------------------"
  echo "Link: $final_url"
  echo "-------------------------------------------"

  ( open "$final_url" || xdg-open "$final_url" || termux-open-url "$final_url" ) &> /dev/null &
}

# Walks selected paths (files and/or folders), attaching each file to a
# multipart PUT so the worker's /upload endpoint can rebuild the tree.
_up_do_multipart_upload() {
  local -a paths=("$@")
  local -a form_args=()
  local total_size=0 p file base rel sz

  for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
      base=$(basename -- "$p")
      while IFS= read -r -d '' file; do
        rel="${file#$p/}"
        form_args+=(-F "files=@${file};filename=${base}/${rel}")
        sz=$(stat -c%s "$file" 2>/dev/null || echo 0)
        total_size=$((total_size + sz))
      done < <(find "$p" -type f -print0)
    elif [ -f "$p" ]; then
      form_args+=(-F "files=@${p};filename=$(basename -- "$p")")
      sz=$(stat -c%s "$p" 2>/dev/null || echo 0)
      total_size=$((total_size + sz))
    else
      echo "  ⚠️  Skipping missing item: $p"
    fi
  done

  if [ ${#form_args[@]} -eq 0 ]; then
    echo "❌ No valid files found in selection"
    return 1
  fi

  if [ "$total_size" -gt "$_SP_MAX_UPLOAD_BYTES" ]; then
    echo "❌ Selection is $((total_size/1024/1024))MB — exceeds the 20MB upload limit"
    return 1
  fi

  echo "☁️  Uploading $(( ${#form_args[@]} )) file entr(y/ies)..."
  local response http_status final_url
  response=$(curl -s --fail -w "\n%{http_code}" -H "Expect:" -X PUT "${form_args[@]}" "$WORKER_URL/upload")
  http_status=$(echo "$response" | tail -n 1)
  final_url=$(echo "$response" | head -n 1)

  if [ "$http_status" == "201" ]; then
    _announce_link "$final_url"
  else
    echo "❌ Upload failed (HTTP $http_status)."
    return 1
  fi
}

# up-1,3,7 / up-1-3,7  — upload the selected items (files AND/OR folders)
# to the environment, preserving structure. Viewable/downloadable from any
# browser as a tree, or reimportable elsewhere via do-.
handle_up_upload() {
  local raw="$1"
  local itemlist="${raw#up-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: up-1,3,5  or  up-1-3,7  (files and folders both supported)"
    return
  fi
  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using up-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return
  _up_do_multipart_upload "${sp_resolved[@]}"
}

# ups-1,3,7 / ups-1-3,7  — upload the selected items merged into a SINGLE
# text file. Files only; refuses immediately if any selected item is a folder.
handle_ups_upload() {
  local raw="$1"
  local itemlist="${raw#ups-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: ups-1,3,5  or  ups-1-3,7  (files only — no folders)"
    return
  fi
  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using ups-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return

  local p
  for p in "${sp_resolved[@]}"; do
    if [ -d "$p" ]; then
      echo "❌ ups- doesn't support folder upload. Try up- instead."
      return 1
    fi
  done

  local tmp
  tmp=$(mktemp)
  for p in "${sp_resolved[@]}"; do
    if [ ! -f "$p" ]; then
      echo "  ⚠️  Skipping missing item: $p"
      continue
    fi
    echo "===== ${p##*/} =====" >> "$tmp"
    cat -- "$p" >> "$tmp"
    echo >> "$tmp"
  done

  if [ ! -s "$tmp" ]; then
    echo "❌ No valid files found in selection"
    rm -f "$tmp"
    return 1
  fi

  echo "☁️  Uploading ${#sp_resolved[@]} file(s) merged into a single text file..."
  local response http_status final_url
  response=$(curl -s --fail -w "\n%{http_code}" -H "Expect:" -X PUT --data-binary "@$tmp" "$WORKER_URL/copy")
  http_status=$(echo "$response" | tail -n 1)
  final_url=$(echo "$response" | head -n 1)
  rm -f "$tmp"

  if [ "$http_status" == "201" ]; then
    _announce_link "$final_url"
  else
    echo "❌ Upload failed (HTTP $http_status)."
    return 1
  fi
}

# do-  — paste a link generated by up-/ups- (or the old copy tool) and
# import its contents locally. Works identically in a local CLI or a
# headless/piped shell: interactive shells get a save-as prompt, non-TTY
# stdout just gets the raw content printed so it can be piped/captured.
# The remote copy is nuked automatically by the worker as soon as it's
# fetched (?raw=1 for text, /zip for file trees) — no separate delete needed.
handle_do_import() {
  read -p "🔗 Paste link to import: " link
  [ -z "$link" ] && echo "🚫 Cancelled" && return

  if [[ "$link" != http*://* ]]; then
    link="$WORKER_URL/$link"
  fi
  link="${link%/}"

  local tmp_headers tmp_body
  tmp_headers=$(mktemp)
  tmp_body=$(mktemp)

  local raw_url="$link?raw=1"
  local http_status
  http_status=$(curl -s -o "$tmp_body" -D "$tmp_headers" -w "%{http_code}" "$raw_url")

  if [ "$http_status" != "200" ]; then
    echo "❌ Link expired, invalid, or already nuked."
    rm -f "$tmp_headers" "$tmp_body"
    return 1
  fi

  local ctype
  ctype=$(grep -i '^content-type:' "$tmp_headers" | tail -1 | tr -d '\r' | cut -d' ' -f2-)
  rm -f "$tmp_headers"

  if [[ "$ctype" == application/json* ]]; then
    echo "📦 Multi-file link detected. Fetching archive..."
    local zip_status
    zip_status=$(curl -s -o "${tmp_body}.zip" -w "%{http_code}" "$link/zip")

    if [ "$zip_status" != "200" ]; then
      echo "❌ Failed to fetch archive (HTTP $zip_status)."
      rm -f "$tmp_body" "${tmp_body}.zip"
      return 1
    fi

    local dest="$path"
    if [ -t 0 ]; then
      read -p "📂 Extract into which folder? (blank = current dir: $path): " dest_in
      [ -n "$dest_in" ] && dest="$dest_in"
    fi
    mkdir -p "$dest"

    if command -v unzip &>/dev/null; then
      unzip -o -q "${tmp_body}.zip" -d "$dest"
      echo "✅ Imported files into: $dest"
    else
      cp "${tmp_body}.zip" "$dest/imported_files.zip"
      echo "⚠️  'unzip' not found — saved raw archive as: $dest/imported_files.zip"
    fi
    rm -f "$tmp_body" "${tmp_body}.zip"
  else
    echo "📄 Text link detected."
    if [ -t 1 ] && [ -t 0 ]; then
      read -p "💾 Save as filename in $path (blank = print to terminal): " fname
    else
      fname=""
    fi

    if [ -n "$fname" ]; then
      mv "$tmp_body" "$path/$fname"
      echo "✅ Imported as: $path/$fname"
    else
      cat "$tmp_body"
      rm -f "$tmp_body"
    fi
  fi
}

# Persistent buffers (c--, m--, s--) — survive after d- applies them
_SP_CP_FILE="${_SP_BUFFER_DIR}/copy.list"
_SP_MV_FILE="${_SP_BUFFER_DIR}/move.list"
_SP_SC_FILE="${_SP_BUFFER_DIR}/shortcut.list"

# One-time buffers (c-, m-, s-) — cleared immediately after d- applies them
_SP_CP_ONCE_FILE="${_SP_BUFFER_DIR}/copy.once.list"
_SP_MV_ONCE_FILE="${_SP_BUFFER_DIR}/move.once.list"
_SP_SC_ONCE_FILE="${_SP_BUFFER_DIR}/shortcut.once.list"

_sp_ensure_store() {
  mkdir -p "$_SP_BUFFER_DIR" 2>/dev/null
  [ -f "$_SP_CP_FILE" ] || : > "$_SP_CP_FILE"
  [ -f "$_SP_MV_FILE" ] || : > "$_SP_MV_FILE"
  [ -f "$_SP_SC_FILE" ] || : > "$_SP_SC_FILE"
  [ -f "$_SP_CP_ONCE_FILE" ] || : > "$_SP_CP_ONCE_FILE"
  [ -f "$_SP_MV_ONCE_FILE" ] || : > "$_SP_MV_ONCE_FILE"
  [ -f "$_SP_SC_ONCE_FILE" ] || : > "$_SP_SC_ONCE_FILE"
}

_sp_load() {
  local -n _sp_out="$1"
  local file="$2"
  _sp_out=()
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    _sp_out+=("$line")
  done < "$file"
}

_sp_save() {
  local -n _sp_in="$1"
  local file="$2"
  : > "$file"
  local entry
  for entry in "${_sp_in[@]}"; do
    [ -n "$entry" ] && printf '%s\n' "$entry" >> "$file"
  done
}

_sp_append() {
  local file="$1"; shift
  local -a existing=()
  _sp_load existing "$file"
  local added=0 dupes=0
  local p
  for p in "$@"; do
    if _in_selection "$p" "${existing[@]}"; then
      dupes=$((dupes+1))
    else
      existing+=("$p")
      added=$((added+1))
    fi
  done
  _sp_save existing "$file"
  echo "$added|$dupes|${#existing[@]}"
}

_sp_resolve_itemlist() {
  local itemlist="$1"
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available in current view to reference"
    return 1
  fi
  local indices
  indices=($(parse_selection "$itemlist" "${#items[@]}"))
  if [ ${#indices[@]} -eq 0 ]; then
    echo "❌ No valid item numbers in '$itemlist'"
    return 1
  fi
  sp_resolved=()
  local idx
  for idx in "${indices[@]}"; do
    sp_resolved+=("${items[$((idx-1))]}")
  done
  return 0
}

# Handles c-, m-, s- (one-time) AND c--, m--, s-- (persistent)
# Longer/more-specific prefixes ("--") are matched first.
handle_shortpath_stage() {
  local raw="$1"
  local prefix persistent label file itemlist

  case "$raw" in
    c--*) prefix="c--"; persistent=true;  label="COPY (persistent)";     file="$_SP_CP_FILE" ;;
    m--*) prefix="m--"; persistent=true;  label="MOVE (persistent)";     file="$_SP_MV_FILE" ;;
    s--*) prefix="s--"; persistent=true;  label="SHORTCUT (persistent)"; file="$_SP_SC_FILE" ;;
    c-*)  prefix="c-";  persistent=false; label="COPY (once)";           file="$_SP_CP_ONCE_FILE" ;;
    m-*)  prefix="m-";  persistent=false; label="MOVE (once)";           file="$_SP_MV_ONCE_FILE" ;;
    s-*)  prefix="s-";  persistent=false; label="SHORTCUT (once)";       file="$_SP_SC_ONCE_FILE" ;;
    *) return 1 ;;
  esac

  itemlist="${raw:${#prefix}}"

  _sp_ensure_store

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: ${prefix}1,3,5  or  ${prefix}1-7"
    return 0
  fi

  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view (group filter or forceshow) before using ${prefix} shortcuts."
    return 0
  fi

  _sp_resolve_itemlist "$itemlist" || return 0

  local result
  result=$(_sp_append "$file" "${sp_resolved[@]}")
  local added="${result%%|*}"
  local rest="${result#*|}"
  local dupes="${rest%%|*}"
  local total="${rest#*|}"

  local msg="📌 Buffered $added item(s) → $label"
  [ "$dupes" -gt 0 ] && msg="$msg (skipped $dupes already buffered)"

  local behavior
  if $persistent; then
    behavior="kept after d- applies it"
  else
    behavior="cleared automatically after d- applies it"
  fi

  echo "$msg — $label buffer now holds $total item(s). Use v- to review, d- to apply ($behavior)."
  return 0
}

_sp_op_label() {
  case "$1" in
    cp) echo "Copy" ;;
    mv) echo "Move" ;;
    sc) echo "Shortcut" ;;
  esac
}

_sp_apply_buffer() {
  local kind="$1" file="$2" dest="$3"
  local -a list=()
  _sp_load list "$file"
  [ ${#list[@]} -eq 0 ] && return 0

  local -a live=()
  local missing=0
  local p
  for p in "${list[@]}"; do
    if [ -e "$p" ]; then
      live+=("$p")
    else
      missing=$((missing+1))
      echo "  ⚠️  Skipping missing item (no longer exists): $p"
    fi
  done

  if [ ${#live[@]} -eq 0 ]; then
    echo "ℹ️  $(_sp_op_label "$kind") buffer had no valid items to apply"
    return 0
  fi

  echo "⚙️  Applying $(_sp_op_label "$kind") buffer (${#live[@]} item(s)) → $dest"
  case "$kind" in
    cp) perform_copy "$dest" "${live[@]}" ;;
    mv) perform_move "$dest" "${live[@]}" ;;
    sc) perform_shortcut "$dest" "${live[@]}" ;;
  esac
}

# d- : apply every non-empty buffer (persistent + one-time) to the current $path.
# Persistent buffers (--) are left intact. One-time buffers (-) are cleared right after applying.
handle_shortpath_dispatch() {
  _sp_ensure_store
  local dest="$path"

  local -a cp_list=() mv_list=() sc_list=()
  local -a cp_once=() mv_once=() sc_once=()
  _sp_load cp_list "$_SP_CP_FILE"
  _sp_load mv_list "$_SP_MV_FILE"
  _sp_load sc_list "$_SP_SC_FILE"
  _sp_load cp_once "$_SP_CP_ONCE_FILE"
  _sp_load mv_once "$_SP_MV_ONCE_FILE"
  _sp_load sc_once "$_SP_SC_ONCE_FILE"

  if [ ${#cp_list[@]} -eq 0 ] && [ ${#mv_list[@]} -eq 0 ] && [ ${#sc_list[@]} -eq 0 ] \
     && [ ${#cp_once[@]} -eq 0 ] && [ ${#mv_once[@]} -eq 0 ] && [ ${#sc_once[@]} -eq 0 ]; then
    echo "ℹ️  All buffers are empty — nothing to apply. Use c-/m-/s- (once) or c--/m--/s-- (persistent) to stage items first."
    return 0
  fi

  echo "📦 Destination: $dest"

  # Persistent buffers — applied, then left alone.
  [ ${#cp_list[@]} -gt 0 ] && _sp_apply_buffer cp "$_SP_CP_FILE" "$dest"
  [ ${#mv_list[@]} -gt 0 ] && _sp_apply_buffer mv "$_SP_MV_FILE" "$dest"
  [ ${#sc_list[@]} -gt 0 ] && _sp_apply_buffer sc "$_SP_SC_FILE" "$dest"

  # One-time buffers — applied, then wiped immediately.
  if [ ${#cp_once[@]} -gt 0 ]; then
    _sp_apply_buffer cp "$_SP_CP_ONCE_FILE" "$dest"
    : > "$_SP_CP_ONCE_FILE"
  fi
  if [ ${#mv_once[@]} -gt 0 ]; then
    _sp_apply_buffer mv "$_SP_MV_ONCE_FILE" "$dest"
    : > "$_SP_MV_ONCE_FILE"
  fi
  if [ ${#sc_once[@]} -gt 0 ]; then
    _sp_apply_buffer sc "$_SP_SC_ONCE_FILE" "$dest"
    : > "$_SP_SC_ONCE_FILE"
  fi

  echo "✅ Buffer apply complete. Persistent (--) buffers were kept. One-time (-) buffers were cleared."
}

# v- : view & manage all six buffers.
_sp_view_one_buffer() {
  local label="$1" file="$2"

  while true; do
    local -a list=()
    _sp_load list "$file"

    echo
    echo "📋 $label buffer (${#list[@]}):"
    if [ ${#list[@]} -eq 0 ]; then
      echo "  (empty)"
    else
      local i=1
      local p
      for p in "${list[@]}"; do
        local exists_tag=""
        [ ! -e "$p" ] && exists_tag="  ⚠️ missing"
        printf "  %2d) %s%s\n" "$i" "$p" "$exists_tag"
        i=$((i+1))
      done
    fi

    echo
    echo "r) Remove item(s)   x) Clear entire $label buffer   q) Back"
    read -p "$label buffer: " bv_choice

    case "$bv_choice" in
      r|R)
        if [ ${#list[@]} -eq 0 ]; then
          echo "⚠️  Nothing to remove"
          continue
        fi
        read -p "Item number(s) to remove (e.g. 1,3 or 2-4): " rm_input
        local rm_indices
        rm_indices=($(parse_selection "$rm_input" "${#list[@]}"))
        if [ ${#rm_indices[@]} -eq 0 ]; then
          echo "❌ No valid numbers entered"
          continue
        fi
        local -A to_remove=()
        local ri
        for ri in "${rm_indices[@]}"; do
          to_remove["$ri"]=1
        done
        local -a kept=()
        local j=1
        local p
        for p in "${list[@]}"; do
          [ -z "${to_remove[$j]+x}" ] && kept+=("$p")
          j=$((j+1))
        done
        _sp_save kept "$file"
        echo "✅ Removed ${#rm_indices[@]} item(s) from $label buffer"
        ;;
      x|X)
        read -p "Clear the entire $label buffer? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$file"
          echo "🗑️  $label buffer cleared"
        else
          echo "🚫 Cancelled"
        fi
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo "⚠️  Invalid choice"
        ;;
    esac
  done
}

handle_shortpath_view() {
  _sp_ensure_store
  while true; do
    local -a cp_list=() mv_list=() sc_list=()
    local -a cp_once=() mv_once=() sc_once=()
    _sp_load cp_list "$_SP_CP_FILE"
    _sp_load mv_list "$_SP_MV_FILE"
    _sp_load sc_list "$_SP_SC_FILE"
    _sp_load cp_once "$_SP_CP_ONCE_FILE"
    _sp_load mv_once "$_SP_MV_ONCE_FILE"
    _sp_load sc_once "$_SP_SC_ONCE_FILE"

    echo
    echo "🗂️  Shortpath buffers"
    echo "  1) Copy      persistent (--)  (${#cp_list[@]} item(s))"
    echo "  2) Move      persistent (--)  (${#mv_list[@]} item(s))"
    echo "  3) Shortcut  persistent (--)  (${#sc_list[@]} item(s))"
    echo "  4) Copy      once (-)         (${#cp_once[@]} item(s))"
    echo "  5) Move      once (-)         (${#mv_once[@]} item(s))"
    echo "  6) Shortcut  once (-)         (${#sc_once[@]} item(s))"
    echo "  a) Clear ALL buffers"
    echo "  q) Back"
    read -p "View buffer: " v_choice

    case "$v_choice" in
      1) _sp_view_one_buffer "Copy (persistent)"     "$_SP_CP_FILE" ;;
      2) _sp_view_one_buffer "Move (persistent)"     "$_SP_MV_FILE" ;;
      3) _sp_view_one_buffer "Shortcut (persistent)" "$_SP_SC_FILE" ;;
      4) _sp_view_one_buffer "Copy (once)"           "$_SP_CP_ONCE_FILE" ;;
      5) _sp_view_one_buffer "Move (once)"           "$_SP_MV_ONCE_FILE" ;;
      6) _sp_view_one_buffer "Shortcut (once)"       "$_SP_SC_ONCE_FILE" ;;
      a|A)
        read -p "Clear ALL six buffers? This can't be undone. (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$_SP_CP_FILE"
          : > "$_SP_MV_FILE"
          : > "$_SP_SC_FILE"
          : > "$_SP_CP_ONCE_FILE"
          : > "$_SP_MV_ONCE_FILE"
          : > "$_SP_SC_ONCE_FILE"
          echo "🗑️  All buffers cleared"
        else
          echo "🚫 Cancelled"
        fi
        ;;
      q|Q|"")
        return 0
        ;;
      *)
        echo "⚠️  Invalid choice"
        ;;
    esac
  done
}
