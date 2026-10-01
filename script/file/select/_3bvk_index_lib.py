"""
_3bvk_index_lib — background metadata index for the .s / .d select engine.

Two caches in one SQLite file  (~/.bashbasicsbyvk/index/index.db):

  hashes    path → size, mtime_ns, inode, device, head-hash, full-hash
            Valid only while the file's CURRENT (size, mtime_ns, inode, device)
            equal the stored ones, so it is always correct — no event
            tracking needed.  Used by .s.dup.  Written through by the select
            engine itself on every run and pre-warmed by the daemon.

  dirsizes  path → recursive size, file count, epoch
            A folder's recursive size can change without its own mtime
            changing, so these rows are only trusted while the daemon is
            alive AND the row's epoch equals the daemon's current epoch (a
            restarted daemon bumps the epoch → everything is recomputed).  The
            daemon deletes rows for every ancestor of a changed path.

Everything degrades gracefully: if sqlite is unavailable, locked, or
BVK_NO_INDEX=1, callers simply compute directly (slower, still correct).
"""
import hashlib
import os
import sqlite3
import stat as statmod
import time
from pathlib import Path

BVK_DIR = Path(os.environ.get("BVK_HOME_DIR") or (Path.home() / ".bashbasicsbyvk"))
INDEX_DIR = BVK_DIR / "index"
DB_PATH = INDEX_DIR / "index.db"
HOT_FILE = INDEX_DIR / "hot.list"
ROOTS_CONF = BVK_DIR / "index_roots.conf"

HEAD_BYTES = 65536
DIR_CACHE_MIN_FILES = 200          # only cache folders with at least this many files
HOT_MAX = 50


def enabled():
    return os.environ.get("BVK_NO_INDEX") != "1"


def _blob(b):
    return sqlite3.Binary(b) if b is not None else None


class Index:
    def __init__(self, path=None):
        INDEX_DIR.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(str(path or DB_PATH), timeout=10, isolation_level=None,
                                  check_same_thread=False)
        try:
            self.db.execute("PRAGMA journal_mode=WAL")
            self.db.execute("PRAGMA synchronous=NORMAL")
        except sqlite3.DatabaseError:
            pass
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS hashes(
                path TEXT PRIMARY KEY, size INTEGER, mtime_ns INTEGER,
                ino INTEGER, dev INTEGER, head BLOB, full BLOB);
            CREATE TABLE IF NOT EXISTS dirsizes(
                path TEXT PRIMARY KEY, size INTEGER, files INTEGER, epoch INTEGER);
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT);
        """)

    # ── meta ──────────────────────────────────────────────────────────────────
    def meta_get(self, key, default=None):
        r = self.db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
        return r[0] if r else default

    def meta_set(self, key, value):
        self.db.execute("INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)", (key, str(value)))

    def epoch(self):
        try:
            return int(self.meta_get("epoch", "0"))
        except ValueError:
            return 0

    def bump_epoch(self):
        e = self.epoch() + 1
        self.meta_set("epoch", e)
        return e

    def daemon_alive(self):
        """True only while a daemon is running AND its inotify watcher is feeding
        events (polling mode cannot invalidate folder sizes → never trusted)."""
        if self.meta_get("events_ok", "0") != "1":
            return False
        try:
            pid = int(self.meta_get("daemon_pid", "0"))
        except ValueError:
            return False
        if pid <= 0:
            return False
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False
        except PermissionError:
            return True

    # ── hash cache ────────────────────────────────────────────────────────────
    @staticmethod
    def _prefix_range(prefix):
        p = prefix.rstrip("/")
        return p + "/", p + "0"           # '0' is the character after '/'

    def hash_rows_under(self, prefix):
        lo, hi = self._prefix_range(prefix)
        out = {}
        for path, size, mt, ino, dev, head, full in self.db.execute(
                "SELECT path,size,mtime_ns,ino,dev,head,full FROM hashes WHERE path>=? AND path<?",
                (lo, hi)):
            out[path] = (size, mt, ino, dev, bytes(head) if head is not None else None,
                         bytes(full) if full is not None else None)
        return out

    def put_hashes(self, rows):
        """rows: (path,size,mtime_ns,ino,dev,head,full)"""
        if not rows:
            return
        self.db.execute("BEGIN")
        try:
            self.db.executemany(
                "INSERT OR REPLACE INTO hashes(path,size,mtime_ns,ino,dev,head,full) VALUES(?,?,?,?,?,?,?)",
                [(p, s, m, i, d, _blob(h), _blob(f)) for p, s, m, i, d, h, f in rows])
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise

    def forget_missing_under(self, prefix, still_exist):
        """Drop cache rows under prefix that are not in `still_exist` (a set)."""
        lo, hi = self._prefix_range(prefix)
        gone = [r[0] for r in self.db.execute("SELECT path FROM hashes WHERE path>=? AND path<?", (lo, hi))
                if r[0] not in still_exist]
        if gone:
            self.db.execute("BEGIN")
            self.db.executemany("DELETE FROM hashes WHERE path=?", [(g,) for g in gone])
            self.db.execute("COMMIT")
        return len(gone)

    # ── dir sizes ─────────────────────────────────────────────────────────────
    def dir_get(self, path):
        if not self.daemon_alive():
            return None
        r = self.db.execute("SELECT size,epoch FROM dirsizes WHERE path=?", (path,)).fetchone()
        if r and r[1] == self.epoch():
            return r[0]
        return None

    def dir_put_many(self, rows):
        """rows: (path,size,files).  Only stored while a daemon can invalidate them."""
        if not rows or not self.daemon_alive():
            return
        ep = self.epoch()
        self.db.execute("BEGIN")
        self.db.executemany("INSERT OR REPLACE INTO dirsizes(path,size,files,epoch) VALUES(?,?,?,?)",
                            [(p, s, f, ep) for p, s, f in rows])
        self.db.execute("COMMIT")

    def dir_invalidate(self, changed_paths, drop_below=()):
        """Delete cached sizes for every ancestor of each changed path, and for
        everything below each path in `drop_below` (deleted / moved folders)."""
        anc = set()
        for p in list(changed_paths) + list(drop_below):
            q = p
            while True:
                anc.add(q)
                nq = os.path.dirname(q)
                if nq == q:
                    break
                q = nq
        self.db.execute("BEGIN")
        if anc:
            self.db.executemany("DELETE FROM dirsizes WHERE path=?", [(a,) for a in anc])
        for d in drop_below:
            lo, hi = self._prefix_range(d)
            self.db.execute("DELETE FROM dirsizes WHERE path>=? AND path<?", (lo, hi))
            self.db.execute("DELETE FROM hashes  WHERE path>=? AND path<?", (lo, hi))
        self.db.execute("COMMIT")

    def stats(self):
        h = self.db.execute("SELECT COUNT(*) FROM hashes").fetchone()[0]
        d = self.db.execute("SELECT COUNT(*) FROM dirsizes").fetchone()[0]
        return {"hashes": h, "dirsizes": d, "epoch": self.epoch()}

    def close(self):
        try:
            self.db.close()
        except Exception:
            pass


def open_index():
    """Index or None (disabled / sqlite problem) — callers must handle None."""
    if not enabled():
        return None
    try:
        return Index()
    except Exception:
        return None


# ══════════════════════════════════════════════════════════════════════════════
#  Duplicate detection (size → head hash → full hash) with the cache
# ══════════════════════════════════════════════════════════════════════════════
def _sha1_file(path, limit=None):
    h = hashlib.sha1()
    try:
        with open(path, "rb") as fh:
            if limit:
                h.update(fh.read(limit))
            else:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    h.update(chunk)
    except OSError:
        return None
    return h.digest()


def dup_groups(files, idx=None, deadline=None, prefix=None):
    """files: iterable of (path, size, mtime_ns, ino, dev) for regular files.
    Returns a list of groups (each a list of paths with identical content).
    Uses and refreshes the hash cache when `idx` is given.  `prefix` is a
    folder that contains every file (saves computing it).  If `deadline`
    (time.time()) passes, hashing stops early and what is known so far is
    returned (used by the background warmer)."""
    by_size, seen = {}, set()
    for rec in files:
        path, size, mt, ino, dev = rec
        if size == 0:
            continue
        key = (dev, ino)
        if key in seen:                       # hard link to a file already counted
            continue
        seen.add(key)
        by_size.setdefault(size, []).append(rec)
    cands = [g for g in by_size.values() if len(g) > 1]
    if not cands:
        return []

    cache = {}
    if idx is not None:
        try:
            if prefix is None:
                flat = [r[0] for g in cands for r in g]
                prefix = os.path.commonpath(flat) if len(flat) > 1 else os.path.dirname(flat[0])
            cache = idx.hash_rows_under(prefix or "/")
        except Exception:
            cache = {}

    rows = {}                                  # path → [size, mt, ino, dev, head, full]
    dirty = set()                              # paths whose row gained a hash this run

    def row_for(rec):
        path = rec[0]
        r = rows.get(path)
        if r is None:
            c = cache.get(path)
            if c is not None and c[0] == rec[1] and c[1] == rec[2] and c[2] == rec[3] and c[3] == rec[4]:
                r = [rec[1], rec[2], rec[3], rec[4], c[4], c[5]]
            else:
                r = [rec[1], rec[2], rec[3], rec[4], None, None]
            rows[path] = r
        return r

    result = []
    stop = False
    for group in cands:
        by_head = {}
        for rec in group:
            if deadline and time.time() > deadline:
                stop = True
                break
            r = row_for(rec)
            if r[4] is None:
                r[4] = _sha1_file(rec[0], HEAD_BYTES)
                if r[4] is not None:
                    dirty.add(rec[0])
            if r[4] is not None:
                by_head.setdefault(r[4], []).append(rec)
        if stop:
            break
        for sub in by_head.values():
            if len(sub) < 2:
                continue
            by_full = {}
            for rec in sub:
                if deadline and time.time() > deadline:
                    stop = True
                    break
                r = row_for(rec)
                if r[5] is None:
                    r[5] = _sha1_file(rec[0])
                    if r[5] is not None:
                        dirty.add(rec[0])
                if r[5] is not None:
                    by_full.setdefault(r[5], []).append(rec[0])
            if stop:
                break
            result.extend(g for g in by_full.values() if len(g) > 1)
        if stop:
            break

    if idx is not None and dirty:
        try:
            idx.put_hashes([(p, *rows[p]) for p in dirty])
        except Exception:
            pass
    return result


# ══════════════════════════════════════════════════════════════════════════════
#  Folder sizes — ONE definition shared by the select engine and the warmer.
#  Matches os.walk semantics: symlinks to folders are not entered and not
#  counted; every other entry counts its lstat size.
# ══════════════════════════════════════════════════════════════════════════════
def tree_sizes(root):
    """Return {dir: (total_size, file_count)} for root and every folder below."""
    out = {}

    def rec(d):
        total = count = 0
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_dir():                       # follows symlinks, like os.walk
                            if e.is_symlink():
                                continue
                            s, c = rec(e.path)
                            total += s
                            count += c
                        else:
                            total += e.stat(follow_symlinks=False).st_size
                            count += 1
                    except OSError:
                        continue
        except OSError:
            pass
        out[d] = (total, count)
        return total, count

    rec(root.rstrip("/") or "/")
    return out


def dir_size(path, idx=None):
    """Recursive size of one folder, via the cache when it can be trusted."""
    path = path.rstrip("/") or "/"
    if idx is not None:
        try:
            hit = idx.dir_get(path)
            if hit is not None:
                return hit
        except Exception:
            pass
    sizes = tree_sizes(path)
    if idx is not None:
        try:
            idx.dir_put_many([(p, s, c) for p, (s, c) in sizes.items() if c >= DIR_CACHE_MIN_FILES])
        except Exception:
            pass
    return sizes[path][0]


# ══════════════════════════════════════════════════════════════════════════════
#  Hot roots (folders worth keeping warm)
# ══════════════════════════════════════════════════════════════════════════════
def register_hot(path, recursive):
    """Remember that .s.dup / big-folder sizes were asked for here, so the daemon
    keeps it warm.  Line format:  R|N <TAB> path"""
    try:
        INDEX_DIR.mkdir(parents=True, exist_ok=True)
        tag = "R" if recursive else "N"
        lines = []
        if HOT_FILE.exists():
            lines = [l.rstrip("\n") for l in HOT_FILE.read_text(errors="replace").splitlines() if l.strip()]
        entry = tag + "\t" + path
        if entry in lines:
            return
        lines = [l for l in lines if l.split("\t", 1)[-1] != path] + [entry]
        HOT_FILE.write_text("\n".join(lines[-HOT_MAX:]) + "\n")
    except OSError:
        pass


def read_roots(fav_dirs=()):
    """All folders the daemon should keep warm → list of (path, recursive)."""
    roots = {}
    if ROOTS_CONF.exists():
        for raw in ROOTS_CONF.read_text(errors="replace").splitlines():
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if line.endswith("  shallow") or line.endswith("\tshallow"):
                roots[line.rsplit(None, 1)[0].strip()] = False
            else:
                roots[line] = True
    if HOT_FILE.exists():
        for line in HOT_FILE.read_text(errors="replace").splitlines():
            if "\t" in line:
                tag, p = line.split("\t", 1)
                roots.setdefault(p, tag == "R")
    for d in fav_dirs:
        roots.setdefault(d, False)
    return [(p, r) for p, r in roots.items() if os.path.isdir(p)]


# ══════════════════════════════════════════════════════════════════════════════
#  Warmer (daemon): fill both caches for one root
# ══════════════════════════════════════════════════════════════════════════════
def warm_root(idx, root, recursive, budget=120.0, nap=0.002):
    """Walk `root` (non-hidden, like the select engine) and make the hash cache
    and folder-size cache current.  Returns a small stats dict."""
    t0 = time.time()
    deadline = t0 + budget
    files = []
    stack = [root.rstrip("/") or "/"]
    seen_dirs = 0
    while stack:
        d = stack.pop()
        seen_dirs += 1
        try:
            with os.scandir(d) as it:
                for e in it:
                    if e.name.startswith("."):
                        continue
                    try:
                        if e.is_dir(follow_symlinks=False):
                            if recursive:
                                stack.append(e.path)
                            continue
                        st = e.stat(follow_symlinks=False)
                        if statmod.S_ISREG(st.st_mode):
                            files.append((e.path, st.st_size, st.st_mtime_ns, st.st_ino, st.st_dev))
                    except OSError:
                        continue
        except OSError:
            continue
        if time.time() > deadline:
            break
        if nap:
            time.sleep(nap)
    groups = dup_groups(files, idx, deadline, prefix=root.rstrip("/") or "/")
    sized = 0
    if recursive and time.time() < deadline:
        try:
            sizes = tree_sizes(root)
            idx.dir_put_many([(p, s, c) for p, (s, c) in sizes.items() if c >= DIR_CACHE_MIN_FILES])
            sized = sum(1 for _, c in sizes.values() if c >= DIR_CACHE_MIN_FILES)
        except Exception:
            pass
    return {"root": root, "files": len(files), "dup_groups": len(groups),
            "dirs_cached": sized, "seconds": round(time.time() - t0, 2)}
