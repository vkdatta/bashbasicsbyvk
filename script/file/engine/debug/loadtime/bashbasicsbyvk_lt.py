"""bashbasicsbyvk_lt — the Python side of `loadtime`.

A Python tool started by bashbasicsbyvk joins the same timeline as the shell:

    try:
        import bashbasicsbyvk_lt; bashbasicsbyvk_lt.install("cloudflare workers")      # first lines of the tool
    except Exception:
        pass

install() does three things, and only while the person is waiting for a screen change
(the shell exports _LT_PEND=1 and BVK_LT_LOG=<file>; otherwise every call here is a no-op):

  1. logs how long the whole tool ran                                  (kind S)
  2. times every HTTP(S) request made through http.client — which covers urllib and requests:
        DNS lookup · TCP connect · TLS handshake · wait for the first byte · download   (kind N)
     written in the same cumulative key=value form curl uses, so one report parser reads both
  3. gives  span("name")  /  mark("name")  for steps of its own

It never raises and never prints: a failure here must not touch the tool.
"""
import os
import socket
import threading
import time

_LOG = os.environ.get("BVK_LT_LOG", "")
_tls = threading.local()
_installed = False
_lock = threading.Lock()


def _now_us():
    return int(time.time() * 1e6)


def active():
    return bool(_LOG) and os.environ.get("_LT_PEND", "") != "" and os.environ.get("_LT_ON_PY", "1") != "0"


def _write(kind, t, dur, name, detail=""):
    if not _LOG:
        return
    try:
        flags = "b" if os.environ.get("_LT_BG") else ""
        name = str(name).replace("\t", " ").replace("\n", " ")
        detail = str(detail).replace("\t", " ").replace("\n", " ")
        line = "%s\t%d\t%d\t%d\t%s\t%s\t%s\n" % (kind, t, max(0, int(dur)), os.getpid(), flags, name, detail)
        with _lock:
            with open(_LOG, "a", encoding="utf-8") as fh:
                fh.write(line)
    except Exception:
        pass


class span(object):
    """with bashbasicsbyvk_lt.span("list Drive folder"): …"""

    def __init__(self, name, detail=""):
        self.name, self.detail = name, detail

    def __enter__(self):
        self.on = active()
        self.t0 = _now_us()
        self.p0 = time.perf_counter()
        return self

    def __exit__(self, *exc):
        if self.on:
            _write("S", self.t0, (time.perf_counter() - self.p0) * 1e6, self.name, self.detail)
        return False


def mark(name, detail=""):
    if active():
        _write("M", _now_us(), 0, name, detail)


# ─────────────────────────────────────────────────────────────── HTTP timing
def _mask_path(path):
    path = (path or "").split("?", 1)[0].split("#", 1)[0]
    out = []
    for seg in path.split("/"):
        if not seg:
            continue
        out.append(seg if len(seg) <= 18 else seg[:6] + "…")
    return "/" + "/".join(out) if out else ""


def _state():
    st = getattr(_tls, "st", None)
    if st is None:
        st = _tls.st = {"dns": 0.0, "tls": 0.0}
    return st


def _patch_http():
    import http.client as hc
    import ssl

    orig_gai = socket.getaddrinfo

    def gai(*a, **k):
        t = time.perf_counter()
        try:
            return orig_gai(*a, **k)
        finally:
            try:
                _state()["dns"] += time.perf_counter() - t
            except Exception:
                pass

    socket.getaddrinfo = gai

    orig_wrap = ssl.SSLContext.wrap_socket

    def wrap(self, *a, **k):
        t = time.perf_counter()
        try:
            return orig_wrap(self, *a, **k)
        finally:
            try:
                _state()["tls"] += time.perf_counter() - t
            except Exception:
                pass

    ssl.SSLContext.wrap_socket = wrap

    orig_connect = hc.HTTPConnection.connect

    def connect(self):
        st = _state()
        st["dns"] = 0.0
        st["tls"] = 0.0
        t = time.perf_counter()
        try:
            return orig_connect(self)
        finally:
            try:
                total = time.perf_counter() - t
                self._lt_connect = (total, st["dns"], st["tls"])
            except Exception:
                pass

    hc.HTTPConnection.connect = connect

    orig_request = hc.HTTPConnection.request

    def request(self, method, url, *a, **k):
        try:
            self._lt_req = (method, url, _now_us(), time.perf_counter())
        except Exception:
            pass
        try:
            return orig_request(self, method, url, *a, **k)
        finally:
            try:
                self._lt_sent = time.perf_counter()
            except Exception:
                pass

    hc.HTTPConnection.request = request

    orig_getresponse = hc.HTTPConnection.getresponse

    def getresponse(self):
        resp = orig_getresponse(self)
        try:
            if active() and getattr(self, "_lt_req", None):
                resp._lt_info = {
                    "req": self._lt_req,
                    "sent": getattr(self, "_lt_sent", self._lt_req[3]),
                    "headers": time.perf_counter(),
                    "connect": getattr(self, "_lt_connect", None),
                    "host": self.host,
                    "tls": isinstance(self, hc.HTTPSConnection),
                    "bytes": 0,
                    "done": False,
                }
                self._lt_connect = None            # the next request on this connection reuses it
        except Exception:
            pass
        return resp

    hc.HTTPConnection.getresponse = getresponse

    def finish(resp):
        info = getattr(resp, "_lt_info", None)
        if not info or info["done"]:
            return
        info["done"] = True
        try:
            method, url, t_us, p0 = info["req"]
            now = time.perf_counter()
            conn = info["connect"]
            total = now - p0
            if conn:
                ctot, dns, tls = conn
                tcp = max(0.0, ctot - dns - tls)
                ns, co = dns, dns + tcp
                ap = co + tls if info["tls"] else 0.0
                pt = ctot
                nc = 1
                # the request is sent after connecting; p0 is taken before connect() ran
                st = info["headers"] - p0
            else:
                ns = co = ap = pt = 0.0
                nc = 0
                st = info["headers"] - p0
            ver = "1.1"
            code = getattr(resp, "status", "")
            detail = "ns=%.6f;co=%.6f;ap=%.6f;pt=%.6f;st=%.6f;tt=%.6f;code=%s;ver=%s;dl=%d;nc=%d" % (
                ns, co, ap, pt, st, total, code, ver, info["bytes"], nc)
            path = url if url.startswith("/") else "/" + url.split("://", 1)[-1].split("/", 1)[-1]
            _write("N", t_us, total * 1e6, "python %s %s%s" % (method, info["host"], _mask_path(path)), detail)
        except Exception:
            pass

    orig_read = hc.HTTPResponse.read

    def read(self, amt=None):
        data = orig_read(self, amt)
        try:
            info = getattr(self, "_lt_info", None)
            if info is not None:
                info["bytes"] += len(data or b"")
                if amt is None or not data:
                    finish(self)
        except Exception:
            pass
        return data

    hc.HTTPResponse.read = read

    orig_close = hc.HTTPResponse.close

    def close(self):
        try:
            finish(self)
        except Exception:
            pass
        return orig_close(self)

    hc.HTTPResponse.close = close


def install(label=None):
    """Hook this process into the timeline.  Safe to call more than once."""
    global _installed
    if _installed or not active():
        return
    _installed = True
    try:
        _patch_http()
    except Exception:
        pass
    if label:
        import atexit
        t0, p0 = _now_us(), time.perf_counter()

        def done():
            if active():
                _write("S", t0, (time.perf_counter() - p0) * 1e6, "python tool: %s" % label, "")

        atexit.register(done)
