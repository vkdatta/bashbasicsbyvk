#!/usr/bin/env bash
# Archive formats: name + content recognition, create/extract round trip for every format, copies like hello.zip1 / hello_tar.gz,
# a lying name, a text file that only LOOKS like an archive.   bash tests/archive/archive_test.sh
# A format whose tool is not installed is reported as SKIP (not verified), never as a pass.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$ROOT/tests/wait_lib.sh"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }; skip() { echo "  SKIP $* (not verified)"; }
source "$(bvk_need bashbasicsbyvk_archive_formats.sh)"; source "$(bvk_need bashbasicsbyvk_hidefiles.sh)" 2>/dev/null
source "$(bvk_need bashbasicsbyvk_staging_archive.sh)"
source "$(bvk_need bashbasicsbyvk_viewport.sh)" 2>/dev/null
declare -F _bvk_name_too_long >/dev/null || { _bvk_name_too_long() { return 1; }; }
_bvk_yn() { printf -v "$1" y; }; _bvk_menu() { printf -v "$1" '%s' "${_MENU_PICK:-zip}"; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; export TMPDIR="$W"

# (1) names: what the name claims, and the folder name it leaves
nm() { local want="$1" stem="$2" n="$3"; if _arc_scan "$n"; then [ "$_ARC_NFMT|$_ARC_STEM" = "$want|$stem" ] && ok "name  $n -> $want [$stem]" || bad "name  $n -> $_ARC_NFMT [$_ARC_STEM] want $want [$stem]"; else bad "name  $n not recognised, want $want"; fi; }
no() { _arc_scan "$1" && bad "name  $1 must NOT be an archive (got $_ARC_NFMT)" || ok "name  $1 is not an archive"; }
nm zip hello hello.zip;               nm zip hello hello.zip1;            nm targz hello hello_tar.gz;       nm targz hello hello.tar-1.gz
nm zip hello "hello- (2).zip";        nm targz hello "hello (1).tar.gz";  nm zip HELLO HELLO.ZIP;            nm targz hello hello.tgz.bak
nm tarxz a a.tar.xz;  nm tarxz a a.txz;  nm tarbz2 a a.tar.bz2;  nm tarbz2 a a.tbz2;  nm tarzst a a.tar.zst;  nm tarzst a a.tzst
nm tarlz4 a a.tar.lz4;  nm 7z a a.7z;  nm skill a a.skill;  nm skill a a.skill1;  nm tar a a.tar;  nm zip x "x - copy.zip";  nm 7z x "x_copy (2).7z"
no notes.txt; no my_zip_notes.txt; no data.gz; no hello.tar.gz.part; no hello; no archive.tar.txt

# (2) round trip of every format, in the folder and from outside it, with and without hidden files
mkdir -p "$W/src/d/.hid" "$W/other"; echo one > "$W/src/a.txt"; echo two > "$W/src/d/b.txt"; echo h > "$W/src/d/.hid/h.txt"; echo o > "$W/other/o.txt"
for f in "${_ARC_FORMATS[@]}"; do
  if ! _arc_have create "$f" || ! _arc_have extract "$f"; then skip "$f round trip: needs ${_ARC_MISSING}"; continue; fi
  for hid in true false; do
    rm -rf "$W/run"; mkdir -p "$W/run"; cp -a "$W/src/." "$W/run/"; path="$W/run"; arc="$W/run/pack${_ARC_LABEL[$f]}"
    _arc_create "$f" "$arc" "$W/run" "$hid" false a.txt d >/dev/null 2>&1 || { bad "$f hid=$hid: create failed"; continue; }
    _arc_detect "$arc" && [ "$_ARC_FMT" = "$f" ] && ok "$f: made, recognised as $_ARC_FMT" || bad "$f: made but recognised as '$_ARC_FMT' ($_ARC_WHY)"
    d="$W/ex_${f}_$hid"; mkdir -p "$d"; _arc_extract "$f" "$arc" "$d" >/dev/null 2>&1 || { bad "$f hid=$hid: extract failed"; continue; }
    [ "$(cat "$d/a.txt" 2>/dev/null)" = one ] && [ "$(cat "$d/d/b.txt" 2>/dev/null)" = two ] && ok "$f hid=$hid: files back" || bad "$f hid=$hid: files missing"
    if [ "$hid" = true ]; then [ -f "$d/d/.hid/h.txt" ] && ok "$f: hidden file kept" || bad "$f: hidden file lost"
    else [ ! -e "$d/d/.hid" ] && ok "$f: hidden left out" || bad "$f: hidden folder should be left out"; fi
  done
  # from outside the folder: the symlinks of the staging folder must be followed (content stored, not a dangling link)
  rm -rf "$W/stage" "$W/ex_out"; mkdir -p "$W/stage" "$W/ex_out"; ln -s "$W/other/o.txt" "$W/stage/o.txt"
  _arc_create "$f" "$W/out${_ARC_LABEL[$f]}" "$W/stage" true true o.txt >/dev/null 2>&1; _arc_extract "$f" "$W/out${_ARC_LABEL[$f]}" "$W/ex_out" >/dev/null 2>&1
  [ "$(cat "$W/ex_out/o.txt" 2>/dev/null)" = o ] && ok "$f: symlinked item stored as a real file" || bad "$f: symlinked item not stored as content"
  rm -f "$W/out${_ARC_LABEL[$f]}"
done

# (3) _decompress_paths: copies, a lying name, a fake
rm -rf "$W/u"; mkdir -p "$W/u"; path="$W/u"
( cd "$W/src" && tar -czf "$W/u/hello_tar.gz" a.txt && zip -q "$W/u/hello- (2).zip" a.txt && tar -czf "$W/u/liar.zip" a.txt && tar -cJf "$W/u/x.tar-1.xz" a.txt )
echo "just text" > "$W/u/my_zip"; : > "$W/u/empty.zip"
out="$(_decompress_paths "$W/u/hello_tar.gz" "$W/u/hello- (2).zip" "$W/u/liar.zip" "$W/u/x.tar-1.xz" "$W/u/my_zip" "$W/u/empty.zip" 2>&1)"
for d in hello hello_1 liar x; do [ "$(cat "$W/u/$d/a.txt" 2>/dev/null)" = one ] && ok "extracted into $d/" || bad "no $d/a.txt"; done
[[ "$out" == *"Skipping 'my_zip'"* && "$out" == *"Skipping 'empty.zip'"* ]] && ok "text file and empty file are skipped, not extracted" || bad "fake archives not skipped: $out"
[ ! -e "$W/u/my_zip_1" ] && [ ! -e "$W/u/empty" ] && ok "no folder made for a fake" || bad "folder made for a fake"
# the file menu's destination: next to the archive
mkdir -p "$W/elsewhere" "$W/u/sub"; cp "$W/u/hello_tar.gz" "$W/u/sub/"; path="$W/elsewhere"; _arc_dest_base="$W/u/sub" _decompress_paths "$W/u/sub/hello_tar.gz" >/dev/null 2>&1
[ -f "$W/u/sub/hello/a.txt" ] && [ ! -e "$W/elsewhere/hello" ] && ok "dest base: extracted beside the archive" || bad "dest base ignored"

# (4) _compress_paths end to end: name prompt strips a typed ending, the ending of the chosen format is used
path="$W/run"; compress_format=targz; zip_hidden_mode=always; _hidden_decide() { _hid_inc=true; }
printf 'mine.tar.gz\n' | _compress_paths "$W/run/a.txt" >/dev/null 2>&1; [ -f "$W/run/mine.tar.gz" ] && ok "z-: mine.tar.gz made (typed ending not doubled)" || bad "z-: mine.tar.gz missing"
compress_format=skill; printf 'sk\n' | _compress_paths "$W/run/a.txt" >/dev/null 2>&1; [ -f "$W/run/sk.skill" ] && ok "z-: sk.skill made" || bad "z-: sk.skill missing"
[ "$fail" = 0 ] && echo "ALL OK"; exit $fail
