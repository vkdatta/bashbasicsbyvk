#!/usr/bin/env bash
# bashbasicsbyvk_chmod.sh — the `chmod-N` command: an interactive chmod for the numbered items.
# ════════════════════════════════════════════════════════════════════════════
#  chmod-1,3   chmod-1-5   chmod-a   chmod-a-2        (the same item lists as eb- z- up-: _sp_guard_and_resolve)
#
#      🫅🏻 Change Mode
#      [Owner] Group Others                     three tabs: who the permissions are for  (tab bar = tabmenu, tappable)
#      Set permissions for the owner …          one plain-words line (CHMOD|owner in the Settings description table)
#       1) notes.txt      [R] [W] [ ]            one row per item;  [R] green · [W] blue · [X] red,  [ ] = off
#
#  Keys (the Select: line is the cell cursor, like a spreadsheet):
#      →  on an EMPTY line        next tab (Owner → Group → Others), ← the tab before        (the app's own tab keys)
#      1  then →                  the line becomes  1-RA  (row 1, Read, Active)  or  1-RD  (Read, Disabled): that is the cell
#      →  ←  on a cell            R → W → X and back;  ← on R goes back to the row number
#      ↑  ↓  on a cell            the same column of the row above / below
#      Enter on  1-RA             switches it off:  the line becomes  1-RD  (and 1-RD → 1-RA)
#      Enter on  1                the same as → : opens the R cell of row 1
#      tap a [R] [W] [X]          switches that permission;  tap a name = the row;  tap a tab = that tab
#  A switch runs the real chmod at once:  chmod u+r  /  u-r  (owner = u, group = g, others = o).  The screen then reads the file again,
#  so what it shows is what the file system says.  A refusal (not your file, read-only disk) is shown in the header, nothing is guessed.
#
#  Folders: Settings › Change mode › Folders decides what a switch on a FOLDER reaches:  off = the folder only (default) ·
#  on = the folder and everything inside it (children first, links are never followed) · ask = a yes / no question each time.
#
#  Built from what exists: _xui_loop / _xui_screen (bashbasicsbyvk_xui.sh), the tab template (bashbasicsbyvk_tabmenu.sh), the item
#  resolver (bashbasicsbyvk_staging_helpers.sh), the choice box _bvk_yn.  Two small hooks of the shared prompt serve the cell cursor and
#  are empty everywhere else:  _vp_nav_fn / _vp_click_fn (browse.sh) and _TE_LR_PASS (textedit.sh).
# ════════════════════════════════════════════════════════════════════════════

_CHM_TAB=owner
_CHM_HL=0                 # the highlighted row, kept across every redraw of the screen
_CHM_ROW=0                # the row of the cell cursor (0 = none) …
_CHM_COL=""               # … and its column: R | W | X
_CHM_MSG=""               # the last result / refusal, shown in the header
_CHM_ST=""                # _chm_st result: A (permission on) | D (off)
_CHM_FULL=0               # 1 = a question box was on the screen: the next redraw is a full one
_CHM_NW=8                 # width of the name column
_CHM_DW=2                 # digits of the row number column
_CHM_C0=0                 # 0-based screen column of the first cell (the tap hit-test)
declare -ga _CHM_PATHS=() _CHM_MODE=()     # per item: its absolute path, its mode as a decimal number

# ── Tabs: defined once in the master template (bashbasicsbyvk_tabmenu.sh) ──
_tm_define chm _CHM_TAB "🫅🏻 Change Mode" "CHMOD" owner:"Owner" group:"Group" others:"Others"

# ── the mode of an item, read from the file system ───────────────────────────────────────────────
_chm_stat_one() {            # SLOT -> _CHM_MODE[SLOT] (decimal); 1 = unreadable
  local p="${_CHM_PATHS[$1]}" o
  [[ "$p" == /* ]] || p="./$p"
  o=$(stat -L -c '%a' "$p" 2>/dev/null) || o=$(stat -L -f '%Lp' "$p" 2>/dev/null) || return 1
  [[ "$o" =~ ^[0-7]{1,4}$ ]] || return 1
  _CHM_MODE[$1]=$(( 8#$o ))
  return 0
}
_chm_stat_all() {            # every item again; one stat call for the lot, one by one only when it fails
  local -a out=(); local i o
  mapfile -t out < <(stat -L -c '%a' "${_CHM_PATHS[@]}" 2>/dev/null)
  if (( ${#out[@]} == ${#_CHM_PATHS[@]} )); then
    for i in "${!out[@]}"; do [[ "${out[i]}" =~ ^[0-7]{1,4}$ ]] && _CHM_MODE[$i]=$(( 8#${out[i]} )) || _chm_stat_one "$i"; done
    return 0
  fi
  for i in "${!_CHM_PATHS[@]}"; do _chm_stat_one "$i"; done
  return 0
}

# ── one permission of one item, for the current tab ──────────────────────────────────────────────
_chm_on() {                  # SLOT COL -> 0 when that permission is on for the current tab's class
  local b sh
  case "$2" in R) b=4 ;; W) b=2 ;; *) b=1 ;; esac
  case "$_CHM_TAB" in owner) sh=6 ;; group) sh=3 ;; *) sh=0 ;; esac
  (( (${_CHM_MODE[$1]:-0} >> sh) & b ))
}
_chm_st() { if _chm_on "$1" "$2"; then _CHM_ST=A; else _CHM_ST=D; fi; }      # SLOT COL -> _CHM_ST

# ── rows ──────────────────────────────────────────────────────────────────────────────────────────
_chm_geometry() {            # the name column and the cell columns from the screen width (rows are cut, never wrapped)
  local p n max=4 cnt=${#_CHM_PATHS[@]}
  for p in "${_CHM_PATHS[@]}"; do n="${p##*/}"; (( ${#n} + 1 > max )) && max=$(( ${#n} + 1 )); done
  _CHM_DW=${#cnt}; (( _CHM_DW < 2 )) && _CHM_DW=2
  _vp_usable
  _CHM_NW=$(( _vp_usable_w - (_CHM_DW + 3) - 2 - 11 ))
  (( _CHM_NW > max )) && _CHM_NW=$max
  (( _CHM_NW < 4 )) && _CHM_NW=4
  _CHM_C0=$(( _CHM_DW + 3 + _CHM_NW + 2 ))
}
_chm_cell() {                # SLOT COL UNDERLINED(0|1) -> _CHM_CELL: [R] green · [W] blue · [X] red · [ ] off
  local clr
  if _chm_on "$1" "$2"; then
    case "$2" in R) clr=32 ;; W) clr=34 ;; *) clr=31 ;; esac
    _CHM_CELL=$'\033['"$clr"m"[$2]"$'\033[39m'              # \e[39m, never \e[0m: the highlighted row (reverse video) must stay highlighted
  else _CHM_CELL='[ ]'; fi
  (( $3 )) && _CHM_CELL=$'\033[4m'"$_CHM_CELL"$'\033[24m'
  return 0
}

chm_build() {
  local p; local -a names=()
  for p in "${_CHM_PATHS[@]}"; do names+=("${p##*/}"); done
  _xui_begin_items "${names[@]}"
  _chm_geometry
  (( _CHM_HL > ${#items[@]} )) && _CHM_HL=${#items[@]}
  _hl_index=$_CHM_HL
  return 0
}
chm_row() {
  _xui_slot "$1"
  local k=$_XUI_SLOT i=$1 name pad c u cells=()
  name="${_CHM_PATHS[$k]##*/}"; [ -d "${_CHM_PATHS[$k]}" ] && name+="/"
  (( ${#name} > _CHM_NW )) && name="${name:0:_CHM_NW-1}…"
  _bvk_dispw "$name"
  printf -v pad '%*s' $(( _CHM_NW > _BVK_W ? _CHM_NW - _BVK_W : 0 )) ''
  for c in R W X; do
    u=0; (( i == _CHM_ROW )) && [ "$c" = "$_CHM_COL" ] && u=1
    _chm_cell "$k" "$c" "$u"; cells+=("$_CHM_CELL")
  done
  printf -v _vp_line ' %*d) %s%s  %s %s %s' "$_CHM_DW" "$i" "$name" "$pad" "${cells[0]}" "${cells[1]}" "${cells[2]}"
}
chm_header() { _tm_head -n "$_CHM_MSG" chm; }            # template V3PX4Y (CHMOD|owner · CHMOD|group · CHMOD|others)
chm_footer() { _tm_footer; }                          # u q h cc: every other key is listed by cc

# ── the cell cursor: ← → ↑ ↓ and the tap (hooks of the shared prompt, set for this screen only) ──────────────
_chm_cell_set() {            # ROW COL ("" = the row alone): the highlight, the line and the underlined cell follow
  local n="$1" col="$2" old="${_CHM_ROW:-0}"
  _CHM_ROW=$n; _CHM_COL=$col
  (( old >= 1 )) && unset "_vp_rowcache[$old]"
  unset "_vp_rowcache[$n]"
  _nav_jump_to "$n"                                      # the highlight (it also types the row number: replaced just below)
  if [ -n "$col" ]; then _xui_slot "$n"; _chm_st "$_XUI_SLOT" "$col"; _buf="$n-$col$_CHM_ST"; else _buf="$n"; fi
  _pos=${#_buf}
  _vp_repaint_row "$n"
  [ -n "${_vp_input_fn:-}" ] && "$_vp_input_fn"
  return 0
}
_chm_nav() {                 # KEY -> 0 when the key was taken here
  local key="$1" n col t
  [[ "$_buf" =~ ^([0-9]+)(-([RWXrwx])[AaDd]?)?$ ]] || return 1
  n=$(( 10#${BASH_REMATCH[1]} )); col="${BASH_REMATCH[3]^^}"
  _vp_count
  (( n >= 1 && n <= _vp_n )) || return 1
  if [ -z "$col" ]; then                                 # only a row number typed: ← → still move the caret, → at its end opens the cell
    case "$key" in
      left)  (( _pos > 0 )) && { _pos=$(( _pos - 1 )); "$_vp_input_fn"; }; return 0 ;;
      right) if (( _pos < ${#_buf} )); then _pos=$(( _pos + 1 )); "$_vp_input_fn"; else _chm_cell_set "$n" R; fi; return 0 ;;
      *) return 1 ;;
    esac
  fi
  case "$key" in
    right) case "$col" in R) col=W ;; W) col=X ;; esac ;;
    left)  case "$col" in R) col="" ;; W) col=R ;; X) col=W ;; esac ;;
    up)    t=$(( n - 1 )); (( t < 1 )) && t=1; n=$t ;;
    down)  t=$(( n + 1 )); (( t > _vp_n )) && t=$_vp_n; n=$t ;;
    *) return 1 ;;
  esac
  _chm_cell_set "$n" "$col"
  return 0
}
_chm_click() {               # a tap on a row at column _MS_X: on a cell it sets the line to that cell (the screen then accepts it); 1 = not a cell
  local c=$(( _MS_X - 1 - _CHM_C0 )) k
  local -a cols=(R W X)
  (( c >= 0 )) || return 1
  k=$(( c / 4 )); (( k <= 2 )) || return 1
  _chm_cell_set "$_MS_ITEM" "${cols[k]}"
  return 0
}

# ── switching ────────────────────────────────────────────────────────────────────────────────────────
_chm_toggle() {              # SLOT COL -> chmod, then read the file again;  0 = done (the message is in _CHM_MSG)
  local k="$1" col="$2" p="${_CHM_PATHS[$1]}" cls who what sign spec rec="${chmod_recursive_mode:-off}" ans err name="${_CHM_PATHS[$1]##*/}"
  [[ "$p" == /* ]] || p="./$p"
  case "$_CHM_TAB" in owner) cls=u; who=owner ;; group) cls=g; who=group ;; *) cls=o; who=others ;; esac
  case "$col" in R) what=read ;; W) what=write ;; *) what=execute ;; esac
  if _chm_on "$k" "$col"; then sign=-; else sign=+; fi
  spec="$cls$sign${col,,}"
  if [ -d "$p" ] && [ ! -L "$p" ] && [ "$rec" = ask ]; then
    _CHM_FULL=1
    _bvk_yn ans "Switch $what for $who on everything inside ${name}/ too?" -c
    case "$ans" in y) rec=on ;; n) rec=off ;; *) _CHM_MSG="🚫 Cancelled — nothing changed"; return 1 ;; esac
  fi
  if [ -d "$p" ] && [ ! -L "$p" ] && [ "$rec" = on ]; then
    err=$(find -P "$p" -depth ! -type l -exec chmod "$spec" {} + 2>&1) || { _CHM_MSG="🔴 $name: ${err%%$'\n'*}"; _chm_stat_one "$k"; return 1; }
  else
    err=$(chmod "$spec" "$p" 2>&1) || { _CHM_MSG="🔴 $name: ${err#chmod: }"; _CHM_MSG="${_CHM_MSG%%$'\n'*}"; return 1; }
  fi
  _chm_stat_one "$k"
  if _chm_on "$k" "$col"; then _CHM_MSG="💫 $name — $who $what: on"; else _CHM_MSG="💫 $name — $who $what: off"; fi
  [ -d "$p" ] && [ "$rec" = on ] && _CHM_MSG+=" (inside too)"
  return 0
}

_chm_cmd() {                 # the _xui_loop handler: 0 redraw · 1 nothing · 3 redraw in place · 9 not mine
  local c="$1" n col
  _CHM_FULL=0
  case "$c" in
    __sw_tab_right__|__sw_tab_left__)
      _CHM_HL=${_hl_index:-0}; _CHM_ROW=0; _CHM_COL=""; _CHM_MSG=""
      _tm_key chm "$c" nowrap || return 1
      return 3 ;;
    rf) _chm_stat_all; _CHM_MSG=""; _CHM_HL=${_hl_index:-0}; return 0 ;;
    [0-9]*)
      if [[ "$c" =~ ^([0-9]+)-([RWXrwx])([AaDd]?)$ ]]; then
        n=$(( 10#${BASH_REMATCH[1]} )); col="${BASH_REMATCH[2]^^}"
        _xui_row "$n" || { _bvk_invalid; return 0; }
        _CHM_HL=$n; _CHM_ROW=$n; _CHM_COL=$col
        _chm_toggle "$_XUI_SLOT" "$col"
        _chm_st "$_XUI_SLOT" "$col"; _CC_PREFILL="$n-$col$_CHM_ST"            # the line starts as  1-RD  (the new state): Enter again switches back
      elif [[ "$c" =~ ^[0-9]+$ ]]; then
        n=$(( 10#$c ))
        _xui_row "$n" || { _bvk_invalid; return 0; }
        _CHM_HL=$n; _CHM_ROW=$n; _CHM_COL=R; _CHM_MSG=""
        _chm_st "$_XUI_SLOT" R; _CC_PREFILL="$n-R$_CHM_ST"                    # a row number + Enter = the same as →
      else _bvk_invalid; return 0; fi
      [ "$_CHM_FULL" = 1 ] && return 0
      return 3 ;;
    *) return 9 ;;
  esac
}

# chmod-<items>
handle_chmod() {
  local raw="$1" i more=""
  if [ "${_GD_ACTIVE:-0}" = 1 ]; then echo "⛅ Google Drive items have no permissions to change."; return 0; fi
  _sp_guard_and_resolve "${raw#chmod-}" "chmod-" || return 0
  _CHM_PATHS=("${sp_resolved[@]}"); _CHM_MODE=()
  _chm_stat_all
  local -a keep=() bad=()                                 # an item whose mode can't be read (gone, no access) is left out and named
  for i in "${!_CHM_PATHS[@]}"; do
    if [ -n "${_CHM_MODE[$i]+x}" ]; then keep+=("$i"); else bad+=("${_CHM_PATHS[$i]##*/}"); fi
  done
  if (( ${#bad[@]} )); then
    (( ${#bad[@]} > 5 )) && more=" … and $(( ${#bad[@]} - 5 )) more"
    echo "🔴  Can't read the permissions of: ${bad[*]:0:5}$more"
  fi
  (( ${#keep[@]} )) || return 0
  local -a paths=() modes=()
  for i in "${keep[@]}"; do paths+=("${_CHM_PATHS[$i]}"); modes+=("${_CHM_MODE[$i]}"); done
  _CHM_PATHS=("${paths[@]}"); _CHM_MODE=("${modes[@]}")
  _CHM_TAB=owner; _CHM_HL=0; _CHM_ROW=0; _CHM_COL=""; _CHM_MSG=""
  _xui_enter
  _xui_screen chm
  _vp_nav_fn=_chm_nav; _vp_click_fn=_chm_click
  _TE_LR_PASS='^[0-9]+(-[RWXrwx][AaDd]?)?$'               # ← → on a typed row number or cell (1 · 1-RA) go to _chm_nav, not to the text caret
  _xui_loop _chm_cmd
  _xui_leave
  return 0
}
