#!/usr/bin/env bash
# bashbasicsbyvk_loadmap.sh - the LOAD MAPPER's loader (AGENTS.md rule 13).
# ════════════════════════════════════════════════════════════════════════════
#  `o` sources THIS file first. It reads bashbasicsbyvk_loadmap.list, the one place that says when each file loads:
#
#    [fg]  loaded before the first paint, in the order listed. Only what the first screen needs.   (_lm_fg, called by o)
#    [bg]  loaded after the first paint, ONE file at a time, and only while no key is waiting       (_lm_idle, called by o
#          before every prompt). A key that arrives stops the loading at once; it goes on at the next idle moment.
#          `@call fn args` lines in [bg] run a function after the files above them (start-ups that must not delay the paint).
#    [no]  never loaded, unless something calls one of its functions. Every function of a [bg] / [no] file is a one-line stub
#          (bashbasicsbyvk_loadmap_stubs.sh, generated): the first call loads the file, then runs the real function.
#
#  A file loads the files it NEEDS first (the generated needs table), and its WITH companions right after it.
#  Why not a background PROCESS: bash cannot hand functions from a child to its parent, so "background" here means the idle
#  moments after the paint, inside the same shell, one small file between two key checks.
#
#  API:   _lm_need FILE.sh...   load these now (idempotent; put it at the top of a function that reads another file's variables)
#         _lm_all               load everything left (the --map-* tools, tests)
#  Env:   BVK_LOADMAP=all       old behaviour: everything loads before the first paint (to compare, or to debug a load-order bug)
#
#  This is the ONLY place besides `o` that may `source` (rule 3). A file sourced here runs inside a function: a top-level
#  `declare` must be `declare -g` (the loadmap check fails on one that is not).
# ════════════════════════════════════════════════════════════════════════════

_LM_SELF="${BASH_SOURCE[0]}"; _LM_DIR="${_LM_SELF%/*}"; [ "$_LM_DIR" = "$_LM_SELF" ] && _LM_DIR=.
_LM_LIST="$_LM_DIR/bashbasicsbyvk_loadmap.list"
if [ ! -r "$_LM_LIST" ]; then
  _LM_LIST=""
  IFS=: read -ra _lm_p <<<"$PATH"
  for _lm_d in "${_lm_p[@]}"; do [ -r "$_lm_d/bashbasicsbyvk_loadmap.list" ] && { _LM_LIST="$_lm_d/bashbasicsbyvk_loadmap.list"; break; }; done
  unset _lm_p _lm_d
fi
declare -gA _LM_DONE=() _LM_PATH=() _LM_NEEDS=() _LM_WITH=()      # NEEDS / WITH are filled by the generated stubs file
declare -ga _LM_LINES=() _LM_BG=()
_LM_DONE[bashbasicsbyvk_loadmap.sh]=1
_LM_STUBS=0; _LM_BG_READY=0; _LM_BGI=0; _LM_IDLE_DONE=0
declare -F _lt_b >/dev/null 2>&1 || { _lt_b() { :; }; _lt_e() { :; }; }     # until the recorder is loaded

# the one `source` of the app (besides o)
_lm_src() {
  local __lm_f="$1" __lm_p="${_LM_PATH[$1]:-}"
  if [ -z "$__lm_p" ]; then
    if [ -r "$_LM_DIR/$__lm_f" ]; then __lm_p="$_LM_DIR/$__lm_f"; else __lm_p="$__lm_f"; fi    # a bare name: bash looks it up in PATH
    _LM_PATH[$__lm_f]="$__lm_p"
  fi
  _lt_b "load ${__lm_f#bashbasicsbyvk_}"
  source "$__lm_p"
  _lt_e
  [ "$__lm_f" = bashbasicsbyvk_loadtime.sh ] && _lt_init       # the recorder starts the moment it is there, so the next loads are on its timeline
  return 0
}

# the stubs file: needs table + one stub per function of every [bg] / [no] file
_lm_ensure_stubs() {
  [ "$_LM_STUBS" = 1 ] && return 0
  _LM_STUBS=1; _LM_DONE[bashbasicsbyvk_loadmap_stubs.sh]=1
  _lm_src bashbasicsbyvk_loadmap_stubs.sh
}

# _lm_load FILE...   the files it needs first, the file, then its WITH companions
_lm_load() {
  local __lm_a
  for __lm_a in "$@"; do
    [ -n "${_LM_DONE[$__lm_a]:-}" ] && continue
    _lm_ensure_stubs
    _LM_DONE[$__lm_a]=1
    [ -n "${_LM_NEEDS[$__lm_a]:-}" ] && _lm_load ${_LM_NEEDS[$__lm_a]}
    _lm_src "$__lm_a"
    [ -n "${_LM_WITH[$__lm_a]:-}" ] && _lm_load ${_LM_WITH[$__lm_a]}
  done
  return 0
}
_lm_need() { _lm_load "$@"; }

# the first call of a stub: load the file that defines the function, then run it
_lm_stub() {
  local __lm_file="$1" __lm_fn="$2"; shift 2
  if [ -n "${_LM_DONE[$__lm_file]:-}" ]; then
    printf '%s\n' "loadmap: $__lm_fn is not defined by $__lm_file (it was loaded, the function is still a stub)" >&2
    return 127
  fi
  _lm_load "$__lm_file"
  "$__lm_fn" "$@"
}

# [fg]: o calls this once, before anything else is loaded
_lm_fg() {
  local __lm_ln __lm_f
  [ -n "$_LM_LIST" ] || { printf '%s\n' "loadmap: bashbasicsbyvk_loadmap.list not found next to the loader or in PATH - reinstall bashbasicsbyvk." >&2; return 1; }
  mapfile -t _LM_LINES <"$_LM_LIST"            # read once; sourcing below must not share a stdin with the list
  for __lm_ln in "${_LM_LINES[@]}"; do
    case "$__lm_ln" in
      ''|'#'*|'@'*) continue ;;
      '[fg]'*) continue ;;
      '['*) break ;;
    esac
    __lm_f="${__lm_ln%%[[:space:]|]*}"
    [ -n "${_LM_DONE[$__lm_f]:-}" ] && continue
    _LM_DONE[$__lm_f]=1
    _lm_src "$__lm_f"
  done
  [ "${BVK_LOADMAP:-}" = all ] && _lm_all
  return 0
}

# [bg] queue: "f:FILE" and "c:FN ARGS" items, in the order listed
_lm_read_bg() {
  local __lm_ln __lm_in=0
  _LM_BG_READY=1
  for __lm_ln in "${_LM_LINES[@]}"; do
    case "$__lm_ln" in
      '[bg]'*) __lm_in=1; continue ;;
      '['*) [ "$__lm_in" = 1 ] && break; continue ;;
      ''|'#'*) continue ;;
    esac
    [ "$__lm_in" = 1 ] || continue
    case "$__lm_ln" in
      '@call'*) __lm_ln="${__lm_ln#@call}"; __lm_ln="${__lm_ln%%|*}"; __lm_ln="${__lm_ln#"${__lm_ln%%[![:space:]]*}"}"; _LM_BG+=("c:${__lm_ln%"${__lm_ln##*[![:space:]]}"}") ;;
      *) _LM_BG+=("f:${__lm_ln%%[[:space:]|]*}") ;;
    esac
  done
}

# after the first paint, before the prompt waits for a key: the stubs first (a key may already be waiting, and its command needs them),
# then the [bg] items one by one, stopping the moment a key is waiting
_lm_idle() {
  [ "$_LM_IDLE_DONE" = 1 ] && return 0
  if [ "$_LM_BG_READY" != 1 ]; then _lm_ensure_stubs; _lm_read_bg; fi
  local __lm_it
  while [ "$_LM_BGI" -lt "${#_LM_BG[@]}" ]; do
    builtin read -t 0 2>/dev/null && return 0          # input is waiting: the person comes first
    __lm_it="${_LM_BG[$_LM_BGI]}"; _LM_BGI=$(( _LM_BGI + 1 ))
    case "$__lm_it" in
      f:*) _lm_load "${__lm_it#f:}" ;;
      c:*) _lt_b "after paint: ${__lm_it#c:}"; ${__lm_it#c:}; _lt_e ;;
    esac
  done
  _LM_IDLE_DONE=1
  return 0
}

# everything that is left: bg and no libraries, in the order of the list (no @call)
_lm_all() {
  local __lm_ln __lm_f
  [ "${#_LM_LINES[@]}" -gt 0 ] || mapfile -t _LM_LINES <"$_LM_LIST"
  _lm_ensure_stubs
  for __lm_ln in "${_LM_LINES[@]}"; do
    case "$__lm_ln" in ''|'#'*|'@'*|'['*) continue ;; esac
    __lm_f="${__lm_ln%%[[:space:]|]*}"
    case "$__lm_f" in _3bvk_*) continue ;; *.sh) _lm_load "$__lm_f" ;; esac
  done
  return 0
}
