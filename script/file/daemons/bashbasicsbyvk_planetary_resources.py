"""
bashbasicsbyvk_planetary_resources (python flavour) - the ONE helper both daemons consume.

  local daemon  (bashbasicsbyvk_local_daemon, python)    keeps every pointer at a path attached to the path
  alien daemon  (bashbasicsbyvk_alien_daemon.sh, bash)   takes snapshots while  o  runs
The bash flavour of this file is bashbasicsbyvk_planetary_resources.sh (same rules, same file formats); the versions both
daemons report live ONLY in bashbasicsbyvk_planetary_versions.list.

What lives here (so it exists once):
  find_file / daemon_version   locate a sibling file by name, read a daemon's version from the single list
  norm / stat_id / map_path    path helpers every registry uses
  write_atomic                 temp file + replace
  dir_lock                     the mkdir lock: owner pid inside, stale / dead-owner takeover, NEVER silently taken while its owner lives
  find_inodes                  the one directory walk that finds moved items by inode (bookmarks, favourites, locks ... all use it)
  pid_alive                    "is this pid alive AND really ours" (a recycled pid does not count)
  Service                      single-instance (flock), pid / version / status / log files, log trim, graceful stop
  ensure_bashrc_hook / install_systemd / remove_legacy   how a daemon is kept running (Termux hook, systemd user unit)
"""
import fcntl
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

HOME = Path.home()
BVK_DIR = Path(os.environ.get("BVK_HOME_DIR") or (HOME / ".bashbasicsbyvk"))
DAEMONS_DIR = BVK_DIR / "daemons"          # pid / log / version / status / instance lock of the daemons that run as their own process
VERSIONS_FILE = "bashbasicsbyvk_planetary_versions.list"


# ══════════════════════════ finding files and versions ══════════════════════════
_FOUND = {}


def find_file(name):
    """Path of a script file by NAME: next to this file (flat install), on PATH, then anywhere below script/file (repo layout)."""
    if name in _FOUND:
        return _FOUND[name]
    here = Path(os.path.realpath(__file__)).parent
    hit = None
    for d in [here] + [Path(p) for p in os.environ.get("PATH", "").split(os.pathsep) if p]:
        f = d / name
        if f.is_file():
            hit = str(f)
            break
    if hit is None:
        for anc in [here] + list(here.parents)[:4]:
            if anc.name == "file":
                for root, _dirs, files in os.walk(anc):
                    if name in files:
                        hit = os.path.join(root, name)
                        break
                break
    _FOUND[name] = hit
    return hit


def load_module(name):
    """Import bashbasicsbyvk_*.py by file name (flat install or repo layout). None when it is not there."""
    path = find_file(name + ".py")
    if not path:
        return None
    import importlib.util
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def daemon_version(name):
    """The version of a daemon ('local' / 'alien') from bashbasicsbyvk_planetary_versions.list; 0 when the list is not found."""
    path = find_file(VERSIONS_FILE)
    try:
        for ln in Path(path).read_text().splitlines():
            k, _, v = ln.partition("=")
            if k.strip() == name and v.strip().isdigit():
                return int(v.strip())
    except (OSError, TypeError):
        pass
    return 0


# ══════════════════════════ paths ══════════════════════════
def norm(p):
    p = str(p)
    if len(p) > 1:
        p = p.rstrip("/")
    return p or "/"


def stat_id(path):
    try:
        st = os.lstat(path)
        return "%d:%d" % (st.st_dev, st.st_ino)
    except OSError:
        return ""


def map_path(p, src, dest):
    """src -> dest for the path itself or anything below it; None when p is unrelated."""
    if p == src:
        return dest
    if p.startswith(src + "/"):
        return dest + p[len(src):]
    return None


def write_atomic(path, text):
    tmp = Path(str(path) + ".%d.tmp" % os.getpid())
    try:
        tmp.write_text(text)
        os.replace(tmp, path)
        return True
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass
        return False


def app_dirs():
    """The app's own state / cache folders: events below them are never a user's move (snapshot copies, our own files)."""
    cfg = Path(os.environ.get("XDG_CONFIG_HOME") or (HOME / ".config"))
    cache = Path(os.environ.get("XDG_CACHE_HOME") or (HOME / ".cache"))
    return tuple(str(p) for p in (BVK_DIR, cfg / "bashbasicsbyvk", cache / "bashbasicsbyvk"))


# ══════════════════════════ the lock ══════════════════════════
def pid_alive(pid, marker=None):
    """True when `pid` is a live process (not a zombie) and, if `marker` is given and can be read, its command line holds it."""
    try:
        pid = int(pid)
        if pid <= 0:
            return False
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except (ValueError, OSError):
        pass                                           # PermissionError: it exists
    try:
        stat = Path("/proc/%d/stat" % pid).read_text()
        if stat.rsplit(")", 1)[-1].split()[0] == "Z":
            return False
    except (OSError, IndexError):
        pass
    if marker:
        cmd = None
        try:
            cmd = Path("/proc/%d/cmdline" % pid).read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
        except OSError:
            try:
                cmd = subprocess.run(["ps", "-p", str(pid), "-o", "args="], capture_output=True, timeout=3).stdout.decode("utf-8", "replace")
            except Exception:
                cmd = None
        if cmd is not None and marker not in cmd:
            return False                               # the pid was recycled by some other program
    return True


def _lock_stale(lockdir, stale):
    try:
        age = time.time() - os.stat(lockdir).st_mtime
    except OSError:
        return False
    try:
        pid = int(Path(lockdir, "pid").read_text().split()[0])
    except (OSError, ValueError, IndexError):
        pid = None
    if pid is not None and not pid_alive(pid):
        return True                                    # the owner died holding it
    return age > stale


def _break_lock(lockdir):
    """Remove a stale lock. The rename is atomic: of several breakers exactly one wins."""
    dead = "%s.dead.%d.%d" % (lockdir, os.getpid(), time.time_ns())
    try:
        os.rename(lockdir, dead)
    except OSError:
        return
    shutil.rmtree(dead, ignore_errors=True)


@contextmanager
def dir_lock(lockdir, wait=3.0, stale=10.0):
    """mkdir lock with the owner's pid inside. Yields True when this caller owns it.

    A lock is taken over only when its owner is dead or it is older than `stale` seconds; a live owner is waited for up to `wait`
    seconds and then the caller goes on WITHOUT the lock (yield False) and never removes a lock it does not own.
    The bash side (_pr_lock in bashbasicsbyvk_planetary_resources.sh) uses the same directory layout."""
    lockdir = str(lockdir)
    got = False
    try:
        os.makedirs(os.path.dirname(lockdir), exist_ok=True)
    except OSError:
        pass
    deadline = time.time() + wait
    while True:
        try:
            os.mkdir(lockdir)
            got = True
            break
        except FileExistsError:
            if _lock_stale(lockdir, stale):
                _break_lock(lockdir)
                continue
            if time.time() > deadline:
                break
            time.sleep(0.05)
        except OSError:
            break
    if got:
        try:
            Path(lockdir, "pid").write_text("%d\n" % os.getpid())
        except OSError:
            pass
    try:
        yield got
    finally:
        if got:
            shutil.rmtree(lockdir, ignore_errors=True)


# ══════════════════════════ the one inode walk ══════════════════════════
def find_inodes(roots, wanted, budget=30.0, skip=None, dirs_only=False):
    """Walk `roots` once (hidden names skipped, like the select engine) and find the items whose "dev:inode" is in `wanted`
    (a set). Returns {id: path}. Stops at the time `budget` or when everything is found. `skip(path)` prunes a folder."""
    want = {}
    for i in wanted:
        try:
            want.setdefault(int(i.partition(":")[2]), set()).add(i)
        except ValueError:
            pass
    found = {}
    deadline = time.time() + budget
    stack = [str(r) for r in roots]
    while stack and want and time.time() < deadline:
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
                    ids = want.get(e.inode())
                    if ids and (isdir or not dirs_only):
                        sid = stat_id(e.path)
                        if sid in ids:
                            found[sid] = e.path
                            ids.discard(sid)
                            if not ids:
                                want.pop(e.inode(), None)
                    if isdir and not (skip and skip(e.path)):
                        stack.append(e.path)
        except OSError:
            continue
    return found


# ══════════════════════════ time zone (a daemon outlives the app) ══════════════════════════
_TZ_SEEN = [None]
_ORIG_TZ = [os.environ.get("TZ")]


def apply_app_timezone():
    """Follow Settings > Timezone (app_timezone in the config file): re-read it whenever it changes."""
    cfg = Path(os.environ.get("XDG_CONFIG_HOME") or (HOME / ".config")) / "bashbasicsbyvk" / "config"
    try:
        st = cfg.stat()
        sig = (st.st_mtime_ns, st.st_size)
    except OSError:
        sig = None
    if sig == _TZ_SEEN[0]:
        return
    _TZ_SEEN[0] = sig
    zone = ""
    if sig:
        try:
            for line in cfg.read_text(errors="replace").splitlines():
                if line.startswith("app_timezone="):
                    zone = line.split("=", 1)[1].strip().strip('"').strip("'")
        except OSError:
            pass
    try:
        fx = re.fullmatch(r"UTC([+-])(\d{2}):(\d{2})", zone)
        if fx:                                         # fixed offset (no tz database on this machine)
            hh, mm = int(fx.group(2)), fx.group(3)
            if hh == 0 and mm == "00":
                os.environ["TZ"] = "UTC0"
            else:
                inv = "-" if fx.group(1) == "+" else "+"
                os.environ["TZ"] = "<%s%02d%s>%s%d:%s" % (fx.group(1), hh, mm, inv, hh, mm)
        elif zone and re.fullmatch(r"[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}", zone):
            import zoneinfo
            zoneinfo.ZoneInfo(zone)                    # must exist, else keep the system zone
            os.environ["TZ"] = zone
        elif _ORIG_TZ[0] is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = _ORIG_TZ[0]
        time.tzset()
    except Exception:
        pass


# ══════════════════════════ a daemon's own files ══════════════════════════
LOG_MAX_LINES = 1000
LOG_KEEP_LINES = 600


class Service:
    """The lifecycle files of one daemon under ~/.bashbasicsbyvk/daemons/: <name>.pid .log .version .status .instance (flock)."""

    def __init__(self, name, marker, legacy_pid_files=()):
        self.name = name
        self.marker = marker                           # a string the daemon's command line always holds
        self.pid_file = DAEMONS_DIR / (name + ".pid")
        self.log_file = DAEMONS_DIR / (name + ".log")
        self.version_file = DAEMONS_DIR / (name + ".version")
        self.status_file = DAEMONS_DIR / (name + ".status")
        self.instance_file = DAEMONS_DIR / (name + ".instance")
        self.legacy_pid_files = [Path(p) for p in legacy_pid_files]
        self._instance_fd = None
        self._log_writes = 0

    # -- single instance: the flock is held for the life of the process, so two shells that start it at once cannot both win --
    def acquire_instance(self):
        try:
            DAEMONS_DIR.mkdir(parents=True, exist_ok=True)
            fd = os.open(self.instance_file, os.O_RDWR | os.O_CREAT, 0o600)
        except OSError:
            return True                                # cannot tell: run
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return False
        self._instance_fd = fd
        try:
            os.ftruncate(fd, 0)
            os.write(fd, ("%d\n" % os.getpid()).encode())
        except OSError:
            pass
        return True

    def write_pid(self, pid=None):
        try:
            DAEMONS_DIR.mkdir(parents=True, exist_ok=True)
            self.pid_file.write_text("%d\n" % (pid or os.getpid()))
        except OSError:
            pass

    def remove_pid(self):
        """Remove the pid file only when it is OUR pid (a replaced daemon must not delete its successor's file)."""
        try:
            if int(self.pid_file.read_text().split()[0]) == os.getpid():
                self.pid_file.unlink()
        except (OSError, ValueError, IndexError):
            pass

    def read_pid(self, path=None):
        try:
            return int(Path(path or self.pid_file).read_text().split()[0])
        except (OSError, ValueError, IndexError):
            return 0

    def is_alive(self):
        """Alive AND really this daemon: a pid that was recycled by another program does not count."""
        for f in [self.pid_file] + self.legacy_pid_files:
            pid = self.read_pid(f)
            if pid and pid != os.getpid() and pid_alive(pid, self.marker):
                return True
        return False

    def running_version(self):
        try:
            return self.version_file.read_text().strip()
        except OSError:
            return ""

    def write_version(self, version):
        try:
            DAEMONS_DIR.mkdir(parents=True, exist_ok=True)
            self.version_file.write_text(str(version) + "\n")
        except OSError:
            pass

    def write_status(self, doc):
        try:
            DAEMONS_DIR.mkdir(parents=True, exist_ok=True)
            tmp = self.status_file.with_suffix(".tmp")
            tmp.write_text(json.dumps(doc))
            os.replace(tmp, self.status_file)
        except (OSError, TypeError, ValueError):
            pass

    def log(self, msg):
        try:
            apply_app_timezone()
            DAEMONS_DIR.mkdir(parents=True, exist_ok=True)
            with open(self.log_file, "a") as f:
                f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S %Z"), msg))
            self._log_writes += 1
            if self._log_writes % 50 == 1:
                self.trim_log()
        except OSError:
            pass

    def trim_log(self):
        try:
            lines = self.log_file.read_text(errors="replace").splitlines()
            if len(lines) > LOG_MAX_LINES:
                write_atomic(self.log_file, "\n".join(lines[-LOG_KEEP_LINES:]) + "\n")
        except OSError:
            pass

    def stop_running(self, timeout=8.0):
        """TERM every live copy (current and legacy pid files), wait until it is gone, KILL what ignores it. True when none is left."""
        pids = {self.read_pid(f) for f in [self.pid_file] + self.legacy_pid_files}
        pids = {p for p in pids if p and p != os.getpid() and pid_alive(p, self.marker)}
        for p in pids:
            try:
                os.kill(p, signal.SIGTERM)
            except OSError:
                pass
        deadline = time.time() + timeout
        while pids and time.time() < deadline:
            pids = {p for p in pids if pid_alive(p, self.marker)}
            if pids:
                time.sleep(0.1)
        for p in pids:
            try:
                os.kill(p, signal.SIGKILL)
            except OSError:
                pass
        for f in self.legacy_pid_files:
            try:
                f.unlink()
            except OSError:
                pass
        return not pids


# ══════════════════════════ keeping a daemon running ══════════════════════════
def has_systemd_user():
    try:
        r = subprocess.run(["systemctl", "--user", "is-system-running"], capture_output=True, timeout=3)
        return r.returncode in (0, 1) and r.stdout.decode().strip() in ("running", "degraded")
    except Exception:
        return False


def is_termux():
    return "com.termux" in str(HOME) or os.environ.get("TERMUX_VERSION") is not None


def _systemd_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME") or (HOME / ".config")) / "systemd" / "user"


def install_systemd(service, description, script, extra_args=("--daemon",)):
    unit = _systemd_dir() / (service + ".service")
    try:
        unit.parent.mkdir(parents=True, exist_ok=True)
        cmd = " ".join(shlex.quote(a) for a in [sys.executable, str(script)] + list(extra_args))
        unit.write_text("[Unit]\nDescription=%s\nAfter=default.target\n\n[Service]\nType=simple\nExecStart=%s\n"
                        "Restart=on-failure\nRestartSec=5\n\n[Install]\nWantedBy=default.target\n" % (description, cmd))
        for step in (["daemon-reload"], ["enable", service], ["restart", service]):
            subprocess.run(["systemctl", "--user"] + step, timeout=10)
        return True
    except Exception:
        return False


def remove_legacy_systemd(service):
    """A unit of an older name: stop, disable, delete."""
    unit = _systemd_dir() / (service + ".service")
    if not unit.exists():
        return
    try:
        subprocess.run(["systemctl", "--user", "disable", "--now", service], capture_output=True, timeout=10)
        unit.unlink()
        subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True, timeout=10)
    except Exception:
        pass


def ensure_bashrc_hook(marker, script, legacy_markers=()):
    """Termux: make ~/.bashrc wake the daemon at every shell. Idempotent. The hook line is
    `( <python> '<script>' </dev/null >/dev/null 2>&1 & disown )` under a marker comment; only a line that IS such a hook
    (it names the daemon script) is replaced, a user's own line after a marker is never touched."""
    bashrc = HOME / ".bashrc"
    new_line = "( %s %s </dev/null >/dev/null 2>&1 & disown )" % (shlex.quote(sys.executable), shlex.quote(str(script)))
    try:
        lines = bashrc.read_text().splitlines() if bashrc.exists() else []
    except OSError:
        return
    base = os.path.basename(str(script))
    all_markers = {marker, *legacy_markers}
    for i in range(len(lines) - 1):
        if lines[i].strip() == marker and lines[i + 1] == new_line:
            if not any(ln.strip() in legacy_markers for ln in lines):
                return
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if ln.strip() in all_markers:
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            if "disown" in nxt and ("daemon" in nxt or base in nxt):
                i += 2                                 # our old hook (marker + its line)
            else:
                i += 1                                 # a marker with something else after it: drop only the marker
            continue
        out.append(ln)
        i += 1
    out += [marker, new_line]
    try:
        bashrc.write_text("\n".join(out) + "\n")
    except OSError:
        pass
