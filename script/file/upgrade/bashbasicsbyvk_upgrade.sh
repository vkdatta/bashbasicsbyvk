#!/usr/bin/env bash
# bashbasicsbyvk_upgrade.sh — the  -u  upgrade loop (an inner loop, like fx / sw / .r)
# ════════════════════════════════════════════════════════════════════════════
#  -u   opens the upgrade loop.  Pick ANY version to install — newest, older, beta.
#
#  Tabs (← / → to cycle when the input is empty):
#    📦 Stable        GitHub Releases (not marked pre-release), newest first
#    🧪 Tags (beta)   git tags, newest first — every build the auto-tagger made
#
#  Commands
#    N      install version N  (asks first)         ←/→   switch tab
#    i-N    description of version N                 m     install latest main (old -u behaviour)
#    rf     refresh the list from GitHub             u     exit        -u   close
#    fx / sw / .r   hand over to those loops         p-…   path map of the listed items
#
#  What "installed" means: pip always reports 0.0 (the version in setup.cfg is not
#  bumped per tag), so this loop records what IT installed in
#      ~/.bashbasicsbyvk/upgrade/installed
#  and marks that row  ★ installed.  Installing by other means is not seen.
#
#  Install itself is _3bvk_upgrade_core <ref>  (pip install git+<repo>@<ref>);
#  with no <ref> it installs the default branch, exactly as before.
#
#  Env:  BVK_UPG_REPO=owner/name   (default vkdatta/bashbasicsbyvk)
#        BVK_UPG_MAX=40            how many versions per tab
#
#  Uses (from the main app): _vp_* viewport, _read_choice_filtered, _inner_run,
#  _filter_reset_state, _bvk_quit, handle_staging_map
# ════════════════════════════════════════════════════════════════════════════

_UPG_REPO="${BVK_UPG_REPO:-vkdatta/bashbasicsbyvk}"
_UPG_GIT_URL="https://github.com/${_UPG_REPO}.git"
_UPG_API="https://api.github.com/repos/${_UPG_REPO}"
_UPG_WEB="https://github.com/${_UPG_REPO}"
_UPG_DIR="${HOME}/.bashbasicsbyvk/upgrade"
_UPG_MAX="${BVK_UPG_MAX:-40}"

_upg_tab="stable"          # stable | tags

declare -ga _UPG_S_TAG=() _UPG_S_NAME=() _UPG_S_DATE=() _UPG_S_BODY=()   # stable releases
declare -ga _UPG_T_TAG=()                                                # tags, newest first
declare -gA _UPG_S_IDX=()          # tag → index in the stable arrays
declare -gA _UPG_T_CACHE=()        # tag → "date<US>author<US>message" (commit info, fetched on i-N)
_UPG_S_LOADED=0
_UPG_T_LOADED=0
_UPG_S_ERR=""
_UPG_T_ERR=""

_UPG_US=$'\x1f'

# ── network (the only place that touches GitHub; override in tests) ──────────
_upg_http_get() {
  curl -fsSL --max-time 20 -H 'Accept: application/vnd.github+json' "$1" 2>/dev/null
}
_upg_ls_remote_tags() {
  command -v git >/dev/null 2>&1 || return 2
  local t=""; command -v timeout >/dev/null 2>&1 && t="timeout 25"
  GIT_TERMINAL_PROMPT=0 $t git ls-remote --tags --refs "$_UPG_GIT_URL" 2>/dev/null
}

_upg_trunc() {                   # _upg_trunc <text> <max>
  local t="$1" m="$2"
  if [ "${#t}" -gt "$m" ]; then printf '%s…' "${t:0:$((m-1))}"; else printf '%s' "$t"; fi
}

_upg_installed() {
  local f="$_UPG_DIR/installed"
  [ -r "$f" ] && head -n 1 "$f" 2>/dev/null
}
_upg_record() { mkdir -p "$_UPG_DIR" 2>/dev/null && printf '%s\n' "$1" > "$_UPG_DIR/installed"; }

# ── loading ───────────────────────────────────────────────────────────────────
_upg_load_stable() {
  _UPG_S_TAG=(); _UPG_S_NAME=(); _UPG_S_DATE=(); _UPG_S_BODY=(); _UPG_S_IDX=()
  _UPG_S_ERR=""; _UPG_S_LOADED=1
  local tmp; tmp="$(mktemp 2>/dev/null)" || { _UPG_S_ERR="no temp file"; return 1; }
  if ! _upg_http_get "$_UPG_API/releases?per_page=$_UPG_MAX" > "$tmp" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"; _UPG_S_ERR="could not reach GitHub (offline, or API rate limit)"; return 1
  fi
  local out
  out="$(python3 - "$tmp" <<'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(2)
if not isinstance(data, list):
    sys.exit(2)
US = "\x1f"
for r in data:
    if r.get("draft") or r.get("prerelease"):
        continue
    body = (r.get("body") or "").replace("\r", "")
    body = body.replace("\\", "\\\\").replace("\n", "\\n").replace(US, " ")
    name = (r.get("name") or "").replace(US, " ").replace("\n", " ")
    print(US.join([r.get("tag_name") or "", name, (r.get("published_at") or "")[:10], body]))
PYEOF
)"
  local rc=$?
  rm -f "$tmp"
  if [ $rc -ne 0 ]; then _UPG_S_ERR="GitHub answered, but not with a release list"; return 1; fi
  local t n d b i=0
  while IFS="$_UPG_US" read -r t n d b; do
    [ -n "$t" ] || continue
    _UPG_S_TAG+=("$t"); _UPG_S_NAME+=("$n"); _UPG_S_DATE+=("$d"); _UPG_S_BODY+=("$b")
    _UPG_S_IDX["$t"]=$i; i=$((i+1))
  done <<<"$out"
  return 0
}

_upg_load_tags() {
  _UPG_T_TAG=(); _UPG_T_ERR=""; _UPG_T_LOADED=1
  local raw rc
  raw="$(_upg_ls_remote_tags)"; rc=$?
  if [ $rc -eq 2 ]; then _UPG_T_ERR="git is not installed (pip needs it for this too)"; return 1; fi
  if [ $rc -ne 0 ] || [ -z "$raw" ]; then
    _UPG_T_ERR="could not list tags (offline, or the repo has none)"; return 1
  fi
  local line ref
  # newest first: the auto-tagger bumps a SemVer tag on every build, so version order = age order
  while IFS= read -r ref; do
    [ -n "$ref" ] && _UPG_T_TAG+=("$ref")
  done < <(printf '%s\n' "$raw" | sed -n 's|^[0-9a-f]\{7,64\}[[:space:]]\{1,\}refs/tags/||p' | sort -rV | head -n "$_UPG_MAX")
  [ "${#_UPG_T_TAG[@]}" -gt 0 ] || { _UPG_T_ERR="the repo has no tags"; return 1; }
  return 0
}

# ── rows ──────────────────────────────────────────────────────────────────────
_upg_rowtext() {
  local i="$1" tag="${items[$((i-1))]}" line inst; inst="$(_upg_installed)"
  if [ "$_upg_tab" = stable ]; then
    local ix="${_UPG_S_IDX[$tag]}" nm
    nm="${_UPG_S_NAME[$ix]}"
    printf -v line " %2d) 📦 %s" "$i" "$tag"
    [ -n "${_UPG_S_DATE[$ix]}" ] && line+="   ${_UPG_S_DATE[$ix]}"
    [ -n "$nm" ] && [ "$nm" != "$tag" ] && line+="  — $(_upg_trunc "$nm" 24)"
    [ "$i" -eq 1 ] && line+="  (latest)"
  else
    printf -v line " %2d) 🧪 %s" "$i" "$tag"
    [ -n "${_UPG_S_IDX[$tag]+x}" ] && line+="  ✓ stable"
    [ "$i" -eq 1 ] && line+="  (newest)"
  fi
  [ -n "$inst" ] && [ "$inst" = "$tag" ] && line+="  ★ installed"
  _vp_line="$line"
}

_upg_tab_label() {
  local a="📦 Stable" b="🧪 Tags (beta)"
  if [ "$_upg_tab" = stable ]; then printf '[%s]   %s' "$a" "$b"; else printf ' %s  [%s]' "$a" "$b"; fi
}

_upg_menu_header() {
  echo
  printf '⬆️  UPGRADE  %s   ←/→ tabs\n' "$(_upg_tab_label)"
  local inst; inst="$(_upg_installed)"
  if [ -n "$inst" ]; then printf '   installed: %s\n' "$inst"
  else printf '   installed: (not recorded yet — install once from here and it will be)\n'; fi
  if [ "$_upg_tab" = stable ] && [ -n "$_UPG_S_ERR" ]; then printf '   ⚠️  %s — rf to retry\n' "$_UPG_S_ERR"; fi
  if [ "$_upg_tab" = tags ]   && [ -n "$_UPG_T_ERR" ]; then printf '   ⚠️  %s — rf to retry\n' "$_UPG_T_ERR"; fi
  if [ "$_upg_tab" = stable ] && [ -z "$_UPG_S_ERR" ] && [ "${#items[@]}" -eq 0 ]; then
    printf '   No stable releases are published yet — try the Tags tab, or m for the latest main.\n'
  fi
  _vp_filter_header_line
}

_upg_menu_footer() {
  if [ "$_upg_tab" = stable ]; then printf '\n[Stable]  %d release(s)\n' "${#items[@]}"
  else printf '\n[Tags]  %d tag(s) — betas included, newest first\n' "${#items[@]}"; fi
  printf 'N) Install version N   i-N) Info   m) Latest main\n'
  printf 'rf) Refresh   u) Exit   -u) Close\n'
}

_upg_set_viewport() {
  _vp_mode="items"
  _vp_rowtext_fn=_upg_rowtext
  _vp_header_fn=_upg_menu_header
  _vp_footer_fn=_upg_menu_footer
  _vp_hl_fn=_vp_is_hl_single
  _msel_set=()
  _vp_input_fn=_print_input_line
  _vp_cache_reset
}

_upg_build_items() {
  imaginary_mode=false
  _filter_reset_state
  items=()
  _hl_index=0
  # the stable list is always needed (the Tags tab marks which tags are stable)
  if [ "$_UPG_S_LOADED" -eq 0 ]; then echo "⏳ Fetching releases from GitHub…"; _upg_load_stable; fi
  if [ "$_upg_tab" = stable ]; then
    items=("${_UPG_S_TAG[@]}")
  else
    if [ "$_UPG_T_LOADED" -eq 0 ]; then echo "⏳ Fetching tags from GitHub…"; _upg_load_tags; fi
    items=("${_UPG_T_TAG[@]}")
  fi
  _all_items=("${items[@]}")
}

_upg_redraw_fresh() {
  declare -F _sm_reset >/dev/null 2>&1 && _sm_reset
  _upg_build_items
  _upg_set_viewport
  _vp_render_from_top
}

_upg_tab_redraw() {
  local _old_blk_h="${_blk_h:-0}"
  _upg_build_items
  _upg_set_viewport
  _vp_tab_repaint "$_old_blk_h"
}

# ── commands ──────────────────────────────────────────────────────────────────
_upg_pick() {                    # _upg_pick <N>  → _upg_ref
  local num="$1"
  if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#items[@]}" ]; then
    echo "⚠️  Invalid version number: $num"; return 1
  fi
  _upg_ref="${items[$((num-1))]}"
  return 0
}

_upg_do_install() {              # _upg_do_install <ref|main> <label>
  local ref="$1" label="$2" ans core inst; inst="$(_upg_installed)"
  echo "⬆️  Install $label"
  [ -n "$inst" ] && [ "$inst" != "$ref" ] && echo "   currently installed: $inst"
  [ -n "$inst" ] && [ "$inst" = "$ref" ] && echo "   (this is already the installed version — it will be reinstalled)"
  read -r -p "   Continue? (y/N): " ans
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
  core="$(command -v _3bvk_upgrade_core 2>/dev/null)"
  [ -n "$core" ] || core="$SCRIPT_DIR/_3bvk_upgrade_core"
  if [ ! -f "$core" ]; then echo "❌ _3bvk_upgrade_core not found"; return 1; fi
  if [ "$ref" = main ]; then bash "$core"; else bash "$core" "$ref"; fi
  local rc=$?
  if [ $rc -eq 0 ]; then
    _upg_record "$ref"
    echo "✅ Installed $label — quit and start  o  again to run it."
    return 0
  fi
  echo "❌ pip exited with $rc — the installed version was not recorded."
  return 1
}

_upg_cmd_install() {
  _upg_pick "$1" || return 1
  _upg_do_install "$_upg_ref" "$_upg_ref"
}

_upg_print_body() {              # _upg_print_body <escaped-body>
  local body="$1" text lines
  [ -n "$body" ] || { echo "   (no description)"; return; }
  text="$(printf '%b' "$body")"
  lines="$(printf '%s\n' "$text" | wc -l)"
  printf '%s\n' "$text" | head -n 40 | sed 's/^/   /'
  [ "$lines" -gt 40 ] && echo "   … ($((lines-40)) more line(s))"
}

_upg_fetch_commit() {            # _upg_fetch_commit <tag> → fills _UPG_T_CACHE[tag]
  local tag="$1" tmp out
  [ -n "${_UPG_T_CACHE[$tag]+x}" ] && return 0
  tmp="$(mktemp 2>/dev/null)" || return 1
  if ! _upg_http_get "$_UPG_API/commits/$tag" > "$tmp" || [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi
  out="$(python3 - "$tmp" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    c = d["commit"]
except Exception:
    sys.exit(2)
US = "\x1f"
msg = (c.get("message") or "").replace("\r", "").replace("\\", "\\\\").replace("\n", "\\n").replace(US, " ")
au = c.get("author") or {}
print(US.join([(au.get("date") or "")[:10], (au.get("name") or "").replace(US, " "), msg]))
PYEOF
)"
  local rc=$?
  rm -f "$tmp"
  [ $rc -eq 0 ] && [ -n "$out" ] || return 1
  _UPG_T_CACHE["$tag"]="$out"
}

_upg_cmd_info() {
  _upg_pick "$1" || return 1
  local tag="$_upg_ref" inst; inst="$(_upg_installed)"
  if [ "$_upg_tab" = stable ]; then
    local ix="${_UPG_S_IDX[$tag]}"
    echo "📦 $tag   (stable release)"
    [ -n "${_UPG_S_NAME[$ix]}" ] && echo "   title    : ${_UPG_S_NAME[$ix]}"
    echo "   published: ${_UPG_S_DATE[$ix]:-unknown}"
    [ "$inst" = "$tag" ] && echo "   status   : ★ installed"
    echo "   page     : $_UPG_WEB/releases/tag/$tag"
    echo "   description:"
    _upg_print_body "${_UPG_S_BODY[$ix]}"
  else
    echo "🧪 $tag   (tag)"
    if [ -n "${_UPG_S_IDX[$tag]+x}" ]; then echo "   stable   : yes — it is a published release (see the Stable tab)"
    else echo "   stable   : no — a tag only, treat it as a beta"; fi
    [ "$inst" = "$tag" ] && echo "   status   : ★ installed"
    if [ -n "${_UPG_S_IDX[$tag]+x}" ]; then echo "   page     : $_UPG_WEB/releases/tag/$tag"
    else echo "   page     : $_UPG_WEB/tree/$tag"; fi
    if _upg_fetch_commit "$tag"; then
      local d a m; IFS="$_UPG_US" read -r d a m <<<"${_UPG_T_CACHE[$tag]}"
      echo "   commit   : ${d:-unknown}${a:+  by $a}"
      echo "   message  :"
      _upg_print_body "$m"
    else
      echo "   message  : (could not fetch the commit — offline, or API rate limit)"
    fi
    if [ -n "${_UPG_S_IDX[$tag]+x}" ]; then
      local ix="${_UPG_S_IDX[$tag]}"
      echo "   release notes:"
      _upg_print_body "${_UPG_S_BODY[$ix]}"
    fi
  fi
}

_upg_cmd_refresh() {
  if [ "$_upg_tab" = stable ]; then _UPG_S_LOADED=0; else _UPG_T_LOADED=0; _UPG_T_CACHE=(); fi
}

_upg_help() {
  cat <<'HLP'
⬆️  UPGRADE  (-u)   ← / → switch tabs
 📦 Stable        published GitHub releases, newest first
 🧪 Tags (beta)   every git tag, newest first (✓ stable = also a release)
 N install version N (asks first) · i-N description · m install latest main
 rf refresh from GitHub · p-… path map of items · u exit · -u close
 fx / sw / .r hand over to those loops
 ★ installed = the last version installed from THIS menu (pip itself always says 0.0)
HLP
}

# ── the loop ──────────────────────────────────────────────────────────────────
upgrade_menu() {
  local _up_saved_prefix="$group_prefix" _up_saved_force="$force_show"
  local _up_saved_all=("${_all_items[@]}")
  _upg_tab="stable"
  group_prefix=""
  force_show=false
  _fx_in_mode=1
  _sw_in_mode=1                    # enables the ←/→ tab sentinels

  local _up_choice _up_fresh
  shopt -s nullglob

  _upg_redraw_fresh

  while true; do
    _read_choice_filtered
    _up_choice="$choice"
    shopt -s nocasematch

    case "$_up_choice" in
      __sw_tab_right__|__sw_tab_left__)
        if [ "$_upg_tab" = stable ]; then _upg_tab=tags; else _upg_tab=stable; fi
        _upg_tab_redraw
        shopt -u nocasematch; continue ;;
    esac

    _up_fresh=true
    case "$_up_choice" in

      -u) echo "↩️  Closing the upgrade loop"; break ;;
      u)  echo "↩️  Closing the upgrade loop"; break ;;

      fx) _inner_next=fx; break ;;
      sw) _inner_next=sw; break ;;
      .r) _inner_next=r;  break ;;

      q) _fx_in_mode=0; _sw_in_mode=0; _bvk_quit ;;

      -h) _upg_help; _up_fresh=false ;;

      i-*)  _upg_cmd_info "${_up_choice#[iI]-}"; _up_fresh=false ;;

      m|main)
        _upg_do_install main "latest main (default branch)" || true
        _up_fresh=false ;;

      rf)
        _upg_cmd_refresh ;;                          # list is rebuilt (and re-fetched) below

      p-*)  handle_staging_map "$_up_choice"; _up_fresh=false ;;

      f)    find_menu; _up_fresh=false ;;
      disk) df -h; _up_fresh=false ;;
      ram)  free -h; _up_fresh=false ;;

      _*) _up_fresh=false ;;

      *)
        if ! [[ "$_up_choice" =~ ^[0-9]+$ ]] || [ "$_up_choice" -lt 1 ] || [ "$_up_choice" -gt "${#items[@]}" ]; then
          echo "⚠️  Invalid selection"; _up_fresh=false
        else
          _upg_cmd_install "$_up_choice" || true
          _up_fresh=false
        fi ;;
    esac

    shopt -u nocasematch
    $_up_fresh && _upg_redraw_fresh
  done

  shopt -u nocasematch
  _fx_in_mode=0
  _sw_in_mode=0
  _vp_rowtext_fn=""
  group_prefix="$_up_saved_prefix"
  force_show="$_up_saved_force"
  _all_items=("${_up_saved_all[@]}")
}
