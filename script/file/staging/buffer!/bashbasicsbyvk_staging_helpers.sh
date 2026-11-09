_SP_BUFFER_DIR="${HOME}/.bashbasicsbyvk/buffer"

# Five buffers (op: cp mv sc bm sl), each "persistent" (c--) and "once" (c-).  Prefixes: c- copy · m- move · k- shortcut · b- bookmark · s- select.
_SP_CP_FILE="${_SP_BUFFER_DIR}/copy.list"
_SP_MV_FILE="${_SP_BUFFER_DIR}/move.list"
_SP_SC_FILE="${_SP_BUFFER_DIR}/shortcut.list"
_SP_BM_FILE="${_SP_BUFFER_DIR}/bookmark.list"
_SP_SL_FILE="${_SP_BUFFER_DIR}/select.list"

_SP_CP_ONCE_FILE="${_SP_BUFFER_DIR}/copy.once.list"
_SP_MV_ONCE_FILE="${_SP_BUFFER_DIR}/move.once.list"
_SP_SC_ONCE_FILE="${_SP_BUFFER_DIR}/shortcut.once.list"
_SP_BM_ONCE_FILE="${_SP_BUFFER_DIR}/bookmark.once.list"
_SP_SL_ONCE_FILE="${_SP_BUFFER_DIR}/select.once.list"

# The buffers that d- applies at a destination (select sets are not applied: fx → <action>.selected.items uses them).
_SP_APPLY_OPS=(cp mv sc bm)

# _sp_file_for <op> <persistent: true|false>  → the buffer file;   _sp_op_pfx <op> → c m k b s;   _sp_op_label <op> → Copy Move ...
_sp_file_for() {
  local v="_SP_${1^^}_FILE"
  [ "$2" = true ] || v="_SP_${1^^}_ONCE_FILE"
  printf '%s' "${!v}"
}
_sp_op_pfx() {
  case "$1" in cp) echo c ;; mv) echo m ;; sc) echo k ;; bm) echo b ;; sl) echo s ;; esac
}
_sp_op_label() {
  case "$1" in
    cp) echo "Copy" ;;
    mv) echo "Move" ;;
    sc) echo "Shortcut" ;;
    bm) echo "Bookmark" ;;
    sl) echo "Select" ;;
  esac
}

_sp_ensure_store() {
  mkdir -p "$_SP_BUFFER_DIR" 2>/dev/null
  local op f
  for op in cp mv sc bm sl; do
    f=$(_sp_file_for "$op" true);  [ -f "$f" ] || : > "$f"
    f=$(_sp_file_for "$op" false); [ -f "$f" ] || : > "$f"
  done
}

# ── what a buffer file holds ─────────────────────────────────────────────────────────────────────────────
#  One line per item.  A plain path is an UNNAMED ("flat") item.  A NAMED set's items are written
#      @<name><TAB><path>
#  (c-1,3 as set1).  Every path is absolute, so a line that starts with @ + has a TAB is never a plain path.
#  _sp_load gives the paths of ALL lines (names dropped) — what every older caller wanted.
_sp_split_line() {            # → _SP_LN_NAME ("" = unnamed) and _SP_LN_PATH
  if [[ "$1" == @*$'\t'* ]]; then
    _SP_LN_NAME="${1#@}"; _SP_LN_NAME="${_SP_LN_NAME%%$'\t'*}"; _SP_LN_PATH="${1#*$'\t'}"
  else
    _SP_LN_NAME=""; _SP_LN_PATH="$1"
  fi
}

_sp_load() {
  local -n _sp_out="$1"
  local file="$2"
  _sp_out=()
  [ -f "$file" ] || return 0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    _sp_split_line "$line"
    _sp_out+=("$_SP_LN_PATH")
  done < "$file"
}

# _sp_load_lines <array> <file>   the raw lines (names kept) — for code that rewrites the file (_sp_save writes lines as they are)
_sp_load_lines() {
  local -n _sp_lo="$1"
  local file="$2" l
  _sp_lo=()
  [ -f "$file" ] || return 0
  while IFS= read -r l; do [ -n "$l" ] && _sp_lo+=("$l"); done < "$file"
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

# _sp_names <array> <file>   the set names in the file, in the order they first appear
_sp_names() {
  local -n _sp_nm="$1"
  local file="$2" l
  local -A seen=()
  _sp_nm=()
  [ -f "$file" ] || return 0
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ -n "$_SP_LN_NAME" ] && [ -z "${seen[$_SP_LN_NAME]+x}" ] && { seen[$_SP_LN_NAME]=1; _sp_nm+=("$_SP_LN_NAME"); }
  done < "$file"
}

# _sp_load_set <array> <file> <name>   the paths of ONE set ("" = the unnamed, flat items)
_sp_load_set() {
  local -n _sp_ls="$1"
  local file="$2" want="$3" l
  _sp_ls=()
  [ -f "$file" ] || return 0
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ "$_SP_LN_NAME" = "$want" ] && _sp_ls+=("$_SP_LN_PATH")
  done < "$file"
}

_sp_has_name() { local -a _n=(); _sp_names _n "$1"; local x; for x in "${_n[@]}"; do [ "$x" = "$2" ] && return 0; done; return 1; }

# _sp_names_csv <csv>  → _SP_WANT (assoc: name → 1).  "set1, set2" and "set1,set2" are the same.
declare -gA _SP_WANT=()
_sp_names_csv() {
  local csv="$1" n
  _SP_WANT=()
  local -a parts=()
  IFS=',' read -ra parts <<< "$csv"
  for n in "${parts[@]}"; do
    n="${n#"${n%%[![:space:]]*}"}"; n="${n%"${n##*[![:space:]]}"}"
    [ -n "$n" ] && _SP_WANT["$n"]=1
  done
}

# _sp_load_apply <array> <file> [names-csv]   the paths d- applies: every line, or only the lines of the named sets; each path once
_sp_load_apply() {
  local -n _sp_la="$1"
  local file="$2" l
  local -A seen=()
  _sp_la=()
  [ -f "$file" ] || return 0
  [ -n "${3:-}" ] && _sp_names_csv "$3"
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    if [ -n "${3:-}" ]; then [ -n "$_SP_LN_NAME" ] && [ -n "${_SP_WANT[$_SP_LN_NAME]+x}" ] || continue; fi
    [ -n "${seen[$_SP_LN_PATH]+x}" ] && continue
    seen[$_SP_LN_PATH]=1
    _sp_la+=("$_SP_LN_PATH")
  done < "$file"
}

# _sp_drop <file> <names-csv>   remove the lines of those sets (names-csv empty = remove everything)
_sp_drop() {
  local file="$1" l
  if [ -z "${2:-}" ]; then : > "$file"; return 0; fi
  _sp_names_csv "$2"
  local -a keep=()
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ -n "$_SP_LN_NAME" ] && [ -n "${_SP_WANT[$_SP_LN_NAME]+x}" ] && continue
    keep+=("$l")
  done < "$file"
  _sp_save keep "$file"
}

# _sp_drop_unnamed <file>   remove the flat (unnamed) items only
_sp_drop_unnamed() {
  local file="$1" l
  local -a keep=()
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ -n "$_SP_LN_NAME" ] && keep+=("$l")
  done < "$file"
  _sp_save keep "$file"
}

# _sp_rename_set <file> <old> <new>   ("" as <old> = give the flat items a name).  The caller has already settled what happens when <new>
# exists (add = the two sets merge: a path that is then in it twice is kept once).
_sp_rename_set() {
  local file="$1" old="$2" new="$3" l out_l
  local -A seen=()
  local -a out=()
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    out_l="$l"
    [ "$_SP_LN_NAME" = "$old" ] && out_l="@${new}"$'\t'"$_SP_LN_PATH"
    [ -n "${seen[$out_l]+x}" ] && continue
    seen[$out_l]=1
    out+=("$out_l")
  done < "$file"
  _sp_save out "$file"
}

# _sp_drop_items <file> <name> <numbers...>   remove the 1-based items of ONE set ("" = the flat items)
_sp_drop_items() {
  local file="$1" name="$2" l n=0 x; shift 2
  local -A gone=()
  local -a keep=()
  for x in "$@"; do gone[$x]=1; done
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    if [ "$_SP_LN_NAME" = "$name" ]; then
      n=$((n+1))
      [ -n "${gone[$n]+x}" ] && continue
    fi
    keep+=("$l")
  done < "$file"
  _sp_save keep "$file"
}

# _sp_drop_paths <file> <paths...>   remove every line (named or not) whose path is one of these — used when an fx action has taken items out of a select set
_sp_drop_paths() {
  local file="$1" l p; shift
  local -A gone=()
  local -a keep=()
  for p in "$@"; do gone["$p"]=1; done
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ -n "${gone[$_SP_LN_PATH]+x}" ] && continue
    keep+=("$l")
  done < "$file"
  _sp_save keep "$file"
}

# _sp_drop_unnamed_paths <file> <paths...>   remove the UNNAMED lines whose path is one of these (named sets are not touched)
_sp_drop_unnamed_paths() {
  local file="$1" l p; shift
  local -A gone=()
  local -a keep=()
  [ -f "$file" ] || return 0
  for p in "$@"; do gone["$p"]=1; done
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ -z "$_SP_LN_NAME" ] && [ -n "${gone[$_SP_LN_PATH]+x}" ] && continue
    keep+=("$l")
  done < "$file"
  _sp_save keep "$file"
}

# _sp_count <file> [names-csv]   how many items (all lines, or those of the named sets)
_sp_count() {
  local file="$1" n=0 l
  [ -f "$file" ] || { echo 0; return; }
  if [ -z "${2:-}" ]; then n=$(grep -c '.' "$file" 2>/dev/null); echo "${n:-0}"; return; fi
  _sp_names_csv "$2"
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    _sp_split_line "$l"
    [ -n "$_SP_LN_NAME" ] && [ -n "${_SP_WANT[$_SP_LN_NAME]+x}" ] && n=$((n+1))
  done < "$file"
  echo "$n"
}

# _sp_append_as <file> <name> <paths...>   add the paths to the set <name> ("" = unnamed); a path already in THAT set is skipped.
# prints  added|dupes|total   (total = every item in the file)
_sp_append_as() {
  local file="$1" name="$2"; shift 2
  local l p added=0 dupes=0 total=0
  local -A have=()
  local -a fresh=()
  if [ -f "$file" ]; then
    while IFS= read -r l; do
      [ -z "$l" ] && continue
      total=$((total+1))
      _sp_split_line "$l"
      [ "$_SP_LN_NAME" = "$name" ] && have["$_SP_LN_PATH"]=1
    done < "$file"
  fi
  for p in "$@"; do
    [ -z "$p" ] && continue
    if [ -n "${have[$p]+x}" ]; then
      dupes=$((dupes+1))
    else
      have["$p"]=1
      if [ -n "$name" ]; then fresh+=("@${name}"$'\t'"$p"); else fresh+=("$p"); fi
      added=$((added+1))
    fi
  done
  [ ${#fresh[@]} -gt 0 ] && printf '%s\n' "${fresh[@]}" >> "$file"
  echo "$added|$dupes|$((total+added))"
}

_sp_append() {
  local file="$1"; shift
  _sp_append_as "$file" "" "$@"
}

# Parse an "all-except" itemlist of the form  a-<exclusions>
# e.g.  a-1-5,7  → all indices except 1,2,3,4,5,7
# Returns a space-separated list of 1-based indices.
_sp_parse_all_except() {
  local spec="$1"    # the part after "a-", e.g. "1-5,7"
  local total="$2"   # total number of items

  local -a excluded=()
  IFS=',' read -ra parts <<< "$spec"
  local part
  for part in "${parts[@]}"; do
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}"
      local i
      for (( i=lo; i<=hi; i++ )); do
        excluded+=("$i")
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      excluded+=("$part")
    fi
  done

  # Build exclusion lookup
  local -A excl_set=()
  local e
  for e in "${excluded[@]}"; do
    excl_set["$e"]=1
  done

  local result=()
  local i
  for (( i=1; i<=total; i++ )); do
    [ -z "${excl_set[$i]+x}" ] && result+=("$i")
  done

  echo "${result[*]}"
}

# ─────────────────────────────────────────────
#  Guard helpers (shared by stage + fileapi handlers)
# ─────────────────────────────────────────────

# Guard: reject empty itemlist or imaginary_mode, then resolve.
# Usage: _sp_guard_and_resolve "$itemlist" "$pfx"  || return 0
# On success, sp_resolved is populated.
_sp_guard_and_resolve() {
  local itemlist="$1" pfx="$2"
  if [ -z "$itemlist" ]; then
    echo "🔴  Usage: ${pfx}1,3,5  or  ${pfx}1-7  or  ${pfx}a-1-5,7"
    return 1
  fi
  if $imaginary_mode; then
    echo "🔴  Too many items to index directly — narrow the view (group filter or forceshow) before using ${pfx} shortcuts."
    return 1
  fi
  _sp_resolve_itemlist "$itemlist"
}

# Files-only pick for the commands that cannot work on a folder (i-  xtr-).
# Usage: _sp_files_only "$itemlist" "$pfx" "$LABEL" "can't be extracted"  || return 0
#   itemlist  what was typed after the prefix (1,3  1-5  a  a-2). EMPTY = ask now with the shared item picker (the one `d` uses).
#   A folder in the pick refuses the WHOLE pick: "<names> are folders, which can't be extracted." (nothing runs, pick again).
# On success sp_files[] holds the file paths.
_sp_files_only() {
  local raw="$1" pfx="$2" label="$3" whynot="$4" p n=0 shown=""
  local -a dirs=() odd=()
  sp_files=()
  if [ -z "$raw" ]; then
    if $imaginary_mode; then select_imaginary_items_common "$path" "$group_prefix" "$label" || return 1
    else select_items_common "$label" allow_a || return 1; fi
    sp_resolved=("${selected_items[@]}")
  else
    _sp_guard_and_resolve "$raw" "$pfx" || return 1
  fi
  for p in "${sp_resolved[@]}"; do
    if [ -d "$p" ]; then dirs+=("${p##*/}")
    elif [ -f "$p" ]; then sp_files+=("$p")
    else odd+=("${p##*/}"); fi
  done
  if [ ${#dirs[@]} -gt 0 ]; then
    for p in "${dirs[@]:0:5}"; do shown+="${shown:+, }$p"; done
    [ ${#dirs[@]} -gt 5 ] && shown+=" … and $(( ${#dirs[@]} - 5 )) more"
    if [ ${#dirs[@]} -eq 1 ]; then echo "🔴  $shown is a folder, which $whynot."
    else echo "🔴  $shown are folders, which $whynot."; fi
    sp_files=(); return 1
  fi
  if [ ${#odd[@]} -gt 0 ]; then
    echo "🔴  ${odd[*]:0:5}: not a regular file — nothing done."
    sp_files=(); return 1
  fi
  [ ${#sp_files[@]} -gt 0 ] || { echo "❌ No files selected"; return 1; }
  return 0
}

# ─────────────────────────────────────────────
#  Named sets:  c-1,3 as set1  — what happens when the name is already taken
# ─────────────────────────────────────────────

# Settings → Buffers keep one rule per buffer:  buffer_conflict_<op> = add | replace | deny | ask   (default ask)
_sp_conflict_mode() {
  local v="buffer_conflict_$1"
  v="${!v:-ask}"
  [[ "$v" =~ ^(add|replace|deny|ask)$ ]] || v=ask
  printf '%s' "$v"
}

# _sp_conflict_decide <op> <file> <name>
#   Settles the case "a set called <name> is already in <file>".  Sets _SP_CF = add | replace and _SP_CF_NAME (the name to use —
#   the user may pick another one).  Returns 1 when the operation is denied or cancelled (the message is printed).
#   add = put the new items into the existing set · replace = the new items take the place of the old ones · deny = keep as it is
_SP_CF=""; _SP_CF_NAME=""
_sp_conflict_decide() {
  local op="$1" file="$2" mode ans n
  local -a have=()
  _SP_CF=add; _SP_CF_NAME="$3"
  while _sp_has_name "$file" "$_SP_CF_NAME"; do
    mode=$(_sp_conflict_mode "$op")
    case "$mode" in
      add)     _SP_CF=add;     return 0 ;;
      replace) _SP_CF=replace; return 0 ;;
      deny)    echo "🚫 A set named '$_SP_CF_NAME' already exists in the $(_sp_op_label "$op") buffer — nothing changed  (Settings → Buffers)."; return 1 ;;
    esac
    _sp_load_set have "$file" "$_SP_CF_NAME"
    # one menu (never a one-line "Choose [1/2/3/n]"): u / q back out of the whole flow like every other menu
    _bvk_menu ans -t "Name already used" -i "⚠️" -d 3 \
      -q "A set named '$_SP_CF_NAME' already exists in the $(_sp_op_label "$op") buffer (${#have[@]} item(s))." \
      "1:Add to it" "2:Replace it with the new items" "3:Deny — keep it as it is" "n:Use another name" || return 1
    [ "${_CM_ABORT:-0}" = 1 ] && return 1
    case "${ans,,}" in
      1) _SP_CF=add;     return 0 ;;
      2) _SP_CF=replace; return 0 ;;
      3) echo "🚫 Cancelled — nothing changed."; return 1 ;;
      n) read -e -r -p "New name: " n
         [ "${_CM_ABORT:-0}" = 1 ] && return 1
         n="${n#"${n%%[![:space:]]*}"}"; n="${n%"${n##*[![:space:]]}"}"
         if _bb_alias_ok "$n"; then _SP_CF_NAME="$n"
         else echo "🔴  A name may use letters, digits, spaces and . _ @ + -  (1-48 characters)."; fi ;;
      *) _bvk_invalid ;;
    esac
  done
  _SP_CF=add
  return 0
}

# ─────────────────────────────────────────────
#  Shared stage / apply logic
# ─────────────────────────────────────────────

# Stage items into any op buffer.
# Usage: _sp_stage_buffer <op> <persistent> <itemlist> [name]
#   op: cp | mv | sc | bm | sl      name: from  "<itemlist> as <name>"  (empty = the flat, unnamed items)
_sp_stage_buffer() {
  local op="$1" persistent="$2" itemlist="$3" name="${4:-}"
  local file pfx label
  file=$(_sp_file_for "$op" "$persistent")
  pfx="$(_sp_op_pfx "$op")"; label="$(_sp_op_label "$op")"; label="${label^^}"
  if $persistent; then pfx="${pfx}--"; label="$label (persistent)"
  else                 pfx="${pfx}-";  label="$label (once)"
  fi

  _sp_ensure_store
  _sp_guard_and_resolve "$itemlist" "$pfx" || return 0

  if [ -n "$name" ]; then
    _sp_conflict_decide "$op" "$file" "$name" || return 0
    name="$_SP_CF_NAME"
    [ "$_SP_CF" = replace ] && _sp_drop "$file" "$name"
  fi

  local result
  result=$(_sp_append_as "$file" "$name" "${sp_resolved[@]}")
  local added="${result%%|*}"
  local rest="${result#*|}"
  local dupes="${rest%%|*}"
  local total="${rest#*|}"

  local msg="📌 Buffered $added item(s) → $label"
  [ -n "$name" ] && msg="$msg as '$name'"
  [ "$dupes" -gt 0 ] && msg="$msg (skipped $dupes already buffered)"

  local behavior use
  if [ "$op" = sl ]; then
    use="fx → <action>.selected.items to use it"
    if $persistent; then behavior="kept after it is used"; else behavior="cleared once it is used"; fi
  else
    use="d-${name:+ $name} to apply"
    if $persistent; then behavior="kept after d- applies it"; else behavior="cleared automatically after d- applies it"; fi
  fi

  echo "$msg — $label buffer now holds $total item(s). Use v- to review, $use ($behavior)."
}

# Apply any op buffer to a destination directory.
# Usage: _sp_apply_buffer <op> <file> <dest> [names-csv]
#   op: cp | mv | sc      names-csv: only these named sets (d- set1,set2); empty = everything in the buffer
_sp_apply_buffer() {
  local op="$1" file="$2" dest="$3" names="${4:-}"
  local label
  label=$(_sp_op_label "$op")   # "Copy" | "Move" | "Shortcut" | "Bookmark"

  local -a list=()
  _sp_load_apply list "$file" "$names"
  [ ${#list[@]} -eq 0 ] && return 0

  # cp/mv: pass the full list — perform_* count it and report missing/failed
  # items in their own compact summary. sc: skip missing items up front.
  case "$op" in
    cp) perform_copy "$dest" "${list[@]}"; return ;;
    mv) perform_move "$dest" "${list[@]}"; return ;;
  esac

  local -a live=()
  local p
  for p in "${list[@]}"; do
    if [ -e "$p" ]; then
      live+=("$p")
    else
      echo "  🔴  Skipping missing item (no longer exists): $p"
    fi
  done

  if [ ${#live[@]} -eq 0 ]; then
    echo "📜  $label buffer had no valid items to apply"
    return 0
  fi

  echo "⚙️  Applying $label buffer (${#live[@]} item(s)) → $dest"
  case "$op" in
    sc) perform_shortcut "$dest" "${live[@]}" ;;
  esac
}

# Resolve an itemlist string (supports "a-<spec>" for all-except) against
# the global $items array.  Populates the global sp_resolved array.
_sp_resolve_itemlist() {
  local itemlist="$1"
  if [ ${#items[@]} -eq 0 ]; then
    echo "❌ No items available in current view to reference"
    return 1
  fi

  local indices=()

  # Bare "a" = select all items
  if [[ "$itemlist" == "a" ]]; then
    indices=($(seq 1 "${#items[@]}"))

  # All-except syntax:  a-<exclusion-spec>
  elif [[ "$itemlist" =~ ^a-(.+)$ ]]; then
    local excl_spec="${BASH_REMATCH[1]}"
    indices=($(_sp_parse_all_except "$excl_spec" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ All-except filter excluded every item (spec: '$excl_spec')"
      return 1
    fi
  else
    indices=($(parse_selection "$itemlist" "${#items[@]}"))
    if [ ${#indices[@]} -eq 0 ]; then
      echo "❌ No valid item numbers in '$itemlist'"
      return 1
    fi
  fi

  sp_resolved=()
  local idx
  for idx in "${indices[@]}"; do
    sp_resolved+=("${items[$((idx-1))]}")
  done
  return 0
}
