#!/usr/bin/env bash
# Bookmarks, Recents and the daemon that observes them.   bash tests/track/track_test.sh
# (1) bash side (bashbasicsbyvk_track.sh): bookmark = pointer to a folder OR a file, follows rename / folder move, heals by inode;
#     recents: record, count, auto-lock after more than 5, follow, forget, exclude rules
# (2) python twin (bashbasicsbyvk_track_lib.py): the same moves seen from outside the app, an editor's backup file is not a move
# (3) the real daemon with inotify: a plain  mv  in a shell re-points a bookmark and a recents row (a rename AND a folder move)
# (4) displayer: a bookmark row wears its target's emoji, no .swlink, red dot when the target is gone
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/wait_lib.sh"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(mktemp -d)"; trap 'kill "${DPID:-0}" 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/bin/t1"; echo x > "$HOME/bin/0.sh"
LOCKSH="$(bvk_need bashbasicsbyvk_lock.sh)"; TRKSH="$(bvk_need bashbasicsbyvk_track.sh)"; LIB="$(bvk_need bashbasicsbyvk_track_lib.py)"
source "$LOCKSH"; source "$(bvk_need bashbasicsbyvk_planetary_resources.sh)"; source "$TRKSH"
_fav_id() { [ -e "$1" ] && stat -c '%d:%i' -- "$1"; }
tgt() { _swlink_read_target_v "$1"; printf '%s' "$_SWL_T"; }

# ---- (1) bash side ---------------------------------------------------------------------
B1="$(_swlink_write "$_SW_DIR" "$HOME/bin/t1" t1)"; B2="$(_swlink_write "$_SW_DIR" "$HOME/bin/0.sh" 0.sh)"
[ "$(tgt "$B2")" = "$HOME/bin/0.sh" ] && ok "a bookmark of a FILE stores the file (not its folder)" || bad "file bookmark target: $(tgt "$B2")"
grep -q '^SWLINK_ID=[0-9]*:[0-9]*$' "$B2" && ok "bookmark carries the inode of its target" || bad "no SWLINK_ID"
_swlink_name_v "$B2"; [ "$_SWL_NAME" = "0.sh" ] && ok "shown name has no .swlink" || bad "name: $_SWL_NAME"
for i in 1 2 3 4 5; do _rc_record "$HOME/bin/0.sh" >/dev/null; done
_lk_load; _lk_is_locked "$HOME/bin/0.sh" && bad "locked after only 5 uses (must be MORE than 5)" || ok "5 uses: not locked yet"
out="$(_rc_record "$HOME/bin/0.sh")"; _lk_load
_lk_is_locked "$HOME/bin/0.sh" && ok "6th use: locked automatically" || bad "not locked after 6 uses"
case "$out" in *"Locked automatically"*) ok "the auto-lock says so" ;; *) bad "auto-lock silent: $out" ;; esac
out="$(_rc_record "$HOME/bin/0.sh")"; [ -z "$out" ] && ok "already locked: nothing to do, nothing said" || bad "re-locked: $out"
_rc_record "$HOME/bin/t1" >/dev/null; _rc_build
[ "${items[0]}" = "$HOME/bin/t1" ] && [ "${items[1]}" = "$HOME/bin/0.sh" ] && ok "recents: newest first, folders and files together" || bad "recents order: ${items[*]}"
mv "$HOME/bin/0.sh" "$HOME/bin/1.sh"; _trk_move "$HOME/bin/0.sh" "$HOME/bin/1.sh"
[ "$(tgt "$B2")" = "$HOME/bin/1.sh" ] && ok "rename: the bookmark follows" || bad "bookmark after rename: $(tgt "$B2")"
_rc_build; [ "${items[1]}" = "$HOME/bin/1.sh" ] && ok "rename: the recents row follows (count kept)" || bad "recents after rename: ${items[*]}"
mv "$HOME/bin" "$HOME/bin2"; _trk_move "$HOME/bin" "$HOME/bin2"
{ [ "$(tgt "$B1")" = "$HOME/bin2/t1" ] && [ "$(tgt "$B2")" = "$HOME/bin2/1.sh" ]; } && ok "folder move: every bookmark below it follows" || bad "after folder move: $(tgt "$B1") $(tgt "$B2")"
mv "$HOME/bin2/1.sh" "$HOME/bin2/zz.sh"
_swlink_heal "$B2" && [ "$(tgt "$B2")" = "$HOME/bin2/zz.sh" ] && ok "a move the app never saw is found by inode" || bad "heal failed: $(tgt "$B2")"
rm -rf "$HOME/bin2/t1"; _trk_forget "$HOME/bin2/t1"
{ ! grep -q "bin2/t1" "$_RC_FILE" && grep -q "bin2/1.sh" "$_RC_FILE" && [ -e "$B1" ]; } && ok "delete: the recents row goes, the bookmark stays" || bad "after delete: $(cat "$_RC_FILE")"
printf 'filename zz.sh\n' > "$_RC_EXCLUDE_FILE"; _rc_build
[ "${#items[@]}" = 0 ] && ok "exclude rule hides a file from recents" || bad "exclude ignored: ${items[*]}"

# ---- (2) python twin -------------------------------------------------------------------
H2="$T/h2"; mkdir -p "$H2/d" "$H2/.bashbasicsbyvk/switch"; echo y > "$H2/d/a.txt"
printf 'SWLINK_TARGET=%s\nSWLINK_NAME=a.txt\n' "$H2/d/a.txt" > "$H2/.bashbasicsbyvk/switch/a.txt.swlink"
printf '2\t%s\n' "$H2/d/a.txt" > "$H2/.bashbasicsbyvk/recents.tsv"
res="$(BVK_HOME_DIR="$H2/.bashbasicsbyvk" python3 -I - "$(dirname "$LIB")" "$H2" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1]); h = sys.argv[2]
import bashbasicsbyvk_track_lib as T
r = T.reconcile_all([h]); os.rename(h + "/d", h + "/e")
m = T.on_moved(h + "/d", h + "/e"); v = T.on_moved(h + "/e/a.txt", h + "/e/a.txt~")
print(r["bookmarks_stamped"], m["bookmarks"], m["recents"], len(v))
PY
)"
[ "$res" = "1 1 1 0" ] && ok "python twin: stamps the inode, follows a folder move, ignores an editor backup rename" || bad "python twin: '$res'"
grep -q "^SWLINK_TARGET=$H2/e/a.txt$" "$H2/.bashbasicsbyvk/switch/a.txt.swlink" && ok "python twin wrote the new target" || bad "target not rewritten"

# ---- (3) the real daemon, inotify ------------------------------------------------------
if python3 -c 'import watchdog' 2>/dev/null; then
  H3="$T/h3"; mkdir -p "$H3/bin" "$H3/.bashbasicsbyvk/switch"; echo z > "$H3/bin/0.sh"
  printf 'SWLINK_TARGET=%s\nSWLINK_NAME=0.sh\n' "$H3/bin/0.sh" > "$H3/.bashbasicsbyvk/switch/0.sh.swlink"
  printf '1\t%s\n' "$H3/bin/0.sh" > "$H3/.bashbasicsbyvk/recents.tsv"
  DM="$(bvk_need bashbasicsbyvk_local_daemon)"; cp "$DM" "$(dirname "$LIB")/bashbasicsbyvk_fav_lib.py" "$LIB" "$(bvk_need bashbasicsbyvk_planetary_resources.py)" "$(bvk_need bashbasicsbyvk_planetary_versions.list)" "$(bvk_need bashbasicsbyvk_index_lib.py)" "$T/" 2>/dev/null
  HOME="$H3" BVK_WARM_DELAY=9999 python3 -I "$T/bashbasicsbyvk_local_daemon" --daemon >/dev/null 2>&1 & DPID=$!
  wait_grep 20 "$H3/.bashbasicsbyvk/daemons/local.log" "observer started" || bad "daemon never started watching"
  mv "$H3/bin/0.sh" "$H3/bin/1.sh"
  wait_until 20 "bookmark follows a plain mv" grep -q "bin/1.sh" "$H3/.bashbasicsbyvk/switch/0.sh.swlink" && ok "daemon: rename seen, bookmark re-pointed" || bad "daemon missed the rename"
  echo q > "$H3/loose.txt"; echo q2 >> "$H3/loose.txt"        # an ordinary file written before the next move: events are handled in order
  mv "$H3/bin" "$H3/bin2"
  wait_until 20 "bookmark follows a folder mv" grep -q "bin2/1.sh" "$H3/.bashbasicsbyvk/switch/0.sh.swlink" && ok "daemon: folder move seen, bookmark re-pointed" || bad "daemon missed the folder move"
  wait_until 20 "recents row follows" grep -q "bin2/1.sh" "$H3/.bashbasicsbyvk/recents.tsv" && ok "daemon: recents row followed too" || bad "recents row not followed"
  grep -q loose "$H3/.bashbasicsbyvk/recents.tsv" && bad "daemon put a modified file into recents" || ok "daemon: modified files do not join recents"
else
  echo "  SKIP daemon part: python watchdog is not installed (NOT verified)"
fi

# ---- (4) displayer ---------------------------------------------------------------------
F="$ROOT/script/file"
_is_archive() { return 1; }; _is_image() { return 1; }; _is_plugin() { return 1; }; _is_executable() { [ -x "$1" ]; }
declare -gA item_icon=() _FAV_LABEL=() _REC_LABEL=()
# shellcheck disable=SC1090
eval "$(sed -n '/^_resolve_display_parts_v() {/,/^_shortcut_display_parts() {/p' "$F/engine/bashbasicsbyvk_displayer.sh" | sed '$d')"
mkdir -p "$HOME/p"; printf '#!/bin/sh\n' > "$HOME/p/run.sh"; chmod +x "$HOME/p/run.sh"; mkdir -p "$HOME/p/dir"
SB1="$(_swlink_write "$_SW_DIR" "$HOME/p/run.sh" run.sh)"; SB2="$(_swlink_write "$_SW_DIR" "$HOME/p/dir" dir)"
_resolve_display_parts_v "$HOME/p/run.sh"; local_icon="$_rdp_icon"; _resolve_display_parts_v "$SB1"
{ [ "$_rdp_icon" = "$local_icon" ] && [ "$_rdp_bn" = "run.sh" ]; } && ok "bookmark of a script: the same emoji as the folder view, no suffix" || bad "script bookmark row: '$_rdp_icon' '$_rdp_bn' vs '$local_icon'"
_resolve_display_parts_v "$SB2"; { [ "$_rdp_icon" = "📁" ] && [ "$_rdp_bn" = "dir" ]; } && ok "bookmark of a folder: 📁" || bad "folder bookmark row: '$_rdp_icon' '$_rdp_bn'"
rm -rf "$HOME/p/dir"; _resolve_display_parts_v "$SB2"; case "$_rdp_bn" in *🔴) ok "bookmark whose target is gone: red dot" ;; *) bad "no red dot: $_rdp_bn" ;; esac
exit $fail
