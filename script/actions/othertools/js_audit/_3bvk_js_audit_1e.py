"""
_3bvk_js_audit_1e.py
Audit 1e -- Missing Imports

Scans every JS file for bare function calls whose names are not:
  • locally defined in the same file
  • already imported
  • a native JS global or keyword
  • a safe string literal
  • defined in a classic (non-module) script that is globally loaded by the
    same HTML page — such functions land on the global scope and are
    available to every other classic script without an import statement

For each genuinely unresolved call, searches all other JS files for where
the function is defined (and whether it is exported), then emits Error rows
with a suggested import statement.
"""

import re
from pathlib import Path

from _3bvk_js_audit_helpers import strip_comments, rel
from _3bvk_js_audit_constants import (
    _JS_KEYWORDS, _NATIVE_GLOBALS, _SAFE_LITERALS,
    _RE_BARE_CALL, _RE_STRING_LITERAL,
    _RE_EVT_ATTR, _RE_EVT_CALL, _EVT_KNOWN,
)
from _3bvk_js_audit_1d import _extract_template_literals, _extract_event_functions


# ---------------------------------------------------------------------------
# Internal _3bvk_js_audit_helpers.py
# ---------------------------------------------------------------------------

def _strip_strings(src):
    """Replace all string literals with spaces so their contents are ignored."""
    return _RE_STRING_LITERAL.sub(lambda m: ' ' * len(m.group()), src)


def _get_imported_names(js_info):
    names = set()
    for imp in js_info.imports:
        if imp.names != ['*']:
            names.update(imp.names)
    return names


def _get_namespace_prefixes(js_info):
    prefixes = set()
    for m in re.finditer(r'\bimport\s*\*\s*as\s+(\w+)\s*from', js_info.source):
        prefixes.add(m.group(1))
    return prefixes


def _relative_import_path(source_path: Path, dest_path: Path, root: Path) -> str:
    try:
        dest_root_rel = '/' + dest_path.relative_to(root).as_posix()
        return dest_root_rel
    except ValueError:
        pass
    rel_path = dest_path.relative_to(source_path.parent)
    s = rel_path.as_posix()
    if not s.startswith('.'):
        s = './' + s
    return s


# ---------------------------------------------------------------------------
# Global-scope name collector
# ---------------------------------------------------------------------------

def collect_html_global_names(html_info, all_js, root):
    """
    Return a set of every function name that is defined in a classic
    (non-module) script loaded by *html_info* and therefore available on the
    global/window scope to every other classic script on the same page.

    Module scripts (is_module=True) are excluded: their top-level names are
    NOT implicitly global, so callers still need an explicit import.

    Only locally-scanned JS files contribute names; remote CDN scripts are
    skipped because their source is not available for static analysis.

    Parameters
    ----------
    html_info : HTMLFileInfo
    all_js    : dict[Path, JSFileInfo]
    root      : project root Path
    """
    from _3bvk_js_audit_helpers import resolve_script_ref

    global_names = set()

    for sr in html_info.script_refs:
        # Modules are scoped — their top-level bindings are NOT global
        if sr.is_module:
            continue
        # Remote scripts cannot be statically analysed
        if sr.is_external:
            continue

        rp = resolve_script_ref(sr.src_attr, root, html_info.path)
        if rp is None or rp not in all_js:
            continue

        finfo = all_js[rp]

        # Collect every function name visible at the top level of this
        # classic script.  We include both finfo.functions (esprima-parsed)
        # and a quick regex sweep so we catch everything regardless of how
        # the parser categorised it.
        global_names.update(finfo.functions.keys())
        clean = strip_comments(finfo.source)
        for m in re.finditer(r'\bfunction\s+(\w+)\s*\(', clean):
            global_names.add(m.group(1))
        for m in re.finditer(
            r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|\w+)\s*=>',
            clean,
        ):
            global_names.add(m.group(1))
        for m in re.finditer(
            r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function\s*\(',
            clean,
        ):
            global_names.add(m.group(1))

    return global_names


# ---------------------------------------------------------------------------
# Audit 1e
# ---------------------------------------------------------------------------

def audit_1e_missing_imports(js_info, all_js, root, html_global_names=None):
    """
    Parameters
    ----------
    js_info           : JSFileInfo for the file being audited
    all_js            : dict[Path, JSFileInfo] for the whole project
    root              : project root Path
    html_global_names : optional set[str] of function names that are defined
                        in classic (non-module) scripts loaded by the page's
                        HTML file.  Functions in this set are available on the
                        global scope at runtime and must NOT be flagged as
                        missing imports, even when they carry no export keyword.
                        Pass None (the default) to preserve existing behaviour
                        for callers that have not yet been updated.
    """
    rows = []

    # Functions injected into global scope by classic <script> tags in the HTML
    # are legitimately callable from every other classic script on the same page
    # without an import.  Treat them like native globals so they are never
    # flagged as missing imports.
    globally_available = set(html_global_names) if html_global_names else set()

    clean  = strip_comments(js_info.source)
    nosstr = _strip_strings(clean)

    locally_defined   = set(js_info.functions.keys())
    already_imported  = _get_imported_names(js_info)
    namespace_aliases = _get_namespace_prefixes(js_info)

    # Broaden locally_defined with extra patterns the esprima/regex parser may miss
    extra_locals = set()
    for m in re.finditer(r'\bfunction\s+(\w+)\s*\(', clean):
        extra_locals.add(m.group(1))
    for m in re.finditer(
        r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|\w+)\s*=>', clean
    ):
        extra_locals.add(m.group(1))
    for m in re.finditer(
        r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function\s*\(', clean
    ):
        extra_locals.add(m.group(1))
    for m in re.finditer(r'(?:^|\n|\{)\s*(\w+)\s*\([^)]*\)\s*\{', clean):
        extra_locals.add(m.group(1))
    locally_defined.update(extra_locals)

    known = (
        locally_defined | already_imported
        | _JS_KEYWORDS | _NATIVE_GLOBALS | _SAFE_LITERALS
        | namespace_aliases
        | globally_available          # classic-script globals: no import needed
    )

    # Collect all bare calls not in the known set
    called_names = set()
    for m in _RE_BARE_CALL.finditer(nosstr):
        name = m.group(1)
        if name not in known:
            called_names.add(name)

    # _strip_strings blanks entire template literals, so any function names
    # that appear only inside JS-built HTML onclick strings (e.g.
    # `<button onclick="toggleDbCol(...)">`) are invisible to _RE_BARE_CALL.
    # Extract them separately from the raw (pre-strip) template literal bodies.
    for tl_body in _extract_template_literals(js_info.source):
        for attr_m in _RE_EVT_ATTR.finditer(tl_body):
            attr_value = attr_m.group(1) or attr_m.group(2) or attr_m.group(3) or ''
            for fname in _extract_event_functions(attr_value):
                if fname not in known:
                    called_names.add(fname)

    if not called_names:
        return rows

    # Resolve each unknown call against all other JS files
    resolution = {}
    for fname in sorted(called_names):
        exported_in = []
        defined_in  = []
        for fpath, finfo in all_js.items():
            if fpath == js_info.path:
                continue
            if fname in finfo.exports:
                exported_in.append((finfo.rel_path, fpath))
            elif fname in finfo.functions:
                defined_in.append((finfo.rel_path, fpath))

        if exported_in:
            resolution[fname] = (exported_in[0][0], True,  exported_in[0][1], exported_in)
        elif defined_in:
            resolution[fname] = (defined_in[0][0],  False, defined_in[0][1],  defined_in)
        else:
            resolution[fname] = None

    # Group by destination file so the suggested import is one line per dest
    dest_groups   = {}
    unknown_names = []

    for fname, res in resolution.items():
        if res is None:
            unknown_names.append(fname)
        else:
            dest_rel, is_exp, dest_abs, found_list = res
            if dest_rel not in dest_groups:
                dest_groups[dest_rel] = {'abs': dest_abs, 'names': []}
            dest_groups[dest_rel]['names'].append((fname, is_exp, found_list))

    # Emit one row per function, merging the suggested import for the group
    for dest_rel, grp in dest_groups.items():
        names_in_grp = sorted(grp['names'], key=lambda x: x[0])
        dest_abs     = grp['abs']

        try:
            rel_import_path = _relative_import_path(js_info.path, dest_abs, root)
        except Exception:
            rel_import_path = dest_rel

        all_exported = [n for n, ex, _ in names_in_grp if ex]
        not_exported = [n for n, ex, _ in names_in_grp if not ex]

        if all_exported:
            suggested = f'import {{ {", ".join(sorted(all_exported))} }} from "{rel_import_path}";'
            if not_exported:
                suggested += (
                    f'\n// NOTE: {", ".join(sorted(not_exported))} found in {dest_rel} '
                    f'but NOT exported -- add export keyword first.'
                )
        else:
            suggested = (
                f'// No exports found in {dest_rel}.\n'
                f'// Functions {", ".join(sorted(n for n, _, _ in names_in_grp))} '
                f'need export keywords added before they can be imported.'
            )

        for i, (fname, is_exp, found_list) in enumerate(names_in_grp):
            found_paths = ', '.join(p for p, _ in found_list)
            if is_exp:
                comment = (
                    f'Function {fname!r} is called in {js_info.rel_path} but is not imported. '
                    f'It is exported from: {found_paths}.'
                )
            else:
                comment = (
                    f'Function {fname!r} is called in {js_info.rel_path} but is not imported. '
                    f'It is defined (but NOT exported) in: {found_paths}. '
                    f'Add "export" keyword to make it importable.'
                )

            rows.append({
                'Sub Audit': '1e - Missing Import',
                'Source': js_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Error',
                'Comment': comment,
                'Suggested Import': suggested if i == 0 else '',
                '_merge_key': (js_info.rel_path, dest_rel),
                '_is_first_in_group': i == 0,
                '_group_size': len(names_in_grp),
            })

    # Functions not found in any file
    for fname in sorted(unknown_names):
        rows.append({
            'Sub Audit': '1e - Missing Import',
            'Source': js_info.rel_path,
            'Destination': '',
            'Status': 'Error',
            'Comment': (
                f'Function {fname!r} is called in {js_info.rel_path} but is not imported '
                f'and not found in any scanned JS file. '
                f'Verify the function name or add the source file.'
            ),
            'Suggested Import': '// Function not found in any scanned file -- cannot suggest import.',
            '_merge_key': (js_info.rel_path, ''),
            '_is_first_in_group': True,
            '_group_size': 1,
        })

    return rows
