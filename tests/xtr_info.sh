#!/usr/bin/env bash
# xtr- (extract) and i- (file info), checked WITHOUT a terminal.   bash tests/xtr_info.sh
#  1. extract engine: first / range / last / dup / unique for lines, words, chars; bytes with a unit (decimal and binary)
#  2. folders are refused with "<names> are folders, which can't be extracted." (whole pick refused, files alone pass)
#  3. info rows: bytes, binary, words, chars with / without spaces, lines (a last line without a line end counts), extension
#  4. the shared sheet writer still honours the eb- defaults and takes the i- / xtr- header
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fail=0
source "$ROOT/tests/wait_lib.sh"
EB="$(bvk_need bashbasicsbyvk_exactbytes.sh)"; FI="$(bvk_need bashbasicsbyvk_fileinfo.sh)"; XT="$(bvk_need bashbasicsbyvk_extract.sh)"; SH="$(bvk_need bashbasicsbyvk_staging_helpers.sh)"
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1: got [$2] want [$3]"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf 'apple pear\nbanana\napple pear\nkiwi\nbanana\nfig' > "$T/a.txt"; mkdir "$T/docs" "$T/src"
head -c 3000 /dev/zero > "$T/z.bin"
# parse_selection lives in the viewport (too heavy to source): a stand-in for "N" and "A-B" is all these checks use
run() { bash -c 'parse_selection() { local a b; if [[ "$1" =~ ^([0-9]+)-([0-9]+)$ ]]; then seq "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; elif [[ "$1" =~ ^[0-9]+$ ]]; then echo "$1"; fi; }; declare -gA item_size=() item_dsize=(); source "$1"; source "$2"; source "$3"; source "$4"; shift 4; eval "$@"' _ "$EB" "$FI" "$XT" "$SH" "$@"; }
x() { run "b=\$(mktemp); _xtr_engine $1 $2 '$3' '$4' \$b '$T/a.txt' >/dev/null; cat \$b.out"; }

eq "lines first 2"   "$(x lines first 2 '')"  $'apple pear\nbanana'
eq "lines range 2-4" "$(x lines range 2 4)"   $'banana\napple pear\nkiwi'
eq "lines last 2"    "$(x lines last 2 '')"   $'banana\nfig'
eq "lines dup"       "$(x lines dup '' '')"   $'apple pear\nbanana'
eq "lines unique"    "$(x lines uniq '' '')"  $'kiwi\nfig'
eq "words first 3"   "$(x words first 3 '')"  'apple pear banana'
eq "words dup 1"     "$(x words dup 1 '')"    'apple'
eq "chars range 2-4" "$(x chars range 2 4)"   'ppl'
eq "bytes first 1 kb"  "$(run "b=\$(mktemp); _xtr_engine bytes first 1 kb \$b '$T/z.bin' >/dev/null; wc -c < \$b.out" | tr -d ' ')" 1000
eq "bytes last 1 kib"  "$(run "b=\$(mktemp); _xtr_engine bytes last 1 kib \$b '$T/z.bin' >/dev/null; wc -c < \$b.out" | tr -d ' ')" 1024
eq "bytes random 1.5 kb" "$(run "b=\$(mktemp); _xtr_engine bytes random 1.5 kb \$b '$T/z.bin' >/dev/null; wc -c < \$b.out" | tr -d ' ')" 1500
eq "nothing to extract = rc 3" "$(run "b=\$(mktemp); _xtr_engine lines dup '' '' \$b '$T/z.bin' >/dev/null; echo \$?")" 3

# 2. folders refused
out="$(run "imaginary_mode=false; items=('$T/docs' '$T/src' '$T/a.txt'); _sp_files_only 1-3 xtr- EXTRACT \"can't be extracted\"; echo rc=\$?")"
case "$out" in *"docs, src are folders, which can't be extracted."*"rc=1"*) ok "folders refused with the sample list" ;; *) bad "folders: $out" ;; esac
out="$(run "imaginary_mode=false; items=('$T/docs' '$T/a.txt'); _sp_files_only 1 xtr- EXTRACT \"can't be extracted\"; echo rc=\$?")"
case "$out" in *"docs is a folder, which can't be extracted."*"rc=1"*) ok "one folder: singular" ;; *) bad "one folder: $out" ;; esac
eq "a file alone passes" "$(run "imaginary_mode=false; items=('$T/docs' '$T/a.txt'); _sp_files_only 2 xtr- EXTRACT x; echo \"rc=\$? \${sp_files[*]##*/}\"")" "rc=0 a.txt"

# 3. info
row="$(run "_fi_scan '$T/a.txt'")"
IFS=$'\t' read -r _ b bin w c ns l ext _ <<< "$row"
eq "info bytes" "$b" 44; eq "info binary" "$bin" 0b101100; eq "info words" "$w" 8
eq "info chars with spaces" "$c" 44; eq "info chars without spaces" "$ns" 37
eq "info lines (last line has no line end)" "$l" 6; eq "info extension" "$ext" txt
txt="$(run "rows=\"\$(_fi_scan '$T/a.txt')\"; _fi_build <<< \"\$rows\"; printf '%s' \"\$_EB_TEXT\"")"
case "$txt" in *"Decimal bytes          44 B"*"Total lines            6"*"Date modified"*) ok "info text has the fields" ;; *) bad "info text: $txt" ;; esac

# 4. sheet
if python3 -c 'import openpyxl' 2>/dev/null; then
  run "_EB_TSV=\$'1\tx\tfile\t1234\t1.21 KiB\t1.23 KB\t/p\n'; _eb_save_sheet '$T/eb'" >/dev/null
  eq "eb- sheet: default header + number cell" "$(python3 -c "
from openpyxl import load_workbook
ws=load_workbook('$T/eb.xlsx').active; print(ws.title, ws['D1'].value, ws['D2'].value)")" "exact bytes Exact bytes 1234"
  run "_EB_HEAD=\$'File\tPosition\tCount\tValue'; _EB_SHEET=extract; _EB_NUMS=2,3; _EB_BOLDLAST=0; _EB_TSV=\$'a.txt\t1\t2\tapple\n'; _eb_save_sheet '$T/xt'" >/dev/null
  eq "xtr- sheet: own header" "$(python3 -c "
from openpyxl import load_workbook
ws=load_workbook('$T/xt.xlsx').active; print(ws.title, ws['D1'].value, ws['B2'].value, ws['D2'].value)")" "extract Value 1 apple"
else echo "  SKIP sheet checks (openpyxl missing) — NOT verified"; fi
exit $fail
