"""
bashbasicsbyvk_fav_lib — favourites file I/O for the daemon.

Same on-disk format as bashbasicsbyvk_favourites.sh (bash side):

    # comments
    PATH=/home/me/icons
    DIR_ID=64768:1234
    icon_01.png #id=64768:99
    big-logo.svg => Logo #id=64768:100
    gone.png #id=64768:101 #moved=/home/me/archive/gone.png

  name [=> alias] [#id=dev:inode] [#moved=/new/abs/path]

The daemon keeps favourites attached when items / folders are renamed or moved
(matched by inode).  It NEVER deletes a favourite: an item that disappears is
kept, and one that moved elsewhere gets a #moved= note (shown in sw → ⭐).

Writes are atomic (tmp + replace) and guarded by the same mkdir-lock the bash
side uses (planetary resources: owner pid inside, taken over only when its owner is dead or
the lock is stale), so the shell and the daemon cannot clobber each other. The lock is
never held during a directory walk: reconcile_all reads under it, walks without it, and
applies what it found on a fresh read (compare-and-set), so an edit made meanwhile survives.
Deleted items: a favourite whose item vanished is KEPT (it may come back or be found by inode);
only the user removes a favourite.
"""
import hashlib
import os
import time
from contextlib import contextmanager
from pathlib import Path

import bashbasicsbyvk_planetary_resources as pr

BVK_DIR = pr.BVK_DIR
FAV_DIR = BVK_DIR / "favourites"
LOCK_DIR = FAV_DIR / ".lock"

LOCK_TIMEOUT = 3.0      # seconds to wait for the lock before proceeding anyway
LOCK_STALE = 10.0       # a lock older than this is considered abandoned


# ── locking (mkdir is atomic; shared with the bash implementation) ────────────
@contextmanager
def lock():
    FAV_DIR.mkdir(parents=True, exist_ok=True)
    with pr.dir_lock(LOCK_DIR, wait=LOCK_TIMEOUT, stale=LOCK_STALE) as got:
        yield got


# ── helpers ───────────────────────────────────────────────────────────────────
norm = pr.norm
stat_id = pr.stat_id


def hash_key(dirpath):
    return hashlib.sha1(norm(dirpath).encode("utf-8", "surrogateescape")).hexdigest()[:16]


def _join(d, name):
    return (d.rstrip("/") or "") + "/" + name


class Item:
    __slots__ = ("name", "alias", "id", "moved")

    def __init__(self, name, alias="", id_="", moved=""):
        self.name, self.alias, self.id, self.moved = name, alias, id_, moved

    def line(self):
        s = self.name
        if self.alias:
            s += " => " + self.alias
        if self.id:
            s += " #id=" + self.id
        if self.moved:
            s += " #moved=" + self.moved
        return s


class FavFile:
    def __init__(self, file, dirpath, dir_id, items):
        self.file = Path(file)
        self.dirpath = dirpath
        self.dir_id = dir_id
        self.items = items
        self.old_files = set()      # files this favourite lived in before its folder moved (removed after the new one is written)

    def find(self, name):
        for it in self.items:
            if it.name == name:
                return it
        return None


def parse(file):
    dirpath, dir_id, items = "", "", []
    try:
        text = Path(file).read_text(encoding="utf-8", errors="surrogateescape")
    except OSError:
        return None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("PATH="):
            dirpath = line[5:]
            continue
        if line.startswith("DIR_ID="):
            dir_id = line[7:]
            continue
        moved = idv = alias = ""
        if " #moved=" in line:
            line, _, moved = line.rpartition(" #moved=")
        if " #id=" in line:
            line, _, idv = line.rpartition(" #id=")
        if " => " in line:
            line, _, alias = line.partition(" => ")
            # partition splits at the first " => "; name is before it
        name = line.strip()
        if name:
            items.append(Item(name, alias.strip(), idv.strip(), moved.strip()))
    if not dirpath:
        return None
    return FavFile(file, dirpath, dir_id, items)


def write(fav):
    """Atomic write; removes the file when no favourites are left."""
    fav.file = FAV_DIR / (hash_key(fav.dirpath) + ".fav")
    if not fav.items:
        try:
            fav.file.unlink()
        except OSError:
            pass
        return
    FAV_DIR.mkdir(parents=True, exist_ok=True)
    tmp = fav.file.with_name(fav.file.name + ".tmp.d%d" % os.getpid())
    lines = [
        "# favourites — one item per line:   name   [=> alias]   #id=dev:inode",
        "# safe to edit by hand; #id keeps a favourite attached if the item is renamed",
        "PATH=" + fav.dirpath,
        "DIR_ID=" + (fav.dir_id or stat_id(fav.dirpath)),
    ] + [it.line() for it in fav.items]
    tmp.write_text("\n".join(lines) + "\n", encoding="utf-8", errors="surrogateescape")
    os.replace(tmp, fav.file)


def load_all():
    out = []
    if not FAV_DIR.is_dir():
        return out
    for f in sorted(FAV_DIR.glob("*.fav")):
        fav = parse(f)
        if fav:
            out.append(fav)
    return out


# ── reconcile one folder's favourites against the disk ───────────────────────
def reconcile(fav, missing_ids=None):
    """Bring one FavFile in line with the filesystem.
    Returns (changed: bool).  Items that cannot be found are collected into
    `missing_ids` ({inode: (fav, item)}) for an optional wider search."""
    changed = False
    d = fav.dirpath
    by_ino = None
    for it in fav.items:
        p = _join(d, it.name)
        if os.path.lexists(p):
            cur = stat_id(p)
            if cur and cur != it.id:
                it.id, changed = cur, True
            if it.moved:
                it.moved, changed = "", True
            continue
        # not at its old name: renamed in place?
        if it.id and ":" in it.id:
            dev, _, ino = it.id.partition(":")
            if by_ino is None:
                by_ino = {}
                try:
                    with os.scandir(d) as sc:
                        for e in sc:
                            by_ino[e.inode()] = e.name
                except OSError:
                    by_ino = {}
            try:
                newname = by_ino.get(int(ino))
            except ValueError:
                newname = None
            if newname and newname != it.name and fav.find(newname) is None:
                it.name, it.moved, changed = newname, "", True
                continue
        if it.moved and os.path.lexists(it.moved):
            continue                                   # known to live elsewhere
        if missing_ids is not None and it.id and ":" in it.id:
            try:
                missing_ids[int(it.id.partition(":")[2])] = (fav, it)
            except ValueError:
                pass
    return changed


def find_moved(missing_ids, roots, budget=60.0, skip=None):
    """One walk of `roots` (planetary resources: the one inode walk) looking for the inodes of missing favourites.
    Sets item.moved for each hit. Returns the number found."""
    if not missing_ids:
        return 0
    wanted = {it.id: (fav, it) for fav, it in missing_ids.values() if it.id}
    hits = pr.find_inodes(roots, set(wanted), budget, skip)
    found = 0
    for sid, path in hits.items():
        fav, it = wanted[sid]
        if path != _join(fav.dirpath, it.name):
            it.moved = path
            found += 1
    return found


# ── event handlers (called by the daemon) ─────────────────────────────────────
def _dir_moved(favs, src, dest):
    """A folder was renamed/moved: re-point every favourites file at/under it. Returns the set of FavFiles that changed."""
    dirty = set()
    for fav in favs:
        old = fav.dirpath
        if old == src or old.startswith(src + "/"):
            fav.old_files.add(fav.file)
            fav.dirpath = dest + old[len(src):]
            dirty.add(fav)
        # entries whose #moved target lived under the moved folder
        for it in fav.items:
            if it.moved and (it.moved == src or it.moved.startswith(src + "/")):
                it.moved = dest + it.moved[len(src):]
                dirty.add(fav)
    return dirty


def _item_moved(favs, src, dest):
    """A file or folder was renamed/moved. Returns the set of FavFiles that changed."""
    src, dest = os.path.normpath(src), os.path.normpath(dest)
    sdir, sname = os.path.dirname(src), os.path.basename(src)
    ddir, dname = os.path.dirname(dest), os.path.basename(dest)
    dirty = set()
    for fav in favs:
        changed = False
        # 1) the moved thing is a favourite of its old folder
        if fav.dirpath == sdir:
            it = fav.find(sname)
            if it is not None:
                if ddir == sdir:                               # renamed in place
                    if fav.find(dname) is None:
                        it.name, it.moved = dname, ""
                        it.id = stat_id(dest) or it.id
                        changed = True
                else:                                          # moved to another folder
                    it.moved = dest
                    it.id = stat_id(dest) or it.id
                    changed = True
        # 2) something lands on a favourite's name (editor atomic-save, or
        #    an item moved back) -> refresh / revive it
        if fav.dirpath == ddir:
            it = fav.find(dname)
            if it is not None and not (fav.dirpath == sdir and sname == dname):
                it.id = stat_id(dest) or it.id
                it.moved = ""
                changed = True
        # 3) an item that already lives elsewhere moved again -> follow it
        for it in fav.items:
            if it.moved and (it.moved == src):
                it.moved = dest
                changed = True
        if changed:
            dirty.add(fav)
    return dirty


def _commit(touched):
    """Write every changed favourites file; remove the file a moved folder's favourites lived in before."""
    for fav in touched:
        write(fav)
        for old in fav.old_files:
            if old != fav.file:
                try:
                    old.unlink()
                except OSError:
                    pass


def apply_moves(events):
    """A batch of (src, dest, is_dir) moves, in the order they happened: ONE lock, favourites read once, every changed file written once.
    Returns the number of favourites files touched."""
    touched = set()
    with lock():
        favs = load_all()
        for src, dest, is_dir in events:
            src, dest = norm(src), norm(dest)
            if is_dir:
                touched |= _dir_moved(favs, src, dest)
            touched |= _item_moved(favs, src, dest)
        _commit(touched)
    return len(touched)


def on_dir_moved(src, dest):
    """One folder was renamed/moved: re-point the favourites files at/under it. Returns the number of files touched."""
    with lock():
        touched = _dir_moved(load_all(), norm(src), norm(dest))
        _commit(touched)
    return len(touched)


def on_item_moved(src, dest):
    """One file or folder was renamed/moved. Returns the number of favourites files touched."""
    with lock():
        touched = _item_moved(load_all(), src, dest)
        _commit(touched)
    return len(touched)


def reconcile_all(search_roots=None, budget=60.0, skip=None):
    """Full pass (daemon start / periodic). Returns dict of counters.
    1. under the lock: bring every file in line with the disk, collect what cannot be found;
    2. WITHOUT the lock: one walk looks for the missing items / folders by inode;
    3. under the lock again, on a fresh read: apply a hit only where the favourite is still exactly as it was when it went missing."""
    stats = {"folders": 0, "changed": 0, "located": 0}
    lost_items, lost_dirs = [], []         # (dirpath, name, id)  /  (dirpath, dir_id)
    with lock():
        missing = {}
        for fav in load_all():
            stats["folders"] += 1
            if not os.path.isdir(fav.dirpath):
                if fav.dir_id and search_roots:
                    lost_dirs.append((fav.dirpath, fav.dir_id))      # the folder itself moved while we were not watching
                continue
            if reconcile(fav, missing):
                write(fav)
                stats["changed"] += 1
        for fav, it in missing.values():
            lost_items.append((fav.dirpath, it.name, it.id))
    if not search_roots or not (lost_items or lost_dirs):
        return stats
    wanted = {i for _, _, i in lost_items} | {d for _, d in lost_dirs}
    hits = pr.find_inodes(search_roots, wanted, budget, skip)        # the lock is NOT held while walking
    if not hits:
        return stats
    with lock():
        favs = load_all()
        for old_dir, dir_id in lost_dirs:
            new = hits.get(dir_id)
            if not new or not os.path.isdir(new):
                continue
            for fav in favs:
                if fav.dirpath == old_dir and fav.dir_id == dir_id and not os.path.isdir(old_dir):
                    old_file = fav.file
                    fav.dirpath = new
                    write(fav)
                    if old_file != fav.file:
                        try:
                            old_file.unlink()
                        except OSError:
                            pass
                    stats["changed"] += 1
        for dirpath, name, ident in lost_items:
            new = hits.get(ident)
            if not new:
                continue
            for fav in favs:
                it = fav.find(name) if fav.dirpath == dirpath else None
                if it is not None and it.id == ident and not os.path.lexists(_join(dirpath, name)) and new != _join(dirpath, name):
                    it.moved = new
                    write(fav)
                    stats["located"] += 1
    return stats
