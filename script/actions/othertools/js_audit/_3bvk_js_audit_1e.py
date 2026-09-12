"""
_3bvk_js_audit_1e.py
Audit 1e -- Missing Imports

Scans every JS file for bare function calls whose names are not:
  - locally defined in the same file
  - already imported
  - a native JS global or keyword
  - a safe string literal
  - defined in a classic (non-module) script that the page's HTML loads
    globally -- such functions are on window scope and need no import

For each genuinely unresolved call, searches all other JS files for where
the function is defined (and whether it is exported), then emits Error rows
with a suggested import statement.
"""

import re
from pathlib import Path

from _3bvk_js_audit_helpers import strip_comments, rel, read_file, resolve_script_ref, _find_index_html
from _3bvk_js_audit_constants import (
    _JS_KEYWORDS, _NATIVE_GLOBALS, _SAFE_LITERALS,
    _RE_BARE_CALL, _RE_STRING_LITERAL,
    _RE_EVT_ATTR, _RE_EVT_CALL, _EVT_KNOWN,
    _RE_COMMENT_BLOCK,
)
from _3bvk_js_audit_1d import _extract_template_literals, _extract_event_functions


# ---------------------------------------------------------------------------
# Internal helpers
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


def _is_external_url(src):
    s = src.strip().lower()
    return s.startswith('http://') or s.startswith('https://') or s.startswith('//')


def _strip_js_comments(src):
    src = _RE_COMMENT_BLOCK.sub('', src)
    return re.sub(r'//[^\n]*', '', src)


# Matches loadScript("url") or loadScript('url') anywhere in the document,
# including inside CDATA blocks and Blogger widget-setting wrappers.
_RE_LOAD_SCRIPT_GLOBAL = re.compile(
    r'(?<![.\w])loadScript\s*\(\s*(?:"([^"]+)"|\'([^\']+)\')\s*[,)]',
    re.MULTILINE,
)
_RE_LOAD_MODULE_GLOBAL = re.compile(
    r'(?<![.\w])loadModule\s*\(\s*(?:"([^"]+)"|\'([^\']+)\')\s*[,)]',
    re.MULTILINE,
)


def _collect_global_names_from_classic_scripts(html_path: Path, all_js: dict, root: Path) -> set:
    """
    Scan the entire HTML file text for every script loaded as a classic
    (non-module) script -- via static <script src>, loadScript(), or any
    equivalent pattern anywhere in the file (including CDATA / Blogger
    widget-setting blocks).

    Collect every function name defined in those scripts.  These names land
    on window/global scope and are legitimately callable from any other
    classic script on the same page without an import.

    loadModule() calls are excluded: module top-level bindings are NOT global.
    Remote/external URLs are skipped (source not available locally).
    """
    global_names = set()

    try:
        html_src = read_file(html_path)
    except Exception:
        return global_names

    script_srcs = []  # list of (src_attr, is_module)

    # 1. Static <script src="..."> tags (existing behaviour)
    _re_script_tag = re.compile(r'<script([^>]*)>', re.IGNORECASE)
    _re_src        = re.compile(r'\bsrc=["\']([^"\']+)["\']', re.IGNORECASE)
    _re_type       = re.compile(r'\btype=["\']([^"\']+)["\']', re.IGNORECASE)
    for m in _re_script_tag.finditer(html_src):
        attrs     = m.group(1)
        src_m     = _re_src.search(attrs)
        type_m    = _re_type.search(attrs)
        is_module = bool(type_m and 'module' in type_m.group(1).lower())
        if src_m:
            script_srcs.append((src_m.group(1), is_module))

    # 2. loadScript("url") calls anywhere in the document (covers CDATA,
    #    Blogger b:widget-setting blocks, inline <script> bodies, etc.)
    for m in _RE_LOAD_SCRIPT_GLOBAL.finditer(html_src):
        src = m.group(1) or m.group(2)
        if src:
            script_srcs.append((src, False))   # classic

    # 3. loadModule("url") calls -- is_module=True, will be excluded below
    for m in _RE_LOAD_MODULE_GLOBAL.finditer(html_src):
        src = m.group(1) or m.group(2)
        if src:
            script_srcs.append((src, True))    # module -- excluded below

    # Build a filename -> JSFileInfo map for fallback matching of CDN URLs
    filename_to_finfo = {}
    for fpath, finfo in all_js.items():
        filename_to_finfo.setdefault(fpath.name, []).append(finfo)

    for src_attr, is_module in script_srcs:
        if is_module:       # modules are scoped, not global
            continue

        finfo = None

        if not _is_external_url(src_attr):
            # Try local path resolution first
            rp = resolve_script_ref(src_attr, root, html_path)
            if rp is not None and rp in all_js:
                finfo = all_js[rp]
        else:
            # For CDN / external URLs, match by filename.
            # e.g. "https://cdn.../notes-state.js" -> notes-state.js in all_js.
            fname = src_attr.rstrip('/').split('/')[-1].split('?')[0]
            candidates = filename_to_finfo.get(fname, [])
            if len(candidates) == 1:
                finfo = candidates[0]
            # If multiple local files share the same name, skip (ambiguous).

        if finfo is None:
            continue

        clean = _strip_js_comments(finfo.source)

        global_names.update(finfo.functions.keys())
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


def _collect_window_globals(all_js) -> set:
    """
    Return the union of window_globals across every JS file in the project.

    Any file -- classic or module -- can do  window.foo = ...  which puts foo
    on the global scope unconditionally.  JSFileInfo already tracks these via
    window_globals; we just aggregate them here.
    """
    names = set()
    for finfo in all_js.values():
        names |= finfo.window_globals
    return names


def _build_html_global_names(js_info, all_js, root) -> set:
    """
    Build the complete set of names that are legitimately on the global scope
    for the page that loads js_info, combining two sources:

    1. Functions defined in classic (non-module) scripts loaded by the HTML --
       these land on window automatically because classic scripts share the
       global scope.

    2. Explicit window.X = ... assignments from ANY JS file (classic or
       module).  A module that does  window.saveFoldState = saveFoldState
       is deliberately publishing to the global scope; callers that reach for
       it as a bare  saveFoldState()  call are correct and must not be flagged.
    """
    html_files = sorted(root.rglob('*.html')) + sorted(root.rglob('*.htm'))

    loading_html = []
    js_name = js_info.path.name
    for html_path in html_files:
        try:
            html_src = read_file(html_path)
        except Exception:
            continue
        if js_name in html_src:
            loading_html.append(html_path)

    if not loading_html:
        idx = _find_index_html(root)
        if idx:
            loading_html = [idx]

    global_names = set()
    for html_path in loading_html:
        global_names |= _collect_global_names_from_classic_scripts(html_path, all_js, root)

    # Explicit window.X = ... assignments from any JS file publish to the
    # global scope regardless of whether the file is a module or classic script.
    global_names |= _collect_window_globals(all_js)

    return global_names


# ---------------------------------------------------------------------------
# Audit 1e
# ---------------------------------------------------------------------------

def audit_1e_missing_imports(js_info, all_js, root):
    rows = []

    # Names globally available via classic scripts loaded by the HTML page --
    # these require no import statement and must not be flagged.
    globally_available = _build_html_global_names(js_info, all_js, root)

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
    # Catch-all: any let/const/var declaration regardless of what it is
    # assigned to.  A variable like  let activeDropdownClose = null  can
    # later hold a function and be called as activeDropdownClose() -- it is
    # local by definition and must never be flagged as a missing import.
    for m in re.finditer(r'\b(?:const|let|var)\s+(\w+)\b', clean):
        extra_locals.add(m.group(1))
    locally_defined.update(extra_locals)

    known = (
        locally_defined | already_imported
        | _JS_KEYWORDS | _NATIVE_GLOBALS | _SAFE_LITERALS
        | namespace_aliases
        | globally_available   # ← classic-script globals: no import needed
    )

    # Collect all bare calls not in the known set
    called_names = set()
    for m in _RE_BARE_CALL.finditer(nosstr):
        name = m.group(1)
        if name not in known:
            called_names.add(name)

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
