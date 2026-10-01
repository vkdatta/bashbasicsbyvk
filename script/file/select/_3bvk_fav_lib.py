"""
_3bvk_fav_lib — favourites file I/O for the daemon.

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
side uses, so the shell and the daemon cannot clobber each other.
"""
import hashlib
import os
import time
from contextlib import contextmanager
from pathlib import Path

BVK_DIR = Path(os.environ.get("BVK_HOME_DIR") or (Path.home() / ".bashbasicsbyvk"))
FAV_DIR = BVK_DIR / "favourites"
LOCK_DIR = FAV_DIR / ".lock"

LOCK_TIMEOUT = 3.0      # seconds to wait for the lock before proceeding anyway
LOCK_STALE = 10.0       # a lock older than this is considered abandoned


# ── locking (mkdir is atomic; shared with the bash implementation) ────────────
@contextmanager
def lock():
    FAV_DIR.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + LOCK_TIMEOUT
    got = False
    while True:
        try:
            os.mkdir(LOCK_DIR)
            got = True
            break
        except FileExistsError:
            try:
                if time.time() - LOCK_DIR.stat().st_mtime > LOCK_STALE:
                    os.rmdir(LOCK_DIR)
                    continue
            except OSError:
                pass
            if time.time() > deadline:
                break
            time.sleep(0.05)
        except OSError:
            break
    try:
        yield got
    finally:
        if got:
            try:
                os.rmdir(LOCK_DIR)
            except OSError:
                pass


# ── helpers ───────────────────────────────────────────────────────────────────
def norm(p):
    p = str(p)
    if len(p) > 1:
        p = p.rstrip("/")
    return p or "/"


def hash_key(dirpath):
    return hashlib.sha1(norm(dirpath).encode("utf-8", "surrogateescape")).hexdigest()[:16]


def stat_id(path):
    try:
        st = os.lstat(path)
        return "%d:%d" % (st.st_dev, st.st_ino)
    except OSError:
        return ""


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
    """One walk of `roots` looking for the inodes of missing favourites.
    Sets item.moved for each hit.  Returns the number found."""
    if not missing_ids:
        return 0
    deadline = time.time() + budget
    found = 0
    remaining = dict(missing_ids)
    stack = [str(r) for r in roots]
    while stack and remaining and time.time() < deadline:
        d = stack.pop()
        try:
            with os.scandir(d) as sc:
                for e in sc:
                    if e.name.startswith("."):
                        continue
                    try:
                        isdir = e.is_dir(follow_symlinks=False)
                    except OSError:
                        continue
                    hit = remaining.get(e.inode())
                    if hit is not None:
                        fav, it = hit
                        if e.path != _join(fav.dirpath, it.name):
                            it.moved = e.path
                            found += 1
                            remaining.pop(e.inode(), None)
                    if isdir and not (skip and skip(e.path)):
                        stack.append(e.path)
        except OSError:
            continue
    return found


# ── event handlers (called by the daemon) ─────────────────────────────────────
def on_dir_moved(src, dest):
    """A folder was renamed/moved: re-point every favourites file at/under it."""
    src, dest = norm(src), norm(dest)
    n = 0
    with lock():
        for fav in load_all():
            old = fav.dirpath
            if old == src or old.startswith(src + "/"):
                fav.dirpath = dest + old[len(src):]
                old_file = fav.file
                write(fav)
                if old_file != fav.file:
                    try:
                        old_file.unlink()
                    except OSError:
                        pass
                n += 1
            # entries whose #moved target lived under the moved folder
            dirty = False
            for it in fav.items:
                if it.moved and (it.moved == src or it.moved.startswith(src + "/")):
                    it.moved = dest + it.moved[len(src):]
                    dirty = True
            if dirty:
                write(fav)
    return n


def on_item_moved(src, dest):
    """A file or folder was renamed/moved.  Returns number of favourites touched."""
    src, dest = os.path.normpath(src), os.path.normpath(dest)
    sdir, sname = os.path.dirname(src), os.path.basename(src)
    ddir, dname = os.path.dirname(dest), os.path.basename(dest)
    n = 0
    with lock():
        for fav in load_all():
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
            #    an item moved back) → refresh / revive it
            if fav.dirpath == ddir:
                it = fav.find(dname)
                if it is not None and not (fav.dirpath == sdir and sname == dname):
                    it.id = stat_id(dest) or it.id
                    it.moved = ""
                    changed = True
            # 3) an item that already lives elsewhere moved again → follow it
            for it in fav.items:
                if it.moved and (it.moved == src):
                    it.moved = dest
                    changed = True
            if changed:
                write(fav)
                n += 1
    return n


def reconcile_all(search_roots=None, budget=60.0, skip=None):
    """Full pass (daemon start / periodic).  Returns dict of counters."""
    stats = {"folders": 0, "changed": 0, "located": 0}
    with lock():
        favs = load_all()
        missing = {}
        for fav in favs:
            stats["folders"] += 1
            if not os.path.isdir(fav.dirpath):
                # folder itself moved while we were not watching → adopt by DIR_ID
                if fav.dir_id:
                    new = _find_dir_by_id(fav.dir_id, search_roots or [], budget / 2, skip)
                    if new:
                        old_file = fav.file
                        fav.dirpath = new
                        write(fav)
                        if old_file != fav.file:
                            try:
                                old_file.unlink()
                            except OSError:
                                pass
                        stats["changed"] += 1
                else:
                    continue
            if reconcile(fav, missing):
                write(fav)
                stats["changed"] += 1
        if missing and search_roots:
            stats["located"] = find_moved(missing, search_roots, budget, skip)
            if stats["located"]:
                touched = {id(f): f for f, _ in missing.values()}
                for fav in touched.values():
                    write(fav)
    return stats


def _find_dir_by_id(dir_id, roots, budget, skip):
    try:
        want = int(dir_id.partition(":")[2])
    except ValueError:
        return None
    deadline = time.time() + budget
    stack = [str(r) for r in roots]
    while stack and time.time() < deadline:
        d = stack.pop()
        try:
            with os.scandir(d) as sc:
                for e in sc:
                    if e.name.startswith("."):
                        continue
                    try:
                        if not e.is_dir(follow_symlinks=False):
                            continue
                    except OSError:
                        continue
                    if e.inode() == want:
                        return e.path
                    if not (skip and skip(e.path)):
                        stack.append(e.path)
        except OSError:
            continue
    return None
