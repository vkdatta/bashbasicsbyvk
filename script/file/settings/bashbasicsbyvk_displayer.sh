# bashbasicsbyvk_displayer.sh
# ════════════════════════════════════════════════════════════════════════════
# Windowed just-in-time displayer.
#
# Architecture
# ────────────
#   Layer 1  — Name index   : full sorted list of paths, names only.
#                             Built by one Python os.scandir() call (~30ms
#                             for 10k entries). No stat. No metadata.
#
#   Layer 2  — Hot window   : ±_BVK_WIN_RADIUS rows around the viewport.
#                             Metadata (size, mtime, icon, children) fetched
#                             by one batched Python stat call per window shift.
#                             Stored in item_size / item_mtime / item_icon /
#                             item_children associative arrays, keyed by path.
#                             Entries outside the window are evicted.
#
#   Layer 3  — On-demand    : Recursive dir size only when user explicitly
#                             enables "size" suffix AND hovers a dir long
#                             enough. Never computed eagerly.
#
# Python is called via embedded heredocs — no external .py files, no daemon,
# no disk cache, no background processes left behind.
#
# Public interface (unchanged from the old displayer)
# ────────────────────────────────────────────────────
#   build_items_with_meta  dir [prefix]  — populate items[]
#   apply_sort                           — sort items[] per sort_mode
#   display_items                        — render visible rows
#   _collect_metadata                    — (now: load window around _hl_index)
#   _ensure_meta                         — (now: idempotent window check)
#   sort_order_settings                  — settings UI
#   display_suffix_settings              — settings UI
#   group_view_settings                  — settings UI
#   _filter_*                            — live prefix filter
# ════════════════════════════════════════════════════════════════════════════

# ── Core arrays ───────────────────────────────────────────────────────────────

declare -gA item_size=()
declare -gA item_mtime=()
declare -gA item_icon=()       # dir|archive|image|plugin|exec|plain|shortcut
declare -gA item_children=()   # -1 for files, ≥0 for dirs
declare -g  _meta_loaded=false
declare -g  _hl_index=0

# Window tracking — which band of items[] has real metadata right now.
declare -g _win_lo=0   # 1-based, inclusive
declare -g _win_hi=0   # 1-based, inclusive
_BVK_WIN_RADIUS=60     # load this many rows above and below viewport centre

# ── Rendering helpers ─────────────────────────────────────────────────────────

_bold()        { printf '\033[1m%s\033[0m'   "$1"; }
_highlight()   { printf '\033[1;7m%s\033[0m' "$1"; }
_highlight_v() { _hl_out=$'\033[1;7m'"$1"$'\033[0m'; }

# ── Icon detection (bash — used only in the window-fetch fallback) ─────────────

_is_archive() {
  local lower="${1##*/}"; lower="${lower,,}"
  case "$lower" in
    *.tar.gz|*.tar.bz2|*.tar.xz|*.tar.zst|*.tar.lz|*.tar.lzma|*.tar.lz4|*.tar.Z|*.tar.sz|*.tar.br) return 0 ;;
    *.zip|*.7z|*.rar|*.tar|*.tgz|*.tbz|*.tbz2|*.txz|*.tzst) return 0 ;;
    *.gz|*.bz2|*.xz|*.zst|*.lz|*.lzma|*.lz4|*.Z|*.zz|*.br|*.sz) return 0 ;;
    *.jar|*.war|*.ear|*.apk|*.aab|*.ipa) return 0 ;;
    *.deb|*.rpm|*.pkg|*.snap|*.flatpak) return 0 ;;
    *.dmg|*.iso|*.img|*.wim|*.cab) return 0 ;;
    *.arj|*.lzh|*.lha|*.ace|*.arc|*.zoo|*.sit|*.sitx|*.sea) return 0 ;;
    *.cpio|*.shar|*.pax|*.hqx|*.bin) return 0 ;;
    *) return 1 ;;
  esac
}

_is_image() {
  local lower="${1##*/}"; lower="${lower,,}"
  case "$lower" in
    *.jpg|*.jpeg|*.png|*.gif|*.bmp|*.tif|*.tiff|*.webp|*.avif|*.heic|*.heif) return 0 ;;
    *.ico|*.cur|*.psd|*.psb|*.xcf|*.ppm|*.pgm|*.pbm|*.pnm|*.pfm|*.pam|*.xbm|*.xpm|*.tga) return 0 ;;
    *.dds|*.exr|*.hdr|*.sgi|*.rgb|*.rgba|*.svg|*.svgz|*.ai|*.eps) return 0 ;;
    *.raw|*.cr2|*.cr3|*.nef|*.nrw|*.arw|*.srf|*.sr2|*.orf|*.rw2|*.rwl) return 0 ;;
    *.pef|*.ptx|*.dng|*.raf|*.mrw|*.dcr|*.kdc|*.erf|*.x3f|*.srw|*.bay) return 0 ;;
    *.apng|*.flif|*.jxl|*.jp2|*.jpx|*.j2k|*.jpf|*.jpm|*.mj2) return 0 ;;
    *) return 1 ;;
  esac
}

_is_executable() {
  local lower="${1##*/}"; lower="${lower,,}"
  [ -x "$1" ] && [ -f "$1" ] && return 0
  case "$lower" in
    *.sh|*.bash|*.zsh|*.fish|*.ksh|*.csh|*.tcsh|*.dash) return 0 ;;
    *.py|*.pyc|*.pyo|*.pyw|*.rb|*.pl|*.pm|*.lua|*.tcl|*.tk) return 0 ;;
    *.js|*.mjs|*.cjs|*.ts|*.mts|*.cts) return 0 ;;
    *.class|*.jar|*.exe|*.com|*.out|*.elf|*.o|*.a|*.lib) return 0 ;;
    *.bat|*.cmd|*.ps1|*.psm1|*.psd1|*.vbs|*.vbe|*.wsf|*.wsh) return 0 ;;
    *.app|*.command|*.run|*.wasm|*.beam|*.elc|*.rbc|*.luac) return 0 ;;
    *) return 1 ;;
  esac
}

_is_plugin() {
  local lower="${1##*/}"; lower="${lower,,}"
  case "$lower" in
    *.crx|*.xpi|*.safariextz|*.vsix|*.visx|*.natvis|*.sublime-package) return 0 ;;
    *.plugin|*.bundle|*.kext|*.mdimporter) return 0 ;;
    *.addon|*.addin|*.adp|*.vst|*.vst3|*.au|*.lv2|*.ladspa|*.dssi) return 0 ;;
    *.sketchplugin|*.figma|*.xdx) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Python helpers — embedded, called via process substitution ────────────────
#
# _PY_SCAN  : given a directory, returns sorted name-only index.
#             Output: one absolute path per line.
#             sort_mode is passed as $1 so Python can sort by name without
#             any stat calls (az/za). For mtime/size sorts Python does one
#             os.scandir() with stat-from-DirEntry (free on Linux).
#
# _PY_META  : given a list of paths on stdin, returns pipe-delimited metadata.
#             Output: path|size_bytes|mtime_epoch|children|icon_type
#             children=-1 for files; for dirs it is a shallow scandir count
#             (NOT recursive) — fast and sufficient for the display column.
#             Recursive size is never computed here.

_py_scan_script() {
# One heredoc, no temp file, called as:  python3 <(_py_scan_script) DIR MODE HIDDEN PFX
python3 - "$@" <<'PYEOF'
import os, sys, stat as st_mod

dirpath  = sys.argv[1]
mode     = sys.argv[2]          # az za new old big small
hidden   = sys.argv[3] == "1"   # show hidden files
pfx      = sys.argv[4].lower() if len(sys.argv) > 4 else ""

_ARCHIVE_MULTI = (".tar.gz",".tar.bz2",".tar.xz",".tar.zst",".tar.lz",
                  ".tar.lzma",".tar.lz4",".tar.z",".tar.sz",".tar.br")
_ARCHIVE = frozenset((".zip",".7z",".rar",".tar",".tgz",".tbz",".tbz2",".txz",".tzst",
    ".gz",".bz2",".xz",".zst",".lz",".lzma",".lz4",".z",".zz",".br",".sz",
    ".jar",".war",".ear",".apk",".aab",".ipa",".deb",".rpm",".pkg",".snap",".flatpak",
    ".dmg",".iso",".img",".wim",".cab",".arj",".lzh",".lha",".ace",".arc",".zoo",
    ".sit",".sitx",".sea",".cpio",".shar",".pax",".hqx",".bin"))
_IMAGE  = frozenset((".jpg",".jpeg",".png",".gif",".bmp",".tif",".tiff",".webp",
    ".avif",".heic",".heif",".ico",".cur",".psd",".psb",".xcf",".ppm",".pgm",
    ".pbm",".pnm",".pfm",".pam",".xbm",".xpm",".tga",".dds",".exr",".hdr",
    ".sgi",".rgb",".rgba",".svg",".svgz",".ai",".eps",".raw",".cr2",".cr3",
    ".nef",".nrw",".arw",".srf",".sr2",".orf",".rw2",".rwl",".pef",".ptx",
    ".dng",".raf",".mrw",".dcr",".kdc",".erf",".x3f",".srw",".bay",
    ".apng",".flif",".jxl",".jp2",".jpx",".j2k",".jpf",".jpm",".mj2"))
_PLUGIN = frozenset((".crx",".xpi",".safariextz",".vsix",".visx",".natvis",
    ".sublime-package",".plugin",".bundle",".kext",".mdimporter",
    ".addon",".addin",".adp",".vst",".vst3",".au",".lv2",".ladspa",".dssi",
    ".sketchplugin",".figma",".xdx"))
_EXEC   = frozenset((".sh",".bash",".zsh",".fish",".ksh",".csh",".tcsh",".dash",
    ".py",".pyc",".pyo",".pyw",".rb",".pl",".pm",".lua",".tcl",".tk",
    ".js",".mjs",".cjs",".ts",".mts",".cts",".class",".jar",
    ".exe",".com",".out",".elf",".o",".a",".lib",
    ".bat",".cmd",".ps1",".psm1",".psd1",".vbs",".vbe",".wsf",".wsh",
    ".app",".command",".run",".wasm",".beam",".elc",".rbc",".luac"))

def icon(name, is_dir, mode_bits):
    if name.endswith(".shortcut"): return "shortcut"
    if is_dir: return "dir"
    lo = name.lower()
    for m in _ARCHIVE_MULTI:
        if lo.endswith(m): return "archive"
    dot = lo.rfind(".")
    ext = lo[dot:] if dot >= 0 else ""
    if ext in _ARCHIVE: return "archive"
    if ext in _IMAGE:   return "image"
    if ext in _PLUGIN:  return "plugin"
    if ext in _EXEC or bool(mode_bits & 0o111): return "exec"
    return "plain"

needs_stat = mode in ("new","old","big","small")

entries = []
try:
    with os.scandir(dirpath) as it:
        for e in it:
            try:
                bn = e.name
                if not hidden and bn.startswith("."): continue
                if pfx and not bn.lower().startswith(pfx): continue
                if needs_stat:
                    s   = e.stat(follow_symlinks=True)
                    sz  = s.st_size if not e.is_dir(follow_symlinks=True) else 0
                    mt  = s.st_mtime
                    ic  = icon(bn, e.is_dir(follow_symlinks=True), s.st_mode)
                    entries.append((e.path, bn.lower(), sz, mt, ic))
                else:
                    entries.append((e.path, bn.lower(), 0, 0.0, ""))
            except Exception:
                pass
except Exception as ex:
    sys.stderr.write(f"scan error: {ex}\n")
    sys.exit(1)

# Sort
if   mode == "az":    entries.sort(key=lambda x: x[1])
elif mode == "za":    entries.sort(key=lambda x: x[1], reverse=True)
elif mode == "new":   entries.sort(key=lambda x: x[3], reverse=True)
elif mode == "old":   entries.sort(key=lambda x: x[3])
elif mode == "big":   entries.sort(key=lambda x: x[2], reverse=True)
elif mode == "small": entries.sort(key=lambda x: x[2])

for e in entries:
    print(e[0])
PYEOF
}

_py_meta_script() {
# Reads absolute paths from $1 file, writes pipe-delimited metadata to stdout.
python3 - "$1" <<'PYEOF'
import os, sys, stat as st_mod

paths_file = sys.argv[1]

_ARCHIVE_MULTI = (".tar.gz",".tar.bz2",".tar.xz",".tar.zst",".tar.lz",
                  ".tar.lzma",".tar.lz4",".tar.z",".tar.sz",".tar.br")
_ARCHIVE = frozenset((".zip",".7z",".rar",".tar",".tgz",".tbz",".tbz2",".txz",".tzst",
    ".gz",".bz2",".xz",".zst",".lz",".lzma",".lz4",".z",".zz",".br",".sz",
    ".jar",".war",".ear",".apk",".aab",".ipa",".deb",".rpm",".pkg",".snap",".flatpak",
    ".dmg",".iso",".img",".wim",".cab",".arj",".lzh",".lha",".ace",".arc",".zoo",
    ".sit",".sitx",".sea",".cpio",".shar",".pax",".hqx",".bin"))
_IMAGE  = frozenset((".jpg",".jpeg",".png",".gif",".bmp",".tif",".tiff",".webp",
    ".avif",".heic",".heif",".ico",".cur",".psd",".psb",".xcf",".ppm",".pgm",
    ".pbm",".pnm",".pfm",".pam",".xbm",".xpm",".tga",".dds",".exr",".hdr",
    ".sgi",".rgb",".rgba",".svg",".svgz",".ai",".eps",".raw",".cr2",".cr3",
    ".nef",".nrw",".arw",".srf",".sr2",".orf",".rw2",".rwl",".pef",".ptx",
    ".dng",".raf",".mrw",".dcr",".kdc",".erf",".x3f",".srw",".bay",
    ".apng",".flif",".jxl",".jp2",".jpx",".j2k",".jpf",".jpm",".mj2"))
_PLUGIN = frozenset((".crx",".xpi",".safariextz",".vsix",".visx",".natvis",
    ".sublime-package",".plugin",".bundle",".kext",".mdimporter",
    ".addon",".addin",".adp",".vst",".vst3",".au",".lv2",".ladspa",".dssi",
    ".sketchplugin",".figma",".xdx"))
_EXEC   = frozenset((".sh",".bash",".zsh",".fish",".ksh",".csh",".tcsh",".dash",
    ".py",".pyc",".pyo",".pyw",".rb",".pl",".pm",".lua",".tcl",".tk",
    ".js",".mjs",".cjs",".ts",".mts",".cts",".class",".jar",
    ".exe",".com",".out",".elf",".o",".a",".lib",
    ".bat",".cmd",".ps1",".psm1",".psd1",".vbs",".vbe",".wsf",".wsh",
    ".app",".command",".run",".wasm",".beam",".elc",".rbc",".luac"))

def icon(name, is_dir, mode_bits):
    if name.endswith(".shortcut"): return "shortcut"
    if is_dir: return "dir"
    lo = name.lower()
    for m in _ARCHIVE_MULTI:
        if lo.endswith(m): return "archive"
    dot = lo.rfind(".")
    ext = lo[dot:] if dot >= 0 else ""
    if ext in _ARCHIVE: return "archive"
    if ext in _IMAGE:   return "image"
    if ext in _PLUGIN:  return "plugin"
    if ext in _EXEC or bool(mode_bits & 0o111): return "exec"
    return "plain"

def children_count(path):
    try:
        return sum(1 for _ in os.scandir(path))
    except Exception:
        return -1

with open(paths_file) as fh:
    paths = [l.rstrip("\n") for l in fh if l.strip()]

out = []
for p in paths:
    try:
        s       = os.stat(p, follow_symlinks=True)
        is_dir  = st_mod.S_ISDIR(s.st_mode)
        sz      = 0 if is_dir else s.st_size
        mt      = int(s.st_mtime)
        ch      = children_count(p) if is_dir else -1
        ic      = icon(os.path.basename(p), is_dir, s.st_mode)
        out.append(f"{p}|{sz}|{mt}|{ch}|{ic}")
    except Exception:
        out.append(f"{p}|0|0|-1|plain")

sys.stdout.write("\n".join(out) + "\n")
PYEOF
}

# ── build_items_with_meta — Layer 1: name index only ─────────────────────────
#
# Calls _py_scan_script which does one os.scandir(), sorts by the current
# sort_mode, and prints one absolute path per line.
# For az/za: ~30–50ms for 10k.  For new/old/big/small: ~80–150ms for 10k
# (stat is free from DirEntry on Linux).
# No metadata arrays are filled here — that happens lazily in _load_window.

build_items_with_meta() {
  local p="$1"
  local pfx="${2:-}"
  items=()
  item_size=()
  item_mtime=()
  item_icon=()
  item_children=()
  _meta_loaded=false
  _win_lo=0
  _win_hi=0

  local hidden_flag=0
  $show_hidden_files && hidden_flag=1
  local mode="${sort_mode:-az}"

  while IFS= read -r line; do
    [ -n "$line" ] && items+=("$line")
  done < <(_py_scan_script "$p" "$mode" "$hidden_flag" "$pfx" 2>/dev/null)
}

# apply_sort — re-sort items[] that are already loaded.
# For az/za sorts by bash (cheap, names already in items[]).
# For metadata sorts, calls Python again on the current items[] list.
# This keeps apply_sort a no-op when build_items_with_meta already sorted.
apply_sort() {
  local mode="${sort_mode:-az}"
  [ ${#items[@]} -eq 0 ] && return

  # az/za: bash sort on basename is fast enough for any realistic items[] size
  case "$mode" in
    az|za)
      local flag; [ "$mode" = "za" ] && flag="-r" || flag=""
      local sorted_output
      sorted_output=$(for f in "${items[@]}"; do
                        local k="${f##*/}"
                        if [[ "$k" == *.shortcut ]]; then
                          local sn; sn=$(_shortcut_read_field "$f" "SHORTCUT_NAME" 2>/dev/null)
                          [ -n "$sn" ] && k="$sn"
                        fi
                        printf '%s\t%s\n' "$k" "$f"
                      done | sort -f $flag -t$'\t' -k1,1 | cut -f2-)
      items=()
      while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done <<< "$sorted_output"
      ;;
    new|old|big|small)
      # Python re-sort using DirEntry stat (free on Linux)
      local hidden_flag=0; $show_hidden_files && hidden_flag=1
      # We already have items[]; just ask Python to stat and sort them.
      local tmp_in; tmp_in=$(mktemp)
      printf '%s\n' "${items[@]}" > "$tmp_in"
      local sorted_output
      sorted_output=$(python3 - "$tmp_in" "$mode" <<'PYEOF'
import os, sys
paths_file = sys.argv[1]
mode       = sys.argv[2]
with open(paths_file) as fh:
    paths = [l.rstrip("\n") for l in fh if l.strip()]
records = []
for p in paths:
    try:
        s      = os.stat(p, follow_symlinks=True)
        is_dir = os.path.isdir(p)
        sz     = 0 if is_dir else s.st_size
        mt     = s.st_mtime
        records.append((p, sz, mt))
    except Exception:
        records.append((p, 0, 0.0))
if   mode == "new":   records.sort(key=lambda x: x[2], reverse=True)
elif mode == "old":   records.sort(key=lambda x: x[2])
elif mode == "big":   records.sort(key=lambda x: x[1], reverse=True)
elif mode == "small": records.sort(key=lambda x: x[1])
for r in records:
    print(r[0])
PYEOF
      )
      rm -f "$tmp_in"
      items=()
      while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done <<< "$sorted_output"
      ;;
  esac

  # Window is now stale — clear it so next render re-fetches.
  _win_lo=0; _win_hi=0
  item_size=(); item_mtime=(); item_icon=(); item_children=()
  _meta_loaded=false
}

# ── _load_window — Layer 2: fetch metadata for centre ± radius ────────────────
#
# centre: 1-based index (usually _hl_index or the middle of the viewport).
# Fetches metadata for [lo..hi] from items[], skipping paths already loaded.
# Uses one Python call for the whole batch → one round-trip to the kernel.

_load_window() {
  local centre="${1:-1}"
  local n="${#items[@]}"
  [ "$n" -eq 0 ] && return

  local lo=$(( centre - _BVK_WIN_RADIUS ))
  local hi=$(( centre + _BVK_WIN_RADIUS ))
  (( lo < 1 )) && lo=1
  (( hi > n )) && hi=$n

  # Nothing to do if this band is already loaded.
  if (( _win_lo > 0 && lo >= _win_lo && hi <= _win_hi )); then
    return
  fi

  # Collect paths in [lo..hi] that don't have metadata yet.
  local tmp_in; tmp_in=$(mktemp)
  local i
  for (( i=lo; i<=hi; i++ )); do
    local f="${items[$((i-1))]}"
    [ -z "${item_size[$f]+x}" ] && printf '%s\n' "$f"
  done > "$tmp_in"

  # If nothing is missing, skip the Python call.
  if [ ! -s "$tmp_in" ]; then
    rm -f "$tmp_in"
    _win_lo=$lo; _win_hi=$hi
    _meta_loaded=true
    return
  fi

  # One batched Python stat call.
  while IFS='|' read -r fpath fsize fmtime fchildren ftype; do
    [ -z "$fpath" ] && continue
    item_size["$fpath"]="$fsize"
    item_mtime["$fpath"]="$fmtime"
    item_children["$fpath"]="$fchildren"
    item_icon["$fpath"]="$ftype"
  done < <(_py_meta_script "$tmp_in" 2>/dev/null)
  rm -f "$tmp_in"

  # Evict entries outside [lo-radius .. hi+radius] to cap memory.
  local evict_lo=$(( lo - _BVK_WIN_RADIUS ))
  local evict_hi=$(( hi + _BVK_WIN_RADIUS ))
  if (( _win_lo > 0 )); then
    local j
    for (( j=_win_lo; j<lo; j++ )); do
      (( j < evict_lo )) || continue   # keep the extended buffer
      local pf="${items[$((j-1))]}"
      unset "item_size[$pf]" "item_mtime[$pf]" "item_icon[$pf]" "item_children[$pf]"
    done
    for (( j=hi+1; j<=_win_hi; j++ )); do
      (( j > evict_hi )) || continue
      local pf="${items[$((j-1))]}"
      unset "item_size[$pf]" "item_mtime[$pf]" "item_icon[$pf]" "item_children[$pf]"
    done
  fi

  _win_lo=$lo; _win_hi=$hi
  _meta_loaded=true
}

# ── _collect_metadata / _ensure_meta — public compat wrappers ─────────────────

_collect_metadata() {
  local centre="${_hl_index:-1}"
  (( centre < 1 )) && centre=1
  _load_window "$centre"
}

_ensure_meta() {
  # Called before render. Shift window to current highlight if needed.
  local centre="${_hl_index:-1}"
  (( centre < 1 )) && centre=1
  if (( _win_lo < 1 || centre < _win_lo || centre > _win_hi )); then
    _load_window "$centre"
  fi
}

_needs_metadata() {
  [[ " ${display_suffix_set:-} " == *" size "* ]] && return 0
  [[ " ${display_suffix_set:-} " == *" time "* ]] && return 0
  [[ " ${display_suffix_set:-} " == *" children "* ]] && return 0
  case "${sort_mode:-az}" in new|old|big|small) return 0 ;; esac
  for lvl in "${group_view_levels[@]}"; do
    case "$lvl" in year|month|date) return 0 ;; esac
  done
  return 1
}

# Recursive dir size is never auto-computed. Return placeholder if not ready.
_needs_dir_size() {
  [[ " ${display_suffix_set:-} " == *" size "* ]] && return 0
  case "${sort_mode:-az}" in big|small) return 0 ;; esac
  return 1
}

# ── Size / time formatters (zero-fork, variable-setting) ─────────────────────

_fmt_size_v() {
  local b="${1:-0}"
  if   (( b < 0 ));         then _fs_out="---"
  elif (( b < 1024 ));      then _fs_out="${b}B"
  elif (( b < 1048576 ));   then _fs_out="$(( b / 1024 ))K"
  elif (( b < 1073741824 )); then _fs_out="$(( b / 1048576 ))M"
  else                           _fs_out="$(( b / 1073741824 ))G"
  fi
}
_fmt_size() { local _fs_out; _fmt_size_v "$1"; printf '%s' "$_fs_out"; }

if printf -v _bvk_tfmt_probe '%(%Y)T' 0 2>/dev/null; then
  _BVK_HAS_TFMT=1
else
  _BVK_HAS_TFMT=0
fi
unset _bvk_tfmt_probe

_fmt_time_v() {
  local epoch="${1:-0}" f
  case "${2:-${display_time_format:-full}}" in
    year)      f='%Y'           ;;
    month)     f='%Y-%b'        ;;
    date)      f='%Y-%b-%d'     ;;
    datetime)  f='%d %H:%M'     ;;
    monthdate) f='%b-%d %H:%M'  ;;
    full|*)    f='%Y-%b-%d %H:%M' ;;
  esac
  if [ "$_BVK_HAS_TFMT" = 1 ]; then
    printf -v _ft_out "%($f)T" "$epoch"
  else
    _ft_out=$(date -d "@$epoch" "+$f")
  fi
}
_fmt_time() { local _ft_out; _fmt_time_v "$1"; printf '%s' "$_ft_out"; }

# ── Suffix builder — ext | size | time | children ────────────────────────────

_build_suffix_v() {
  local fpath="$1"
  local _fs_out _ft_out
  _bs_out=""
  local token bn
  for token in ${display_suffix_set:-}; do
    case "$token" in
      ext)
        bn="${fpath##*/}"
        if [[ "$bn" == *.shortcut ]]; then
          _bs_out+=" | →shortcut"
        else
          [[ "$bn" == *.* ]] && _bs_out+=" | .${bn##*.}" || _bs_out+=" | (no ext)"
        fi
        ;;
      size)
        local sz="${item_size[$fpath]:-}"
        if [ -z "$sz" ]; then
          _bs_out+=" | ..."
        else
          # Dirs: size from metadata is flat inode size (0 if unknown).
          # Show "---" to signal that recursive size is not computed,
          # rather than a misleading "0B".
          if [ -d "$fpath" ] && (( sz == 0 )); then
            _bs_out+=" | ---"
          else
            _fmt_size_v "$sz"
            _bs_out+=" | $_fs_out"
          fi
        fi
        ;;
      time)
        local mt="${item_mtime[$fpath]:-}"
        if [ -z "$mt" ]; then
          _bs_out+=" | ..."
        else
          _fmt_time_v "$mt"
          _bs_out+=" | $_ft_out"
        fi
        ;;
      children)
        local ch="${item_children[$fpath]:-}"
        if [ -z "$ch" ]; then
          _bs_out+=" | ..."
        elif (( ch < 0 )); then
          : # file — no children token shown
        else
          _bs_out+=" | ${ch} items"
        fi
        ;;
    esac
  done
}
_build_suffix() { local _bs_out; _build_suffix_v "$1"; printf '%s' "$_bs_out"; }

# ── Icon resolution — reads item_icon[] set by Python; bash fallback ──────────

_resolve_display_parts_v() {
  local f="$1"
  _rdp_bn="${f##*/}"
  if [[ "$_rdp_bn" == *.shortcut ]]; then
    _shortcut_display_parts "$f"
    _rdp_icon="$_sc_icon"
    _rdp_bn="$_sc_display"
    return
  fi
  local ic="${item_icon[$f]:-}"
  if [ -n "$ic" ]; then
    case "$ic" in
      dir)      _rdp_icon="📁" ;;
      archive)  _rdp_icon="📦" ;;
      image)    _rdp_icon="🌄" ;;
      plugin)   _rdp_icon="🧩" ;;
      exec)     _rdp_icon="⚙️"  ;;
      *)        _rdp_icon="📄" ;;
    esac
  else
    # Metadata not loaded yet for this row — use type-check fallback.
    if   [ -d "$f" ];         then _rdp_icon="📁"
    elif _is_archive "$f";    then _rdp_icon="📦"
    elif _is_image   "$f";    then _rdp_icon="🌄"
    elif _is_plugin  "$f";    then _rdp_icon="🧩"
    elif _is_executable "$f"; then _rdp_icon="⚙️"
    else                           _rdp_icon="📄"
    fi
  fi
}

# ── Shortcut display ──────────────────────────────────────────────────────────

_shortcut_display_parts() {
  local sc_file="$1"
  local sc_type sc_name sc_target
  sc_type=$(_shortcut_read_field "$sc_file" "SHORTCUT_TYPE")
  sc_name=$(_shortcut_read_field "$sc_file" "SHORTCUT_NAME")
  sc_target=$(_shortcut_read_field "$sc_file" "SHORTCUT_TARGET")
  [ -z "$sc_name" ] && sc_name="${sc_file##*/}" && sc_name="${sc_name%.shortcut}"
  local _broken=""
  [ -n "$sc_target" ] && [ ! -e "$sc_target" ] && _broken=" ⚠️ (broken)"
  if [ "$sc_type" == "dir" ]; then _sc_icon="🔑"; else _sc_icon="🗝️"; fi
  _sc_display="${sc_name}${_broken}"
}

# ── Row text helpers ──────────────────────────────────────────────────────────

_item_line_text()   { _item_line_text_v "$1"; printf '%s' "$_ilt_out"; }
_item_line_text_v() {
  local target="$1"
  local _rdp_icon _rdp_bn _sc_icon _sc_display _bs_out
  _ilt_out=""
  (( target < 1 || target > ${#items[@]} )) && return
  local f="${items[$((target-1))]}"
  _resolve_display_parts_v "$f"
  if [ -n "${display_suffix_set:-}" ]; then _build_suffix_v "$f"; else _bs_out=""; fi
  printf -v _ilt_out " %2d) %s %s%s" "$target" "$_rdp_icon" "$_rdp_bn" "$_bs_out"
}

# ── Flat display ──────────────────────────────────────────────────────────────

_display_items_flat() {
  local idx=1 f line
  local _rdp_icon _rdp_bn _sc_icon _sc_display _bs_out
  local want_suffix=0
  [ -n "${display_suffix_set:-}" ] && want_suffix=1
  local hl="${_hl_index:-0}"
  for f in "${items[@]}"; do
    _resolve_display_parts_v "$f"
    if [ "$want_suffix" = 1 ]; then _build_suffix_v "$f"; else _bs_out=""; fi
    printf -v line " %2d) %s %s%s" "$idx" "$_rdp_icon" "$_rdp_bn" "$_bs_out"
    if [ "$idx" -eq "$hl" ]; then
      _highlight_v "$line"; printf '%s\n' "$_hl_out"
    else
      printf '%s\n' "$line"
    fi
    idx=$(( idx + 1 ))
  done
}

# ── Grouped display ───────────────────────────────────────────────────────────

_gk_ext()   {
  local bn="${1##*/}"
  [[ "$bn" == *.shortcut ]] && { printf '[shortcut]'; return; }
  [ -d "$1" ] && { printf '[dir]'; return; }
  [[ "$bn" == *.* ]] && printf '.%s' "${bn##*.}" || printf '(no ext)'
}
_gk_year()  { local _ft_out; _fmt_time_v "${item_mtime[$1]:-0}" year;  printf '%s' "$_ft_out"; }
_gk_month() { local _ft_out; _fmt_time_v "${item_mtime[$1]:-0}" month; printf '%s' "$_ft_out"; }
_gk_date()  { local _ft_out; _fmt_time_v "${item_mtime[$1]:-0}" date;  printf '%s' "$_ft_out"; }

_composite_key() {
  local f="$1" key=""
  for lvl in "${group_view_levels[@]}"; do
    case "$lvl" in
      ext)   key+="$(_gk_ext   "$f")|" ;;
      year)  key+="$(_gk_year  "$f")|" ;;
      month) key+="$(_gk_month "$f")|" ;;
      date)  key+="$(_gk_date  "$f")|" ;;
    esac
  done
  printf '%s' "$key"
}

_display_grouped() {
  local depth="${#group_view_levels[@]}"
  [ "$depth" -eq 0 ] && { _display_items_flat; return; }

  local -a all_keys=()
  declare -A key_seen=()
  declare -A key_items=()
  for f in "${items[@]}"; do
    local ck; ck=$(_composite_key "$f")
    [ -z "${key_seen[$ck]+x}" ] && { all_keys+=("$ck"); key_seen["$ck"]=1; }
    key_items["$ck"]+="$f"$'\n'
  done

  local global_idx=1 ck f indent indent_items lvl_idx lvl part line
  local -a parts
  local _rdp_icon _rdp_bn _sc_icon _sc_display _bs_out

  for ck in "${all_keys[@]}"; do
    IFS='|' read -ra parts <<< "$ck"
    lvl_idx=0
    for lvl in "${group_view_levels[@]}"; do
      indent=$(printf '%*s' "$(( lvl_idx * 2 ))" '')
      printf "%s── %s: %s\n" "$indent" "${lvl^^}" "${parts[$lvl_idx]:-?}"
      lvl_idx=$(( lvl_idx + 1 ))
    done
    indent_items=$(printf '%*s' "$(( depth * 2 ))" '')
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      _resolve_display_parts_v "$f"
      if [ -n "${display_suffix_set:-}" ]; then _build_suffix_v "$f"; else _bs_out=""; fi
      printf -v line "%s%2d) %s %s%s" "$indent_items" "$global_idx" "$_rdp_icon" "$_rdp_bn" "$_bs_out"
      if [ "$global_idx" -eq "${_hl_index:-0}" ]; then
        _highlight_v "$line"; printf '%s\n' "$_hl_out"
      else
        printf '%s\n' "$line"
      fi
      global_idx=$(( global_idx + 1 ))
    done <<< "${key_items[$ck]}"
    echo
  done
}

# ── display_items — public entry point ────────────────────────────────────────

display_items() {
  if [ ${#items[@]} -eq 0 ]; then
    echo "🛑 This directory is empty"
    return
  fi
  if _needs_metadata; then
    _ensure_meta
  fi
  local use_group=false
  [ "${#group_view_levels[@]}" -gt 0 ] && ! ${imaginary_mode:-false} && use_group=true
  if $use_group; then _display_grouped; else _display_items_flat; fi
}

# ── Multi-select parser ───────────────────────────────────────────────────────

_parse_multi_select() {
  local input="$1" max="$2"
  local -A seen=(); local -a out=()
  IFS=',' read -ra parts <<< "$input"
  for part in "${parts[@]}"; do
    part="${part// /}"
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local s="${BASH_REMATCH[1]}" e="${BASH_REMATCH[2]}"
      (( s > e )) && { local tmp=$s; s=$e; e=$tmp; }
      for (( i=s; i<=e && i<=max; i++ )); do
        [ -z "${seen[$i]+x}" ] && out+=("$i") && seen[$i]=1
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      (( part >= 1 && part <= max )) && [ -z "${seen[$part]+x}" ] && out+=("$part") && seen[$part]=1
    fi
  done
  printf '%s\n' "${out[@]}" | sort -n | tr '\n' ' '
}

# ── Sort order settings UI ────────────────────────────────────────────────────

sort_order_settings() {
  local modes=("az" "za" "new" "old" "big" "small")
  local labels=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")
  echo
  echo "Sort order (current: ${sort_mode}):"
  for i in "${!modes[@]}"; do
    local num=$(( i+1 ))
    if [ "${modes[$i]}" = "$sort_mode" ]; then
      printf " %d) $(_green "${labels[$i]} ✓")\n" "$num"
    else
      printf " %d) %s\n" "$num" "${labels[$i]}"
    fi
  done
  read -r -p "Choice [1-6] (blank = no change): " c
  if [[ "$c" =~ ^[1-6]$ ]]; then
    sort_mode="${modes[$((c-1))]}"
    save_settings
    echo "✅ Sort mode set to: ${labels[$((c-1))]}"
  else
    echo "No change"
  fi
}

# ── Display suffix settings UI ────────────────────────────────────────────────

_show_suffix_state() {
  local tokens=("ext" "size" "time" "children")
  local labels=("Extension (.sh)" "File size (4.2K  — dirs show --- until computed)" "Modified time" "Children count (dirs only)")
  echo
  echo "Display suffix components:"
  for i in "${!tokens[@]}"; do
    local num=$(( i+1 )) tok="${tokens[$i]}"
    if [[ " $display_suffix_set " == *" $tok "* ]]; then
      printf " %d) $(_green "${labels[$i]} ✓")\n" "$num"
    else
      printf " %d) %s\n" "$num" "${labels[$i]}"
    fi
  done
}

_show_time_format_state() {
  echo
  echo "Time format (used when time is enabled):"
  local tfmts=("year" "month" "date" "datetime" "monthdate" "full")
  local tlabels=("Year only (2023)" "Month only (Mar)" "Date only (15)" \
    "Date+Time (15 14:32)" "Month+Date+Time (Mar-15 14:32)" "Full (2023-Mar-15 14:32)")
  for i in "${!tfmts[@]}"; do
    local num=$(( i+1 ))
    if [ "${tfmts[$i]}" = "$display_time_format" ]; then
      printf "  %d) $(_green "${tlabels[$i]} ✓")\n" "$num"
    else
      printf "  %d) %s\n" "$num" "${tlabels[$i]}"
    fi
  done
}

display_suffix_settings() {
  local tokens=("ext" "size" "time" "children")
  local tfmts=("year" "month" "date" "datetime" "monthdate" "full")

  while true; do
    _show_suffix_state
    echo
    echo "a) Add components   r) Remove components   t) Set time format"
    echo "n) Clear all (none)   q) Done"
    read -r -p "Action: " action
    action="${action,,}"

    case "$action" in
      q) break ;;

      n)
        display_suffix_set=""
        save_settings
        echo "✅ All suffixes cleared"
        ;;

      a)
        echo "Add by number (comma/range, e.g. 1,3 or 1-4):"
        read -r -p "Numbers: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel; sel=$(_parse_multi_select "$inp" 4)
        local changed=false
        for n in $sel; do
          local tok="${tokens[$((n-1))]}"
          if [[ " $display_suffix_set " != *" $tok "* ]]; then
            display_suffix_set="${display_suffix_set:+$display_suffix_set }$tok"
            changed=true
          fi
        done
        display_suffix_set="${display_suffix_set## }"
        display_suffix_set="${display_suffix_set%% }"
        $changed && save_settings && echo "✅ Added" || echo "Already set — no change"
        ;;

      r)
        if [ -z "$display_suffix_set" ]; then echo "Nothing to remove"; continue; fi
        echo "Remove by number (comma/range):"
        read -r -p "Numbers: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel; sel=$(_parse_multi_select "$inp" 4)
        local changed=false
        for n in $sel; do
          local tok="${tokens[$((n-1))]}"
          if [[ " $display_suffix_set " == *" $tok "* ]]; then
            display_suffix_set="${display_suffix_set//$tok/}"
            changed=true
          fi
        done
        read -ra _arr <<< "$display_suffix_set"
        display_suffix_set="${_arr[*]}"
        $changed && save_settings && echo "✅ Removed" || echo "Not present — no change"
        ;;

      t)
        _show_time_format_state
        echo "Set time format [1-6] (blank = no change):"
        read -r -p "Choice: " tc
        if [[ "$tc" =~ ^[1-6]$ ]]; then
          display_time_format="${tfmts[$((tc-1))]}"
          save_settings
          echo "✅ Time format set"
        else
          echo "No change"
        fi
        ;;

      *) echo "⚠️  Invalid action. Use a/r/t/n/q" ;;
    esac
  done
}

# ── Group view settings UI ────────────────────────────────────────────────────

_valid_level() { case "$1" in ext|year|month|date) return 0 ;; *) return 1 ;; esac }

_show_group_state() {
  local all_levels=("ext" "year" "month" "date")
  local all_labels=("Extension" "Year" "Month" "Date")
  echo
  if [ ${#group_view_levels[@]} -eq 0 ]; then
    echo "Group view: OFF"
  else
    echo "Group view chain: ${group_view_levels[*]}"
  fi
  echo
  echo "Available levels:"
  for i in "${!all_levels[@]}"; do
    local num=$(( i+1 )) lvl="${all_levels[$i]}" in_chain=false
    for gl in "${group_view_levels[@]}"; do [ "$gl" = "$lvl" ] && in_chain=true && break; done
    if $in_chain; then
      local pos=0
      for j in "${!group_view_levels[@]}"; do
        [ "${group_view_levels[$j]}" = "$lvl" ] && pos=$(( j+1 ))
      done
      printf " %d) $(_green "${all_labels[$i]} ✓ (position $pos)")\n" "$num"
    else
      printf " %d) %s\n" "$num" "${all_labels[$i]}"
    fi
  done
}

group_view_settings() {
  local all_levels=("ext" "year" "month" "date")

  while true; do
    _show_group_state
    [ ${#group_view_levels[@]} -gt 0 ] && echo && echo "u) Ungroup (turn off all grouping)"
    echo "a) Add level to chain   r) Remove level from chain"
    echo "o) Reorder chain   q) Done"
    read -r -p "Action: " action; action="${action,,}"

    case "$action" in
      q) break ;;

      u)
        group_view_levels=(); group_view_levels_str=""
        save_settings; echo "✅ Grouping turned off"
        ;;

      a)
        echo "Add level(s) by number (comma/range):"
        read -r -p "Numbers [1-4]: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel; sel=$(_parse_multi_select "$inp" 4)
        local changed=false
        for n in $sel; do
          local lvl="${all_levels[$((n-1))]}" already=false
          for gl in "${group_view_levels[@]}"; do [ "$gl" = "$lvl" ] && already=true && break; done
          if ! $already; then group_view_levels+=("$lvl"); changed=true; fi
        done
        $changed || echo "All already in chain — no change"
        $changed && group_view_levels_str="${group_view_levels[*]}" && save_settings && echo "✅ Level(s) added"
        ;;

      r)
        [ ${#group_view_levels[@]} -eq 0 ] && { echo "Chain is empty"; continue; }
        echo "Remove level(s) by number (comma/range) [based on available levels list above]:"
        read -r -p "Numbers [1-4]: " inp
        [ -z "$inp" ] && { echo "No change"; continue; }
        local sel; sel=$(_parse_multi_select "$inp" 4)
        local changed=false; local -a new_chain=(); declare -A to_remove=()
        for n in $sel; do to_remove["${all_levels[$((n-1))]}"]="1"; done
        for gl in "${group_view_levels[@]}"; do
          if [ -z "${to_remove[$gl]+x}" ]; then new_chain+=("$gl")
          else changed=true; fi
        done
        if $changed; then
          group_view_levels=("${new_chain[@]}")
          group_view_levels_str="${group_view_levels[*]}"
          save_settings; echo "✅ Level(s) removed"
        else
          echo "None of those were in the chain — no change"
        fi
        ;;

      o)
        [ ${#group_view_levels[@]} -le 1 ] && { echo "Need at least 2 levels in chain to reorder"; continue; }
        echo "Current chain:"
        for i in "${!group_view_levels[@]}"; do printf "  %d) %s\n" "$(( i+1 ))" "${group_view_levels[$i]}"; done
        echo "Enter new order as position numbers (e.g. 2,1,3):"
        read -r -p "Order: " inp
        IFS=',' read -ra order_parts <<< "$inp"
        local -a new_chain=(); local -A used_pos=(); local valid=true
        for p in "${order_parts[@]}"; do
          p="${p// /}"
          if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#group_view_levels[@]} )); then
            if [ -z "${used_pos[$p]+x}" ]; then
              new_chain+=("${group_view_levels[$((p-1))]}"); used_pos[$p]=1
            fi
          else
            valid=false
          fi
        done
        if [ "${#new_chain[@]}" -ne "${#group_view_levels[@]}" ]; then
          echo "⚠️  Incomplete order — no change"
        else
          group_view_levels=("${new_chain[@]}")
          group_view_levels_str="${group_view_levels[*]}"
          save_settings; echo "✅ Chain reordered: ${group_view_levels[*]}"
        fi
        ;;

      *) echo "⚠️  Invalid action. Use a/r/o/u/q" ;;
    esac
  done
}

# ── Filter feature ────────────────────────────────────────────────────────────

_filter_query=""
declare -ga _all_items=()

_filter_snapshot() { _all_items=("${items[@]}"); }

_filter_apply() {
  local q="${_filter_query,,}"
  items=()
  if [ -z "$q" ]; then
    items=("${_all_items[@]}")
  else
    local f bn
    for f in "${_all_items[@]}"; do
      bn="${f##*/}"
      [[ "${bn,,}" == "$q"* ]] && items+=("$f")
    done
  fi
  # Reset window so next render fetches fresh metadata for the filtered set.
  _win_lo=0; _win_hi=0
  _meta_loaded=false
  _vp_cache_reset
}

_filter_backspace() {
  if [ -n "$_filter_query" ]; then
    _filter_query="${_filter_query%?}"
    _filter_apply
    return 0
  fi
  return 1
}

_filter_append() { _filter_query+="${1,,}"; _filter_apply; }

_filter_clear() {
  _filter_query=""
  items=("${_all_items[@]}")
  _win_lo=0; _win_hi=0
  _meta_loaded=false
  _vp_cache_reset
}
