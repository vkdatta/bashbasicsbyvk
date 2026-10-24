"""Recursive, ignore-aware project crawler."""
from __future__ import annotations

import fnmatch
import os
from pathlib import Path
from typing import Iterator, Optional, Sequence

from bashbasicsbyvk_polyglot_languages import EXT_TO_LANG, SHEBANG_LANGS

IGNORE_DIRS = frozenset({
    ".git", ".hg", ".svn", "node_modules", "venv", ".venv", "env", ".env", "__pycache__",
    "build", "dist", "target", "out", ".idea", ".vscode", ".tox", ".mypy_cache",
    ".pytest_cache", ".ruff_cache", ".next", ".nuxt", "coverage", "vendor", "bower_components",
    "site-packages", ".gradle", ".cache", "obj", "bin", ".eggs", "htmlcov", ".terraform",
})
IGNORE_FILE_GLOBS = ("*.min.js", "*.min.css", "*.bundle.js", "*.chunk.js", "*.map",
                     "*.pb.go", "*_pb2.py", "*.generated.*", "package-lock.json")


def looks_minified(sample: str) -> bool:
    lines = sample.splitlines() or [""]
    avg = sum(len(l) for l in lines) / len(lines)
    return avg > 300 or max(len(l) for l in lines) > 5000


def read_text(path: Path, max_bytes: int) -> Optional[str]:
    """Read a source file; None if it is too large, binary or minified."""
    try:
        if path.stat().st_size > max_bytes:
            return None
        data = path.read_bytes()
    except OSError:
        return None
    if b"\x00" in data[:4096]:
        return None
    text = data.decode("utf-8", errors="replace")
    if looks_minified(text[:20000]):
        return None
    return text


def sniff_shebang(path: Path) -> Optional[str]:
    """Language of an extensionless script from its `#!` line (e.g. `#!/usr/bin/env bash`), else None."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(160)
    except OSError:
        return None
    if not head.startswith(b"#!"):
        return None
    line = head.split(b"\n", 1)[0].decode("utf-8", errors="replace").lower()
    for lang, needles in SHEBANG_LANGS:
        if any(n in line for n in needles):
            return lang
    return None


def crawl(root: Path, excludes: Sequence[str] = (), languages: Optional[Sequence[str]] = None,
          ) -> Iterator[tuple]:
    """Yield (absolute_path, language_name) for every supported source file."""
    wanted = set(languages) if languages else None
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = Path(dirpath).relative_to(root)
        dirnames[:] = sorted(
            d for d in dirnames
            if d not in IGNORE_DIRS
            and not d.endswith(".egg-info")
            and not any(fnmatch.fnmatch((rel_dir / d).as_posix(), p) or fnmatch.fnmatch(d, p) for p in excludes)
        )
        for fn in sorted(filenames):
            ext = os.path.splitext(fn)[1].lower()
            lang = EXT_TO_LANG.get(ext)
            if lang is None and not ext and not fn.startswith("."):      # extensionless: look at the shebang
                lang = sniff_shebang(Path(dirpath) / fn)
            if lang is None or (wanted and lang not in wanted):
                continue
            rel = (rel_dir / fn).as_posix()
            if any(fnmatch.fnmatch(fn, g) for g in IGNORE_FILE_GLOBS):
                continue
            if any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(fn, p) for p in excludes):
                continue
            yield Path(dirpath) / fn, lang
