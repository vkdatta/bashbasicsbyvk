#!/usr/bin/env bash
# Folder sizes must follow the disk, checked WITHOUT a terminal.   bash tests/pty/fast/engine/dsize_cache.sh
#  1. a folder size is recomputed after a delete (the cache is cleared by _dsize_invalidate), and a size job that was
#     running while the disk changed is thrown away instead of being stored
#  2. the Python size engine counts symlinks, special files and hard links the way the C engine does (a hard link once)
#  3. an unreadable top folder is -1 (shown as ---), never a cached 0
#  4. sort big / small ranks a folder by its recursive size
#  5. sizes keep one decimal (1.9M is not 1M or 2M)
#  6. one unique-name rule: folders and dotfiles have no extension, a.tar.gz stays whole
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"; S="$ROOT/script/file"; fail=0
ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1: got [$2] want [$3]"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T"; display_suffix_set="size"; sort_mode=az
source "$S/engine/ui/bashbasicsbyvk_displayer.sh" 2>/dev/null
eval "$(sed -n '/^_bvk_unique_name() {/,/^}/p' "$S/engine/ui/bashbasicsbyvk_viewport.sh")"

mkdir -p "$T/a" "$T/b"; head -c 1000000 /dev/zero > "$T/a/f"; head -c 500000 /dev/zero > "$T/b/f"
items=("$T/a" "$T/b"); _win_lo=1; _win_hi=2
job() { _load_dir_size_window; local i=0; while ! _dir_size_job_poll && [ $((i++)) -lt 200 ]; do sleep 0.05; done; }
job; eq "first size" "${item_dsize[$T/a]}" 1000000
rm "$T/a/f"; _dsize_invalidate; _win_lo=1; _win_hi=2; job
eq "size after delete" "${item_dsize[$T/a]}" 0
head -c 800000 /dev/zero > "$T/a/g"; _dsize_invalidate; _win_lo=1; _win_hi=2; _load_dir_size_window
rm "$T/a/g"; _dsize_invalidate; sleep 0.4; _dir_size_job_poll
eq "stale job not stored" "${#item_dsize[@]}" 0

mkdir -p "$T/h/s1" "$T/h/s2" "$T/h/s3" "$T/h/s4" "$T/h/s5"; for i in 1 2 3 4 5; do head -c 100 /dev/zero > "$T/h/s$i/f"; done
ln "$T/h/s1/f" "$T/h/s1/hl"; ln -s /etc/hostname "$T/h/sym"; mkfifo "$T/h/fifo"
want=$(( 500 + 13 )); echo "$T/h" > "$T/in"
got="$(_py_recursive_size "$T/in" 2>/dev/null)"; eq "python: symlink counted, hard link once" "${got##*|}" "$want"
echo "$T/none" > "$T/in"; got="$(_py_recursive_size "$T/in" 2>/dev/null)"; eq "unreadable top folder" "${got##*|}" -1

mkdir -p "$T/s/big" "$T/s/mid"; head -c 3000000 /dev/zero > "$T/s/big/f"; head -c 1500000 /dev/zero > "$T/s/mid/f"; head -c 2000000 /dev/zero > "$T/s/file"
_dsize_invalidate; items=("$T/s/file" "$T/s/mid" "$T/s/big"); sort_mode=big; _items_presorted=true; _items_presorted_mode=big; apply_sort
eq "sort big" "$(printf '%s ' "${items[@]##*/}")" "big file mid "
_dsize_invalidate; items=("$T/s/file" "$T/s/mid" "$T/s/big"); sort_mode=small; _items_presorted_mode=small; apply_sort
eq "sort small" "$(printf '%s ' "${items[@]##*/}")" "mid file big "

_fmt_size_v 1992294; eq "1.8M not 2M" "$_fs_out" 1.8M
_fmt_size_v 146800640; eq "140.0M" "$_fs_out" 140.0M
_fmt_size_v -1; eq "unreadable" "$_fs_out" "---"

mkdir -p "$T/n/my.project"; touch "$T/n/a.txt" "$T/n/.bashrc" "$T/n/k.tar.gz"
_bvk_unique_name "$T/n" my.project dir; eq "folder name" "$_BVK_UQ" "my.project (1)"
_bvk_unique_name "$T/n" a.txt;          eq "file name" "$_BVK_UQ" "a (1).txt"
_bvk_unique_name "$T/n" .bashrc;        eq "dotfile" "$_BVK_UQ" ".bashrc (1)"
_bvk_unique_name "$T/n" k.tar.gz;       eq "double extension" "$_BVK_UQ" "k (1).tar.gz"
[ "$fail" = 0 ] && echo "dsize_cache: PASS" || echo "dsize_cache: FAIL"; exit "$fail"
