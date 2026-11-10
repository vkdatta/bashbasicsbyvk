"""
bashbasicsbyvk_track_lib - keeps everything that POINTS at a path in step with the path, for the local daemon.

The twin of bashbasicsbyvk_track.sh (same files, same formats; the app does the same in bash for the changes IT makes,
this file does it for the changes made OUTSIDE the app: mv in a shell, a file manager, another tool).

  bookmarks   ~/.bashbasicsbyvk/switch/*.swlink   SWLINK_TARGET= follows a rename / move (a file or a folder, and anything below a folder)
              SWLINK_ID=dev:inode                 finds a target that moved while nobody was watching
  recents     ~/.bashbasicsbyvk/recents.tsv       COUNT<TAB>/abs/path : a row follows its item, a deleted item's row goes
  locks       ~/.bashbasicsbyvk/locks.list        a lock follows its item; a lock of a vanished item is kept for a day (it may come back)
  shortcuts   ~/.bashbasicsbyvk/shortcut.registry sc_file|target : both halves follow; SHORTCUT_TARGET= is rewritten in the .shortcut file
  ids         ~/.bashbasicsbyvk/pointers.state    JSON: the "dev:inode" of every lock / recents row / shortcut target, so those can be
                                                  found again after a move nobody saw (bookmarks keep their id inside the .swlink)

It NEVER deletes a bookmark: a bookmark whose target is gone stays (the app shows it with a red dot).
Favourites are kept by bashbasicsbyvk_fav_lib.py.

How it writes: ONE batch of events = one lock, every registry read once and written once, each write atomic. The lock is never held
during a directory walk: reconcile_all reads and stamps under the lock, walks without it, and applies what it found as ordinary
"moved" events (so a pointer the user edited during the walk is never overwritten with old text).

CLI:  python3 bashbasicsbyvk_track_lib.py sync      one full reconcile now (prints the counters)
"""
import json
import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path

import bashbasicsbyvk_planetary_resources as pr

BVK_DIR = pr.BVK_DIR
SW_DIR = BVK_DIR / "switch"
RECENTS = BVK_DIR / "recents.tsv"
LOCKS = BVK_DIR / "locks.list"
SHORTCUTS = BVK_DIR / "shortcut.registry"
STATE = BVK_DIR / "pointers.state"
LOCK_DIR = BVK_DIR / "track.lock"          # the same mkdir lock bashbasicsbyvk_track.sh uses (_trk_lock)
LOCK_WAIT = 5.0
LOCK_STALE = 15.0
LOCK_ORPHAN_GRACE = 86400                  # a lock whose item vanished is kept this long (delete + recreate, a checkout) before it goes
MISS_BACKOFF = 6 * 3600                    # an id the walk could not find is searched again after this long (a sync on demand ignores it)

norm, stat_id = pr.norm, pr.stat_id
_map = pr.map_path
_write_atomic = pr.write_atomic
_MISS = {}                                 # "dev:inode" -> earliest time of the next walk for it (daemon memory only)


class LockBusy(Exception):
    """The track lock is held by a live process for longer than LOCK_WAIT: the caller tries again later."""


@contextmanager
def _lock(strict=True):
    with pr.dir_lock(LOCK_DIR, wait=LOCK_WAIT, stale=LOCK_STALE) as got:
        if strict and not got:
            raise LockBusy()
        yield


_TRANSIENT = (".swp", ".swpx", ".tmp", "~", ".bak", ".orig", ".lock", ".part", ".crdownload")


def is_transient(p):
    """An editor's backup / temp file: a rename INTO or OUT OF one is a save, not a move of the item."""
    return p.endswith(_TRANSIENT) or os.path.basename(p).startswith(".#")


# ═════════════════════════ the registries, read into memory ═════════════════════════
class _World:
    """Every registry, loaded once under the lock, changed in memory, written back once (only what changed)."""

    def __init__(self):
        self.bm = []            # [path of .swlink, lines, target, dirty]
        for f in self._swlinks():
            try:
                lines = f.read_text(errors="replace").splitlines()
            except OSError:
                continue
            self.bm.append([f, lines, self._get(lines, "SWLINK_TARGET"), False])
        self.rc = self._read_recents()
        self.rc_dirty = False
        self.lk = self._read_lines(LOCKS)
        self.lk_dirty = False
        self.sc = self._read_lines(SHORTCUTS)
        self.sc_dirty = False
        self.sc_files = {}      # .shortcut files whose SHORTCUT_TARGET= must be rewritten: path -> new target
        self.state = self._read_state()
        self.state_dirty = False
        self.counts = {"bookmarks": 0, "recents": 0, "locks": 0, "shortcuts": 0}

    # -- readers
    @staticmethod
    def _swlinks():
        try:
            return sorted(p for p in SW_DIR.rglob("*.swlink") if p.is_file())
        except OSError:
            return []

    @staticmethod
    def _get(lines, key):
        pre = key + "="
        for ln in lines:
            if ln.startswith(pre):
                return ln[len(pre):]
        return ""

    @staticmethod
    def _read_lines(path):
        try:
            return path.read_text(errors="replace").splitlines()
        except OSError:
            return []

    @staticmethod
    def _read_recents():
        rows = []
        try:
            for ln in RECENTS.read_text(errors="replace").splitlines():
                n, _, p = ln.partition("\t")
                if p and n.isdigit():
                    rows.append([int(n), p])
        except OSError:
            pass
        return rows

    @staticmethod
    def _read_state():
        try:
            d = json.loads(STATE.read_text())
            if isinstance(d, dict):
                return {k: d.get(k) if isinstance(d.get(k), dict) else {} for k in ("locks", "recents", "shortcuts")}
        except (OSError, ValueError):
            pass
        return {"locks": {}, "recents": {}, "shortcuts": {}}

    # -- a path moved: every pointer follows
    def move(self, src, dest):
        for b in self.bm:
            new = _map(b[2], src, dest)
            if new is not None:
                b[2], b[3] = new, True
                self.counts["bookmarks"] += 1
        n = 0
        for r in self.rc:
            new = _map(r[1], src, dest)
            if new is not None:
                r[1], n = new, n + 1
        if n:
            self.rc_dirty = True
            self.counts["recents"] += n
        out, n = [], 0
        for p in self.lk:
            new = _map(p, src, dest)
            out.append(new if new is not None else p)
            n += new is not None
        if n:
            self.lk, self.lk_dirty = out, True
            self.counts["locks"] += n
        out, n = [], 0
        for row in self.sc:
            sc, _, target = row.partition("|")
            new_sc, new_t = _map(sc, src, dest) or sc, _map(target, src, dest) or target
            if new_sc == sc and new_t == target:
                out.append(row)
                continue
            self.sc_dirty = True
            if not os.path.isfile(new_sc):
                continue                                        # the shortcut file is gone: lazy cleanup, like the app
            if new_t != target:
                self.sc_files[new_sc] = new_t
                n += 1
            out.append(new_sc + "|" + new_t)
        if self.sc_dirty:
            self.sc = out
        self.counts["shortcuts"] += n
        for kind in ("locks", "recents", "shortcuts"):          # the ids follow their paths
            d, nd = self.state[kind], {}
            for k, v in d.items():
                new = _map(k, src, dest)
                nd[new if new is not None else k] = v
            if nd != d:
                self.state[kind], self.state_dirty = nd, True

    # -- a path is gone: its recents row goes at once; a lock is kept for the grace time (it may come back)
    def gone(self, path):
        keep = [r for r in self.rc if _map(r[1], path, "") is None]
        if len(keep) != len(self.rc):
            self.counts["recents"] += len(self.rc) - len(keep)
            self.rc, self.rc_dirty = keep, True
        now = int(time.time())
        for p in self.lk:
            if _map(p, path, "") is not None:
                ent = self.state["locks"].setdefault(p, {})
                if not ent.get("gone"):
                    ent["gone"] = now
                    self.state_dirty = True
                    self.counts["locks"] += 1

    # -- stamping ids; dropping orphans
    def stamp(self):
        """Give every pointer whose target exists its id; clear the 'gone' mark of a lock whose item is back; drop old orphans.
        Returns the missing pointers as {id: path}."""
        stamped, missing, now = 0, {}, int(time.time())
        for b in self.bm:
            lines, target = b[1], b[2]
            if not target:
                continue
            ident = self._get(lines, "SWLINK_ID")
            if os.path.lexists(target):
                cur = stat_id(target)
                if cur and cur != ident:
                    self._set(b, "SWLINK_ID", cur)
                    stamped += 1
            elif ident and ":" in ident:
                missing[ident] = target
        keep_locks = []
        for p in self.lk:
            ent = self.state["locks"].setdefault(p, {})
            if os.path.lexists(p):
                cur = stat_id(p)
                if cur and ent.get("id") != cur:
                    ent["id"] = cur
                    self.state_dirty = True
                if ent.pop("gone", None):
                    self.state_dirty = True
                keep_locks.append(p)
            elif ent.get("gone") and now - ent["gone"] > LOCK_ORPHAN_GRACE:
                self.state["locks"].pop(p, None)                # the item never came back: the lock goes
                self.state_dirty = self.lk_dirty = True
            else:
                if not ent.get("gone"):
                    ent["gone"] = now                           # noticed missing now: start the grace time
                    self.state_dirty = True
                if ent.get("id"):
                    missing[ent["id"]] = p
                keep_locks.append(p)
        if self.lk_dirty or len(keep_locks) != len(self.lk):
            self.lk, self.lk_dirty = keep_locks, True
        for r in self.rc:
            p = r[1]
            cur = stat_id(p) if os.path.lexists(p) else ""
            ent = self.state["recents"]
            if cur:
                if ent.get(p) != cur:
                    ent[p], self.state_dirty = cur, True
            elif ent.get(p):
                missing[ent[p]] = p
        for row in self.sc:
            t = row.partition("|")[2]
            ent = self.state["shortcuts"]
            cur = stat_id(t) if t and os.path.lexists(t) else ""
            if cur:
                if ent.get(t) != cur:
                    ent[t], self.state_dirty = cur, True
            elif t and ent.get(t):
                missing[ent[t]] = t
        self.stamped = stamped
        return missing

    # -- writers
    def _set(self, b, key, value):
        pre, out, found = key + "=", [], False
        for ln in b[1]:
            if ln.startswith(pre):
                out.append(pre + value)
                found = True
            else:
                out.append(ln)
        if not found:
            out.append(pre + value)
        b[1], b[3] = out, True

    def save(self):
        for b in self.bm:
            if b[3]:
                lines = list(b[1])
                pre, found = "SWLINK_TARGET=", False
                for i, ln in enumerate(lines):
                    if ln.startswith(pre):
                        lines[i], found = pre + b[2], True
                        break
                if not found and b[2]:
                    lines.append(pre + b[2])
                _write_atomic(b[0], "\n".join(lines) + "\n")
        if self.rc_dirty:
            seen, out = {}, []
            for n, p in self.rc:                                # two rows that now point at one path become one (the bigger count)
                if p in seen:
                    out[seen[p]][0] = max(out[seen[p]][0], n)
                else:
                    seen[p] = len(out)
                    out.append([n, p])
            _write_atomic(RECENTS, "".join("%d\t%s\n" % (n, p) for n, p in out))
        if self.lk_dirty:
            _write_atomic(LOCKS, "".join(p + "\n" for p in sorted(set(self.lk))))
        if self.sc_dirty:
            _write_atomic(SHORTCUTS, "".join(r + "\n" for r in self.sc))
        for f, target in self.sc_files.items():
            try:
                lines = Path(f).read_text(errors="replace").splitlines()
                lines = ["SHORTCUT_TARGET=" + target if ln.startswith("SHORTCUT_TARGET=") else ln for ln in lines]
                _write_atomic(f, "\n".join(lines) + "\n")
            except OSError:
                pass
        if self.state_dirty:
            live = {"locks": set(self.lk), "recents": {r[1] for r in self.rc}, "shortcuts": {r.partition("|")[2] for r in self.sc}}
            doc = {k: {p: v for p, v in self.state[k].items() if p in live[k]} for k in live}
            _write_atomic(STATE, json.dumps(doc))


# ═════════════════════════ what the daemon calls ═════════════════════════
def apply_batch(events, raw=False, strict=True):
    """A batch of filesystem events, in the order they happened: (kind, src, dest) with kind "moved" or "deleted".
    Everything that follows is applied under ONE lock, with every registry read once and written once.
    Returns {"bookmarks": n, "recents": n, "locks": n, "shortcuts": n} (the pointers that changed). `raw` skips the editor-temp filter.
    `strict`: raise LockBusy when a live process keeps the lock too long (the daemon then retries the batch) instead of writing without it."""
    todo = []
    for kind, src, dest in events:
        src = norm(src)
        if kind == "moved" and dest:
            dest = norm(dest)
            if raw or not (is_transient(src) or is_transient(dest)):
                todo.append(("moved", src, dest))
        elif kind == "deleted" and (raw or not is_transient(src)):
            todo.append(("deleted", src, ""))
    if not todo:
        return {}
    with _lock(strict):
        w = _World()
        gone = []
        for kind, src, dest in todo:
            if kind == "moved":
                w.move(src, dest)
            else:
                gone.append(src)
        for p in gone:
            if not os.path.lexists(p):          # a delete followed by a re-create (a checkout, a build) is not a delete
                w.gone(p)
        w.save()
        return w.counts


def on_moved(src, dest):
    """One file or folder was renamed / moved. Returns {what: count} of everything that followed it."""
    return apply_batch([("moved", src, dest)])


def on_deleted(path):
    """One file or folder was deleted. Its recents row goes, its lock is kept for a day, bookmarks stay (shown with a red dot)."""
    return apply_batch([("deleted", path, "")])


def reconcile_all(search_roots, budget=30.0, skip=None, force=False):
    """Full pass (daemon start, periodically, .dm.sync).
    1. under the lock: stamp the id of every pointer whose target exists, list the ones whose target is gone;
    2. WITHOUT the lock: one walk finds them by inode (an id that was not found is not searched again for six hours, unless `force`);
    3. under the lock again: what was found is applied as a normal "moved" event, on freshly read registries."""
    try:
        with _lock():
            w = _World()
            missing = w.stamp()
            w.save()
            stamped = w.stamped
    except LockBusy:
        return {"bookmarks_stamped": 0, "bookmarks_located": 0, "searched": 0, "found": 0, "busy": 1}
    now = time.time()
    if force:
        _MISS.clear()
    wanted = {i: p for i, p in missing.items() if _MISS.get(i, 0) <= now}
    found = pr.find_inodes(search_roots, set(wanted), budget, skip) if wanted else {}
    for i in wanted:
        if i not in found:
            _MISS[i] = now + MISS_BACKOFF
    moved = [("moved", wanted[i], p) for i, p in found.items() if wanted[i] != p]
    located = 0
    if moved:
        try:
            located = apply_batch(moved, raw=True).get("bookmarks", 0)
        except LockBusy:
            for i in found:
                _MISS.pop(i, None)                          # not applied: look again at the next pass
    return {"bookmarks_stamped": stamped, "bookmarks_located": located, "searched": len(wanted), "found": len(found)}


def recents_count():
    return len(_World._read_recents())


if __name__ == "__main__":
    if sys.argv[1:] == ["sync"]:
        print(reconcile_all([str(Path.home())], budget=30.0, force=True,
                            skip=lambda p: "/." in p[len(str(Path.home())):]))
    else:
        print(__doc__)
