#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_ext.sh
# adf-staging='file/delete/delete.by.extension'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.by.extension
#  Lists the extensions found in the current folder (with counts). Pick one
#  or more by number, range, or name (py,txt); a = all. Case-insensitive.
# ════════════════════════════════════════════════════════════════════════════

# Two questions, one step each (_mc_steps: u = one question back): the extensions, then Confirm delete / Back up.
# They share _fx_adf_delete_by_ext's locals (files count exts reply chosen).
_de_s_pick() {
  echo "🗑️  Delete by extension in $path:"
  local i lbl
  for i in "${!exts[@]}"; do
    lbl=".${exts[$i]}"; [ "${exts[$i]}" = "noext" ] && lbl="(no extension)"
    printf '%d) %s  (%d file(s))\n' $((i+1)) "$lbl" "${count[${exts[$i]}]}"
  done
  _mc_text reply "Select: " "Pick one or more: numbers/ranges (1,3 or 2-4), extension names (py,txt), or a = all"
  case $? in 0) ;; 1) return 1 ;; 2) return 2 ;; *) return 3 ;; esac
  [ -z "$reply" ] && { echo "🚫 Cancelled"; return 3; }

  chosen=()
  local tok idx
  local -a toks=()
  IFS=',' read -ra toks <<< "${reply// /}"
  for tok in "${toks[@]}"; do
    tok="${tok#.}"; tok="${tok,,}"
    [ -z "$tok" ] && continue
    if [ -n "${count[$tok]+x}" ] && ! [[ "$tok" =~ ^[0-9]+$ ]]; then
      chosen["$tok"]=1
    else
      for idx in $(_fxdel_pick_indices "$tok" "${#exts[@]}"); do
        chosen["${exts[$((idx-1))]}"]=1
      done
    fi
  done
  [ ${#chosen[@]} -eq 0 ] && { echo "❌ No valid extensions selected"; return 3; }
  return 0
}
_de_s_confirm() {
  local f b e rc
  selected_items=()
  for f in "${files[@]}"; do
    b="${f##*/}"; e="${b##*.}"
    [ "$e" = "$b" ] && e="noext"
    [ -n "${chosen[${e,,}]+x}" ] && selected_items+=("$f")
  done
  echo "Selected extension(s): $(printf '.%s ' "${!chosen[@]}")"
  _fxdel_run_selected; rc=$?
  case "$rc" in 1|2) return "$rc" ;; esac
  return 0
}

_fx_adf_delete_by_ext() {
  local -a files=()
  _fxdel_list_files files
  [ ${#files[@]} -eq 0 ] && { echo "No files"; return; }

  local -A count=() chosen=()
  local f b e
  for f in "${files[@]}"; do
    b="${f##*/}"; e="${b##*.}"
    [ "$e" = "$b" ] && e="noext"
    e="${e,,}"
    count["$e"]=$(( ${count[$e]:-0} + 1 ))
  done

  local -a exts=()
  mapfile -t exts < <(printf '%s\n' "${!count[@]}" | sort)

  local reply
  _mc_steps _de_s_pick _de_s_confirm
  case $? in 0) ;; 1) echo "↩️  Back"; return ;; 2) return 1 ;; *) return ;; esac
}
_fx_adf_register_fx "delete.by.extension" "_fx_adf_delete_by_ext"
