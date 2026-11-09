# bashbasicsbyvk_textedit.sh — THE text-edit template: one set of editing keys for EVERY place the app takes typed input
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
#  Every key loop (main "Select:", number picker, smart menus, typed-line prompts, Settings / choice menus) used to carry its
#  own copy of "insert a char, backspace, left, right".  They all call THIS file now, so a key works the same everywhere
#  and a new key is added ONCE.
#
#  Keys (what a computer's text field does):
#     ← →                    move · with a selection: collapse it to its left / right end
#     Shift+← →              select by character              Ctrl+← →   move by word        Ctrl+Shift+← →   select by word
#     Home End               start / end of the line          Shift+Home End   select to the start / end
#     Ctrl+Home / End        start / end of the whole text    Ctrl+Shift+Home / End   select to it
#     Shift+↑ ↓              select to the line above / below (a one-line text: to its start / end)
#     Ctrl+A                 select all  (an EMPTY line keeps the old list meaning: first item / select all rows)
#     Ctrl+C  Ctrl+Insert    copy the selection  (nothing selected: Ctrl+C interrupts, exactly as it always did)
#     Ctrl+X  Shift+Delete   cut                              Ctrl+V  Shift+Insert  paste (a paste is ONE edit, like a terminal paste)
#     Ctrl+Shift+C / V / X   the terminal-emulator spelling of the same three (where the terminal can send them)
#     Backspace  Delete      delete one character, or the selection
#     Ctrl+Backspace / Ctrl+W / Alt+Backspace   delete the word before the cursor      Ctrl+Delete / Alt+D   the word after
#     Ctrl+U  Ctrl+K         delete to the start / end of the line                      Ctrl+D   delete the character under the cursor
#     Ctrl+Z  Ctrl+Y (Ctrl+Shift+Z)   undo / redo
#     typing or pasting over a selection replaces it.
#
#  How a loop uses it (the whole contract — do not write another key switch):
#     _te_begin                                        when the loop starts (raw tty + clean selection / undo)
#     _te_esc  ESC  MODE BUFVAR POSVAR REDRAW EDIT PASTE   an escape sequence was read (ESC = what followed the escape byte)
#     _te_byte KEY  MODE BUFVAR POSVAR REDRAW EDIT PASTE   a single byte was read
#         return 0 = it was an editing key and has been done (the loop does `continue`);  1 = not ours, the loop goes on.
#         MODE  list: the line sits under a LIST — plain ↑ ↓ PgUp PgDn Home End (and ← → / Ctrl+A / Ctrl+E on an EMPTY line) stay
#                     the list's; everything else is ours.        text: a plain typed line — Home / End are ours too.
#         REDRAW  function: the cursor or the selection moved (draw the line again)
#         EDIT    function: the text changed (draw it, follow the list / hint / filter)       PASTE  function TEXT: insert TEXT
#               (a loop that redraws after every key itself passes `:` for REDRAW / EDIT)
#     _te_insert BUFVAR POSVAR TEXT                    type / paste TEXT at the cursor; a selection is replaced
#     _te_del_sel BUFVAR POSVAR                        delete the selection (rc 0 = there was one)
#  Drawing: the line drawers (_bvk_fit_input, _bvk_row_multi, _cm_edit_draw) ask _te_hl for the selected part in reverse video.
#  A selection belongs to ONE text: it counts only while the line still IS that text (_TE_ABUF), so a loop that sets its
#  buffer by hand (an arrow that types a number) drops it by itself.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

_TE_ANC=-1          # selection anchor (the other end is the cursor); -1 = nothing selected
_TE_ABUF=""         # the text the anchor belongs to
_TE_LO=0            # the selection found by the last _te_sel
_TE_HI=0
_TE_CH=""           # the chord decoded by the last _te_decode_*
_TE_W=0             # scratch result of the word / line helpers
_TE_OUT=""          # _te_hl result
_TE_GOT=""          # _te_clip_get result
_TE_CLIP=""         # the app's own clipboard: used when this machine has no clipboard tool
_TE_UNDO=()
_TE_REDO=()
_TE_LASTOP=""

# a line editor starts: raw keys, clean selection + undo.   _te_begin [BUFVAR POSVAR MODE REDRAW EDIT PASTE]
# With the six arguments the editor is also REGISTERED (_te_ctx_push): that is what lets Ctrl-C and Ctrl-Z work.  They are not bytes:
# bash's `read -n1` switches the terminal's signal keys back on while it waits, so Ctrl-C arrives as SIGINT and Ctrl-Z as SIGTSTP
# (which a script ignores: the key just disappears).  While an editor is registered both signals are caught and handled as the
# editing keys they are (_te_onsig).  Every _te_begin with arguments is paired with a _te_end where the loop leaves.
_te_begin() {
  stty -icanon -echo -isig -iexten min 1 time 0 2>/dev/null || stty -icanon -echo min 1 time 0 2>/dev/null
  _TE_ANC=-1; _TE_ABUF=""; _TE_UNDO=(); _TE_REDO=(); _TE_LASTOP=""
  (( $# >= 6 )) && _te_ctx_push "$@"
  return 0
}
_TE_STK=()          # the open editors, innermost last: "BUFVAR POSVAR MODE REDRAW EDIT PASTE"
_TE_OLDTRAP=""
_te_ctx_push() {
  if (( ${#_TE_STK[@]} == 0 )); then _TE_OLDTRAP="$(trap -p INT TSTP)"; trap '_te_onsig int' INT; trap '_te_onsig tstp' TSTP; fi
  _TE_STK+=("$1 $2 $3 $4 $5 $6")
}
_te_end() {          # the editor on top is closed: the signals go back to what they were when the last one is gone
  local n=${#_TE_STK[@]}
  (( n > 0 )) || return 0
  _TE_STK=("${_TE_STK[@]:0:n-1}")
  if (( n == 1 )); then trap - INT TSTP; [ -n "$_TE_OLDTRAP" ] && eval "$_TE_OLDTRAP"; _TE_OLDTRAP=""; fi
  return 0
}
_te_interrupt() { trap - INT TSTP; kill -INT 0 2>/dev/null; }   # Ctrl-C with nothing selected is what it always was: the interrupt
_te_onsig() {        # SIGINT = Ctrl-C (copy) · SIGTSTP = Ctrl-Z (undo), for the editor on top
  local n=${#_TE_STK[@]} c
  if (( n == 0 )); then [ "$1" = int ] && _te_interrupt; return 0; fi
  IFS=" " builtin read -ra c <<< "${_TE_STK[n-1]}"
  if [ "$1" = int ]; then _te_dispatch ctrl-c "${c[0]}" "${c[1]}" "${c[2]}" "${c[3]}" "${c[4]}" "${c[5]}"
  else _te_dispatch ctrl-z "${c[0]}" "${c[1]}" "${c[2]}" "${c[3]}" "${c[4]}" "${c[5]}"; fi
  return 0
}

# ── selection ─────────────────────────────────────────────────────────────────────────────────────────────────────────
# _te_sel TEXT CURSOR  -> rc 0 and _TE_LO / _TE_HI when TEXT has a selection (anchor and cursor apart)
_te_sel() {
  (( _TE_ANC >= 0 )) || return 1
  [ "$1" = "$_TE_ABUF" ] || return 1
  (( _TE_ANC <= ${#1} && _TE_ANC != $2 )) || return 1
  if (( _TE_ANC < $2 )); then _TE_LO=$_TE_ANC; _TE_HI=$2; else _TE_LO=$2; _TE_HI=$_TE_ANC; fi
  return 0
}

# _te_hl TEXT CURSOR START LEN -> _TE_OUT = TEXT[START, START+LEN) with the selected part in reverse video
_te_hl() {
  local b="$1" s="$3" l="$4" a z
  _TE_OUT="${b:s:l}"
  _te_sel "$b" "$2" || return 0
  a=$(( _TE_LO > s ? _TE_LO : s )); z=$(( _TE_HI < s + l ? _TE_HI : s + l ))
  (( a < z )) || return 0
  _TE_OUT="${b:s:a-s}"$'\033[7m'"${b:a:z-a}"$'\033[27m'"${b:z:s+l-z}"
}

# _te_sel_len TEXT CURSOR -> _TE_N = how many characters of TEXT are selected (0 = none)
_te_sel_len() { _TE_N=0; _te_sel "$1" "$2" && _TE_N=$(( _TE_HI - _TE_LO )); return 0; }

# ── undo ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
# _te_push TEXT CURSOR KIND — remember the line before a change (typing / backspacing in a row is ONE undo step)
_te_push() {
  if [ "$3" = type ] || [ "$3" = bs ]; then [ "$_TE_LASTOP" = "$3" ] && return 0; fi
  _TE_UNDO+=("$2|$1")
  (( ${#_TE_UNDO[@]} > 100 )) && _TE_UNDO=("${_TE_UNDO[@]:1}")
  _TE_REDO=(); _TE_LASTOP="$3"
  return 0
}
_te_undo() {
  local -n _te_b="$1" _te_p="$2"
  local n=${#_TE_UNDO[@]} s
  (( n > 0 )) || return 1
  s="${_TE_UNDO[n-1]}"; _TE_UNDO=("${_TE_UNDO[@]:0:n-1}")
  _TE_REDO+=("$_te_p|$_te_b")
  _te_p="${s%%|*}"; _te_b="${s#*|}"; _TE_ANC=-1; _TE_LASTOP=undo
  return 0
}
_te_redo() {
  local -n _te_b="$1" _te_p="$2"
  local n=${#_TE_REDO[@]} s
  (( n > 0 )) || return 1
  s="${_TE_REDO[n-1]}"; _TE_REDO=("${_TE_REDO[@]:0:n-1}")
  _TE_UNDO+=("$_te_p|$_te_b")
  _te_p="${s%%|*}"; _te_b="${s#*|}"; _TE_ANC=-1; _TE_LASTOP=redo
  return 0
}

# ── editing ───────────────────────────────────────────────────────────────────────────────────────────────────────────
# _te_cut BUFVAR POSVAR LO HI — delete [LO, HI), cursor to LO
_te_cut() {
  local -n _te_b="$1" _te_p="$2"
  _te_push "$_te_b" "$_te_p" cut
  _te_b="${_te_b:0:$3}${_te_b:$4}"; _te_p=$3; _TE_ANC=-1
}
_te_del_sel() {
  local -n _te_b="$1" _te_p="$2"
  _te_sel "$_te_b" "$_te_p" || return 1
  _te_cut "$1" "$2" "$_TE_LO" "$_TE_HI"
  return 0
}
# _te_insert BUFVAR POSVAR TEXT — type / paste: a selection is replaced, the cursor lands after TEXT
_te_insert() {
  local -n _te_b="$1" _te_p="$2"
  local t="$3" k=type
  [ -n "$t" ] || return 0
  (( ${#t} > 1 )) && k=paste
  if _te_sel "$_te_b" "$_te_p"; then _te_cut "$1" "$2" "$_TE_LO" "$_TE_HI"; k=paste; else _te_push "$_te_b" "$_te_p" "$k"; fi
  _TE_ANC=-1
  _te_b="${_te_b:0:_te_p}${t}${_te_b:_te_p}"; _te_p=$(( _te_p + ${#t} ))
}

# ── words and lines ───────────────────────────────────────────────────────────────────────────────────────────────────
_te_wordl() {   # TEXT POS -> _TE_W = start of the word before POS
  local s="$1" i=$2
  while (( i > 0 )) && [[ "${s:i-1:1}" != [[:alnum:]_] ]]; do i=$(( i - 1 )); done
  while (( i > 0 )) && [[ "${s:i-1:1}" == [[:alnum:]_] ]]; do i=$(( i - 1 )); done
  _TE_W=$i
}
_te_wordr() {   # TEXT POS -> _TE_W = end of the word after POS
  local s="$1" i=$2 n=${#1}
  while (( i < n )) && [[ "${s:i:1}" != [[:alnum:]_] ]]; do i=$(( i + 1 )); done
  while (( i < n )) && [[ "${s:i:1}" == [[:alnum:]_] ]]; do i=$(( i + 1 )); done
  _TE_W=$i
}
_te_ls() { local t="${1:0:$2}" last; last="${t##*$'\n'}"; _TE_W=$(( ${#t} - ${#last} )); }          # start of the line POS is on
_te_le() { local rest="${1:$2}" first; first="${rest%%$'\n'*}"; _TE_W=$(( $2 + ${#first} )); }      # end of that line
_te_lineup() {   # same column one line up (the first line: the start of the text)
  local t="${1:0:$2}" last ls col prev pl ps
  last="${t##*$'\n'}"; ls=$(( ${#t} - ${#last} )); col=${#last}
  (( ls > 0 )) || { _TE_W=0; return 0; }
  t="${1:0:ls-1}"; prev="${t##*$'\n'}"; pl=${#prev}; ps=$(( ls - 1 - pl ))
  (( col > pl )) && col=$pl
  _TE_W=$(( ps + col ))
}
_te_linedown() {   # same column one line down (the last line: the end of the text)
  local t="${1:0:$2}" rest="${1:$2}" last col first ns nl
  [[ "$rest" == *$'\n'* ]] || { _TE_W=${#1}; return 0; }
  last="${t##*$'\n'}"; col=${#last}
  first="${rest%%$'\n'*}"; ns=$(( $2 + ${#first} + 1 ))
  rest="${1:ns}"; nl="${rest%%$'\n'*}"
  (( col > ${#nl} )) && col=${#nl}
  _TE_W=$(( ns + col ))
}

# ── the clipboard ─────────────────────────────────────────────────────────────────────────────────────────────────────
# Whatever this machine has: Termux:API, macOS, Wayland, X11, WSL; over ssh the terminal's own clipboard (OSC 52, set only).
# With none of them the app keeps the text itself, so cut / copy / paste still work inside the app.
_te_run() { if command -v timeout >/dev/null 2>&1; then timeout 3 "$@"; else "$@"; fi; }
_te_clip_set() {
  _TE_CLIP="$1"
  if command -v termux-clipboard-set >/dev/null 2>&1; then builtin printf '%s' "$1" | _te_run termux-clipboard-set >/dev/null 2>&1 && return 0
  elif command -v pbcopy >/dev/null 2>&1; then builtin printf '%s' "$1" | pbcopy >/dev/null 2>&1 && return 0
  elif [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null 2>&1; then builtin printf '%s' "$1" | _te_run wl-copy >/dev/null 2>&1 && return 0
  elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then builtin printf '%s' "$1" | _te_run xclip -selection clipboard -i >/dev/null 2>&1 && return 0
  elif [ -n "${DISPLAY:-}" ] && command -v xsel >/dev/null 2>&1; then builtin printf '%s' "$1" | _te_run xsel -ib >/dev/null 2>&1 && return 0
  elif command -v clip.exe >/dev/null 2>&1; then builtin printf '%s' "$1" | clip.exe >/dev/null 2>&1 && return 0
  fi
  declare -F _bb_osc52_copy >/dev/null 2>&1 && _bb_osc52_copy "$1" 2>/dev/null
  return 0
}
_te_clip_get() {   # -> _TE_GOT
  local t=""
  if command -v termux-clipboard-get >/dev/null 2>&1; then t="$(_te_run termux-clipboard-get 2>/dev/null </dev/null)"
  elif command -v pbpaste >/dev/null 2>&1; then t="$(pbpaste 2>/dev/null </dev/null)"
  elif [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null 2>&1; then t="$(_te_run wl-paste -n 2>/dev/null </dev/null)"
  elif [ -n "${DISPLAY:-}" ] && command -v xclip >/dev/null 2>&1; then t="$(_te_run xclip -selection clipboard -o 2>/dev/null </dev/null)"
  elif [ -n "${DISPLAY:-}" ] && command -v xsel >/dev/null 2>&1; then t="$(_te_run xsel -ob 2>/dev/null </dev/null)"
  elif command -v powershell.exe >/dev/null 2>&1; then t="$(_te_run powershell.exe -NoProfile -Command Get-Clipboard 2>/dev/null </dev/null | tr -d '\r')"
  fi
  [ -n "$t" ] || t="$_TE_CLIP"
  _TE_GOT="$t"
}

# ── decoding keys into chords ─────────────────────────────────────────────────────────────────────────────────────────
# A chord is a name: left  shift-left  ctrl-left  ctrl-shift-left  home  delete  ctrl-delete  backspace  ctrl-a  ctrl-shift-c ...
_te_decode_byte() {   # one byte read from the terminal -> _TE_CH (rc 1 = not an editing key)
  case "$1" in
    $'\x01') _TE_CH=ctrl-a ;;
    $'\x03') _TE_CH=ctrl-c ;;
    $'\x04') _TE_CH=ctrl-d ;;
    $'\x05') _TE_CH=ctrl-e ;;
    $'\x0b') _TE_CH=ctrl-k ;;
    $'\x15') _TE_CH=ctrl-u ;;
    $'\x16') _TE_CH=ctrl-v ;;
    $'\x17') _TE_CH=ctrl-w ;;
    $'\x18') _TE_CH=ctrl-x ;;
    $'\x19') _TE_CH=ctrl-y ;;
    $'\x1a') _TE_CH=ctrl-z ;;
    $'\x7f'|$'\x08') _TE_CH=backspace ;;
    *) _TE_CH=""; return 1 ;;
  esac
  return 0
}

# what followed the escape byte (as _read_key_seq returns it) -> _TE_CH  (rc 1 = not an editing key)
# CSI forms understood:  ESC[1;5D (modifier = 1 + shift 1 + alt 2 + ctrl 4) · ESC[3;5~ · ESC[99;5u (kitty) · ESC[27;5;99~ (xterm)
_te_decode_esc() {
  local s="$1" fin p a b c rest k="" code="" mod=1 m ct=0 sh=0 L=abcdefghijklmnopqrstuvwxyz pre=""
  _TE_CH=""
  case "$s" in
    '['?*) ;;
    O[ABCDHF]) case "${s:1}" in A) _TE_CH=up ;; B) _TE_CH=down ;; C) _TE_CH=right ;; D) _TE_CH=left ;; H) _TE_CH=home ;; F) _TE_CH=end ;; esac; return 0 ;;
    $'\x7f'|$'\x08') _TE_CH=ctrl-backspace; return 0 ;;       # Alt+Backspace
    b) _TE_CH=ctrl-left; return 0 ;;                          # Alt+B / Alt+F / Alt+D: the readline words
    f) _TE_CH=ctrl-right; return 0 ;;
    d) _TE_CH=ctrl-delete; return 0 ;;
    *) return 1 ;;
  esac
  fin="${s: -1}"; p="${s:1:${#s}-2}"
  a="${p%%;*}"; rest="${p#*;}"; [ "$rest" = "$p" ] && rest=""
  b="${rest%%;*}"; c="${rest#*;}"; [ "$c" = "$rest" ] && c=""
  case "$fin" in
    A|B|C|D|H|F)
      case "$fin" in A) k=up ;; B) k=down ;; C) k=right ;; D) k=left ;; H) k=home ;; F) k=end ;; esac
      mod="${b:-1}" ;;
    '~')
      case "$a" in
        1|7) k=home ;; 2) k=insert ;; 3) k=delete ;; 4|8) k=end ;; 5) k=pgup ;; 6) k=pgdn ;;
        27) code="$c" ;;
        *) return 1 ;;
      esac
      mod="${b:-1}" ;;
    u) code="$a"; mod="${b:-1}" ;;
    *) return 1 ;;
  esac
  if [ -n "$code" ]; then
    [[ "$code" =~ ^[0-9]+$ ]] || return 1
    if (( code == 127 || code == 8 )); then k=backspace
    elif (( code >= 97 && code <= 122 )); then k="${L:code-97:1}"
    elif (( code >= 65 && code <= 90 )); then k="${L:code-65:1}"; sh=1
    else return 1; fi
  fi
  [[ "$mod" =~ ^[0-9]+$ ]] || return 1
  m=$(( mod > 0 ? mod - 1 : 0 ))
  (( m & 1 )) && sh=1
  (( m & 2 )) && ct=1                    # Alt works like Ctrl for words
  (( m & 4 )) && ct=1
  [ -n "$k" ] || return 1
  [[ "$k" == [a-z] ]] && (( ! ct )) && return 1       # a plain letter is typing, not a chord
  (( ct )) && pre="ctrl-"
  (( sh )) && pre+="shift-"
  _TE_CH="$pre$k"
  return 0
}

# ── the one switch ────────────────────────────────────────────────────────────────────────────────────────────────────
# _te_apply CHORD BUFVAR POSVAR MODE -> 0 not an editing key · 1 cursor / selection moved · 2 text changed · 3 paste (_BVK_PASTE) · 4 done, nothing to redraw
_te_apply() {
  local ch="$1" mode="${4:-text}"
  local -n _te_b="$2" _te_p="$3"
  local len=${#_te_b} sel=0 ct=0 sh=0 base="$1" np lo=0 hi=0
  if _te_sel "$_te_b" "$_te_p"; then sel=1; lo=$_TE_LO; hi=$_TE_HI; fi
  case "$ch" in
    ctrl-a)
      (( len > 0 )) || { [ "$mode" = list ] && return 0; return 4; }
      _TE_ANC=0; _TE_ABUF="$_te_b"; _te_p=$len; _TE_LASTOP=move; return 1 ;;
    ctrl-e)
      (( len > 0 )) || { [ "$mode" = list ] && return 0; return 4; }
      _TE_ANC=-1; _te_p=$len; _TE_LASTOP=move; return 1 ;;
    ctrl-c|ctrl-shift-c|ctrl-insert)
      if (( sel )); then _te_clip_set "${_te_b:lo:hi-lo}"; return 4; fi
      [ "$ch" = ctrl-c ] && _te_interrupt                    # nothing selected: Ctrl-C is what it always was
      return 4 ;;
    ctrl-x|ctrl-shift-x|shift-delete)
      (( sel )) || return 4
      _te_clip_set "${_te_b:lo:hi-lo}"; _te_del_sel "$2" "$3"; return 2 ;;
    ctrl-v|ctrl-shift-v|shift-insert)
      _te_clip_get; [ -n "$_TE_GOT" ] || return 4
      if declare -F _bvk_paste_clean >/dev/null 2>&1; then _bvk_paste_clean "$_TE_GOT"; else _BVK_PASTE="$_TE_GOT"; fi
      while [[ "$_BVK_PASTE" == *[$'\r\n'] ]]; do _BVK_PASTE="${_BVK_PASTE%[$'\r\n']}"; done
      [ -n "$_BVK_PASTE" ] || return 4
      return 3 ;;
    ctrl-z) _te_undo "$2" "$3" && return 2; return 4 ;;
    ctrl-y|ctrl-shift-z) _te_redo "$2" "$3" && return 2; return 4 ;;
    backspace)
      if (( sel )); then _te_del_sel "$2" "$3"; return 2; fi
      (( _te_p > 0 )) || return 4
      _te_push "$_te_b" "$_te_p" bs
      _te_b="${_te_b:0:_te_p-1}${_te_b:_te_p}"; _te_p=$(( _te_p - 1 )); return 2 ;;
    delete|ctrl-d)
      [ "$ch" = ctrl-d ] && (( len == 0 )) && return 0        # Ctrl-D on an empty line is the caller's end-of-input
      if (( sel )); then _te_del_sel "$2" "$3"; return 2; fi
      (( _te_p < len )) || return 4
      _te_push "$_te_b" "$_te_p" del
      _te_b="${_te_b:0:_te_p}${_te_b:_te_p+1}"; return 2 ;;
    ctrl-backspace|ctrl-w)
      if (( sel )); then _te_del_sel "$2" "$3"; return 2; fi
      (( _te_p > 0 )) || return 4
      _te_wordl "$_te_b" "$_te_p"; _te_cut "$2" "$3" "$_TE_W" "$_te_p"; return 2 ;;
    ctrl-delete)
      if (( sel )); then _te_del_sel "$2" "$3"; return 2; fi
      (( _te_p < len )) || return 4
      _te_wordr "$_te_b" "$_te_p"; _te_cut "$2" "$3" "$_te_p" "$_TE_W"; return 2 ;;
    ctrl-u)
      _te_ls "$_te_b" "$_te_p"; (( _TE_W < _te_p )) || return 4
      _te_cut "$2" "$3" "$_TE_W" "$_te_p"; return 2 ;;
    ctrl-k)
      _te_le "$_te_b" "$_te_p"; (( _TE_W > _te_p )) || return 4
      _te_cut "$2" "$3" "$_te_p" "$_TE_W"; return 2 ;;
  esac
  # movement and selection by movement
  [[ "$base" == ctrl-* ]] && { ct=1; base="${base#ctrl-}"; }
  [[ "$base" == shift-* ]] && { sh=1; base="${base#shift-}"; }
  case "$base" in left|right|home|end|up|down) ;; *) return 0 ;; esac
  if (( ! sh )); then
    case "$base" in
      up|down) return 0 ;;                                                   # the list's (or the prompt's own) keys
      home|end) (( ct )) || { [ "$mode" = list ] && return 0; } ;;
      left|right) (( ct )) || { [ "$mode" = list ] && [ -z "$_te_b" ] && return 0; } ;;   # an empty line: the list's tab keys
    esac
  fi
  if (( ! sh && sel && ! ct )) && [[ "$base" == left || "$base" == right ]]; then
    [ "$base" = left ] && np=$lo || np=$hi                                  # a selection collapses to its edge
  else
    case "$base" in
      left)  if (( ct )); then _te_wordl "$_te_b" "$_te_p"; np=$_TE_W; else np=$(( _te_p > 0 ? _te_p - 1 : 0 )); fi ;;
      right) if (( ct )); then _te_wordr "$_te_b" "$_te_p"; np=$_TE_W; else np=$(( _te_p < len ? _te_p + 1 : len )); fi ;;
      home)  if (( ct )); then np=0;    else _te_ls "$_te_b" "$_te_p"; np=$_TE_W; fi ;;
      end)   if (( ct )); then np=$len; else _te_le "$_te_b" "$_te_p"; np=$_TE_W; fi ;;
      up)    _te_lineup "$_te_b" "$_te_p"; np=$_TE_W ;;
      down)  _te_linedown "$_te_b" "$_te_p"; np=$_TE_W ;;
    esac
  fi
  if (( sh )); then (( sel )) || { _TE_ANC=$_te_p; _TE_ABUF="$_te_b"; }
  else _TE_ANC=-1; fi
  _te_p=$np; _TE_LASTOP=move
  return 1
}

# _te_dispatch CHORD BUFVAR POSVAR MODE REDRAW EDIT PASTE -> 0 done (the loop continues) · 1 not an editing key
_te_dispatch() {
  local _td_rc
  _te_apply "$1" "$2" "$3" "$4"; _td_rc=$?
  case "$_td_rc" in
    0) return 1 ;;
    1) "$5" ;;
    2) "$6" ;;
    3) "$7" "$_BVK_PASTE" ;;
  esac
  return 0
}
# (the wrappers take MODE first, as documented at the top; _te_dispatch takes it after the two variables)
_te_esc()  { _te_decode_esc "$1" || return 1; _te_dispatch "$_TE_CH" "$3" "$4" "$2" "${@:5}"; }
_te_byte() { _te_decode_byte "$1" || return 1; _te_dispatch "$_TE_CH" "$3" "$4" "$2" "${@:5}"; }
