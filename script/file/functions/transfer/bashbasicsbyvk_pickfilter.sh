# bashbasicsbyvk_pickfilter.sh — the rules of the file picker that python code can call (bashbasicsbyvk_filepicker, .py).
#
# ONE picker: the Transfer source picker (local_navigator in bashbasicsbyvk_transfer.sh: N opens a folder or picks a file, s-N / s-a / 1,3-5 pick
# several, v reviews and confirms).  This file adds only the RULES (which files / folders may be picked) and the runner; local_navigator and
# _nav_add_range ask _pf_filter_items / _pf_allows while _PF_ACTIVE is set, so Transfer and every other caller behave exactly as before.
#
# The commands (one string, several joined with ;  — the leading "3bvk.filepicker." / "bvk.filepicker." / "filepicker." is optional):
#   allow(files,folders)   these kinds can be picked (files · folders · both)
#   block(folders)         these kinds can NOT be picked (block(folders) = files only)
#   allow.ext(csv)         ONLY files with these extensions can be picked (csv,tsv · .csv · tar.gz); with no allow(...) it also means files only
#   block.ext(txt)         every file EXCEPT these extensions can be picked
# Folders are always listed (you need them to walk around); the rules decide what can be PICKED.  Files the rules refuse are not listed.
#
#   _pf_parse "<commands>"     fills the rules; rc 0 ok · 1 not understood (the reason is in _PF_ERR)
#   _pf_allows PATH            rc 0 when PATH can be picked
#   _pf_filter_items ARRAY     drops the files that can not be picked (folders stay)
#   _pf_run "<commands>" [start_folder]   runs the picker.  rc 0 picked (nav_selected_items = the paths) · 2 nothing picked · 64 commands not understood

_PF_ACTIVE=""; _PF_JOB=""; _PF_DESC=""; _PF_NOUN=""; _PF_ERR=""
_PF_KIND_ALLOW=(); _PF_KIND_BLOCK=(); _PF_EXT_ALLOW=(); _PF_EXT_BLOCK=()

# _pf_kind WORD → files | folders (stdout), rc 1 when it is neither
_pf_kind() {
  case "${1,,}" in
    file|files) echo files ;;
    folder|folders|dir|dirs|directory|directories) echo folders ;;
    *) return 1 ;;
  esac
}

# _pf_has WORD ARRAYNAME → rc 0 when WORD is in the array
_pf_has() {
  local -n _pfh_a="$2"; local _pfh_w
  for _pfh_w in "${_pfh_a[@]}"; do [ "$_pfh_w" = "$1" ] && return 0; done
  return 1
}

_pf_parse() {
  _PF_ERR=""; _PF_KIND_ALLOW=(); _PF_KIND_BLOCK=(); _PF_EXT_ALLOW=(); _PF_EXT_BLOCK=()
  local _pp_all="${1//$'\n'/;}" _pp_cmd _pp_verb _pp_args _pp_a _pp_k
  local -a _pp_cmds=() _pp_list=()
  IFS=';' read -ra _pp_cmds <<<"$_pp_all"                      # bvk-read-ok: splits a string (here-string), reads no terminal
  for _pp_cmd in "${_pp_cmds[@]}"; do
    _pp_cmd="${_pp_cmd#"${_pp_cmd%%[![:space:]]*}"}"; _pp_cmd="${_pp_cmd%"${_pp_cmd##*[![:space:]]}"}"
    [ -n "$_pp_cmd" ] || continue
    _pp_cmd="${_pp_cmd#3bvk.}"; _pp_cmd="${_pp_cmd#bvk.}"; _pp_cmd="${_pp_cmd#filepicker.}"
    if [[ ! "${_pp_cmd,,}" =~ ^(allow|block)(\.ext)?[[:space:]]*\((.*)\)$ ]]; then
      _PF_ERR="not understood: '$_pp_cmd'  (use allow(files,folders) · allow.ext(csv) · block(folders) · block.ext(txt), joined with ;)"
      return 1
    fi
    _pp_verb="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"; _pp_args="${BASH_REMATCH[3]}"
    _pp_list=(); IFS=',' read -ra _pp_list <<<"$_pp_args"      # bvk-read-ok: splits a string (here-string), reads no terminal
    local -a _pp_clean=()
    for _pp_a in "${_pp_list[@]}"; do
      _pp_a="${_pp_a#"${_pp_a%%[![:space:]]*}"}"; _pp_a="${_pp_a%"${_pp_a##*[![:space:]]}"}"
      _pp_a="${_pp_a//[\'\"]/}"
      [ -n "$_pp_a" ] && _pp_clean+=("$_pp_a")
    done
    if [ "${#_pp_clean[@]}" -eq 0 ]; then _PF_ERR="'$_pp_cmd' needs at least one name inside the brackets"; return 1; fi
    for _pp_a in "${_pp_clean[@]}"; do
      case "$_pp_verb" in
        allow|block)
          _pp_k=$(_pf_kind "$_pp_a") || { _PF_ERR="'$_pp_a' in '$_pp_cmd': use files or folders (extensions go in allow.ext(...) / block.ext(...))"; return 1; }
          if [ "$_pp_verb" = allow ]; then _PF_KIND_ALLOW+=("$_pp_k"); else _PF_KIND_BLOCK+=("$_pp_k"); fi ;;
        allow.ext|block.ext)
          _pp_a="${_pp_a,,}"; _pp_a="${_pp_a#\*}"; _pp_a="${_pp_a#.}"
          [ -n "$_pp_a" ] || { _PF_ERR="empty extension in '$_pp_cmd'"; return 1; }
          if [ "$_pp_verb" = allow.ext ]; then _PF_EXT_ALLOW+=("$_pp_a"); else _PF_EXT_BLOCK+=("$_pp_a"); fi ;;
      esac
    done
  done
  return 0
}

# can this KIND (files | folders) be picked at all?
_pf_kind_ok() {
  _pf_has "$1" _PF_KIND_BLOCK && return 1
  if [ "${#_PF_KIND_ALLOW[@]}" -gt 0 ]; then _pf_has "$1" _PF_KIND_ALLOW; return; fi
  [ "$1" = folders ] && [ "${#_PF_EXT_ALLOW[@]}" -gt 0 ] && return 1       # "only .csv files": nothing else is asked for
  return 0
}

# _pf_allows PATH  → rc 0 when the rules let PATH be picked
_pf_allows() {
  local _pa_p="$1" _pa_n _pa_e
  if [ -d "$_pa_p" ]; then _pf_kind_ok folders; return; fi
  _pf_kind_ok files || return 1
  _pa_n="${_pa_p##*/}"; _pa_n="${_pa_n,,}"
  if [ "${#_PF_EXT_ALLOW[@]}" -gt 0 ]; then
    for _pa_e in "${_PF_EXT_ALLOW[@]}"; do [[ "$_pa_n" == *".$_pa_e" ]] && break; _pa_e=""; done
    [ -n "$_pa_e" ] || return 1
  fi
  for _pa_e in "${_PF_EXT_BLOCK[@]}"; do [[ "$_pa_n" == *".$_pa_e" ]] && return 1; done
  return 0
}

# folders stay on the list (they are how you walk around); a file the rules refuse is not listed
_pf_filter_items() {
  local -n _pfi_a="$1"; local -a _pfi_keep=(); local _pfi_i
  for _pfi_i in "${_pfi_a[@]}"; do
    if [ -d "$_pfi_i" ] || _pf_allows "$_pfi_i"; then _pfi_keep+=("$_pfi_i"); fi
  done
  _pfi_a=("${_pfi_keep[@]}")
}

# the plain-words line under the title + the noun of the s-N suggestion
_pf_describe() {
  local _pd_f=0 _pd_d=0 _pd_e _pd_e2
  _pf_kind_ok files && _pd_f=1; _pf_kind_ok folders && _pd_d=1
  if   (( _pd_f && _pd_d )); then _PF_NOUN="items";   _PF_DESC="You can pick files and folders."
  elif (( _pd_f ));          then _PF_NOUN="files";   _PF_DESC="You can pick files only."
  elif (( _pd_d ));          then _PF_NOUN="folders"; _PF_DESC="You can pick folders only."
  else                            _PF_NOUN="items";   _PF_DESC="The rules leave nothing that can be picked."; fi
  if (( _pd_f )) && [ "${#_PF_EXT_ALLOW[@]}" -gt 0 ]; then
    _pd_e=""; for _pd_e2 in "${_PF_EXT_ALLOW[@]}"; do _pd_e+="${_pd_e:+, }.$_pd_e2"; done
    _PF_DESC+=" Only $_pd_e files."
  fi
  if (( _pd_f )) && [ "${#_PF_EXT_BLOCK[@]}" -gt 0 ]; then
    _pd_e=""; for _pd_e2 in "${_PF_EXT_BLOCK[@]}"; do _pd_e+="${_pd_e:+, }.$_pd_e2"; done
    _PF_DESC+=" Not $_pd_e files."
  fi
  _PF_DESC+=" Type a number to open a folder or pick a file; s-N picks a folder as it is; v reviews and confirms."
}

# _pf_run "<commands>" [start_folder]
_pf_run() {
  local _pr_rc
  _pf_parse "$1" || return 64
  _pf_describe
  _PF_ACTIVE=1; _PF_JOB="${BVK_PICK_FOR:-your code}"
  nav_selected_items=()
  local_navigator source "${2:-$PWD}"; _pr_rc=$?
  _PF_ACTIVE=""; _PF_JOB=""; _PF_DESC=""; _PF_NOUN=""
  [ "$_pr_rc" -eq 0 ] && [ "${#nav_selected_items[@]}" -gt 0 ] && return 0
  return 2
}
