#!/usr/bin/env bash
# bashbasicsbyvk_switch.sh
# ════════════════════════════════════════════════════════════════════════════
#  SWITCH — three-tab overlay inside the main file-manager loop
#
#  Tabs (← / → to cycle when input is empty):
#    📌 Bookmarks  ~/.bashbasicsbyvk/switch/   — pointers to folders AND files (.swlink inside, never shown)
#    🕐 Recents    ~/.bashbasicsbyvk/recents.tsv — folders entered with cd, files edited in the run loop (bashbasicsbyvk_track.sh)
#    ⭐ Favourites the favourites of the folder you came from (manage them:
#                  N open/go · b remove (b-1,3 · x = same) · r rename alias · e edit file · e-N file actions).
#                  Adding is done in the file view with  fa.
#
#  Execute / scripting has moved to bashbasicsbyvk_functions.sh (fx tab).
#  Tab switch is in-place: the block redraws inside the existing terminal
#  block — no scroll, no new container.
# ════════════════════════════════════════════════════════════════════════════

# ── Storage roots ─────────────────────────────────────────────────────────────
# _SW_DIR, the recents file and the exclude file are defined once, in bashbasicsbyvk_track.sh (the load mapper loads it first: NEEDS column)

_sw_ensure_store() {
  mkdir -p "$_SW_DIR" 2>/dev/null
}

# ── Exclude list helpers

# Ensure the exclude file exists
_sw_excl_ensure() {
  if [ ! -f "$_RC_EXCLUDE_FILE" ]; then
    cat > "$_RC_EXCLUDE_FILE" << 'EXCL_TEMPLATE'
# recents_exclude.conf — files/folders to hide from recents
#
# Syntax:  <type>  <value>        (the xe screen writes these for you)
#   filename             NAME      — file named exactly NAME, in any directory
#   filename-contains    TEXT      — file whose name contains TEXT
#   filename-starts      TEXT      — file whose name starts with TEXT
#   filename-ends        TEXT      — file whose name ends with TEXT
#   filepath             /abs/path — this exact file only
#   foldername           NAME      — everything inside any folder named exactly NAME
#   foldername-contains  TEXT      — ... any folder whose name contains TEXT
#   foldername-starts    TEXT      — ... any folder whose name starts with TEXT
#   foldername-ends      TEXT      — ... any folder whose name ends with TEXT
#   dirpath              /abs/path — everything under this directory
#
# Examples:
#   filename   .env
#   foldername .git
#   foldername node_modules
#   foldername __pycache__
#   filepath   /home/user/notes/secret.txt
#   dirpath    /home/user/work/private
EXCL_TEMPLATE
  fi
}

# Read the active (non-comment) rules into three parallel arrays: kind, value, line number in the file.
# _sw_excl_rows then turns them into the display rows the screens show (_SW_XROW), so no screen prints its own list.
declare -ga _SW_XK=() _SW_XV=() _SW_XLN=() _SW_XROW=()
_sw_excl_load() {
  _sw_excl_ensure
  _SW_XK=(); _SW_XV=(); _SW_XLN=(); _SW_XROW=()
  local line kind value lineno=0 lab
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$(( lineno + 1 ))
    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
    read -r kind value <<< "$line"
    _SW_XK+=("$kind"); _SW_XV+=("$value"); _SW_XLN+=("$lineno")
    lab="$(_rc_excl_label "$kind")" || lab="❓ $kind"
    _SW_XROW+=("$lab $value")
  done < "$_RC_EXCLUDE_FILE"
}

# Add one rule: question 1 = Exclude What? (kind of rule), question 2 = the text for that kind.
_sw_excl_add() {
  _sw_excl_ensure
  local pick kind lab value what
  _bvk_menu pick -t "Exclude What?" -i "🚫" -n \
    "@h:For files" \
    "1:filename contains" "2:filename equals" "3:filename from path" "4:filename starts with" "5:filename ends with" \
    "@h:For folders (everything inside is hidden too)" \
    "6:foldername contains" "7:foldername equals" "8:foldername from path" "9:foldername starts with" "10:foldername ends with" \
    || { echo "↩️  Back"; return 0; }      # u / q = back out (AGENTS rule 6: a fixed-answer question is a _bvk_menu)
  case "$pick" in
    1) kind="filename-contains"   ; what="Name contains" ;;
    2) kind="filename"            ; what="Exact name" ;;
    3) kind="filepath"            ; what="Full path of the file" ;;
    4) kind="filename-starts"     ; what="Name starts with" ;;
    5) kind="filename-ends"       ; what="Name ends with" ;;
    6) kind="foldername-contains" ; what="Name contains" ;;
    7) kind="foldername"          ; what="Exact name" ;;
    8) kind="dirpath"             ; what="Full path of the folder" ;;
    9) kind="foldername-starts"   ; what="Name starts with" ;;
    10) kind="foldername-ends"    ; what="Name ends with" ;;
    *) echo "Cancelled."; return 0 ;;
  esac
  lab="$(_rc_excl_label "$kind")"
  echo
  echo "🚫 Exclude What? › ${lab#* }"
  _bvk_read value "$what: " -I || return 0
  value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"      # trim the ends, keep spaces inside a name
  [ -z "$value" ] && { echo "Cancelled — empty value."; return 0; }
  case "$kind" in
    filepath|dirpath)
      value="${value/#\~/$HOME}"                                                              # ~ → home; a relative path is taken from here
      [[ "$value" == /* ]] || value="$PWD/$value" ;;
    *) [[ "$value" == */* ]] && { echo "🔴  A name has no / in it. Use \"from path\" for a place."; return 0; } ;;
  esac
  if grep -qxF -- "$kind  $value" "$_RC_EXCLUDE_FILE" 2>/dev/null; then
    echo "📜  Rule already exists: ${lab#* } $value"
    return 0
  fi
  printf '%s  %s\n' "$kind" "$value" >> "$_RC_EXCLUDE_FILE"
  echo "💫 Added: ${lab#* } $value"
  echo "   (applies at once)"
}

# Remove rule number $1 (index into _SW_XK, from _sw_excl_load).
_sw_excl_drop() {
  local i="$1"
  [ -n "${_SW_XLN[$i]:-}" ] || return 1
  sed -i "${_SW_XLN[$i]}d" "$_RC_EXCLUDE_FILE"
  echo "🗑️  Removed: ${_SW_XROW[$i]}"
}

# Remove from the typed key r: pick a rule, it goes; the list stays open until it is empty or u.
_sw_excl_remove() {
  local pick i
  while true; do
    _sw_excl_load
    if [ "${#_SW_XK[@]}" -eq 0 ]; then echo "No rules to remove."; return 0; fi
    local -a items=()
    for i in "${!_SW_XROW[@]}"; do items+=("$(( i + 1 )):${_SW_XROW[$i]}"); done
    _bvk_menu pick -t "Remove from exclude list" -i "🚫" -n -p "${items[@]}" || return 0       # u = back to the exclude list, q = quit (the caller reads _bvk_back)
    [[ "$pick" =~ ^[0-9]+$ ]] || return 0
    _sw_excl_drop $(( pick - 1 )) || return 0
  done
}

# A rule was picked in the list: Edit Rule (change its text) or Remove Rule.
_sw_excl_rule() {
  local i="$1" act value kind="${_SW_XK[$1]}"
  _bvk_menu act -t "${_SW_XROW[$i]}" -i "🚫" -n -p "e:Edit Rule" "r:Remove Rule" || return 0
  case "$act" in
    r) _sw_excl_drop "$i" ;;
    e) echo
       _bvk_read value "New text: " -I || return 0
       value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
       [ -z "$value" ] && { echo "Cancelled — empty value."; return 0; }
       case "$kind" in
         filepath|dirpath) value="${value/#\~/$HOME}"; [[ "$value" == /* ]] || value="$PWD/$value" ;;
         *) [[ "$value" == */* ]] && { echo "🔴  A name has no / in it. Use \"from path\" for a place."; return 0; } ;;
       esac
       sed -i "${_SW_XLN[$i]}s|.*|$(printf '%s  %s' "$kind" "$value" | sed 's/[|&\\]/\\&/g')|" "$_RC_EXCLUDE_FILE"
       echo "💫 Changed: $(_rc_excl_label "$kind" | cut -d' ' -f2-) $value" ;;
  esac
}

# Open the config file in $EDITOR / nano / vi
_sw_excl_edit() {
  _sw_excl_ensure
  local ed="${EDITOR:-}"
  if [ -z "$ed" ]; then
    command -v nano &>/dev/null && ed="nano" || ed="vi"
  fi
  echo "📝 Opening $_RC_EXCLUDE_FILE in $ed"
  "$ed" "$_RC_EXCLUDE_FILE"
  echo "   (applies at once)"
}

# Main exclude manager — called by 'xe' inside recents tab.  ONE screen: the rules are the numbered rows (pick one: Edit Rule / Remove Rule);
# the actions are typed keys in the footer (a add · r remove · e edit file).
_sw_excl_menu() {
  local xc i
  local -a rows acts
  while true; do
    _sw_excl_load
    rows=(); for i in "${!_SW_XROW[@]}"; do rows+=("$(( i + 1 )):${_SW_XROW[$i]}"); done
    acts=("a|add:Add rule" "r|remove:Remove rule" "e|edit:Edit file")
    # THE native choice menu (rule 18): u = back to recents, q = quit
    if [ "${#rows[@]}" -gt 0 ]; then
      _bvk_menu xc -t "Exclude List for Recents" -i "🚫" -k -n -p -a "${acts[0]}" -a "${acts[1]}" -a "${acts[2]}" "${rows[@]}"
    else        # no rule to pick: the three actions are the rows
      _bvk_menu xc -t "Exclude List for Recents" -i "🚫" -k -n -e "(no rules yet)" "${acts[@]}"
    fi || {
      _bvk_back && { echo "↩️  Back to recents"; return 0; }
      _bvk_quit; return 0
    }
    case "$xc" in
      a)  _sw_excl_add    ;;
      r)  _sw_excl_remove ;;
      e)  _sw_excl_edit   ;;
      [0-9]*) _sw_excl_rule $(( xc - 1 )) ;;
    esac
  done
}

# ── Tab state
_sw_tab="bookmarks"   # bookmarks | recents | favourites
_sw_in_mode=0         # 1 while inside switch_menu — enables ←/→ sentinel
_sw_did_switch=false  # set true on successful path jump — changes q behaviour

# ── Bookmarks: add / remove

_sw_add_path() {
  local outer_path="$1" sw_cur_dir="$2"
  _sw_ensure_store
  local dup t
  while IFS= read -r -d '' dup; do
    _swlink_read_target_v "$dup"
    if [ "$_SWL_T" = "$outer_path" ]; then
      echo "📜  Already in switch: $outer_path"
      return 0
    fi
  done < <(find "$_SW_DIR" -name '*.swlink' -print0 2>/dev/null)
  local display_name
  display_name=$(basename "$outer_path")
  _swlink_write "$sw_cur_dir" "$outer_path" "$display_name" >/dev/null
  echo "💫 Added: $display_name  →  $outer_path"
}

# b · b-1,3 · b-a-1-2 · x   — ONE remove, whatever the spelling (footer says b, the map says b-, x is the old key).
# Only the bookmark pointer goes: the folder or file it points to is never touched, so no cloud backup either.
_sw_remove_paths() {
  local raw="${1:-}" spec="" ans n
  case "$raw" in [bB]-*) spec="${raw:2}" ;; esac
  selected_items=()
  if [ -n "$spec" ]; then
    $imaginary_mode && { echo "🔴  Navigate into a group first, then use b-N"; return 0; }
    sp_resolved=()
    _sp_resolve_itemlist "$spec" || return 0
    selected_items=("${sp_resolved[@]}")
  else
    if $imaginary_mode; then select_imaginary_items_common "$path" "$group_prefix" "🗑️ Remove bookmark" || return 0
    else select_items_common "🗑️ Remove bookmark" allow_a || return 0; fi
  fi
  n=${#selected_items[@]}
  [ "$n" -eq 0 ] && { echo "📜  Nothing selected"; return 0; }
  _bvk_yn ans "Remove $n bookmark(s)? Only the bookmark goes — what it points to is NOT touched." -d none || return 0
  case "${ans,,}" in y|yes) ;; *) echo "Cancelled."; return 0 ;; esac
  local it removed=0
  for it in "${selected_items[@]}"; do
    rm -rf -- "$it" && { _carry_forget "$it"; removed=$((removed+1)); }
  done
  echo "💫 Removed $removed bookmark(s)"
}

# recents and favourites are "managed" tabs: the normal file commands are blocked
_sw_is_ro() { [ "$_sw_tab" = "recents" ] || [ "$_sw_tab" = "favourites" ]; }

# ── Tabs: defined once in the master template (bashbasicsbyvk_tabmenu.sh), which also draws the bar, steps ←/→ and builds the footer ──
_tm_define sw _sw_tab "🔀 Switch" "Switch" bookmarks:"📌 Bookmarks" recents:"🕐 Recents" favourites:"⭐ Favourites"

# ── Headers / footers

_sw_menu_header() {
  local _loc                                       # template V3PX4Y (Switch|bookmarks · recents · favourites)
  case "$_sw_tab" in
    recents) _loc="(folders you entered with cd · files you edited)" ;;
    favourites) _loc="⭐ favourites of: $_sw_outer_path" ;;
    *)       _loc="$path${group_prefix:+ [group: ${group_prefix^^}*]}" ;;
  esac
  _tm_head -n "📂 $_loc" sw
}

_sw_menu_header_imaginary() {
  _sw_menu_header
  echo "$_imag_banner"
}

# one footer for all three tabs: u q h cc (+ the group prefix note on Bookmarks). Every other key (a b r e xe clr e-N …) is listed by cc.
_sw_menu_footer() {
  local -a _f=()
  [ "$_sw_tab" = bookmarks ] && [ -n "$group_prefix" ] && _f+=("|" "u.prefix" "#Group prefix now: ${group_prefix^^}*")
  _tm_footer "${_f[@]}"
}

_sw_set_viewport_for_tab() {
  if $imaginary_mode; then
    _vp_mode="imaginary"
    _vp_header_fn=_sw_menu_header_imaginary
  else
    _vp_mode="items"
    _vp_header_fn=_sw_menu_header
  fi
  _vp_footer_fn=_sw_menu_footer
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
}

# ── Item builder per tab

_sw_build_items_for_tab() {
  _FAV_LABEL=()
  imaginary_mode=false
  _filter_reset_state
  items=()
  _hl_index=0

  case "$_sw_tab" in

    recents)
      _rc_build
      ;;

    favourites)
      _fav_sw_build "$_sw_outer_path"
      ;;

    bookmarks)
      _bvk_build_path_items
      ;;
  esac
}

# ── Read-only guard

_sw_recents_blocked() {
  if [ "$_sw_tab" = "favourites" ]; then
    printf '🔴  Not available in Favourites — use x / r / e here, or go to the Bookmarks tab\n'
  else
    printf '🔴  Recents is managed by the app — use the Bookmarks tab or fx (functions) for scripts\n'
  fi
}

# ── Bookmarks selection
# Returns 1 when a switch should be performed (_sw_result_path set)

_sw_result_path=""

_sw_bookmarks_handle_selection() {
  local choice="$1"

  # e-N — bypass .swlink intercept, call handle_file directly (same as fx/udf)
  if [[ "$choice" =~ ^[eE]-([0-9]+)$ ]]; then
    local n="${BASH_REMATCH[1]}"
    $imaginary_mode && { echo "🔴  Navigate into a group first, then use e-N"; return 0; }
    if [ "$n" -ge 1 ] && [ "$n" -le "${#items[@]}" ]; then
      local t="${items[$((n-1))]}"
      [ -d "$t" ] && { path="$t"; group_prefix=""; force_show=false; return 0; }
      [ -f "$t" ] && handle_file "$t"
    else
      _bvk_invalid
    fi
    return 0
  fi

  # imaginary mode
  if $imaginary_mode; then
    local matched=false ch=""
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#imaginary_map[@]}" ]; then
      ch="${imaginary_map[$((choice-1))]}"; matched=true
    elif [ ${#choice} -eq 1 ]; then
      for gc in "${imaginary_map[@]}"; do
        [[ "$gc" == "${choice^^}" || "$gc" == "$choice" ]] && { ch="$gc"; matched=true; break; }
      done
    fi
    if $matched; then
      if [ "$ch" = "#" ]; then
        imaginary_mode=false; items=()
        while IFS= read -r -d '' _f; do
          _bn="${_f##*/}"
          [[ "$_bn" == "." || "$_bn" == ".." ]] && continue
          ! $show_hidden_files && [[ "$_bn" == .* ]] && continue
          local _bn_lower="${_bn,,}"
          [ -n "$group_prefix" ] && [[ "$_bn_lower" != "$group_prefix"* ]] && continue
          local _next="${_bn_lower:${#group_prefix}:1}"
          case "$_next" in [a-zA-Z0-9]|_|.|'-'|'('|')'|'['|']'|'{'|'}'|@|'!'|'~'|'+'|'='|'^'|'&'|'%'|'$'|','|';'|"'"|' ') continue ;; esac
          items+=("$_f")
        done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
        _collect_metadata; apply_sort
      elif [[ "$ch" =~ ^[A-Z]$ ]]; then
        group_prefix="${group_prefix}${ch,,}"; force_show=false
      else
        group_prefix="${group_prefix}${ch}"; force_show=false
      fi
    else
      _bvk_invalid
    fi
    return 0
  fi

  # flat mode
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local selected="${items[$((choice-1))]}" bn
    bn="${selected##*/}"
    [ -d "$selected" ] && { path="$selected"; group_prefix=""; force_show=false; return 0; }
    if [[ "$bn" == *.swlink ]]; then
      # a bookmark is a POINTER: a folder opens (the list moves there), a file opens its run loop. The pointer's own file is never what you land on.
      _swlink_read_target_v "$selected" || { echo "🔴  Bookmark has no target"; return 0; }
      if [ ! -e "$_SWL_T" ]; then
        _swlink_heal "$selected" && echo "📍 ${bn%.swlink} had moved — found it: $_SWL_T" || { echo "🔴  Target gone: $_SWL_T"; return 0; }
      fi
      if [ -d "$_SWL_T" ]; then _sw_result_path="$_SWL_T"; return 1; fi
      handle_file "$_SWL_T"
      return 0
    fi
    [ -f "$selected" ] && handle_file "$selected"
  else
    _bvk_invalid
  fi
  return 0
}

# ── Favourites selection
# Folder → jump there (leaves sw).  File → open like anywhere else.

_sw_favourites_handle_selection() {
  local choice="$1"
  [[ "$choice" =~ ^[0-9]+$ ]] || { _bvk_invalid; return 0; }
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ] || { echo "🔴  Out of range"; return 0; }
  local t="${items[$((choice-1))]}"
  if [ ! -e "$t" ]; then
    local _mv="${_FAV_MOVED_TO[$t]:-}"
    if [ -n "$_mv" ] && [ -e "$_mv" ]; then          # the daemon saw it move — follow it
      if [ -d "$_mv" ]; then _sw_result_path="$_mv"; else _sw_result_path="${_mv%/*}"; fi
      echo "📍 ${t##*/} moved — going to: $_sw_result_path"
      return 1
    fi
    echo "🔴  Missing: ${t##*/} — remove it with x"; return 0
  fi
  if [ -d "$t" ]; then _sw_result_path="$t"; return 1; fi
  handle_file "$t"
  return 0
}

# ── Recents selection

# Recents: a folder → the list moves there (like a bookmark); a file → its run loop.
_sw_recents_handle_selection() {
  local choice="$1"
  [[ "$choice" =~ ^[0-9]+$ ]] || { _bvk_invalid; return 0; }
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ] || { echo "🔴  Out of range"; return 0; }
  local t="${items[$((choice-1))]}"
  if [ -d "$t" ]; then _sw_result_path="$t"; return 1; fi
  handle_file "$t"
  return 0
}

# ── In-place tab redraw
# Rebuilds items + chrome, then repaints the existing terminal block.
# Does NOT scroll or emit a new block.

# Switch path context to the new tab, then rebuild its rows (the template snapshots the old block height BEFORE this runs)
_sw_tab_prepare() {
  case "$_sw_tab" in
    bookmarks) path="$_SW_DIR" ;;
    recents)   : ;;
    favourites) path="$_sw_outer_path" ;;   # pickers show the folder these favourites belong to
  esac
  group_prefix=""
  force_show=false
  _sw_build_items_for_tab
}
_sw_tab_redraw() { _tm_tab_redraw _sw_tab_prepare _sw_set_viewport_for_tab; }

# ── Main entry point

# _sw_perform_switch <dir>   the switch itself: restores the folder view state, cd's there, records it and resets the picker state.
# (dynamic scope: the caller is the switch loop that owns _sw_saved_* / _sw_result_path / _sw_did_switch / _sw_in_mode)
_sw_perform_switch() {
  local _sw_cd_target="$1"
  group_prefix="$_sw_saved_prefix"
  force_show="$_sw_saved_force"
  cd -- "$_sw_cd_target" 2>/dev/null || true
  path="$_sw_cd_target"
  _sw_did_switch=true
  _sw_result_path=""
  _sw_saved_path=""
  _sw_in_mode=0
  printf '🔀 → %s\n' "$_sw_cd_target"
}

switch_menu() {
  _lm_need bashbasicsbyvk_track.sh       # _SW_DIR, the bookmark and recents helpers
  _sw_ensure_store

  local _sw_outer_path="$path"
  local _sw_saved_path="$path"
  local _sw_saved_prefix="$group_prefix"
  local _sw_saved_force="$force_show"

  _sw_tab="bookmarks"
  path="$_SW_DIR"
  group_prefix=""
  force_show=false
  _sw_in_mode=1
  # Execute / scripting → use fx (functions_menu) instead

  local _sw_choice _sw_rc

  shopt -s nullglob

  # ── First render
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  _sw_build_items_for_tab
  _sw_set_viewport_for_tab
  _vp_render_from_top

  while true; do

    _read_choice_filtered
    _sw_choice="$choice"

    shopt -s nocasematch

    # ── Tab-switch sentinels
    case "$_sw_choice" in
      __sw_tab_right__|__sw_tab_left__)
        _tm_key sw "$_sw_choice"
        _sw_tab_redraw
        shopt -u nocasematch; continue
        ;;
    esac

    # ── After any real action, do a full fresh render at top of loop
    local _sw_do_fresh=true

    case "$_sw_choice" in

      sw|SW)
        echo "↩️  Exiting switch mode"
        break
        ;;

      fx|FX)
        # Hand over to the fx inner loop (outer loop is unchanged)
        _inner_next=fx
        break
        ;;

      xe|XE)
        # Exclude list — accessible from either tab, most useful in recents
        _sw_excl_menu
        ;;

 clr|CLR)
        if [ "$_sw_tab" = "recents" ]; then
          local _clr_ans
          _bvk_yn _clr_ans "Clear all recents? This only clears the list, not your files." -d none
          if [[ "${_clr_ans,,}" == "y" ]]; then
            : > "$_RC_FILE"
            echo "💫 Recents list cleared."
          else
            echo "Cancelled."
          fi
        else
          _sw_recents_blocked
          _sw_do_fresh=false
        fi
        ;;
        
      q)
        _bvk_quit                    # q = close to the main loop (u = back one screen); never leaves the app
        break
        ;;

      -h) open_help ;;

      u)
        if _sw_is_ro; then
          # Recents / Favourites are flat lists: there is nothing to go "up" into, so u leaves
          # (it used to print the read-only warning and trap the user)
          echo "↩️  Exiting switch mode"; break
        elif [ -n "$group_prefix" ]; then
          group_prefix="${group_prefix%?}"; force_show=false
        elif [ "$path" != "$_SW_DIR" ] && [ "$path" != "/" ]; then
          path=$(dirname "$path"); group_prefix=""; force_show=false
        else
          echo "↩️  At root — exiting switch mode"; break
        fi
        ;;

      fs)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_force_show
        ;;

      a|A)
        if [ "$_sw_tab" = "favourites" ]; then
          echo "📜  Add favourites from the file view with  fa  (numbers, ranges, or a .s expression)"; _sw_do_fresh=false
        else
          _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || _sw_add_path "$_sw_outer_path" "$path"
        fi
        ;;

      b|b-*|x)
        # ONE remove for bookmarks and favourites (footer: b) · cmdmap: b-N · x = the old key).
        # Staging a bookmark (b-) is a FILE-VIEW command; here it would only bookmark a bookmark.
        case "$_sw_tab" in
          favourites) _fav_sw_remove "$_sw_outer_path" "$_sw_choice" ;;
          recents)    _sw_recents_blocked; _sw_do_fresh=false ;;
          *)          _sw_remove_paths "$_sw_choice" ;;
        esac
        ;;

      e|E)
        if [ "$_sw_tab" = "favourites" ]; then _fav_sw_edit "$_sw_outer_path"
        else echo "📜  e edits the favourites file — open the ⭐ Favourites tab first"; _sw_do_fresh=false; fi
        ;;

      c)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_create
        ;;

      d)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || delete_items
        ;;

      l-*)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_lock_items "$_sw_choice"
        ;;

      ul-*)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_unlock_items "$_sw_choice"
        ;;

      t)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || transfer_menu
        ;;

      z)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || organise_menu
        ;;

      r)
        if [ "$_sw_tab" = "favourites" ]; then _fav_sw_rename "$_sw_outer_path"
        else _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_rename
        fi
        ;;

      f)            find_menu ;;
      s)            settings_menu ;;

      cd)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || { _rc_record "$path"; _lt_cleanup; cd "$path" && exec "$SHELL"; }
        ;;

      disk)         df -h ;;
      ram)          free -h ;;

      rf)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_refresh
        ;;

      d-|d-\ *)     handle_staging_dispatch "${_sw_choice:2}" ;;
      v-)           handle_staging_view ;;

      c-*|m-*|k-*|s-*)
        _sw_is_ro && { _sw_recents_blocked; _sw_do_fresh=false; } || handle_staging_stage "$_sw_choice"
        ;;

      p-*)
        # path map only READS the listed items, so every tab may use it; "save to txt"
        # goes to the folder sw was opened from (not the bookmark store)
        local _saved_path_p="$path"; path="$_sw_outer_path"
        handle_staging_map "$_sw_choice"
        path="$_saved_path_p"
        ;;

      _*)           _sw_do_fresh=false ;;   # filter: viewport handles it live

      *)
        case "$_sw_tab" in
          bookmarks)
            _sw_bookmarks_handle_selection "$_sw_choice"
            _sw_rc=$?
            if [ "$_sw_rc" -eq 1 ] && [ -n "$_sw_result_path" ]; then
              _sw_perform_switch "$_sw_result_path"      # a folder: a bookmarked file never gets here (it opened its run loop above)
              return 0
            fi
            ;;
          recents)
            _sw_recents_handle_selection "$_sw_choice"
            _sw_rc=$?
            if [ "$_sw_rc" -eq 1 ] && [ -n "$_sw_result_path" ]; then
              _sw_perform_switch "$_sw_result_path"
              return 0
            fi
            ;;
          favourites)
            _sw_favourites_handle_selection "$_sw_choice"
            _sw_rc=$?
            if [ "$_sw_rc" -eq 1 ] && [ -n "$_sw_result_path" ]; then
              _sw_perform_switch "$_sw_result_path"
              return 0
            fi
            ;;
        esac
        ;;
    esac

    shopt -u nocasematch
    [ "${_BVK_TO_MAIN:-0}" = 1 ] && break          # q inside a command / prompt of this loop: close to the main loop

    # ── Re-render after action
    if $_sw_do_fresh; then
      declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
      _sw_build_items_for_tab
      _sw_set_viewport_for_tab
      _vp_render_from_top
    fi

  done

  shopt -u nocasematch
  _sw_in_mode=0

  if [ -n "$_sw_saved_path" ]; then
    path="$_sw_saved_path"
    group_prefix="$_sw_saved_prefix"
    force_show="$_sw_saved_force"
  fi
}