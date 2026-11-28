#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_ext.sh
# adf-staging='file/delete/delete.by.extension'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.by.extension
#  Lists the extensions found in the current folder (with counts) on the ONE pick screen (_pick_groups, template MG2374).
#  s-N / s-1,3 / s-a (or a name: py,txt) take whole extensions · N goes inside an extension and lists its files one by one.
# ════════════════════════════════════════════════════════════════════════════

# Two questions, one step each (_mc_steps: u = one question back): the extensions (the pick screen, MG2374), then Confirm delete / Back up.
# They share _fx_adf_delete_by_ext's locals (files exts label ext_of); selected_items is the global every delete flow fills.
_de_s_pick() {
  _pick_groups -i 🗑 -w to "extensions" "delete" "extensions" "$path" files exts label ext_of selected_items
  case $? in 0) return 0 ;; 1) return 1 ;; 2) return 2 ;; *) return 3 ;; esac
}
_de_s_confirm() {
  local rc
  _sel_summary selected_items "🗑  About to delete"
  _sel_preview selected_items
  _fxdel_run_selected; rc=$?
  case "$rc" in 1|2) return "$rc" ;; esac
  return 0
}

_fx_adf_delete_by_ext() {
  local -a files=()
  _fxdel_list_files files
  [ ${#files[@]} -eq 0 ] && { echo "No files"; return; }

  local -A count=() label=() ext_of=()
  local f b e
  for f in "${files[@]}"; do
    b="${f##*/}"; e="${b##*.}"
    [ "$e" = "$b" ] && e="noext"
    e="${e,,}"
    ext_of["$f"]="$e"
    count["$e"]=$(( ${count[$e]:-0} + 1 ))
  done

  local -a exts=()
  mapfile -t exts < <(printf '%s\n' "${!count[@]}" | sort)
  for e in "${exts[@]}"; do
    if [ "$e" = noext ]; then label["$e"]="(no extension)  (${count[$e]} file(s))"
    else label["$e"]=".$e  (${count[$e]} file(s))"; fi
  done

  _mc_steps _de_s_pick _de_s_confirm
  case $? in 0) ;; 1) echo "↩  Back"; return ;; 2) return 1 ;; *) return ;; esac
}
_fx_adf_register_fx "delete.by.extension" "_fx_adf_delete_by_ext"
