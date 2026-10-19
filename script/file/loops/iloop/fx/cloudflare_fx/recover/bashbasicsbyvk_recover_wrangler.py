"""bashbasicsbyvk_recover_wrangler - the worker's REAL wrangler config, taken from `wrangler init --from-dash <worker>`.

Why: the Cloudflare REST API only returns parsed settings, so a wrangler file rebuilt from it loses routes, cron
triggers, custom domains, migrations ... `wrangler init --from-dash` knows how to produce all of that.

What it costs, and how that is avoided
  `wrangler init` is a project scaffolder: next to the wrangler file it also writes package.json / tsconfig / .git and
  RUNS `npm install` (wrangler + ~hundreds of MB of dependencies = the "node_modules" that doubled network + storage).
  So here:
    * it runs in a THROWAWAY temp folder that is deleted afterwards - only the wrangler config file is read back;
    * npm / pnpm / yarn / bun are replaced by no-op stubs on that one process's PATH, so nothing is ever installed
      (the install step "succeeds" instantly and downloads nothing);
    * wrangler itself is located once (an installed `wrangler`, else `npx`) and warmed up once per run under a lock,
      so parallel workers never download it N times or race on the npx cache.
  Nothing from the scaffold (src/, package.json, package-lock.json, node_modules, .git) ever reaches the recovered folder.

Secrets: the API token / account id go to wrangler through its ENVIRONMENT only (never on a command line, never in a file).
Any failure raises WranglerError; the caller then falls back to the (lossy) config rebuilt from the REST API.

    BVK_RECOVER_WRANGLER=0     disable this step completely (always rebuild from the REST API)
    BVK_WRANGLER="cmd args"    use this wrangler command instead of `wrangler` / `npx wrangler`
    BVK_WRANGLER_TIMEOUT=SEC   per-worker timeout (default 240)
"""
import json, os, re, shlex, shutil, stat, subprocess, tempfile, threading
from pathlib import Path
from bashbasicsbyvk_recover_project import WRANGLER_FILES, read_wrangler

TIMEOUT = max(30, int(os.environ.get("BVK_WRANGLER_TIMEOUT", "240") or 240))
WARMUP_TIMEOUT = 900                                   # first npx run has to download wrangler once
STUBBED = ("npm", "pnpm", "yarn", "bun")   # package managers that must never install anything here
_STUB = """#!/bin/sh
# bashbasicsbyvk: no-op package manager - `wrangler init` must not install anything.
case "$1" in --version|-v|-V|version) echo "10.9.0" ;; esac
exit 0
"""

_lock = threading.Lock()
_resolved = {"done": False, "cmd": None, "err": None}


class WranglerError(Exception):
    """wrangler could not give a config for this worker (caller falls back to the REST-API rebuild)."""


def enabled():
    return os.environ.get("BVK_RECOVER_WRANGLER", "1").strip().lower() not in ("0", "false", "no", "off")


def _run(cmd, env, cwd, timeout):
    return subprocess.run(cmd, env=env, cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, timeout=timeout, text=True, errors="replace")


def _base_env():
    env = dict(os.environ)
    env.update({"CI": "1", "NO_COLOR": "1", "FORCE_COLOR": "0",
                "WRANGLER_SEND_METRICS": "false", "CREATE_CLOUDFLARE_TELEMETRY_DISABLED": "1",
                "npm_config_update_notifier": "false", "npm_config_fund": "false", "npm_config_audit": "false"})
    return env


def _wrangler_command():
    """The command (list) that runs wrangler; resolved + warmed up ONCE per process, thread-safe."""
    with _lock:
        if _resolved["done"]:
            if _resolved["cmd"]: return _resolved["cmd"]
            raise WranglerError(_resolved["err"])
        _resolved["done"] = True
        try:
            custom = os.environ.get("BVK_WRANGLER", "").strip()
            if custom:
                cmd = shlex.split(custom)
            elif shutil.which("wrangler"):
                cmd = [shutil.which("wrangler")]
            elif shutil.which("npx"):
                cmd = [shutil.which("npx"), "--yes", "--prefer-offline", "wrangler"]
            else:
                raise WranglerError("neither `wrangler` nor `npx` (Node.js) is installed")
            # warm-up: proves the command works and, for npx, downloads wrangler ONCE (not once per worker)
            warm = [c for c in cmd if c != "--prefer-offline"] + ["--version"]
            try:
                r = _run(warm, _base_env(), tempfile.gettempdir(), WARMUP_TIMEOUT)
            except (OSError, subprocess.TimeoutExpired) as e:
                raise WranglerError(f"could not start wrangler: {type(e).__name__}: {e}")
            if r.returncode != 0:
                raise WranglerError("wrangler --version failed: " + _tail(r.stdout))
            _resolved["cmd"] = cmd
            return cmd
        except WranglerError as e:
            _resolved["err"] = str(e)
            raise


def _tail(text, n=3):
    lines = [l.strip() for l in (text or "").strip().splitlines() if l.strip()]
    return " | ".join(lines[-n:]) or "(no output)"


def _make_stubs(folder):
    for name in STUBBED:
        p = Path(folder, name)
        p.write_text(_STUB)
        p.chmod(p.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _find_config(tmp, worker):
    """The wrangler file wrangler init wrote: <tmp>/<worker>/ first, then <tmp>/, then one folder level down."""
    tmp = Path(tmp)
    dirs = [tmp / worker, tmp] + sorted(d for d in tmp.iterdir() if d.is_dir() and d.name not in ("node_modules", ".git"))
    for d in dirs:
        for f in WRANGLER_FILES:
            if (d / f).is_file(): return d / f
    return None


def config_from_dash(worker, token, account):
    """Run `wrangler init --from-dash <worker>` in a throwaway folder. Returns (filename, bytes). Raises WranglerError."""
    cmd = _wrangler_command()
    env = _base_env()
    env["CLOUDFLARE_API_TOKEN"] = token
    env["CLOUDFLARE_ACCOUNT_ID"] = account
    tmp = tempfile.mkdtemp(prefix="bvk-wrangler-")
    try:
        stubs = Path(tmp, ".stubs"); stubs.mkdir()
        _make_stubs(stubs)
        env["PATH"] = str(stubs) + os.pathsep + env.get("PATH", "")
        work = Path(tmp, "w"); work.mkdir()
        args = ["init", "--from-dash", worker, "-y"]
        # --no-delegate-c3: use wrangler's own (plain) init instead of create-cloudflare, which would also fetch itself
        tries = [args + ["--no-delegate-c3"], args]          # older/newer wrangler may not know the flag -> retry without
        r = None
        for a in tries:
            try:
                r = _run(cmd + a, env, str(work), TIMEOUT)
            except subprocess.TimeoutExpired:
                raise WranglerError(f"wrangler init timed out after {TIMEOUT}s")
            except OSError as e:
                raise WranglerError(f"could not start wrangler: {e}")
            if r.returncode == 0 or not re.search(r"unknown argument|unrecognized|not a valid option", r.stdout or "", re.I):
                break
        found = _find_config(work, worker)
        if found is None:
            if r.returncode != 0:
                raise WranglerError(f"wrangler init failed (exit {r.returncode}): {_tail(r.stdout)}")
            raise WranglerError("wrangler init finished but wrote no wrangler.jsonc / wrangler.json / wrangler.toml")
        data = found.read_bytes()
        if not data.strip():
            raise WranglerError(f"wrangler init wrote an empty {found.name}")
        if not found.name.endswith(".toml") and not read_wrangler(found):
            raise WranglerError(f"wrangler init wrote an unreadable {found.name}")
        return found.name, data
    finally:
        shutil.rmtree(tmp, ignore_errors=True)               # scaffold (and any stray node_modules) is gone


def set_main(filename, data, main):
    """Point the config's top-level `main` at the recovered entry file, changing nothing else (comments/format kept).
    Returns (bytes, changed)."""
    text = data.decode("utf-8", "surrogateescape")      # byte-faithful round trip
    if filename.endswith(".toml"):
        m = re.search(r"(?m)^\[", text)                      # top-level keys live before the first [table]
        head, tail = (text[:m.start()], text[m.start():]) if m else (text, "")
        new, n = re.subn(r'(?m)^(\s*main\s*=\s*)(["\'])[^"\']*\2', lambda x: f'{x.group(1)}"{main}"', head, count=1)
        text = new + tail
    else:
        text, n = re.subn(r'("main"\s*:\s*)"[^"]*"', lambda x: f'{x.group(1)}"{main}"', text, count=1)
    return text.encode("utf-8", "surrogateescape"), bool(n)
