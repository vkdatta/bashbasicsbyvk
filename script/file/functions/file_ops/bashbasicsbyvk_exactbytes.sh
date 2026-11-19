# bashbasicsbyvk_exactbytes.sh — the `eb-` command: the EXACT size of the numbered items.
#   Also the home of the helpers `i-` (bashbasicsbyvk_fileinfo.sh) and `xtr-` (bashbasicsbyvk_extract.sh) share:
#   _eb_commas, _eb_unit, _eb_save_sheet (Excel / CSV) and _eb_finish (the "Excel or clipboard?" question).
#
#   eb-1,3   eb-1-5   eb-a   eb-a-2        (the same item lists as up- c- z-: _sp_guard_and_resolve)
#
#   Per item and in total it shows three things:
#     exact bytes   the real number of bytes, e.g. 1,234,567 B
#     binary        1024-based units (KiB MiB GiB TiB)
#     data          1000-based units (KB MB GB TB), the way disks and networks count
#   then asks once:  save it in Excel  /  copy it to the clipboard.
#
#   Where the bytes come from (nothing is measured twice):
#     file    item_size[]  (the list already knows it)   else  wc -c
#     folder  item_dsize[] (the background size job)     else  du -sb  else  find + wc -c
#   Folders count every file below them (apparent size, the same number the list shows next to a folder).
#
#   Needs: bashbasicsbyvk_staging_helpers.sh (_sp_guard_and_resolve), bashbasicsbyvk_choose.sh (_bvk_menu),
#          bashbasicsbyvk_deps.sh (_dep_need, only for the Excel file), the copy command (clipboard).

# _eb_commas N  ->  _EB_C   (1234567 -> 1,234,567)
_eb_commas() {
  local n="${1:-0}" out=""
  while [ "${#n}" -gt 3 ]; do out=",${n: -3}$out"; n="${n:0:${#n}-3}"; done
  _EB_C="$n$out"
}

# _eb_unit BYTES BASE  ->  _EB_U   BASE 1024 = binary (KiB), 1000 = data (KB).  Two decimals, rounded.
_eb_unit() {
  local b="${1:-0}" base="${2:-1024}" div=1 i=0 whole frac
  local -a names
  if [ "$base" = 1000 ]; then names=(B KB MB GB TB PB); else names=(B KiB MiB GiB TiB PiB); fi
  if [ "$b" -lt "$base" ]; then _EB_U="$b B"; return; fi
  while [ "$i" -lt 5 ] && [ "$b" -ge $(( div * base )) ]; do div=$(( div * base )); i=$(( i + 1 )); done
  whole=$(( b / div ))
  frac=$(( ( (b % div) * 100 + div / 2 ) / div ))
  if [ "$frac" -ge 100 ]; then whole=$(( whole + 1 )); frac=0; fi
  if [ "$whole" -ge "$base" ] && [ "$i" -lt 5 ]; then whole=1; frac=0; i=$(( i + 1 )); fi   # 1023.999 KiB rounds up to 1.00 MiB, not 1024.00 KiB
  printf -v _EB_U '%d.%02d %s' "$whole" "$frac" "${names[$i]}"
}

# _eb_dir_bytes DIR -> _EB_B  (the list's cached folder size when the size job has finished, otherwise measured now)
_eb_dir_bytes() {
  local d="$1" v n
  v="${item_dsize[$d]:-}"
  if [[ "$v" =~ ^[0-9]+$ ]]; then _EB_B="$v"; return 0; fi
  v="$(du -sb -- "$d" 2>/dev/null | { read -r n _; printf '%s' "$n"; })"
  if [[ "$v" =~ ^[0-9]+$ ]]; then _EB_B="$v"; return 0; fi
  # no GNU du (macOS, busybox): add up wc -c of every file; wc prints one "total" line per batch, it is not a file
  v="$(find "$d" -type f -exec wc -c {} + 2>/dev/null | awk '$0 ~ /^ *[0-9]+ total$/ {next} {s += $1} END {printf "%d", s}')"
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  _EB_B="$v"
}

# _eb_item_bytes PATH -> _EB_B  (0 for anything that is not a file or a folder: wc on a fifo would wait forever)
_eb_item_bytes() {
  local p="$1" v
  _EB_B=0
  if [ -d "$p" ]; then _eb_dir_bytes "$p"; return; fi
  [ -f "$p" ] || return 0
  v="${item_size[$p]:-}"
  if [[ "$v" =~ ^[0-9]+$ ]]; then _EB_B="$v"; return; fi
  v="$(wc -c < "$p" 2>/dev/null)"; v="${v//[[:space:]]/}"
  [[ "$v" =~ ^[0-9]+$ ]] && _EB_B="$v"
}

# _eb_table  -> _EB_TEXT (the table the person reads and the clipboard gets), _EB_TSV (rows for the Excel / CSV file)
#   uses  _eb_names[] _eb_bytes[] _eb_kinds[] _eb_paths[]  and  _eb_total
_eb_table() {
  local i n w=10 nm line bi da
  for i in "${!_eb_names[@]}"; do n=${#_eb_names[i]}; [ "$n" -gt "$w" ] && w=$n; done
  [ "$w" -gt 34 ] && w=34
  _EB_TEXT=""; _EB_TSV=""
  printf -v line '%-4s %-*s %20s  %12s  %12s' "No." "$w" "Name" "Exact bytes" "Binary" "Data"
  _EB_TEXT+="$line"$'\n'
  for i in "${!_eb_names[@]}"; do
    nm="${_eb_names[i]}"; [ "${#nm}" -gt "$w" ] && nm="${nm:0:w-1}…"
    _eb_commas "${_eb_bytes[i]}"; _eb_unit "${_eb_bytes[i]}" 1024; bi="$_EB_U"; _eb_unit "${_eb_bytes[i]}" 1000; da="$_EB_U"
    printf -v line '%-4s %-*s %18s B  %12s  %12s' "$(( i + 1 ))" "$w" "$nm" "$_EB_C" "$bi" "$da"
    _EB_TEXT+="$line"$'\n'
    _EB_TSV+="$(( i + 1 ))"$'\t'"${_eb_names[i]//[$'\t\n']/ }"$'\t'"${_eb_kinds[i]}"$'\t'"${_eb_bytes[i]}"$'\t'"$bi"$'\t'"$da"$'\t'"${_eb_paths[i]//[$'\t\n']/ }"$'\n'
  done
  _eb_commas "$_eb_total"; _eb_unit "$_eb_total" 1024; bi="$_EB_U"; _eb_unit "$_eb_total" 1000; da="$_EB_U"
  printf -v line '%-4s %-*s %18s B  %12s  %12s' "" "$w" "Total (${#_eb_names[@]})" "$_EB_C" "$bi" "$da"
  _EB_TEXT+="$line"$'\n'
  _EB_TSV+=$'\t'"Total"$'\t'$'\t'"$_eb_total"$'\t'"$bi"$'\t'"$da"$'\t'$'\n'
  _EB_TEXT+="Binary = 1024-based (KiB, MiB).  Data = 1000-based (KB, MB)."
}

# _eb_save_sheet FILE-WITHOUT-EXTENSION  -> writes .xlsx (openpyxl) or, when openpyxl is missing, .csv; prints where
#   rows come from _EB_TSV (tab separated, one row per line).  The callers that are not eb- set, before the call:
#     _EB_HEAD   the header cells, tab separated   (default: the eb- table)
#     _EB_SHEET  the sheet name                    (default: exact bytes)
#     _EB_NUMS   1-based numeric columns, comma separated: written as numbers, shown with thousands commas (default: 4)
#     _EB_BOLDLAST  1 = the last row (a Total row) is bold (default 1)
_eb_save_sheet() {
  local base="$1" tsv head sheet nums boldlast
  tsv="$(mktemp)" || return 1
  printf '%s' "$_EB_TSV" > "$tsv"
  printf -v head 'No.\tName\tType\tExact bytes\tBinary (1024)\tData (1000)\tFull path'
  head="${_EB_HEAD-$head}"; sheet="${_EB_SHEET:-exact bytes}"; nums="${_EB_NUMS-4}"; boldlast="${_EB_BOLDLAST:-1}"
  python3 - "$base" "$tsv" "$head" "$sheet" "$nums" "$boldlast" <<'PYEOF'
import csv, sys
base, tsv, head_s, sheet, nums_s, boldlast = sys.argv[1:7]
head = head_s.split("\t")
n = len(head)
nums = [int(x) - 1 for x in nums_s.split(",") if x.strip().isdigit()]
rows = []
with open(tsv, encoding="utf-8") as f:
    for line in f.read().split("\n"):
        if not line:
            continue
        c = line.split("\t")
        c += [""] * (n - len(c))
        c = c[:n]
        for i in nums:
            if c[i] != "":
                try:
                    c[i] = int(c[i])
                except ValueError:
                    pass
        rows.append(c)
try:
    from openpyxl import Workbook
    from openpyxl.styles import Font
    wb = Workbook(); ws = wb.active; ws.title = sheet[:31]
    ws.append(head)
    for r in rows:
        ws.append(r)
    for cell in ws[1]:
        cell.font = Font(bold=True)
    if boldlast == "1" and rows:
        for cell in ws[len(rows) + 1]:
            cell.font = Font(bold=True)
    for r in range(2, len(rows) + 2):
        for i in nums:
            ws.cell(r, i + 1).number_format = "#,##0"
    ws.freeze_panes = "A2"
    for i, h in enumerate(head, 1):
        w = max([len(h)] + [len(str(r[i - 1])) for r in rows]) + 2
        ws.column_dimensions[ws.cell(1, i).column_letter].width = min(w, 60)
    wb.save(base + ".xlsx")
    print("📗 Saved -> " + base + ".xlsx")
except ImportError:
    with open(base + ".csv", "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f); w.writerow(head); w.writerows(rows)
    print("🔴  openpyxl is not installed, so a CSV (opens in Excel) was saved instead -> " + base + ".csv")
PYEOF
  local rc=$?
  rm -f "$tsv"
  return $rc
}

# _eb_finish TITLE ICON FILE-STEM COMMAND   the one question that ends eb- and i-: save _EB_TSV in Excel, or copy _EB_TEXT.
#   The table is ALWAYS printed before this is called (the caller prints _EB_TEXT first); nothing is saved or copied unseen.
_eb_finish() {
  local title="$1" icon="$2" stem="$3" cmd="${4:-$3}" ans stamp
  _bvk_menu ans -t "$title" -i "$icon" -q "What do you want to do with this table?" \
    "x:Save it in Excel" "c:Copy it to the clipboard" || return 0
  [ "${_CM_ABORT:-0}" = 1 ] && return 0
  case "${ans,,}" in
    x) _dep_need -c "$cmd Excel file (without it a CSV is saved instead)" openpyxl || true
       printf -v stamp '%(%Y%m%d_%H%M%S)T' -1
       _eb_save_sheet "${path%/}/${stem}_$stamp" ;;
    c) printf '%s\n' "$_EB_TEXT" | bashbasicsbyvk_copy && echo "💫 Copied to clipboard" ;;
    *) _bvk_invalid ;;
  esac
  return 0
}

# eb-<items>
handle_eb() {
  local raw="$1" p
  _sp_guard_and_resolve "${raw#eb-}" "eb-" || return 0
  local -a _eb_names=() _eb_bytes=() _eb_kinds=() _eb_paths=()
  local _eb_total=0 _EB_B _EB_C _EB_U _EB_TEXT _EB_TSV
  for p in "${sp_resolved[@]}"; do
    _eb_item_bytes "$p"
    _eb_names+=("${p##*/}")
    _eb_bytes+=("$_EB_B")
    if [ -d "$p" ]; then _eb_kinds+=("folder"); else _eb_kinds+=("file"); fi
    _eb_paths+=("$p")
    _eb_total=$(( _eb_total + _EB_B ))
  done
  _eb_table
  echo
  echo "📐 Exact bytes"
  printf '%s\n' "$_EB_TEXT"
  echo
  _eb_finish "Exact bytes" "📐" "exact_bytes" "eb-"
  return 0
}
