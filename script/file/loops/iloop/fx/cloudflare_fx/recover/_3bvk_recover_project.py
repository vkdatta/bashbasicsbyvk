"""_3bvk_recover_project - wrangler config (rebuilt from the API, or copied byte-for-byte from the project folder),
_headers / _redirects, and the project's own identifiers. Project lookup is locked to the NAVIGATION path."""
import json, os, re
from pathlib import Path
from _3bvk_recover_util import safe_join
from _3bvk_recover_jslex import _ID

def build_wrangler(name, settings):
    s = settings.get("result", {}) if settings else {}
    cfg = {"name": name, "main": "src/worker.js", "compatibility_date": s.get("compatibility_date")}
    if s.get("compatibility_flags"): cfg["compatibility_flags"] = s["compatibility_flags"]
    if s.get("usage_model") == "standard": pass
    v, do, kv, r2, d1, svc, qp, wf, ae, hd, vz, secrets, other = {}, [], [], [], [], [], [], [], [], [], [], [], []
    for b in s.get("bindings", []):
        t, n = b.get("type"), b.get("name")
        if t == "plain_text": v[n] = b.get("text")
        elif t == "json": v[n] = b.get("json")
        elif t == "secret_text": secrets.append(n)
        elif t == "durable_object_namespace":
            e = {"name": n, "class_name": b.get("class_name")}
            if b.get("script_name"): e["script_name"] = b["script_name"]
            do.append(e)
        elif t == "kv_namespace": kv.append({"binding": n, "id": b.get("namespace_id")})
        elif t == "r2_bucket": r2.append({"binding": n, "bucket_name": b.get("bucket_name")})
        elif t == "d1": d1.append({"binding": n, "database_id": b.get("id")})
        elif t == "service": svc.append({"binding": n, "service": b.get("service")})
        elif t == "queue": qp.append({"binding": n, "queue": b.get("queue_name")})
        elif t == "workflow":
            e = {"binding": n, "name": b.get("workflow_name"), "class_name": b.get("class_name")}
            if b.get("script_name"): e["script_name"] = b["script_name"]
            wf.append(e)
        elif t == "ai": cfg["ai"] = {"binding": n}
        elif t == "analytics_engine": ae.append({"binding": n, "dataset": b.get("dataset")})
        elif t == "hyperdrive": hd.append({"binding": n, "id": b.get("id")})
        elif t == "vectorize": vz.append({"binding": n, "index_name": b.get("index_name")})
        elif t == "browser": cfg["browser"] = {"binding": n}
        else: other.append(f"{n} ({t})")
    for key, val in (("vars", v), ("kv_namespaces", kv), ("r2_buckets", r2), ("d1_databases", d1),
                     ("services", svc), ("workflows", wf), ("analytics_engine_datasets", ae),
                     ("hyperdrive", hd), ("vectorize", vz)):
        if val: cfg[key] = val
    if qp: cfg["queues"] = {"producers": qp}
    if do:
        cfg["durable_objects"] = {"bindings": do}
        cfg["migrations"] = [{"tag": "v1", "new_classes": sorted({x["class_name"] for x in do if not x.get("script_name")})}]
    obs = s.get("observability")
    if obs: cfg["observability"] = {"enabled": bool(obs.get("enabled"))}
    cfg["upload_source_maps"] = True
    text = json.dumps(cfg, indent=2) + "\n"
    if secrets: text += "// Secrets - re-set with `wrangler secret put <NAME>`: " + ", ".join(secrets) + "\n"
    if other: text += "// Bindings needing manual review: " + ", ".join(other) + "\n"
    text += "// Check: cron triggers, routes and custom domains are NOT recovered here.\n"
    return text, secrets

# ------------------------------------------------------------ local project -
# wrangler config and the static-asset rules files are the most important files of a project and are NOT stored in
# Cloudflare in their original form (only parsed settings are). When the original project folder is available they are
# copied BYTE FOR BYTE (never regenerated, re-encoded, re-indented or newline-converted), and the project's identifiers
# are used to tell names the author wrote (`mainSql2`) from suffixes esbuild added (`dk2`).
WRANGLER_FILES = ("wrangler.jsonc", "wrangler.json", "wrangler.toml")
ASSET_RULE_FILES = ("_headers", "_redirects")
SKIP_DIRS = {"node_modules", ".git", ".wrangler", ".svn", ".hg", "__pycache__"}
SRC_EXT = (".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx", ".mts", ".cts")

def strip_jsonc(text):
    """Remove // and /* */ comments and trailing commas from JSONC (string-aware) so json.loads can read it."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"': j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1]); i = j + 1; continue
        if c == "/" and text[i + 1:i + 2] == "/":
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if c == "/" and text[i + 1:i + 2] == "*":
            j = text.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

def read_wrangler(path):
    """Tolerant read of a wrangler config -> dict (only used to learn name / assets dir; the file itself is copied raw)."""
    try:
        text = Path(path).read_bytes().decode("utf-8", "replace").lstrip("\ufeff")
        if str(path).endswith(".toml"):
            cfg, table = {}, None
            for line in text.splitlines():
                line = line.split("#", 1)[0].strip()
                m = re.match(r"^\[([^\[\]]+)\]$", line)
                if m: table = m.group(1).strip(); cfg.setdefault(table, {}); continue
                m = re.match(r'^([A-Za-z0-9_.-]+)\s*=\s*"([^"]*)"', line)
                if m: (cfg if table is None else cfg[table])[m.group(1)] = m.group(2)
            return cfg
        return json.loads(strip_jsonc(text))
    except Exception:
        return {}

def find_project(worker, start, explicit=None):
    """Locate the project folder whose wrangler config names this worker. Returns Path or None."""
    def wrangler_in(d):
        return [d / f for f in WRANGLER_FILES if (d / f).is_file()]
    if explicit:
        d = Path(explicit).expanduser().resolve()
        return d if d.is_dir() and wrangler_in(d) else None
    hits, seen = [], set()
    roots = [start]                       # navigation path only (the original also scanned its parent)
    for root in roots:
        for dp, dns, _ in os.walk(root):
            depth = len(Path(dp).relative_to(root).parts)
            dns[:] = sorted(x for x in dns if x not in SKIP_DIRS and not x.endswith("-recovered") and depth < 3)
            d = Path(dp).resolve()
            if d in seen: continue
            seen.add(d)
            for w in wrangler_in(d):
                if read_wrangler(w).get("name") == worker: hits.append(d); break
    return hits[0] if hits else None

def project_identifiers(project):
    """Every identifier-like word in the project's own JS/TS files (what the author actually wrote)."""
    words = set()
    for dp, dns, fns in os.walk(project):
        dns[:] = [x for x in dns if x not in SKIP_DIRS and not x.endswith("-recovered")]
        for f in fns:
            if f.endswith(SRC_EXT):
                try: words.update(_ID.findall(Path(dp, f).read_text("utf-8", "replace")))
                except OSError: pass
    return words

def copy_project_files(project, out):
    """Byte-exact copy of wrangler config + _headers/_redirects. Returns list of (relative path, sha256, size)."""
    import hashlib, shutil
    found = []
    def put(src):
        rel = src.relative_to(project)
        dest = safe_join(out, rel.as_posix())
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
        a, b = src.read_bytes(), dest.read_bytes()
        if a != b: raise RuntimeError(f"byte verification failed for {rel}")
        found.append((rel.as_posix(), hashlib.sha256(a).hexdigest(), len(a)))
    cfgs = [project / f for f in WRANGLER_FILES if (project / f).is_file()]
    for c in cfgs: put(c)
    dirs = {project}
    for c in cfgs:
        cfg = read_wrangler(c)
        a = cfg.get("assets")
        if isinstance(a, dict) and a.get("directory"): dirs.add((project / str(a["directory"])).resolve())
    for sub in ("public", "dist", "static", "build", "out", "assets", "site", "web"): dirs.add(project / sub)
    for d in sorted(dirs):
        try: d.relative_to(project.resolve())
        except ValueError: continue
        for f in ASSET_RULE_FILES:
            if (d / f).is_file(): put(d / f)
    return found
