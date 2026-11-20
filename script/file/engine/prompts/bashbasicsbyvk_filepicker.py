"""bashbasicsbyvk_filepicker - the python door to THE file / folder picker (bashbasicsbyvk_filepicker, the app's own Transfer picker).

    import bashbasicsbyvk_filepicker as fp

    paths = fp.pick("allow(files,folders)")                    # a list of absolute paths; [] when nothing was picked
    paths = fp.pick("allow.ext(csv)")                          # only .csv files
    paths = fp.pick("block(folders)")                          # files only
    paths = fp.pick("block.ext(txt)")                          # everything except .txt files
    paths = fp.pick("allow(files,folders); allow.ext(csv)")    # several commands, joined with ;   (.csv files and any folder)

The commands are the ones you would write as 3bvk.filepicker.allow(files,folders) ... : a leading "3bvk.filepicker." is accepted and ignored,
so the text can be copied as it is.  (A python name cannot start with a digit, so the call is  fp.pick("...")  and the commands go in the string.)
The same thing, spelled as calls:  fp.filepicker.allow("files", "folders")  ·  fp.filepicker.allow.ext("csv")  ·  fp.filepicker.block("folders")
·  fp.filepicker.block.ext("txt")  - each opens the picker and returns the list; to join several rules use pick("...; ...").

In the picker: N opens a folder or picks a file, s-N picks a folder as it is (s-a all, s-2-4 a range, 1,3-5 several), v reviews and confirms,
u goes up / back, q quits.  No answer (q / u at the top / Ctrl-D) gives [] - or raises EOFError with  strict=True.
Wrong commands raise ValueError.  The picker is drawn on the terminal even when this process's stdin / stdout are pipes.
"""
import os
import shutil
import sys
from pathlib import Path

import bashbasicsbyvk_qbridge as _qb      # inside the app the question is asked by the app itself (see bashbasicsbyvk_qbridge.py)

CLI_NAME = "bashbasicsbyvk_filepicker"

files = "files"          # so  allow(files, folders)  reads like the commands
folders = "folders"


def _cli():
    here = Path(__file__).resolve().parent / CLI_NAME
    if here.is_file():
        return str(here)
    return shutil.which(CLI_NAME)


def _title_name():
    try:
        return os.path.basename(sys.argv[0]) or "your code"
    except (AttributeError, IndexError):
        return "your code"


def pick(commands="allow(files,folders)", start=None, strict=False):
    """Open the picker with these commands; -> list of absolute paths ([] = nothing picked; EOFError with strict=True)."""
    cli = _cli()
    if not (cli or _qb.active()):
        raise RuntimeError("bashbasicsbyvk is not installed: bashbasicsbyvk_filepicker was not found")
    tail = [str(commands)]
    if start:
        tail += ["-s", str(start)]
    tail += ["-f", _title_name()]
    try:
        rc, raw = _qb.run("filepicker", tail, cli)
    except OSError as e:
        raise RuntimeError("the file picker could not be started: %s" % e)
    if rc == 0:
        return [p for p in raw.decode("utf-8", "replace").split("\n") if p]
    if rc in (130, -2):                               # Ctrl-C inside the picker: the same as at input()
        raise KeyboardInterrupt
    if rc == 64:
        raise ValueError("bashbasicsbyvk_filepicker did not understand: %r  (use allow(files,folders) · allow.ext(csv) · block(folders) · block.ext(txt), joined with ;)" % (commands,))
    if rc == 3:
        raise RuntimeError("the file picker is not installed (reinstall bashbasicsbyvk)")
    if strict:
        raise EOFError("nothing was picked")
    return []


def _names(args):
    out = []
    for a in args:
        out += [x for x in (a if isinstance(a, (list, tuple)) else [a])]
    return ",".join(str(x) for x in out)


class _Rule:
    """filepicker.allow(...) / filepicker.allow.ext(...) / filepicker.block(...) / filepicker.block.ext(...): one rule, one picker."""

    def __init__(self, verb):
        self._verb = verb
        self.ext = lambda *exts, **kw: pick("%s.ext(%s)" % (verb, _names(exts)), **kw)

    def __call__(self, *kinds, **kw):
        return pick("%s(%s)" % (self._verb, _names(kinds)), **kw)


class _FilePicker:
    allow = _Rule("allow")
    block = _Rule("block")
    pick = staticmethod(pick)


filepicker = _FilePicker()
