# bashbasicsbyvk_displayer.sh
# ════════════════════════════════════════════════════════════════════════════
# Fully integrated daemon-backed displayer.
#
# The Python daemon (bvk_daemon.py) is the only dependency to add.
# Source this file exactly as before — no other files needed:
#
#   source bashbasicsbyvk_coresettings.sh
#   source bashbasicsbyvk_displayer.sh       ← this file (replaces old one)
#
# WHAT CHANGED vs the old displayer
# ─────────────────────────────────
#   • build_items_with_meta()  → daemon-backed; falls back to find/stat
#   • _collect_metadata()      → no-op when daemon loaded data
#   • _build_suffix_v()        → adds "children" token (4th suffix)
#   • _show_suffix_state()     → shows 4 options
#   • display_suffix_settings()→ handles 4 tokens
#   • All icon logic now reads from item_icon[] set by daemon, so icon
#     detection runs in Python once and is free on every render
#   • No bvk_client.sh, no displayer_children_patch.sh needed
#   • No manual bvk_cache_invalidate() calls needed anywhere — inotify
#     detects every create/delete/rename from any source automatically
# ════════════════════════════════════════════════════════════════════════════

# ── Core metadata arrays ──────────────────────────────────────────────────────

declare -gA item_size=()
declare -gA item_mtime=()
declare -gA item_children=()   # -1 for files, ≥0 for dirs (child count)
declare -gA item_icon=()       # dir|archive|image|plugin|exec|plain|shortcut
_meta_loaded=false
declare -g  _hl_index=0

# ── Daemon paths ──────────────────────────────────────────────────────────────

_BVK_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/bashbasicsbyvk"
_BVK_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bashbasicsbyvk"
_BVK_SOCK="$_BVK_CFG_DIR/daemon.sock"
_BVK_PID="$_BVK_CFG_DIR/daemon.pid"
_BVK_LOG="$_BVK_CACHE_DIR/daemon.log"

# bvk_daemon.py must live in the same directory as this file (or SCRIPT_DIR)
_BVK_DAEMON_PY="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/bvk_daemon"

# Tracks whether current items[] were populated by the daemon
declare -g _bvk_meta_source=""   # "daemon" | ""

# ── Daemon lifecycle ───────────────────────────────────────────────────────────

_bvk_daemon_start() {
  [ -S "$_BVK_SOCK" ] && return 0
  [ -f "$_BVK_DAEMON_PY" ] || return 1
  mkdir -p "$_BVK_CFG_DIR" "$_BVK_CACHE_DIR"
  python3 "$_BVK_DAEMON_PY" --daemon </dev/null >>"$_BVK_LOG" 2>&1 &
  disown
  local i=0
  while ! [ -S "$_BVK_SOCK" ] && (( i < 30 )); do
    sleep 0.1; i=$(( i + 1 ))
  done
  [ -S "$_BVK_SOCK" ]
}

bvk_daemon_stop()   { [ -S "$_BVK_SOCK" ] && python3 "$_BVK_DAEMON_PY" QUIT 2>/dev/null; }
bvk_daemon_status() {
  echo "Daemon socket : $_BVK_SOCK"
  if [ -S "$_BVK_SOCK" ]; then
    local r; r=$(python3 "$_BVK_DAEMON_PY" PING 2>/dev/null | head -1)
    [ "$r" = "PONG" ] && echo "Daemon status : running (pid $(cat "$_BVK_PID" 2>/dev/null))" \
                       || echo "Daemon status : socket exists but not responding"
  else
    echo "Daemon status : not running"
  fi
  echo "Cache dir     : $_BVK_CACHE_DIR"
  echo "Log           : $_BVK_LOG"
  local cnt=0
  [ -d "$_BVK_CACHE_DIR" ] && cnt=$(find "$_BVK_CACHE_DIR" -name "*.json" 2>/dev/null | wc -l)
  echo "Cached dirs   : $cnt"
}

# ── Daemon query ───────────────────────────────────────────────────────────────

_bvk_query() {
  local dirpath="$1" hidden_flag=0
  $show_hidden_files && hidden_flag=1
  [ -S "$_BVK_SOCK" ] || _bvk_daemon_start || return 1
  python3 "$_BVK_DAEMON_PY" LIST "$dirpath" "$hidden_flag" 2>/dev/null
}

# ── build_items_with_meta — daemon-backed drop-in ─────────────────────────────
#
# After return:
#   items[]             full paths (not yet sorted)
#   item_size[$p]       bytes for files, 0 for dirs
#   item_mtime[$p]      unix epoch
#   item_children[$p]   ≥0 for dirs (child count), -1 for files
#   item_icon[$p]       dir|archive|image|plugin|exec|plain|shortcut
#   _meta_loaded=true   prevents _ensure_meta() from wiping daemon data

build_items_with_meta() {
  local p="$1"
  local pfx="${2:-}"

  items=()
  item_size=()
  item_mtime=()
  item_children=()
  item_icon=()
  _meta_loaded=false
  _bvk_meta_source=""

  local line fpath fsize fmtime fchildren ftype
  while IFS= read -r line; do
    [ "$line" = "END" ] && break
    [ -z "$line" ] && continue
    [[ "$line" == ERROR:* ]] && break

    IFS='|' read -r fpath fsize fmtime fchildren ftype <<< "$line"
    [ -z "$fpath" ] && continue

    if [ -n "$pfx" ]; then
      local bn="${fpath##*/}"
      [[ "${bn,,}" != "${pfx,,}"* ]] && continue
    fi

    items+=("$fpath")
    item_size["$fpath"]="$fsize"
    item_mtime["$fpath"]="$fmtime"
    item_children["$fpath"]="$fchildren"
    item_icon["$fpath"]="$ftype"
  done < <(_bvk_query "$p" 2>/dev/null)

  if [ ${#items[@]} -gt 0 ] || [ -S "$_BVK_SOCK" ]; then
    _meta_loaded=true
    _bvk_meta_source="daemon"
    return 0
  fi

  # ── Fallback: daemon unavailable ────────────────────────────────────────────
  _bvk_build_fallback "$p" "$pfx"
}

# Original bash-only scan (used when Python is unavailable)
_bvk_build_fallback() {
  local p="$1" pfx="${2:-}"
  if [ -n "$pfx" ] || $show_hidden_files; then
    while IFS= read -r -d '' f; do
      local bn="${f##*/}"
      [[ "$bn" == "." || "$bn" == ".." ]] && continue
      ! $show_hidden_files && [[ "$bn" == .* ]] && continue
      [ -n "$pfx" ] && [[ "${bn,,}" != "${pfx,,}"* ]] && continue
      items+=("$f")
    done < <(find "$p" -maxdepth 1 -mindepth 1 -print0 2>/dev/null)
  else
    local f
    for f in "$p"/*; do
      [ -e "$f" ] || continue
      items+=("$f")
    done
  fi
}

# ── _collect_metadata — short-circuits when daemon already populated data ──────

_collect_metadata() {
  # Daemon already filled item_size[], item_mtime[], item_children[], item_icon[].
  # After filter/sort the items[] subset still exists in those dicts — just
  # mark loaded so _ensure_meta() stops calling us.
  if [ "$_bvk_meta_source" = "daemon" ]; then
    _meta_loaded=true
    return
  fi

  # Fallback path (no daemon): original stat-based collection
  item_size=()
  item_mtime=()
  [ ${#items[@]} -eq 0 ] && { _meta_loaded=true; return; }

  local need_dir_size=false
  _needs_dir_size && need_dir_size=true

  local -a files=() dirs=()
  local f
  for f in "${items[@]}"; do
    [ -d "$f" ] && dirs+=("$f") || files+=("$f")
  done

  if [ ${#files[@]} -gt 0 ]; then
    while IFS='|' read -r fpath fsize fmtime; do
      item_size["$fpath"]="$fsize"
      item_mtime["$fpath"]="$fmtime"
    done < <(stat -c "%n|%s|%Y" "${files[@]}" 2>/dev/null)
  fi

  if [ ${#dirs[@]} -gt 0 ]; then
    while IFS='|' read -r fpath fmtime; do
      item_mtime["$fpath"]="$fmtime"
      item_size["$fpath"]=0
    done < <(stat -c "%n|%Y" "${dirs[@]}" 2>/dev/null)

    if $need_dir_size; then
      while IFS=$'\t' read -r sz fpath; do
        item_size["$fpath"]="$sz"
      done < <(du -sb "${dirs[@]}" 2>/dev/null)
    fi
  fi

  _meta_loaded=true
}

_ensure_meta() {
  $_meta_loaded && return
  _collect_metadata
}

# ── Rendering helpers ──────────────────────────────────────────────────────────

_bold()      { printf '\033[1m%s\033[0m' "$1"; }
_highlight() { printf '\033[1;7m%s\033[0m' "$1"; }
_highlight_v() { _hl_out=$'\033[1;7m'"$1"$'\033[0m'; }

# ── Icon resolution ────────────────────────────────────────────────────────────
#
# When daemon supplied item_icon[], we read it directly — zero filesystem ops.
# Fallback bash path (no daemon) uses the _is_* functions.

_is_archive() {
  local bn="${1##*/}" lower; lower="${bn,,}"
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
    *.pef|*.ptx|*.dng|*.raf|*.mef|*.mrw|*.dcr|*.kdc|*.erf|*.x3f|*.srw|*.bay) return 0 ;;
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
    *.js|*.mjs|*.cjs|*.ts|*.mts|*.cts|*.class|*.jar) return 0 ;;
    *.exe|*.com|*.out|*.elf|*.o|*.a|*.lib) return 0 ;;
    *.bat|*.cmd|*.ps1|*.psm1|*.psd1|*.vbs|*.vbe|*.wsf|*.wsh) return 0 ;;
    *.app|*.command|*.run|*.wasm|*.beam|*.elc|*.rbc|*.luac) return 0 ;;
    *) return 1 ;;
  esac
}

_is_plugin() {
  local lower="${1##*/}"; lower="${lower,,}"
  case "$lower" in
    *.crx|*.xpi|*.safariextz|*.vsix|*.visx|*.natvis|*.sublime-package) return 0 ;;
    *.plugin|*.bundle|*.kext|*.mdimporter|*.addon|*.addin|*.adp) return 0 ;;
    *.vst|*.vst3|*.au|*.lv2|*.ladspa|*.dssi|*.sketchplugin|*.figma|*.xdx) return 0 ;;
    *) return 1 ;;
  esac
}

# _resolve_display_parts_v — sets _rdp_icon and _rdp_bn.
# Reads item_icon[] from daemon when available; falls back to _is_* functions.

_resolve_display_parts_v() {
  local f="$1"
  _rdp_bn="${f##*/}"

  if [[ "$_rdp_bn" == *.shortcut ]]; then
    _shortcut_display_parts "$f"
    _rdp_icon="$_sc_icon"
    _rdp_bn="$_sc_display"
    return
  fi

  # Fast path: daemon told us the icon type
  local _itype="${item_icon[$f]:-}"
  if [ -n "$_itype" ]; then
    case "$_itype" in
      dir)      _rdp_icon="📁" ;;
      archive)  _rdp_icon="📦" ;;
      image)    _rdp_icon="🌄" ;;
      plugin)   _rdp_icon="🧩" ;;
      exec)     _rdp_icon="⚙️"  ;;
      *)        _rdp_icon="📄" ;;
    esac
    return
  fi

  # Fallback: classify via bash functions (no daemon)
  if   [ -d "$f" ];         then _rdp_icon="📁"
  elif _is_archive "$f";    then _rdp_icon="📦"
  elif _is_image "$f";      then _rdp_icon="🌄"
  elif _is_plugin "$f";     then _rdp_icon="🧩"
  elif _is_executable "$f"; then _rdp_icon="⚙️"
  else                           _rdp_icon="📄"
  fi
}

# ── Metadata predicates ───────────────────────────────────────────────────────

_needs_metadata() {
  [[ " ${display_suffix_set:-} " == *" size "*     ]] && return 0
  [[ " ${display_suffix_set:-} " == *" time "*     ]] && return 0
  [[ " ${display_suffix_set:-} " == *" children "* ]] && return 0
  case "${sort_mode:-az}" in new|old|big|small) return 0 ;; esac
  for lvl in "${group_view_levels[@]}"; do
    case "$lvl" in year|month|date) return 0 ;; esac
  done
  return 1
}

_needs_dir_size() {
  case "${sort_mode:-az}" in big|small) return 0 ;; esac
  [[ " ${display_suffix_set:-} " == *" size "* ]] && return 0
  return 1
}

# ── Size / time formatters ────────────────────────────────────────────────────

_fmt_size_v() {
  local b="${1:-0}"
  if   (( b < 1024 ));       then _fs_out="${b}B"
  elif (( b < 1048576 ));    then _fs_out="$(( b / 1024 ))K"
  elif (( b < 1073741824 )); then _fs_out="$(( b / 1048576 ))M"
  else                            _fs_out="$(( b / 1073741824 ))G"
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
    year)      f='%Y' ;;
    month)     f='%Y-%b' ;;
    date)      f='%Y-%b-%d' ;;
    datetime)  f='%d %H:%M' ;;
    monthdate) f='%b-%d %H:%M' ;;
    full|*)    f='%Y-%b-%d %H:%M' ;;
  esac
  if [ "$_BVK_HAS_TFMT" = 1 ]; then
    printf -v _ft_out "%($f)T" "$epoch"
  else
    _ft_out=$(date -d "@$epoch" "+$f")
  fi
}
_fmt_time() { local _ft_out; _fmt_time_v "$1"; printf '%s' "$_ft_out"; }

# ── Suffix builder — supports ext | size | time | children ────────────────────

_build_suffix_v() {
  local fpath="$1" token bn
  local _fs_out _ft_out
  _bs_out=""
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
        _fmt_size_v "${item_size[$fpath]:-0}"
        _bs_out+=" | $_fs_out"
        ;;
      time)
        _fmt_time_v "${item_mtime[$fpath]:-0}"
        _bs_out+=" | $_ft_out"
        ;;
      children)
        # Only shown for directories (daemon sets children=-1 for files)
        local _ch="${item_children[$fpath]:-}"
        if [ -n "$_ch" ] && (( _ch >= 0 )) 2>/dev/null; then
          _bs_out+=" | ${_ch} items"
        fi
        ;;
    esac
  done
}
_build_suffix() { local _bs_out; _build_suffix_v "$1"; printf '%s' "$_bs_out"; }

# ── Single-row text helpers ───────────────────────────────────────────────────

_item_line_text()   { local _ilt_out; _item_line_text_v "$1"; printf '%s' "$_ilt_out"; }
_item_line_text_v() {
  local target="$1" f
  local _rdp_icon _rdp_bn _sc_icon _sc_display _bs_out
  _ilt_out=""
  (( target < 1 || target > ${#items[@]} )) && return
  f="${items[$((target-1))]}"
  _resolve_display_parts_v "$f"
  if [ -n "${display_suffix_set:-}" ]; then
    _build_suffix_v "$f"
  else
    _bs_out=""
  fi
  printf -v _ilt_out " %2d) %s %s%s" "$target" "$_rdp_icon" "$_rdp_bn" "$_bs_out"
}

# ── Flat and grouped display ──────────────────────────────────────────────────

_display_items_flat() {
  local idx=1 f line
  local _rdp_icon _rdp_bn _sc_icon _sc_display _bs_out
  local want_suffix=0
  [ -n "${display_suffix_set:-}" ] && want_suffix=1
  local hl="${_hl_index:-0}"
  for f in "${items[@]}"; do
    _resolve_display_parts_v "$f"
    if [ "$want_suffix" = 1 ]; then
      _build_suffix_v "$f"
    else
      _bs_out=""
    fi
    printf -v line " %2d) %s %s%s" "$idx" "$_rdp_icon" "$_rdp_bn" "$_bs_out"
    if [ "$idx" -eq "$hl" ]; then
      _highlight_v "$line"
      printf '%s\n' "$_hl_out"
    else
      printf '%s\n' "$line"
    fi
    idx=$(( idx + 1 ))
  done
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

  local global_idx=1
  local ck f indent indent_items lvl_idx lvl part line
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
      if [ -n "${display_suffix_set:-}" ]; then
        _build_suffix_v "$f"
      else
        _bs_out=""
      fi
      printf -v line "%s%2d) %s %s%s" "$indent_items" "$global_idx" "$_rdp_icon" "$_rdp_bn" "$_bs_out"
      if [ "$global_idx" -eq "${_hl_index:-0}" ]; then
        _highlight_v "$line"
        printf '%s\n' "$_hl_out"
      else
        printf '%s\n' "$line"
      fi
      global_idx=$(( global_idx + 1 ))
    done <<< "${key_items[$ck]}"
    echo
  done
}

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

  if $use_group; then
    _display_grouped
  else
    _display_items_flat
  fi
}

# ── Sort ──────────────────────────────────────────────────────────────────────

apply_sort() {
  local mode="${sort_mode:-az}"
  [ ${#items[@]} -eq 0 ] && return

  case "$mode" in
    az|za)
      local flag; [ "$mode" = "za" ] && flag="-r" || flag=""
      local sorted_output
      sorted_output=$(for f in "${items[@]}"; do
                        local _sort_key="${f##*/}"
                        if [[ "$_sort_key" == *.shortcut ]]; then
                          _sort_key=$(_shortcut_read_field "$f" "SHORTCUT_NAME" 2>/dev/null)
                          [ -z "$_sort_key" ] && _sort_key="${f##*/}"
                        fi
                        printf '%s\t%s\n' "$_sort_key" "$f"
                      done | sort -f $flag -t$'\t' -k1,1 | cut -f2-)
      items=()
      while IFS= read -r line; do [ -n "$line" ] && items+=("$line"); done <<< "$sorted_output"
      return
      ;;
  esac

  _ensure_meta

  local -a records=()
  for f in "${items[@]}"; do
    case "$mode" in
      new|old)   records+=("${item_mtime[$f]:-0}"$'\t'"$f") ;;
      big|small) records+=("${item_size[$f]:-0}"$'\t'"$f") ;;
    esac
  done

  local flag
  case "$mode" in
    new|big)   flag="-k1,1nr" ;;
    old|small) flag="-k1,1n"  ;;
  esac

  items=()
  while IFS= read -r line; do
    [ -n "$line" ] && items+=("$line")
  done < <(printf '%s\n' "${records[@]}" | sort -t$'\t' $flag | cut -f2-)
}

# ── Group-view key helpers ────────────────────────────────────────────────────

_gk_ext() {
  local bn="${1##*/}"
  if [[ "$bn" == *.shortcut ]]; then printf '[shortcut]'; return; fi
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

  if [ "$sc_type" == "dir" ]; then
    _sc_icon="🔑"
  else
    _sc_icon="🗝️"
  fi
  _sc_display="${sc_name}${_broken}"
}

# ── Settings UI — suffix (4 tokens: ext size time children) ──────────────────

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

_show_suffix_state() {
  local tokens=("ext" "size" "time" "children")
  local labels=("Extension (.sh)" "File size (4.2K)" "Modified time" "Children count (12 items)")
  echo
  echo "Display suffix components:"
  echo " ─────────────────────────────"
  for i in "${!tokens[@]}"; do
    local num=$((i+1)) tok="${tokens[$i]}"
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
  local tlabels=("Year only (2023)" "Month only (Mar)" "Date only (15)" "Date+Time (15 14:32)" "Month+Date+Time (Mar-15 14:32)" "Full (2023-Mar-15 14:32)")
  for i in "${!tfmts[@]}"; do
    local num=$((i+1))
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
        echo "Add by number (comma/range, e.g. 1,3 or 1-2 or 1-4):"
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

# ── Sort order settings UI ────────────────────────────────────────────────────

sort_order_settings() {
  local modes=("az" "za" "new" "old" "big" "small")
  local labels=("A → Z" "Z → A" "Newest first" "Oldest first" "Largest first" "Smallest first")
  echo
  echo "Sort order (current: ${sort_mode}):"
  for i in "${!modes[@]}"; do
    local num=$((i+1))
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
    local num=$((i+1)) lvl="${all_levels[$i]}" in_chain=false
    for gl in "${group_view_levels[@]}"; do [ "$gl" = "$lvl" ] && in_chain=true && break; done
    if $in_chain; then
      local pos=0
      for j in "${!group_view_levels[@]}"; do
        [ "${group_view_levels[$j]}" = "$lvl" ] && pos=$((j+1))
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
        for i in "${!group_view_levels[@]}"; do printf "  %d) %s\n" "$((i+1))" "${group_view_levels[$i]}"; done
        echo "Enter new order as position numbers (e.g. 2,1,3):"
        read -r -p "Order: " inp
        IFS=',' read -ra order_parts <<< "$inp"
        local -a new_chain=(); local -A used_pos=()
        for p in "${order_parts[@]}"; do
          p="${p// /}"
          if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#group_view_levels[@]} )); then
            if [ -z "${used_pos[$p]+x}" ]; then
              new_chain+=("${group_view_levels[$((p-1))]}"); used_pos[$p]=1
            fi
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

_filter_append() {
  _filter_query+="${1,,}"
  _filter_apply
}

_filter_clear() {
  _filter_query=""
  items=("${_all_items[@]}")
  _meta_loaded=false
  _vp_cache_reset
}
