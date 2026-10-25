#!/usr/bin/env python3
"""A small in-memory GitHub REST API for the tests (AGENTS: tests never touch the internet).
It speaks only what bashbasicsbyvk_github uses, and is deliberately STRICT where GitHub is strict:
  - a release whose tag_name does not exist is refused (422), so the tool must create the tag first
  - creating a ref that exists is refused (422); a non-forced ref update that is not a fast-forward is refused
  - a download redirected to another host must arrive WITHOUT the Authorization header (the second server records it)
Failure injection:  state.fail["patch_release"] = {"tag_name_to_fail"}  makes PATCH of that release answer 500 (rollback tests).
"""
import hashlib, json, re, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

GOOD = "good-token"
USER = {"login": "tester", "id": 4242, "name": "Test Er", "email": None}


def sha_of(*parts):
    return hashlib.sha1(json.dumps(parts, sort_keys=True).encode()).hexdigest()


class Repo:
    def __init__(self, full, private=False, fork=False, archived=False, desc=""):
        self.full, self.private, self.fork, self.archived, self.desc = full, private, fork, archived, desc
        self.default_branch = "main"
        self.commits, self.tag_objs, self.tags, self.branches, self.releases, self.assets = {}, {}, {}, {}, [], {}
        self.next_id = 100

    def commit(self, msg, parents=(), tree=None, author=None, committer=None):
        author = author or {"name": "Ann", "email": "ann@x", "date": "2026-01-01T00:00:00Z"}
        c = {"message": msg, "tree": {"sha": tree or sha_of("tree", msg)}, "parents": [{"sha": p} for p in parents],
             "author": author, "committer": committer or author}
        s = sha_of("commit", c["message"], c["tree"]["sha"], [p["sha"] for p in c["parents"]], author, c["committer"])
        c["sha"] = s
        self.commits[s] = c
        return s

    def rid(self):
        self.next_id += 1
        return self.next_id


class State:
    def __init__(self):
        self.repos, self.fail, self.blob_seen, self.log = {}, {}, [], []
        self.delay = 0.0                        # seconds each API call takes (a real network is slow: the loading bar must survive that)
        self.blob_port = 0

    def add(self, full, **kw):
        r = Repo(full, **kw); self.repos[full] = r; return r


def make_handler(state):
    class H(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        def log_message(self, *a): pass

        # -- plumbing
        def _send(self, code, obj=None, headers=None, raw=None, ctype="application/json"):
            body = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else b"")
            self.send_response(code)
            if body:
                self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def _body(self):
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n).decode() or "{}") if n else {}

        def _page(self, items, qs):
            per = int(qs.get("per_page", ["30"])[0]); page = int(qs.get("page", ["1"])[0])
            chunk = items[(page - 1) * per: page * per]
            hdr = {}
            if page * per < len(items):
                u = urlparse(self.path); q = dict((k, v[0]) for k, v in parse_qs(u.query).items()); q["page"] = str(page + 1)
                hdr["Link"] = '<http://127.0.0.1:%d%s?%s>; rel="next"' % (self.server.server_port, u.path, "&".join("%s=%s" % kv for kv in q.items()))
            self._send(200, chunk, hdr)

        def _route(self, method):
            u = urlparse(self.path); qs = parse_qs(u.query); p = unquote(u.path)
            state.log.append((method, p))
            if state.delay:
                time.sleep(state.delay)
            if self.headers.get("Authorization") != "Bearer " + GOOD:
                return self._send(401, {"message": "Bad credentials"})
            if p == "/user":
                return self._send(200, USER)
            if p == "/user/repos" and method == "GET":
                items = [{"full_name": r.full, "private": r.private, "fork": r.fork, "archived": r.archived, "is_template": False,
                          "description": r.desc, "pushed_at": "2026-10-%02dT10:00:00Z" % (10 + i)} for i, r in enumerate(state.repos.values())]
                return self._page(items, qs)
            m = re.match(r"^/repos/([^/]+/[^/]+)(/.*)?$", p)
            if not m or m.group(1) not in state.repos:
                return self._send(404, {"message": "Not Found"})
            R, rest = state.repos[m.group(1)], m.group(2) or ""
            return self._repo(method, R, rest, qs)

        def _repo(self, method, R, rest, qs):
            if rest == "" and method == "GET":
                return self._send(200, {"default_branch": R.default_branch, "full_name": R.full})
            # releases
            if rest == "/releases" and method == "GET":
                return self._page([self._rel(R, r) for r in R.releases], qs)
            if rest == "/releases" and method == "POST":
                b = self._body()
                if any(r["tag_name"] == b["tag_name"] for r in R.releases):
                    return self._send(422, {"message": "Validation Failed", "errors": [{"code": "already_exists"}]})
                if b["tag_name"] not in R.tags:                       # real GitHub makes a lightweight tag at target_commitish
                    tgt = b.get("target_commitish") or R.default_branch
                    sha = R.branches.get(tgt) or (tgt if tgt in R.commits else None)
                    if not sha:
                        return self._send(422, {"message": "target_commitish invalid"})
                    R.tags[b["tag_name"]] = ("commit", sha)
                r = {"id": R.rid(), "tag_name": b["tag_name"], "name": b.get("name"), "body": b.get("body"), "draft": bool(b.get("draft")),
                     "prerelease": bool(b.get("prerelease")), "published_at": "2026-10-20T00:00:00Z", "created_at": "2026-10-20T00:00:00Z", "assets": []}
                R.releases.append(r)
                return self._send(201, self._rel(R, r))
            mm = re.match(r"^/releases/(\d+)$", rest)
            if mm:
                r = next((x for x in R.releases if x["id"] == int(mm.group(1))), None)
                if not r:
                    return self._send(404, {"message": "Not Found"})
                if method == "DELETE":
                    R.releases.remove(r); return self._send(204)
                if method == "PATCH":
                    b = self._body()
                    if r["tag_name"] in state.fail.get("patch_release", ()):
                        return self._send(500, {"message": "boom"})
                    if "tag_name" in b:
                        if b["tag_name"] not in R.tags:
                            return self._send(422, {"message": "tag does not exist"})
                        if any(x is not r and x["tag_name"] == b["tag_name"] for x in R.releases):
                            return self._send(422, {"message": "tag already used by another release"})
                    r.update({k: v for k, v in b.items() if k in ("tag_name", "name", "body", "draft", "prerelease")})
                    return self._send(200, self._rel(R, r))
            mm = re.match(r"^/releases/assets/(\d+)$", rest)
            if mm and method == "GET":
                if mm.group(1) not in R.assets:
                    return self._send(404, {"message": "Not Found"})
                return self._send(302, headers={"Location": "http://127.0.0.1:%d/blob/%s" % (state.blob_port, mm.group(1))})
            # tags / refs
            mm = re.match(r"^/git/matching-refs/(tags|heads)$", rest)
            if mm and method == "GET":
                if mm.group(1) == "tags":
                    items = [{"ref": "refs/tags/" + n, "object": {"type": t, "sha": s}} for n, (t, s) in R.tags.items()]
                else:
                    items = [{"ref": "refs/heads/" + n, "object": {"type": "commit", "sha": s}} for n, s in R.branches.items()]
                return self._page(items, qs)
            mm = re.match(r"^/git/ref/tags/(.+)$", rest)
            if mm and method == "GET":
                n = mm.group(1)
                if n not in R.tags:
                    return self._send(404, {"message": "Not Found"})
                t, s = R.tags[n]
                return self._send(200, {"ref": "refs/tags/" + n, "object": {"type": t, "sha": s}})
            if rest == "/git/refs" and method == "POST":
                b = self._body(); n = b["ref"][len("refs/tags/"):]
                if n in R.tags:
                    return self._send(422, {"message": "Reference already exists"})
                typ = "tag" if b["sha"] in R.tag_objs else "commit" if b["sha"] in R.commits else None
                if not typ:
                    return self._send(422, {"message": "Object does not exist"})
                R.tags[n] = (typ, b["sha"]); return self._send(201, {"ref": b["ref"]})
            mm = re.match(r"^/git/refs/(tags|heads)/(.+)$", rest)
            if mm:
                kind, n = mm.groups(); store = R.tags if kind == "tags" else R.branches
                if n not in store:
                    return self._send(404, {"message": "Reference does not exist"})
                if method == "DELETE":
                    del store[n]; return self._send(204)
                if method == "PATCH":
                    b = self._body(); sha = b["sha"]
                    typ = "tag" if sha in R.tag_objs else "commit" if sha in R.commits else None
                    if not typ:
                        return self._send(422, {"message": "Object does not exist"})
                    store[n] = (typ, sha) if kind == "tags" else sha
                    return self._send(200, {"ref": "refs/%s/%s" % (kind, n)})
            mm = re.match(r"^/git/tags/([0-9a-f]+)$", rest)
            if mm and method == "GET":
                t = R.tag_objs.get(mm.group(1))
                return self._send(200, t) if t else self._send(404, {"message": "Not Found"})
            if rest == "/git/tags" and method == "POST":
                b = self._body()
                if not b.get("tagger"):
                    return self._send(422, {"message": "tagger required in this mock"})
                if b["object"] not in R.commits and b["object"] not in R.tag_objs:
                    return self._send(422, {"message": "object does not exist"})
                t = {"tag": b["tag"], "message": b["message"], "tagger": b["tagger"], "object": {"type": b["type"], "sha": b["object"]}}
                t["sha"] = sha_of("tag", t); R.tag_objs[t["sha"]] = t
                return self._send(201, t)
            mm = re.match(r"^/git/commits/([0-9a-f]+)$", rest)
            if mm and method == "GET":
                c = R.commits.get(mm.group(1))
                return self._send(200, c) if c else self._send(404, {"message": "Not Found"})
            if rest == "/git/commits" and method == "POST":
                b = self._body()
                s = R.commit(b["message"], [x for x in b["parents"]], b["tree"], b.get("author"), b.get("committer"))
                return self._send(201, R.commits[s])
            mm = re.match(r"^/commits/(.+)$", rest)
            if mm and method == "GET":
                ref = mm.group(1)
                sha = R.branches.get(ref) or (R.tags[ref][1] if ref in R.tags and R.tags[ref][0] == "commit" else None) or (ref if ref in R.commits else None)
                return self._send(200, {"sha": sha}) if sha else self._send(404, {"message": "No commit found for SHA: " + ref})
            return self._send(404, {"message": "Not Found (mock has no %s %s)" % (method, rest)})

        def _rel(self, R, r):
            out = dict(r); out["html_url"] = "https://github.test/%s/releases/tag/%s" % (R.full, r["tag_name"])
            out["assets"] = [{"id": int(i), "name": n} for i, (n, _) in R.assets.items() if i.startswith(str(r["id"]))]
            return out

        def do_GET(self): self._route("GET")
        def do_POST(self): self._route("POST")
        def do_PATCH(self): self._route("PATCH")
        def do_DELETE(self): self._route("DELETE")
    return H


def make_blob_handler(state):
    class B(BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def do_GET(self):
            state.blob_seen.append(self.headers.get("Authorization"))
            data = state.blobs.get(self.path.rsplit("/", 1)[-1], b"")
            self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    return B


def start(state):
    """-> (api_base, stop())"""
    state.blobs = {}
    api = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(state))
    blob = ThreadingHTTPServer(("127.0.0.1", 0), make_blob_handler(state))
    state.blob_port = blob.server_port
    for s in (api, blob):
        threading.Thread(target=s.serve_forever, daemon=True).start()
    def stop():
        for s in (api, blob):
            s.shutdown(); s.server_close()
    return "http://127.0.0.1:%d" % api.server_port, stop
