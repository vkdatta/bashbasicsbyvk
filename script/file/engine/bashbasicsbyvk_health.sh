#!/usr/bin/env bash
# bashbasicsbyvk_health.sh — the  health  command
# ════════════════════════════════════════════════════════════════════════════
#  The file list is normally produced by the native C helper (bvk-ls).  When that
#  cannot be used the Python code takes over and the header says  [loaded by py].
#  `health` re-runs, step by step and verbosely, exactly what _bvk_go_bin does
#  (displayer.sh) and then exercises every bvk-ls sub-command, so the REASON is
#  printed instead of silently falling back.
#
#    health          full report on screen  (also saved to ~/.bashbasicsbyvk/health.log)
#
#  Sections
#    1  this session      what the running app currently believes
#    2  system            CPU / OS / shell / python
#    3  expected binary   which bvk-ls-<os>-<arch> this machine should use
#    4  where `o` lives   the install dir the binary is looked up from
#    5  candidates        every place _bvk_go_bin looks, checked one by one:
#                         exists · size · ELF header · CPU match · Android/glibc build
#                         · exec bit · noexec mount · real run (stderr captured)
#    6  other copies      bvk-ls files found elsewhere / inside the pip install record
#    7  sub-commands      scan count meta dsize window groups hashscan gfilter
#                         on a scratch folder (ASCII + Unicode) and on the current folder
#    8  python fallback   is the fallback itself healthy
#    9  verdict           the root cause + what to fix
#
#  Exit code 3 from groups / hashscan / gfilter is NOT a fault: it means "this folder
#  has non-ASCII names, ask Python".  health labels it so you can tell it apart.
#
#  Uses: _bvk_go_bin, _BVK_GO_BIN, _BVK_GO_WHY, _BVK_LOAD_SRC, _BVK_META_SRC (displayer.sh)
# ════════════════════════════════════════════════════════════════════════════

_HL_BAD=0
_HL_WARN=0
declare -a _HL_FINDINGS=()      # "what is wrong|how to fix"
_HL_WHY=""
_HL_FIX=""

_hl_h()    { printf '\n━━ %s ━━\n' "$*"; }
_hl_ok()   { printf '  ✅ %s\n' "$*"; }
_hl_bad()  { printf '  ❌ %s\n' "$*"; _HL_BAD=$((_HL_BAD+1)); }
_hl_warn() { printf '  ⚠️  %s\n' "$*"; _HL_WARN=$((_HL_WARN+1)); }
_hl_info() { printf '     %s\n' "$*"; }
_hl_fix()  { printf '     🔧 %s\n' "$*"; }
_hl_find() { _HL_FINDINGS+=("$1|$2"); }      # root-cause list for the verdict

_hl_us() {                                   # current time in microseconds → _HL_T
  local t="${EPOCHREALTIME:-}"
  if [ -n "$t" ]; then t="${t/[.,]/}"; _HL_T="${t}"
  else _HL_T=$(( $(date +%s) * 1000000 )); fi
}

# does the filesystem holding $1 carry the noexec mount flag?   0 yes · 1 no · 2 unknown
_hl_noexec() {
  [ -r /proc/mounts ] || return 2
  local p; p="$(readlink -f -- "$1" 2>/dev/null || printf '%s' "$1")"
  awk -v p="$p" '
    { mp=$2; gsub(/\\040/," ",mp)
      if (mp=="/" || p==mp || index(p, mp "/")==1) if (length(mp)>=best) { best=length(mp); opts=$4 } }
    END { if (best==0) exit 2; if (opts ~ /(^|,)noexec(,|$)/) exit 0; exit 1 }' /proc/mounts
}

# ELF header → _HL_ELF = notelf | <class>:<machine>:<type>   (machine: amd64 arm64 arm x86 other)
_hl_elf() {
  local hex cls mach typ
  hex="$(od -An -tx1 -N20 -v "$1" 2>/dev/null | tr -d ' \n')"
  if [ "${hex:0:8}" != "7f454c46" ]; then _HL_ELF="notelf"; return 1; fi
  case "${hex:8:2}" in 01) cls=32 ;; 02) cls=64 ;; *) cls=? ;; esac
  case "${hex:36:4}" in
    3e00) mach=amd64 ;; b700) mach=arm64 ;; 2800) mach=arm ;; 0300) mach=x86 ;; *) mach="other(${hex:36:4})" ;;
  esac
  case "${hex:32:4}" in 0200) typ=EXEC ;; 0300) typ=DYN/PIE ;; *) typ="type-${hex:32:4}" ;; esac
  _HL_ELF="$cls:$mach:$typ"
}

# turn a failed run into words → _HL_WHY / _HL_FIX
_hl_explain() {                              # _hl_explain <rc> <stderr> <bin>
  local rc="$1" err="$2" b="$3"
  case "$err" in
    *"Exec format error"*)
      _HL_WHY="Exec format error — the binary was built for a different CPU/OS than this machine"
      _HL_FIX="Rebuild/ship the right bvk-ls-<os>-<arch> (CI: .github/workflows/build.yml) and check the arch name mapping in _bvk_go_bin" ;;
    *PHDR*|*"broken executable"*)
      _HL_WHY="the Android linker refused it: this is a glibc static-pie build (no PT_PHDR)"
      _HL_FIX="On Android _bvk_go_bin must pick bvk-ls-android-<arch> (NDK build). Check 'uname -o' prints Android and that the android binary shipped" ;;
    *"Permission denied"*)
      _HL_WHY="Permission denied when running it (no exec permission, noexec mount, or SELinux/app sandbox)"
      _HL_FIX="chmod +x it; if the mount is noexec copy the binary to an exec-able dir (e.g. \$PREFIX/bin) and look it up there" ;;
    *"No such file or directory"*|*"not found"*|*"bad ELF interpreter"*)
      _HL_WHY="'No such file' for an existing file = its dynamic loader/interpreter is missing (wrong libc: e.g. an android build on glibc, or the reverse)"
      _HL_FIX="Use the static linux build on glibc/musl systems and the android build only on Android; check the interpreter with: readelf -l $b | grep interpreter" ;;
    *)
      case "$rc" in
        126) _HL_WHY="exit 126: found but cannot be executed (permissions / noexec mount)"
             _HL_FIX="chmod +x, or move the binary off a noexec filesystem" ;;
        127) _HL_WHY="exit 127: command/loader not found"
             _HL_FIX="the file's interpreter is missing — wrong build for this OS" ;;
        124) _HL_WHY="timed out (hung for 5 s)"
             _HL_FIX="run it by hand: $b count \$HOME 0" ;;
        132|134|136|139) _HL_WHY="crashed (signal, exit $rc) — illegal instruction / abort / segfault"
             _HL_FIX="the build uses instructions or a loader this device does not support; rebuild with a lower baseline" ;;
        *)   _HL_WHY="ran but exited with status $rc${err:+: ${err%%$'\n'*}}"
             _HL_FIX="run it by hand to see the error: $b count \$HOME 0" ;;
      esac ;;
  esac
}

# Check ONE candidate. Returns 0 if it is a working binary. Sets _HL_WHY/_HL_FIX otherwise.
_hl_check_bin() {                            # _hl_check_bin <path> <expected-mach> <expected-os>
  local b="$1" xm="$2" xo="$3" sz hexmode rc err m
  _HL_WHY=""; _HL_FIX=""
  if [ -z "$b" ]; then _HL_WHY="not found"; return 1; fi
  _hl_info "path   : $b"
  if [ ! -e "$b" ]; then _HL_WHY="file does not exist"; return 1; fi
  if [ ! -f "$b" ]; then _HL_WHY="exists but is not a regular file"; return 1; fi
  sz="$(wc -c <"$b" 2>/dev/null | tr -d ' ')"
  hexmode="$(stat -c '%A' "$b" 2>/dev/null || ls -l "$b" 2>/dev/null | cut -c1-10)"
  _hl_info "size   : ${sz:-?} bytes   mode: ${hexmode:-?}"
  if [ "${sz:-0}" -eq 0 ]; then
    _HL_WHY="file is empty (0 bytes) — truncated copy or failed build"
    _HL_FIX="re-install; check the CI 'Commit generated binaries' step"; return 1
  fi

  if ! _hl_elf "$b"; then
    local peek; peek="$(head -c 64 "$b" 2>/dev/null | tr -c '[:print:]' '.')"
    _hl_info "header : not an ELF file → '${peek:0:48}'"
    case "$peek" in
      version\ https://git-lfs*) _HL_WHY="it is a git-lfs pointer, not the binary"; _HL_FIX="fetch real content (git lfs pull) or stop tracking the binary with LFS" ;;
      "<"*|*html*|*HTML*)        _HL_WHY="it is an HTML page (a download/redirect error saved as the binary)"; _HL_FIX="re-fetch from the raw URL" ;;
      *)                         _HL_WHY="not an ELF executable"; _HL_FIX="rebuild the binary" ;;
    esac
    return 1
  fi
  m="${_HL_ELF#*:}"; m="${m%%:*}"
  _hl_info "ELF    : ${_HL_ELF//:/ · }"
  if [ -n "$xm" ] && [ "$m" != "$xm" ]; then
    _HL_WHY="built for $m but this machine needs $xm"
    _HL_FIX="ship the $xm build under this name (check the arch mapping in build.sh / build.yml)"; return 1
  fi

  local has_android=0
  grep -aq '/system/bin/linker' "$b" 2>/dev/null && has_android=1
  if [ "$xo" = android ] && [ "$has_android" -eq 0 ]; then
    _hl_info "build  : glibc static build (no Android linker path in it)"
    _HL_WHY="this is a Linux/glibc build but the device is Android — its linker aborts with 'Could not find a PHDR'"
    _HL_FIX="use bvk-ls-android-<arch> (NDK build); make sure it is in bashbasicsbyvk/bin and _bvk_go_bin maps Android → android"
    return 1
  fi
  if [ "$xo" = linux ] && [ "$has_android" -eq 1 ]; then
    _hl_info "build  : Android (bionic) build"
    _HL_WHY="this is an Android build but the OS is plain Linux (no /system/bin/linker)"
    _HL_FIX="uname -o does not say Android here, so the linux build must be used; check the file naming"
    return 1
  fi

  if [ ! -x "$b" ]; then
    if chmod +x "$b" 2>/dev/null && [ -x "$b" ]; then _hl_warn "was not executable — chmod +x worked just now (the installer should set this)"
    else
      _HL_WHY="not executable and chmod +x failed (read-only install location?)"
      _HL_FIX="make the file executable at install time (setup.py data_files mode) or copy it somewhere writable"; return 1
    fi
  fi
  _hl_info "exec   : executable bit set"

  _hl_noexec "$b"; case $? in
    0) _hl_info "mount  : filesystem is mounted noexec"
       _HL_WHY="the filesystem holding it is mounted noexec — the kernel will refuse to run it"
       _HL_FIX="install into an exec-able prefix (Termux: \$PREFIX; Linux: ~/.local/bin or /usr/local/bin) instead of $(dirname "$b")"
       # keep going: the real run below confirms it
       ;;
    1) _hl_info "mount  : exec allowed" ;;
    *) _hl_info "mount  : (could not read mount options)" ;;
  esac

  local t=""; command -v timeout >/dev/null 2>&1 && t="timeout 5"
  err="$($t "$b" count "${HOME:-.}" 0 2>&1 >/dev/null)"; rc=$?
  if [ $rc -eq 0 ]; then _hl_info "run    : self-test OK (count \$HOME → exit 0)"; _HL_WHY=""; _HL_FIX=""; return 0; fi
  _hl_info "run    : self-test FAILED, exit $rc${err:+, stderr: ${err%%$'\n'*}}"
  # does it work on another folder? then it is a path-access problem, not the binary
  if $t "$b" count /tmp 0 >/dev/null 2>&1; then
    _HL_WHY="the binary runs, but cannot read \$HOME ($HOME) — folder access/permission problem"
    _HL_FIX="the self-test in _bvk_go_bin probes \$HOME; on Android/Termux grant storage access or probe a folder that is always readable"
    return 1
  fi
  _hl_explain "$rc" "$err" "$b"
  return 1
}

# ── sub-command exerciser ─────────────────────────────────────────────────────
# _hl_run <label> <expect> <args…>   expect: 0 | 0or3 (3 = Unicode → Python, by design)
_hl_run() {
  local label="$1" expect="$2"; shift 2
  local t0 t1 out rc ms first n
  _hl_us; t0=$_HL_T
  out="$("$_HL_BIN" "$@" 2>&1)"; rc=$?
  _hl_us; t1=$_HL_T; ms=$(( (t1 - t0) / 1000 ))
  n=$(printf '%s' "$out" | grep -c '' )
  first="${out%%$'\n'*}"; first="${first:0:60}"
  if [ $rc -eq 0 ]; then
    _hl_ok "$(printf '%-9s exit 0   %5d ms   %s line(s)  %s' "$label" "$ms" "$n" "${first:+→ $first}")"
  elif [ $rc -eq 3 ] && [ "$expect" = 0or3 ]; then
    _hl_warn "$(printf '%-9s exit 3   %5d ms   Unicode names → Python is used ON PURPOSE for this folder' "$label" "$ms")"
    _HL_UNI=$((_HL_UNI+1))
  else
    _hl_bad "$(printf '%-9s exit %s  %5d ms   %s' "$label" "$rc" "$ms" "${first:-(no output)}")"
    _hl_find "bvk-ls '$label' fails (exit $rc${first:+: $first}) — that part falls back to Python" "run by hand: $_HL_BIN $* ; then fix the C source (bvk-ls/src)"
  fi
}

_hl_subcommands() {
  local d u f
  d="$(mktemp -d 2>/dev/null)" || { _hl_warn "no temp dir — skipped"; return; }
  u="$(mktemp -d 2>/dev/null)"
  : > "$d/a.txt"; : > "$d/B.txt"; : > "$d/.hidden"; : > "$d/#hash"; mkdir "$d/sub"; : > "$d/sub/x"; head -c 4096 /dev/zero > "$d/sub/y"
  : > "$u/a.txt"; : > "$u/Éclair.txt"; : > "$u/日本.txt"
  f="$d/.paths"; printf '%s\n' "$d/a.txt" "$d/sub" > "$f"
  _HL_UNI=0
  _hl_info "scratch folder (ASCII only): $d"
  _hl_run count    0     count   "$d" 0
  _hl_run scan     0     scan    "$d" az 0 ""
  _hl_run meta     0     meta    "$f"
  _hl_run dsize    0     dsize   "$f"
  _hl_run window   0     window  "$d" az 0 "" 1 3
  _hl_run groups   0or3  groups  "$d" 0 ""
  _hl_run hashscan 0or3  hashscan "$d" 0 ""
  _hl_run gfilter  0or3  gfilter "$d" 0 "" "a" partial
  _hl_info "scratch folder (with Unicode names): $u"
  _hl_run groups   0or3  groups  "$u" 0 ""
  _hl_run gfilter  0or3  gfilter "$u" 0 "" "e" partial

  if [ -n "${path:-}" ] && [ -d "$path" ]; then
    local h=0; [ "${show_hidden_files:-false}" = "true" ] && h=1
    _hl_info "your current folder: $path"
    _hl_run count    0     count   "$path" "$h"
    _hl_run scan     0     scan    "$path" az "$h" ""
    _hl_run groups   0or3  groups  "$path" "$h" ""
  fi
  rm -rf "$d" "$u" 2>/dev/null
  if [ "${_HL_UNI:-0}" -gt 0 ]; then
    _hl_info ""
    _hl_info "ℹ️  exit 3 is by design (groups.c: non-ASCII names need Unicode rules). It makes the header"
    _hl_info "   say [loaded by py] for those folders even though the C binary works. To remove that,"
    _hl_info "   groups.c/gfilter must learn the Unicode grouping rules."
  fi
}

# ── the report ────────────────────────────────────────────────────────────────
_hl_report() {
  local _m="" _os="" _o _d b i
  echo "🩺 bashbasicsbyvk health — C engine (bvk-ls) vs Python fallback"
  printf '   %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

  _hl_h "1  this session"
  if [ -z "${_BVK_GO_BIN+x}" ]; then _hl_info "_BVK_GO_BIN : (not probed yet in this shell)"
  elif [ -z "$_BVK_GO_BIN" ]; then _hl_warn "_BVK_GO_BIN is EMPTY — the probe already failed once; the result is cached for this whole session"
  else _hl_ok "_BVK_GO_BIN = $_BVK_GO_BIN"; fi
  [ -n "${_BVK_GO_WHY:-}" ] && _hl_info "recorded reason : $_BVK_GO_WHY"
  _hl_info "header tag now  : load=${_BVK_LOAD_SRC:-(none yet)}  meta=${_BVK_META_SRC:-(none yet)}   (c = native, py = fallback)"
  _hl_info "BVK_NO_GO=${BVK_NO_GO:-0}   BVK_SHOW_SRC=${BVK_SHOW_SRC:-1}"
  if [ "${BVK_NO_GO:-0}" = "1" ]; then
    _hl_bad "BVK_NO_GO=1 — the C engine is disabled by an environment variable"
    _hl_find "BVK_NO_GO=1 is set in the environment" "unset BVK_NO_GO (check ~/.bashrc / ~/.profile)"
  fi

  _hl_h "2  system"
  _hl_info "uname   : $(uname -srm 2>/dev/null)"
  _hl_info "OS name : $(uname -o 2>/dev/null || echo unknown)"
  _hl_info "bash    : ${BASH_VERSION:-?}"
  _hl_info "PREFIX  : ${PREFIX:-(unset)}    HOME: ${HOME:-(unset)}"
  if [ -d "${HOME:-/nonexistent}" ] && [ -r "$HOME" ]; then _hl_ok "\$HOME is readable (the self-test probes it)"
  else _hl_bad "\$HOME is missing or unreadable — the self-test in _bvk_go_bin probes it and will always fail"
       _hl_find "\$HOME ($HOME) is not a readable directory" "fix HOME, or change the probe folder in _bvk_go_bin"; fi

  _hl_h "3  expected binary"
  case "$(uname -m)" in
    aarch64|arm64) _m=arm64 ;;
    x86_64|amd64)  _m=amd64 ;;
    armv7*|armv8l) _m=arm ;;
    *)             _m="" ;;
  esac
  case "$(uname -o 2>/dev/null)" in Android) _os=android ;; *) _os=linux ;; esac
  if [ -z "$_m" ]; then
    _hl_bad "CPU '$(uname -m)' has no prebuilt bvk-ls (supported: aarch64/arm64, x86_64/amd64, armv7*/armv8l)"
    _hl_find "unsupported CPU '$(uname -m)'" "add it to the arch case in _bvk_go_bin and to build.sh / build.yml"
  else
    _hl_ok "this machine should use:  bvk-ls-$_os-$_m"
  fi

  _hl_h "4  where 'o' lives"
  _o="$(command -v o 2>/dev/null)"
  _hl_info "command -v o : ${_o:-(nothing)}   [$(type -t o 2>/dev/null || echo none)]"
  _d="${_o%/*}"
  if [ -z "$_o" ]; then
    _hl_bad "'o' is not found on PATH — the lookup \"\$_d/../bashbasicsbyvk/bin\" becomes \"/../bashbasicsbyvk/bin\" (wrong)"
    _hl_find "'o' is not on PATH (alias/function/relative call), so the install-dir lookup is broken" "start it via the installed 'o' on PATH, or resolve its dir with readlink -f \$0 in _bvk_go_bin"
  elif [ "${_o#/}" = "$_o" ]; then
    _hl_warn "command -v returned a non-absolute value ('$_o') — an alias or function; the dir lookup will be wrong"
  else
    _hl_ok "install bin dir: $_d   →   data dir: $(readlink -f -- "$_d/../bashbasicsbyvk" 2>/dev/null || echo "$_d/../bashbasicsbyvk")"
  fi

  _hl_h "5  candidates (the exact order _bvk_go_bin tries)"
  local -a _lbl=("bvk-ls on PATH") _cand=("$(command -v bvk-ls 2>/dev/null)")
  if [ -n "$_m" ]; then
    _lbl+=("install data dir" "bvk-ls-$_os-$_m on PATH")
    _cand+=("$_d/../bashbasicsbyvk/bin/bvk-ls-$_os-$_m" "$(command -v "bvk-ls-$_os-$_m" 2>/dev/null)")
  fi
  _HL_BIN=""
  local -a _whys=() _fixes=()
  for i in "${!_cand[@]}"; do
    printf '\n  [%d] %s\n' "$((i+1))" "${_lbl[$i]}"
    if _hl_check_bin "${_cand[$i]}" "$_m" "$_os"; then
      _hl_ok "usable"
      [ -z "$_HL_BIN" ] && _HL_BIN="${_cand[$i]}"
    else
      _hl_info "✗ ${_HL_WHY:-unusable}"
      [ -n "$_HL_FIX" ] && _hl_fix "$_HL_FIX"
      _whys+=("${_lbl[$i]}: ${_HL_WHY}"); _fixes+=("${_HL_FIX}")
    fi
  done

  _hl_h "6  other copies on this machine"
  local -a roots=() hits=()
  [ -n "$_d" ] && roots+=("$_d/..")
  for b in "${PREFIX:-}" "$HOME/.local" /usr/local /usr /opt; do [ -n "$b" ] && [ -d "$b" ] && roots+=("$b"); done
  local t=""; command -v timeout >/dev/null 2>&1 && t="timeout 8"
  while IFS= read -r b; do [ -n "$b" ] && hits+=("$b"); done < <($t find "${roots[@]}" -maxdepth 5 -type f -name 'bvk-ls*' 2>/dev/null | sort -u)
  if [ "${#hits[@]}" -eq 0 ]; then
    _hl_bad "no bvk-ls file anywhere under the install prefixes"
    _hl_find "no bvk-ls binary was installed at all" "the pip install shipped none: the commit/tag you installed predates the 'build: update bvk-ls binaries' commit, or setup.py data_files did not pick them up. Upgrade to a newer tag (-u) and re-check."
  else
    for b in "${hits[@]}"; do _hl_info "found: $b"; done
  fi
  if command -v pip >/dev/null 2>&1; then
    local rec; rec="$(pip show -f bashbasicsbyvk 2>/dev/null | grep -i 'bvk-ls' | head -n 6)"
    if [ -n "$rec" ]; then _hl_info "pip RECORD lists:"; printf '%s\n' "$rec" | sed 's/^/       /'
    else _hl_info "pip RECORD lists no bvk-ls file (it was not part of the installed package)"; fi
  fi

  if [ -n "$_HL_BIN" ]; then
    _hl_h "7  sub-commands (using $_HL_BIN)"
    _hl_subcommands
  else
    _hl_h "7  sub-commands"
    _hl_info "skipped — no working binary (see section 5)"
  fi

  _hl_h "8  python fallback"
  if command -v python3 >/dev/null 2>&1; then
    _hl_ok "python3 $(python3 -c 'import sys;print(sys.version.split()[0])' 2>/dev/null)"
    python3 -c 'import os, multiprocessing, concurrent.futures' 2>/dev/null \
      && _hl_ok "multiprocessing + ProcessPoolExecutor import fine (used by the fallback)" \
      || _hl_bad "multiprocessing / concurrent.futures cannot be imported — the fallback itself is broken"
  else
    _hl_bad "python3 not found — neither C nor Python can list files"
  fi

  _hl_h "9  verdict"
  if [ -n "$_HL_BIN" ] && [ "${#_HL_FINDINGS[@]}" -eq 0 ]; then
    _hl_ok "C engine is HEALTHY: $_HL_BIN"
    if [ "${_BVK_LOAD_SRC:-}" = py ] || [ "${_BVK_META_SRC:-}" = py ]; then
      _hl_warn "…but the header currently says [loaded by py]. Likely causes, in order:"
      _hl_info "  a) this folder has non-ASCII names (groups/hashscan/gfilter exit 3 → Python, by design)"
      _hl_info "  b) the probe failed once earlier in this session and its EMPTY result is cached (restart 'o')"
      _hl_info "  c) a specific sub-command failed — see section 7"
    fi
  else
    if [ -z "$_HL_BIN" ]; then
      _hl_bad "PYTHON FALLBACK IS ACTIVE — no usable bvk-ls was found"
      for i in "${!_whys[@]}"; do _hl_info "  • ${_whys[$i]}"; done
    fi
    local fnd
    for fnd in "${_HL_FINDINGS[@]}"; do
      _hl_info "ROOT CAUSE: ${fnd%%|*}"
      _hl_fix "${fnd#*|}"
    done
    if [ -z "$_HL_BIN" ] && [ "${#_HL_FINDINGS[@]}" -eq 0 ]; then
      # no finding of its own: use the most specific per-candidate reason (an existing-but-broken file beats "not found")
      for i in "${!_whys[@]}"; do
        case "${_whys[$i]}" in *"not found"|*"does not exist") ;; *) _hl_info "ROOT CAUSE: ${_whys[$i]}"; [ -n "${_fixes[$i]}" ] && _hl_fix "${_fixes[$i]}"; break ;; esac
      done
    fi
  fi
  printf '\n   %d problem(s), %d warning(s)\n' "$_HL_BAD" "$_HL_WARN"
}

bvk_health() {
  local log="${HOME}/.bashbasicsbyvk/health.log"
  mkdir -p "${log%/*}" 2>/dev/null
  # a pipeline = subshell: the probe below cannot disturb the running session's cached state
  _hl_report 2>&1 | tee "$log"
  printf '\n📝 Saved: %s   (send it along to get it patched)\n' "$log"
}
