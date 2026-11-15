"""bashbasicsbyvk_ask - the python door to THE typed-line prompt (bashbasicsbyvk_ask, the app's native line editor).

    import bashbasicsbyvk_ask as bvk
    name = bvk.ask("Enter table name: ")             # a str; raises EOFError when there is no answer, like the built-in line input
    key = bvk.ask("API token (hidden): ", secret=True)
    name = bvk.ask("Table: ", back=True)             # a tool that chains questions: u raises bvk.Back (ask the question before again)

u / q typed alone are the two navigation words of every menu: q (and Ctrl-D) raise EOFError; u raises EOFError too, or Back with back=True.  @u / @q is that text.

Never use the built-in line input, a stdin readline or getpass in a tool: this is the one door (AGENTS.md rule 16).  Only when the editor is not
installed (a broken install) does it fall back to one plain line on the terminal.
"""
import shutil
import subprocess
import sys
from pathlib import Path

CLI_NAME = "bashbasicsbyvk_ask"


class Back(EOFError):
    """u at a question of a chain (ask(..., back=True)): the caller asks the question before again.  An EOFError on purpose: a tool that does not chain
    treats u like q / Ctrl-D (leave), which is what it did before."""


def steps(*fns):
    """The questions of one flow, one function each (the Python twin of _mc_steps in bashbasicsbyvk_menuchrome.sh): a step returns normally when it asked
    and was answered, False when it had nothing to ask (u skips it on the way back), and raises Back for u.  u on the first question that asks raises Back
    to the caller (the tool leaves)."""
    asked = []                                       # the steps that asked something: u goes back to the last of them
    i = 0
    while i < len(fns):
        try:
            r = fns[i]()
        except Back:
            if not asked:
                raise
            i = asked.pop()
            continue
        if r is not False:
            asked.append(i)
        i += 1


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


def ask(prompt, initial="", secret=False, back=False, select=False, multiline=False):
    cli = _cli()
    if cli:
        cmd = ["bash", cli, prompt]
        if initial:
            cmd += ["-i", initial]
        if secret:
            cmd += ["-s"]
        if back:
            cmd += ["-b"]
        if select:
            cmd += ["-S"]
        if multiline:
            cmd += ["-m"]
        try:
            r = subprocess.run(cmd, stdout=subprocess.PIPE)
        except OSError:
            r = None
        if r is not None:
            if r.returncode == 0:
                return r.stdout.decode("utf-8", "replace")
            if r.returncode in (130, -2):                 # Ctrl-C inside the editor: the same as at input()
                raise KeyboardInterrupt
            if r.returncode == 4:                         # u, with back=True
                raise Back
            if r.returncode != 3:                         # 2 = no answer (q / u / Ctrl-D); anything else = the tool ended: never ask twice
                raise EOFError
            # 3 = the editor is not installed: the plain line below
    return _plain(prompt)
