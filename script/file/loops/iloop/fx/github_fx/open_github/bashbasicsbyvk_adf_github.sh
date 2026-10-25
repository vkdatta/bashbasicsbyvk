#!/usr/bin/env bash
# bashbasicsbyvk_adf_github.sh
# adf-staging='github_fx/open github'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — github_fx → open github        (the screens; the work lives in bashbasicsbyvk_github, helpers in bashbasicsbyvk_ghlib.sh)
#
#  fx → github_fx → open github
#    1. finds your GitHub key on this machine (environment, ~/.bashrc and the secrets files it sources, gh CLI, git-credentials,
#       netrc). None found → says so and tells you to put  export GITHUB_TOKEN="..."  in ~/.bashrc (or the secrets file it sources).
#    2. shows ALL your repos.  Pick one → two tabs, like the upgrade loop:   📦 Stable   🔖 Tags      (←/→)
#    3. on a tab, pick rows:   N · 1,3-5 · a (all) · a-2 (all except 2)   → an action menu, or type the action directly:
#         c        create a stable release (Stable tab) / a tag (Tags tab)
#         e[-SEL]  edit: title, notes, tag message, commit message — one item (editor) or many (set / find+replace / prepend / append)
#         r[-SEL]  rename: prefix, suffix, find+replace, regex, or each by hand — every new name is checked for conflicts first
#         d[-SEL]  delete: release only / release + tag (Stable) · tag only / tag + release (Tags)
#         g[-SEL]  download = clone at that tag, with a depth or the full history, optionally with the release notes and files
#         i-N      info      rf  reload      u  back
#
#  Your key is never typed, shown, stored or put on a command line: the engine reads it itself (see its header).
# ════════════════════════════════════════════════════════════════════════════

_GHX_LOGIN=""; _GHX_SRC=""; _GHX_MSG=""; _GHX_NAV=""
_GHX_REPO=""; _GHX_TAB="stable"
declare -ga _GHX_R_NAME=() _GHX_R_VIS=() _GHX_R_FLAGS=() _GHX_R_PUSHED=() _GHX_R_DESC=()
declare -ga _GHX_S_TAG=() _GHX_S_NAME=() _GHX_S_DATE=() _GHX_S_FLAGS=()
declare -ga _GHX_T_TAG=() _GHX_T_TYPE=() _GHX_T_SHA=() _GHX_T_STATE=()
declare -gA _GHX_S_HAS=()
declare -ga _GHX_PICK=()
_GHX_BUSY=""

# ── key ─────────────────────────────────────────────────────────────────────
_ghx_no_key_help() {
  echo
  echo "🔑 No GitHub key was found on this machine."
  echo "   Put a token in your ~/.bashrc, or in the secrets file your ~/.bashrc sources:"
  echo
  echo "       export GITHUB_TOKEN=\"ghp_xxxxxxxxxxxxxxxxxxxx\""
  echo
  echo "   then open a new shell (or run  source ~/.bashrc ) and start  o  again."
  echo "   Make one at GitHub → Settings → Developer settings → Personal access tokens"
  echo "   (classic: scope 'repo' · fine-grained: Contents + Metadata, read and write)."
  echo
  echo "   Looked at:"
  local f; for f in "$@"; do echo "     • $f"; done
}

_ghx_sign_in() {                 # sets _GHX_LOGIN / _GHX_SRC and exports BVK_GH_PICK, or leaves a message in _GHX_MSG
  local out kind
  local -a f=()
  _GHX_MSG=""
  out="$(_gh_run auth 2>/dev/null)"
  IFS="$_GH_US" read -r -a f <<<"$out"
  kind="${f[0]:-}"
  case "$kind" in
    OK)       _GHX_LOGIN="${f[1]}"; _GHX_SRC="${f[2]}"; export BVK_GH_PICK="${f[3]}"; return 0 ;;
    NONE)     _GHX_MSG="none"; _GHX_NONE=("${f[@]:1}"); return 1 ;;
    REJECTED) _GHX_MSG="GitHub rejected the key it found (${f[1]:-expired or revoked}). Put a fresh token in ~/.bashrc or the secrets file it sources, then start o again."; return 1 ;;
    *)        _GHX_MSG="${f[1]:-could not reach GitHub (offline?)}"; return 1 ;;
  esac
}

# ── data ────────────────────────────────────────────────────────────────────
_ghx_fetch_repos() {
  local out n v fl p d
  out="$(_gh_run repos 2>/dev/null)" || return 1
  _GHX_R_NAME=(); _GHX_R_VIS=(); _GHX_R_FLAGS=(); _GHX_R_PUSHED=(); _GHX_R_DESC=()
  while IFS="$_GH_US" read -r n v fl p d; do
    [ -n "$n" ] || continue
    _GHX_R_NAME+=("$n"); _GHX_R_VIS+=("$v"); _GHX_R_FLAGS+=("$fl"); _GHX_R_PUSHED+=("$p"); _GHX_R_DESC+=("$d")
  done <<<"$out"
  return 0
}

_ghx_load_repo() {               # releases (stable) + tags of $_GHX_REPO
  local rel tags t n d id fl b ty sha rid st
  rel="$(_gh_run releases "$_GHX_REPO" 2>/dev/null)" || { _GHX_MSG="could not read the releases of $_GHX_REPO (offline, no access, or API rate limit)"; return 1; }
  tags="$(_gh_run tags "$_GHX_REPO" 2>/dev/null)"    || { _GHX_MSG="could not read the tags of $_GHX_REPO"; return 1; }
  _GHX_S_TAG=(); _GHX_S_NAME=(); _GHX_S_DATE=(); _GHX_S_FLAGS=(); _GHX_S_HAS=()
  _GHX_T_TAG=(); _GHX_T_TYPE=(); _GHX_T_SHA=(); _GHX_T_STATE=()
  while IFS="$_GH_US" read -r t n d id fl b; do
    [ -n "$t" ] || continue
    _GHX_S_TAG+=("$t"); _GHX_S_NAME+=("$n"); _GHX_S_DATE+=("$d"); _GHX_S_FLAGS+=("$fl"); _GHX_S_HAS["$t"]=1
  done <<<"$rel"
  while IFS="$_GH_US" read -r t ty sha rid st; do
    [ -n "$t" ] || continue
    _GHX_T_TAG+=("$t"); _GHX_T_TYPE+=("$ty"); _GHX_T_SHA+=("$sha"); _GHX_T_STATE+=("$st")
  done <<<"$tags"
  return 0
}

_ghx_reload() {
  _ghx_load_repo || echo "❌ ${_GHX_MSG:-reload failed}"
}

# ── repos screen ────────────────────────────────────────────────────────────
ghp_build() {
  local i rows=()
  for i in "${!_GHX_R_NAME[@]}"; do rows+=("${_GHX_R_NAME[$i]} ${_GHX_R_VIS[$i]} ${_GHX_R_DESC[$i]}"); done
  _xui_begin_items "${rows[@]}"
}

ghp_row() {
  _xui_slot "$1"; local s="$_XUI_SLOT" ic="📂" tag=""
  [ "${_GHX_R_VIS[$s]}" = private ] && ic="🔒"
  case "${_GHX_R_FLAGS[$s]}" in *F*) tag+="  fork" ;; esac
  case "${_GHX_R_FLAGS[$s]}" in *A*) tag+="  archived" ;; esac
  printf -v _vp_line ' %2d) %s %-34s %s%s' "$1" "$ic" "$(_xui_trunc "${_GHX_R_NAME[$s]}" 34)" "${_GHX_R_PUSHED[$s]:-—}" "$tag"
}

ghp_header() {
  echo; echo "🐙 GitHub   ${#_GHX_R_NAME[@]} repo(s) · signed in as ${_GHX_LOGIN}"
  printf '🔑 key: %s\n' "$_GHX_SRC"
  printf '📂 downloads go to: %s\n' "$_GHX_NAV"
  _vp_filter_header_line
}

ghp_footer() { _mc_footer "#Select a number to open that repo" "=:filter" "rf" "u"; }

_ghp_cmd() {
  case "$1" in
    rf) _ghx_fetch_repos || echo "❌ Reload failed."; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { _bvk_invalid; return 1; }
      _GHX_REPO="${_GHX_R_NAME[$_XUI_SLOT]}"; _GHX_TAB="stable"
      if ! _ghx_load_repo; then echo "❌ $_GHX_MSG"; return 1; fi
      _xui_enter
      _xui_screen ghr
      _xui_loop _ghr_cmd
      _xui_leave
      return 0 ;;
    fx|sw|api|.r|-u) echo "↩️  Go back with  u  first."; return 1 ;;
    *) return 9 ;;
  esac
}

# ── repo screen: Stable / Tags ──────────────────────────────────────────────
_bvk_tabs_register "📦 Stable" "🔖 Tags"   # tab bar: tappable (bashbasicsbyvk_mouse.sh)
_ghx_tab_label() {
  local a="📦 Stable" b="🔖 Tags"
  if [ "$_GHX_TAB" = stable ]; then printf '[%s]   %s' "$a" "$b"; else printf ' %s  [%s]' "$a" "$b"; fi
}

ghr_build() {
  local i rows=()
  if [ "$_GHX_TAB" = stable ]; then
    for i in "${!_GHX_S_TAG[@]}"; do rows+=("${_GHX_S_TAG[$i]} ${_GHX_S_NAME[$i]}"); done
  else
    for i in "${!_GHX_T_TAG[@]}"; do rows+=("${_GHX_T_TAG[$i]} ${_GHX_T_TYPE[$i]} ${_GHX_T_STATE[$i]}"); done
  fi
  _xui_begin_items "${rows[@]}"
}

ghr_row() {
  _xui_slot "$1"; local s="$_XUI_SLOT" line
  if [ "$_GHX_TAB" = stable ]; then
    printf -v line ' %2d) 📦 %-18s' "$1" "$(_xui_trunc "${_GHX_S_TAG[$s]}" 18)"
    [ -n "${_GHX_S_DATE[$s]}" ] && line+="  ${_GHX_S_DATE[$s]}"
    [ -n "${_GHX_S_NAME[$s]}" ] && [ "${_GHX_S_NAME[$s]}" != "${_GHX_S_TAG[$s]}" ] && line+="  — $(_xui_trunc "${_GHX_S_NAME[$s]}" 22)"
    [ "$s" -eq 0 ] && line+="  (latest)"
  else
    printf -v line ' %2d) 🔖 %-18s %-11s' "$1" "$(_xui_trunc "${_GHX_T_TAG[$s]}" 18)" "${_GHX_T_TYPE[$s]}"
    case "${_GHX_T_STATE[$s]}" in stable) line+=" ✓ stable" ;; pre) line+=" pre-release" ;; draft) line+=" draft" ;; esac
    [ "$s" -eq 0 ] && line+="  (newest)"
  fi
  _vp_line="$line"
}

ghr_header() {
  echo; printf '🐙 %s   %s   ←/→ tabs\n' "$_GHX_REPO" "$(_ghx_tab_label)"
  if [ "${#items[@]}" -eq 0 ]; then
    if [ "$_GHX_TAB" = stable ]; then echo "   No stable releases yet — c creates one, or open the Tags tab."; else echo "   No tags yet — c creates one."; fi
  fi
  _vp_filter_header_line
}

ghr_footer() {
  local what="release(s)"; [ "$_GHX_TAB" = tags ] && what="tag(s)"
  _mc_footer "#${#items[@]} $what — select: N · 1,3-5 · a (all) · a-2 (all except 2)" "c:Create" "e:Edit" "r:Rename" "d:Delete" "g:Download" "|" "i-N:Info" "rf" "u"
}

# the picked display rows (_XUI_SEL) → tag names in _GHX_PICK
_ghx_pick_names() {
  _GHX_PICK=(); local r
  for r in "${_XUI_SEL[@]}"; do
    _xui_slot "$r"
    if [ "$_GHX_TAB" = stable ]; then _GHX_PICK+=("${_GHX_S_TAG[$_XUI_SLOT]}"); else _GHX_PICK+=("${_GHX_T_TAG[$_XUI_SLOT]}"); fi
  done
}

_ghx_show_picked() {
  local t n=0
  for t in "${_GHX_PICK[@]}"; do
    n=$((n+1)); [ "$n" -le 12 ] && echo "     • $t"
  done
  [ "$n" -gt 12 ] && echo "     … and $((n-12)) more"
}

# a job folder: plain files, so nothing a person typed is ever quoted, evaluated or put on a command line
_ghx_job_new() {
  _GHX_JOB="$(mktemp -d 2>/dev/null)" || { echo "❌ no temp folder"; return 1; }
  printf '%s' "$_GHX_REPO" > "$_GHX_JOB/repo"
}
_ghx_job_tags() { local t; : > "$_GHX_JOB/tags"; for t in "${_GHX_PICK[@]}"; do printf '%s\n' "$t" >> "$_GHX_JOB/tags"; done; }
_ghx_job_run() {                 # _ghx_job_run <engine command> [extra]
  local cmd="$1"; shift
  echo
  declare -F _sl_hold >/dev/null 2>&1 && _sl_hold            # git prints its own progress: smartload stays out of the way
  _gh_run "$cmd" --job "$_GHX_JOB" "$@"; local rc=$?
  declare -F _sl_release >/dev/null 2>&1 && _sl_release
  rm -rf "$_GHX_JOB"; _GHX_JOB=""
  echo
  return $rc
}

# text in the editor (notes and messages are several lines); keeps every byte, trailing newlines included
_ghx_editor() {                  # _ghx_editor <initial-text>  → $_GHX_TEXT ; rc 1 = nothing saved
  local f x; f="$(mktemp 2>/dev/null)" || return 1
  printf '%s' "$1" > "$f"
  _rl_editor "$f"
  x="$(cat "$f"; printf x)"; rm -f "$f"
  _GHX_TEXT="${x%x}"
  return 0
}

_ghx_current() {                 # _ghx_current <tag> <field>  → raw text on stdout
  _gh_run get "$_GHX_REPO" "$1" "$2" 2>/dev/null
}

_ghx_field_name() { case "$1" in t) echo "release title" ;; n) echo "release notes" ;; m) echo "tag message" ;; c) echo "commit message" ;; esac; }
_ghx_field_file() { case "$1" in t) echo title ;; n) echo body ;; m) echo tag_message ;; c) echo commit_message ;; esac; }

# ask what to do with ONE field of every picked item → writes <field>.mode/.a/.b into the job
_ghx_ask_field() {
  local k="$1" name file mode cur new a b multi=0
  name="$(_ghx_field_name "$k")"; file="$(_ghx_field_file "$k")"
  [[ "$k" == [nmc] ]] && multi=1
  if [ "${#_GHX_PICK[@]}" -eq 1 ]; then
    cur="$(_ghx_current "${_GHX_PICK[0]}" "$file"; printf x)"; cur="${cur%x}"
    if [ "$multi" = 1 ]; then
      echo "   ✏️  $name of ${_GHX_PICK[0]} — the editor opens; save and close it."
      _ghx_editor "$cur" || return 1; new="$_GHX_TEXT"
    else
      IFS= read -e -r -i "$cur" -p "   New $name: " new || return 1
    fi
    if [ "$new" = "$cur" ]; then echo "   (the $name is unchanged — skipped)"; return 2; fi
    printf '%s' set > "$_GHX_JOB/$file.mode"; printf '%s' "$new" > "$_GHX_JOB/$file.a"
    return 0
  fi
  _bvk_menu mode -t "How to change the $name of ${#_GHX_PICK[@]} items" -i "✏️" \
    "s:Set it to one new text for all" "f:Find and replace a piece of text" "p:Add text at the start" "a:Add text at the end" || return 1
  local hint=""; [ "$multi" = 1 ] && hint="  (type \\n for a new line)"
  case "$mode" in
    s) if [ "$multi" = 1 ]; then echo "   ✏️  the editor opens: write the text every item gets."; _ghx_editor "" || return 1; a="$_GHX_TEXT"
       else IFS= read -r -p "   New $name for all: " a || return 1; fi
       printf '%s' set > "$_GHX_JOB/$file.mode"; printf '%s' "$a" > "$_GHX_JOB/$file.a" ;;
    f) IFS= read -r -p "   Find$hint: " a || return 1; [ -n "$a" ] || { echo "   (nothing to find)"; return 2; }
       IFS= read -r -p "   Replace with (empty = remove it)$hint: " b || return 1
       [ "$multi" = 1 ] && { a="$(printf '%b' "$a")"; b="$(printf '%b' "$b")"; }
       printf '%s' replace > "$_GHX_JOB/$file.mode"; printf '%s' "$a" > "$_GHX_JOB/$file.a"; printf '%s' "$b" > "$_GHX_JOB/$file.b" ;;
    p|a) IFS= read -r -p "   Text to add (used exactly as typed — include a space or \\n yourself)$hint: " a || return 1
       [ -n "$a" ] || return 2
       [ "$multi" = 1 ] && a="$(printf '%b' "$a")"
       [ "$mode" = p ] && printf '%s' prepend > "$_GHX_JOB/$file.mode" || printf '%s' append > "$_GHX_JOB/$file.mode"
       printf '%s' "$a" > "$_GHX_JOB/$file.a" ;;
  esac
  return 0
}

# ── actions ─────────────────────────────────────────────────────────────────
_ghx_edit() {
  local fields k ans any=0 rc
  _bvk_menu fields -m -t "Edit ${#_GHX_PICK[@]} item(s)" -i "✏️" -q "What do you want to change?" \
    "t:Release title" "n:Release notes" "m:Tag message" "c:Commit message" || return 1
  [ -n "$fields" ] || { echo "🚫 Nothing chosen."; return 1; }
  _ghx_job_new || return 1
  for k in $fields; do
    _ghx_ask_field "$k"; rc=$?
    [ "$rc" = 1 ] && { rm -rf "$_GHX_JOB"; echo "🚫 Cancelled"; return 1; }
    [ "$rc" = 0 ] && any=1
  done
  [ "$any" = 1 ] || { rm -rf "$_GHX_JOB"; echo "📜  Nothing to change."; return 1; }
  _ghx_job_tags
  echo; echo "✏️  Change:"
  for k in t n m c; do [ -f "$_GHX_JOB/$(_ghx_field_file "$k").mode" ] && echo "   • $(_ghx_field_name "$k")  ($(<"$_GHX_JOB/$(_ghx_field_file "$k").mode"))"; done
  echo "   on:"; _ghx_show_picked
  if [ -f "$_GHX_JOB/commit_message.mode" ]; then
    echo
    echo "⚠️  A commit cannot be edited in place: this makes a NEW commit with the same files and parents"
    echo "   (signatures are lost) and moves the tag(s) to it. Branches keep the old commit unless you say so."
    _bvk_yn ans "Also move any branch that ends exactly at the old commit?" -d n
    case "$ans" in [yY]*) printf '1' > "$_GHX_JOB/move_branch" ;; esac
  fi
  if [ -f "$_GHX_JOB/tag_message.mode" ]; then echo "   📜 A tag message change replaces the tag (same commit); a lightweight tag becomes annotated."; fi
  _bvk_yn ans "Apply to ${#_GHX_PICK[@]} item(s)?" -d n
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) rm -rf "$_GHX_JOB"; echo "🚫 Cancelled"; return 1 ;; esac
  _ghx_job_run edit
  _ghx_reload
}

_ghx_rename() {
  local rule a b t new n=0 ans rc
  local one=""; [ "${#_GHX_PICK[@]}" -eq 1 ] && one="m:Type the new name"
  if [ -n "$one" ]; then rule=m
  else
    _bvk_menu rule -t "Rename ${#_GHX_PICK[@]} items" -i "🔤" \
      "p:Add a prefix to every name" "s:Add a suffix to every name" "f:Find and replace text in every name" "x:Regex replace (\\1 = a group)" "m:Type each new name" || return 1
  fi
  _ghx_job_new || return 1
  _ghx_job_tags
  case "$rule" in
    p) _xui_ask "Prefix" || { rm -rf "$_GHX_JOB"; return 1; }; printf '%s' prefix > "$_GHX_JOB/rule.mode"; printf '%s' "$_XUI_IN" > "$_GHX_JOB/rule.a" ;;
    s) _xui_ask "Suffix" || { rm -rf "$_GHX_JOB"; return 1; }; printf '%s' suffix > "$_GHX_JOB/rule.mode"; printf '%s' "$_XUI_IN" > "$_GHX_JOB/rule.a" ;;
    f) _xui_ask "Find" || { rm -rf "$_GHX_JOB"; return 1; }; a="$_XUI_IN"
       IFS= read -e -r -p "   Replace with (empty = remove it): " b
       printf '%s' replace > "$_GHX_JOB/rule.mode"; printf '%s' "$a" > "$_GHX_JOB/rule.a"; printf '%s' "$b" > "$_GHX_JOB/rule.b" ;;
    x) _xui_ask "Pattern (python regex, e.g.  ^v(.*)\$ )" || { rm -rf "$_GHX_JOB"; return 1; }; a="$_XUI_IN"
       IFS= read -e -r -p "   Replacement (e.g.  release-\\1 ): " b
       printf '%s' regex > "$_GHX_JOB/rule.mode"; printf '%s' "$a" > "$_GHX_JOB/rule.a"; printf '%s' "$b" > "$_GHX_JOB/rule.b" ;;
    m) printf '%s' manual > "$_GHX_JOB/rule.mode"; : > "$_GHX_JOB/map"
       for t in "${_GHX_PICK[@]}"; do
         IFS= read -e -r -i "$t" -p "   $t → " new || { rm -rf "$_GHX_JOB"; echo "🚫 Cancelled"; return 1; }
         printf '%s\t%s\n' "$t" "$new" >> "$_GHX_JOB/map"
       done ;;
    *) rm -rf "$_GHX_JOB"; return 1 ;;
  esac
  echo; echo "🔤 Checking every new name against the tags and releases of $_GHX_REPO …"
  _gh_run rename --job "$_GHX_JOB" --plan; rc=$?
  if [ "$rc" != 0 ]; then rm -rf "$_GHX_JOB"; echo; return 1; fi
  echo "   Releases follow their tags; a release title that equals the old tag name is renamed too."
  _bvk_yn ans "Rename now?" -d n
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) rm -rf "$_GHX_JOB"; echo "🚫 Cancelled"; return 1 ;; esac
  _ghx_job_run rename
  _ghx_reload
}

_ghx_delete() {
  local what ans
  if [ "$_GHX_TAB" = stable ]; then
    _bvk_menu what -t "Delete ${#_GHX_PICK[@]} stable release(s)" -i "🗑️" \
      "r:Delete the release only (the git tag stays)" "b:Delete the release AND its git tag" || return 1
  else
    _bvk_menu what -t "Delete ${#_GHX_PICK[@]} tag(s)" -i "🗑️" \
      "t:Delete the tag only (a release on it becomes a draft on GitHub)" "b:Delete the tag AND its release" || return 1
  fi
  echo; echo "🗑️  Delete from $_GHX_REPO  (cannot be undone from here):"; _ghx_show_picked
  case "$what" in r) echo "   → release only" ;; t) echo "   → tag only" ;; b) echo "   → release and tag" ;; esac
  _bvk_yn ans "Delete ${#_GHX_PICK[@]} item(s)?" -d none
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
  _ghx_job_new || return 1; _ghx_job_tags
  case "$what" in r) printf 1 > "$_GHX_JOB/release" ;; t) printf 1 > "$_GHX_JOB/tag" ;; b) printf 1 > "$_GHX_JOB/release"; printf 1 > "$_GHX_JOB/tag" ;; esac
  _ghx_job_run delete
  _ghx_reload
}

_ghx_download() {
  local how depth=0 withrel ans dest def=n
  _bvk_menu how -t "Download ${#_GHX_PICK[@]} item(s) — clone at the tag" -i "⬇️" \
    "d:With depth — only the last N commits (fast, small)" "f:Without depth — the full history" || return 1
  if [ "$how" = d ]; then
    _xui_ask "Depth (number of commits)" 1 || return 1
    [[ "$_XUI_IN" =~ ^[0-9]+$ ]] && [ "$_XUI_IN" -ge 1 ] || { echo "❌ Depth must be a number, 1 or more."; return 1; }
    depth="$_XUI_IN"
  fi
  [ "$_GHX_TAB" = stable ] && def=y
  _bvk_yn withrel "Also download the release notes and files (assets) of tags that have a release?" -d "$def"
  _xui_ask "Download into" "$_GHX_NAV" || return 1
  dest="${_XUI_IN/#\~/$HOME}"
  echo; echo "⬇️  ${#_GHX_PICK[@]} item(s) → $dest/$(_xui_trunc "${_GHX_REPO#*/}" 30)-<tag>/   ($([ "$depth" -gt 0 ] && echo "depth $depth" || echo "full history")$([[ "$withrel" == [yY]* ]] && echo ", with release notes and files"))"
  _ghx_show_picked
  _bvk_yn ans "Start?" -d y
  case "$ans" in [yY]|[yY][eE][sS]) ;; *) echo "🚫 Cancelled"; return 1 ;; esac
  _ghx_job_new || return 1; _ghx_job_tags
  printf '%s' "$dest" > "$_GHX_JOB/dest"; printf '%s' "$depth" > "$_GHX_JOB/depth"
  [[ "$withrel" == [yY]* ]] && printf 1 > "$_GHX_JOB/with_release"
  _ghx_job_run clone
}

_ghx_create() {
  local tag target title ans msg="" body="" exists=0 t
  if [ "$_GHX_TAB" = stable ]; then echo; echo "📦 New stable release in $_GHX_REPO"; else echo; echo "🔖 New tag in $_GHX_REPO"; fi
  _xui_ask "Tag name (e.g. v1.2.0)" || return 1
  tag="$_XUI_IN"
  for t in "${_GHX_T_TAG[@]}"; do [ "$t" = "$tag" ] && exists=1; done
  if [ "$exists" = 1 ]; then
    if [ "$_GHX_TAB" = tags ]; then echo "❌ The tag '$tag' already exists."; return 1; fi
    echo "   '$tag' is an existing tag — the release is attached to it."
  else
    IFS= read -e -r -p "   Branch, tag or commit to build it from (Enter = the default branch): " target
    _bvk_yn ans "Make it an annotated tag with a message?" -d n
    case "$ans" in [yY]*) echo "   ✏️  the editor opens: write the tag message."; _ghx_editor "" && msg="$_GHX_TEXT" ;; esac
  fi
  if [ "$_GHX_TAB" = tags ]; then
    _ghx_job_new || return 1
    printf '%s' "$tag" > "$_GHX_JOB/tag"; printf '%s' "$target" > "$_GHX_JOB/target"; printf '%s' "$msg" > "$_GHX_JOB/tag_message"
    _ghx_job_run create-tag && {
      _bvk_yn ans "Also publish a stable release for it?" -d n
      case "$ans" in [yY]*) _ghx_create_release_for "$tag" ;; esac; }
    _ghx_reload; return 0
  fi
  IFS= read -e -r -p "   Release title (Enter = the tag name): " title
  _bvk_yn ans "Write the release notes now (opens the editor)?" -d y
  case "$ans" in [yY]*) _ghx_editor "" && body="$_GHX_TEXT" ;; esac
  _ghx_job_new || return 1
  printf '%s' "$tag" > "$_GHX_JOB/tag"; printf '%s' "$target" > "$_GHX_JOB/target"; printf '%s' "$msg" > "$_GHX_JOB/tag_message"
  printf '%s' "$title" > "$_GHX_JOB/title"; printf '%s' "$body" > "$_GHX_JOB/body"
  _ghx_job_run create-release
  _ghx_reload
}

_ghx_create_release_for() {      # a tag that was just made → its stable release
  local title body="" ans
  IFS= read -e -r -p "   Release title (Enter = the tag name): " title
  _bvk_yn ans "Write the release notes now (opens the editor)?" -d y
  case "$ans" in [yY]*) _ghx_editor "" && body="$_GHX_TEXT" ;; esac
  _ghx_job_new || return 1
  printf '%s' "$1" > "$_GHX_JOB/tag"; printf '%s' "$title" > "$_GHX_JOB/title"; printf '%s' "$body" > "$_GHX_JOB/body"
  _ghx_job_run create-release
}

_ghx_actions() {                 # rows picked (_XUI_SEL) → what to do with them
  local act
  _ghx_pick_names
  _bvk_menu act -t "${#_GHX_PICK[@]} selected in $_GHX_REPO" -i "🐙" \
    "e:Edit title, notes, tag message, commit message" "r:Rename" "d:Delete" "g:Download (clone at the tag)" "i:Info" || return 1
  _ghx_run_action "$act"
}

_ghx_run_action() {
  case "$1" in
    e) _ghx_edit ;;
    r) _ghx_rename ;;
    d) _ghx_delete ;;
    g) _ghx_download ;;
    i) local t; for t in "${_GHX_PICK[@]}"; do _gh_run info "$_GHX_REPO" "$t"; echo; done ;;
  esac
}

_ghr_cmd() {
  case "$1" in
    __sw_tab_right__|__sw_tab_left__)
      if [ "$_GHX_TAB" = stable ]; then _GHX_TAB=tags; else _GHX_TAB=stable; fi
      return 3 ;;
    rf) _ghx_reload; return 0 ;;
    c)  _ghx_create; return 0 ;;
    i-*)
      _xui_parse_sel "${1#*-}" || return 1
      _ghx_pick_names; _ghx_run_action i; return 1 ;;
    e|e-*|r|r-*|d|d-*|g|g-*)
      _xui_select_rows "SELECT" "🐙  Which items?" "$1" || return 1
      _ghx_pick_names; _ghx_run_action "${1:0:1}"; return 0 ;;
    [0-9]*|a|a-*)
      _xui_parse_sel "$1" || return 1
      _ghx_actions; return 0 ;;
    fx|sw|api|.r|-u) return 9 ;;
    *) return 9 ;;
  esac
}

# ── the button ──────────────────────────────────────────────────────────────
_fx_adf_github() {
  _dep_need -c "GitHub" github || return 1
  _GHX_NAV="${_fx_outer_path:-$path}"                       # the navigation path, NOT $PWD
  if ! _gh_locate; then echo "❌ GitHub needs Python 3 and bashbasicsbyvk_github (the engine) — not found."; return 1; fi
  _GHX_NONE=()
  if ! _ghx_sign_in; then
    if [ "$_GHX_MSG" = none ]; then _ghx_no_key_help "${_GHX_NONE[@]}"; else echo "❌ $_GHX_MSG"; fi
    return 1
  fi
  if ! _ghx_fetch_repos; then echo "❌ Could not read your repos from GitHub (offline, or API rate limit)."; return 1; fi
  if [ "${#_GHX_R_NAME[@]}" -eq 0 ]; then echo "📜  GitHub shows no repo for $_GHX_LOGIN."; return 1; fi
  _xui_enter
  _xui_screen ghp
  _xui_loop _ghp_cmd
  _xui_leave
  unset BVK_GH_PICK
}

_fx_adf_register "open github" "_fx_adf_github" "github_fx/open github"
