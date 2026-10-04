# bashbasicsbyvk_displayer.sh
# ════════════════════════════════════════════════════════════════════════════
# Windowed JIT displayer. Aggressive ProcessPoolExecutor on all stat-heavy
# paths; async background pool for recursive directory sizes.
#
# Layer 1  — Name index   : Python scandir, sorted by name or stat sort.
# Layer 2  — Hot window   : ±60 rows, batch stat via ProcessPoolExecutor.
# Layer 3  — Recursive    : async background pool, splits top dirs by subdir
#                           fanout. Never blocks render.
# ════════════════════════════════════════════════════════════════════════════

# ── Core arrays ───────────────────────────────────────────────────────────────

declare -gA item_size=()
declare -gA item_mtime=()
declare -gA item_icon=()
declare -gA item_children=()
declare -gA item_dsize=()          # recursive dir size cache
declare -g  _meta_loaded=false
declare -g  _hl_index=0

declare -g _win_lo=0
declare -g _win_hi=0
_BVK_WIN_RADIUS=60

declare -g _items_presorted=false
declare -g _items_presorted_mode=""

# Async recursive dir-size job state
declare -g _BVK_DSIZE_JOB_PID=""
declare -g _BVK_DSIZE_JOB_IN=""
declare -g _BVK_DSIZE_JOB_OUT=""

# Per-session temp dir for job scratch
if [ -z "${_BVK_DSIZE_TMP:-}" ]; then
  _BVK_DSIZE_TMP="$(mktemp -d -t bvk-dsize.XXXXXX 2>/dev/null)"
  export _BVK_DSIZE_TMP
fi

# ── Rendering helpers ─────────────────────────────────────────────────────────

_bold()        { printf '\033[1m%s\033[0m'   "$1"; }
_highlight()   { printf '\033[1;7m%s\033[0m' "$1"; }
_highlight_v() { _hl_out=$'\033[1;7m'"$1"$'\033[0m'; }

# ── Icon detection (window-fetch fallback only) ───────────────────────────────

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

# ═══════════════════════════════════════════════════════════════════════════════
# _py_scan_script — Layer 1: name index with optional parallel stat.
# ═══════════════════════════════════════════════════════════════════════════════
_py_scan_script() {
python3 - "$@" <<'PYEOF'
import os, sys, stat as st_mod
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor

dirpath  = sys.argv[1]
mode     = sys.argv[2]
hidden   = sys.argv[3] == "1"
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

def _stat_chunk(args):
    dirpath_c, names = args
    out = []
    for name in names:
        p = os.path.join(dirpath_c, name)
        try:
            s = os.stat(p, follow_symlinks=True)
            isd = st_mod.S_ISDIR(s.st_mode)
            sz = 0 if isd else s.st_size
            mt = s.st_mtime
            out.append((p, name.lower(), sz, mt))
        except Exception:
            out.append((p, name.lower(), 0, 0.0))
    return out

def _pick_ctx():
    methods = mp.get_all_start_methods()
    if "fork" in methods:
        return mp.get_context("fork")
    return mp.get_context()

names = []
try:
    with os.scandir(dirpath) as it:
        for e in it:
            bn = e.name
            if bn in (".", ".."): continue
            if not hidden and bn.startswith("."): continue
            if pfx and not bn.lower().startswith(pfx): continue
            names.append(bn)
except Exception as ex:
    sys.stderr.write(f"scan error: {ex}\n")
    sys.exit(1)

needs_stat = mode in ("new","old","big","small")

entries = []
if not needs_stat:
    entries = [(os.path.join(dirpath, n), n.lower(), 0, 0.0) for n in names]
elif len(names) < 400:
    entries = _stat_chunk((dirpath, names))
else:
    nproc = min(os.cpu_count() or 4, 8)
    total = len(names)
    chunk_size = max(500, total // (nproc * 4))
    chunks = [names[i:i+chunk_size] for i in range(0, total, chunk_size)]
    work = [(dirpath, c) for c in chunks]
    ctx = _pick_ctx()
    try:
        with ProcessPoolExecutor(max_workers=nproc, mp_context=ctx) as ex:
            for r in ex.map(_stat_chunk, work, chunksize=1):
                entries.extend(r)
    except Exception:
        entries = _stat_chunk((dirpath, names))

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

# ═══════════════════════════════════════════════════════════════════════════════
# _py_meta_script — Layer 2: batch stat for the visible window.
# ═══════════════════════════════════════════════════════════════════════════════
_py_meta_script() {
python3 - "$1" <<'PYEOF'
import os, sys, stat as st_mod
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

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

def stat_one(p):
    try:
        s       = os.stat(p, follow_symlinks=True)
        is_dir  = st_mod.S_ISDIR(s.st_mode)
        sz      = 0 if is_dir else s.st_size
        mt      = int(s.st_mtime)
        if is_dir:
            try:
                ch = sum(1 for _ in os.scandir(p))
            except Exception:
                ch = -1
        else:
            ch = -1
        ic      = icon(os.path.basename(p), is_dir, s.st_mode)
        return f"{p}|{sz}|{mt}|{ch}|{ic}"
    except Exception:
        return f"{p}|0|0|-1|plain"

def _meta_chunk(chunk):
    return [stat_one(p) for p in chunk]

def _pick_ctx():
    methods = mp.get_all_start_methods()
    if "fork" in methods:
        return mp.get_context("fork")
    return mp.get_context()

with open(paths_file) as fh:
    paths = [l.rstrip("\n") for l in fh if l.strip()]

if not paths:
    sys.exit(0)

n = len(paths)
results = []

if n < 400:
    workers = min(8, n)
    with ThreadPoolExecutor(max_workers=workers) as ex:
        results = list(ex.map(stat_one, paths))
else:
    nproc = min(os.cpu_count() or 4, 8)
    chunk_size = max(200, n // (nproc * 4))
    chunks = [paths[i:i+chunk_size] for i in range(0, n, chunk_size)]
    ctx = _pick_ctx()
    try:
        with ProcessPoolExecutor(max_workers=nproc, mp_context=ctx) as ex:
            for r in ex.map(_meta_chunk, chunks, chunksize=1):
                results.extend(r)
    except Exception:
        with ThreadPoolExecutor(max_workers=8) as ex:
            results = list(ex.map(stat_one, paths))

sys.stdout.write("\n".join(results) + "\n")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# _py_recursive_size — Layer 3: aggressive parallel recursive dir sizes.
#
# Splits each top dir into per-subdir tasks when fanout ≥ 4, so a single
# window dir with 200 subdirs becomes 200 parallel tasks. Aggregates by
# top dir at the end. Runs in background via & disown from bash.
# ═══════════════════════════════════════════════════════════════════════════════
_py_recursive_size() {
python3 - "$1" <<'PYEOF'
import os, sys
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor

paths_file = sys.argv[1]

def _pick_ctx():
    m = mp.get_all_start_methods()
    return mp.get_context("fork") if "fork" in m else mp.get_context()

def _walk_size(path):
    """Iterative DFS, symlink-loop protected."""
    total = 0
    stack = [path]
    seen = set()
    while stack:
        d = stack.pop()
        try:
            real = os.path.realpath(d)
            if real in seen:
                continue
            seen.add(real)
        except Exception:
            pass
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_dir(follow_symlinks=False):
                            stack.append(e.path)
                        elif e.is_file(follow_symlinks=False):
                            total += e.stat(follow_symlinks=False).st_size
                    except Exception:
                        pass
        except Exception:
            pass
    return total

def _plan(paths):
    """
    Each task is (top_path, walk_path, base_offset, tag).
      tag == "walk"  → recurse walk_path, add base_offset
      tag == "base"  → just return base_offset (immediate files of top)
    """
    tasks = []
    for p in paths:
        try:
            entries = list(os.scandir(p))
        except Exception:
            tasks.append((p, p, 0, "walk"))
            continue
        subdirs = []
        base = 0
        for e in entries:
            try:
                if e.is_dir(follow_symlinks=False):
                    subdirs.append(e.path)
                elif e.is_file(follow_symlinks=False):
                    base += e.stat(follow_symlinks=False).st_size
            except Exception:
                pass
        if len(subdirs) >= 4:
            for sd in subdirs:
                tasks.append((p, sd, 0, "walk"))
            if base:
                tasks.append((p, p, base, "base"))
        else:
            tasks.append((p, p, base, "walk"))
    return tasks

def _run(task):
    top, walk, base, tag = task
    if tag == "base":
        return (top, base)
    return (top, _walk_size(walk) + base)

with open(paths_file) as fh:
    paths = [l.rstrip("\n") for l in fh if l.strip()]

if not paths:
    sys.exit(0)

tasks = _plan(paths)

if len(tasks) <= 1:
    results = [_run(t) for t in tasks]
else:
    nproc = min(os.cpu_count() or 4, 8, len(tasks))
    try:
        with ProcessPoolExecutor(max_workers=nproc,
                                 mp_context=_pick_ctx()) as ex:
            results = list(ex.map(_run, tasks, chunksize=1))
    except Exception:
        results = [_run(t) for t in tasks]

totals = {}
for top, sz in results:
    totals[top] = totals.get(top, 0) + sz

for p in paths:
    print(f"{p}|{totals.get(p, 0)}")
PYEOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# build_items_with_meta / apply_sort — Layer 1
# ═══════════════════════════════════════════════════════════════════════════════
build_items_with_meta() {
  local p="$1"
  local pfx="${2:-}"
  items=()
  item_size=(); item_mtime=(); item_icon=(); item_children=()
  _meta_loaded=false
  _win_lo=0; _win_hi=0

  local hidden_flag=0
  $show_hidden_files && hidden_flag=1
  local mode="${sort_mode:-az}"

  mapfile -t items < <(_py_scan_script "$p" "$mode" "$hidden_flag" "$pfx" 2>/dev/null)

  _items_presorted=true
  _items_presorted_mode="$mode"
}

apply_sort() {
  local mode="${sort_mode:-az}"
  [ ${#items[@]} -eq 0 ] && { _items_presorted=true; _items_presorted_mode="$mode"; return; }

  if [ "${_items_presorted:-false}" = "true" ] && \
     [ "${_items_presorted_mode:-}" = "$mode" ]; then
    _win_lo=0; _win_hi=0
    item_size=(); item_mtime=(); item_icon=(); item_children=()
    _meta_loaded=false
    return
  fi

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
      mapfile -t items <<< "$sorted_output"
      ;;
    new|old|big|small)
      local tmp_in; tmp_in=$(mktemp)
      printf '%s\n' "${items[@]}" > "$tmp_in"
      local sorted_output
      sorted_output=$(python3 - "$tmp_in" "$mode" <<'PYEOF'
import os, sys, stat as st_mod
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor

paths_file = sys.argv[1]; mode = sys.argv[2]

def _chunk(paths):
    out = []
    for p in paths:
        try:
            s = os.stat(p, follow_symlinks=True)
            sz = 0 if os.path.isdir(p) else s.st_size
            out.append((p, sz, s.st_mtime))
        except Exception:
            out.append((p, 0, 0.0))
    return out

def _ctx():
    m = mp.get_all_start_methods()
    return mp.get_context("fork") if "fork" in m else mp.get_context()

with open(paths_file) as fh:
    paths = [l.rstrip("\n") for l in fh if l.strip()]

n = len(paths)
records = []
if n < 400:
    records = _chunk(paths)
else:
    nproc = min(os.cpu_count() or 4, 8)
    cs = max(500, n // (nproc * 4))
    chunks = [paths[i:i+cs] for i in range(0, n, cs)]
    try:
        with ProcessPoolExecutor(max_workers=nproc, mp_context=_ctx()) as ex:
            for r in ex.map(_chunk, chunks, chunksize=1):
                records.extend(r)
    except Exception:
        records = _chunk(paths)

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
      mapfile -t items <<< "$sorted_output"
      ;;
  esac

  _items_presorted=true
  _items_presorted_mode="$mode"

  _win_lo=0; _win_hi=0
  item_size=(); item_mtime=(); item_icon=(); item_children=()
  _meta_loaded=false
}

# ═══════════════════════════════════════════════════════════════════════════════
# _load_window — Layer 2 metadata for centre ± radius.
# ═══════════════════════════════════════════════════════════════════════════════
_load_window() {
  local centre="${1:-1}"
  local n="${#items[@]}"
  [ "$n" -eq 0 ] && return

  local lo=$(( centre - _BVK_WIN_RADIUS ))
  local hi=$(( centre + _BVK_WIN_RADIUS ))
  (( lo < 1 )) && lo=1
  (( hi > n )) && hi=$n

  if (( _win_lo > 0 && lo >= _win_lo && hi <= _win_hi )); then
    return
  fi

  local tmp_in; tmp_in=$(mktemp)
  local i
  for (( i=lo; i<=hi; i++ )); do
    local f="${items[$((i-1))]}"
    [ -z "${item_size[$f]+x}" ] && printf '%s\n' "$f"
  done > "$tmp_in"

  if [ ! -s "$tmp_in" ]; then
    rm -f "$tmp_in"
    _win_lo=$lo; _win_hi=$hi
    _meta_loaded=true
    return
  fi

  while IFS='|' read -r fpath fsize fmtime fchildren ftype; do
    [ -z "$fpath" ] && continue
    item_size["$fpath"]="$fsize"
    item_mtime["$fpath"]="$fmtime"
    item_children["$fpath"]="$fchildren"
    item_icon["$fpath"]="$ftype"
  done < <(_py_meta_script "$tmp_in" 2>/dev/null)
  rm -f "$tmp_in"

  local evict_lo=$(( lo - _BVK_WIN_RADIUS ))
  local evict_hi=$(( hi + _BVK_WIN_RADIUS ))
  if (( _win_lo > 0 )); then
    local j
    for (( j=_win_lo; j<lo; j++ )); do
      (( j < evict_lo )) || continue
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

_collect_metadata() {
  local centre="${_hl_index:-1}"
  (( centre < 1 )) && centre=1
  _load_window "$centre"
}

_ensure_meta() {
  local centre="${_hl_index:-1}"
  (( centre < 1 )) && centre=1
  if (( _win_lo < 1 || centre < _win_lo || centre > _win_hi )); then
    _load_window "$centre"
  fi
  # Kick off background recursive dir-size for any newly visible dirs.
  if declare -F _load_dir_size_window >/dev/null 2>&1; then
    _load_dir_size_window
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

_needs_dir_size() {
  [[ " ${display_suffix_set:-} " == *" size "* ]] && return 0
  return 1
}

# ── Async recursive dir-size orchestration ────────────────────────────────────

# Spawn (or replace) a background job that computes recursive sizes for
# any dirs in the current window that don't yet have cached sizes.
# Non-blocking: returns immediately.
_load_dir_size_window() {
  _needs_dir_size || return 0
  [ "$_win_lo" -lt 1 ] && return 0

  # If a job is still running, do not spawn another.
  if [ -n "$_BVK_DSIZE_JOB_PID" ] && kill -0 "$_BVK_DSIZE_JOB_PID" 2>/dev/null; then
    return 0
  fi
  # Previous job left state around after exiting without poll — clean.
  if [ -n "$_BVK_DSIZE_JOB_IN" ] && [ -f "$_BVK_DSIZE_JOB_IN" ]; then
    rm -f "$_BVK_DSIZE_JOB_IN" "$_BVK_DSIZE_JOB_OUT"
  fi
  _BVK_DSIZE_JOB_PID=""
  _BVK_DSIZE_JOB_IN=""
  _BVK_DSIZE_JOB_OUT=""

  local tmp_in; tmp_in=$(mktemp "$_BVK_DSIZE_TMP/in.XXXXXX" 2>/dev/null) || tmp_in=$(mktemp)
  local i f
  for (( i=_win_lo; i<=_win_hi; i++ )); do
    f="${items[$((i-1))]}"
    [ -d "$f" ] || continue
    [ -n "${item_dsize[$f]+x}" ] && continue
    printf '%s\n' "$f"
  done > "$tmp_in"

  if [ ! -s "$tmp_in" ]; then
    rm -f "$tmp_in"
    return 0
  fi

  _BVK_DSIZE_JOB_IN="$tmp_in"
  _BVK_DSIZE_JOB_OUT="${tmp_in}.out"

  _py_recursive_size "$tmp_in" > "$_BVK_DSIZE_JOB_OUT" 2>/dev/null &
  _BVK_DSIZE_JOB_PID=$!
  disown 2>/dev/null || true
  return 0
}

# Called from the poll loop. Returns 0 if a completed job was harvested
# (caller should repaint), 1 otherwise.
_dir_size_job_poll() {
  [ -z "$_BVK_DSIZE_JOB_PID" ] && return 1
  kill -0 "$_BVK_DSIZE_JOB_PID" 2>/dev/null && return 1

  # Job finished — harvest.
  if [ -f "$_BVK_DSIZE_JOB_OUT" ]; then
    while IFS='|' read -r dp ds; do
      [ -z "$dp" ] && continue
      item_dsize["$dp"]="${ds:-0}"
    done < "$_BVK_DSIZE_JOB_OUT"
    rm -f "$_BVK_DSIZE_JOB_OUT" "$_BVK_DSIZE_JOB_IN"
  fi

  _BVK_DSIZE_JOB_PID=""
  _BVK_DSIZE_JOB_IN=""
  _BVK_DSIZE_JOB_OUT=""

  # Immediately kick off the next batch for any new visible dirs.
  _load_dir_size_window
  return 0
}

# ── Size / time formatters ────────────────────────────────────────────────────

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

# ── Suffix builder — now shows real recursive sizes for dirs ──────────────────

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
        if [ -d "$fpath" ]; then
          # Recursive size for dirs, from async cache.
          local dsz="${item_dsize[$fpath]:-}"
          if [ -n "$dsz" ]; then
            _fmt_size_v "$dsz"
            _bs_out+=" | $_fs_out"
          else
            _bs_out+=" | ⏳"
          fi
        else
          local sz="${item_size[$fpath]:-}"
          if [ -z "$sz" ]; then
            _bs_out+=" | ..."
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
          :
        else
          _bs_out+=" | ${ch} items"
        fi
        ;;
    esac
  done
}
_build_suffix() { local _bs_out; _build_suffix_v "$1"; printf '%s' "$_bs_out"; }

# ── Icon resolution ───────────────────────────────────────────────────────────

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
    if   [ -d "$f" ];         then _rdp_icon="📁"
    elif _is_archive "$f";    then _rdp_icon="📦"
    elif _is_image   "$f";    then _rdp_icon="🌄"
    elif _is_plugin  "$f";    then _rdp_icon="🧩"
    elif _is_executable "$f"; then _rdp_icon="⚙️"
    else                           _rdp_icon="📄"
    fi
  fi
  # favourites: alias ("Alias (name)") / ⭐ marker while favourite mode is paused
  [ -n "${_FAV_LABEL[$f]+x}" ] && _rdp_bn="${_FAV_LABEL[$f]}"
}

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

# ── Settings screens: sort order · file details · group by ────────────────────
# Same look as every other menu: numbered rows, "Select:" prompt, footer line.
#   u = back to the Settings menu     q = close Settings (back to the main menu)
# [x] / [ ] rows are on/off switches: ↑↓ move, Space (or Enter / the number) flips one.

sort_order_settings() {
  local modes=("az" "za" "new" "old" "big" "small")
  local labels=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")
  local i c
  echo
  echo "Sort order"
  for i in "${!modes[@]}"; do
    if [ "${modes[$i]}" = "$sort_mode" ]; then
      printf " %d) %s\n" "$((i+1))" "$(_green "${labels[$i]} ✓")"
    else
      printf " %d) %s\n" "$((i+1))" "${labels[$i]}"
    fi
  done
  echo
  echo "u) Back   q) Close settings"
  _st_read c
  case "${c,,}" in u) return ;; q) _st_quit=1; return ;; esac
  if [[ "$c" =~ ^[1-6]$ ]]; then
    sort_mode="${modes[$((c-1))]}"
    _items_presorted=false
    save_settings
    echo "✅ Sort order: ${labels[$((c-1))]}"
  else
    echo "No change"
  fi
}

_time_format_menu() {
  local tfmts=("year" "month" "date" "datetime" "monthdate" "full")
  local tlabels=("Year (2023)" "Month (Mar)" "Day (15)" "Day + time (15 14:32)" "Month-day + time (Mar-15 14:32)" "Full date + time (2023-Mar-15 14:32)")
  local i c
  echo
  echo "Time format"
  for i in "${!tfmts[@]}"; do
    if [ "${tfmts[$i]}" = "$display_time_format" ]; then
      printf " %d) %s\n" "$((i+1))" "$(_green "${tlabels[$i]} ✓")"
    else
      printf " %d) %s\n" "$((i+1))" "${tlabels[$i]}"
    fi
  done
  echo
  echo "u) Back   q) Close settings"
  _st_read c
  case "${c,,}" in u) return ;; q) _st_quit=1; return ;; esac
  if [[ "$c" =~ ^[1-6]$ ]]; then
    display_time_format="${tfmts[$((c-1))]}"
    save_settings
  fi
}

display_suffix_settings() {
  local tokens=("ext" "size" "time" "children")
  local labels=("Extension" "Size" "Modified time" "Item count (folders)")
  local tfmts=("year" "month" "date" "datetime" "monthdate" "full")
  local i c mark last=0 tok new t
  while :; do
    echo
    echo "File details (shown after each name)"
    for i in "${!tokens[@]}"; do
      mark="[ ]"; [[ " $display_suffix_set " == *" ${tokens[$i]} "* ]] && mark="[x]"
      echo " $((i+1))) $mark ${labels[$i]}"
    done
    echo " 5) Time format: $display_time_format"
    echo
    echo "u) Back   q) Close settings   (↑↓ move, Space toggle)"
    _st_read c "$last" 1
    case "${c,,}" in
      u) return ;;
      q) _st_quit=1; return ;;
      [1-4])
        tok="${tokens[$((c-1))]}"; new=""
        if [[ " $display_suffix_set " == *" $tok "* ]]; then
          for t in $display_suffix_set; do [ "$t" = "$tok" ] || new+="${new:+ }$t"; done
        else
          new="${display_suffix_set:+$display_suffix_set }$tok"
        fi
        display_suffix_set="$new"
        save_settings
        last=$c ;;
      5) _time_format_menu; (( _st_quit )) && return; last=5 ;;
      "") ;;
      *) echo "⚠️  Pick 1-5, u or q" ;;
    esac
  done
}

_valid_level() { case "$1" in ext|year|month|date) return 0 ;; *) return 1 ;; esac }

group_view_settings() {
  local levels=("ext" "year" "month" "date")
  local labels=("Extension" "Year" "Month" "Date")
  local ord=("1st" "2nd" "3rd" "4th")
  local i j c pos last=0 lvl
  local -a new
  while :; do
    echo
    echo "Group by (levels nest in the order you tick them)"
    for i in "${!levels[@]}"; do
      pos=""
      for j in "${!group_view_levels[@]}"; do
        [ "${group_view_levels[$j]}" = "${levels[$i]}" ] && pos="${ord[$j]}"
      done
      if [ -n "$pos" ]; then echo " $((i+1))) [x] ${labels[$i]}   ($pos)"
      else echo " $((i+1))) [ ] ${labels[$i]}"; fi
    done
    echo
    echo "u) Back   q) Close settings   (↑↓ move, Space toggle)"
    _st_read c "$last" 1
    case "${c,,}" in
      u) return ;;
      q) _st_quit=1; return ;;
      [1-4])
        lvl="${levels[$((c-1))]}"; new=()
        pos=0
        for j in "${!group_view_levels[@]}"; do
          if [ "${group_view_levels[$j]}" = "$lvl" ]; then pos=1; else new+=("${group_view_levels[$j]}"); fi
        done
        if (( pos )); then group_view_levels=("${new[@]}"); else group_view_levels+=("$lvl"); fi
        group_view_levels_str="${group_view_levels[*]}"
        save_settings
        last=$c ;;
      "") ;;
      *) echo "⚠️  Pick 1-4, u or q" ;;
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