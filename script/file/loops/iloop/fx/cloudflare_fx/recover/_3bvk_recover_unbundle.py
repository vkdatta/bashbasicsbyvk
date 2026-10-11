"""_3bvk_recover_unbundle - split an esbuild bundle into per-module ES files; extract exact files from a source map."""
import json, os, re
from pathlib import Path
from _3bvk_recover_jslex import (SUFFIXED, RESERVED, _ID, clean, lex_idents, occ_kind, apply_positions, restore_undefined)
from _3bvk_recover_names import restore_local_names
from _3bvk_recover_util import safe_join, relimport

MARKER = re.compile(r'(?m)(?:^|(?<=\n\n))// ((?:[\w@.+\-]+/)*[\w@.+\-]+\.(?:m?js|cjs|tsx?|jsx|json))\n')
DECL = re.compile(r'^(?:async\s+)?(?:function\*?|class|var|let|const)\s+([A-Za-z_$][\w$]*)', re.M)
IMPORT_LOCALS = re.compile(r'^import\s+(?:([A-Za-z_$][\w$]*)\s*(?:,|\s+from)|\*\s+as\s+([A-Za-z_$][\w$]*)|\{([^}]*)\})', re.M)
VENDOR_HINTS = ("node_modules/", ".npm/", "_virtual", "unenv", "/.wrangler/")
HASHED_ASSET = re.compile(r'^[0-9a-f]{40}-(.+)$')

def classify(marker):
    """('app'|'vendor', safe relative path). Never returns a path that can escape the output dir."""
    if any(h in marker for h in VENDOR_HINTS): return "vendor", None
    parts = [x for x in marker.replace("\\", "/").split("/") if x not in ("", ".")]
    up = 0
    while parts and parts[0] == "..": parts.pop(0); up += 1
    parts = [x for x in parts if x != ".."]
    if not parts: return "vendor", None
    rel = "/".join(parts)
    if up: rel = "external/" + rel
    elif rel.startswith("src/"): rel = rel[4:]
    return "app", rel


def unbundle(text, out_src, asset_map=None, log=None, restore_names=True, known=None):
    """Returns (app_modules_written, vendor_modules_skipped); (0, 0) if no esbuild markers."""
    asset_map, log = asset_map or {}, log if log is not None else []
    text = text.replace("\r\n", "\n")
    text = re.sub(r'\n//# sourceMappingURL=.*\n?$', "\n", text)
    ms = list(MARKER.finditer(text))
    if not ms: return 0, 0
    mods = {}
    for i, m in enumerate(ms):
        end = ms[i + 1].start() if i + 1 < len(ms) else len(text)
        mods[m.group(1)] = mods.get(m.group(1), "") + text[m.end():end]
    entry = ms[-1].group(1)
    tail = re.search(r'\nexport \{([^}]*)\};?\s*$', mods[entry])
    final = []
    if tail:
        mods[entry] = mods[entry][:tail.start()] + "\n"
        for item in tail.group(1).split(","):
            item = item.strip()
            if item: final.append(re.split(r"\s+as\s+", item) if " as " in item else [item, item])
    kind = {k: classify(k) for k in mods}
    mods = {k: clean(v) for k, v in mods.items()}
    app = [k for k in mods if kind[k][0] == "app"]
    decl, idents, all_top = {}, {}, set()
    for k, c in mods.items():
        for n in DECL.findall(c): decl.setdefault(n, k); all_top.add(n)
        for mm in re.finditer(r'^(?:var|let|const)\s*([\[{][^=]*?[\]}])\s*=', c, re.M):   # top-level destructuring
            keys = set(re.findall(r'([A-Za-z_$][\w$]*)\s*:', mm.group(1)))
            all_top.update(set(_ID.findall(mm.group(1))) - keys)
        for a, b, cc in IMPORT_LOCALS.findall(c):
            all_top.update(x for x in (a, b) if x)
            for part in cc.split(","):
                part = part.strip()
                if part: all_top.add(re.split(r"\s+as\s+", part)[-1].strip())
    lex = {k: lex_idents(c) for k, c in mods.items()}
    for k in mods: idents[k] = {o[2] for o in lex[k][0] if occ_kind(o) in ("var", "shorthand")}
    edges = {}
    for k in mods:
        for n in idents[k]:
            owner = decl.get(n)
            if owner and owner != k: edges.setdefault((k, owner), set()).add(n)
    # ---- restore original names that esbuild suffixed with 2, 3, ... to avoid cross-module collisions
    occs = {k: lex[k][0] for k in app}
    M = {k: {} for k in app}
    positions = {k: [] for k in app}
    if restore_names:
        toks = {k: {o[2] for o in occs[k] if occ_kind(o) in ("var", "shorthand")} for k in app}
        shorthand = {k: {o[2] for o in occs[k] if occ_kind(o) == "shorthand"} for k in app}
        for local, alias in final:                      # exact evidence: esbuild keeps public export names
            k = decl.get(local)
            if k in M and local != alias and alias not in RESERVED and alias not in toks[k] and local not in shorthand[k]:
                M[k][local] = alias; toks[k].add(alias)
        for k in app:
            best = {}
            for name in sorted(toks[k]):
                m = SUFFIXED.match(name)
                if not m or name in M[k] or name in shorthand[k]: continue
                base, num = m.group(1), int(m.group(2))
                if num < 2 or base in RESERVED or base not in all_top or base in toks[k]: continue
                if known is not None and (name in known or base not in known): continue
                if base not in best or num < best[base][0]: best[base] = (num, name)
            for base, (_, name) in best.items():
                M[k][name] = base; toks[k].add(base)
        for k in app:
            for old, new in sorted(M[k].items()): log.append(f"{kind[k][1]}: {old} -> {new}")
            positions[k] += [(o[0], o[1], M[k][o[2]]) for o in occs[k] if o[2] in M[k] and occ_kind(o) == "var"]
        # Local (function/block scoped) names. esbuild renames a nested binding `X` to `X2`, `X3`... only when an
        # ENCLOSING scope (or a module top-level name) already owns `X`. So `X2 -> X` is exactly reversible when
        #   (a) `X` is bound in a strictly enclosing scope (or at module top level), and
        #   (b) `X` is not referenced anywhere inside the scope that owns `X2` (otherwise the two would collide).
        # A name like `mainSql2` whose plain `mainSql` is NOT in an enclosing scope is the author's own and is kept.
        for k in app:
            restore_local_names(k, kind[k][1], mods[k], lex[k], M[k], all_top, positions[k], log, known)
        for k in app:
            if positions[k]: mods[k] = apply_positions(mods[k], positions[k])
    new_name = lambda k, n: M.get(k, {}).get(n, n)
    exported = {}
    for (u, o), ns in edges.items(): exported.setdefault(o, set()).update(ns)
    for local, alias in final:
        if local in decl and not (alias == "default" and decl[local] == entry): exported.setdefault(decl[local], set()).add(local)
    written = skipped = 0
    for k, code in mods.items():
        if kind[k][0] == "vendor": skipped += 1; continue
        rel_k = kind[k][1]
        if known is None or "undefined" in known: code = restore_undefined(code)
        for old in sorted(exported.get(k, ())):
            n = new_name(k, old)
            code = re.sub(r'^var ' + re.escape(n) + r' = class\b', "export class " + n, code, flags=re.M)
            code = re.sub(r'^((?:async\s+)?function\*?\s+' + re.escape(n) + r'\b)', r'export \1', code, flags=re.M)
            code = re.sub(r'^(var|let|const)\s+' + re.escape(n) + r'\b', r'export \1 ' + n, code, flags=re.M)
        code = re.sub(r'(export class \w+ [^\n]*\{[\s\S]*?\n)\};\n', r'\1}\n', code)
        def asset(m):                                   # hashed asset import -> original-looking relative path
            rel = asset_map.get(m.group(3))
            return f'{m.group(1)}{m.group(2)}{relimport(rel_k, rel) if rel else "./" + m.group(3)}{m.group(2)}'
        code = re.sub(r'(from\s+)(["\'])\./([0-9a-f]{40}-[^"\']+)\2', asset, code)
        head = []
        for (u, o), ns in sorted(edges.items()):
            if u != k: continue
            if kind[o][0] == "vendor":
                head.append("// uses bundled dependency/polyfill code: " + ", ".join(sorted(ns)[:8]) + (" ..." if len(ns) > 8 else ""))
            else:
                specs = []
                for n in sorted(ns, key=lambda x: new_name(o, x)):
                    a, b = new_name(o, n), new_name(k, n)
                    specs.append(a if a == b else f"{a} as {b}")
                head.append('import { %s } from "%s";' % (", ".join(specs), relimport(rel_k, kind[o][1])))
        if k == entry:
            for local, alias in final:
                o = decl.get(local)
                if alias == "default" and o == k:
                    code = re.sub(r'^var ' + re.escape(local) + r' = ', "export default ", code, count=1, flags=re.M)
                elif o and kind[o][0] == "app" and o != k:
                    ln = new_name(o, local)
                    spec = ln if ln == alias else f"{ln} as {alias}"
                    head.append('export { %s } from "%s";' % (spec if alias != "default" else f"{ln} as default", relimport(rel_k, kind[o][1])))
        dest = safe_join(out_src, rel_k)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("\n".join(head) + ("\n\n" if head else "") + code)
        written += 1
    return written, skipped

def extract_source_map(map_bytes, out_dir):
    obj = json.loads(map_bytes)
    n = 0
    for s, c in zip(obj.get("sources", []), obj.get("sourcesContent") or []):
        if c is None: continue
        parts = [x for x in re.sub(r"^[\w+.-]+://", "", s).split("/") if x not in ("", ".", "..")]
        if not parts: continue
        dest = out_dir.joinpath(*parts)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(c); n += 1
    return n

