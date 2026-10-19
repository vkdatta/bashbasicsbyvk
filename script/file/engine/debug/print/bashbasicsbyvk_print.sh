#!/usr/bin/env bash
# ============================================================
#  PRINT  —  "what is on my screen right now?"  as plain text
#
#  Typed at any prompt:   print
#  gives the screen exactly as the last menu drew it (header, rows, footer, the "Select:" line)
#  and offers the same two options as  p- :  1) copy to clipboard   2) save as txt
#
#  How it works
#  ------------
#  Every menu is drawn by ONE of four code paths, and each keeps a copy of what it just drew:
#     _vp_emit          the viewport (main list, switch, fx, upgrade, rules, api, smart menus …)
#     _st_draw          the Settings / Home screens
#     echo / printf     plain text printed between menus (recorded by the smart-menu layer)
#     the prompt line   "Select:" or the text of a question
#  Nothing is copied while you navigate: the copy is a single variable assignment per redraw.
#  The ANSI colour / cursor codes are stripped only when  print  is typed.
# ============================================================

_BVK_SCR_RAW=""        # the last frame a menu drew (with its escape codes)
_BVK_SCR_EXTRA=""      # plain output printed after that frame (messages, a question's text)
_BVK_SCR_PROMPT=""     # the prompt line that was waiting for the answer, e.g. "Select:"

# escape codes / cursor moves / carriage returns → plain text
_bvk_scr_plain() {
  local esc=$'\033'
  printf '%s' "$1" | sed -E \
    -e "s#${esc}\\][^${esc}]*(${esc}\\\\|\\x07)##g" \
    -e "s#${esc}\\[[0-9;?<=>]*[ -/]*[@-~]##g" \
    -e "s#${esc}[()][0-9A-Za-z]##g" \
    -e 's/.*\r//' 2>/dev/null
}

# the screen as plain text (stdout)
_bvk_scr_text() {
  local body extra prompt
  body="$(_bvk_scr_plain "$_BVK_SCR_RAW")"
  extra="$(_bvk_scr_plain "$_BVK_SCR_EXTRA")"
  prompt="${_BVK_SCR_PROMPT%"${_BVK_SCR_PROMPT##*[![:space:]]}"}"
  [ -n "$prompt" ] || prompt="Select:"
  # trailing blank lines are noise
  body="${body#"${body%%[![:space:]]*}"}"
  body="${body%"${body##*[![:space:]]}"}"
  extra="${extra%"${extra##*[![:space:]]}"}"
  extra="${extra#"${extra%%[![:space:]]*}"}"
  printf '%s\n' "$body"
  [ -n "$extra" ] && printf '%s\n' "$extra"
  printf '%s\n' "$prompt"
}

# `print` — capture, then copy / save
bvk_print_cmd() {
  declare -F _lt_tool_begin >/dev/null 2>&1 && _lt_tool_begin
  local text lines
  text="$(_bvk_scr_text)"
  lines=$(printf '%s\n' "$text" | wc -l)
  builtin printf '📸 Captured the screen (%s lines)\n' "${lines//[[:space:]]/}"
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  if declare -F _map_deliver >/dev/null 2>&1; then
    _map_deliver "$text" "bvk-screen-$(date +%Y%m%d-%H%M%S).txt"
  fi
  declare -F _lt_tool_end >/dev/null 2>&1 && _lt_tool_end
  return 0
}
