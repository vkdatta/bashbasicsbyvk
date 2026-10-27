declare -F _lt_b >/dev/null 2>&1 || { _lt_b(){ :; }; _lt_e(){ :; }; _lt_enter(){ :; }; _lt_ready(){ :; }; _lt_mark(){ :; }; }   # loadtime hooks: no-ops when the recorder is not loaded
_vp_rows_now=0
_vp_cols_now=0
_vp_size_pending=""

_vp_read_size() {
  local sz r c
  _vp_pr=""; _vp_pc=""
  sz=$(stty size 2>/dev/null)
  r="${sz%% *}"; c="${sz##* }"
  if [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -gt 0 ] \
     && [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ]; then
    _vp_pr="$r"; _vp_pc="$c"
    return 0
  fi
  r=$(tput lines 2>/dev/null); c=$(tput cols 2>/dev/null)
  if [[ "$r" =~ ^[0-9]+$ ]] && [ "$r" -gt 0 ] \
     && [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -gt 0 ]; then
    _vp_pr="$r"; _vp_pc="$c"
    return 0
  fi
  return 1
}

_vp_probe_size() {
  if _vp_read_size; then
    _vp_rows_now="$_vp_pr"; _vp_cols_now="$_vp_pc"
  elif [ "$_vp_rows_now" -gt 0 ] 2>/dev/null; then
    : 
  else
    _vp_rows_now=24; _vp_cols_now=80   
  fi
}

_term_rows() {
  [ "$_vp_rows_now" -gt 0 ] 2>/dev/null || _vp_probe_size
  echo "$_vp_rows_now"
}

_term_cols() {
  [ "$_vp_cols_now" -gt 0 ] 2>/dev/null || _vp_probe_size
  echo "$_vp_cols_now"
}

# ── one-row input fitting ───────────────────────────────────────────────────────────────────
# Every typed-line editor redraws its row with  \r \033[K <prompt><text>  and then moves the cursor back with \033[nD.
# That only works while prompt+text fit ONE terminal row. When a long link is pasted on a narrow screen (a phone) the
# text wraps, \r / \033[K / \033[nD then only act on the LAST wrapped row, so every keystroke prints the prompt again
# one row lower ("Paste link ..." 60 times). These helpers keep the row to ONE line: the text scrolls sideways inside
# the row (a "<" marks hidden text on the left) and the hint row is clipped, so nothing ever wraps.
_bvk_is_ascii() { local LC_ALL=C; [[ "$1" != *[!\ -~]* ]]; }

# ── THE one cell-width rule for a non-ASCII character ───────────────────────────────────────────────────────
# _vp_cpw <codepoint> -> _VP_CPW = 0 | 1 | 2.  EVERY width measurement in the app (_bvk_dispw, _vp_cells, so every
# prompt caret, row fit and erase count) goes through THIS function.  Never write another range table.
# It follows wcwidth / Unicode: a character is 2 cells only when it is a wide (East Asian W/F) character or has
# Emoji_Presentation=Yes (📁 👤 💫 🔴 ✅ ❌ ⭐ ...).  Emoji that are text-by-default (🗄 🗑 👁 🖥 ⚠ ℹ ✏ ⚙ ⏱ ◀ ▶ ...) are 1 cell even
# when followed by U+FE0F: Termux and most terminals draw them 1 cell wide, and U+FE0F itself adds nothing.
# (Counting 🗄️ as 2 put the caret one cell too far right, "hello |", on every prompt that began with such an emoji.)
_VP_TEXT_EMOJI=" 1F321 1F324-1F32C 1F336 1F37D 1F396-1F397 1F399-1F39B 1F39E-1F39F 1F3CB-1F3CE 1F3D4-1F3DF 1F3F3 1F3F5 1F3F7 1F43F 1F441 1F4FD 1F549-1F54A 1F56F-1F570 1F573-1F579 1F587 1F58A-1F58D 1F590 1F5A5 1F5A8 1F5B1-1F5B2 1F5BC 1F5C2-1F5C4 1F5D1-1F5D3 1F5DC-1F5DE 1F5E1 1F5E3 1F5E8 1F5EF 1F5F3 1F5FA 1F6CB 1F6CD-1F6CF 1F6E0-1F6E5 1F6E9 1F6F0 1F6F3 "
_VP_WIDE_BMP=" 231A-231B 23E9-23EC 23F0 23F3 25FD-25FE 2614-2615 2648-2653 267F 2693 26A1 26AA-26AB 26BD-26BE 26C4-26C5 26CE 26D4 26EA 26F2-26F3 26F5 26FA 26FD 2705 270A-270B 2728 274C 274E 2753-2755 2757 2795-2797 27B0 27BF 2B1B-2B1C 2B50 2B55 "
_vp_in_set() {   # $1 codepoint (decimal)  $2 space list of HEX or HEX-HEX  -> 0 when inside
  local cp=$1 r lo hi
  for r in $2; do
    lo=$(( 16#${r%-*} )); hi=$(( 16#${r#*-} ))
    (( cp >= lo && cp <= hi )) && return 0
  done
  return 1
}
_vp_cpw() {
  local cp=$1
  _VP_CPW=1
  if   (( cp < 0x300 )); then return 0
  elif (( (cp >= 0x300 && cp <= 0x36F) || (cp >= 0x200B && cp <= 0x200F) || (cp >= 0xFE00 && cp <= 0xFE0F) )); then _VP_CPW=0
  elif (( (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0xA4CF) || (cp >= 0xAC00 && cp <= 0xD7A3) \
       || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE30 && cp <= 0xFE6F) || (cp >= 0xFF00 && cp <= 0xFF60) \
       || (cp >= 0xFFE0 && cp <= 0xFFE6) || (cp >= 0x20000 && cp <= 0x3FFFD) )); then _VP_CPW=2
  elif (( cp >= 0x2300 && cp <= 0x2BFF )); then
    _vp_in_set "$cp" "$_VP_WIDE_BMP" && _VP_CPW=2
  elif (( cp >= 0x1F000 && cp <= 0x1FAFF )); then
    if   _vp_in_set "$cp" "$_VP_TEXT_EMOJI"; then _VP_CPW=1
    elif (( (cp >= 0x1F300 && cp <= 0x1F64F) || (cp >= 0x1F680 && cp <= 0x1F6FF) || (cp >= 0x1F900 && cp <= 0x1F9FF) \
         || (cp >= 0x1FA70 && cp <= 0x1FAFF) || cp == 0x1F004 || cp == 0x1F0CF || cp == 0x1F18E \
         || (cp >= 0x1F191 && cp <= 0x1F19A) || (cp >= 0x1F201 && cp <= 0x1F251) )); then _VP_CPW=2
    fi
  fi
}

_bvk_dispw() {   # $1 text -> _BVK_W = display cells (ANSI colour codes ignored, wide chars/emoji = 2, combining = 0)
  local s="$1" i c cp w=0 n
  while [[ "$s" == *$'\033'* ]] && [[ "$s" =~ $'\033'\[[0-9\;?]*[A-Za-z] ]]; do s="${s/"${BASH_REMATCH[0]}"/}"; done
  if _bvk_is_ascii "$s"; then _BVK_W=${#s}; return 0; fi
  if (( ${#s} > 2000 )); then
    # a huge text (a big paste): in a multibyte locale every step over 100 000 characters is slow, so measure it bytewise.
    # printable ASCII = 1 cell each; any other character is 2-4 bytes for 1-2 cells, so half its bytes is a fair estimate.
    local LC_ALL=C rest
    rest="${s//[ -~]/}"                       # (two statements: LC_ALL must be set BEFORE this runs)
    _BVK_W=$(( ${#s} - ${#rest} + (${#rest} + 1) / 2 )); return 0
  fi
  n=${#s}
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9\ ._/:#=,\;-]) w=$(( w + 1 )) ;;
      *) printf -v cp '%d' "'$c" 2>/dev/null || cp=0
         if (( cp < 32 )); then :
         else _vp_cpw "$cp"; w=$(( w + _VP_CPW )); fi ;;
    esac
  done
  _BVK_W=$w
}

_bvk_cols() {   # -> _BVK_COLS (cached geometry, never below 20)
  [ "${_vp_cols_now:-0}" -gt 0 ] 2>/dev/null || _vp_probe_size
  _BVK_COLS="${_vp_cols_now:-80}"; [ "$_BVK_COLS" -ge 20 ] 2>/dev/null || _BVK_COLS=80
}

_bvk_clip() {   # $1 text [$2 max cells; default cols-1] -> _BVK_CLIP = text cut so it cannot wrap
  local s="$1" lim="$2"
  [ -n "$lim" ] || { _bvk_cols; lim=$(( _BVK_COLS - 1 )); }
  _bvk_dispw "$s"
  while (( _BVK_W > lim && ${#s} > 0 )); do s="${s:0:${#s}-1}"; _bvk_dispw "$s"; done
  _BVK_CLIP="$s"
}

# _bvk_hint_wrap TEXT [MAX_LINES=3] [WIDTH]  ->  _BVK_HINT_LN[] (the lines) · _BVK_HINT_N (how many, 0 for an empty text)
# The ONE rule for every suggestion row (cheat-code hints, notices): a text longer than one row EXPANDS onto the next rows, broken at
# spaces, the way a Settings description does (_st_desc_wrap), instead of being cut with "…".  Only a text that would need more than
# MAX_LINES rows is cut, with "…" on the last row.  A text that fits is returned untouched (its own spacing).
_bvk_hint_wrap() {
  local t="$1" max="${2:-3}" lim="${3:-}" x line="" cand
  local -a words
  _BVK_HINT_LN=(); _BVK_HINT_N=0
  [ -n "$t" ] || return 0
  [ -n "$lim" ] || { _bvk_cols; lim=$(( _BVK_COLS - 1 )); }
  (( lim < 8 )) && lim=8
  (( max < 1 )) && max=1
  _bvk_dispw "$t"
  if (( _BVK_W <= lim )); then _BVK_HINT_LN=("$t"); _BVK_HINT_N=1; return 0; fi
  builtin read -ra words <<< "$t"
  for x in "${words[@]}"; do
    if [ -z "$line" ]; then cand="$x"; else cand="$line $x"; fi
    _bvk_dispw "$cand"
    if (( _BVK_W <= lim )); then line="$cand"; continue; fi
    [ -n "$line" ] && _BVK_HINT_LN+=("$line")
    _bvk_dispw "$x"
    (( _BVK_W > lim )) && { _bvk_clip "$x" "$lim"; x="$_BVK_CLIP"; }       # one word wider than a row: cut it
    line="$x"
  done
  [ -n "$line" ] && _BVK_HINT_LN+=("$line")
  if (( ${#_BVK_HINT_LN[@]} > max )); then
    _BVK_HINT_LN=("${_BVK_HINT_LN[@]:0:max}")
    _bvk_clip "${_BVK_HINT_LN[max-1]}" $(( lim - 1 ))
    _BVK_HINT_LN[max-1]="${_BVK_CLIP}…"
  fi
  _BVK_HINT_N=${#_BVK_HINT_LN[@]}
  return 0
}

_BVK_FIT_S=0
# _bvk_fit_input PROMPT TEXT CURSOR [LEFT_MARGIN_CELLS]
#   -> _BVK_FIT_PROMPT (prompt, shortened if the screen is tiny) · _BVK_FIT (what to print after it) · _BVK_FIT_BACK (cells to
#      move the cursor left from the end of _BVK_FIT).   _BVK_FIT_S (first visible char) is kept between calls so the text does
#      not jump; set it to 0 when a new line starts.
_bvk_fit_input() {
  local p="$1" b="$2" pos="$3" lm="${4:-0}" cols avail pw len s tc wide=0 vis t i c
  _bvk_cols; cols=$(( _BVK_COLS - lm ))
  _bvk_dispw "$p"; pw=$_BVK_W
  while (( pw > cols - 12 && ${#p} > 1 )); do p="${p:1}"; _bvk_dispw "$p"; pw=$_BVK_W; done   # tiny screen: keep the prompt's tail
  _BVK_FIT_PROMPT="$p"
  avail=$(( cols - pw - 1 ))                      # one spare cell so the cursor never sits in the "pending wrap" column
  (( avail < 4 )) && avail=4
  len=${#b}; (( pos > len )) && pos=$len; (( pos < 0 )) && pos=0
  if ! _bvk_is_ascii "$b"; then                   # wide chars: leave room for their second cell
    # only the part around the cursor can be on screen: a 100 000-character paste must not be measured char by char
    local ws=0 we=$len
    if (( len > cols * 4 )); then ws=$(( pos - cols * 2 )); (( ws < 0 )) && ws=0; we=$(( ws + cols * 4 )); (( we > len )) && we=$len; fi
    for (( i=ws; i<we; i++ )); do c="${b:i:1}"; _bvk_dispw "$c"; (( _BVK_W > 1 )) && wide=$(( wide + 1 )); done
    avail=$(( avail - wide )); (( avail < 4 )) && avail=4
  fi
  s=${_BVK_FIT_S:-0}; (( s < 0 || s > len )) && s=0
  if (( len <= avail )); then s=0
  else
    (( pos - s > avail - (s > 0 ? 1 : 0) )) && s=$(( pos - (avail - 1) ))   # cursor ran off the right edge
    (( s > 0 && pos - s < 1 )) && { s=$(( pos - 1 )); (( s < 0 )) && s=0; }  # keep one char left of the cursor visible
    (( s > len - avail + 1 )) && s=$(( len - avail + 1 ))                   # do not leave an empty tail
    (( s < 0 )) && s=0
  fi
  _BVK_FIT_S=$s
  tc=$avail; (( s > 0 )) && tc=$(( avail - 1 ))
  vis="${b:s:tc}"
  t="$vis"; (( s > 0 )) && t="<$vis"
  _BVK_FIT="$t"
  t="${b:pos:$(( s + tc - pos > 0 ? s + tc - pos : 0 ))}"
  _bvk_dispw "$t"; _BVK_FIT_BACK=$_BVK_W
  _bvk_dispw "$_BVK_FIT"; _BVK_FIT_COL=$(( pw + _BVK_W - _BVK_FIT_BACK ))     # the cursor's column (the notice puts it back there)
}

_vp_check_resize() {
  _vp_resized=false
  _vp_read_size || return 1
  local nr="$_vp_pr" nc="$_vp_pc"
  if [ "$nr" = "$_vp_rows_now" ] && [ "$nc" = "$_vp_cols_now" ]; then
    _vp_size_pending=""
    return 1
  fi
  if [ "$_vp_size_pending" = "${nr}x${nc}" ]; then
    _vp_rows_now="$nr"; _vp_cols_now="$nc"
    _vp_size_pending=""
    return 0
  fi
  _vp_size_pending="${nr}x${nc}"
  return 1
}

_set_available_above() {
  local total_lines="$1" rows cur_row
  rows=$(_term_rows)
  cur_row=$(( total_lines < rows ? total_lines : rows ))
  _available_above=$(( cur_row - 1 ))
}

_repaint_line_above() {
  local dist="$1" content="$2"
  [ "$dist" -gt "$_available_above" ] && return 1
  builtin printf '\033[s\033[%dA\r\033[2K\033[?7l%s\033[?7h\033[u' "$dist" "$content"
}

declare -gA _vp_rowcache=()
declare -ga _vp_hdr_arr=()
declare -ga _vp_ftr_arr=()
_vp_mode="items"
_vp_rowtext_fn=""   # custom per-row renderer; empty = use display_items / _item_line_text
_vp_count_fn=""     # custom item counter; empty = use ${#items[@]}
_vp_start=1
_vp_end=0
_vp_page=0
_vp_n=0
_vp_top_n=0
_vp_footer_n=0
_vp_rows_printed=0
_blk_h=0
_vp_cols=80
_vp_width_margin=2
_vp_line=""
_vp_resized=false
_vp_poll_fast="0.5"
_vp_poll_slow="4"
_vp_poll_cur="0.5"
_vp_idle=0
_vp_rule="   ─────────────────────────────"

# The idle tick brings the mouse reports back once a hand-back is over (bashbasicsbyvk_mouse.sh).  A typed key brings them back at
# once; a byte of an escape sequence does not (the button release of the tap / the tail of a swipe is one, and it must not undo the
# hand-back): the read loops call this right after reading the first byte, which is their local  key.
_vp_poll_active() {
  _vp_idle=0; _vp_poll_cur="$_vp_poll_fast"
  if [ "${_BVK_MOUSE_PASS:-0}" = 1 ]; then
    if [ "${key-}" = $'\x1b' ]; then _bvk_mouse_rearm; else _bvk_mouse_rearm force; fi
  fi
  return 0
}
_vp_poll_tick() {
  [ "${_BVK_MOUSE_PASS:-0}" = 1 ] && _bvk_mouse_rearm
  _vp_idle=$(( _vp_idle + 1 ))
  (( _vp_idle > 12 )) && _vp_poll_cur="$_vp_poll_slow"
}

_vp_strip_ansi() {
  local s="$1" out=""
  while [[ "$s" == *$'\033['* ]]; do
    out+="${s%%$'\033['*}"
    s="${s#*$'\033['}"
    s="${s#*[a-zA-Z]}"
  done
  _vp_plain="$out$s"
}

# ---- THE width helpers: every menu / footer / smart-menu measures through these ----
# Display width of a string in terminal cells -> _vp_w.  ANSI is ignored, emoji and
# CJK count 2, variation selectors / joiners / combining marks count 0.
# (${#s} counts characters, not cells: a row with 📁 / 👤 is one cell wider than
#  its length, which is how a "fitting" line still wrapped on a phone.)
_vp_cells() {
  local s="$1" i c cp w=0
  _vp_strip_ansi "$s"; s="$_vp_plain"
  if [[ "$s" != *[![:ascii:]]* ]]; then _vp_w=${#s}; return 0; fi
  for ((i=0; i<${#s}; i++)); do
    c="${s:i:1}"
    if [[ "$c" == [[:ascii:]] ]]; then w=$(( w + 1 )); continue; fi
    builtin printf -v cp '%d' "'$c" 2>/dev/null || cp=0
    _vp_cpw "$cp"; w=$(( w + _VP_CPW ))
  done
  _vp_w=$w
}

# Usable width for ONE logical line: live terminal width minus the margin.
# Always reads the size first, so nothing ever works from a stale / zero width.
_vp_usable() {
  [ "$_vp_cols_now" -gt 0 ] 2>/dev/null || _vp_probe_size
  _vp_usable_w=$(( _vp_cols_now - _vp_width_margin ))
  (( _vp_usable_w < 8 )) && _vp_usable_w=8
}

_vp_fit() {
  local text="$1" limit s i c
  _vp_usable; limit=$_vp_usable_w
  # a text far longer than the screen (a big paste shown in a header) is cut first: measuring 100 000 characters one by one takes minutes
  (( ${#text} > limit * 20 )) && text="${text:0:limit*10}"
  _vp_cells "$text"
  if (( _vp_w <= limit )); then _vp_line="$text"; return 0; fi
  # too wide in CELLS: cut the plain text cell by cell and end with …
  _vp_strip_ansi "$text"; s="$_vp_plain"
  local out="" w=0
  for ((i=0; i<${#s}; i++)); do
    c="${s:i:1}"
    _vp_cells "$c"
    (( w + _vp_w > limit - 1 )) && break
    out+="$c"; w=$(( w + _vp_w ))
  done
  _vp_line="${out}…"
}

# Row model.  _vp_n = number of ITEMS (what the user numbers and selects).
#              _vp_R = number of screen ROWS (what scrolls / pages).
# They are equal except in Group by view (_vp_gv=1), where group header rows sit between
# the items: row -> item comes from _gv_row[], item -> row from _gv_irow[] (built by
# _gv_build in bashbasicsbyvk_displayer.sh, by the C helper).  Every caller outside this
# file keeps talking in ITEM numbers (_vp_ensure_visible, _vp_repaint_row, _hl_index …).
declare -g _vp_R=0 _vp_gv=0

# Group by only applies while the row map still matches items[] (cheap sanity check).
_vp_gv_check() {
  _vp_gv=0
  [ "${_gv_on:-false}" = true ] || return 0
  [ "$_vp_mode" == "items" ] || return 0
  [ -z "${_vp_rowtext_fn:-}" ] && [ -z "${_vp_count_fn:-}" ] || return 0
  [ "${imaginary_mode:-false}" = true ] && return 0
  [ "${_sw_in_mode:-0}" = 1 ] && return 0
  [ "${_fx_in_mode:-0}" = 1 ] && return 0
  local n=${#items[@]}
  (( n > 0 && n == _gv_n )) || return 0
  [ "${items[0]}" = "$_gv_first" ] && [ "${items[n-1]}" = "$_gv_last" ] || return 0
  _vp_gv=1
  return 0
}

_vp_count() {
  _vp_gv=0
  if [ -n "${_vp_count_fn:-}" ]; then
    $_vp_count_fn
    _vp_R=$_vp_n
    return 0
  fi
  if [ "$_vp_mode" == "imaginary" ]; then
    _vp_n=${#imaginary_map[@]}
  else
    _vp_n=${#items[@]}
    [ "${_gv_on:-false}" = true ] && _vp_gv_check
  fi
  _vp_R=$_vp_n
  (( _vp_gv )) && _vp_R=${#_gv_row[@]}
  return 0
}

# Items hidden above / below the visible rows (Group by view): _vp_ab / _vp_bl.
_vp_gv_hidden() {
  local r v
  _vp_ab=$_vp_n; _vp_bl=$_vp_n
  r=$_vp_start
  while (( r <= _vp_R )); do
    v="${_gv_row[$((r-1))]}"
    [[ "$v" == H* ]] || { _vp_ab=$(( v - 1 )); break; }
    r=$(( r + 1 ))
  done
  r=$_vp_end
  while (( r >= 1 )); do
    v="${_gv_row[$((r-1))]}"
    [[ "$v" == H* ]] || { _vp_bl=$(( _vp_n - v )); break; }
    r=$(( r - 1 ))
  done
}
_vp_row_text() {
  local i="$1" t
  if [ -n "${_vp_rowcache[$i]+x}" ]; then
    _vp_line="${_vp_rowcache[$i]}"
    return 0
  fi
  if [ -n "${_vp_rowtext_fn:-}" ]; then
    $_vp_rowtext_fn "$i"
    t="$_vp_line"
  elif [ "$_vp_mode" == "imaginary" ]; then
    t="${imaginary_lines[$((i-1))]}"
  else
    if $_vp_lazy_rows && declare -F _load_window >/dev/null 2>&1 \
       && (( _win_lo < 1 || i < _win_lo || i > _win_hi )); then
      _load_window "$i"      # keep the metadata window under the rows being drawn
    fi
    if declare -F _item_line_text_v >/dev/null 2>&1; then _item_line_text_v "$i"; t="$_ilt_out"; else t="$(_item_line_text "$i")"; fi
    (( _vp_gv )) && t="$_gv_pad$t"
  fi
  _vp_fit "$t"
  _vp_rowcache[$i]="$_vp_line"
  return 0
}

_vp_cache_reset() {
  unset _vp_rowcache
  declare -gA _vp_rowcache=()
  _vp_disp_ok=false
}

# Lists longer than this are NOT pre-formatted row by row. Pre-formatting walks
# every item in bash (a -d test + type checks + a pipe read per item): ~20-60 s
# for 200k files in force-show. Above the limit only the rows that are drawn get
# formatted (_vp_row_text -> _item_line_text_v) and the metadata window (C `meta`)
# follows the rows. Override with BVK_PRIME_MAX.
declare -g _vp_lazy_rows=false
declare -g _vp_meta_primed=false   # true while display_items runs in the prime subshell

_vp_prime_rows() {
  _lt_b "prepare rows (icons, sizes, names)"
  _vp_prime_rows_run
  _lt_e
}
_vp_prime_rows_run() {
  declare -F _gv_off >/dev/null 2>&1 && _gv_off
  [ "$_vp_mode" == "items" ] || return 0
  declare -F _lk_load >/dev/null 2>&1 && _lk_load     # 🔒 suffix needs the lock registry
  # If a custom row-text function is set it owns every row — display_items
  # must not pre-fill the cache or the custom icons are overwritten.
  [ -n "${_vp_rowtext_fn:-}" ] && return 0
  declare -F display_items >/dev/null 2>&1 || return 0
  _vp_count
  (( _vp_n == 0 )) && return 0
  # Group by: re-order items[] into groups + build the header rows (C helper, Python
  # twin as backup).  Rows are then drawn on demand like a big list, from _gv_row.
  if declare -F _gv_build >/dev/null 2>&1 && _gv_build; then
    _vp_count
    _vp_lazy_rows=true
    _vp_disp_ok=false
    declare -F _ensure_meta >/dev/null 2>&1 && _ensure_meta
    return 0
  fi
  _vp_lazy_rows=false
  if (( _vp_n > ${BVK_PRIME_MAX:-1500} )); then
    _vp_lazy_rows=true
    _vp_disp_ok=false
    declare -F _ensure_meta >/dev/null 2>&1 && _ensure_meta
    return 0
  fi
  local -a _dl=()
  # Load the metadata window and start the background folder-size job HERE, in
  # the main shell. `< <(display_items)` runs in a subshell: anything it
  # started (item_size[], the dsize job PID and output file) was thrown away
  # when it exited, so folders showed the "⏳" placeholder forever and the poll
  # loop had no job to harvest. display_items skips its own load while
  # _vp_meta_primed is set.
  if declare -F _needs_metadata >/dev/null 2>&1 && _needs_metadata \
     && declare -F _ensure_meta >/dev/null 2>&1; then
    _ensure_meta
  fi
  _vp_meta_primed=true
  mapfile -t _dl < <(display_items)
  _vp_meta_primed=false
  if [ "${#_dl[@]}" -eq "$_vp_n" ]; then
    local i
    for ((i=1; i<=_vp_n; i++)); do
      _vp_fit "${_dl[$((i-1))]}"
      _vp_rowcache[$i]="$_vp_line"
    done
    _vp_disp_ok=true
  else
    _vp_disp_ok=false
    [ -n "$BVK_VP_DEBUG" ] && \
      echo "🔴  display_items emitted ${#_dl[@]} lines for $_vp_n items — using _item_line_text" >&2
  fi
  return 0
}

_vp_is_hl_single() { [ "$1" -eq "${_hl_index:-0}" ]; }
# A number typed into the Select row highlights that row (_hl_index). _HL_TYPED remembers WHICH highlight came from typing, so
# when the typed number is gone (backspace) or invalid (more than the items there are) exactly that highlight is dropped —
# a highlight the user moved with the arrow keys is not touched.
_HL_TYPED=0
_hl_typed_clear() {
  local old="${_hl_index:-0}"
  if (( _HL_TYPED > 0 && old == _HL_TYPED )); then
    _HL_TYPED=0; _hl_index=0
    _vp_repaint_row "$old"
    [ -n "${_vp_input_fn:-}" ] && $_vp_input_fn
  else _HL_TYPED=0; fi
  return 0
}
_vp_is_hl_multi()  { [ -n "${_msel_set[$1]+x}" ]; }
_vp_is_hl() { $_vp_hl_fn "$1"; }

# Selection mark for row $1 → sets _smk_out, returns 0 when the row's item is in
# the .s selection.  Only for screens that list real files through the default
# row renderer (screens with their own row-text function list functions/menus,
# and grouped view rows are groups — they get the header count instead).
_vp_mark_sel() {
  [ "$_vp_mode" == "items" ] || return 1
  [ -z "${_vp_rowtext_fn:-}" ] || return 1
  [ -s "${_SEL_FILE:-/nonexistent}" ] || return 1
  declare -F _sel_mark_v >/dev/null 2>&1 || return 1
  _sel_mark_v "${items[$(( $1 - 1 ))]:-}" "$_vp_line"
}

# Menu chrome layout (every screen that goes through the viewport):
#
#     header
#     ───────────
#     options
#     ───────────
#     <linebreak>
#     footer
#     <suggestion row>      (menus with a typed prompt: the live suggestion; others: a linebreak)
#     Select:
#
# The linebreak above the footer and the one after it are added HERE, so no menu has
# to print them and none can forget them (the header sits directly on the rule):
#   header : trailing blank lines are dropped, nothing is appended
#   footer : leading + trailing blank lines are dropped, one is put before and
#            one after.  An empty header / footer adds nothing.
# which prompts have the suggestion row (between the footer and "Select:")
_vp_wants_hint_row() {
  case "${_vp_input_fn:-}" in _print_input_line|_sm_input_fn|_multi_print_input_line) return 0 ;; esac
  return 1
}
_vp_build_chrome() {
  local _i _n
  _vp_probe_size; _vp_cols="$_vp_cols_now"     # live width BEFORE header/footer wrap to it
  mapfile -t _vp_hdr_arr < <($_vp_header_fn)
  mapfile -t _vp_ftr_arr < <($_vp_footer_fn)

  # header: drop trailing blanks (the rule follows immediately, no linebreak between)
  _n=${#_vp_hdr_arr[@]}
  while (( _n > 0 )) && [[ "${_vp_hdr_arr[$((_n-1))]}" != *[![:space:]]* ]]; do _n=$(( _n - 1 )); done
  _vp_hdr_arr=("${_vp_hdr_arr[@]:0:_n}")
  [ "${_multi_hdr_gap:-0}" = 1 ] && [ "$_n" -gt 0 ] && _vp_hdr_arr+=("")      # a screen may keep one blank row above the rule (rename)

  # footer: drop blanks at both edges, then frame it with one linebreak above and one below
  _n=${#_vp_ftr_arr[@]}
  while (( _n > 0 )) && [[ "${_vp_ftr_arr[$((_n-1))]}" != *[![:space:]]* ]]; do _n=$(( _n - 1 )); done
  _vp_ftr_arr=("${_vp_ftr_arr[@]:0:_n}")
  _i=0
  while (( _i < _n )) && [[ "${_vp_ftr_arr[$_i]}" != *[![:space:]]* ]]; do _i=$(( _i + 1 )); done
  _vp_ftr_arr=("${_vp_ftr_arr[@]:_i}")
  if (( ${#_vp_ftr_arr[@]} > 0 )); then
    if _vp_wants_hint_row; then _vp_ftr_arr=("" "${_vp_ftr_arr[@]}")        # the suggestion row IS the linebreak below the footer
    else _vp_ftr_arr=("" "${_vp_ftr_arr[@]}" ""); fi
  fi

  _vp_top_n=${#_vp_hdr_arr[@]}
  _vp_footer_n=${#_vp_ftr_arr[@]}
}

_vp_apply_chrome_budget() {
  local i n k tmp=()
  _vp_hdr_out=()
  _vp_ftr_out=()

  if (( _vp_hdr_show >= _vp_top_n )); then
    _vp_hdr_out=("${_vp_hdr_arr[@]}")
  else
    tmp=()
    for i in "${_vp_hdr_arr[@]}"; do [ -n "${i// /}" ] && tmp+=("$i"); done
    n=${#tmp[@]}
    k=$(( n - _vp_hdr_show )); (( k < 0 )) && k=0
    for ((i=k; i<n; i++)); do _vp_hdr_out+=("${tmp[$i]}"); done
  fi

  if (( _vp_ftr_show >= _vp_footer_n )); then
    _vp_ftr_out=("${_vp_ftr_arr[@]}")
  else
    tmp=()
    for i in "${_vp_ftr_arr[@]}"; do [ -n "${i// /}" ] && tmp+=("$i"); done
    n=${#tmp[@]}
    k=0
    for ((i=0; i<n && k<_vp_ftr_show; i++)); do _vp_ftr_out+=("${tmp[$i]}"); k=$((k+1)); done
  fi

  _vp_hdr_show=${#_vp_hdr_out[@]}
  _vp_ftr_show=${#_vp_ftr_out[@]}
}

_vp_geometry() {
  local rows chrome min_rows
  _vp_probe_size
  rows="$_vp_rows_now"
  _vp_cols="$_vp_cols_now"
  _vp_count

  _vp_ind=1
  _vp_hdr_show=$_vp_top_n
  _vp_ftr_show=$_vp_footer_n

  # Select-prompt screens keep ONE suggestion row ABOVE the prompt (between the footer and "Select:"): hints ("type to filter live",
  # "s → Settings"), notices and the loading bar are drawn there, never on the line being typed on.
  # It is one row on a wide screen and two on a narrow one (a phone): a suggestion longer than the row expands onto the second row
  # (_bvk_hint_wrap) instead of being cut.  _vp_hint_row stays the 0/1 flag "this prompt has the area", _vp_hint_n is its height.
  _vp_hint_row=0; _vp_hint_n=0
  if _vp_wants_hint_row; then
    _vp_hint_row=1; _vp_hint_n=1
    (( _vp_cols_now < ${BVK_HINT_WIDE:-100} && rows >= 24 )) && _vp_hint_n=2
  fi

  min_rows=3
  (( _vp_R > 0 && _vp_R < min_rows )) && min_rows=$_vp_R
  (( min_rows < 1 )) && min_rows=1

  while :; do
    chrome=$(( _vp_hdr_show + 2 * _vp_ind + _vp_ftr_show + 1 + _vp_hint_n ))
    (( rows - chrome >= min_rows )) && break
    if   (( _vp_ftr_show > 0 ));  then _vp_ftr_show=$(( _vp_ftr_show - 1 ))
    elif (( _vp_ind > 0 ));       then _vp_ind=0
    elif (( _vp_hdr_show > 1 ));  then _vp_hdr_show=$(( _vp_hdr_show - 1 ))
    else break
    fi
  done

  _vp_apply_chrome_budget

  chrome=$(( _vp_hdr_show + 2 * _vp_ind + _vp_ftr_show + 1 + _vp_hint_n ))
  _vp_page=$(( rows - chrome ))
  (( _vp_page < 1 )) && _vp_page=1
  (( _vp_page > _vp_R )) && _vp_page=$_vp_R
  _vp_rows_printed=$_vp_page
  (( _vp_n == 0 )) && _vp_rows_printed=1
  _blk_h=$(( _vp_hdr_show + _vp_ind + _vp_rows_printed + _vp_ind + _vp_ftr_show + _vp_hint_n + 1 ))
}

_vp_ensure_visible() {
  local sel="$1" old="$_vp_start" max_start top
  (( _vp_n == 0 )) && { _vp_start=1; return 1; }
  (( sel < 1 )) && sel=1
  (( sel > _vp_n )) && sel=$_vp_n
  top=$sel
  if (( _vp_gv )); then
    sel="${_gv_irow[$((sel-1))]}"           # item number -> screen row
    top=$sel
    # scrolling UP to the first item of a group brings its header rows into view too
    # (but never so far that the item itself would fall off the bottom of a short screen)
    while (( top > 1 && sel - top + 1 < _vp_page )) && [[ "${_gv_row[$((top-2))]}" == H* ]]; do top=$(( top - 1 )); done
  fi
  if (( top < _vp_start )); then
    _vp_start=$top
  elif (( sel > _vp_start + _vp_page - 1 )); then
    _vp_start=$(( sel - _vp_page + 1 ))
  fi
  max_start=$(( _vp_R - _vp_page + 1 ))
  (( max_start < 1 )) && max_start=1
  (( _vp_start > max_start )) && _vp_start=$max_start
  (( _vp_start < 1 )) && _vp_start=1
  _vp_end=$(( _vp_start + _vp_page - 1 ))
  (( _vp_end > _vp_R )) && _vp_end=$_vp_R
  [ "$_vp_start" -ne "$old" ]
}

# Frame buffering: every line of a screen is appended to _vp_frame and the whole
# screen is written in ONE write at the end of _vp_emit (pop).  There is no timer, no
# sleep and no helper process in the draw path: "carpet" is kept as a setting value
# for old config files but draws exactly like pop — nothing is ever delayed.
_vp_frame=""
_vp_force_pop=0         # kept for old callers; every draw is instant now

# Kept so Settings / old callers that ask for an animation keep working.
_vp_anim_pick() {
  if [ "${_sw_in_mode:-0}" = "1" ] || [ "${_fx_in_mode:-0}" = "1" ]; then
    _vp_am="${anim_inner:-carpet}"
  else
    _vp_am="${anim_outer:-pop}"
  fi
}
_vp_anim_mode() { _vp_anim_pick; echo "$_vp_am"; }
_vp_anim_start() { :; }     # the old background carpet writer no longer exists

_vp_el() { _vp_frame+=$'\r\033[2K\033[?7l'"$1"$'\033[?7h\n'; }

_vp_emit() {
  local i line
  _vp_count
  _vp_end=$(( _vp_start + _vp_page - 1 ))
  (( _vp_end > _vp_R )) && _vp_end=$_vp_R

  _vp_frame=""
  local _it _lo=$_vp_start _hi=$_vp_end
  if (( _vp_gv )); then
    _vp_gv_hidden                              # items above / below the visible rows
    _lo=$(( _vp_ab + 1 )); _hi=$(( _vp_n - _vp_bl ))
  fi
  # one grep for all visible rows instead of one per row (selection marks)
  declare -F _sel_prewarm >/dev/null 2>&1 && _sel_prewarm "$_lo" "$_hi"

  for line in "${_vp_hdr_out[@]}"; do _vp_fit "$line"; _vp_el "$_vp_line"; done

  if (( _vp_ind > 0 )); then
    if (( _vp_start > 1 )); then
      if (( _vp_gv )); then
        if (( _vp_ab > 0 )); then _vp_el "   ▲ ${_vp_ab} more above"; else _vp_el "   ▲ group headers above"; fi
      else
        _vp_el "   ▲ $(( _vp_start - 1 )) more above"
      fi
    else
      _vp_el "$_vp_rule"
    fi
  fi

  if (( _vp_n == 0 )); then
    _vp_el "   (no items)"
  else
    for ((i=_vp_start; i<=_vp_end; i++)); do
      _it=$i
      if (( _vp_gv )); then
        _it="${_gv_row[$((i-1))]}"
        if [[ "$_it" == H* ]]; then               # group header row (not selectable)
          _vp_fit "${_it:1}"
          _vp_el $'\033[1m'"$_vp_line"$'\033[0m'
          continue
        fi
      fi
      _vp_row_text "$_it"
      line="$_vp_line"
      _vp_mark_sel "$_it" && line="$_smk_out"
      if _vp_is_hl "$_it"; then _highlight_v "$line"; line="$_hl_out"; fi
      _vp_el "$line"
    done
  fi

  if (( _vp_ind > 0 )); then
    if (( _vp_end < _vp_R )); then
      if (( _vp_gv )); then _vp_el "   ▼ ${_vp_bl} more below"; else _vp_el "   ▼ $(( _vp_n - _vp_end )) more below"; fi
    else
      _vp_el "$_vp_rule"
    fi
  fi

  for line in "${_vp_ftr_out[@]}"; do _vp_fit "$line"; _vp_el "$_vp_line"; done
  # the suggestion row: sits between the footer and the "Select:" line (see _bvk_hint_paint)
  if (( ${_vp_hint_row:-0} )); then local _hn; for (( _hn=0; _hn<${_vp_hint_n:-1}; _hn++ )); do _vp_el ""; done; _hint_cur="?"; fi   # the rows were just redrawn blank: the next sync repaints the suggestion

  # frame is complete — one write; ?2026 = synchronized output (terminals that lack it ignore it)
  builtin printf '\033[?2026h%s\033[?2026l' "$_vp_frame"
  _BVK_SCR_RAW="$_vp_frame"; _BVK_SCR_EXTRA=""      # print: remember what was just drawn
  _vp_frame=""
  _set_available_above "$_blk_h"
  return 0
}

# --- repaint the block in place (block top is _blk_h-1 lines up) ---
_vp_rerender() {
  builtin printf '\033[%dA\r' "$(( _blk_h - 1 ))"
  _vp_emit
  $_vp_input_fn
}

_vp_render_fresh() {
  [ "${_SL_WANT:-0}" = 1 ] && _sl_ready          # smartload: the wait is over; wipe its bar before this screen is drawn
  declare -F _cm_abort_report >/dev/null 2>&1 && _cm_abort_report   # a cancelled flow: say why, once, above the menu
  _hint_cur="?"          # a fresh screen: whatever sits under the prompt is unknown, repaint the hint row
  _lt_b "draw: header + footer layout"
  _vp_build_chrome
  _vp_geometry
  _vp_ensure_visible "${_hl_index:-1}"
  _lt_e
  _lt_b "draw: rows → one write to the terminal"
  _vp_emit
  _lt_e
  $_vp_input_fn
}

_vp_redraw_in_place() {
  local up=$(( _blk_h - 1 ))
  local rows
  rows=$(_term_rows)
  (( up > rows - 1 )) && up=$(( rows - 1 ))
  (( up < 0 )) && up=0
  (( up > 0 )) && builtin printf '\033[%dA' "$up"
  builtin printf '\r\033[J'
  _vp_force_pop=1
  _vp_render_fresh
  _vp_force_pop=0
}

# Fresh (block-emitting) render of the current list from the top: reset scroll + caches,
# re-prime rows, draw.  Callers set up items[] / viewport first.
_vp_render_from_top() {
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows
  _vp_render_fresh
}

# Shared tail of every in-place TAB redraw (switch / functions / rule book).
# Caller rebuilds items + calls its *_set_viewport first, and passes the block height
# it snapshotted BEFORE the tab changed:   _vp_tab_repaint "$_old_blk_h"
# _read_choice ends with a trailing `echo`, so the cursor sits one row BELOW the block;
# we move up the FULL old height (not -1, which drifts one line per switch) and emit the
# chrome WITHOUT an input line (_read_choice prints that fresh each loop).
_vp_tab_repaint() {
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows
  local _up=$(( ${1:-0} ))
  local _rows; _rows=$(_term_rows)
  (( _up > _rows - 1 )) && _up=$(( _rows - 1 ))
  (( _up < 0 ))         && _up=0
  (( _up > 0 ))         && printf '\033[%dA' "$_up"
  printf '\r\033[J'
  _hint_cur="?"
  _vp_build_chrome
  _vp_geometry
  _vp_ensure_visible "${_hl_index:-1}"
  _vp_emit
}

# "🔍 filter: Q*  (shown/total)" header row — identical in every loop header.
_vp_filter_header_line() {
  [ -n "$_filter_query" ] || return 0
  printf '🔍 filter: %s*  (%d/%d)\n' "${_filter_query^^}" "${#items[@]}" "$(_filter_total_count)"
}

_vp_dist() { echo $(( _vp_end - $1 + _vp_ind + _vp_ftr_show + _vp_hint_n + 1 )); }

_vp_repaint_row() {
  local i="$1" r="$1" line
  (( _vp_gv )) && r="${_gv_irow[$((i-1))]:-0}"       # item number -> screen row
  (( r < _vp_start || r > _vp_end )) && return 1
  _vp_row_text "$i"
  line="$_vp_line"
  _vp_mark_sel "$i" && line="$_smk_out"
  _vp_is_hl "$i" && line="$(_highlight "$line")"
  _repaint_line_above "$(_vp_dist "$r")" "$line"
  return 0
}

_vp_on_resize() { _vp_resized=true; }

_vp_page_step="${BVK_PAGE_STEP:-10}"

_read_key_seq() {
  local c
  _esc=""
  IFS= read -rsn1 -t 0.08 c || return 1
  _esc="$c"
  case "$c" in
    '[')
      while IFS= read -rsn1 -t 0.08 c; do
        _esc+="$c"
        case "$c" in
          [0-9]|';'|'<') continue ;;          # '<' opens an SGR mouse report: ESC[<button;column;row M|m  (see bashbasicsbyvk_mouse.sh)
          *) break ;;
        esac
      done
      if [ "$_esc" = "[M" ]; then             # X10 mouse report: three raw bytes follow; never let them reach the prompt
        IFS= read -rsn1 -t 0.08 c && _esc+="$c"
        IFS= read -rsn1 -t 0.08 c && _esc+="$c"
        IFS= read -rsn1 -t 0.08 c && _esc+="$c"
      fi
      ;;
    'O')
      IFS= read -rsn1 -t 0.08 c && _esc+="$c"
      ;;
  esac
  return 0
}

# ------------------------------------------------------------------------------------------------
# MULTI-ROW INPUT — a text that does not fit one row (or has line breaks) is shown in full, wrapped, as a block of rows
# ------------------------------------------------------------------------------------------------
# The block starts on the prompt's own row and grows downward (all rows are shown unless the text is taller than the screen; then the window follows the
# cursor). Left/right/typing move the cursor INSIDE it, across rows. Up/down/PgUp/PgDn/Home/End still move the list:
# the loops call _bvk_blk_park first (cursor back on the first row) so every row-relative repaint stays correct.
_BVK_MAX_INPUT=512           # an input longer than this is refused, whatever menu it is typed or pasted into
_BLK_ROWS=1; _BLK_CROW=0; _BLK_TOP=0; _BVK_FIT_COL=0

_bvk_blk_reset() {           # back to a plain one-row prompt: wipe the extra rows
  if (( ${_BLK_ROWS:-1} > 1 )); then
    builtin printf '\r'; (( _BLK_CROW > 0 )) && builtin printf '\033[%dA' "$_BLK_CROW"
    builtin printf '\033[J'; _hint_cur=""
  fi
  _BLK_ROWS=1; _BLK_CROW=0; _BLK_TOP=0
}
_bvk_blk_park() {            # cursor back on the block's first row (before something repaints list rows relative to it)
  (( ${_BLK_ROWS:-1} > 1 )) || return 0
  builtin printf '\r'; (( _BLK_CROW > 0 )) && builtin printf '\033[%dA' "$_BLK_CROW"
  _BLK_CROW=0
}
_bvk_blk_leave() {           # the prompt is being left: cursor to the block's last row, so the next echo lands below it
  local d=$(( ${_BLK_ROWS:-1} - 1 - ${_BLK_CROW:-0} ))
  (( d > 0 )) && builtin printf '\033[%dB' "$d"
  (( ${_BLK_ROWS:-1} > 1 )) && builtin printf '\r'
  _BLK_ROWS=1; _BLK_CROW=0; _BLK_TOP=0
}

# _bvk_row_multi PROMPT TEXT CURSOR
#   returns 1 when everything fits ONE row (nothing drawn: the caller draws the row as before);
#   returns 0 after drawing the whole text as a block of rows with the cursor at CURSOR.
_bvk_row_multi() {
  local p="$1" b="$2" pos="$3" cols pw len i o line ll cap chunk cl rest first=1 k R crow=0 ccol up out t found=0 top nvis maxv
  _bvk_cols; cols=$_BVK_COLS
  [[ "$p" == *$'\n'* ]] && { _bvk_blk_reset; return 1; }
  _bvk_dispw "$p"; pw=$_BVK_W
  if [[ "$b" != *$'\n'* ]]; then
    _bvk_dispw "$b"
    if (( pw + _BVK_W < cols - 1 )); then _bvk_blk_reset; return 1; fi
  fi
  len=${#b}; (( pos > len )) && pos=$len; (( pos < 0 )) && pos=0
  local -a rs=() rl=() rc=()
  i=0
  while :; do
    rest="${b:i}"; line="${rest%%$'\n'*}"; ll=${#line}; o=0
    while :; do
      cap=$(( cols - 1 - (first == 1 ? pw : 0) )); (( cap < 4 )) && cap=4
      chunk="${line:o:cap}"
      if ! _bvk_is_ascii "$chunk"; then               # wide characters take two cells: shrink the chunk to fit
        _bvk_dispw "$chunk"
        while (( _BVK_W > cap && ${#chunk} > 1 )); do chunk="${chunk%?}"; _bvk_dispw "$chunk"; done
      fi
      cl=${#chunk}; first=0
      rs+=( $(( i + o )) ); rl+=( "$cl" ); o=$(( o + cl ))
      if (( o >= ll )); then rc+=( 0 ); break; else rc+=( 1 ); fi
    done
    i=$(( i + ll + 1 ))
    (( i > len )) && break
  done
  R=${#rs[@]}
  for (( k=0; k<R; k++ )); do                          # which row holds the cursor
    if (( pos < rs[k] + rl[k] )) || { (( pos == rs[k] + rl[k] )) && (( rc[k] == 0 )); }; then crow=$k; found=1; break; fi
  done
  (( found )) || crow=$(( R - 1 ))
  t="${b:rs[crow]:pos-rs[crow]}"; _bvk_dispw "$t"; ccol=$(( (crow == 0 ? pw : 0) + _BVK_W ))
  # every row of the text is shown (no fixed row limit). Only when the text is taller than the screen itself can it not be drawn
  # in full (the cursor cannot move above the top row): then the window of rows follows the cursor.
  maxv=$R; (( ${_vp_rows_now:-0} > 2 && maxv > _vp_rows_now - 1 )) && maxv=$(( _vp_rows_now - 1 )); (( maxv < 1 )) && maxv=1
  top=${_BLK_TOP:-0}
  (( top > R - maxv )) && top=$(( R - maxv )); (( top < 0 )) && top=0
  (( crow < top )) && top=$crow
  (( crow >= top + maxv )) && top=$(( crow - maxv + 1 ))
  nvis=$(( R - top )); (( nvis > maxv )) && nvis=$maxv
  _BLK_TOP=$top
  out=$'\r'; (( _BLK_CROW > 0 )) && out+=$'\033['"$_BLK_CROW"A
  if [ "${_vp_hint_row:-0}" = 1 ] && [ -n "${_hint_cur:-}" ]; then   # the block replaces the suggestion (every row of it)
    for (( k=1; k<=${_vp_hint_n:-1}; k++ )); do out+=$'\033['"$k"$'A\r\033[2K\033['"$k"$'B'; done
  fi
  out+=$'\033[J'
  for (( k=top; k<top+nvis; k++ )); do
    (( k > top )) && out+=$'\r\n'
    (( k == 0 )) && out+="$p"
    out+="${b:rs[k]:rl[k]}"
  done
  up=$(( nvis - 1 - (crow - top) )); (( up > 0 )) && out+=$'\033['"$up"A
  out+=$'\r'; (( ccol > 0 )) && out+=$'\033['"$ccol"C
  builtin printf '%s' "$out"
  _BLK_ROWS=$nvis; _BLK_CROW=$(( crow - top )); _hint_cur=""; _BVK_FIT_COL=$ccol
  return 0
}

# moving the cursor inside the text: a plain one-row text just steps the cursor; a block is redrawn (it may scroll / change row)
# _bvk_cursor_to NEWPOS REDRAW_FN
_bvk_cursor_to() {
  local old="$_pos" lo hi
  _pos="$1"
  if (( ${_BLK_ROWS:-1} > 1 )); then "$2"; return 0; fi
  if (( _pos > old )); then lo=$old; hi=$_pos; else lo=$_pos; hi=$old; fi
  _bvk_dispw "${_buf:lo:hi-lo}"
  if (( _pos > old )); then builtin printf '\033[%dC' "$_BVK_W"; else builtin printf '\033[%dD' "$_BVK_W"; fi
}

# the limit: _bvk_room N = N more characters still fit into _buf
_bvk_room() { (( ${#_buf} + $1 <= _BVK_MAX_INPUT )); }
# a one-line red notice on the row under the input (it stays until the next key); the cursor is put back where it was
# ── the suggestion row ─────────────────────────────────────────────────────────────────────────────────────
# ONE row directly above the "Select:" line (between the footer and the prompt):
#     u) Up   cd) Change directory   q) Quit
#     h) Home   s) Settings   -h) Help   -u) Upgrade
#     <suggestion>
#     Select: _
# It is part of the drawn block (_vp_hint_row, counted in _blk_h / _vp_dist), so painting it never scrolls the screen.
# The cursor is on row _BLK_CROW of the prompt block; it ends where it started (column 0).
_bvk_hint_paint() {   # $1 text ("" = wipe)  $2 sgr (default dim).  A long text expands onto the next reserved row (_bvk_hint_wrap).
  local n=${_vp_hint_n:-1} i up sgr="${2:-2}" out="" ln
  _BVK_HINT_N=0; [ -n "$1" ] && _bvk_hint_wrap "$1" "$n"
  for (( i=0; i<n; i++ )); do
    up=$(( ${_BLK_CROW:-0} + n - i ))                     # row i of the area, counted up from the cursor's row
    ln=""; (( i < _BVK_HINT_N )) && ln=$'\033['"$sgr"'m'"${_BVK_HINT_LN[i]}"$'\033[0m'
    out+=$'\033['"$up"$'A\r\033[2K'"$ln"$'\033['"$up"$'B'
  done
  builtin printf '%s\r' "$out"
}
_bvk_hint_leave() {   # the prompt is being left (cursor on the block's LAST row): wipe the rows above its FIRST row
  local n=${_vp_hint_n:-1} i up out=""
  for (( i=0; i<n; i++ )); do up=$(( ${_BLK_ROWS:-1} + i )); out+=$'\033['"$up"$'A\r\033[2K\033['"$up"$'B'; done
  builtin printf '%s\r' "$out"
}
_bvk_notice() {
  if [ "${_vp_hint_row:-0}" = 1 ]; then
    _bvk_hint_paint "$1" "1;31"
    (( ${_BVK_FIT_COL:-0} > 0 )) && builtin printf '\033[%dC' "$_BVK_FIT_COL"
    _hint_cur="__notice__"; return 0
  fi
  local down=$(( ${_BLK_ROWS:-1} - 1 - ${_BLK_CROW:-0} ))
  (( down > 0 )) && builtin printf '\033[%dB' "$down"
  builtin printf '\n\r\033[2K\033[1;31m%s\033[0m\033[%dA\r' "$1" $(( down + 1 ))
  (( ${_BVK_FIT_COL:-0} > 0 )) && builtin printf '\033[%dC' "$_BVK_FIT_COL"
  _hint_cur="__notice__"
}
# after refusing a paste: swallow whatever is still arriving from it (a terminal without paste markers sends it in pieces)
_bvk_paste_drain() { local junk; while IFS= builtin read -rs -d '' -n 65536 -t 0.15 junk; do :; done; return 0; }
# refuse: nothing was added; redraw the row and say why.   _bvk_too_large TOTAL_CHARS REDRAW_FN [drain]
_bvk_too_large() {
  [ "${3:-}" = drain ] && _bvk_paste_drain
  "$2"
  _bvk_notice "Too large: $1 characters (limit $_BVK_MAX_INPUT). Not accepted; nothing was changed."
}

# ------------------------------------------------------------------------------------------------
# PASTE  — one paste = ONE edit, never a replay of keystrokes
# ------------------------------------------------------------------------------------------------
# Every input row (Select: · Item numbers: · smart menus · typed-line prompts · settings) reads one key at a time.
# A pasted text used to arrive as thousands of "keys": each one redrew the row (the "someone is typing" animation) and
# every line break was taken as Enter. Now:
#   1. bracketed paste is switched on while a row is open: the terminal wraps a paste in ESC[200~ ... ESC[201~, so the
#      whole text is read in one go and its line breaks are text, never Enter;
#   2. terminals that do not send those markers: a burst of bytes that is already waiting when a key is read is the same
#      paste — it is swallowed in one read. (A lone "text" + Enter that arrives together is still just typing + Enter.)
# The text goes into the row in ONE insert + ONE redraw. Line breaks and tabs become a space, other control bytes
# are dropped, nothing else is changed. Only the user pressing Enter ever accepts a row.
_BVK_PASTE=""        # the text of the last paste
_BVK_PASTE_ENTER=0   # 1 = the burst was "typed text + Enter" (not a paste): the caller accepts the row after inserting it
_bvk_paste_on()  { [ -t 1 ] && builtin printf '\033[?2004h'; return 0; }
_bvk_paste_off() { [ -t 1 ] && builtin printf '\033[?2004l'; return 0; }

# _bvk_paste_clean TEXT -> _BVK_PASTE   (line breaks are KEPT: a paste stays multi-line; CR dropped, tab -> space, other control bytes dropped)
# (tr, not ${t//x/y}: in a UTF-8 locale bash's pattern replace is quadratic — 100 000 characters would take minutes)
_bvk_paste_clean() {
  local t="$1"
  case "$t" in *[[:cntrl:]]*)
    t="$(builtin printf '%s' "$t" | LC_ALL=C tr -d '\r' | LC_ALL=C tr '\t' ' ' | LC_ALL=C tr -d '\000-\011\013\014\016-\037\177')"
    ;;
  esac
  _BVK_PASTE="$t"
}

# the ESC[200~ marker was just read: take everything up to ESC[201~ -> _BVK_PASTE (cleaned)
_bvk_paste_bracketed() {
  local chunk="" all="" tail="" rc
  while :; do
    chunk=""
    IFS= builtin read -rs -d $'\033' -t 2 chunk; rc=$?
    all+="$chunk"
    if [ "$rc" -eq 0 ]; then
      tail=""; IFS= builtin read -rs -n5 -t 0.5 tail
      [ "$tail" = "[201~" ] && break
      all+="$tail"                       # a stray ESC inside the paste: keep going
    else
      [ "$rc" -gt 128 ] && [ -n "$chunk" ] && continue   # still arriving
      break                              # silence or EOF: take what came
    fi
  done
  while [[ "$all" == *[$'\r\n'] ]]; do all="${all%[$'\r\n']}"; done   # the closing line break of a copied block is not text
  _bvk_paste_clean "$all"
}

# _bvk_paste_burst KEY  — KEY was just read (a printable char, or a line break for Enter).
#   returns 0 and sets _BVK_PASTE (+ _BVK_PASTE_ENTER) when more input was already waiting; 1 = a single key, nothing swallowed
_bvk_paste_burst() {
  local first="$1" rest="" chunk rc t body nl=$'\n'
  builtin read -t 0 2>/dev/null || return 1
  while :; do                           # keep taking input until it has been quiet for a moment: the WHOLE paste, however it was chunked
    chunk=""
    IFS= builtin read -rs -d '' -n 65536 -t 0.06 chunk; rc=$?
    rest+="$chunk"
    if [ "$rc" -gt 128 ]; then [ -z "$chunk" ] && break; continue; fi
    [ "$rc" -ne 0 ] && break
  done
  [ -z "$rest" ] && return 1
  rest="${rest%%$'\033'*}"               # an arrow key that came right behind the text: not part of it
  t="$first$rest"
  # "typed text + Enter" that arrived in one piece (scripts, key macros): text, then Enter — the row is accepted by that Enter
  body="$t"; while [[ "$body" == *[$'\r\n'] ]]; do body="${body%[$'\r\n']}"; done
  _BVK_PASTE_ENTER=0
  if [ "$body" != "$t" ] && [[ "$body" != *[$'\r\n']* ]]; then _BVK_PASTE_ENTER=1; t="$body"
  else
    while [[ "$t" == *[$'\r\n'] ]]; do t="${t%[$'\r\n']}"; done      # a paste's closing line break is not an Enter either
  fi
  _bvk_paste_clean "$t"
  return 0
}

# ------------------------------------------------------------------------------------------------
# NAME LENGTH — a file / folder name is at most 255 BYTES (the filesystem standard). Never create or rename past it.
# ------------------------------------------------------------------------------------------------
# _bvk_name_too_long NAME   0 = some part of NAME (each "/"-separated part) is longer than 255 bytes
_bvk_name_too_long() {
  local LC_ALL=C part rest="$1"
  while :; do
    part="${rest%%/*}"
    [ "${#part}" -gt 255 ] && return 0
    [[ "$rest" == */* ]] || return 1
    rest="${rest#*/}"
  done
}
# _bvk_name_bytes NAME  -> _BVK_NB (its length in bytes)
_bvk_name_bytes() { local LC_ALL=C; _BVK_NB=${#1}; }
# _bvk_name_refuse NAME [folder|file]   prints why it was not created / renamed
_bvk_name_refuse() {
  local n="$1" kind="${2:-name}" shown
  _bvk_name_bytes "$n"
  shown="${n:0:30}"; [ "${#n}" -gt 30 ] && shown="${shown}..."
  builtin printf ' %s "%s" was not created: its name is %s bytes, over the 255-byte limit (255 characters for plain ASCII names) that every filesystem accepts.\n' "$kind" "$shown" "$_BVK_NB" >&2
}

_key_name() {
  local s="$1" fin body num
  _kname=""
  [ -z "$s" ] && return 1
  fin="${s: -1}"
  case "$s" in
    'O'*)
      case "$fin" in
        A) _kname=up ;; B) _kname=down ;;
        C) _kname=right ;; D) _kname=left ;;
        H) _kname=home ;; F) _kname=end ;;
      esac
      return 0
      ;;
    '['*) ;;
    *) return 1 ;;
  esac
  body="${s:1}"
  num="${body%"$fin"}"
  num="${num%%;*}"
  case "$fin" in
    A) _kname=up ;;
    B) _kname=down ;;
    C) _kname=right ;;
    D) _kname=left ;;
    H) _kname=home ;;
    F) _kname=end ;;
    '~')
      case "$num" in
        1|7) _kname=home ;;
        4|8) _kname=end ;;
        5)   _kname=pgup ;;
        6)   _kname=pgdn ;;
      esac
      ;;
  esac
  return 0
}

# q  — two different things, never mixed up:
#   _bvk_exit  the q of the MAIN LOOP (the file list): leave the whole app.
#   _bvk_quit  the q of EVERY OTHER screen (fx, sw, .r, api, bk, sv, sn, rbam, nf, cs, -u, Home ...): close to the main loop.
#              It only raises _BVK_TO_MAIN; the caller returns / breaks, every menu loop on the way sees the flag and leaves
#              (_inner_run, Home, the loops themselves), and the main loop clears it at the top of its next round.
#              It must NEVER exit the app: after  _bvk_quit  the caller has to  break / return.
# u (back / up one level) is handled by each menu itself and only ever goes back ONE screen.
_BVK_TO_MAIN=0
_bvk_exit() {
  _bvk_paste_off
  declare -F _bvk_mouse_off >/dev/null 2>&1 && _bvk_mouse_off
  if ${_sw_did_switch:-false}; then [ "${_GD_ACTIVE:-0}" = 1 ] && _gd_before_exec; _lt_cleanup; cd "$path" && exec "$SHELL"; else exit 0; fi
}
_bvk_quit() {
  _fx_in_mode=0; _sw_in_mode=0
  _BVK_TO_MAIN=1
  return 0
}

_is_ctrl_char() {
  case "$1" in
    [[:cntrl:]]) return 0 ;;
    *) return 1 ;;
  esac
}

# parse_selection: expands a selection string like "1,3-5,7" into space-separated indices
# clamped to [1..max].  Output is consumed by callers via: for idx in $(parse_selection …)
#
# Python heredoc replaces the inner loop's  part=$(echo "$part" | xargs)  which spawns a
# full echo+xargs pipeline (≥3 processes) for EVERY comma-separated token.  For a typical
# multi-select input with N tokens that means N×3 subprocess spawns; Python does the entire
# job in a single process.  Called on every keystroke in multi-select mode, so the saving
# compounds quickly.
# Estimated speedup: 5-10x for inputs with ≥3 tokens.
# Requires: python3 on PATH (standard on any modern Linux/macOS).
parse_selection() {
  local input="$1"
  local max="$2"
  python3 - "$input" "$max" <<'PYEOF'
import sys, re
input_str = sys.argv[1]
max_val   = int(sys.argv[2])
indices   = []
for part in input_str.split(','):
    part = part.strip()
    if not part:
        continue
    m = re.match(r'^(\d+)-(\d+)$', part)
    if m:
        start, end = int(m.group(1)), int(m.group(2))
        indices.extend(i for i in range(start, end + 1) if i <= max_val)
    elif re.match(r'^\d+$', part):
        num = int(part)
        if 1 <= num <= max_val:
            indices.append(num)
if indices:
    print(' '.join(str(i) for i in indices))
PYEOF
}

# a big paste (text with letters / words in it) is not a selection: never parse it char by char
_multi_is_big_text() { [ "${#_buf}" -gt 2000 ] && [[ "$_buf" == *[!0-9\ ,.a-]* ]]; }
_multi_compute_set() {
  _msel_set=()
  local idx
  _vp_count
  _multi_is_big_text && return 0
  local _b="${_buf// /}"
  if [ "${_multi_allow_a:-false}" == "true" ] && [[ "$_b" == "a" ]]; then
    for idx in $(seq 1 "$_vp_n"); do _msel_set["$idx"]=1; done
  elif [ "${_multi_allow_a:-false}" == "true" ] && [[ "$_b" =~ ^a-([0-9][0-9,-]*)$ ]]; then
    for idx in $(_sp_parse_all_except "${BASH_REMATCH[1]}" "$_vp_n"); do _msel_set["$idx"]=1; done
  else
    for idx in $(parse_selection "$_buf" "$_vp_n"); do
      _msel_set["$idx"]=1
    done
  fi
}

_multi_print_input_line() {
  local _mp back
  if [ "$_vp_mode" == "imaginary" ]; then _BVK_SCR_PROMPT="Group numbers:"; _mp="Group numbers: "
  else _mp="${_multi_label:-Item numbers}: "; _BVK_SCR_PROMPT="${_mp% }"; fi      # _multi_label: a screen that calls this "Select" (rename)
  _bvk_row_multi "$_mp" "$_buf" "$_pos" && return 0       # a text that does not fit one row: shown in full, as a block of rows
  declare -F _input_hint_sync >/dev/null 2>&1 && _input_hint_sync
  builtin printf '\r\033[K'
  _bvk_fit_input "$_mp" "$_buf" "$_pos"                  # one row only: a long paste must not wrap
  builtin printf '%s%s' "$_BVK_FIT_PROMPT" "$_BVK_FIT"; back="$_BVK_FIT_BACK"
  [ "$back" -gt 0 ] && builtin printf '\033[%dD' "$back"
}

_multi_header_fn() {
  # a screen that is not a folder view (e.g. -auth) supplies its own title via this hook
  if [ -n "${_multi_header_hook:-}" ]; then $_multi_header_hook; return 0; fi
  _menu_header
  [ "$_vp_mode" == "imaginary" ] && echo "$_imag_banner"
  return 0
}

_multi_footer_fn() {
  # a screen with its own footer (rename: "u) Up   q) Close") supplies it via this hook
  if [ -n "${_multi_footer_hook:-}" ]; then $_multi_footer_hook; return 0; fi
  echo
  if [ "${_multi_allow_a:-false}" == "true" ]; then
    echo "$_prompt (ranges: 1-10,15-20,33   a = all   a-1-5,7 = all except)"
  else
    echo "$_prompt (supports ranges: 1-10,15-20,33)"
  fi
  echo "up/down ±1, PgUp/PgDn ±${_vp_page_step}, Home/End first/last, left/right move cursor"
}

_multi_render() {
  _multi_compute_set
  clear
  _vp_header_fn=_multi_header_fn
  _vp_footer_fn=_multi_footer_fn
  _vp_hl_fn=_vp_is_hl_multi
  _vp_input_fn=_multi_print_input_line
  _vp_start=1
  _vp_cache_reset
  _vp_prime_rows
  _vp_render_fresh
}

_multi_cursor_index() {
  local bounds s e num
  _multi_is_big_text && return 1
  bounds=$(_multi_number_token_bounds) || return 1
  [ -z "$bounds" ] && return 1
  read -r s e <<< "$bounds"
  num="${_buf:s:e-s}"
  [ -z "$num" ] && return 1
  echo $((10#$num))
}

_multi_sync() {
  _bvk_blk_park                                      # list rows are repainted relative to the first input row
  local -A _old_set=()
  local k
  for k in "${!_msel_set[@]}"; do _old_set["$k"]=1; done

  _multi_compute_set

  local -A _changed=()
  for k in "${!_old_set[@]}"; do
    [ -z "${_msel_set[$k]+x}" ] && _changed["$k"]=1
  done
  for k in "${!_msel_set[@]}"; do
    [ -z "${_old_set[$k]+x}" ] && _changed["$k"]=1
  done

  local target
  target=$(_multi_cursor_index)
  if [ -n "$target" ] && _vp_ensure_visible "$target"; then
    _vp_rerender
    return 0
  fi

  if [ "${#_changed[@]}" -gt 0 ]; then
    local idx
    for idx in "${!_changed[@]}"; do
      _vp_repaint_row "$idx"
    done
  fi

  _multi_print_input_line
}

_multi_number_token_bounds() {
  local s=$_pos e=$_pos
  while [ "$s" -gt 0 ] && [[ "${_buf:s-1:1}" =~ [0-9] ]]; do s=$((s-1)); done
  while [ "$e" -lt "${#_buf}" ] && [[ "${_buf:e:1}" =~ [0-9] ]]; do e=$((e+1)); done
  [ "$s" -eq "$e" ] && return 1
  echo "$s $e"
}

_multi_adjust_number_at_cursor() {
  local dir="$1" bounds s e num n max newnum
  bounds=$(_multi_number_token_bounds)
  if [ -z "$bounds" ]; then
    if [ -z "$_buf" ]; then
      # same as the main menu: down -> first item, up -> last item
      _vp_count
      case "$dir" in
        up|end) _buf="${_vp_n:-1}" ;;
        *)      _buf="1" ;;
      esac
      [ "${_buf:-0}" -lt 1 ] 2>/dev/null && _buf="1"
      _pos=${#_buf}
      _multi_sync
    fi
    return
  fi
  read -r s e <<< "$bounds"
  num="${_buf:s:e-s}"
  n=$((10#$num))
  _vp_count
  max="$_vp_n"
  # Direction MUST match the main menu (browse.sh): down = next item (+1), up = previous (-1),
  # both wrap; PgDn = +page, PgUp = -page, both clamp.
  case "$dir" in
    down) n=$((n+1)); [ "$n" -gt "$max" ] && n=1 ;;
    up)   n=$((n-1)); [ "$n" -lt 1 ] && n=$max ;;
    # page/home/end clamp rather than wrap
    pgdn) n=$(( n + _vp_page_step )); [ "$n" -gt "$max" ] && n=$max ;;
    pgup) n=$(( n - _vp_page_step )); [ "$n" -lt 1 ] && n=1 ;;
    home) n=1 ;;
    end)  n=$max ;;
  esac
  newnum="$n"
  _buf="${_buf:0:s}${newnum}${_buf:e}"
  _pos=$(( s + ${#newnum} ))
  _multi_sync
}

# mouse / touch in the picker (see bashbasicsbyvk_mouse.sh): a click toggles the item in the typed list (1-3,7), a double click
# puts it in and accepts, ▲ / ▼ and the wheel scroll the window.  returns 2 = accept now.
_multi_click() {
  _bvk_blk_park
  if ! _bvk_mouse_prow; then _multi_print_input_line; return 0; fi
  _bvk_mouse_hit "$_MS_Y" "$_BVK_CROW"
  local rc=0 it
  case "$_MS_KIND" in
    item)
      it="$_MS_ITEM"
      local _numre='^[0-9, -]*$'
      if [[ "$_buf" =~ $_numre ]]; then      # a, a-1-5 or a typed command: not a list of numbers, leave it alone
        _multi_compute_set
        if _bvk_mouse_dbl "m:$it"; then rc=2; _msel_set[$it]=1       # double: the item is in, and Enter
        elif [ -n "${_msel_set[$it]+x}" ]; then unset '_msel_set[$it]'
        else _msel_set[$it]=1; fi
        _buf="$(_sm_render_set)"; _pos=${#_buf}
        _multi_sync; return $rc
      fi ;;
    pgup) _BVK_LAST_ITEM=""; _bvk_mouse_scroll $(( - _vp_page )) ;;
    pgdn) _BVK_LAST_ITEM=""; _bvk_mouse_scroll "$_vp_page" ;;
    prompt) _bvk_mouse_other "$_MS_Y" "$_BVK_CROW" ;;            # hands the touch back: the next tap opens the keyboard
  esac
  _multi_print_input_line
  return $rc
}

# The picker ("Item numbers:" / "Group numbers:") is a prompt inside a flow: a command typed here
# (s, h ...) runs and the picker is asked again; a blocked one cancels the flow (see cmdmap).
_multi_prompt_loop() {
  declare -F _cm_ctx_find >/dev/null 2>&1 && _cm_ctx_find
  while :; do
    _multi_prompt_loop_raw
    declare -F _cm_gate_multi >/dev/null 2>&1 || break
    _cm_gate_multi && break
  done
}

# cc types a command into this prompt (text that is not numbers is judged by the gate on Enter)
_multi_type_key() {
  local key="$1"
  _is_ctrl_char "$key" && return 0
  _buf="${_buf:0:_pos}${key}${_buf:_pos}"
  _pos=$(( _pos + 1 ))
  _multi_sync
}
_multi_type_text() { _buf="$1"; _pos=${#_buf}; _multi_sync; }
# a paste: ONE insert, ONE redraw
_multi_paste_text() {
  local t="$1"
  [ -z "$t" ] && return 0
  _bvk_room "${#t}" || { _bvk_too_large $(( ${#_buf} + ${#t} )) _multi_print_input_line drain; return 0; }
  _buf="${_buf:0:_pos}${t}${_buf:_pos}"
  _pos=$(( _pos + ${#t} ))
  _multi_sync
}

_multi_prompt_loop_raw() {
  local key seq _rc
  _buf=""
  _pos=0

  stty -icanon -echo min 1 time 0 2>/dev/null
  trap '_vp_on_resize' WINCH
  _bvk_paste_on
  declare -F _bvk_mouse_on >/dev/null 2>&1 && _bvk_mouse_on; _BVK_LAST_ITEM=""
  _multi_render
  _lt_ready text
  [ -n "${_CC_PREFILL:-}" ] && _cc_replay _multi_type_key _multi_type_text

  while true; do
    IFS= read -rsn1 -t "$_vp_poll_cur" key
    _rc=$?
    if [ "$_rc" -gt 128 ]; then
      _vp_poll_tick
      if _vp_check_resize; then _multi_render; _vp_poll_active; fi
      continue
    fi
    [ "$_rc" -ne 0 ] && break
    _vp_poll_active
    if [[ "$key" == $'\x1b' ]]; then
      _read_key_seq || continue
      if [ "$_esc" = "[200~" ]; then _bvk_paste_bracketed; _multi_paste_text "$_BVK_PASTE"; continue; fi
      if declare -F _bvk_mouse_decode >/dev/null 2>&1 && _bvk_mouse_decode "$_esc"; then
        case "$_MS_ACT" in
          press)     _multi_click; (( $? == 2 )) && break ;;
          wheelup)   _bvk_mouse_wheel_window -1; _multi_print_input_line ;;
          wheeldown) _bvk_mouse_wheel_window 1;  _multi_print_input_line ;;
        esac
        continue
      fi
      _key_name "$_esc"
      case "$_kname" in
        up)   _multi_adjust_number_at_cursor up ;;
        down) _multi_adjust_number_at_cursor down ;;
        pgup) _multi_adjust_number_at_cursor pgup ;;
        pgdn) _multi_adjust_number_at_cursor pgdn ;;
        home) _multi_adjust_number_at_cursor home ;;
        end)  _multi_adjust_number_at_cursor end ;;
        right)
          if [ "$_pos" -lt "${#_buf}" ]; then
            _bvk_cursor_to $(( _pos + 1 )) _multi_print_input_line
          fi
          ;;
        left)
          if [ "$_pos" -gt 0 ]; then
            _bvk_cursor_to $(( _pos - 1 )) _multi_print_input_line
          fi
          ;;
        *) : ;;
      esac
      continue
    fi

    if [ -z "$key" ] || [[ "$key" == [[:print:]] ]]; then
      if _bvk_paste_burst "${key:-$'\n'}"; then
        _multi_paste_text "$_BVK_PASTE"
        [ "$_BVK_PASTE_ENTER" = 1 ] && break
        continue
      fi
    fi

    case "$key" in
      "")
        break
        ;;
      $'\x7f'|$'\x08')
        if [ "$_pos" -gt 0 ]; then
          _buf="${_buf:0:_pos-1}${_buf:_pos}"
          _pos=$(( _pos - 1 ))
          _multi_sync
        fi
        ;;
      $'\x01') _multi_adjust_number_at_cursor home ;;   # Ctrl-A
      $'\x05') _multi_adjust_number_at_cursor end ;;    # Ctrl-E
      *)
        # never let stray control bytes into the buffer
        _is_ctrl_char "$key" && continue
        _bvk_room 1 || { _bvk_too_large $(( ${#_buf} + 1 )) _multi_print_input_line; continue; }
        _buf="${_buf:0:_pos}${key}${_buf:_pos}"
        _pos=$(( _pos + 1 ))
        _multi_sync
        ;;
    esac
  done

  trap - WINCH
  _bvk_paste_off
  declare -F _bvk_mouse_off >/dev/null 2>&1 && _bvk_mouse_off
  stty "$_orig_stty" 2>/dev/null
  _bvk_blk_leave
  if [ "${_vp_hint_row:-0}" = 1 ] && [ -n "${_hint_cur:-}" ]; then _hint_cur=""; _bvk_hint_leave; fi
  echo
  _lt_enter "$_buf"
}
