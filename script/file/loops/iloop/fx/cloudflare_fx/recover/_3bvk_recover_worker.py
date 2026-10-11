"""_3bvk_recover_worker - the recovery pipeline for ONE worker (download -> source map / unbundle -> wrangler files).

This is the body of the old recover.py main(), unchanged in behaviour, with these differences:
  * it takes everything as arguments (token, account, output folder, project folder) and prompts for nothing
  * a failure raises RecoverError for this worker only, so a multi-worker batch carries on
  * the output folder is created only after the script was downloaded, so a failed download leaves nothing behind
"""
import base64, json, os, re
from _3bvk_recover_api import ApiError, http_get, get_json, split_multipart
from _3bvk_recover_unbundle import HASHED_ASSET, extract_source_map, unbundle
from _3bvk_recover_wasm import wasm_to_wat
from _3bvk_recover_project import (ASSET_RULE_FILES, build_wrangler, copy_project_files, project_identifiers, read_wrangler)
from _3bvk_recover_util import RecoverError, safe_join


def recover_worker(name, token, account, out, project, rep):
    """Recover worker `name` into the (not yet existing) folder `out`. `project` = original project folder or None."""
    say = rep.say
    known = project_identifiers(project) if project else None
    base = f"/accounts/{account}/workers/scripts/{name}"
    say(f"Project folder: {project}" if project else "Project folder: not found (wrangler/_headers/_redirects will NOT be byte-exact)")

    # 1. code ---------------------------------------------------------------
    say(f"\n[1/5] Downloading deployed code for '{name}'...")
    raw = None
    for ep in ("/content/v2", ""):
        try:
            data, ctype = http_get(base + ep, token); raw = (data, ctype); break
        except ApiError as e:
            say(f"  note: {e}")
    if not raw:
        raise RecoverError("could not download the script. Check worker name, account ID and token permissions (Workers Scripts: Read).")
    data, ctype = raw
    for d in ("raw", "config", "src"): (out / d).mkdir(parents=True)
    (out / "raw/worker-content.bin").write_bytes(data)
    parts = split_multipart(data, ctype)
    say(f"  received {len(parts)} part(s): " + ", ".join(f"{n} ({len(b)} B)" for n, b in parts))

    # 2. config -------------------------------------------------------------
    say("\n[2/5] Downloading configuration...")
    settings = None
    for fname, ep in (("settings.json", "/settings"), ("script-settings.json", "/script-settings"),
                      ("subdomain.json", "/subdomain")):
        try:
            j = get_json(base + ep, token)
            (out / "config" / fname).write_text(json.dumps(j, indent=2))
            if fname == "settings.json": settings = j
            say(f"  ok: {fname}")
        except ApiError as e:
            say(f"  skipped {fname}: {e}")

    # 3. versions -----------------------------------------------------------
    say("\n[3/5] Downloading version history...")
    try:
        vl = get_json(base + "/versions", token)
        (out / "config/versions.json").write_text(json.dumps(vl, indent=2))
        res = vl.get("result", {})
        items = res.get("items", res) if isinstance(res, dict) else res
        found_code = 0
        for it in items:
            vid = it.get("id", "")
            if not re.fullmatch(r"[A-Za-z0-9_-]+", vid): continue
            try:
                v = get_json(f"{base}/versions/{vid}", token)
            except ApiError as e:
                say(f"  version {vid}: {e}"); continue
            num = it.get("number", vid)
            vdir = out / "config" / "versions" / str(num)
            vdir.mkdir(parents=True, exist_ok=True)
            (vdir / "version.json").write_text(json.dumps(v, indent=2))
            # some API responses embed module contents; save them if present
            mods = (v.get("result", {}).get("resources", {}) or {}).get("modules") or v.get("result", {}).get("modules") or []
            for m in mods:
                blob = m.get("content_base64") or m.get("content")
                if not blob: continue
                raw_b = base64.b64decode(blob) if m.get("content_base64") else blob.encode()
                (vdir / re.sub(r"[^A-Za-z0-9._-]", "_", m.get("name", "module.js"))).write_bytes(raw_b)
                found_code += 1
        say(f"  {len(items)} version(s) listed; {found_code} module body(ies) were embedded in version details.")
        if not found_code:
            say("  (Cloudflare returned metadata only for older versions - only the latest code is recoverable from the API.)")
    except ApiError as e:
        say(f"  skipped: {e}")

    # 4. recover sources ----------------------------------------------------
    say("\n[4/5] Recovering sources...")
    maps = [(n, b) for n, b in parts if n.endswith(".map")]
    codes = [(n, b) for n, b in parts if not n.endswith(".map")]
    exact = 0
    for n, b in maps:
        (out / "raw" / n).write_bytes(b)
        try:
            k = extract_source_map(b, out / "src-from-map"); exact += k
            say(f"  source map {n}: {k} original file(s) recovered EXACTLY")
        except Exception as e:
            say(f"  could not parse source map {n}: {e}")
    refs = []
    for n, b in codes:
        (out / "raw" / n).write_bytes(b)
        for m in re.findall(rb"sourceMappingURL\s*=\s*([^\s*]+)", b):
            refs.append(f"{n} -> {m.decode('utf-8', 'replace')}")
    if refs and not maps:
        say("  bundle references a source map, but Cloudflare did not return it: " + "; ".join(refs))
        say("  (deploy with upload_source_maps = true to get exact recovery next time)")
    # non-JS modules (wasm, text, data): Cloudflare stores them as "<sha1>-<original name>" and drops the folder.
    asset_map, wat_done = {}, 0
    for n, b in codes:
        if n.endswith((".js", ".mjs", ".cjs")): continue
        m = HASHED_ASSET.match(n)
        orig = m.group(1) if m else n
        asset_map[n] = ("wasm/" if n.endswith(".wasm") else "assets/") + orig
    for n, b in codes:
        if n in asset_map:
            try:
                dest = safe_join(out / "src", asset_map[n]); dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(b)
                say(f"  {n} -> src/{asset_map[n]}")
                if n.endswith(".wasm"):
                    try:
                        wtxt = wasm_to_wat(b, asset_map[n].split("/")[-1])
                        dest.with_suffix(".wat").write_text(wtxt); wat_done += 1
                        say(f"    disassembled -> src/{asset_map[n][:-5]}.wat ({len(wtxt.splitlines())} lines)")
                    except Exception as e:
                        say(f"    could not disassemble {n}: {e}")
            except Exception as e:
                say(f"  ERROR copying {n}: {e}")
    rename_log, approx = [], 0
    keep = os.environ.get("RECOVER_KEEP_SUFFIXES") == "1"
    for n, b in codes:
        if n in asset_map: continue
        try:
            text = b.decode("utf-8", "replace")
            count, skipped = unbundle(text, out / "src", asset_map, rename_log, restore_names=not keep, known=known)
            if count:
                approx += count
                say(f"  {n}: unbundled into {count} app module(s); skipped {skipped} bundled dependency/polyfill module(s)")
            else:
                safe_join(out / "src", n).write_text(text.replace("\r\n", "\n"))
                say(f"  {n}: no bundler markers found; written as-is (already one module, or minified/other bundler)")
        except Exception as e:
            import traceback
            say(f"  ERROR while processing {n}: {e}\n" + traceback.format_exc())
    if rename_log:
        (out / "RENAMES.txt").write_text("Identifiers whose esbuild collision suffix (2, 3, ...) was removed.\n"
                                         "Review if any look wrong; set RECOVER_KEEP_SUFFIXES=1 to disable.\n"
                                         + ("Names were checked against the project source in " + str(project) + ".\n\n" if project else
                                            "No project source was available: a name like `x2` is restored to `x` when `x` is bound in an enclosing\n"
                                            "scope, which cannot be told apart from an author-chosen `x2`. Pass --project to resolve this exactly.\n\n") + "\n".join(rename_log) + "\n")
        say(f"  restored {len(rename_log)} original identifier name(s) (see RENAMES.txt)")
    if exact: say(f"  => exact originals in src-from-map/ (use these instead of src/)")
    # keep the entry file name consistent with wrangler main
    entry = out / "src/worker.js"
    if not entry.exists():
        cands = sorted((out / "src").glob("*.js"))
        main_name = next((c.name for c in cands if c.name in ("index.js", "main.js")), cands[0].name if cands else "worker.js")
    else:
        main_name = "worker.js"

    # 5. wrangler / headers / redirects -------------------------------------
    say("\n[5/5] Project configuration...")
    gtext, secrets = build_wrangler(name, settings)
    gtext = gtext.replace('"src/worker.js"', f'"src/{main_name}"')
    copied = []
    if project:
        try:
            copied = copy_project_files(project, out)
        except Exception as e:
            say(f"  ERROR copying project files: {e}")
    if copied:
        for rel, digest, size in copied: say(f"  copied byte-for-byte: {rel} ({size} B, sha256 {digest[:16]}...)")
        missing = [f for f in ASSET_RULE_FILES if not any(r.endswith(f) for r, _, _ in copied)]
        if missing: say("  not present in the project (nothing to copy): " + ", ".join(missing))
        (out / "config" / "wrangler.generated.jsonc").write_text(gtext)
        say("  (settings rebuilt from the Cloudflare API saved as config/wrangler.generated.jsonc for comparison only)")
        for r, _, _ in copied:
            if r.startswith("wrangler."):
                main = read_wrangler(out / r).get("main")
                if main and not (out / main).exists():
                    say(f"  WARNING: {r} has main = {main!r} but that file is not in the recovered output - adjust the path.")
    else:
        (out / "wrangler.jsonc").write_text(gtext)
        say("  WARNING: wrangler.jsonc was REBUILT from Cloudflare settings - it is not the original file (comments,")
        say("  formatting, cron triggers, routes, custom domains, migrations and _headers/_redirects are not recoverable")
        say("  from the API). Re-run with --project <original folder> for byte-exact copies.")
    say(f"  secrets to re-set: {', '.join(secrets) if secrets else 'none'}")

    say("\nDone. Output: " + str(out))
    say("Next: cd into it, run `npx wrangler deploy --dry-run`, diff against live behavior, then commit to git.")
    say("Lost for good without a source map: comments, TypeScript types, original formatting, package.json, tests.")
    (out / "RECOVERY-REPORT.txt").write_text(rep.text())
