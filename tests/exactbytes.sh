#!/usr/bin/env bash
# eb- (exact bytes) and the nano wrap setting, checked WITHOUT a terminal.   bash tests/exactbytes.sh
#  1. byte counts: a file, a folder (every file below it), an empty file; the list's cached size is used when it is there
#  2. binary (1024) and data (1000) units: rounding, and a value that rounds up to the next unit rolls over (1000.00 GB -> 1.00 TB)
#  3. the table (the text the person reads / the clipboard gets) and the sheet rows carry the same numbers
#  4. nano wrap: one managed block in nanorc, replaced (never repeated) on every call, nothing else in the file touched
#  5. Reset all: --if-present does not create a nanorc that never carried the block
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; fail=0
source "$ROOT/tests/wait_lib.sh"
EB="$(bvk_need bashbasicsbyvk_exactbytes.sh)"; NANO="$(bvk_need bashbasicsbyvk_importnano.sh)"
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1: got [$2] want [$3]"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/d/sub"; head -c 1500 /dev/zero > "$T/d/a.bin"; head -c 2500 /dev/zero > "$T/d/sub/b.bin"
head -c 1234567 /dev/zero > "$T/big.dat"; : > "$T/empty.txt"

run() { bash -c 'declare -gA item_size=() item_dsize=(); source "$1"; shift; eval "$@"' _ "$EB" "$@"; }

# 1. byte counts
eq "file (wc -c)"      "$(run "_eb_item_bytes '$T/big.dat'; echo \$_EB_B")" 1234567
eq "empty file"        "$(run "_eb_item_bytes '$T/empty.txt'; echo \$_EB_B")" 0
eq "folder = all files below" "$(run "_eb_item_bytes '$T/d'; echo \$_EB_B")" 4000
eq "cached file size is reused"   "$(run "item_size['$T/big.dat']=42; _eb_item_bytes '$T/big.dat'; echo \$_EB_B")" 42
eq "cached folder size is reused" "$(run "item_dsize['$T/d']=77; _eb_item_bytes '$T/d'; echo \$_EB_B")" 77
eq "a fifo is not read (0, no hang)" "$(mkfifo "$T/ff"; timeout 5 bash -c 'declare -gA item_size=() item_dsize=(); source "$1"; _eb_item_bytes "$2"; echo $_EB_B' _ "$EB" "$T/ff")" 0

# 2. units
u() { run "_eb_unit $1 $2; echo \"\$_EB_U\""; }
eq "999 B (binary)"        "$(u 999 1024)" "999 B"
eq "1024 = 1.00 KiB"       "$(u 1024 1024)" "1.00 KiB"
eq "1000 = 1.00 KB (data)" "$(u 1000 1000)" "1.00 KB"
eq "1234567 binary"        "$(u 1234567 1024)" "1.18 MiB"
eq "1234567 data"          "$(u 1234567 1000)" "1.23 MB"
eq "rolls over to the next unit (data)"   "$(u 999999999999 1000)" "1.00 TB"
eq "rolls over to the next unit (binary)" "$(u 1048575 1024)" "1.00 MiB"
eq "thousands separators"  "$(run '_eb_commas 1234567; echo $_EB_C')" "1,234,567"

# 3. table and sheet rows
tab="$(run '_eb_names=(big.dat d); _eb_bytes=(1234567 4000); _eb_kinds=(file folder); _eb_paths=(/x/big.dat /x/d); _eb_total=1238567; _eb_table; printf "%s\n--\n%s" "$_EB_TEXT" "$_EB_TSV"')"
case "$tab" in *"1,234,567 B"*"1.18 MiB"*"1.23 MB"*) ok "table has exact bytes, binary and data" ;; *) bad "table: $tab" ;; esac
case "$tab" in *"Total (2)"*"1,238,567 B"*) ok "table has the total" ;; *) bad "total missing: $tab" ;; esac
case "$tab" in *$'1\tbig.dat\tfile\t1234567\t1.18 MiB\t1.23 MB\t/x/big.dat'*) ok "sheet row = same numbers" ;; *) bad "sheet row: $tab" ;; esac

# 4. nano wrap
export HOME="$T/home"; mkdir -p "$HOME"; export SHELL=/bin/bash; unset SUDO_USER
printf 'set tabsize 4\n\n# bashbasicsbyvk nano settings\nset mouse\n' > "$HOME/.nanorc"
nano() { bash -c 'source "$1"; nano_wrap="$2"; shift 2; "$@"' _ "$NANO" "$@"; }
nano wrap bvk_nano_wrap_apply; nano wrap bvk_nano_wrap_apply
eq "wrap: block written once"  "$(grep -c '^# bashbasicsbyvk nano wrap$' "$HOME/.nanorc")" 1
eq "wrap: softwrap on"         "$(grep -c '^set softwrap$' "$HOME/.nanorc")" 1
nano nowrap bvk_nano_wrap_apply; nano nowrap bvk_nano_wrap_apply
eq "nowrap: block replaced, not added" "$(grep -c '^# bashbasicsbyvk nano wrap$' "$HOME/.nanorc")" 1
eq "nowrap: softwrap off"      "$(grep -c '^unset softwrap$' "$HOME/.nanorc")" 1
eq "nowrap: no stale 'set softwrap'" "$(grep -c '^set softwrap$' "$HOME/.nanorc")" 0
eq "the rest of nanorc is untouched" "$(sed -n '1,4p' "$HOME/.nanorc" | tr '\n' '|')" 'set tabsize 4||# bashbasicsbyvk nano settings|set mouse|'
nano wrap bvk_nano_wrap_apply; nano nowrap bvk_nano_wrap_apply; nano wrap bvk_nano_wrap_apply
eq "no blank-line growth over many calls" "$(grep -c '^$' "$HOME/.nanorc")" 2

# 5. --if-present
rm -f "$HOME/.nanorc"; nano wrap bvk_nano_wrap_apply --if-present
[ ! -e "$HOME/.nanorc" ] && ok "--if-present creates nothing" || bad "--if-present created a nanorc"
printf 'set tabsize 2\n' > "$HOME/.nanorc"; nano wrap bvk_nano_wrap_apply --if-present
eq "--if-present leaves a nanorc without our block alone" "$(cat "$HOME/.nanorc")" "set tabsize 2"

[ "$fail" = 0 ] && echo "ALL OK" || { echo "FAILED"; exit 1; }
