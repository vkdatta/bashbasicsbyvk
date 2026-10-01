#!/usr/bin/env bash
# bashbasicsbyvk_favourites.sh — per-folder favourites (the third view mode)
# ════════════════════════════════════════════════════════════════════════════
#  MODES  (priority, highest first)
#     ⭐ favourite   a folder that has favourites shows ONLY those
#     🗂️ imaginary   folder too big → grouped view             (fs = show normal)
#     📁 normal
#  ns  = leave favourite mode for this visit (ns again = back).  fs  = leave
#  imaginary mode.  Each override peels one mode:  ns, then fs, shows it all.
#
#  OUTER LOOP  (display + add only)
#     fa 3,5,7-9      numbers / ranges     fa a   fa a-1-4   (all / all except)
#     fa sel          the current .s selection (direct children of this folder)
#     fa .s.ext svg & .s.sw icon_1        any .s expression — no need to list
#                                         200k items first
#  INSIDE sw → ⭐ Favourites tab  (manage this folder's favourites)
#     N open/go   b remove   rn rename (alias)   e edit the file
#
#  STORAGE   ~/.bashbasicsbyvk/favourites/<hash>.fav   (plain text, one per folder)
#        PATH=/home/me/icons
#        DIR_ID=64768:1234                 ← the folder's identity
#        icon_01.png #id=64768:99
#        big-logo.svg => Logo #id=64768:100     (name => alias)
#        old.png #id=64768:101 #moved=/home/me/archive/old.png   (set by the daemon)
#  Every favourite remembers the item's inode (#id) and the folder remembers its
#  own (DIR_ID), so renaming an item OR the folder keeps the favourites attached.
#  Items that vanish are kept and shown as ⚠️ missing — never auto-deleted.
#  The daemon (bashbasicsbyvk_recents_daemon) keeps this file in step in the
#  background — renames, folder renames, and moves to other folders (#moved=).
#  Both sides write atomically and share one lock:  favourites/.lock
# ════════════════════════════════════════════════════════════════════════════

_FAV_DIR="${HOME}/.bashbasicsbyvk/favourites"

declare -gA _FAV_LABEL=()          # full path → text shown instead of the plain name
declare -ga _fav_names=() _fav_alias=() _fav_ids=() _fav_stale=() _fav_moved=()
declare -gA _FAV_MOVED_TO=()       # missing item path → where it moved to (sw ⭐ tab)
_FAV_FILE=""
_fav_base=""                        # folder the arrays belong to
_fav_dirty=false
_fav_cache_key=""
_fav_on=false                       # favourite mode is showing right now
_fav_has=false                      # this folder has ≥1 live favourite
_ns_on=false                        # user paused favourite mode for this visit
_fav_banner=""
_fav_last_path=""

# ── small helpers ─────────────────────────────────────────────────────────────
_fav_id() {                         # dev:inode of a path
  local i
  i=$(stat -c '%d:%i' -- "$1" 2>/dev/null) || i=$(stat -f '%d:%i' -- "$1" 2>/dev/null) || i=""
  printf '%s' "$i"
}

# change fingerprint: nanosecond mtime + size (whole-second mtime can miss edits
# made within the same second — e.g. by the daemon or a hand edit)
_fav_mtime() {
  stat -c '%.9Y:%s' -- "$1" 2>/dev/null || stat -c '%Y:%s' -- "$1" 2>/dev/null \
    || stat -f '%m:%z' -- "$1" 2>/dev/null || echo 0
}

_fav_hash() {
  if   command -v sha1sum >/dev/null 2>&1; then printf '%s' "$1" | sha1sum | cut -c1-16
  elif command -v md5sum  >/dev/null 2>&1; then printf '%s' "$1" | md5sum  | cut -c1-16
  else printf '%s' "$1" | cksum | tr ' ' '_'; fi
}

_fav_norm() { local d="${1%/}"; [ -z "$d" ] && d="/"; printf '%s' "$d"; }
_fav_join() { local b="${1%/}"; printf '%s/%s' "$b" "$2"; }

# ── lock shared with the daemon (mkdir is atomic) ─────────────────────────────
_FAV_LOCK_DEPTH=0
_FAV_LOCK_OWN=false
_fav_lock() {
  if [ "$_FAV_LOCK_DEPTH" -gt 0 ]; then _FAV_LOCK_DEPTH=$(( _FAV_LOCK_DEPTH + 1 )); return 0; fi
  mkdir -p "$_FAV_DIR" 2>/dev/null
  local lk="$_FAV_DIR/.lock" tries=0 age
  _FAV_LOCK_OWN=false
  while true; do
    if mkdir "$lk" 2>/dev/null; then _FAV_LOCK_OWN=true; break; fi
    age=$(( $(date +%s) - $(stat -c %Y "$lk" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 10 ]; then rmdir "$lk" 2>/dev/null; continue; fi     # abandoned
    tries=$(( tries + 1 ))
    [ "$tries" -ge 30 ] && break                                          # ~3s, then go ahead
    sleep 0.1
  done
  _FAV_LOCK_DEPTH=1
}
_fav_unlock() {
  [ "$_FAV_LOCK_DEPTH" -gt 0 ] || return 0
  _FAV_LOCK_DEPTH=$(( _FAV_LOCK_DEPTH - 1 ))
  if [ "$_FAV_LOCK_DEPTH" -eq 0 ] && $_FAV_LOCK_OWN; then rmdir "$_FAV_DIR/.lock" 2>/dev/null; _FAV_LOCK_OWN=false; fi
}

# ── locate the .fav file for a folder (adopting it if the folder was renamed) ─
# Sets _FAV_FILE. Returns 0 when the file exists, 1 otherwise.
_fav_file_for() {
  local dir; dir=$(_fav_norm "$1")
  _FAV_FILE="$_FAV_DIR/$(_fav_hash "$dir").fav"
  [ -f "$_FAV_FILE" ] && return 0
  local -a all=("$_FAV_DIR"/*.fav)
  [ ${#all[@]} -eq 0 ] && return 1
  local did; did=$(_fav_id "$dir")
  [ -z "$did" ] && return 1
  local hit oldp
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    oldp=$(grep -m1 '^PATH=' "$hit" 2>/dev/null); oldp="${oldp#PATH=}"
    [ -d "$oldp" ] && [ "$(_fav_id "$oldp")" = "$did" ] && [ "$oldp" != "$dir" ] && continue  # still reachable elsewhere
    mv -- "$hit" "$_FAV_FILE" 2>/dev/null || continue
    _fav_dirty=true                                 # PATH= line gets rewritten on save
    _fav_adopted=true
    return 0
  done < <(grep -l -x -F "DIR_ID=$did" "${all[@]}" 2>/dev/null)
  return 1
}

# ── load + reconcile ──────────────────────────────────────────────────────────
# _fav_load <dir>   fills _fav_* arrays. Returns 1 if the folder has no favourites.
_fav_adopted=false
_fav_load() {
  local dir; dir=$(_fav_norm "$1")
  _fav_adopted=false
  local existed=true
  _fav_file_for "$dir" || existed=false
  local key="$dir|$(_fav_mtime "$_FAV_FILE")|$(_fav_mtime "$dir")"
  if $existed && [ "$key" = "$_fav_cache_key" ] && [ "$_fav_base" = "$dir" ]; then
    return 0
  fi
  _fav_names=(); _fav_alias=(); _fav_ids=(); _fav_stale=(); _fav_moved=()
  _fav_base="$dir"; _fav_dirty=false
  $_fav_adopted && _fav_dirty=true
  if ! $existed; then _fav_cache_key=""; return 1; fi

  local line name alias id moved
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    case "$line" in \#*|PATH=*|DIR_ID=*) continue ;; esac
    id=""; alias=""; moved=""
    if [[ "$line" == *" #moved="* ]]; then moved="${line##* #moved=}"; line="${line% #moved=*}"; fi
    if [[ "$line" == *" #id="* ]]; then id="${line##* #id=}"; line="${line% #id=*}"; fi
    if [[ "$line" == *" => "* ]]; then alias="${line#* => }"; line="${line%% => *}"; fi
    name="$line"
    [ -z "$name" ] && continue
    _fav_names+=("$name"); _fav_alias+=("$alias"); _fav_ids+=("$id"); _fav_stale+=(0); _fav_moved+=("$moved")
  done < "$_FAV_FILE"

  # reconcile with what is actually on disk
  local i p cur ino hit
  for i in "${!_fav_names[@]}"; do
    p=$(_fav_join "$dir" "${_fav_names[$i]}")
    if [ -e "$p" ] || [ -L "$p" ]; then
      cur=$(_fav_id "$p")
      if [ -n "$cur" ] && [ "$cur" != "${_fav_ids[$i]}" ]; then _fav_ids[$i]="$cur"; _fav_dirty=true; fi
      if [ -n "${_fav_moved[$i]}" ]; then _fav_moved[$i]=""; _fav_dirty=true; fi     # it is back
    elif [ -n "${_fav_ids[$i]}" ]; then
      ino="${_fav_ids[$i]#*:}"
      hit=$(find "$dir" -maxdepth 1 -inum "$ino" -print -quit 2>/dev/null)
      if [ -n "$hit" ]; then _fav_names[$i]="${hit##*/}"; _fav_moved[$i]=""; _fav_dirty=true     # renamed in place
      else _fav_stale[$i]=1; fi
    else
      _fav_stale[$i]=1
    fi
  done
  $_fav_dirty && _fav_save "$dir"
  _fav_cache_key="$dir|$(_fav_mtime "$_FAV_FILE")|$(_fav_mtime "$dir")"
  [ ${#_fav_names[@]} -gt 0 ]
}

# _fav_save <dir>  (atomic; removes the file when nothing is left)
_fav_save() {
  local dir; dir=$(_fav_norm "$1")
  mkdir -p "$_FAV_DIR" 2>/dev/null
  _fav_file_for "$dir" >/dev/null 2>&1
  if [ ${#_fav_names[@]} -eq 0 ]; then
    rm -f -- "$_FAV_FILE"; _fav_cache_key=""; _fav_dirty=false; return
  fi
  _fav_lock
  local tmp="${_FAV_FILE}.tmp.$$" i line
  {
    echo "# favourites — one item per line:   name   [=> alias]   #id=dev:inode"
    echo "# safe to edit by hand; #id keeps a favourite attached if the item is renamed"
    echo "PATH=$dir"
    echo "DIR_ID=$(_fav_id "$dir")"
    for i in "${!_fav_names[@]}"; do
      line="${_fav_names[$i]}"
      [ -n "${_fav_alias[$i]}" ] && line+=" => ${_fav_alias[$i]}"
      [ -n "${_fav_ids[$i]}" ]   && line+=" #id=${_fav_ids[$i]}"
      [ -n "${_fav_moved[$i]:-}" ] && line+=" #moved=${_fav_moved[$i]}"
      printf '%s\n' "$line"
    done
  } > "$tmp" && mv -- "$tmp" "$_FAV_FILE"
  _fav_dirty=false
  _fav_cache_key=""
  _fav_unlock
}

# ── main-loop hooks ───────────────────────────────────────────────────────────
# _fav_begin : decides favourite mode for $path, prepares labels + banner.
_fav_begin() {
  _fav_on=false; _fav_has=false; _fav_banner=""; _FAV_LABEL=()
  if [ "$path" != "$_fav_last_path" ]; then _ns_on=false; _fav_last_path="$path"; fi
  _fav_load "$path" || return 0
  local i live=0 stale=0 p
  for i in "${!_fav_names[@]}"; do
    if [ "${_fav_stale[$i]}" = 1 ]; then stale=$((stale+1)); continue; fi
    live=$((live+1))
    p=$(_fav_join "$path" "${_fav_names[$i]}")
    if [ -n "${_fav_alias[$i]}" ]; then
      if $_ns_on; then _FAV_LABEL["$p"]="⭐ ${_fav_alias[$i]} (${_fav_names[$i]})"
      else _FAV_LABEL["$p"]="${_fav_alias[$i]} (${_fav_names[$i]})"; fi
    elif $_ns_on; then
      _FAV_LABEL["$p"]="⭐ ${_fav_names[$i]}"
    fi
  done
  [ "$live" -eq 0 ] && { _FAV_LABEL=(); return 0; }
  _fav_has=true
  local note=""; [ "$stale" -gt 0 ] && note="  ⚠️ $stale missing (sw → ⭐)"
  if $_ns_on; then
    _fav_banner="⭐ $live favourite(s) here, hidden — ns to show only them${note}"
  else
    _fav_on=true
    _fav_banner="⭐ Favourites: $live of ${total:-?} item(s) — ns = show all   sw → ⭐ tab = manage${note}"
  fi
}

# _fav_build_items : items = this folder's live favourites, sorted like any view.
_fav_build_items() {
  imaginary_mode=false
  items=()
  local i
  for i in "${!_fav_names[@]}"; do
    [ "${_fav_stale[$i]}" = 1 ] && continue
    items+=("$(_fav_join "$path" "${_fav_names[$i]}")")
  done
  item_size=(); item_mtime=(); item_icon=(); item_children=()
  _meta_loaded=false; _win_lo=0; _win_hi=0
  _items_presorted=false
  apply_sort
}

handle_normal_show() {             # ns
  if $_fav_has; then
    if $_ns_on; then _ns_on=false; echo "⭐ Favourite mode back on"
    else _ns_on=true; echo "📁 Favourite mode paused — showing the normal view (ns again to return)"; fi
  else
    echo "ℹ️  No favourites in this folder yet — add some with:  fa"
  fi
}

handle_force_show_guarded() {      # fs
  if $_fav_on; then
    echo "⭐ Favourite mode is on here — type ns first to leave it, then fs if the folder is still grouped"
  else
    handle_force_show
  fi
}

# ── adding ────────────────────────────────────────────────────────────────────
_fav_help() {
  cat <<'HLP'
⭐ FAVOURITES  (per folder — the folder then shows only them)
 fa 3,5,7-9         add by number / range      fa a   fa a-1-4
 fa sel             add the current .s selection
 fa .s.ext svg & .s.sw icon_1     add whatever a .s expression matches
 ns                 leave favourite mode for this visit (ns again = back)
 fs                 leave the grouped (imaginary) view, as before
 sw → ⭐ tab         N open   b remove   rn rename (alias)   e edit file
Files: ~/.bashbasicsbyvk/favourites/   (plain text, safe to edit)
HLP
}

# _fav_add <dir> <path...>
_fav_add() { _fav_lock; _fav_add_locked "$@"; local rc=$?; _fav_unlock; return $rc; }
_fav_add_locked() {
  local dir; dir=$(_fav_norm "$1"); shift
  _fav_load "$dir" >/dev/null 2>&1 || { _fav_names=(); _fav_alias=(); _fav_ids=(); _fav_stale=(); _fav_moved=(); _fav_base="$dir"; }
  local -A have=()
  local i p name
  for i in "${!_fav_names[@]}"; do have["${_fav_names[$i]}"]=1; done
  local added=0 dup=0 skip=0
  local -a cand=()
  for p in "$@"; do
    name="${p##*/}"
    if [ "${p%/*}" != "${dir%/}" ] && ! { [ "$dir" = "/" ] && [ "${p%/*}" = "" ]; }; then skip=$((skip+1)); continue; fi
    [ -e "$p" ] || [ -L "$p" ] || { skip=$((skip+1)); continue; }
    if [[ "$name" == *$'\t'* || "$name" == *$'\n'* || "$name" == *" => "* || "$name" == *" #id="* ]]; then skip=$((skip+1)); continue; fi
    if [ -n "${have[$name]+x}" ]; then dup=$((dup+1)); continue; fi
    have["$name"]=1
    cand+=("$p")
  done
  # ids in batches (one stat process per 400 items)
  local -a ids=()
  local n=${#cand[@]} off=0
  while [ "$off" -lt "$n" ]; do
    local -a chunk=("${cand[@]:off:400}")
    mapfile -t -O "${#ids[@]}" ids < <(stat -c '%d:%i' -- "${chunk[@]}" 2>/dev/null || stat -f '%d:%i' -- "${chunk[@]}" 2>/dev/null)
    off=$((off+400))
  done
  local k
  for k in "${!cand[@]}"; do
    _fav_names+=("${cand[$k]##*/}"); _fav_alias+=(""); _fav_stale+=(0); _fav_moved+=("")
    if [ "${#ids[@]}" -eq "$n" ]; then _fav_ids+=("${ids[$k]}"); else _fav_ids+=(""); fi
    added=$((added+1))
  done
  [ "$added" -gt 0 ] && _fav_save "$dir"
  local msg="⭐ Added $added favourite(s)"
  [ "$dup" -gt 0 ]  && msg="$msg, $dup already favourite"
  [ "$skip" -gt 0 ] && msg="$msg, $skip skipped (not directly in this folder)"
  echo "$msg"
  if [ "$added" -gt 0 ]; then
    _ns_on=true; _fav_last_path="$path"        # keep the normal view this visit so you can keep adding
    echo "ℹ️  Next time you open this folder it shows only favourites  (ns toggles)"
  fi
}

handle_fav_add() {                 # fa ...
  local arg="${1#fa}"
  arg="${arg#"${arg%%[![:space:]]*}"}"; arg="${arg%"${arg##*[![:space:]]}"}"
  if [ "$arg" = "help" ]; then _fav_help; return; fi
  if [ -z "$arg" ]; then
    echo "⭐ Add to favourites in $path"
    echo "   numbers/ranges (1,3,5-9)   a   a-1-4   sel   or a .s expression"
    read -r -p "Add: " arg
    arg="${arg#"${arg%%[![:space:]]*}"}"
    [ -z "$arg" ] && { echo "🚫 Cancelled"; return; }
  fi
  local -a picked=()
  case "$arg" in
    sel)
      local -a sel=()
      _sel_load_live sel
      [ ${#sel[@]} -eq 0 ] && { echo "ℹ️  Selection is empty (use .s first)"; return; }
      picked=("${sel[@]}") ;;
    .s*|.d*|\!*|\(*)
      _sel_eval "$arg" || return
      [ ${#_SEL_FOUND[@]} -eq 0 ] && { echo "ℹ️  Nothing matched"; return; }
      picked=("${_SEL_FOUND[@]}")
      if [ ${#picked[@]} -gt 500 ]; then
        local ans; read -r -p "Add ${#picked[@]} favourites? (y/n): " ans
        [[ "$ans" == [yY] ]] || { echo "🚫 Cancelled"; return; }
      fi ;;
    *)
      if $imaginary_mode; then
        echo "⚠️  This folder is grouped — numbers mean groups. Use  fa <.s expression>  (or fs first)"
        return
      fi
      local spec="${arg// /}" idx
      local -a indices=()
      if [ "${spec,,}" = "a" ]; then indices=($(seq 1 "${#items[@]}"))
      elif [[ "$spec" =~ ^[aA]-(.+)$ ]]; then indices=($(_sp_parse_all_except "${BASH_REMATCH[1]}" "${#items[@]}"))
      else indices=($(parse_selection "$spec" "${#items[@]}")); fi
      for idx in "${indices[@]}"; do picked+=("${items[$((idx-1))]}"); done
      [ ${#picked[@]} -eq 0 ] && { echo "❌ No valid items selected"; return; } ;;
  esac
  _fav_add "$path" "${picked[@]}"
}

# ── sw ⭐ tab helpers ─────────────────────────────────────────────────────────
_fav_sw_build() {                  # _fav_sw_build <dir>  → items + labels (stale included)
  items=(); _FAV_LABEL=(); _FAV_MOVED_TO=()
  _fav_load "$1" >/dev/null 2>&1 || return 0
  local i p
  for i in "${!_fav_names[@]}"; do
    p=$(_fav_join "$1" "${_fav_names[$i]}")
    items+=("$p")
    if [ "${_fav_stale[$i]}" = 1 ] && [ -n "${_fav_moved[$i]:-}" ]; then
      _FAV_MOVED_TO["$p"]="${_fav_moved[$i]}"
      _FAV_LABEL["$p"]="${_fav_alias[$i]:+${_fav_alias[$i]} — }${_fav_names[$i]} ↪ moved to ${_fav_moved[$i]}"
    elif [ "${_fav_stale[$i]}" = 1 ]; then
      _FAV_LABEL["$p"]="${_fav_alias[$i]:+${_fav_alias[$i]} — }${_fav_names[$i]} ⚠️ (missing)"
    elif [ -n "${_fav_alias[$i]}" ]; then
      _FAV_LABEL["$p"]="${_fav_alias[$i]} (${_fav_names[$i]})"
    fi
  done
}

_fav_sw_remove() {                 # _fav_sw_remove <dir>
  local dir; dir=$(_fav_norm "$1")
  [ ${#items[@]} -eq 0 ] && { echo "ℹ️  No favourites here"; return; }
  echo "🗑️  Remove favourite(s) — the files themselves are NOT touched"
  select_items_common "REMOVE FAVOURITE" allow_a || return
  _fav_lock
  _fav_cache_key=""; _fav_load "$dir" >/dev/null 2>&1
  local -A drop=()
  local p
  for p in "${selected_items[@]}"; do drop["${p##*/}"]=1; done
  local -a n=() a=() d=() s=() m=()
  local i removed=0
  for i in "${!_fav_names[@]}"; do
    if [ -n "${drop[${_fav_names[$i]}]+x}" ]; then removed=$((removed+1)); continue; fi
    n+=("${_fav_names[$i]}"); a+=("${_fav_alias[$i]}"); d+=("${_fav_ids[$i]}"); s+=("${_fav_stale[$i]}"); m+=("${_fav_moved[$i]:-}")
  done
  _fav_names=("${n[@]}"); _fav_alias=("${a[@]}"); _fav_ids=("${d[@]}"); _fav_stale=("${s[@]}"); _fav_moved=("${m[@]}")
  _fav_save "$dir"
  _fav_unlock
  echo "✅ Removed $removed favourite(s)"
  [ ${#_fav_names[@]} -eq 0 ] && echo "ℹ️  No favourites left — this folder shows normally again"
}

_fav_sw_rename() {                 # _fav_sw_rename <dir>   (alias only; the file is untouched)
  local dir; dir=$(_fav_norm "$1")
  [ ${#items[@]} -eq 0 ] && { echo "ℹ️  No favourites here"; return; }
  local num alias
  read -r -p "Rename which favourite (number): " num
  [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#items[@]}" ] || { echo "⚠️  Invalid number"; return; }
  local name="${items[$((num-1))]##*/}"
  read -r -p "New display name for '$name' (empty = clear alias): " alias
  if [[ "$alias" == *$'\t'* || "$alias" == *" #id="* || "$alias" == *" => "* ]]; then echo "❌ That name has characters not allowed"; return; fi
  _fav_lock
  _fav_cache_key=""; _fav_load "$dir" >/dev/null 2>&1
  local i
  for i in "${!_fav_names[@]}"; do
    [ "${_fav_names[$i]}" = "$name" ] && _fav_alias[$i]="$alias"
  done
  _fav_save "$dir"
  _fav_unlock
  if [ -n "$alias" ]; then echo "✅ '$name' now shows as '$alias' (file unchanged)"; else echo "✅ Alias cleared for '$name'"; fi
}

_fav_sw_edit() {                   # _fav_sw_edit <dir>
  local dir; dir=$(_fav_norm "$1")
  if ! _fav_file_for "$dir"; then echo "ℹ️  No favourites file yet — add some with fa"; return; fi
  _rule_editor "$_FAV_FILE"
  _fav_cache_key=""
  echo "✅ Favourites reloaded"
}
