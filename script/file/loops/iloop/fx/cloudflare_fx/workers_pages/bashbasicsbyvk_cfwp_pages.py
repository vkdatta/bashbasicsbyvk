"""bashbasicsbyvk_cfwp_pages - recover a Cloudflare Pages project's asset files (stdlib only, multi-threaded, no wget needed).

Cloudflare has no API that downloads (or even lists) the files of a Pages deployment, so - exactly like the
reference pages.sh (wget --recursive --page-requisites --no-parent --no-host-directories) - the latest PRODUCTION
deployment's own URL is mirrored:

  * every file is saved AS IS: the response bytes are written untouched (no link rewriting, no re-encoding)
  * the URL path IS the folder layout (/css/app.css -> css/app.css, /blog/ -> blog/index.html);
    an extensionless HTML route (/about) is saved as about.html - the name Pages itself serves it from
  * files are found by following the same links wget follows: <a href>, <link href>, <script src>, <img src/srcset>,
    <source>, <video poster>, <iframe>, <embed>, <object data>, inline style="url()", <style> and CSS url()/@import;
    <meta content> is followed ONLY for real URL meta tags (og:image, twitter:image, msapplication-*, refresh)
  * same host only; fetched concurrently by a thread pool; the report lists files in discovery order

    recover_pages(name, token, account, out, rep)

Not recoverable (not publicly served): original sources, _headers, _redirects, Pages Functions, and files that are
only built into a JavaScript string at runtime.
"""
import hashlib, http.client, os, re, shutil, time, urllib.error, urllib.parse, urllib.request
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from html.parser import HTMLParser
from pathlib import PurePosixPath
from bashbasicsbyvk_recover_api import ApiError, get_json
from bashbasicsbyvk_recover_util import RecoverError, safe_join

MAX_FILES = 20000
MAX_BYTES = 200 * 1024 * 1024
WORKERS = max(1, int(os.environ.get("BVK_PAGES_THREADS", "16") or 16))
RETRIES = 2
UA = "bashbasicsbyvk-recover/2"

_CSSURL = re.compile(r"""url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)""", re.I)
_CSSIMP = re.compile(r"""@import\s+(?:"([^"]*)"|'([^']*)')""", re.I)
_REFRESH = re.compile(r"""url\s*=\s*['"]?([^'";]+)""", re.I)

# tag -> attributes that hold a URL (what wget --page-requisites / --recursive follows)
_URL_ATTRS = {
    "a": ("href",), "area": ("href",), "link": ("href",), "script": ("src",), "img": ("src", "data-src"),
    "source": ("src",), "video": ("src", "poster"), "audio": ("src",), "track": ("src",), "iframe": ("src",),
    "frame": ("src",), "embed": ("src",), "object": ("data",), "input": ("src",), "image": ("href", "xlink:href"),
    "use": ("href", "xlink:href"), "body": ("background",),
}
_SRCSET_TAGS = {"img", "source"}
# <meta> tags whose content="" really is a URL (everything else - descriptions, titles - is plain text)
_META_URL_KEYS = {"og:image", "og:image:url", "og:image:secure_url", "og:video", "og:audio", "og:url",
                  "twitter:image", "twitter:image:src", "msapplication-tileimage", "msapplication-config"}


class _LinkParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.found, self._in_style = [], False

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        for k in _URL_ATTRS.get(tag, ()):
            if a.get(k): self.found.append(a[k])
        if tag in _SRCSET_TAGS and a.get("srcset"):
            for part in a["srcset"].split(","):
                part = part.strip().split(None, 1)[0] if part.strip() else ""
                if part: self.found.append(part)
        if tag == "meta":
            key = (a.get("property") or a.get("name") or "").lower()
            if key in _META_URL_KEYS and a.get("content"): self.found.append(a["content"])
            if a.get("http-equiv", "").lower() == "refresh":
                m = _REFRESH.search(a.get("content", ""))
                if m: self.found.append(m.group(1))
        if a.get("style"): self.found.extend(_css_links(a["style"]))
        if tag == "style": self._in_style = True

    def handle_endtag(self, tag):
        if tag == "style": self._in_style = False

    def handle_data(self, data):
        if self._in_style: self.found.extend(_css_links(data))


def _css_links(text):
    out = []
    for rx in (_CSSURL, _CSSIMP):
        for m in rx.finditer(text):
            out.append(next((g for g in m.groups() if g), ""))
    return out


def _safe_url(raw, base):
    """Raw href/src text -> absolute, fully percent-encoded http(s) URL without #fragment/?query - or None.
    A URL with spaces, an em dash or control characters never reaches urllib unescaped (that was the InvalidURL crash)."""
    raw = (raw or "").strip().replace("&amp;", "&")
    if not raw or raw.startswith(("#", "data:", "mailto:", "tel:", "javascript:", "blob:", "about:")):
        return None
    try:
        u = urllib.parse.urlsplit(urllib.parse.urljoin(base, raw))
    except ValueError:
        return None
    if u.scheme not in ("http", "https") or not u.netloc:
        return None
    path = urllib.parse.quote(u.path or "/", safe="/%:@!$&'()*+,;=~-._")
    return urllib.parse.urlunsplit((u.scheme, u.netloc, path, "", ""))


def _links(body, base, is_css):
    if is_css:
        raw = _css_links(body)
    else:
        p = _LinkParser()
        try:
            p.feed(body); p.close()
        except Exception:
            pass                                          # a broken page still yields the links parsed so far
        raw = p.found
    seen, out = set(), []
    for r in raw:
        u = _safe_url(r, base)
        if u and u not in seen:
            seen.add(u); out.append(u)
    return out


def _local_path(url, ctype):
    """URL -> relative file path. /a/ -> a/index.html ; /a (html) -> a.html ; /a.css -> a.css"""
    p = urllib.parse.unquote(urllib.parse.urlsplit(url).path) or "/"
    if p.endswith("/"):
        p += "index.html"
    elif not PurePosixPath(p).suffix and "html" in ctype.lower():
        p += ".html"
    p = "/".join(seg for seg in p.split("/") if seg not in ("", ".", ".."))
    return re.sub(r'[<>:"|?*\x00-\x1f]', "_", p) or "index.html"


# ------------------------------------------------------------------- HTTP --
class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def _fetch_once(url, hops=6):
    """-> (bytes, content-type, final_url). Redirects are followed by hand so they stay on the same host."""
    for _ in range(hops):
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
        try:
            with _opener.open(req, timeout=40) as r:
                body = r.read(MAX_BYTES + 1)
                if len(body) > MAX_BYTES:
                    raise ApiError("file larger than limit, skipped")
                return body, r.headers.get("Content-Type", ""), url
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307, 308) and e.headers.get("Location"):
                nxt = _safe_url(e.headers["Location"], url)
                if not nxt or urllib.parse.urlsplit(nxt).netloc != urllib.parse.urlsplit(url).netloc:
                    raise ApiError("redirects off-site, skipped")
                url = nxt; continue
            raise ApiError(f"HTTP {e.code}")
    raise ApiError("too many redirects")


def _fetch(url):
    """One URL, with retries on transient trouble. EVERY failure becomes ApiError: one bad URL never aborts the crawl."""
    last = None
    for attempt in range(RETRIES + 1):
        try:
            return _fetch_once(url)
        except ApiError as e:
            last = e
            code = str(e)
            if not (code.startswith("HTTP 5") or code == "HTTP 429"):
                raise
        except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError) as e:   # incl. InvalidURL
            last = ApiError(f"{type(e).__name__}: {getattr(e, 'reason', e)}")
        time.sleep(0.6 * (attempt + 1))
    raise last


# ------------------------------------------------------------- deployment --
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


# ------------------------------------------------------------------ crawl --
def _crawl(base_url, out, rep):
    host = urllib.parse.urlsplit(base_url).netloc
    seeds = [base_url + p for p in ("/", "/404.html", "/robots.txt", "/sitemap.xml", "/favicon.ico", "/manifest.json")]
    seq, seen = {}, set()                    # url -> discovery number ; every URL ever queued
    saved = {}                               # url -> (seq, rel, size)
    used_rel, failed, skipped = set(), [], 0
    digests, root_rel = {}, None
    pending = {}                             # future -> url
    stopped = False

    def queue(ex, url):
        nonlocal stopped
        if url in seen or urllib.parse.urlsplit(url).netloc != host:
            return
        if len(seen) >= MAX_FILES:
            stopped = True; return
        seen.add(url); seq[url] = len(seq) + 1
        pending[ex.submit(_fetch, url)] = url

    with ThreadPoolExecutor(max_workers=WORKERS, thread_name_prefix="pages") as ex:
        for s in seeds:
            queue(ex, s)
        while pending:
            done, _ = wait(list(pending), return_when=FIRST_COMPLETED)
            for fut in done:
                url = pending.pop(fut)
                try:
                    body, ctype, final = fut.result()
                except ApiError as e:
                    if str(e) != "HTTP 404":
                        failed.append((seq[url], f"{url}  ({e})"))
                    continue
                except Exception as e:                                   # never let one URL stop the crawl
                    failed.append((seq[url], f"{url}  ({type(e).__name__}: {e})")); continue
                low = ctype.lower()
                fpath = urllib.parse.urlsplit(final).path
                is_root = fpath in ("", "/", "/index.html")
                # a non-HTML file name (.png, .txt ...) answered with an HTML page = SPA fallback, not a real file
                if "html" in low and PurePosixPath(fpath).suffix not in ("", ".html", ".htm") and not is_root:
                    skipped += 1; continue
                rel = _local_path(final, ctype)
                if rel in used_rel:                                      # two URLs resolved to the same file
                    skipped += 1; continue
                try:
                    dest = safe_join(out, rel)
                    if dest.is_dir(): dest = dest / "index.html"; rel += "/index.html"
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(body)                              # AS IS
                except (ValueError, OSError) as e:
                    failed.append((seq[url], f"{url}  ({e})")); continue
                used_rel.add(rel)
                digests[rel] = hashlib.sha256(body).hexdigest()
                if is_root and root_rel is None:
                    root_rel = rel
                saved[final] = (seq[url], rel, len(body))
                saved.setdefault(url, saved[final])
                rep.echo(f"saved {rel}  ({len(body)} B)")
                is_css = "css" in low or rel.endswith(".css")
                if ("html" in low or is_css) and len(saved) < MAX_FILES:
                    for link in _links(body.decode("utf-8", "replace"), final, is_css):
                        queue(ex, link)
    # SPA fallback: Pages answers an unknown route with the root document (status 200). Such copies of the root
    # page are not real files - drop them (checked after the crawl so the order of the threads cannot matter).
    if root_rel:
        for rel, d in list(digests.items()):
            if rel != root_rel and d == digests[root_rel]:
                try: (out / rel).unlink()
                except OSError: pass
                for u in [u for u, v in saved.items() if v[1] == rel]: del saved[u]
                skipped += 1
    return saved, failed, skipped, stopped


def recover_pages(name, token, account, out, rep):
    say = rep.say
    say(f"\n[1/3] Finding the latest production deployment of '{name}'...")
    dep = _deployment(name, token, account)
    base_url = dep["url"].rstrip("/")
    say(f"  deployment id : {dep.get('id')}")
    say(f"  created (UTC) : {dep.get('created_on')}")
    say(f"  url           : {base_url}")

    say(f"\n[2/3] Downloading publicly accessible files ({WORKERS} threads)...")
    out.mkdir(parents=True)
    try:
        saved, failed, skipped, stopped = _crawl(base_url, out, rep)
        if stopped:
            say(f"  STOPPED at {MAX_FILES} URLs (safety limit).")
        files = sorted({v for v in saved.values()})                      # unique (seq, rel, size), discovery order
        if not files:
            raise RecoverError("nothing could be downloaded (is the deployment behind Cloudflare Access, or empty?)")

        say("\n[3/3] Writing report...")
        lines = [f"Cloudflare Pages recovery: {name}", f"deployment id : {dep.get('id')}",
                 f"created (UTC) : {dep.get('created_on')}", f"source url    : {base_url}",
                 f"files saved   : {len(files)}", f"duplicate/fallback responses skipped: {skipped}", "",
                 "WARNING: this mirrors PUBLICLY ACCESSIBLE resources. It cannot recover original source files, the",
                 "original folder structure beyond what the URLs show, _headers, _redirects, Pages Functions or files",
                 "only loaded by JavaScript at runtime. Files are saved byte-for-byte as served.", ""]
        if failed:
            lines += ["FAILED:"] + [f"  {f}" for _, f in sorted(failed)] + [""]
        lines += ["FILES (discovery order):"] + [f"  {n:>5}  {rel}  ({size} B)" for n, rel, size in files]
        (out / "RECOVERY-REPORT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        say(f"  {len(files)} file(s) saved" + (f", {len(failed)} failed (see RECOVERY-REPORT.txt)" if failed else ""))
    except BaseException:
        shutil.rmtree(out, ignore_errors=True)       # never leave a half-mirrored folder: it would be "already recovered"
        raise
