#!/usr/bin/env bash
# ============================================================
#  CC  —  cheat codes
#
#  Typed at any prompt that has the command layer:     cc
#  opens a Settings / Home style list of every command THAT prompt accepts right now:
#
#     🎮 Cheat codes  ·  main
#        ─────────────────────────────
#      1) loadtime          Load time: what each screen change cost   ›
#      2) c-                Stage COPY   (e.g. c-1,3)                  ›
#      …
#     u) Back   ↑↓) Move
#     Type 1-60, then enter to put it in the prompt   =) Filter
#     Select:
#
#  Pick a row (number + Enter, ↑↓ + Enter, or  =lo  to filter first) and the list closes.
#  The command is then TYPED INTO THE PROMPT you came from — exactly as if you had keyed it in —
#  and waits there.  Nothing runs until you press Enter, so a command that needs an argument
#  (c-  m-  .s  …) can be finished first:   c-  →  c-1-5  →  Enter.
#
#  What is listed
#  --------------
#  Not "every command in the app" but the ones this prompt would really run, decided by the
#  command map itself (the same _cm_resolve that judges what you type):
#     · wired in this menu's .map (own commands + the main ones it inherits), not blocked,
#     · and accepted by this KIND of prompt:  a menu (Select:)  accepts act / filter commands,
#       a prompt inside a flow (Item numbers: …)  accepts only nav / util / tool commands,
#     · plus the keys a smart menu prints itself ("c) Create user"),
#     · Settings / Home screens have their own, smaller grammar:  u  q  =  print  loadtime  cc.
#  So the list can never offer a command that would answer "❌ Invalid command".
#
#  "=" filter   =lo   matches the command NAMES first (loadtime).  When no name matches, the
#               descriptions are searched too  (=stage  →  c-  m-  s-  b-).
#
#  How the pick reaches the prompt
#  -------------------------------
#  cc leaves the text in  _CC_PREFILL.  Every reader consumes it once, when it starts:
#     _read_choice_raw         Select:            (main list and every viewport menu)
#     _multi_prompt_loop_raw   Item numbers:
#     _sm_run                  smart menus (numbered read -p lists)
#     _cm_text_read            plain text questions
#     _st_run                  Settings / Home screens
#  A text that starts with  =  is replayed key by key so the live filter starts; anything else is
#  dropped into the buffer in one go.  The gates clear a pick nobody consumed.
# ============================================================

_CC_PREFILL=""        # text waiting to be typed into the next prompt that reads
_CC_HINT_NOW=0        # 1 = the text editor should paint the hint row for the text it starts with
_CC_OPEN=0            # 1 while the cc list itself is on screen (cc inside cc is ignored)
_CC_CTX=""            # "st" = called from a Settings / Home screen (their own, smaller grammar)

declare -ga _CC_KEY=() _CC_DESC=() _CC_INS=()

# ------------------------------------------------------------ what can be typed here?
_cc_add() {   # key description   (first one wins, a key is listed once)
  case "$_cc_seen" in *$'\n'"$1"$'\n'*) return 0 ;; esac
  _cc_seen+="$1"$'\n'
  _CC_KEY+=("$1"); _CC_DESC+=("$2"); _CC_INS+=("$1")
}

_cc_collect() {
  _CC_KEY=(); _CC_DESC=(); _CC_INS=()
  local _cc_seen=$'\n'
  if [ "$_CC_CTX" = st ]; then
    # Settings / Home screens read only these (see _st_run)
    _cc_add u        "Back"
    _cc_add q        "Close Settings, back to the main menu"
    _cc_add '='      "Filter the rows  (=text · Enter keeps it · = + Enter clears it)"
    _cc_add print    "Print what is on screen — copy it or save as txt"
    _cc_add loadtime "Load time: what each screen change cost  (loadtime 2 · loadtime all)"
    return 0
  fi

  local mode="${_CM_RUN_MODE:-menu}" m="${_CM_MAP:-main}" i key tgt k
  [ "${_CM_BOOTED:-0}" = 1 ] || _cm_boot
  _cm_table_build "$m"
  local n=${#_ct_key[@]}
  # copy the table first: _cm_resolve below must not disturb what we iterate
  local -a tk=("${_ct_key[@]}") tt=("${_ct_tgt[@]}")
  for (( i=0; i<n; i++ )); do
    key="${tk[i]}"; tgt="${tt[i]}"
    [ "$tgt" = BLOCK ] && continue
    case "$_cc_seen" in *$'\n'"$key"$'\n'*) continue ;; esac
    # would THIS prompt take the key?  (the same judge that handles what you type)
    _cm_resolve "$mode" "$key"
    case "$_CM_ACT" in run|local|back) ;; *) continue ;; esac
    local d="$_CM_DESC"
    [ -n "$_CM_EX" ] && d+="  (e.g. $_CM_EX)"
    _cc_add "$key" "$d"
  done
  # keys the menu draws itself ("c) Create user") are commands of THAT menu
  # (row numbers are not commands: you pick those by typing the number, as always)
  local -a lk=()
  for k in "${!_CM_LOCAL[@]}"; do [[ "$k" =~ ^[0-9]+$ ]] || lk+=("$k"); done
  if [ "${#lk[@]}" -gt 0 ]; then
    while IFS= read -r k; do _cc_add "$k" "${_CM_LOCAL[$k]}"; done < <(printf '%s\n' "${lk[@]}" | sort)
  fi
  return 0
}

# ------------------------------------------------------------ the list (Settings / Home engine)
_cc_build() {
  _st_reset
  local i n=${#_CC_KEY[@]} q xm="${filter_mode:-partial}" k anyk=0
  # =text matches command NAMES first; when no name has it, descriptions are searched too
  _st_filter_wide=0
  q="${fq:-}"; q="${q,,}"
  if [ -n "$q" ]; then
    for (( i=0; i<n; i++ )); do
      k="${_CC_KEY[i],,}"
      if [ "$xm" = exact ]; then [[ "$k" == "$q"* ]] && { anyk=1; break; }
      else [[ "$k" == *"$q"* ]] && { anyk=1; break; }; fi
    done
    (( anyk )) || _st_filter_wide=1
  fi
  for (( i=0; i<n; i++ )); do
    _st_add a "${_CC_KEY[i]}" 0 "${_CC_DESC[i]}" "${_CC_INS[i]}"
  done
}

_cc_act() {   # row index, key — the row's tag is the text to type
  _lm_need bashbasicsbyvk_settings_ui.sh      # a settings callback: reads the screen's _st_tag / sets _st_back
  _CC_PICK="${_st_tag[$1]}"
  _st_back=1
}

# cc  —  entry point (bvk_main_exec cc)
bvk_cc_cmd() {
  [ "$_CC_OPEN" = 1 ] && return 0
  if [ ! -t 0 ] || [ ! -t 1 ]; then echo "cc needs a terminal"; return 0; fi
  declare -F _st_run >/dev/null 2>&1 || { echo "cc: the Settings engine is not loaded"; return 0; }
  declare -F _lt_tool_begin >/dev/null 2>&1 && _lt_tool_begin

  _CC_PREFILL=""
  _CC_PICK=""
  _cc_collect
  local where="${_CM_MAP:-main}"
  [ "$_CC_CTX" = st ] && where="this screen"

  # look: header 🎮, no "Settings ›" crumb, our own footer; all of it is undone when we return
  local _st_icon="🎮" _st_crumb="" _st_verb="put it in the prompt" _st_f1_custom="u) Back   ↑↓) Move"
  local _fw_keep="${_st_filter_wide:-0}" _d0="${_st_depth:-0}"
  # a sub-screen: it erases itself when it closes, so the menu you came from redraws in place
  (( _st_depth < 1 )) && _st_depth=1
  _CC_OPEN=1
  _st_run "Cheat codes · $where" _cc_build _cc_act
  _CC_OPEN=0
  _st_quit=0; _st_back=0
  _st_depth=$_d0
  _st_filter_wide=$_fw_keep
  # the Settings engine leaves the keyboard raw while a screen is open: hand it back the way we got it
  if (( _d0 == 0 )); then _st_tty_cooked; _st_stty=""; fi

  _CC_PREFILL="$_CC_PICK"
  _CC_PICK=""
  declare -F _lt_tool_end >/dev/null 2>&1 && _lt_tool_end
  return 0
}

# ------------------------------------------------------------ readers: consume the pick
# _cc_take  →  _CC_TAKEN = the text to start the prompt with ("" = nothing waiting); clears it
_CC_TAKEN=""
_cc_take() { _CC_TAKEN="$_CC_PREFILL"; _CC_PREFILL=""; [ -n "$_CC_TAKEN" ]; }

# _cc_replay KEYFN BULKFN
#   a text that starts with "=" goes through KEYFN one character at a time (the live filter has to
#   see it start); any other text is handed to BULKFN once.
_cc_replay() {
  _cc_take || return 0
  local t="$_CC_TAKEN" i
  if [[ "$t" == =* ]]; then
    for (( i=0; i<${#t}; i++ )); do "$1" "${t:i:1}"; done
  else
    "$2" "$t"
  fi
  return 0
}

# gates call this first: a pick that no reader took must not leak into a later prompt
_cc_forget() { _CC_PREFILL=""; }
