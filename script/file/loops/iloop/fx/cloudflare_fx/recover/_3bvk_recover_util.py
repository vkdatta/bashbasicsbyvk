"""_3bvk_recover_util - small helpers shared by every recover module (report log, safe paths)."""
import os
from pathlib import Path


class Report:
    """Per-worker report: every line is printed AND kept for RECOVERY-REPORT.txt (replaces the old global REPORT)."""
    def __init__(self):
        self.lines = []

    def say(self, msg):
        print(msg)
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

