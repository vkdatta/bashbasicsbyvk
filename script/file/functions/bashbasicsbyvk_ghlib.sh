#!/usr/bin/env bash
# bashbasicsbyvk_ghlib.sh — the GitHub helpers that the upgrade loop (-u) and GitHub (fx → github_fx → open github) SHARE.
# ════════════════════════════════════════════════════════════════════════════
#  Before this file the upgrade loop carried its own copy of each of these; now there is one:
#
#    _GH_US                       the field separator of every list row (0x1f: never typed by a person, never in a name)
#    _gh_locate                   finds python + the engine  bashbasicsbyvk_github  ($_GH_PY, $_GH_TOOL)   rc 1 = not found
#    _gh_run <command> ...        runs the engine (rc 127 when it is not found)
#    _gh_releases_rows <file>     GitHub's release list (JSON file) → rows  tag US title US date US body      (stable only)
#    _gh_commit_row <file>        GitHub's commit (JSON file) → one row  date US author US message
#    _gh_tags_newest_first <max>  `git ls-remote --tags --refs` on stdin → tag names, newest version first
#    _gh_print_body <escaped>     prints a row's escaped body (\n → newline), 40 lines at most, indented
#
#  The parsing lives in the engine (python: bashbasicsbyvk_github parse-releases / parse-commit) so the upgrade loop
#  and the GitHub screens read releases the same way. tests/github/github_test.py proves the output is byte-for-byte
#  what the upgrade loop's own code printed before.
#  No source here (AGENTS rule 3): this file is loaded through the load mapper, before the upgrade loop.
# ════════════════════════════════════════════════════════════════════════════

_GH_US=$'\x1f'
_GH_PY=""; _GH_TOOL=""
_gh_lib_dir="${BASH_SOURCE[0]}"; case "$_gh_lib_dir" in */*) _gh_lib_dir="${_gh_lib_dir%/*}" ;; *) _gh_lib_dir=. ;; esac
_GH_LIB_DIR="$(cd -- "$_gh_lib_dir" && pwd)"; unset _gh_lib_dir

_gh_locate() {
  [ -n "$_GH_PY" ] && [ -n "$_GH_TOOL" ] && [ -f "$_GH_TOOL" ] && return 0
  _GH_PY="$(command -v python3 || command -v python)"
  [ -n "$_GH_PY" ] || return 1
  local d
  for d in "${SCRIPT_DIR:-}" "$_GH_LIB_DIR/../loops/iloop/fx/github_fx/gh"; do
    [ -n "$d" ] && [ -f "$d/bashbasicsbyvk_github" ] && { _GH_TOOL="$(cd -- "$d" && pwd)/bashbasicsbyvk_github"; return 0; }
  done
  d="$(command -v bashbasicsbyvk_github 2>/dev/null)"
  [ -n "$d" ] && { _GH_TOOL="$d"; return 0; }
  return 1
}

_gh_run() { _gh_locate || return 127; "$_GH_PY" "$_GH_TOOL" "$@"; }

_gh_releases_rows() { _gh_run parse-releases "$1"; }
_gh_commit_row()    { _gh_run parse-commit "$1"; }

# newest first: the auto-tagger bumps a SemVer tag on every build, so version order = age order
_gh_tags_newest_first() {
  sed -n 's|^[0-9a-f]\{7,64\}[[:space:]]\{1,\}refs/tags/||p' | sort -rV | head -n "$1"
}

_gh_print_body() {              # _gh_print_body <escaped-body>
  local body="$1" text lines
  [ -n "$body" ] || { echo "   (no description)"; return; }
  text="$(printf '%b' "$body")"
  lines="$(printf '%s\n' "$text" | wc -l)"
  printf '%s\n' "$text" | head -n 40 | sed 's/^/   /'
  [ "$lines" -gt 40 ] && echo "   … ($((lines-40)) more line(s))"
}
