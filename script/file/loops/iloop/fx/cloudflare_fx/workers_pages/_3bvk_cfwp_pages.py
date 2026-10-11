"""_3bvk_cfwp_pages - recover a Cloudflare Pages project's CONTENT (stdlib only, no wget needed).

Cloudflare gives no download endpoint for Pages assets, so - exactly like the reference pages.sh - the latest
PRODUCTION deployment's own URL is mirrored: every publicly reachable file is saved, following links found in
HTML / CSS (href, src, srcset, poster, inline style url(), @import, manifest, icons). Same host only.

    recover_pages(name, token, account, out, rep)

It cannot recover what is not publicly served: original source files, folder layout, _headers, _redirects,
Pages Functions. Files only referenced from JavaScript at runtime are not found. The report says so.
"""
import re, urllib.error, urllib.parse, urllib.request
from collections import deque
from pathlib import PurePosixPath
from _3bvk_recover_api import ApiError, get_json
from _3bvk_recover_util import RecoverError, safe_join

MAX_FILES = 5000
MAX_BYTES = 100 * 1024 * 1024
UA = "bashbasicsbyvk-recover/1"
_ATTR = re.compile(r"""(?:href|src|poster|data-src|data-href|content|action)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))""", re.I)
_SRCSET = re.compile(r"""srcset\s*=\s*(?:"([^"]*)"|'([^']*)')""", re.I)
_CSSURL = re.compile(r"""url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)""", re.I)
_CSSIMP = re.compile(r"""@import\s+(?:"([^"]*)"|'([^']*)')""", re.I)
_HTML_EXT = (".html", ".htm")


def _deployment(name, token, account):
    q = urllib.parse.quote(name, safe="")
    j = get_json(f"/accounts/{account}/pages/projects/{q}/deployments?env=production&per_page=1", token)
    res = j.get("result") or []
    if res and res[0].get("url"):
        return res[0]
    p = (get_json(f"/accounts/{account}/pages/projects/{q}", token).get("result") or {})
    d = p.get("canonical_deployment") or p.get("latest_deployment") or {}
    if not d.get("url"):
        raise RecoverError("no production deployment found for this Pages project")
    return d


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def _fetch(url, hops=5):
    """-> (bytes, content-type, final_url). Follows redirects by hand so they can be kept on the same host."""
    for _ in range(hops):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with _opener.open(req, timeout=30) as r:
                body = r.read(MAX_BYTES + 1)
                if len(body) > MAX_BYTES:
                    raise ApiError("file larger than 100 MB, skipped")
                return body, r.headers.get("Content-Type", ""), url
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307, 308) and e.headers.get("Location"):
                nxt = urllib.parse.urljoin(url, e.headers["Location"])
                if urllib.parse.urlsplit(nxt).netloc != urllib.parse.urlsplit(url).netloc:
                    raise ApiError("redirects off-site, skipped")
                url = nxt; continue
            raise ApiError(f"HTTP {e.code}")
        except urllib.error.URLError as e:
            raise ApiError(f"network error: {e.reason}")
    raise ApiError("too many redirects")


def _links(text, base, is_css):
    found = []
    if not is_css:
        for m in _ATTR.finditer(text):
            found.append(next(g for g in m.groups() if g is not None))
        for m in _SRCSET.finditer(text):
            for part in (m.group(1) or m.group(2) or "").split(","):
                part = part.strip().split(" ")[0]
                if part: found.append(part)
    for rx in (_CSSURL, _CSSIMP):
        for m in rx.finditer(text):
            found.append(next((g for g in m.groups() if g), ""))
    out = []
    for raw in found:
        raw = raw.strip().replace("&amp;", "&")
        if not raw or raw.startswith(("#", "data:", "mailto:", "tel:", "javascript:", "blob:")):
            continue
        out.append(urllib.parse.urljoin(base, raw))
    return out


def _local_path(url, ctype):
    """URL -> relative file path. /a/ -> a/index.html ; /a (html) -> a.html ; /a.css -> a.css"""
    p = urllib.parse.unquote(urllib.parse.urlsplit(url).path) or "/"
    if p.endswith("/"):
        p += "index.html"
    elif not PurePosixPath(p).suffix and "html" in ctype.lower():
        p += ".html"
    p = p.lstrip("/")
    return re.sub(r'[<>:"|?*\x00-\x1f]', "_", p) or "index.html"


def recover_pages(name, token, account, out, rep):
    say = rep.say
    say(f"\n[1/3] Finding the latest production deployment of '{name}'...")
    dep = _deployment(name, token, account)
    base_url = dep["url"].rstrip("/")
    host = urllib.parse.urlsplit(base_url).netloc
    say(f"  deployment id : {dep.get('id')}")
    say(f"  created (UTC) : {dep.get('created_on')}")
    say(f"  url           : {base_url}")

    say("\n[2/3] Mirroring publicly accessible files...")
    out.mkdir(parents=True)
    queue = deque([base_url + "/", base_url + "/404.html", base_url + "/robots.txt", base_url + "/sitemap.xml",
                   base_url + "/favicon.ico", base_url + "/manifest.json"])
    seen, saved, failed, skipped = set(), {}, [], 0
    while queue and len(saved) < MAX_FILES:
        url = queue.popleft().split("#", 1)[0].split("?", 1)[0]
        if url in seen or urllib.parse.urlsplit(url).netloc != host:
            continue
        seen.add(url)
        try:
            body, ctype, final = _fetch(url)
        except ApiError as e:
            if str(e) != "HTTP 404":
                failed.append(f"{url}  ({e})")
            continue
        low = ctype.lower()
        rel = _local_path(final.split("?", 1)[0], ctype)
        if rel in saved.values():                       # SPA fallback: an unknown path answered with index.html
            skipped += 1; continue
        try:
            dest = safe_join(out, rel)
        except ValueError as e:
            failed.append(f"{url}  ({e})"); continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(body)
        saved[url] = rel
        print(f"  saved {rel}  ({len(body)} B)")
        is_css = "css" in low or rel.endswith(".css")
        if "html" in low or is_css:
            for link in _links(body.decode("utf-8", "replace"), final, is_css):
                if link.split("#", 1)[0].split("?", 1)[0] not in seen:
                    queue.append(link)
    if queue and len(saved) >= MAX_FILES:
        say(f"  STOPPED at {MAX_FILES} files (safety limit).")
    if not saved:
        raise RecoverError("nothing could be downloaded (is the deployment behind Cloudflare Access, or empty?)")

    say("\n[3/3] Writing report...")
    lines = [f"Cloudflare Pages recovery: {name}", f"deployment id : {dep.get('id')}",
             f"created (UTC) : {dep.get('created_on')}", f"source url    : {base_url}",
             f"files saved   : {len(saved)}", f"duplicate/fallback responses skipped: {skipped}", "",
             "WARNING: this mirrors PUBLICLY ACCESSIBLE resources. It cannot recover original source files, the",
             "original folder structure, _headers, _redirects, Pages Functions or files only loaded by JavaScript.", ""]
    lines += ["FAILED:"] + [f"  {f}" for f in failed] + [""] if failed else []
    lines += ["FILES:"] + [f"  {rel}  <-  {u}" for u, rel in saved.items()]
    (out / "RECOVERY-REPORT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    say(f"  {len(saved)} file(s) saved" + (f", {len(failed)} failed (see RECOVERY-REPORT.txt)" if failed else ""))
