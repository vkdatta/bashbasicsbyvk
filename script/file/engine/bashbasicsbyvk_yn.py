"""bashbasicsbyvk_yn - the python door to THE yes/no question (bashbasicsbyvk_yn, the app's native choice menu).

    import bashbasicsbyvk_yn as yn
    if yn.ask("Do you want to continue?", title="xtract", icon="🔗"):        # True = Yes, False = No / no answer / no terminal
        ...
    yn.ask(...) -> True | False | None      (None = no answer: the menu was left)

The menu is drawn on the terminal even when this process's stdin / stdout are pipes.  Only when the menu is not installed (a broken install)
does it fall back to one plain y/n line on the terminal.
"""
import shutil
import subprocess
from pathlib import Path

CLI_NAME = "bashbasicsbyvk_yn"


def _cli():
    here = Path(__file__).resolve().parent / CLI_NAME
    if here.is_file():
        return str(here)
    return shutil.which(CLI_NAME)


def _plain(question):
    try:
        with open("/dev/tty", "r+") as tty:
            while True:
                tty.write(question + " (y/n): ")
                tty.flush()
                line = tty.readline()
                if not line:
                    return None
                a = line.strip().lower()
                if a in ("y", "yes"):
                    return True
                if a in ("n", "no"):
                    return False
    except OSError:
        return None


def ask(question, title="", icon=""):
    cli = _cli()
    if cli:
        cmd = ["bash", cli, question]
        if title:
            cmd += ["-t", title]
        if icon:
            cmd += ["-i", icon]
        try:
            rc = subprocess.run(cmd).returncode
        except OSError:
            rc = 3
        if rc == 0:
            return True
        if rc == 1:
            return False
        if rc == 2:
            return None
    return _plain(question)
