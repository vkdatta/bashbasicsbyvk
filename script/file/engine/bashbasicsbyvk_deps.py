"""bashbasicsbyvk_deps - the python door to THE central dependency installer (bashbasicsbyvk_deps.sh + bashbasicsbyvk_deps.list, AGENTS.md rule 12).

    import bashbasicsbyvk_deps as deps
    if not deps.ensure("polyglot", "?rich", "tree_sitter_python", context="Polyglot"):    # ids / features; "?id" = optional
        sys.exit(1)

`ensure` runs the bash engine with the terminal handed through: if something is missing the person sees the Installer menu (list + yes/no),
the installs run in parallel, and afterwards this process can import the new packages at once.  Nothing here installs anything itself:
there is no pip recipe, sentinel or package table in python any more - they all live in the registry / the engine.

    ensure(*ids, context="", optional=False, yes=False, check_only=False, quiet=False) -> bool
    have(module, dist=None, min_version=None) -> bool            is the module importable (and that distribution new enough)
    refresh_import_paths()                                       user site-packages + ~/.local/bin visible to this process right after an install
"""
import importlib
import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

CLI_NAME = "bashbasicsbyvk_deps.sh"


def _cli():
    here = Path(__file__).resolve().parent / CLI_NAME
    if here.is_file():
        return str(here)
    return shutil.which(CLI_NAME)


def refresh_import_paths():
    """Make a fresh `pip install --user` importable at once, and ~/.local/bin (user-space installs) findable."""
    try:
        import site
        try:
            site.addsitedir(site.getusersitepackages())
        except Exception:
            pass
        importlib.invalidate_caches()
    except Exception:
        pass
    local_bin = str(Path.home() / ".local" / "bin")
    if os.path.isdir(local_bin) and local_bin not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = os.environ.get("PATH", "") + os.pathsep + local_bin


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


def ensure(*ids, context="", optional=False, yes=False, check_only=False, quiet=False):
    """True when everything REQUIRED in `ids` is installed afterwards (the Installer menu is shown first when something is missing)."""
    cli = _cli()
    if cli is None:
        print(f"❌ {CLI_NAME} was not found next to this tool - reinstall bashbasicsbyvk.", file=sys.stderr)
        return False
    cmd = ["bash", cli]
    if context:
        cmd += ["-c", context]
    if optional:
        cmd.append("-o")
    if yes:
        cmd.append("-y")
    if check_only:
        cmd.append("-n")
    if quiet:
        cmd.append("-q")
    cmd += list(ids)
    try:
        if quiet:
            rc = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        else:
            rc = subprocess.run(cmd).returncode
    except OSError as e:
        print(f"❌ could not run {CLI_NAME}: {e}", file=sys.stderr)
        return False
    refresh_import_paths()
    return rc == 0
