"""_3bvk_recover_api - Cloudflare REST access (stdlib only): GET helpers, worker list, multipart splitting."""
import json, os, re, urllib.error, urllib.request
from email.parser import BytesParser
from email import policy

API = os.environ.get("CLOUDFLARE_API_BASE", "https://api.cloudflare.com/client/v4")

# ----------------------------------------------------------------- HTTP ----
class ApiError(Exception): pass

def http_get(path, token):
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.read(), r.headers.get("Content-Type", "")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            msg = "; ".join(x.get("message", "") for x in json.loads(body).get("errors", [])) or body[:200]
        except Exception:
            msg = body[:200]
        raise ApiError(f"HTTP {e.code} on {path.split('?')[0]}: {msg}")
    except urllib.error.URLError as e:
        raise ApiError(f"Network error on {path}: {e.reason}")

def get_json(path, token):
    data, _ = http_get(path, token)
    return json.loads(data)


def list_workers(token, account):
    """Names of every Worker script in the account, sorted. Raises ApiError (token / account problems surface here)."""
    res = get_json(f"/accounts/{account}/workers/scripts", token).get("result") or []
    names = sorted({w.get("id") for w in res if isinstance(w, dict) and w.get("id")}, key=str.lower)
    return names

# --------------------------------------------------------------- multipart --
def split_multipart(data, content_type):
    if "multipart/" not in content_type.lower():
        return [("worker.js", data)]
    msg = BytesParser(policy=policy.default).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\nMIME-Version: 1.0\r\n\r\n" + data)
    parts = []
    for i, p in enumerate(msg.iter_parts()):
        name = p.get_filename() or p.get_param("name", header="content-disposition") or f"part-{i}.js"
        name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(name)) or f"part-{i}.js"
        payload = p.get_payload(decode=True)
        if payload is not None: parts.append((name, payload))
    return parts

