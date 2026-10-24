"""bashbasicsbyvk_pipboot - the ONE self-install helper: a one-shot, sentinel-guarded `pip install` of a missing Python package.

Used by bashbasicsbyvk_recents_daemon (watchdog) and bashbasicsbyvk_polyglot (numpy, rich, openpyxl, tree-sitter + grammars).
The recipe is the daemon's: plain `--user` first, then `--user --break-system-packages` (PEP 668 / Termux; inside a venv plain `pip install`
instead, because `--user` is refused there).  A sentinel file records the last attempt, so a failing install is not retried before
`retry` seconds.  After an install the caller re-imports; refresh_import_paths() makes a fresh `--user` install importable at once.
"""
import importlib
import importlib.util
import subprocess
import sys
import time


def _attempts():
    return ([],) if sys.prefix != sys.base_prefix else (["--user"], ["--user", "--break-system-packages"])


def refresh_import_paths():
    """Put user site-packages on sys.path and invalidate import caches (needed right after a fresh `pip install --user`)."""
    try:
        import site
        try:
            site.addsitedir(site.getusersitepackages())
        except Exception:
            pass
        importlib.invalidate_caches()
    except Exception:
        pass


def _version_tuple(text):
    out = []
    for part in text.split("."):
        digits = "".join(c for c in part if c.isdigit())
        if not digits:
            break
        out.append(int(digits))
    return tuple(out)


def have(module, dist=None, min_version=None):
    """True if `module` is importable (and, when `dist` + `min_version` are given, that distribution is at least that version)."""
    refresh_import_paths()
    try:
        if importlib.util.find_spec(module) is None:
            return False
    except (ImportError, ValueError):
        return False
    if dist and min_version:
        try:
            from importlib import metadata
            return _version_tuple(metadata.version(dist)) >= tuple(min_version)
        except Exception:
            return False
    return True


def retry_due(sentinel, retry):
    """True when no attempt is recorded in `sentinel` (a Path) or the last one is older than `retry` seconds."""
    if not sentinel.exists():
        return True
    try:
        return time.time() - sentinel.stat().st_mtime > retry
    except OSError:
        return True


def run_pip(args, log, timeout):
    """`python -m pip install --no-input ... <args>`; returns the exit code (124 on timeout, 1 on any other failure to run)."""
    cmd = [sys.executable, "-m", "pip", "install", "--no-input", "--disable-pip-version-check"] + args
    log(f"pip: {' '.join(cmd)}")
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=timeout)
        out = proc.stdout.decode(errors="replace").strip()
        err = proc.stderr.decode(errors="replace").strip()
        if out:
            log(f"pip stdout tail: {out[-500:]}")
        if err:
            log(f"pip stderr tail: {err[-500:]}")
        return proc.returncode
    except subprocess.TimeoutExpired:
        log(f"pip install timed out after {timeout}s")
        return 124
    except Exception as e:
        log(f"pip install raised {type(e).__name__}: {e}")
        return 1


def install(spec, sentinel, log, timeout=120):
    """One-shot install of `spec` ("watchdog", "tree-sitter>=0.23", a wheel path ...); records the outcome in `sentinel` (a Path).
    Returns True when pip succeeded.  The caller checks that the module really imports (have())."""
    success = False
    for flags in _attempts():
        rc = run_pip(flags + [spec], log, timeout)
        if rc == 0:
            success = True
            log(f"pip install {spec} succeeded")
            break
        log(f"pip attempt rc={rc} (args={flags + [spec]})")
    try:
        sentinel.parent.mkdir(parents=True, exist_ok=True)
        sentinel.write_text(f"{time.strftime('%Y-%m-%d %H:%M:%S %Z')} {'ok' if success else 'failed'}\n")
    except OSError:
        pass
    return success
