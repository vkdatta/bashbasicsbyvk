#!/usr/bin/env bash
# bashbasicsbyvk_adf_delete_ext.sh
# adf-staging='file_fx/delete/delete.by.extension'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — delete.by.extension
#  Lists the extensions found in the current folder (with counts). Pick one
#  or more by number, range, or name (py,txt); a = all. Case-insensitive.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_delete_by_ext() {
  local -a files=()
  _fxdel_list_files files
  [ ${#files[@]} -eq 0 ] && { echo "No files"; return; }

  local -A count=()
  local f b e
  for f in "${files[@]}"; do
    b="${f##*/}"; e="${b##*.}"
    [ "$e" = "$b" ] && e="noext"
    e="${e,,}"
    count["$e"]=$(( ${count[$e]:-0} + 1 ))
  done

  local -a exts=()
  mapfile -t exts < <(printf '%s\n' "${!count[@]}" | sort)

  echo "🗑️  Delete by extension in $path:"
  local i lbl
  for i in "${!exts[@]}"; do
    lbl=".${exts[$i]}"; [ "${exts[$i]}" = "noext" ] && lbl="(no extension)"
    printf '%d) %s  (%d file(s))\n' $((i+1)) "$lbl" "${count[${exts[$i]}]}"
  done
  echo "Pick one or more: numbers/ranges (1,3 or 2-4), extension names (py,txt), or a = all"
  local reply
  read -p "Choice: " reply
  [ -z "$reply" ] && { echo "🚫 Cancelled"; return; }
  case "${reply,,}" in u) echo "↩️  Back"; return ;; q) _bvk_quit ;; esac

  local -A chosen=()
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
  [ ${#chosen[@]} -eq 0 ] && { echo "❌ No valid extensions selected"; return; }

  selected_items=()
  for f in "${files[@]}"; do
    b="${f##*/}"; e="${b##*.}"
    [ "$e" = "$b" ] && e="noext"
    [ -n "${chosen[${e,,}]+x}" ] && selected_items+=("$f")
  done
  echo "Selected extension(s): $(printf '.%s ' "${!chosen[@]}")"
  _fxdel_run_selected
}
_fx_adf_register "delete.by.extension" "_fx_adf_delete_by_ext" "file_fx/delete/delete.by.extension"
