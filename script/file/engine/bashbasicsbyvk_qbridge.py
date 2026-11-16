"""bashbasicsbyvk_qbridge - how a python tool of the app asks its questions THROUGH the app.

A python tool that the app runs (_inf_py in bashbasicsbyvk_infinity_run.sh) has BVK_QBRIDGE set.  The three doors (bashbasicsbyvk_ask / _yn / _choose)
then do not start a menu of their own: they send the question to the app over two pipes, the app asks it with its own prompts (hint row, cc,
typed commands, u / q) and sends back the exit code and the text the stand-alone door would have given.  Without BVK_QBRIDGE the doors work as before.
"""
import os
import subprocess


def active():
    return bool(os.environ.get("BVK_QBRIDGE"))


def _read_field(fd):
    buf = b""
    while True:
        c = os.read(fd, 1)
        if not c:
            raise EOFError
        if c == b"\0":
            return buf
        buf += c


def run(kind, tail, cli=None, capture=True):
    """-> (returncode, stdout bytes).  kind = ask | yn | choose, tail = the arguments the door script takes."""
    d = os.environ.get("BVK_QBRIDGE")
    if d:
        msg = [kind] + [str(a) for a in tail]
        data = (str(len(msg)) + "\0" + "".join(a + "\0" for a in msg)).encode("utf-8")
        w = os.open(d + "/req", os.O_WRONLY)
        try:
            os.write(w, data)
        finally:
            os.close(w)
        r = os.open(d + "/rsp", os.O_RDONLY)
        try:
            rc = int(_read_field(r) or b"3")
            out = _read_field(r)
        finally:
            os.close(r)
        return rc, out
    r = subprocess.run(["bash", cli] + list(tail), stdout=subprocess.PIPE if capture else None)
    return r.returncode, (r.stdout or b"")
