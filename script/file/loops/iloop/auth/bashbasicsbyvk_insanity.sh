#!/usr/bin/env bash
# insanity — the insanity meter: one row above the status row (lang | notifications | pending) of the main screen.
# ════════════════════════════════════════════════════════════════════════════
#  What it shows      🧠 ███████████░░░░░░░░░  63  unhinged
#  Scale              0-100 (it may pass 100: "severely insane"). Colour is a GRADIENT of the level:
#                     green 0-40 · light orange to 60 · yellow to 80 · red to 100 · violet above 100
#  How it is made     (the server does the sum)  level = yesterday's level / 2 + today's credits consumed / 50 * 100
#  Free users         the bar is blurred and says "Upgrade to see your insanity levels" (the plan table is in bashbasicsbyvk_auth.sh)
#  Background         like the notification count (⏰): the header only READS a tiny cache file ("<epoch> <plan> <level> <user>")
#                     and never waits for the network; a stale cache starts ONE silent background refresh (GET /plan, at most
#                     once a minute). No -auth user = no row at all.
# ════════════════════════════════════════════════════════════════════════════

_IN_STALE_S=120          # the cache is refreshed in the background when older than this
_IN_LOCK_S=60            # ... and at most once in this time
_IN_FULL_CREDITS=50      # credits consumed in a day = 100 on the meter (server twin: CREDITS_FOR_FULL_METER in fileapi/src/plans.js)

# gradient stops: level -> colour.  Green until 40, light orange at 60, yellow at 80, red at 100, violet from 130 up.
_IN_SV=(0 40 60 80 100 130)
_IN_SR=(60 60 255 250 235 150)
_IN_SG=(200 200 170 220 50 80)
_IN_SB=(90 90 80 60 50 230)

_in_state_file() { printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/bashbasicsbyvk/insanity"; }

# level (integer, any size) -> _IN_R _IN_G _IN_B  (integer maths, no forks: the header is redrawn all the time)
_in_rgb() {
  local v=$1 i n=${#_IN_SV[@]} v0 v1 span t
  (( v < 0 )) && v=0
  (( v > _IN_SV[n-1] )) && v=${_IN_SV[n-1]}
  for (( i = 1; i < n - 1; i++ )); do (( v <= _IN_SV[i] )) && break; done
  v0=${_IN_SV[i-1]}; v1=${_IN_SV[i]}; span=$(( v1 - v0 )); t=$(( v - v0 ))
  _IN_R=$(( _IN_SR[i-1] + (_IN_SR[i] - _IN_SR[i-1]) * t / span ))
  _IN_G=$(( _IN_SG[i-1] + (_IN_SG[i] - _IN_SG[i-1]) * t / span ))
  _IN_B=$(( _IN_SB[i-1] + (_IN_SB[i] - _IN_SB[i-1]) * t / span ))
}
# r g b -> _IN_ESC  (24-bit colour when the terminal says it has it, else the nearest of the 256-colour cube)
_in_esc() {
  case "${COLORTERM:-}" in
    truecolor|24bit) _IN_ESC=$'\033[38;2;'"$1;$2;$3"m ;;
    *) _IN_ESC=$'\033[38;5;'"$(( 16 + 36 * ($1 * 5 / 255) + 6 * ($2 * 5 / 255) + ($3 * 5 / 255) ))"m ;;
  esac
}
# the word that goes with a level (server twin: insanityLabel in fileapi/src/plans.js)
_in_label() {
  local v=$1
  if   (( v > 100 )); then _IN_LABEL="severely insane"
  elif (( v > 80 ));  then _IN_LABEL="raving"
  elif (( v > 60 ));  then _IN_LABEL="unhinged"
  elif (( v > 40 ));  then _IN_LABEL="restless"
  else _IN_LABEL="calm"; fi
}

# _in_bar LEVEL WIDTH -> _IN_BAR  (coloured, ends with a reset).  Cell i of a filled bar has the colour of its own place on the
# 0-100 scale, so a bar at 70 runs green -> orange -> yellow; above 100 the whole bar is pulled towards violet.
_in_bar() {
  local lv=$1 w=$2 i fill shift=0 pos out="" dim=$'\033[2m'
  (( lv < 0 )) && lv=0
  if (( lv > 100 )); then fill=$w; shift=$(( (lv - 100) * 3 )); else fill=$(( (lv * w + 50) / 100 )); (( lv > 0 && fill == 0 )) && fill=1; fi
  for (( i = 0; i < w; i++ )); do
    if (( i < fill )); then
      pos=$(( (i + 1) * 100 / w + shift ))
      _in_rgb "$pos"; _in_esc "$_IN_R" "$_IN_G" "$_IN_B"; out+="${_IN_ESC}█"
    else out+="${dim}░"; fi
    out+=$'\033[0m'
  done
  _IN_BAR="$out"
}
# the blurred bar of a free user: shades only, no colour, no level
_in_blur() {
  local w=$1 i out="" pat=(▒ ░ ▓ ▒ ░ ▒ ▓ ░)
  for (( i = 0; i < w; i++ )); do out+="${pat[i % 8]}"; done
  _IN_BAR=$'\033[2;90m'"$out"$'\033[0m'
}

# ── the cache (read by the header, written by the background refresh and by the Plan screen)
_IN_PLAN=""; _IN_LEVEL=""
_in_store() {   # $1=plan key  $2=level (or "-" when the account has no meter)
  local f; f=$(_in_state_file); mkdir -p "${f%/*}" 2>/dev/null || return 0
  printf '%s %s %s %s\n' "${EPOCHSECONDS:-$(date +%s)}" "$1" "$2" "$(cat "${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/active" 2>/dev/null)" > "$f" 2>/dev/null
  return 0
}
# the /plan answer -> _IN_P_KEY _IN_P_NAME _IN_P_REALM _IN_P_LEVEL _IN_P_LABEL _IN_P_CM _IN_P_SM _IN_P_MONTHLY _IN_P_LOCKED ; 1 when it is not a plan answer
_in_parse() {
  local rec; rec=$(node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => { try {
      const o = JSON.parse(d), p = o.plan, i = o.insanity || {};
      if (!o.ok || !p) process.exit(1);
      process.stdout.write([p.key, p.name, p.realm, i.level === undefined ? "-" : Math.round(i.level), i.label || "", p.credit_mult, p.sub_mult, p.monthly_charge_credits, o.insanity_locked ? 1 : 0].join("\x1f"));
    } catch (e) { process.exit(1); } });' <<<"$1" 2>/dev/null) || return 1
  IFS=$'\x1f' read -r _IN_P_KEY _IN_P_NAME _IN_P_REALM _IN_P_LEVEL _IN_P_LABEL _IN_P_CM _IN_P_SM _IN_P_MONTHLY _IN_P_LOCKED <<<"$rec"
  [ -n "$_IN_P_KEY" ]
}
_in_refresh() {   # runs in a silent background subshell
  _ux_http GET /plan >/dev/null 2>&1 || true
  [ "${_UX_STATUS:-}" = 200 ] || return 0
  _in_parse "$_UX_BODY" && _in_store "$_IN_P_KEY" "$_IN_P_LEVEL"
}
# -> _IN_PLAN _IN_LEVEL  (empty while nothing is known yet).  Never waits: a stale cache only starts the background refresh.
_in_get() {
  local f at plan lv uid now lock age act
  _IN_PLAN=""; _IN_LEVEL=""
  f=$(_in_state_file); now=${EPOCHSECONDS:-$(date +%s)}
  IFS= read -r act < "${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/active" 2>/dev/null
  at=0
  if [ -r "$f" ]; then
    read -r at plan lv uid < "$f"
    [[ "$at" =~ ^[0-9]+$ ]] || at=0
    if [ "$uid" = "$act" ]; then _IN_PLAN="$plan"; _IN_LEVEL="$lv"; else at=0; fi     # another user was active: not theirs
  fi
  if (( now - at >= _IN_STALE_S )); then
    lock="$f.lock"; age=999
    [ -e "$lock" ] && { read -r age < "$lock" 2>/dev/null; [[ "$age" =~ ^[0-9]+$ ]] && age=$(( now - age )) || age=999; }
    if (( age >= _IN_LOCK_S )) && command -v curl >/dev/null 2>&1; then
      mkdir -p "${f%/*}" 2>/dev/null; printf '%s\n' "$now" > "$lock" 2>/dev/null
      ( _in_refresh >/dev/null 2>&1 </dev/null & ) 2>/dev/null
    fi
  fi
  return 0
}

# ── the row.  Prints ONE line (with its newline), or nothing when no -auth user is active.
_in_row() {
  [ -s "${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk/auth/active" ] || return 0
  _in_get
  local cols=${COLUMNS:-80} w=20 lv txt
  (( cols < 60 )) && w=12
  if [ -z "$_IN_PLAN" ]; then                                               # nothing known yet (no fork: the header is redrawn all the time)
    local i dots=""; for (( i = 0; i < w; i++ )); do dots+="·"; done
    printf '🧠 \033[2m%s\033[0m  –\n' "$dots"; return 0
  fi
  if [ "$_IN_PLAN" = free ] || [ "$_IN_LEVEL" = "-" ] || [ -z "$_IN_LEVEL" ]; then   # animal realm: blurred
    txt="🔒 Upgrade to see your insanity levels"
    (( cols < 52 )) && { w=8; txt="🔒 Upgrade to see insanity"; }
    _in_blur "$w"
    printf '🧠 %s  \033[2m%s\033[0m\n' "$_IN_BAR" "$txt"
    return 0
  fi
  lv=$_IN_LEVEL; [[ "$lv" =~ ^[0-9]+$ ]] || lv=0
  _in_bar "$lv" "$w"; _in_label "$lv"
  _in_rgb "$lv"; _in_esc "$_IN_R" "$_IN_G" "$_IN_B"
  printf '🧠 %s  %s%s\033[0m  \033[2m%s\033[0m\n' "$_IN_BAR" "$_IN_ESC" "$lv" "$_IN_LABEL"
}
