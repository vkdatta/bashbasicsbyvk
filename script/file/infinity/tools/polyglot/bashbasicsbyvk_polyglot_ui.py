"""Progress + console helpers. Uses `rich` when installed, plain text otherwise."""
from __future__ import annotations

import sys
from contextlib import contextmanager

try:
    from rich.console import Console
    from rich.progress import (BarColumn, MofNCompleteColumn, Progress, TaskProgressColumn,
                               TextColumn, TimeElapsedColumn)
    HAVE_RICH = True
except ImportError:                                           # pragma: no cover
    HAVE_RICH = False


class ProgressUI:
    def __init__(self, quiet: bool = False, plain: bool = False) -> None:
        self.quiet = quiet
        self.use_rich = HAVE_RICH and not plain
        self._p = None
        self._err = Console(stderr=True) if self.use_rich else None

    def __enter__(self):
        if self.use_rich and not self.quiet:
            self._p = Progress(TextColumn("[bold cyan]{task.description}"), BarColumn(), MofNCompleteColumn(),
                               TaskProgressColumn(), TimeElapsedColumn(), console=self._err)
            self._p.__enter__()
        return self

    def __exit__(self, *exc):
        if self._p is not None:
            self._p.__exit__(*exc)

    def warn(self, msg: str) -> None:
        if self.quiet:
            return
        if self._err is not None:
            self._err.print(f"[yellow]warning:[/yellow] {msg}", highlight=False)
        else:
            print(f"warning: {msg}", file=sys.stderr)

    @contextmanager
    def task(self, description: str, total: int):
        total = max(int(total), 1)
        if self.quiet:
            yield (lambda n=1: None)
        elif self._p is not None:
            tid = self._p.add_task(description, total=total)
            yield (lambda n=1: self._p.advance(tid, n))
            self._p.update(tid, completed=total)
        else:                                                 # plain fallback: ~10 updates
            state = {"done": 0, "last": -1}

            def advance(n=1):
                state["done"] += n
                step = int(10 * state["done"] / total)
                if step != state["last"]:
                    state["last"] = step
                    print(f"{description}: {min(100, 100 * state['done'] // total)}% ({min(state['done'], total)}/{total})",
                          file=sys.stderr)
            yield advance
