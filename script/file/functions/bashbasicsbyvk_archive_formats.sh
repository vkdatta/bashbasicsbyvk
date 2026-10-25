#!/usr/bin/env bash
# bashbasicsbyvk_archive_formats.sh — the ONE place that knows which archive formats exist, how to recognise one, how to make one and how to open one.
# ════════════════════════════════════════════════════════════════════════════
#  Formats (id → file name ending):
#     zip   .zip        tar     .tar        targz  .tar.gz / .tgz     tarxz  .tar.xz / .txz     tarbz2 .tar.bz2 / .tbz2
#     7z    .7z         tarzst  .tar.zst / .tzst                       tarlz4 .tar.lz4
#     skill .skill      (a normal zip file whose name ends in .skill — the format AI assistants hand out)
#
#  RECOGNISING (semantic, not by the last dot):
#    1. the NAME is read as words, so a copy made by a file manager or a download still counts:
#           hello.zip1   hello_tar.gz   hello.tar-1.gz   hello- (2).zip   hello (1).tar.gz   hello.ZIP   hello.tgz.bak
#       The format word must come last (a trailing number, "copy", "bak", "old" is ignored); a compressed stream
#       (gz xz bz2 zst lz4) only counts as an archive when the word "tar" comes right before it.
#    2. the CONTENT (the first bytes of the file) is the judge: the name only says "this might be an archive",
#       the bytes say which one it really is. A name that lies (a .zip that is really a tar.gz) is opened as what it is;
#       a text file called notes_zip is not an archive at all.
#
#  API (all results come back in globals, no subshells — this runs on every file menu):
#    _arc_scan NAME          name only      → _ARC_NFMT (format id the name claims), _ARC_STEM (name without the archive ending / copy marker)
#    _arc_magic FILE         content only   → _ARC_MAGIC (zip gz xz bz2 zst lz4 7z tar | "")
#    _arc_detect FILE        both           → _ARC_FMT (the real format id), _ARC_STEM ; returns 1 and sets _ARC_WHY when it is not an archive
#    _arc_need create|extract FMT           → 0 when every tool is installed, else prints the missing one and returns 1
#    _arc_have create|extract FMT           → same, silent
#    _arc_create FMT ARCHIVE WORKDIR HIDDEN FOLLOW ITEM...   (ITEMs are relative to WORKDIR; HIDDEN=true|false; FOLLOW=true|false: follow symlinks)
#    _arc_extract FMT ARCHIVE DESTDIR
#    _arc_strip_ext NAME     → _ARC_STRIPPED (NAME without a typed archive ending)
#    _arc_is_fmt ID · _arc_supported (one-line list of endings, for messages)
#  Used by: staging_archive.sh (z- uz- and the fx zip / unzip actions), run.sh (the file menu), the Compress format setting.
# ════════════════════════════════════════════════════════════════════════════

declare -ga _ARC_FORMATS=(zip tar targz tarxz tarbz2 7z tarzst tarlz4 skill)
declare -gA _ARC_LABEL=([zip]=".zip" [tar]=".tar" [targz]=".tar.gz" [tarxz]=".tar.xz" [tarbz2]=".tar.bz2" [7z]=".7z" [tarzst]=".tar.zst" [tarlz4]=".tar.lz4" [skill]=".skill")
declare -gA _ARC_NOTE=(
  [zip]="opens everywhere, files can be reached one by one"
  [tar]="bundles files, no compression"
  [targz]="good balance of speed and size, widely supported"
  [tarxz]="high compression, slower"
  [tarbz2]="traditional, moderate to high compression"
  [7z]="high compression, encryption, solid archives"
  [tarzst]="fast and compact, the modern gzip"
  [tarlz4]="fastest, compresses less"
  [skill]="a zip with a .skill ending (as AI assistants give them)")
# the tools a format needs (space separated; "7z" = any 7-Zip build). Extraction of the zip family can use 7-Zip when unzip is missing.
declare -gA _ARC_TOOLS_C=([zip]="zip" [skill]="zip" [tar]="tar" [targz]="tar gzip" [tarxz]="tar xz" [tarbz2]="tar bzip2" [7z]="7z" [tarzst]="tar zstd" [tarlz4]="tar lz4")
declare -gA _ARC_TOOLS_X=([zip]="unzip" [skill]="unzip" [tar]="tar" [targz]="tar gzip" [tarxz]="tar xz" [tarbz2]="tar bzip2" [7z]="7z" [tarzst]="tar zstd" [tarlz4]="tar lz4")
# Termux / apt package that provides a tool
declare -gA _ARC_PKG=([zip]=zip [unzip]=unzip [tar]=tar [gzip]=gzip [xz]=xz-utils [bzip2]=bzip2 [zstd]=zstd [lz4]=lz4 [7z]=p7zip)

_ARC_NFMT="" _ARC_STEM="" _ARC_MAGIC="" _ARC_FMT="" _ARC_WHY="" _ARC_STRIPPED="" _ARC_MISSING="" _ARC_7Z=""

_arc_is_fmt() { [ -n "${_ARC_LABEL[${1:-}]+x}" ]; }

_arc_supported() { echo ".zip .tar .tar.gz/.tgz .tar.xz/.txz .tar.bz2/.tbz2 .7z .tar.zst/.tzst .tar.lz4 .skill"; }

# ── 1. the name ─────────────────────────────────────────────────────────────
# a word that may follow the format word (or sit between "tar" and "gz") without changing what the file is
_arc_junk() {
  case "$1" in
    copy|copia|bak|old|orig|backup) return 0 ;;
    *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# a format word, possibly with a copy number glued on (zip1, tar2, 7z1): sets _arc_w (the word) / returns 1
_arc_word() {
  _arc_w=""
  [[ "$1" =~ ^(zip|tar|tgz|txz|tbz2?|tzst|tlz4|7z|skill|gz|xz|bz2|zst|lz4)[0-9]*$ ]] || return 1
  _arc_w="${BASH_REMATCH[1]}"
}

_arc_scan() {
  _ARC_NFMT=""; _ARC_STEM=""
  local orig="$1" n="${1,,}" rest tok pre off=0 i j k end s prev
  local -a T=() B=()
  rest="$n"
  while [[ "$rest" =~ ^([^[:alnum:]]*)([[:alnum:]]+) ]]; do
    pre=${#BASH_REMATCH[1]}; tok="${BASH_REMATCH[2]}"
    T+=("$tok"); B+=($(( off + pre )))
    off=$(( off + pre + ${#tok} )); rest="${n:off}"
  done
  k=${#T[@]}
  i=$(( k - 1 ))
  while (( i >= 0 )) && _arc_junk "${T[i]}" && ! _arc_word "${T[i]}"; do i=$(( i - 1 )); done   # copy numbers / "copy" after the ending
  (( i >= 0 )) || return 1
  _arc_word "${T[i]}" || return 1
  end=${B[i]}
  case "$_arc_w" in
    zip)  _ARC_NFMT=zip ;;
    skill) _ARC_NFMT=skill ;;
    tar)  _ARC_NFMT=tar ;;
    7z)   _ARC_NFMT=7z ;;
    tgz)  _ARC_NFMT=targz ;;
    txz)  _ARC_NFMT=tarxz ;;
    tbz|tbz2) _ARC_NFMT=tarbz2 ;;
    tzst) _ARC_NFMT=tarzst ;;
    tlz4) _ARC_NFMT=tarlz4 ;;
    gz|xz|bz2|zst|lz4)
      # a compressed stream is an archive only as "<something> tar <junk> gz": look left past copy numbers for the word tar
      j=$(( i - 1 ))
      while (( j >= 0 )) && _arc_junk "${T[j]}" && ! _arc_word "${T[j]}"; do j=$(( j - 1 )); done
      (( j >= 0 )) || return 1
      _arc_word "${T[j]}" && [ "$_arc_w" = tar ] || return 1
      end=${B[j]}
      case "${T[i]}" in
        gz*)  _ARC_NFMT=targz ;;
        xz*)  _ARC_NFMT=tarxz ;;
        bz2*) _ARC_NFMT=tarbz2 ;;
        zst*) _ARC_NFMT=tarzst ;;
        lz4*) _ARC_NFMT=tarlz4 ;;
      esac ;;
    *) return 1 ;;
  esac
  # the stem: what stands before the ending, minus separators and a copy marker such as " (2)" or "_copy"
  s="${orig:0:end}"
  while :; do
    prev="$s"
    s="${s%"${s##*[![:space:]._-]}"}"
    if   [[ "${s,,}" =~ ^(.*[^[:space:]_-]|)[[:space:]_-]*\([0-9]+\)$ ]]; then s="${s:0:${#BASH_REMATCH[1]}}"
    elif [[ "${s,,}" =~ ^(.*[^[:space:]_-])[[:space:]_-]*\(copy([[:space:]]*[0-9]+)?\)$ ]]; then s="${s:0:${#BASH_REMATCH[1]}}"
    elif [[ "${s,,}" =~ ^(.*[^[:space:]_-])[[:space:]_-]+copy([[:space:]]*[0-9]+)?$ ]]; then s="${s:0:${#BASH_REMATCH[1]}}"
    fi
    [ "$s" = "$prev" ] && break
  done
  _ARC_STEM="$s"
  return 0
}

# ── 2. the content ──────────────────────────────────────────────────────────
_arc_magic() {
  _ARC_MAGIC=""
  local h
  h="$(LC_ALL=C head -c 265 -- "$1" 2>/dev/null | od -An -v -tx1 2>/dev/null)" || return 1
  h="${h//[[:space:]]/}"
  case "$h" in
    504b0304*|504b0506*|504b0708*) _ARC_MAGIC=zip ;;
    1f8b*)                         _ARC_MAGIC=gz ;;
    fd377a585a00*)                 _ARC_MAGIC=xz ;;
    425a68*)                       _ARC_MAGIC=bz2 ;;
    28b52ffd*|5[0-9a-f]2a4d18*)    _ARC_MAGIC=zst ;;
    04224d18*|02214c18*)           _ARC_MAGIC=lz4 ;;
    377abcaf271c*)                 _ARC_MAGIC=7z ;;
    *) [ "${h:514:10}" = 7573746172 ] && _ARC_MAGIC=tar ;;      # "ustar" at byte 257
  esac
  return 0
}

# ── 1 + 2 together ──────────────────────────────────────────────────────────
_arc_detect() {
  _ARC_FMT=""; _ARC_WHY=""
  if ! _arc_scan "${1##*/}"; then _ARC_WHY="its name does not end like an archive (supported: $(_arc_supported))"; return 1; fi
  if [ ! -f "$1" ]; then _ARC_WHY="not an existing file"; return 1; fi
  _arc_magic "$1"
  case "$_ARC_MAGIC" in
    zip)  if [ "$_ARC_NFMT" = skill ]; then _ARC_FMT=skill; else _ARC_FMT=zip; fi ;;
    gz)   _ARC_FMT=targz ;;
    xz)   _ARC_FMT=tarxz ;;
    bz2)  _ARC_FMT=tarbz2 ;;
    zst)  _ARC_FMT=tarzst ;;
    lz4)  _ARC_FMT=tarlz4 ;;
    7z)   _ARC_FMT=7z ;;
    tar)  _ARC_FMT=tar ;;
    *)    _ARC_WHY="the name says archive but the content is not one (empty, damaged or another kind of file)"; return 1 ;;
  esac
  return 0
}

# a typed name with an archive ending: strip it (longest ending first)
_arc_strip_ext() {
  local n="$1" l="${1,,}" e
  _ARC_STRIPPED="$n"
  for e in .tar.gz .tar.xz .tar.bz2 .tar.zst .tar.lz4 .tgz .txz .tbz2 .tbz .tzst .tlz4 .tar .zip .7z .skill; do
    if [[ "$l" == *"$e" && ${#n} -gt ${#e} ]]; then _ARC_STRIPPED="${n:0:$(( ${#n} - ${#e} ))}"; return 0; fi
  done
  return 0
}

# ── tools ───────────────────────────────────────────────────────────────────
# _arc_7z: the 7-Zip binary of this machine (7zz / 7z / 7za / 7zr) → _ARC_7Z ; 1 when none
_arc_7z() {
  [ -n "$_ARC_7Z" ] && [ -x "$_ARC_7Z" ] && return 0
  local b
  for b in 7zz 7z 7za 7zr; do _ARC_7Z="$(command -v "$b" 2>/dev/null)" && [ -n "$_ARC_7Z" ] && return 0; done
  _ARC_7Z=""; return 1
}

_arc_tool_ok() {
  case "$1" in
    7z)    _arc_7z ;;
    *)     command -v "$1" >/dev/null 2>&1 ;;
  esac
}

# _arc_have create|extract FMT   (silent)  — sets _ARC_MISSING to the first tool that is not there
_arc_have() {
  local t list
  _ARC_MISSING=""
  if [ "$1" = create ]; then list="${_ARC_TOOLS_C[$2]}"; else list="${_ARC_TOOLS_X[$2]}"; fi
  for t in $list; do
    _arc_tool_ok "$t" && continue
    # a zip can also be opened by 7-Zip when unzip is not installed
    if [ "$t" = unzip ] && _arc_7z; then continue; fi
    _ARC_MISSING="$t"; return 1
  done
  return 0
}

_arc_need() {
  _arc_have "$1" "$2" && return 0
  echo "❌ '$_ARC_MISSING' not found — install it first (e.g. pkg install ${_ARC_PKG[$_ARC_MISSING]:-$_ARC_MISSING})."
  return 1
}

# ── making an archive ───────────────────────────────────────────────────────
# the 7-Zip builds disagree about symlinks: p7zip stores the link unless told -l, the new 7-Zip follows it by itself
_arc_7z_follow() {
  _ARC_7Z_FOLLOW=()
  [ "$1" = true ] || return 0
  case "$("$_ARC_7Z" 2>&1 | head -n 3)" in *[Pp]7[Zz]ip*) _ARC_7Z_FOLLOW=(-l) ;; esac
}

_arc_create() {
  local fmt="$1" arc="$2" wd="$3" hid="$4" follow="$5"; shift 5
  local -a items=("$@") filt=()
  local rc=0 th="" tf=""
  [ "$follow" = true ] && th="h"
  case "$fmt" in
    zip|skill)
      if [ "$hid" = true ]; then
        ( cd "$wd" && zip -r "$arc" "${items[@]}" )                      # zip follows symlinks by default
      else
        # same list, minus hidden files/folders inside the chosen items
        ( cd "$wd" && _hid_find0 false 0 "${items[@]/#/./}" | tr '\0' '\n' | zip "$arc" -@ )
      fi
      rc=$? ;;
    tar|targz|tarxz|tarbz2)
      case "$fmt" in targz) tf=z ;; tarxz) tf=J ;; tarbz2) tf=j ;; esac
      if [ "$hid" = true ]; then
        ( cd "$wd" && tar "-c${tf}${th}f" "$arc" "${items[@]}" )
      else
        ( cd "$wd" && _hid_find0 false 0 "${items[@]/#/./}" | tar "-c${tf}${th}f" "$arc" --null --no-recursion -T - )
      fi
      rc=$? ;;
    tarzst|tarlz4)
      if [ "$fmt" = tarzst ]; then filt=(zstd -q -c -T0); else filt=(lz4 -q -c); fi
      # tar writes to a pipe, the compressor to the file: a failure of either stage is a failure
      if [ "$hid" = true ]; then
        ( cd "$wd" || exit 1
          tar "-c${th}f" - "${items[@]}" | "${filt[@]}" > "$arc"
          ps=("${PIPESTATUS[@]}"); [ "${ps[0]}" -eq 0 ] && [ "${ps[1]}" -eq 0 ] )
      else
        ( cd "$wd" || exit 1
          _hid_find0 false 0 "${items[@]/#/./}" | tar "-c${th}f" - --null --no-recursion -T - | "${filt[@]}" > "$arc"
          ps=("${PIPESTATUS[@]}"); [ "${ps[1]}" -eq 0 ] && [ "${ps[2]}" -eq 0 ] )
      fi
      rc=$? ;;
    7z)
      _arc_7z || return 1
      _arc_7z_follow "$follow"
      if [ "$hid" = true ]; then
        ( cd "$wd" && "$_ARC_7Z" a -y -bd -spd "${_ARC_7Z_FOLLOW[@]}" "$arc" -- "${items[@]}" )
      else
        local lst; lst="$(mktemp "${TMPDIR:-/tmp}/bvk7z.XXXXXX")" || return 1
        # 7-Zip walks into every folder it is handed, so the list names files and EMPTY folders only (the hidden ones are already gone from it)
        ( cd "$wd" || exit 1
          while IFS= read -r -d '' e; do
            if [ -d "$e" ] && [ -n "$(ls -A -- "$e" 2>/dev/null)" ]; then continue; fi
            printf '%s\n' "${e#./}"
          done < <(_hid_find0 false 0 "${items[@]/#/./}") > "$lst"
          "$_ARC_7Z" a -y -bd -spd -r- -scsUTF-8 "${_ARC_7Z_FOLLOW[@]}" "$arc" @"$lst" )
        rc=$?; rm -f -- "$lst"; return $rc
      fi
      rc=$? ;;
    *) echo "❌ Unknown archive format: $fmt"; return 1 ;;
  esac
  [ $rc -ne 0 ] && rm -f -- "$arc" 2>/dev/null            # a half-written archive is worse than none
  return $rc
}

# ── opening an archive ──────────────────────────────────────────────────────
_arc_extract() {
  local fmt="$1" arc="$2" dest="$3" rc=0
  local -a ps=()
  case "$fmt" in
    zip|skill)
      if command -v unzip >/dev/null 2>&1; then unzip -q "$arc" -d "$dest"; rc=$?
      else _arc_7z && "$_ARC_7Z" x -y -bd -o"$dest" -- "$arc"; rc=$?; fi ;;
    tar)    tar -xf  "$arc" -C "$dest"; rc=$? ;;
    targz)  tar -xzf "$arc" -C "$dest"; rc=$? ;;
    tarxz)  tar -xJf "$arc" -C "$dest"; rc=$? ;;
    tarbz2) tar -xjf "$arc" -C "$dest"; rc=$? ;;
    tarzst) zstd -q -d -c -- "$arc" | tar -xf - -C "$dest"; ps=("${PIPESTATUS[@]}"); rc=$(( ps[0] != 0 ? ps[0] : ps[1] )) ;;
    tarlz4) lz4 -q -d -c -- "$arc"  | tar -xf - -C "$dest"; ps=("${PIPESTATUS[@]}"); rc=$(( ps[0] != 0 ? ps[0] : ps[1] )) ;;
    7z)     _arc_7z && "$_ARC_7Z" x -y -bd -o"$dest" -- "$arc"; rc=$? ;;
    *)      echo "❌ Unknown archive format: $fmt"; return 1 ;;
  esac
  return $rc
}
