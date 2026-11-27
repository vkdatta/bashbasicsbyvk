#!/usr/bin/env bash
# ============================================================
#  CC  —  cheat codes
#
#  Typed at any prompt that has the command layer:     cc
#  opens a Settings / Home style list of every command THAT prompt accepts right now:
#
#     🎮 Cheat codes  ·  main
#
#     [✳️ Menu Specific] 🌏 General          ← → (or a tap) switch the tab
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
#  Two tabs split that list:
#     ✳️ Menu Specific   the commands only THIS menu handles (its own keys, the file actions of the main list ...)
#     🌏 General         the commands every screen takes: u q h cc rf =, print, loadtime and every main command run by
#                        bvk_main_exec (s i -h -auth disk ram health ...)           (_ad_is_general, bashbasicsbyvk_advert.sh)
#  The cc opens on Menu Specific, or on General when this menu has nothing of its own.  =filter searches the tab you are on.
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

declare -ga _CC_KEY=() _CC_DESC=() _CC_INS=() _CC_SCOPE=()     # _CC_SCOPE[i] = m (menu specific) | g (general): which tab row i belongs to
_CC_TABS_REG=0        # 1 once the tab labels are registered for taps (_bvk_tabs_register)
_CC_TAB_LABELS=("✳️ Menu Specific" "🌏 General")

# ── what can be typed here?   (ADVERT: cc only RENDERS the registry — bashbasicsbyvk_advert.sh)
#   · a list screen (Settings, Home, Pending ...): _st_draw declared everything the screen accepts when it was drawn
#   · any other prompt: the menu's map + the keys the prompt / footer printed, declared now (the same declaring helpers the footers use)
_cc_collect() {
  _CC_KEY=(); _CC_DESC=(); _CC_INS=(); _CC_SCOPE=()
  if [ "$_CC_CTX" != st ]; then
    local m="${_CM_MAP:-main}" k mode=menu
    # how THIS menu takes a typed word: a list prompt (menu) takes the inherited main words; a question inside a flow (text) only the wired ones.
    # Where cc was typed (_CM_RUN_MODE) says nothing about that: a smart menu's gate runs everything in text mode.
    { [ "${_CM_MAP_KIND[$m]:-menu}" = prompt ] || [ "${_CM_FLOW:-0}" != 0 ]; } && mode=text
    [ "${_CM_BOOTED:-0}" = 1 ] || _cm_boot
    _ad_open "$m"
    _ad_from_dispatcher "$m"
    _ad_from_map "$m" "" "$mode"
    for k in "${!_CM_LOCAL[@]}"; do [[ "$k" =~ ^[0-9]+$ ]] || _ad_accept "$k" "${_CM_LOCAL[$k]}" 0; done
    if [ "${_CC_FOOTER:-0}" = 1 ]; then
      for k in "${!_MC_PRINTED[@]}"; do [[ "$k" =~ ^[0-9]+$ ]] || _ad_accept "$k" "${_MC_PRINTED[$k]}" 0; done
    fi
  fi
  _ad_cc_rows
  local i
  for (( i=0; i<${#_AD_CC_KEY[@]}; i++ )); do _CC_KEY+=("${_AD_CC_KEY[i]}"); _CC_DESC+=("${_AD_CC_DESC[i]}"); _CC_INS+=("${_AD_CC_KEY[i]}")
    if _ad_is_general "${_AD_CC_KEY[i]}"; then _CC_SCOPE+=(g); else _CC_SCOPE+=(m); fi
  done
  return 0
}

# ── the list (Settings / Home engine)
_cc_build() {
  _st_reset
  local i n=${#_CC_KEY[@]} q xm="${filter_mode:-partial}" k anyk=0 want=m other=g here=0 there=0
  (( ${_st_tab_cur:-0} == 1 )) && { want=g; other=m; }
  # =text matches command NAMES first; when no name has it, descriptions are searched too
  _st_filter_wide=0
  q="${fq:-}"; q="${q,,}"
  if [ -n "$q" ]; then
    for (( i=0; i<n; i++ )); do
      [ "${_CC_SCOPE[i]}" = "$want" ] || continue                    # the names of THIS tab decide whether descriptions are searched too
      k="${_CC_KEY[i],,}"
      if [ "$xm" = exact ]; then [[ "$k" == "$q"* ]] && { anyk=1; break; }
      else [[ "$k" == *"$q"* ]] && { anyk=1; break; }; fi
    done
    (( anyk )) || _st_filter_wide=1
  fi
  for (( i=0; i<n; i++ )); do
    if [ "${_CC_SCOPE[i]}" = "$want" ]; then
      _st_add a "${_CC_KEY[i]}" 0 "${_CC_DESC[i]}" "${_CC_INS[i]}"
      [ -z "$q" ] || [[ "${_CC_KEY[i],,}" == *"$q"* || "${_CC_DESC[i],,}" == *"$q"* ]] && here=$(( here + 1 ))
    elif [ -n "$q" ]; then
      [[ "${_CC_KEY[i],,}" == *"$q"* || "${_CC_DESC[i],,}" == *"$q"* ]] && there=$(( there + 1 ))
    fi
  done
  # a filter that finds nothing on this tab but something on the other one says so (the footer already says "No match")
  _st_msg=""
  (( here == 0 && there > 0 )) && _st_msg="No match on this tab, $there on the other  (← → switches)"
  return 0
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
  local _st_icon="🎮" _st_crumb="" _st_verb="put it in the prompt"
  # the two tabs (the Settings engine draws the bar and moves _st_tab_cur): open on Menu Specific, or on General when this menu has nothing of its own
  local -a _st_tab_labels=("${_CC_TAB_LABELS[@]}"); local _st_tab_cur=1 _ci _TE_LR_PASS='^[0-9]+$'
  for _ci in "${_CC_SCOPE[@]}"; do [ "$_ci" = m ] && { _st_tab_cur=0; break; }; done
  if (( ! _CC_TABS_REG )); then _CC_TABS_REG=1; declare -F _bvk_tabs_register >/dev/null 2>&1 && _bvk_tabs_register "${_CC_TAB_LABELS[@]}"; fi
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

# ── readers: consume the pick
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

