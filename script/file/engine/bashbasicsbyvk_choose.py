"""bashbasicsbyvk_choose - the python door to THE one-of-many question (bashbasicsbyvk_choose, the app's native choice menu).

    import bashbasicsbyvk_choose as choose
    key = choose.ask("Select statement type:", [("1", "INSERT INTO"), ("2", "INSERT OR IGNORE INTO")], default="1")   # a str: the row's key
    keys = choose.ask("Recover which?", rows, multi=True)                                                              # a list of keys
    key = choose.ask("Pick one", rows, back=True)       # a tool that chains questions: u raises Back (ask the question before again)

Rows are (key, label) pairs or "key:Label" strings.  There is no answer: EOFError (q / u / Ctrl-D), like bashbasicsbyvk_ask.ask; u raises Back with back=True.
The menu is drawn on the terminal even when this process's stdin / stdout are pipes.  Only when the menu is not installed (a broken install) does it
fall back to one plain numbered line on the terminal.
"""
import shutil
from pathlib import Path

import bashbasicsbyvk_qbridge as _qb      # inside the app the question is asked by the app itself (see bashbasicsbyvk_qbridge.py)

try:
    from bashbasicsbyvk_ask import Back, steps          # the SAME Back / steps as the typed prompts: one chain across both doors
except ImportError:                                      # a broken install
    class Back(EOFError):
        pass

    def steps(*fns):
        for f in fns:
            f()

CLI_NAME = "bashbasicsbyvk_choose"


def _cli():
    here = Path(__file__).resolve().parent / CLI_NAME
    if here.is_file():
        return str(here)
    return shutil.which(CLI_NAME)


def _rows(items):
    out = []
    for it in items:
        k, lab = (it if isinstance(it, (tuple, list)) else str(it).split(":", 1))
        out.append((str(k), str(lab)))
    return out


def _plain(question, rows, default, multi):
    try:
        with open("/dev/tty", "r+") as tty:
            tty.write(question + "\n")
            for k, lab in rows:
                tty.write(f"  {k}) {lab}\n")
            while True:
                tty.write("Choice" + (" (keys separated by spaces)" if multi else "") + ": ")
                tty.flush()
                line = tty.readline()          # bvk-read-ok: last fallback of a broken install (no bashbasicsbyvk_choose)
                if not line:
                    raise EOFError
                got = line.split()
                keys = [k.lower() for k, _ in rows]
                if not got and default and not multi:
                    return default
                if got and all(g.lower() in keys for g in got) and (multi or len(got) == 1):
                    return got if multi else got[0]
    except OSError:
        raise EOFError


def ask(question, items, title="", icon="", default="", multi=False, back=False, keys_line=False):
    rows = _rows(items)
    cli = _cli()
    if cli or _qb.active():
        tail = [question]
        if title:
            tail += ["-t", title]
        if icon:
            tail += ["-i", icon]
        if default:
            tail += ["-d", str(default)]
        if multi:
            tail += ["-m"]
        if keys_line:
            tail += ["-k"]
        if back:
            tail += ["-b"]
        tail += [f"{k}:{lab}" for k, lab in rows]
        try:
            rc, raw = _qb.run("choose", tail, cli)
        except OSError:
            rc, raw = 3, b""
        if rc == 0:
            out = raw.decode("utf-8", "replace").strip()
            return out.split() if multi else out
        if rc in (130, -2):                           # Ctrl-C inside the menu
            raise KeyboardInterrupt
        if rc == 4:                                   # u, with back=True
            raise Back
        if rc != 3:                                   # 2 = no answer; anything else = the tool ended: never ask twice
            raise EOFError
        # 3 = the menu is not installed: the plain line below
    return _plain(question, rows, str(default), multi)
