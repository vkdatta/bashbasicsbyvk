# Route a raw staging command (c-* m-* k-* b-* s-*  and the persistent c--* m--* k--* b--* s--*) to the correct buffer.
# Path-map commands (p-*) are handled by handle_staging_map (staging_map.sh).
#
#   c- copy · m- move · k- shortcut · b- bookmark · s- select      (one dash = once, two dashes = persistent)
#
# Syntax supported for the item-list portion:
#   1,3,5          → items 1, 3 and 5
#   1-7            → items 1 through 7
#   a              → ALL items
#   a-1-5,7        → ALL items EXCEPT 1–5 and 7
#   (any combo)    optionally followed by   as <name>   → the items form the named set <name>:   m-a as set1 · c-1,2 as set2
#                  (the same "as" the up- / ux- / save- commands use: _bb_split_alias).  d- set1 then applies only that set.
handle_staging_stage() {
  local raw="$1"
  local op pfx persistent=false

  case "$raw" in
    c--*) op=cp; pfx="c--" ;;
    m--*) op=mv; pfx="m--" ;;
    k--*) op=sc; pfx="k--" ;;
    b--*) op=bm; pfx="b--" ;;
    s--*) op=sl; pfx="s--" ;;
    c-*)  op=cp; pfx="c-" ;;
    m-*)  op=mv; pfx="m-" ;;
    k-*)  op=sc; pfx="k-" ;;
    b-*)  op=bm; pfx="b-" ;;
    s-*)  op=sl; pfx="s-" ;;
    *) return 1 ;;
  esac
  [[ "$pfx" == *-- ]] && persistent=true

  _bb_split_alias "${raw:${#pfx}}" "${pfx}a as set1   ·   ${pfx}1,3-5 as set2" || return 0
  _sp_stage_buffer "$op" "$persistent" "$_BB_ITEMLIST" "$_BB_LINK_ALIAS"
}

# d-            apply EVERY buffer to the current folder
# d- set1       apply only the set(s) called set1 (in every buffer that has one).  d- set1,set2 for several.
# $1 = what was typed after "d-"  (empty, or " set1").
handle_staging_dispatch() {
  _sp_ensure_store
  local dest="$path" names="${1:-}" persistent op file n total=0
  names="${names#"${names%%[![:space:]]*}"}"; names="${names%"${names##*[![:space:]]}"}"

  for persistent in true false; do
    for op in "${_SP_APPLY_OPS[@]}"; do
      file=$(_sp_file_for "$op" "$persistent")
      n=$(_sp_count "$file" "$names"); total=$((total + n))
    done
  done

  if [ "$total" -eq 0 ]; then
    if [ -n "$names" ]; then
      echo "🔴  No set named '$names' in the copy / move / shortcut / bookmark buffers.  v- shows the names in use."
    else
      echo "📜  All buffers are empty — nothing to apply. Use c-/m-/k-/b- (once) or c--/m--/k--/b-- (persistent) to stage items first."
    fi
    return 0
  fi

  echo "📦 Destination: $dest${names:+   (set: $names)}"

  # persistent buffers first (kept), then the once buffers (the applied items are cleared afterwards)
  for persistent in true false; do
    for op in "${_SP_APPLY_OPS[@]}"; do
      file=$(_sp_file_for "$op" "$persistent")
      [ "$(_sp_count "$file" "$names")" -gt 0 ] || continue
      _sp_apply_op "$op" "$file" "$dest" "$names"
      [ "$persistent" = false ] && _sp_drop "$file" "$names"
    done
  done

  if [ -n "$names" ]; then
    echo "💫 Applied set(s): $names. Persistent (--) sets were kept; one-time (-) sets were cleared. Everything else stays buffered."
  else
    echo "💫 Buffer apply complete. Persistent (--) buffers were kept. One-time (-) buffers were cleared."
  fi
}

_sp_apply_op() {              # <op> <file> <dest> [names-csv]
  case "$1" in
    cp) staging_copy_apply     "$2" "$3" "${4:-}" ;;
    mv) staging_move_apply     "$2" "$3" "${4:-}" ;;
    sc) staging_shortcut_apply "$2" "$3" "${4:-}" ;;
    bm) staging_bookmark_apply "$2" "$3" "${4:-}" ;;
  esac
}

# ─────────────────────────────────────────────
#  Buffer viewer (v-)
# ─────────────────────────────────────────────

# One set of a buffer (name "" = the flat, unnamed items): numbered paths, remove items.
# $5 = 1 when the buffer also holds named sets (so the flat items are one row among others).  Returns when the user goes back (u).
_sp_view_set() {
  local label="$1" file="$2" op="$3" name="$4" grouped="${5:-0}" where="" bv_choice rm_input confirm
  [ -n "$name" ] && where=" › $name"
  [ -z "$name" ] && [ "$grouped" = 1 ] && where=" › flat items"

  while true; do
    local -a list=()
    _sp_load_set list "$file" "$name"

    if [ -n "$name" ] && [ ${#list[@]} -eq 0 ]; then
      echo "📜  Set '$name' is empty now — back to the $label buffer"
      return 0
    fi

    _mc_header "📋 $label buffer${where} (${#list[@]}):"
    if [ ${#list[@]} -eq 0 ]; then
      echo "  (empty)"
    else
      local -a rows=()
      local p
      for p in "${list[@]}"; do
        if [ -e "$p" ]; then rows+=("$p"); else rows+=("$p  🔴 missing"); fi
      done
      _mc_options 1 "${rows[@]}"
    fi

    if [ -n "$name" ]; then
      _mc_footer "x:Remove item(s)" "n:Rename set" "clr:Clear set $name" "u:Back" "q:Quit"
    elif [ "$grouped" = 1 ]; then
      _mc_footer "x:Remove item(s)" "n:Name these items" "clr:Clear the flat items" "u:Back" "q:Quit"
    else
      _mc_footer "x:Remove item(s)" "clr:Clear entire $label buffer" "u:Back" "q:Quit"
    fi
    read -e -p "$label buffer${where}: " bv_choice

    case "$bv_choice" in
      x|X)
        if [ ${#list[@]} -eq 0 ]; then
          echo "🔴  Nothing to remove"
          continue
        fi
        read -e -p "Item number(s) to remove (e.g. 1,3 or 2-4): " rm_input
        local rm_indices
        rm_indices=($(parse_selection "$rm_input" "${#list[@]}"))
        if [ ${#rm_indices[@]} -eq 0 ]; then
          echo "❌ No valid numbers entered"
          continue
        fi
        _sp_drop_items "$file" "$name" "${rm_indices[@]}"
        echo "💫 Removed ${#rm_indices[@]} item(s) from the $label buffer${where}"
        ;;
      n|N)
        if [ -z "$name" ] && [ "$grouped" != 1 ]; then echo "🔴  These items have no name — name them with  c-1,3 as <name>  (or from the buffer list when it holds sets)"; continue; fi
        _sp_view_rename "$label" "$file" "$op" "$name" && { name="$_SP_NEW_NAME"; where=" › $name"; grouped=0; }
        ;;
      clr|CLR)
        if [ -n "$name" ]; then
          _bvk_yn confirm "Clear set '$name' from the $label buffer?" -d n -i "🗑️" || confirm=n
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then _sp_drop "$file" "$name"; echo "🗑️  Set '$name' cleared"; return 0
          else echo "🚫 Cancelled"; fi
        else
          local what="the $label buffer"
          [ "$grouped" = 1 ] && what="the flat items of the $label buffer"
          _bvk_yn confirm "Clear $what?" -d n -i "🗑️" || confirm=n
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            _sp_drop_unnamed "$file"
            echo "🗑️  $label buffer cleared"
            return 0
          else
            echo "🚫 Cancelled"
          fi
        fi
        ;;
      u|U|"")
        return 0
        ;;
      q|Q)
        _bvk_quit; return 0
        ;;
      *)
        _bvk_invalid
        ;;
    esac
  done
}

# Rename set <old> ("" = give the flat items a name) in <file>.  A name that is taken follows Settings → Buffers (add / replace / deny / ask).
# Returns 0 and sets _SP_NEW_NAME when something was renamed.
_SP_NEW_NAME=""
_sp_view_rename() {
  local label="$1" file="$2" op="$3" old="$4" new
  read -e -r -p "New name${old:+ for '$old'}: " new
  [ "${_CM_ABORT:-0}" = 1 ] && return 1
  new="${new#"${new%%[![:space:]]*}"}"; new="${new%"${new##*[![:space:]]}"}"
  [ -z "$new" ] && { echo "🚫 Cancelled"; return 1; }
  if ! _bb_alias_ok "$new"; then echo "🔴  A name may use letters, digits, spaces and . _ @ + -  (1-48 characters)."; return 1; fi
  [ "$new" = "$old" ] && return 1
  _sp_conflict_decide "$op" "$file" "$new" || return 1
  new="$_SP_CF_NAME"
  [ "$new" = "$old" ] && return 1
  [ "$_SP_CF" = replace ] && _sp_drop "$file" "$new"
  _sp_rename_set "$file" "$old" "$new"
  echo "💫 ${old:+'$old' }renamed to '$new' in the $label buffer"
  _SP_NEW_NAME="$new"
  return 0
}

# One buffer: its sets (and the flat items) as a list; pick a number to open one.
_sp_view_one_buffer() {
  local label="$1" file="$2" op="$3" bv_choice rm_input rn_input confirm

  while true; do
    local -a names=() flat=() rows=() rowname=()
    _sp_names names "$file"

    # no named set at all: the plain list of paths, as it always was
    if [ ${#names[@]} -eq 0 ]; then _sp_view_set "$label" "$file" "$op" "" 0; return 0; fi

    _sp_load_set flat "$file" ""
    local nm
    for nm in "${names[@]}"; do
      local -a cnt_arr=()
      _sp_load_set cnt_arr "$file" "$nm"
      rows+=("$nm >  (${#cnt_arr[@]})"); rowname+=("$nm")
    done
    [ ${#flat[@]} -gt 0 ] && { rows+=("flat items (no name) >  (${#flat[@]})"); rowname+=(""); }

    _mc_header "📋 $label buffer ($(_sp_count "$file")):"
    _mc_options 1 "${rows[@]}"
    _mc_footer "x:Remove item(s)" "n:Rename set" "clr:Clear entire $label buffer" "u:Back" "q:Quit"
    read -e -p "$label buffer: " bv_choice

    case "$bv_choice" in
      [0-9]*)
        if [[ "$bv_choice" =~ ^[0-9]+$ ]] && [ "$bv_choice" -ge 1 ] && [ "$bv_choice" -le ${#rows[@]} ]; then
          _sp_view_set "$label" "$file" "$op" "${rowname[$((bv_choice-1))]}" 1
        else
          _bvk_invalid
        fi
        ;;
      x|X)
        read -e -p "Set number(s) to remove (e.g. 1,3 or 2-4): " rm_input
        local rm_indices ri
        rm_indices=($(parse_selection "$rm_input" "${#rows[@]}"))
        if [ ${#rm_indices[@]} -eq 0 ]; then
          echo "❌ No valid numbers entered"
          continue
        fi
        local drop_csv=""
        for ri in "${rm_indices[@]}"; do
          if [ -z "${rowname[$((ri-1))]}" ]; then _sp_drop_unnamed "$file"; else drop_csv+="${rowname[$((ri-1))]},"; fi
        done
        [ -n "$drop_csv" ] && _sp_drop "$file" "${drop_csv%,}"
        echo "💫 Removed ${#rm_indices[@]} set(s) from the $label buffer"
        ;;
      n|N)
        read -e -p "Set number to rename: " rn_input
        if [[ "$rn_input" =~ ^[0-9]+$ ]] && [ "$rn_input" -ge 1 ] && [ "$rn_input" -le ${#rows[@]} ]; then
          _sp_view_rename "$label" "$file" "$op" "${rowname[$((rn_input-1))]}"
        else
          echo "❌ Enter the number of one set"
        fi
        ;;
      clr|CLR)
        _bvk_yn confirm "Clear the entire $label buffer?" -d n
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          : > "$file"
          echo "🗑️  $label buffer cleared"
          return 0
        else
          echo "🚫 Cancelled"
        fi
        ;;
      u|U|"")
        return 0
        ;;
      q|Q)
        _bvk_quit; return 0
        ;;
      *)
        _bvk_invalid
        ;;
    esac
  done
}

# The buffers v- lists, in the order of its numbers (1-8 as always, then Select):  op  persistent  menu-name
_SP_VIEW_ROWS=("cp true" "mv true" "sc true" "bm true" "cp false" "mv false" "sc false" "bm false" "sl true" "sl false")

handle_staging_view() {
  _sp_ensure_store
  local v_choice confirm
  while true; do
    local -a rows=()
    local r op persistent file n nsets mode
    local -a nm=()
    for r in "${_SP_VIEW_ROWS[@]}"; do
      op="${r% *}"; persistent="${r#* }"
      file=$(_sp_file_for "$op" "$persistent")
      n=$(_sp_count "$file"); _sp_names nm "$file"; nsets=${#nm[@]}
      if [ "$persistent" = true ]; then mode="persistent ($(_sp_op_pfx "$op")--)"; else mode="once ($(_sp_op_pfx "$op")-)"; fi
      local cell; printf -v cell '%-10s%-19s(%s item(s)' "$(_sp_op_label "$op")" "$mode" "$n"
      [ "$nsets" -gt 0 ] && cell+=", $nsets set(s)"
      rows+=("$cell)")
    done

    _mc_header "🗂️  Shortpath buffers"
    _mc_options 1 "${rows[@]}"
    _mc_footer "clr:Clear ALL buffers" "u:Back" "q:Quit"
    read -e -p "View buffer: " v_choice

    case "$v_choice" in
      [0-9]|10)
        if [ "$v_choice" -ge 1 ] && [ "$v_choice" -le ${#_SP_VIEW_ROWS[@]} ]; then
          r="${_SP_VIEW_ROWS[$((v_choice-1))]}"; op="${r% *}"; persistent="${r#* }"
          _sp_view_one_buffer "$(_sp_op_label "$op") ($([ "$persistent" = true ] && echo persistent || echo once))" "$(_sp_file_for "$op" "$persistent")" "$op"
        else
          _bvk_invalid
        fi
        ;;
      clr|CLR)
        _bvk_yn confirm "Clear ALL ten buffers? This can't be undone." -d n
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          for r in "${_SP_VIEW_ROWS[@]}"; do : > "$(_sp_file_for "${r% *}" "${r#* }")"; done
          echo "🗑️  All buffers cleared"
        else
          echo "🚫 Cancelled"
        fi
        ;;
      u|U|"")
        return 0
        ;;
      q|Q)
        _bvk_quit; return 0
        ;;
      *)
        _bvk_invalid
        ;;
    esac
  done
}
