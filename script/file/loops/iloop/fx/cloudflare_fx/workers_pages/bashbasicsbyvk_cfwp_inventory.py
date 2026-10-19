"""bashbasicsbyvk_cfwp_inventory - every Worker AND Pages project of the account, with its latest deployment time, plus export.

Stdlib only. Re-uses the REST helpers of the recover modules (bashbasicsbyvk_recover_api); nothing there is modified.

    list_inventory(token, account)  -> (rows, warnings)   rows = [{type, name, epoch, error}] sorted Worker first, then Pages
    export_rows(rows, nav, fmt)     -> [paths written]    fmt = csv | json | both

Times are converted to the APP timezone: the app exports TZ (see _apply_timezone in the settings), and Python honours it.
"""
import csv, json, os, re, time, urllib.parse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from bashbasicsbyvk_recover_api import ApiError, get_json

TYPES = ("Worker", "Pages")
LOAD_THREADS = max(1, int(os.environ.get("BVK_LOAD_THREADS", "16") or 16))
_TS = re.compile(r"^(\d{4})-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?$")


def to_epoch(value):
    """Cloudflare ISO timestamp -> epoch seconds (int) or None. Tolerates any number of fraction digits."""
    m = _TS.match(str(value or "").strip())
    if not m:
        return None
    y, mo, d, h, mi, s, z = m.groups()
    dt = datetime(int(y), int(mo), int(d), int(h), int(mi), int(s), tzinfo=timezone.utc)
    if z and z != "Z":
        sign = 1 if z[0] == "+" else -1
        zz = z[1:].replace(":", "")
        return int(dt.timestamp()) - sign * (int(zz[:2]) * 3600 + int(zz[2:]) * 60)
    return int(dt.timestamp())


def fmt_local(epoch):
    """Epoch -> '2026-10-11 14:05:09 IST' in the app timezone (TZ env); 'Not available' when unknown."""
    if epoch in (None, ""):
        return "Not available"
    return datetime.fromtimestamp(int(epoch)).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def fmt_utc(epoch):
    if epoch in (None, ""):
        return ""
    return datetime.fromtimestamp(int(epoch), timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ------------------------------------------------------------------ listing --
def _pages_projects(token, account):
    """Page 1 first (it says how many pages there are), then every remaining page at the same time."""
    path = f"/accounts/{account}/pages/projects"
    j = get_json(path, token)
    out = list(j.get("result") or [])
    total = int((j.get("result_info") or {}).get("total_pages") or 1)
    if not out or total <= 1:
        return out
    with ThreadPoolExecutor(max_workers=min(LOAD_THREADS, total - 1)) as ex:
        for res in ex.map(lambda pg: get_json(f"{path}?page={pg}", token).get("result") or [], range(2, total + 1)):
            out.extend(res)
    return out


def _worker_scripts(token, account):
    return get_json(f"/accounts/{account}/workers/scripts", token).get("result") or []


def _worker_when(token, account, script):
    name = script["id"]
    q = urllib.parse.quote(name, safe="")
    try:
        j = get_json(f"/accounts/{account}/workers/scripts/{q}/deployments", token)
        deps = (j.get("result") or {}).get("deployments") or []
        if deps:
            return to_epoch(deps[0].get("created_on")), ""
    except ApiError as e:
        err = str(e)
    else:
        err = ""
    ep = to_epoch(script.get("modified_on"))                    # no deployment record -> last modified
    return ep, ("" if ep else err)


def _pages_when(token, account, project):
    dep = project.get("canonical_deployment") or project.get("latest_deployment") or {}
    ep = to_epoch(dep.get("created_on"))
    if ep:
        return ep, ""
    try:
        q = urllib.parse.quote(project["name"], safe="")
        j = get_json(f"/accounts/{account}/pages/projects/{q}/deployments?env=production&per_page=1", token)
        res = j.get("result") or []
        return (to_epoch(res[0].get("created_on")) if res else None), ""
    except ApiError as e:
        return None, str(e)


def list_inventory(token, account):
    warnings, jobs = [], []

    def listing(fn):                                            # -> (items, warning)
        try:
            return fn(token, account), None
        except ApiError as e:
            return [], str(e)

    with ThreadPoolExecutor(max_workers=2) as ex:               # workers list and pages list at the same time
        fw, fp = ex.submit(listing, _worker_scripts), ex.submit(listing, _pages_projects)
        ws, werr = fw.result(); ps, perr = fp.result()
    for w in ws:
        if isinstance(w, dict) and w.get("id"):
            jobs.append(("Worker", w["id"], w))
    for p in ps:
        if isinstance(p, dict) and p.get("name"):
            jobs.append(("Pages", p["name"], p))
    if werr: warnings.append(f"Workers listing failed: {werr}")
    if perr: warnings.append(f"Pages listing failed: {perr}")
    if not jobs and warnings and len(warnings) == 2:
        raise ApiError("; ".join(warnings))

    def one(job):
        typ, name, obj = job
        try:
            ep, err = (_worker_when if typ == "Worker" else _pages_when)(token, account, obj)
        except Exception as e:                                   # one row's problem must not drop the list
            ep, err = None, f"{type(e).__name__}: {e}"
        return {"type": typ, "name": name, "epoch": ep, "error": err}

    with ThreadPoolExecutor(max_workers=max(1, min(LOAD_THREADS, len(jobs) or 1))) as ex:
        rows = list(ex.map(one, jobs))
    rows.sort(key=lambda r: (TYPES.index(r["type"]), r["name"].lower()))
    return rows, warnings


# ------------------------------------------------------------------- export --
def export_rows(rows, nav, fmt):
    """Write the list to NAV (never overwrites). fmt: csv | json | both. Returns the paths written."""
    stamp = time.strftime("%Y%m%d-%H%M%S")
    tzname = time.strftime("%Z")
    written = []
    for kind in (("csv", "json") if fmt == "both" else (fmt,)):
        p = Path(nav) / f"cloudflare_workers_pages_{stamp}.{kind}"
        n = 1
        while p.exists():
            p = Path(nav) / f"cloudflare_workers_pages_{stamp}_{n}.{kind}"; n += 1
        if kind == "csv":
            with open(p, "w", encoding="utf-8", newline="") as f:
                w = csv.writer(f)
                w.writerow(["name", "type", f"last_deployment ({tzname})", "last_deployment_utc"])
                for r in rows:
                    w.writerow([r["name"], r["type"], fmt_local(r["epoch"]), fmt_utc(r["epoch"])])
        else:
            data = [{"name": r["name"], "type": r["type"], "last_deployment": fmt_local(r["epoch"]),
                     "last_deployment_utc": fmt_utc(r["epoch"]) or None, "timezone": tzname} for r in rows]
            p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written.append(str(p))
    return written
