# bashbasicsbyvk_infinity_run.sh - how the Infinity Stones tools run INSIDE the app (no tool has a process of its own that the app cannot see).
# ════════════════════════════════════════════════════════════════════════════
#  Every tool of the menu is part of the app, so the hint row, cc, typed commands (s h -h ...), u / q and every question are the app's own:
#
#   bash tools (Git Push, Python audit, Localhost)   functions of the app (bashbasicsbyvk_<tool>.sh) run through  _inf_sub
#   python tools (Extract, JS audit, SQL, Polyglot)  python does the WORK; the app asks every QUESTION through  _inf_py
#
#  _inf_sub "SET-OPTIONS" BODYFN [args]   run BODYFN in a subshell: `exit`, `die`, `set -e` and `trap EXIT` of the tool end only the tool.
#       SET-OPTIONS = the `set` flags the old stand-alone script had ("-Eeuo pipefail", "" = none).  The body starts from a trap handler:
#       bash ignores `set -e` for everything below a caller that sits in `a || b` / `if a` (the app has such callers), and a trap handler
#       is the one place that starts with a clean slate, so `set -e` keeps working exactly as it did in the old script.
#       exit 42 = q was typed below: the app closes up to the main loop (_bvk_quit).
#
#  _inf_py TOOL [args]                    run a python tool as a worker of the app.  Its questions (bashbasicsbyvk_ask / _yn / _choose in python:
#       bashbasicsbyvk_qbridge.py) arrive here through two pipes and are asked with the app's OWN _bvk_read / _bvk_yn / _bvk_menu, so a python
#       question is the same menu as every other one and nothing about it can drift.  The answer goes back with the same exit code the
#       stand-alone door used (0 answered · 1 no · 2 no answer · 4 u with -b), so the tools did not change.
# ════════════════════════════════════════════════════════════════════════════

declare -ga _INF_ARGV=()
declare -g _INF_OPTS="" _INF_RC=0 _INF_OUT=""

_inf_sub() {
  local _is_rc=0
  _sl_ready                                         # the tool talks to the person now: the "Working on ..." wait is over (smartload acts only in the main process, not in the subshell below)
  _INF_OPTS="$1"; shift
  _INF_ARGV=("$@")
  (
    trap '[ -n "$_INF_OPTS" ] && set $_INF_OPTS; "${_INF_ARGV[@]}"; exit $?' USR1
    kill -USR1 "$BASHPID"
    exit 0
  ) || _is_rc=$?
  if [ "$_is_rc" = 42 ]; then _bvk_quit; return 0; fi
  return "$_is_rc"
}

# ── the questions of a python tool, asked with the app's own menus
_inf_q_yn() {      # question [-t T] [-i I] [-c] [-b]
  local _q="$1" _b=0 _ans="" _a; shift
  local -a _f=()
  for _a in "$@"; do if [ "$_a" = -b ]; then _b=1; else _f+=("$_a"); fi; done
  _INF_OUT=""
  if _bvk_yn _ans "$_q" "${_f[@]}"; then
    case "$_ans" in y) _INF_RC=0 ;; n) _INF_RC=1 ;; *) _INF_RC=2 ;; esac
  else
    _INF_RC=2; [ "$_b" = 1 ] && _bvk_back && _INF_RC=4
  fi
}

_inf_q_choose() {  # question [-t T] [-i I] [-d key] [-k] [-m] [-b] key:Label ...
  local _q="$1" _b=0 _ans=""; shift
  local -a _f=() _r=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -b) _b=1; shift ;;
      -t|-i|-d) _f+=("$1" "${2-}"); shift $(( $# >= 2 ? 2 : 1 )) ;;
      -k|-m) _f+=("$1"); shift ;;
      *) _r+=("$1"); shift ;;
    esac
  done
  _INF_OUT=""
  if _bvk_menu _ans -q "$_q" "${_f[@]}" -- "${_r[@]}"; then
    _INF_RC=0; _INF_OUT="$_ans"
  else
    _INF_RC=2; [ "$_b" = 1 ] && _bvk_back && _INF_RC=4
  fi
}

_inf_q_ask() {     # "Prompt: " [-i text] [-s] [-b] [-S] [-m]
  local _p="$1" _i="" _s=0 _b=0 _CE_SELECT=0 _m=0 _ans=""; shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -i) _i="${2-}"; shift $(( $# >= 2 ? 2 : 1 )) ;;
      -s) _s=1; shift ;;
      -b) _b=1; shift ;;
      -S) _CE_SELECT=1; shift ;;
      -m) _m=1; shift ;;
      *) shift ;;
    esac
  done
  local -a _f=()
  [ -n "$_i" ] && _f+=(-i "$_i")
  (( _s )) && _f+=(-s)
  (( _m )) && _f+=(-m)
  (( _s )) || _cm_prompt_has_choices "$_p" || _mc_footer_std -b      # the footer every typed-line prompt prints (a prompt that lists its own answers gets none)
  _CM_BACKED=0; _INF_OUT=""
  if _bvk_read _ans "$_p" "${_f[@]}"; then
    _INF_RC=0; _INF_OUT="$_ans"
  else
    _INF_RC=2; [ "$_b" = 1 ] && [ "${_CM_BACKED:-0}" = 1 ] && _INF_RC=4
  fi
}

# one request from the python tool (fd 8) -> one answer (fd 9).  A request = N, then N arguments, each ended by a NUL; the answer = RC NUL TEXT NUL.
_inf_serve_one() {
  local _n="" _a="" _i
  local -a _av=()
  IFS= read -r -d '' -t 0.3 -u 8 _n || return 1      # bvk-read-ok: the pipe of a python tool (fd 8), not the terminal
  for (( _i = 0; _i < _n; _i++ )); do IFS= read -r -d '' -u 8 _a || break; _av+=("$_a"); done      # bvk-read-ok: the pipe of a python tool (fd 8), not the terminal
  _INF_RC=3; _INF_OUT=""
  case "${_av[0]:-}" in
    yn)     _inf_q_yn "${_av[@]:1}" ;;
    choose) _inf_q_choose "${_av[@]:1}" ;;
    ask)    _inf_q_ask "${_av[@]:1}" ;;
  esac
  printf '%s\0%s\0' "$_INF_RC" "$_INF_OUT" >&9
  return 0
}

_inf_py() {
  local _tool="$1" _d _pid _rc=0 _mon="$-"
  shift
  _sl_ready                                         # the tool talks to the person now: the "Working on ..." wait is over
  [ -r "$_tool" ] || { echo "Tool not found: $_tool"; return 1; }
  command -v python3 >/dev/null 2>&1 || _dep_need -c "Infinity Stones" python3 || return 1
  _d="$(mktemp -d "${TMPDIR:-/tmp}/bvk-inf.XXXXXX")" || return 1
  mkfifo "$_d/req" "$_d/rsp" || { rm -rf "$_d"; return 1; }
  exec 8<>"$_d/req" 9<>"$_d/rsp"
  set +m                                            # no job control: the worker stays in the app's process group (the terminal, Ctrl-C)
  BVK_QBRIDGE="$_d" python3 -c 'import os, runpy, signal, sys
signal.signal(signal.SIGINT, signal.default_int_handler)      # a background job of a script starts with SIGINT ignored
t = sys.argv[1]; sys.argv = sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(t)))
runpy.run_path(t, run_name="__main__")' "$_tool" "$@" &
  _pid=$!
  [[ "$_mon" == *m* ]] && set -m
  while kill -0 "$_pid" 2>/dev/null; do _inf_serve_one; done
  wait "$_pid" || _rc=$?
  exec 8>&- 9>&-
  rm -rf "$_d"
  return "$_rc"
}
