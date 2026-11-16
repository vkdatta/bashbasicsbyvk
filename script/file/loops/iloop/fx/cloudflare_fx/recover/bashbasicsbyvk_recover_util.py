"""bashbasicsbyvk_recover_util - small helpers shared by every recover module (report log, safe paths, the concurrent batch runner)."""
import os, re, threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

NAME_OK = re.compile(r"[A-Za-z0-9_-]+")
JOBS = max(1, int(os.environ.get("BVK_RECOVER_JOBS", "6") or 6))     # items recovered at the same time


class Report:
    """Per-item report: every line is printed AND kept for RECOVERY-REPORT.txt.
    `label` (e.g. "Pages delluna") prefixes every printed line so several items can run in parallel threads and
    their output stays readable; a shared lock keeps lines whole."""
    _lock = threading.Lock()

    def __init__(self, label=None):
        self.lines = []
        self.label = label

    def echo(self, msg):
        """Print only (not kept in the report) - for per-file progress."""
        with Report._lock:
            for ln in str(msg).split("\n"):
                print(f"[{self.label}] {ln}" if self.label else ln, flush=True)

    def say(self, msg):
        self.echo(msg)
        self.lines.append(msg)

    def text(self):
        return "\n".join(self.lines) + "\n"


class RecoverError(Exception):
    """A recoverable failure for ONE worker (the batch carries on with the next one)."""


def relimport(frm, to):
    r = os.path.relpath(to, str(Path(frm).parent))
    return (r if r.startswith(".") else "./" + r).replace(os.sep, "/")


def safe_join(root, rel):
    root = root.resolve(); dest = (root / rel).resolve()
    if root != dest and root not in dest.parents: raise ValueError(f"refusing to write outside output dir: {rel}")
    return dest


def progress(futs, labels, status_of):
    """Live line each time an item finishes: [k/N] icon label."""
    icon = {"ok": "💫", "skipped": "⏭️", "failed": "❌"}
    idx = {f: i for i, f in enumerate(futs)}
    for k, f in enumerate(as_completed(futs), 1):
        Report(None).echo(f"── [{k}/{len(futs)}] {icon.get(status_of(f.result()), '')} {labels[idx[f]]}")


def run_pool(noun, tasks, labels, status_of):
    """Run the zero-argument `tasks` concurrently (JOBS at a time); results keep the order of `tasks`."""
    print(f"\nRecovering {len(tasks)} {noun}(s), up to {JOBS} at the same time...", flush=True)
    with ThreadPoolExecutor(max_workers=min(JOBS, len(tasks))) as ex:
        futs = [ex.submit(t) for t in tasks]
        progress(futs, labels, status_of)
        return [f.result() for f in futs]

