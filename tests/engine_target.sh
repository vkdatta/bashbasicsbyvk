#!/usr/bin/env bash
# _bvk_engine_target is the ONE place that maps this machine to a prebuilt binary (arm64 | amd64 | arm | 386, android | linux | darwin | freebsd).   bash tests/engine_target.sh
# (1) the mapping table  (2) no other file re-implements the CPU case  (3) the stand-alone cmds (copy, delete) load it themselves
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/script"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }

T="$(find "$S" -name bashbasicsbyvk_engine_target.sh -print -quit)"
[ -n "$T" ] && ok "engine_target.sh exists" || { bad "bashbasicsbyvk_engine_target.sh not found"; echo FAILED; exit 1; }

row() ( uname() { case "$1" in -m) echo "$FM" ;; -o) echo "$FO" ;; esac; }; source "$T"; OSTYPE="$FT"; _bvk_engine_target; echo "${_bet_m:-none}/$_bet_os" )
chk() { FM="$1" FO="$2" FT="$3" got="$(FM="$1" FO="$2" FT="$3" row)"; [ "$got" = "$4" ] && ok "uname -m=$1 uname -o=$2 OSTYPE=$3 -> $4" || bad "uname -m=$1 uname -o=$2 OSTYPE=$3 -> $got (want $4)"; }
chk aarch64 GNU/Linux linux-gnu     arm64/linux
chk arm64   GNU/Linux linux-gnu     arm64/linux
chk x86_64  GNU/Linux linux-gnu     amd64/linux
chk amd64   GNU/Linux linux-gnu     amd64/linux
chk armv7l  GNU/Linux linux-gnu     arm/linux
chk armv8l  GNU/Linux linux-gnu     arm/linux
chk aarch64 Android   linux-gnu     arm64/android
chk aarch64 GNU/Linux linux-android arm64/android
chk i686    GNU/Linux linux-gnu     386/linux
chk i386    GNU/Linux linux-gnu     386/linux
chk arm64   Darwin    darwin23.0    arm64/darwin
chk x86_64  Darwin    darwin22.1    amd64/darwin
chk x86_64  FreeBSD   freebsd14.0   amd64/freebsd
chk i686    Android   linux-android none/android
chk armv7l  Darwin    darwin23.0    none/darwin
chk arm64   FreeBSD   freebsd14.0   none/freebsd
chk riscv64 GNU/Linux linux-gnu     none/linux

dup="$(grep -rnE 'aarch64\|arm64\)' "$S" --include='*.sh' | grep -v 'bashbasicsbyvk_engine_target.sh' | head -3)"
[ -z "$dup" ] && ok "no other file re-implements the CPU mapping" || bad "CPU mapping copied, call _bvk_engine_target instead: $dup"

for f in "$S"/file/functions/_3bvk_import_cmd_delete.sh "$S/file/staging/!buffer/fileapi/_3bvk_import_cmd_copy.sh"; do
  grep -q 'bashbasicsbyvk_engine_target.sh' "$f" && ok "$(basename "$f") loads engine_target (it cannot load displayer)" || bad "$(basename "$f") calls _bvk_xfer_bin but does not load engine_target"
done
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
