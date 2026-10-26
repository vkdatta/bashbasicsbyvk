#!/usr/bin/env bash
# bashbasicsbyvk_deps.sh - THE just-in-time dependency installer (AGENTS.md rule 12).
# ════════════════════════════════════════════════════════════════════════════
#  Instead of "7z not found, please install it with: pkg install 7zip" and exit, a feature asks THIS engine for what it needs.
#  If something is missing the person gets the Installer menu:
#
#     📦 Installer
#
#     "Make a .7z" needs these external dependencies, which are not installed:
#        1) 7-Zip   makes and opens .7z archives
#                   install: pkg install 7zip
#     Do you want to install them?      yes / no
#
#  yes -> everything is installed in ONE go (see "Parallel" below), re-checked, and the caller carries on;  no -> rc 1, caller backs out.
#
#  WHAT it needs, HOW to detect it and HOW to install it on each package manager lives in ONE data file: bashbasicsbyvk_deps.list
#  (the central registry and the menu -> dependency map).  This file only reads it.  A new external dependency = one line there.
#
#  Two ways to use it (same file):
#     source "bashbasicsbyvk_deps.sh"            (the app: `o` loads it through _3bvk_import_engine.sh; import files of stand-alone tools)
#         _dep_need  [opts] <id|feature>...      rc 0 everything required is there (maybe after installing) · 1 declined / failed / no terminal
#         _dep_have  <id|feature>...             rc 0 when all required are installed; silent, never installs; _DEP_MISSING lists what is not
#     bashbasicsbyvk_deps.sh [opts] <id|feature>...   (stand-alone tools, python: bashbasicsbyvk_deps.py)   same, as an exit code
#
#  Options:   -c TEXT  what the person was doing (menu heading)      -o  also ask for the feature's OPTIONAL dependencies
#             -y       assume yes (no menu)                          -n  only check, never install (prints the list + the commands)
#             -q       no menu, no output: installs ONLY the `auto` user-space pip packages (the recents daemon), at most once a day each
#             --dry-run  print the commands, run nothing            --check  status of everything in the registry   --list  the map
#  Ids:       a dependency id (7z, numpy), a feature (archive.create.7z, polyglot), `?id` = optional, a pip family member (tree_sitter_python)
#  Env:       BVK_DEPS_ASSUME=yes|no  answers the menu (scripts, CI)      BVK_DEPS_MANAGER=apt|termux|...  forces the package manager
#             BVK_DEPS_JOBS=N  parallel installs (default: CPUs, max 4)   BVK_DEPS_REGISTRY=file  another registry (tests)
#             BVK_DEPS_LOG=file  install log (default ~/.bashbasicsbyvk/deps_install.log)
#
#  Parallel
#     * detection: the pip modules are probed by ONE python process running at the same time as the program probes;
#     * installation: system packages (one package-manager call: those managers hold a lock, and sudo needs the terminal) run in the foreground
#       while the pip lane and the npm lane run at the same time in the background, as soon as their own prerequisites (python / node) exist;
#       if a pip batch fails, its packages are retried one by one, several at a time.
#  The menu is ALWAYS `_bvk_yn` (same look, arrows, touch, u/q): in the app it is already loaded; run on its own, the engine loads it through
#  its own import file (_3bvk_import_deps.sh). Only if that cannot be loaded (broken install) it falls back to one plain yes/no line.
#  The list and progress go to STDERR, so a caller may capture stdout; do not call _dep_need inside $( ) (the menu needs the terminal).
# ════════════════════════════════════════════════════════════════════════════

declare -gA _DEP_KIND=() _DEP_PROBE=() _DEP_PKGS=() _DEP_LABEL=() _DEP_WHYTXT=() _DEP_NEEDS=() _DEP_FLAGS=() _DEP_NOTE=()
declare -gA _DEP_FTITLE=() _DEP_FREQ=() _DEP_FOPT=()
declare -ga _DEP_GROUPS=() _DEP_ORDER=() _DEP_TITLES=()
declare -gA _DEP_SEEN=() _DEP_REQ=() _PL_HOW=()
declare -gA _DEP_ST=()          # id -> 1 installed / 0 missing  (this process' last look; a positive answer is kept for the whole run)
_DEP_LOADED=0
_DEP_MGR="${_DEP_MGR:-}"
_DEP_MISSING=""

# ── small helpers ────────────────────────────────────────────────────────────
_dep_say() { printf '%s\n' "$*" >&2; }

_dep_log() {
  local f="${BVK_DEPS_LOG:-$HOME/.bashbasicsbyvk/deps_install.log}"
  mkdir -p "${f%/*}" 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$f" 2>/dev/null
  return 0
}

# user-space installs (pip --user, npm --prefix ~/.local) put programs in ~/.local/bin
_dep_path_fix() {
  [ -d "$HOME/.local/bin" ] || return 0
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$PATH:$HOME/.local/bin" ;; esac
  return 0
}

_dep_jobs() {
  local n="${BVK_DEPS_JOBS:-}"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || { n=$(nproc 2>/dev/null || echo 2); (( n > 4 )) && n=4; (( n < 1 )) && n=1; }
  printf '%s' "$n"
}

# _dep_path id -> prints the path of the first of the dependency's commands that exists (kind cmd / npm); rc 1 = none
_dep_path() {
  local p IFS=,
  _dep_load || return 1
  _dep_resolve "$1" || return 1
  for p in ${_DEP_PROBE[$1]}; do command -v "$p" 2>/dev/null && return 0; done
  return 1
}

# the package manager of this machine -> _DEP_MGR  (termux apt dnf yum pacman apk zypper brew, or empty)
_dep_mgr() {
  [ -n "${BVK_DEPS_MANAGER:-}" ] && { _DEP_MGR="$BVK_DEPS_MANAGER"; return 0; }
  [ -n "$_DEP_MGR" ] && return 0
  if [[ "${PREFIX:-}" == *com.termux* ]] && command -v pkg >/dev/null 2>&1; then _DEP_MGR=termux
  elif [ "$(uname -s 2>/dev/null)" = Darwin ] && command -v brew >/dev/null 2>&1; then _DEP_MGR=brew
  elif command -v apt-get >/dev/null 2>&1; then _DEP_MGR=apt
  elif command -v dnf >/dev/null 2>&1;     then _DEP_MGR=dnf
  elif command -v yum >/dev/null 2>&1;     then _DEP_MGR=yum
  elif command -v pacman >/dev/null 2>&1;  then _DEP_MGR=pacman
  elif command -v apk >/dev/null 2>&1;     then _DEP_MGR=apk
  elif command -v zypper >/dev/null 2>&1;  then _DEP_MGR=zypper
  elif command -v brew >/dev/null 2>&1;    then _DEP_MGR=brew
  else _DEP_MGR=""; fi
  return 0
}

# _DEP_PRIV = (sudo) when the manager needs root and we are not root; rc 1 = needs root and there is no way to get it
_dep_priv() {
  _DEP_PRIV=()
  case "$_DEP_MGR" in termux|brew|"") return 0 ;; esac
  [ "$(id -u 2>/dev/null)" = 0 ] && return 0
  if command -v sudo >/dev/null 2>&1; then _DEP_PRIV=(sudo); return 0; fi
  return 1
}

# _DEP_CMD = the install command of the manager (without sudo, without packages); _DEP_UPD = how to refresh its package lists (may be empty)
_dep_cmds() {
  _DEP_UPD=()
  case "$_DEP_MGR" in
    termux) _DEP_CMD=(pkg install -y);                _DEP_UPD=(pkg update -y) ;;
    apt)    _DEP_CMD=(apt-get install -y);            _DEP_UPD=(apt-get update) ;;
    dnf)    _DEP_CMD=(dnf install -y) ;;
    yum)    _DEP_CMD=(yum install -y) ;;
    pacman) _DEP_CMD=(pacman -S --noconfirm --needed); _DEP_UPD=(pacman -Sy) ;;
    apk)    _DEP_CMD=(apk add);                        _DEP_UPD=(apk update) ;;
    zypper) _DEP_CMD=(zypper --non-interactive install); _DEP_UPD=(zypper --non-interactive refresh) ;;
    brew)   _DEP_CMD=(brew install) ;;
    *)      _DEP_CMD=() ;;
  esac
}

# does the manager know package $1?  (only asked when a registry line offers alternatives)
_dep_pkg_known() {
  case "$_DEP_MGR" in
    apt|termux) apt-cache show "$1" >/dev/null 2>&1 ;;
    dnf|yum)    "$_DEP_MGR" info "$1" >/dev/null 2>&1 ;;
    pacman)     pacman -Si "$1" >/dev/null 2>&1 ;;
    apk)        [ -n "$(apk search -e "$1" 2>/dev/null)" ] ;;
    zypper)     zypper --non-interactive info "$1" >/dev/null 2>&1 ;;
    brew)       brew info "$1" >/dev/null 2>&1 ;;
    *)          return 1 ;;
  esac
}

# ── the registry ─────────────────────────────────────────────────────────────
_dep_registry() {
  local d
  if [ -n "${BVK_DEPS_REGISTRY:-}" ]; then [ -r "$BVK_DEPS_REGISTRY" ] && { printf '%s' "$BVK_DEPS_REGISTRY"; return 0; }; return 1; fi
  d="${BASH_SOURCE[0]}"; case "$d" in */*) d="${d%/*}" ;; *) d=. ;; esac
  [ -r "$d/bashbasicsbyvk_deps.list" ] && { printf '%s' "$d/bashbasicsbyvk_deps.list"; return 0; }
  d=$(command -v bashbasicsbyvk_deps.list 2>/dev/null) && [ -r "$d" ] && { printf '%s' "$d"; return 0; }
  return 1
}

_dep_load() {
  local reg t id a b c d e f g h
  [ "$_DEP_LOADED" = 1 ] && return 0
  if ! reg=$(_dep_registry); then
    _dep_say "❌ The dependency registry (bashbasicsbyvk_deps.list) was not found next to bashbasicsbyvk_deps.sh - reinstall bashbasicsbyvk."
    return 1
  fi
  while IFS='|' read -r t id a b c d e f g h; do
    case "$t" in
      D) _DEP_KIND[$id]="$a"; _DEP_PROBE[$id]="$b"; _DEP_PKGS[$id]="$c"; _DEP_LABEL[$id]="$d"; _DEP_WHYTXT[$id]="$e"
         _DEP_NEEDS[$id]="$f"; _DEP_FLAGS[$id]="$g"; _DEP_NOTE[$id]="$h" ;;
      G) _DEP_GROUPS+=("$id|$a|$b|$c|$d|$e") ;;
      F) _DEP_FTITLE[$id]="$a"; _DEP_FREQ[$id]="$b"; _DEP_FOPT[$id]="$c" ;;
    esac
  done < "$reg"
  _DEP_LOADED=1
  _dep_path_fix
  return 0
}

# a member of a pip family (tree_sitter_python) gets its entry made up from the G line
_dep_resolve() {
  local id="$1" g pre pp ver needs label why rest
  [ -n "${_DEP_KIND[$id]+x}" ] && return 0
  for g in "${_DEP_GROUPS[@]}"; do
    IFS='|' read -r pre pp ver needs label why <<<"$g"
    if [[ "$id" == "$pre"* && ${#id} -gt ${#pre} ]]; then
      rest="${id#"$pre"}"
      _DEP_KIND[$id]=pip; _DEP_PROBE[$id]="$id"; _DEP_PKGS[$id]="pip=${pp}${rest//_/-}${ver}"
      _DEP_LABEL[$id]="$label ($rest)"; _DEP_WHYTXT[$id]="$why"; _DEP_NEEDS[$id]="$needs"; _DEP_FLAGS[$id]=""; _DEP_NOTE[$id]=""
      return 0
    fi
  done
  return 1
}

# ── detection ────────────────────────────────────────────────────────────────
# the pip modules of the arguments (module[:dist:min]) -> "module ok|no" lines; ONE python process
_dep_pip_probe_py() {
  python3 - "$@" <<'PY'
import sys, importlib, importlib.util
try:
    import site
    site.addsitedir(site.getusersitepackages())
except Exception:
    pass
importlib.invalidate_caches()
def vt(text):
    out = []
    for part in text.split("."):
        digits = "".join(c for c in part if c.isdigit())
        if not digits:
            break
        out.append(int(digits))
    return tuple(out)
for spec in sys.argv[1:]:
    mod, _, rest = spec.partition(":")
    dist, _, minv = rest.partition(":")
    ok = False
    try:
        ok = importlib.util.find_spec(mod) is not None
    except Exception:
        ok = False
    if ok and dist and minv:
        try:
            from importlib import metadata
            ok = vt(metadata.version(dist)) >= vt(minv)
        except Exception:
            ok = False
    print(mod, "ok" if ok else "no")
PY
}

# one id, no cache: rc 0 installed
_dep_probe_one() {
  local id="$1" kind="${_DEP_KIND[$1]}" probe="${_DEP_PROBE[$1]}" p
  case "$kind" in
    cmd|npm) local IFS=,; for p in $probe; do command -v "$p" >/dev/null 2>&1 && return 0; done; return 1 ;;
    file)    local IFS=,; for p in $probe; do p="${p//\$PREFIX/${PREFIX:-/nonexistent}}"; p="${p//\$TZDIR/${TZDIR:-/nonexistent}}"; [ -e "$p" ] && return 0; done; return 1 ;;
    pymod)   command -v python3 >/dev/null 2>&1 && python3 -c 'import importlib.util,sys; sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)' "$probe" 2>/dev/null ;;
    pip)     command -v python3 >/dev/null 2>&1 && [ "$(_dep_pip_probe_py "$probe" 2>/dev/null)" = "${probe%%:*} ok" ] ;;
    *)       return 1 ;;
  esac
}

# probe ids ($@, already registered) at once -> _DEP_ST.  Positives found earlier are kept.
_dep_probe_all() {
  local id pf="" pids=() out="" mods=() ids=() line
  for id in "$@"; do
    [ "${_DEP_ST[$id]:-0}" = 1 ] && continue
    if [ "${_DEP_KIND[$id]}" = pip ]; then ids+=("$id"); mods+=("${_DEP_PROBE[$id]}"); fi
  done
  if [ "${#mods[@]}" -gt 0 ]; then
    if command -v python3 >/dev/null 2>&1; then
      pf=$(mktemp "${TMPDIR:-/tmp}/bvkdep.XXXXXX") && { _dep_pip_probe_py "${mods[@]}" > "$pf" 2>/dev/null & } 2>/dev/null   # runs while the programs below are probed
      pids+=($!)
    fi
  fi
  for id in "$@"; do
    [ "${_DEP_ST[$id]:-0}" = 1 ] && continue
    [ "${_DEP_KIND[$id]}" = pip ] && continue
    if _dep_probe_one "$id"; then _DEP_ST[$id]=1; else _DEP_ST[$id]=0; fi
  done
  [ "${#pids[@]}" -gt 0 ] && wait "${pids[@]}" 2>/dev/null          # only OUR probe: never every background job of the app
  for id in "${ids[@]}"; do _DEP_ST[$id]=0; done
  if [ -n "$pf" ]; then
    while read -r line; do
      for id in "${ids[@]}"; do
        [ "${_DEP_PROBE[$id]%%:*} ok" = "$line" ] && _DEP_ST[$id]=1
      done
    done < "$pf"
    rm -f "$pf"
  fi
  return 0
}

# ── turning the arguments into a dependency list ─────────────────────────────
# _dep_add id required(1|0): the id, then what it needs first (dependency-first order in _DEP_ORDER)
_dep_add() {
  local id="$1" req="$2" n
  _dep_resolve "$id" || { _dep_say "❌ Unknown dependency '$id' (not in bashbasicsbyvk_deps.list)."; return 1; }
  if [ -n "${_DEP_SEEN[$id]+x}" ]; then [ "$req" = 1 ] && _DEP_REQ[$id]=1; return 0; fi
  _DEP_SEEN[$id]=1; _DEP_REQ[$id]=$req
  for n in ${_DEP_NEEDS[$id]}; do _dep_add "$n" "$req" || return 1; done
  _DEP_ORDER+=("$id")
  return 0
}

# a token of a feature: id, or a/b = either is enough
_dep_add_token() {
  local tok="$1" req="$2" alt a
  if [[ "$tok" == */* ]]; then
    IFS='/' read -ra alt <<<"$tok"
    for a in "${alt[@]}"; do
      _dep_resolve "$a" || { _dep_say "❌ Unknown dependency '$a' (not in bashbasicsbyvk_deps.list)."; return 1; }
      if [ "${_DEP_ST[$a]:-}" = 1 ] || _dep_probe_one "$a"; then _DEP_ST[$a]=1; return 0; fi
    done
    _dep_add "${alt[0]}" "$req"; return $?
  fi
  _dep_add "$tok" "$req"
}

# _dep_expand [-o] arg... -> _DEP_ORDER / _DEP_REQ ; rc 2 for an unknown name
_dep_expand() {
  local withopt=0 a opt t
  [ "${1:-}" = -o ] && { withopt=1; shift; }
  _DEP_ORDER=(); _DEP_SEEN=(); _DEP_REQ=()
  _DEP_TITLES=()
  for a in "$@"; do
    opt=0; [[ "$a" == \?* ]] && { opt=1; a="${a#\?}"; }
    if [ -n "${_DEP_FREQ[$a]+x}" ] || [ -n "${_DEP_FOPT[$a]+x}" ]; then
      _DEP_TITLES+=("${_DEP_FTITLE[$a]}")
      for t in ${_DEP_FREQ[$a]}; do _dep_add_token "$t" $(( opt ? 0 : 1 )) || return 2; done
      if [ "$withopt" = 1 ] || [ "$opt" = 1 ]; then for t in ${_DEP_FOPT[$a]}; do _dep_add_token "$t" 0 || return 2; done; fi
    else
      _dep_add_token "$a" $(( opt ? 0 : 1 )) || return 2
    fi
  done
  return 0
}

# ── the install plan ─────────────────────────────────────────────────────────
# _dep_pkgkey id key -> _DEP_VAL ; rc 1 when the registry has no value for that key
_dep_pkgkey() {
  local ent
  local -a parts=()
  IFS=';' read -ra parts <<<"${_DEP_PKGS[$1]}"
  for ent in "${parts[@]}"; do
    [ "${ent%%=*}" = "$2" ] && [ -n "${ent#*=}" ] && { _DEP_VAL="${ent#*=}"; return 0; }
  done
  _DEP_VAL=""; return 1
}

# _dep_pkgval id -> _DEP_VAL (the registry value for this manager); rc 1 = not installable on this platform
_dep_pkgval() {
  case "${_DEP_KIND[$1]}" in
    pip) if [ -n "$_DEP_MGR" ] && _dep_pkgkey "$1" "$_DEP_MGR" && [[ "$_DEP_VAL" == sys:* ]]; then return 0; fi
         _dep_pkgkey "$1" pip ;;
    npm) _dep_pkgkey "$1" npm ;;
    *)   [ -n "$_DEP_MGR" ] && { _dep_pkgkey "$1" "$_DEP_MGR" || _dep_pkgkey "$1" '*'; } ;;
  esac
}

# pick one of `a,b` : the first the manager knows (or the first)
_dep_choose_pkg() {
  local cand="$1" c first=""
  local -a list=()
  IFS=',' read -ra list <<<"$cand"
  first="${list[0]}"
  [ "${#list[@]}" -gt 1 ] && for c in "${list[@]}"; do _dep_pkg_known "$c" && { printf '%s' "$c"; return 0; }; done
  printf '%s' "$first"
}

_dep_plan_sys() {   # _dep_plan_sys candidates id
  local pkg p
  pkg=$(_dep_choose_pkg "$1")
  for p in "${_PL_SYS[@]}"; do [ "$p" = "$pkg" ] && pkg=""; done
  [ -n "$pkg" ] && _PL_SYS+=("$pkg")
  [ -n "${2:-}" ] && _PL_HOW[$2]="${_DEP_PRIV[*]:+${_DEP_PRIV[*]} }${_DEP_CMD[*]} $(_dep_choose_pkg "$1")"
  return 0
}

# _dep_plan id...  (the missing ones, dependency-first) -> _PL_SYS _PL_RECIPE _PL_PIP _PL_NPM _PL_NA _PL_HOW[id]
_dep_plan() {
  local id v r name pre p kind
  _PL_SYS=(); _PL_RECIPE=(); _PL_PIP=(); _PL_NPM=(); _PL_NA=(); _PL_EXTRA=(); _PL_HOW=()
  _dep_mgr; _dep_priv; _DEP_PRIV_OK=$?; _dep_cmds
  for id in "$@"; do
    kind="${_DEP_KIND[$id]}"
    if ! _dep_pkgval "$id"; then _PL_NA+=("$id"); _PL_HOW[$id]="no automatic install on this system"; continue; fi
    v="$_DEP_VAL"
    case "$kind" in
      pip) if [[ "$v" == sys:* ]]; then _dep_plan_sys "${v#sys:}" "$id"; else _PL_PIP+=("$v"); _PL_HOW[$id]="python3 -m pip install $v"; fi ;;
      npm) _PL_NPM+=("$v"); _PL_HOW[$id]="npm install -g $v" ;;
      *)   if [[ "$v" == @* ]]; then
             r="${v#@}"; name="${r%%+*}"; pre=""; [[ "$r" == *+* ]] && pre="${r#*+}"
             _PL_RECIPE+=("$name"); _PL_HOW[$id]="$(_dep_recipe_text "$name")"
             for p in ${pre//+/ }; do
               _dep_resolve "$p" && [ "${_DEP_ST[$p]:-0}" != 1 ] && ! _dep_probe_one "$p" && _dep_pkgval "$p" && { _dep_plan_sys "$_DEP_VAL" ""; _PL_EXTRA+=("${_DEP_LABEL[$p]}"); }
             done
           else _dep_plan_sys "$v" "$id"; fi ;;
    esac
  done
  return 0
}

# ── recipes: installs that are more than "package manager + name" ─────────────
_dep_recipe_text() {
  case "$1" in
    gh-apt) printf '%s' "adds GitHub's official apt repository (cli.github.com) to this computer, then installs gh" ;;
    gh-dnf) printf '%s' "adds GitHub's official rpm repository (cli.github.com) to this computer, then installs gh" ;;
    *)      printf '%s' "install recipe $1" ;;
  esac
}

_dep_recipe_gh_apt() {
  local arch key=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  arch=$(dpkg --print-architecture 2>/dev/null) || arch=amd64
  command -v curl >/dev/null 2>&1 || { echo "curl is required to fetch GitHub's signing key"; return 1; }
  _dep_run "${_DEP_PRIV[@]}" mkdir -p -m 755 /etc/apt/keyrings || return 1
  if [ "${BVK_DEPS_DRYRUN:-0}" = 1 ]; then _dep_say "   would: fetch the GitHub CLI signing key, add /etc/apt/sources.list.d/github-cli.list, apt-get update, apt-get install -y gh"; return 0; fi
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | "${_DEP_PRIV[@]}" tee "$key" >/dev/null || { echo "could not download GitHub's signing key"; return 1; }
  "${_DEP_PRIV[@]}" chmod go+r "$key" || return 1
  echo "deb [arch=$arch signed-by=$key] https://cli.github.com/packages stable main" | "${_DEP_PRIV[@]}" tee /etc/apt/sources.list.d/github-cli.list >/dev/null || return 1
  _dep_run "${_DEP_PRIV[@]}" apt-get update || return 1
  _dep_run "${_DEP_PRIV[@]}" apt-get install -y gh
}

_dep_recipe_gh_dnf() {
  _dep_run "${_DEP_PRIV[@]}" "$_DEP_MGR" install -y 'dnf-command(config-manager)' || return 1
  _dep_run "${_DEP_PRIV[@]}" "$_DEP_MGR" config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo || return 1
  _dep_run "${_DEP_PRIV[@]}" "$_DEP_MGR" install -y gh
}

# ── running things ───────────────────────────────────────────────────────────
_dep_run() {
  _dep_log "run: $*"
  if [ "${BVK_DEPS_DRYRUN:-0}" = 1 ]; then _dep_say "   would run: $*"; return 0; fi
  "$@"; local rc=$?
  _dep_log "rc=$rc: $*"
  return $rc
}

_dep_lane_sys() {          # system packages, then recipes (foreground: sudo may ask for a password)
  local rc=0 r
  if [ "${#_PL_SYS[@]}" -gt 0 ]; then
    _dep_say "   ▶ ${_DEP_PRIV[*]:+${_DEP_PRIV[*]} }${_DEP_CMD[*]} ${_PL_SYS[*]}"
    _dep_run "${_DEP_PRIV[@]}" "${_DEP_CMD[@]}" "${_PL_SYS[@]}"; rc=$?
    if [ $rc -ne 0 ] && [ "${#_DEP_UPD[@]}" -gt 0 ]; then       # stale package lists are the usual reason: refresh once, retry once
      _dep_say "   ↻ refreshing the package lists, then trying again"
      _dep_run "${_DEP_PRIV[@]}" "${_DEP_UPD[@]}" && _dep_run "${_DEP_PRIV[@]}" "${_DEP_CMD[@]}" "${_PL_SYS[@]}"
    fi
  fi
  for r in "${_PL_RECIPE[@]}"; do
    _dep_say "   ▶ $(_dep_recipe_text "$r")"
    case "$r" in
      gh-apt) _dep_recipe_gh_apt ;;
      gh-dnf) _dep_recipe_gh_dnf ;;
    esac
  done
  return 0
}

# one pip package, trying the flags that work on a normal / PEP 668 / venv Python
_dep_pip_one() {
  local spec="$1" f
  local -a tries=()
  if [ "$(python3 -c 'import sys; print(int(sys.prefix != sys.base_prefix))' 2>/dev/null)" = 1 ]; then tries=("")
  else tries=("--user" "--user --break-system-packages"); fi
  for f in "${tries[@]}"; do
    # shellcheck disable=SC2086
    _dep_run python3 -m pip install --no-input --disable-pip-version-check $f "$spec" && return 0
  done
  return 1
}

_dep_lane_pip() {          # all at once; when the batch fails, one by one, several at a time
  local f s n=0 jobs; jobs=$(_dep_jobs)
  local -a tries=()
  if [ "$(python3 -c 'import sys; print(int(sys.prefix != sys.base_prefix))' 2>/dev/null)" = 1 ]; then tries=("")
  else tries=("--user" "--user --break-system-packages"); fi
  for f in "${tries[@]}"; do
    # shellcheck disable=SC2086
    _dep_run python3 -m pip install --no-input --disable-pip-version-check $f "${_PL_PIP[@]}" && return 0
  done
  [ "${#_PL_PIP[@]}" -gt 1 ] || return 1
  echo "pip batch failed: retrying each package on its own"
  for s in "${_PL_PIP[@]}"; do
    _dep_pip_one "$s" &
    n=$(( n + 1 )); (( n >= jobs )) && { wait -n 2>/dev/null; n=$(( n - 1 )); }
  done
  wait
  return 0
}

_dep_lane_npm() {
  local s prefix_dir
  prefix_dir=$(npm config get prefix 2>/dev/null)
  for s in "${_PL_NPM[@]}"; do
    if [ -n "$prefix_dir" ] && [ -w "$prefix_dir" ]; then _dep_run npm install -g "$s"
    else _dep_run npm install -g --prefix "$HOME/.local" "$s"; fi
  done
}

# ── asking ───────────────────────────────────────────────────────────────────
# _dep_show title ids...  : the Installer text (stderr)
_dep_show() {
  local title="$1" id n=0 how mark
  shift
  _dep_say ""
  _dep_say "📦 Installer"
  _dep_say ""
  _dep_say "  ${title:+$title }requires the following external dependencies, which are not installed:"
  _dep_say ""
  for id in "$@"; do
    n=$(( n + 1 )); mark=""; [ "${_DEP_REQ[$id]:-1}" = 0 ] && mark="  (optional)"
    how="${_PL_HOW[$id]:-}"
    _dep_say "   $n) ${_DEP_LABEL[$id]}${mark}"
    _dep_say "        what for: ${_DEP_WHYTXT[$id]}"
    [ -n "$how" ] && _dep_say "        install : $how"
    [ -n "${_DEP_NOTE[$id]}" ] && _dep_say "        note    : ${_DEP_NOTE[$id]}"
  done
  _dep_say ""
  if [ "${#_PL_SYS[@]}${#_PL_PIP[@]}${#_PL_NPM[@]}" != "000" ]; then
    [ "${#_PL_EXTRA[@]}" -gt 0 ] && _dep_say "  Also installed first (needed by the steps above): ${_PL_EXTRA[*]}"
    _dep_say "  System packages are installed together; Python and npm packages are installed at the same time."
    _dep_say ""
  fi
}

# "no" to an optional dependency is remembered for a week (BVK_DEPS_NAG_DAYS)
_dep_statedir() { printf '%s' "${BVK_DEPS_STATE:-$HOME/.bashbasicsbyvk/deps}"; }
_dep_decline() { local d; d=$(_dep_statedir); mkdir -p "$d" 2>/dev/null && : > "$d/$1.declined" 2>/dev/null; return 0; }
_dep_declined() {
  local f; f="$(_dep_statedir)/$1.declined"
  [ -f "$f" ] || return 1
  [ $(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) )) -lt $(( ${BVK_DEPS_NAG_DAYS:-7} * 86400 )) ]
}

# the answer: rc 0 = install
_dep_ask() {
  local ans=""
  _DEP_NOASK=0
  case "${BVK_DEPS_ASSUME:-}" in
    y|yes|Y|YES|Yes) _dep_say "  (BVK_DEPS_ASSUME=yes: installing)"; return 0 ;;
    n|no|N|NO|No)    _DEP_NOASK=1; return 1 ;;
  esac
  if [ ! -t 0 ] && [ "${_DEP_CLI:-0}" = 1 ] && ! { : </dev/tty; } 2>/dev/null; then    # a tool run on its own with nobody to ask
    _DEP_NOASK=1
    _dep_say "  No terminal to ask on, nothing was installed."
    _dep_say "  Install them with the commands above, or run again with:  BVK_DEPS_ASSUME=yes  (or the -y option)."
    return 1
  fi
  if declare -F _bvk_yn >/dev/null 2>&1; then          # the shared choice menu: in the app, and in a tool run on its own (its import file loads it)
    if [ ! -t 0 ] && [ "${_DEP_CLI:-0}" = 1 ]; then   # stdin is the tool's data (cat file | tool): ask on the terminal, never on the data
      _bvk_yn ans "Do you want to install them?" -t "Installer" -i "📦" </dev/tty || return 1
    else
      _bvk_yn ans "Do you want to install them?" -t "Installer" -i "📦" || return 1
    fi
    [ "$ans" = y ]; return $?
  fi
  while :; do
    read -r -p "Do you want to install them? [yes/no]: " ans </dev/tty || return 1
    case "${ans,,}" in y|yes) return 0 ;; n|no) return 1 ;; esac
  done
}

# ── the public calls ─────────────────────────────────────────────────────────
# _dep_have id|feature... : rc 0 when everything REQUIRED is installed.  Never installs, never prints.  _DEP_MISSING = what is not.
_dep_have() {
  local id withopt=() ; [ "${1:-}" = -o ] && { withopt=(-o); shift; }
  _DEP_MISSING=""
  _dep_load || return 2
  _dep_expand "${withopt[@]}" "$@" || return 2
  _dep_probe_all "${_DEP_ORDER[@]}"
  for id in "${_DEP_ORDER[@]}"; do
    [ "${_DEP_ST[$id]:-0}" = 1 ] && continue
    [ "${_DEP_REQ[$id]:-1}" = 1 ] && _DEP_MISSING+="${_DEP_MISSING:+ }$id"
  done
  [ -z "$_DEP_MISSING" ]
}

_dep_need() {
  local ctx="" withopt=() assume="" check=0 quiet=0 id
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -c) ctx="$2"; shift 2 ;;
      -o) withopt=(-o); shift ;;
      -y) assume=yes; shift ;;
      -n) check=1; shift ;;
      -q) quiet=1; shift ;;
      --dry-run) BVK_DEPS_DRYRUN=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  [ "$#" -gt 0 ] || { _dep_say "usage: _dep_need [-c text] [-o] [-y] [-n] [-q] <id|feature>..."; return 2; }
  _dep_load || return 2
  _dep_expand "${withopt[@]}" "$@"; local erc=$?
  [ $erc -ne 0 ] && return 2
  _dep_probe_all "${_DEP_ORDER[@]}"
  local -a miss=() reqmiss=()
  for id in "${_DEP_ORDER[@]}"; do
    [ "${_DEP_ST[$id]:-0}" = 1 ] && continue
    miss+=("$id"); [ "${_DEP_REQ[$id]:-1}" = 1 ] && reqmiss+=("$id")
  done
  _DEP_MISSING="${reqmiss[*]}"
  [ "${#miss[@]}" -eq 0 ] && return 0                               # fast path: everything is there
  # an OPTIONAL one the person already said no to is not offered again for a week
  if [ "$quiet" != 1 ] && [ "$check" != 1 ]; then
    local -a keep=()
    for id in "${miss[@]}"; do
      if [ "${_DEP_REQ[$id]:-1}" = 0 ] && _dep_declined "$id"; then continue; fi
      keep+=("$id")
    done
    miss=("${keep[@]}")
    [ "${#miss[@]}" -eq 0 ] && return 0
  fi

  if [ "$quiet" = 1 ]; then _dep_quiet "${miss[@]}"; return $?; fi

  _dep_plan "${miss[@]}"
  local reqrc=0; [ "${#reqmiss[@]}" -gt 0 ] && reqrc=1            # what the caller gets when nothing is installed: only a missing REQUIRED one is a failure
  local -a todo=() na_req=()
  for id in "${miss[@]}"; do
    local isna=0 p
    for p in "${_PL_NA[@]}"; do [ "$p" = "$id" ] && isna=1; done
    if [ $isna = 1 ]; then [ "${_DEP_REQ[$id]:-1}" = 1 ] && na_req+=("$id"); continue; fi
    todo+=("$id")
  done

  local title="$ctx"
  [ -z "$title" ] && [ "${#_DEP_TITLES[@]}" -eq 1 ] && title="${_DEP_TITLES[0]}"
  [ -n "$title" ] && title="\"$title\""
  _dep_show "$title" "${miss[@]}"
  for id in "${na_req[@]}"; do _dep_say "  ⚠ ${_DEP_LABEL[$id]}: ${_PL_HOW[$id]} - install it yourself, then try again."; done
  [ "${#na_req[@]}" -gt 0 ] && [ "${#todo[@]}" -eq 0 ] && return 1
  [ "$check" = 1 ] && return $reqrc
  if [ "${_DEP_PRIV_OK:-0}" != 0 ] && { [ "${#_PL_SYS[@]}" -gt 0 ] || [ "${#_PL_RECIPE[@]}" -gt 0 ]; }; then
    _dep_say "  ⚠ Installing system packages needs root and 'sudo' was not found: run as root, or install them yourself."
    return $reqrc
  fi
  if [ -n "$assume" ]; then BVK_DEPS_ASSUME=$assume; fi
  if ! _dep_ask; then
    _dep_say "  ↩ Not installed."
    if [ "${_DEP_NOASK:-0}" != 1 ]; then for id in "${miss[@]}"; do [ "${_DEP_REQ[$id]:-1}" = 0 ] && _dep_decline "$id"; done; fi
    return $reqrc
  fi
  _dep_install "${todo[@]}"
  local rc=0
  for id in "${reqmiss[@]}"; do [ "${_DEP_ST[$id]:-0}" = 1 ] || rc=1; done
  _DEP_MISSING=""; for id in "${reqmiss[@]}"; do [ "${_DEP_ST[$id]:-0}" = 1 ] || _DEP_MISSING+="${_DEP_MISSING:+ }$id"; done
  return $rc
}

# install everything in the plan (_PL_*), then look again
_dep_install() {
  local tmp id ok=1 bg_pip=0 bg_npm=0 late_pip=0 late_npm=0 pids=() p
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/bvkdeps.XXXXXX") || return 1
  _dep_say ""
  # a lane that needs something the system lane is going to install waits for it; the others start now
  if [ "${#_PL_PIP[@]}" -gt 0 ]; then
    if [ "${_DEP_ST[python3]:-0}" = 1 ] || command -v python3 >/dev/null 2>&1; then
      if [ "${_DEP_ST[pip]:-0}" = 1 ] || python3 -c 'import pip' 2>/dev/null; then bg_pip=1; else late_pip=1; fi
    else late_pip=1; fi
  fi
  if [ "${#_PL_NPM[@]}" -gt 0 ]; then
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then bg_npm=1; else late_npm=1; fi
  fi
  [ $bg_pip = 1 ] && { _dep_say "   ▶ Python packages (in the background): ${_PL_PIP[*]}"; ( _dep_lane_pip ) > "$tmp/pip.log" 2>&1 & pids+=($!); }
  [ $bg_npm = 1 ] && { _dep_say "   ▶ npm packages (in the background): ${_PL_NPM[*]}"; ( _dep_lane_npm ) > "$tmp/npm.log" 2>&1 & pids+=($!); }
  _dep_lane_sys
  hash -r 2>/dev/null; _dep_path_fix
  if [ $late_pip = 1 ]; then
    if command -v python3 >/dev/null 2>&1; then _dep_say "   ▶ Python packages (in the background): ${_PL_PIP[*]}"; ( _dep_lane_pip ) > "$tmp/pip.log" 2>&1 & pids+=($!)
    else echo "python3 is not available, so the Python packages were skipped" > "$tmp/pip.log"; fi
  fi
  if [ $late_npm = 1 ]; then
    if command -v npm >/dev/null 2>&1; then _dep_say "   ▶ npm packages (in the background): ${_PL_NPM[*]}"; ( _dep_lane_npm ) > "$tmp/npm.log" 2>&1 & pids+=($!)
    else echo "npm is not available, so the npm packages were skipped" > "$tmp/npm.log"; fi
  fi
  [ "${#pids[@]}" -gt 0 ] && { _dep_say "   … waiting for the background installs"; for p in "${pids[@]}"; do wait "$p" 2>/dev/null; done; }
  hash -r 2>/dev/null; _dep_path_fix
  # look again (forget the old "missing" answers)
  for id in "$@"; do _DEP_ST[$id]=0; done
  _dep_probe_all "$@"
  _dep_say ""
  for id in "$@"; do
    if [ "${_DEP_ST[$id]:-0}" = 1 ]; then _dep_say "   ✅ ${_DEP_LABEL[$id]}"
    else
      ok=0; _dep_say "   ❌ ${_DEP_LABEL[$id]} could not be installed"
      _dep_log "FAILED ${id}"
    fi
  done
  if [ $ok = 0 ]; then
    for p in pip npm; do [ -s "$tmp/$p.log" ] && { _dep_say "   --- last lines of the $p install ---"; tail -n 6 "$tmp/$p.log" >&2; }; done
    _dep_say "   Full log: ${BVK_DEPS_LOG:-$HOME/.bashbasicsbyvk/deps_install.log}"
  fi
  for id in pip npm; do [ -f "$tmp/$id.log" ] && _dep_log "$id lane output: $(tail -c 800 "$tmp/$id.log" | tr '\n' ' ')"; done
  rm -rf "$tmp"
  return 0
}

# -q : no menu, no output.  Only `auto` pip packages, one attempt a day each (the recents daemon's rule, now in one place).
_dep_quiet() {
  local id dir s now rc=0; dir=$(_dep_statedir)
  local -a go=()
  mkdir -p "$dir" 2>/dev/null
  now=$(date +%s)
  for id in "$@"; do
    if [[ " ${_DEP_FLAGS[$id]} " != *" auto "* ]]; then [ "${_DEP_REQ[$id]:-1}" = 1 ] && rc=1; continue; fi
    s="$(_dep_statedir)/$id.attempted"
    if [ -f "$s" ] && [ $(( now - $(stat -c %Y "$s" 2>/dev/null || echo 0) )) -lt 86400 ]; then rc=1; continue; fi
    go+=("$id")
  done
  [ "${#go[@]}" -eq 0 ] && return $rc
  _dep_plan "${go[@]}"
  [ "${#_PL_SYS[@]}${#_PL_NPM[@]}${#_PL_RECIPE[@]}" = "000" ] || return 1       # never system packages in the background
  command -v python3 >/dev/null 2>&1 || return 1
  _dep_lane_pip >/dev/null 2>&1
  hash -r 2>/dev/null
  for id in "${go[@]}"; do : > "$dir/$id.attempted"; _DEP_ST[$id]=0; done
  _dep_probe_all "${go[@]}"
  for id in "${go[@]}"; do [ "${_DEP_ST[$id]:-0}" = 1 ] || rc=1; done
  return $rc
}

# ── the table / map (for people and for tests) ───────────────────────────────
_dep_table() {
  local id st
  _dep_load || return 2
  _dep_mgr
  echo "package manager: ${_DEP_MGR:-none found}"
  _dep_probe_all "${!_DEP_KIND[@]}"
  for id in $(printf '%s\n' "${!_DEP_KIND[@]}" | sort); do
    st="missing"; [ "${_DEP_ST[$id]:-0}" = 1 ] && st="installed"
    printf '%-16s %-9s %-9s %s\n' "$id" "${_DEP_KIND[$id]}" "$st" "${_DEP_LABEL[$id]}"
  done
}

_dep_map() {
  local f
  _dep_load || return 2
  for f in $(printf '%s\n' "${!_DEP_FTITLE[@]}" | sort); do
    printf '%-26s requires: %-30s optional: %s\n' "$f" "${_DEP_FREQ[$f]:--}" "${_DEP_FOPT[$f]:--}"
  done
}

_dep_main() {
  case "${1:-}" in
    --list)  _dep_map; return $? ;;
    --check) _dep_table; return $? ;;
    -h|--help|"") sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; [ -z "${1:-}" ] && return 2; return 0 ;;
  esac
  _dep_need "$@"
}

if [ "${BASH_SOURCE[0]##*/}" = "${0##*/}" ]; then      # run, not sourced (also when started as `bash bashbasicsbyvk_deps.sh` through PATH)
  _DEP_CLI=1
  # run on its own (not loaded by `o`): the one thing a stand-alone executable may source is its own import file, which brings the choice menu
  declare -F _bvk_yn >/dev/null 2>&1 || source "_3bvk_import_deps.sh" 2>/dev/null
  _dep_main "$@"
  exit $?
fi
