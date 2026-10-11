"""_3bvk_recover_util - small helpers shared by every recover module (report log, safe paths)."""
import os, threading
from pathlib import Path


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

