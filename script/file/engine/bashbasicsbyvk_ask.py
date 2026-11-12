"""bashbasicsbyvk_ask - the python door to THE typed-line prompt (bashbasicsbyvk_ask, the app's native line editor).

    import bashbasicsbyvk_ask as bvk
    name = bvk.ask("Enter table name: ")             # a str; raises EOFError when there is no answer, like the built-in line input
    key = bvk.ask("API token (hidden): ", secret=True)

Never use the built-in line input, a stdin readline or getpass in a tool: this is the one door (AGENTS.md rule 16).  Only when the editor is not
installed (a broken install) does it fall back to one plain line on the terminal.
"""
import shutil
import subprocess
import sys
from pathlib import Path

CLI_NAME = "bashbasicsbyvk_ask"


def _cli():
    here = Path(__file__).resolve().parent / CLI_NAME
    if here.is_file():
        return str(here)
    return shutil.which(CLI_NAME)


def _plain(prompt):
    try:
        with open("/dev/tty", "r+") as tty:
            tty.write(prompt)
            tty.flush()
            line = tty.readline()   # bvk-read-ok: last fallback of a broken install (no bashbasicsbyvk_ask)
    except OSError:
        line = sys.stdin.readline()   # bvk-read-ok: no terminal at all (a pipe, a test harness): the piped answer
    if not line:
        raise EOFError
    return line.rstrip("\r\n")


def ask(prompt, initial="", secret=False):
    cli = _cli()
    if cli:
        cmd = ["bash", cli, prompt]
        if initial:
            cmd += ["-i", initial]
        if secret:
            cmd += ["-s"]
        try:
            r = subprocess.run(cmd, stdout=subprocess.PIPE)
        except OSError:
            r = None
        if r is not None:
            if r.returncode == 0:
                return r.stdout.decode("utf-8", "replace")
            if r.returncode in (130, -2):                 # Ctrl-C inside the editor: the same as at input()
                raise KeyboardInterrupt
            if r.returncode != 3:                         # 2 = no answer (Ctrl-D); anything else = the tool ended: never ask twice
                raise EOFError
            # 3 = the editor is not installed: the plain line below
    return _plain(prompt)
