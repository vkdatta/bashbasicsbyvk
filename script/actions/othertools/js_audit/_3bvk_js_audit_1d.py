"""
_3bvk_js_audit_1d.py.py
Audit 1d -- Imported Function in JS-built HTML
           (also covers "1d - Local Func in ES Module HTML"
            and       "1d - Unimported Func in JS-built HTML")

Checks that any function referenced inside a JS template-literal HTML string
(e.g.  `<button onclick="myFunc()">`)  is properly exposed via
window.<name> = ...  when the calling file is an ES module.

Three sub-cases:
  • Imported function used in a JS-built HTML string → must be window-exposed
    in the *destination* (exporting) file.
  • Locally defined function in an ES-module file used in a JS-built HTML
    string → must be window-exposed in *this* file.
  • Function used in a JS-built HTML string that is neither imported nor
    locally defined → missing import (cross-file onclick without import).
"""

import re
from _3bvk_js_audit_helpers import resolve_js_path, rel
from _3bvk_js_audit_constants import _RE_EVT_ATTR, _RE_EVT_CALL, _EVT_KNOWN, _NATIVE_GLOBALS, _JS_KEYWORDS


# ---------------------------------------------------------------------------
# Helper: extract all user-defined function names from an event-attr value
# ---------------------------------------------------------------------------

def _extract_event_functions(attr_value: str) -> list:
    """Return all user-defined function names called in an event-attr value."""
    return [
        m.group(1)
        for m in _RE_EVT_CALL.finditer(attr_value)
        if m.group(1) not in _EVT_KNOWN
    ]


# ---------------------------------------------------------------------------
# Helper: template-literal body extractor
# ---------------------------------------------------------------------------

def _extract_template_literals(source: str) -> list:
    """
    Return the body text (between the backticks, excluding ${...} markers)
    of every top-level template literal in *source*.

    Uses a character-by-character state machine so that:
      - Nested ${...} expressions (including nested template literals and
        strings inside them) are handled correctly.
      - A backtick inside a ${...} expression does NOT close the outer template.
      - The returned body is the raw text as it appears in the source,
        which is exactly what _RE_EVT_ATTR needs to find onclick="...".
    """
    results = []
    i = 0
    n = len(source)

    while i < n:
        if source[i] == '`':
            # Start of a template literal
            i          += 1
            body_start  = i
            depth       = 0
            brace_stack = []

            while i < n:
                ch = source[i]

                if depth == 0:
                    if ch == '\\':
                        i += 2
                        continue
                    if ch == '`':
                        results.append(source[body_start:i])
                        i += 1
                        break
                    if ch == '$' and i + 1 < n and source[i + 1] == '{':
                        depth += 1
                        brace_stack.append(1)
                        i += 2
                        continue
                else:
                    # Inside a ${...} expression
                    if ch in ('"', "'", '`'):
                        quote = ch
                        i    += 1
                        while i < n:
                            c2 = source[i]
                            if c2 == '\\':
                                i += 2
                                continue
                            if c2 == quote:
                                i += 1
                                break
                            if quote == '`' and c2 == '$' and i + 1 < n and source[i + 1] == '{':
                                i    += 2
                                inner = 1
                                while i < n and inner:
                                    if source[i] == '{':
                                        inner += 1
                                    elif source[i] == '}':
                                        inner -= 1
                                    i += 1
                                continue
                            i += 1
                        continue
                    if ch == '{':
                        brace_stack[-1] += 1
                    elif ch == '}':
                        brace_stack[-1] -= 1
                        if brace_stack[-1] == 0:
                            brace_stack.pop()
                            depth -= 1
                i += 1
        else:
            # Skip comments and regular strings so their contents don't
            # confuse the backtick scanner.
            if source[i:i + 2] == '//':
                while i < n and source[i] != '\n':
                    i += 1
            elif source[i:i + 2] == '/*':
                end = source.find('*/', i + 2)
                i   = end + 2 if end != -1 else n
            elif source[i] in ('"', "'"):
                q  = source[i]
                i += 1
                while i < n:
                    if source[i] == '\\':
                        i += 2
                        continue
                    if source[i] == q:
                        i += 1
                        break
                    i += 1
            else:
                i += 1

    return results


# ---------------------------------------------------------------------------
# Audit 1d
# ---------------------------------------------------------------------------

def audit_1d_imported_in_html_string(js_info, all_js, root):
    rows = []

    # Build map: imported name → (ImportSpec, resolved dest_path)
    imported_names = {}
    for imp in js_info.imports:
        dest_path = resolve_js_path(imp.from_path, root, js_info.path)
        for n in imp.names:
            imported_names[n] = (imp, dest_path)

    template_bodies = _extract_template_literals(js_info.source)

    # ------------------------------------------------------------------
    # Sub-check A: imported function used in JS-built HTML string
    # ------------------------------------------------------------------
    if imported_names:
        for tl_body in template_bodies:
            for attr_m in _RE_EVT_ATTR.finditer(tl_body):
                attr_value = attr_m.group(1) or attr_m.group(2) or attr_m.group(3) or ''
                for fname in _extract_event_functions(attr_value):
                    if fname not in imported_names:
                        continue
                    imp, dest_path = imported_names[fname]
                    dest_rel = rel(dest_path) if dest_path else imp.from_path
                    if dest_path and dest_path in all_js:
                        dest_info = all_js[dest_path]
                        if fname not in dest_info.window_globals:
                            rows.append({
                                'Sub Audit': '1d - Imported Func in JS-built HTML',
                                'Source': js_info.rel_path,
                                'Destination': dest_rel,
                                'Status': 'Error',
                                'Comment': (
                                    f'Function {fname!r} is imported from {dest_rel} and used '
                                    f'imperatively in a JS-built HTML string '
                                    f'(e.g. onclick="{fname}()"). It MUST be exposed via '
                                    f'window.{fname} = ... in {dest_rel} for HTML inline events '
                                    f'to reach it, but no window assignment was found.'
                                ),
                                'Suggested Import': '',
                            })
                        else:
                            rows.append({
                                'Sub Audit': '1d - Imported Func in JS-built HTML',
                                'Source': js_info.rel_path,
                                'Destination': dest_rel,
                                'Status': 'OK',
                                'Comment': (
                                    f'Function {fname!r} is imported from {dest_rel}, used in '
                                    f'JS-built HTML, and is correctly window-exposed in {dest_rel}.'
                                ),
                                'Suggested Import': '',
                            })

    # ------------------------------------------------------------------
    # Sub-check B: locally defined function in an ES-module used in
    # a JS-built HTML string but not window-exposed
    # ------------------------------------------------------------------
    if js_info.is_es_module:
        local_funcs = set(js_info.functions.keys())
        if local_funcs:
            for tl_body in template_bodies:
                for attr_m in _RE_EVT_ATTR.finditer(tl_body):
                    attr_value = attr_m.group(1) or attr_m.group(2) or attr_m.group(3) or ''
                    for fname in _extract_event_functions(attr_value):
                        if fname in local_funcs and fname not in js_info.window_globals:
                            rows.append({
                                'Sub Audit': '1d - Local Func in ES Module HTML',
                                'Source': js_info.rel_path,
                                'Destination': '',
                                'Status': 'Error',
                                'Comment': (
                                    f'Function {fname!r} is defined locally in this ES module '
                                    f'file and used in a JS-built HTML string '
                                    f'(e.g. onclick="{fname}()"). In ES modules, inline event '
                                    f'handlers can only reach global (window) functions. '
                                    f'Add `window.{fname} = {fname};` in this file to expose it.'
                                ),
                                'Suggested Import': f'window.{fname} = {fname};',
                            })

    # ------------------------------------------------------------------
    # Sub-check C: function used in a JS-built HTML onclick that is
    # neither imported into this file nor locally defined here.
    # These are cross-file calls where the import statement is missing
    # entirely. Search all_js for where the function is defined/exported
    # and report it so the caller knows what to add.
    # ------------------------------------------------------------------
    already_covered = set(imported_names.keys()) | set(js_info.functions.keys())
    # Also exclude pure JS globals / keywords that _EVT_KNOWN already filters,
    # but _EVT_KNOWN is applied inside _extract_event_functions so by here
    # every fname is already a user-defined name.
    _ALL_KNOWN = _NATIVE_GLOBALS | _JS_KEYWORDS

    for tl_body in template_bodies:
        for attr_m in _RE_EVT_ATTR.finditer(tl_body):
            attr_value = attr_m.group(1) or attr_m.group(2) or attr_m.group(3) or ''
            for fname in _extract_event_functions(attr_value):
                if fname in already_covered:
                    continue
                if fname in _ALL_KNOWN:
                    continue

                # Search all other JS files for definition / export
                exported_in = []
                defined_in  = []
                for fpath, finfo in all_js.items():
                    if fpath == js_info.path:
                        continue
                    if fname in finfo.exports:
                        exported_in.append(finfo.rel_path)
                    elif fname in finfo.functions:
                        defined_in.append(finfo.rel_path)

                if exported_in:
                    origin      = exported_in[0]
                    is_exported = True
                    all_origins = exported_in
                elif defined_in:
                    origin      = defined_in[0]
                    is_exported = False
                    all_origins = defined_in
                else:
                    origin      = None
                    is_exported = False
                    all_origins = []

                if origin:
                    suggested = (
                        f'import {{ {fname} }} from "{origin}";'
                        if is_exported
                        else f'// {fname} found in {origin} but not exported -- add export keyword first.'
                    )
                    comment = (
                        f'Function {fname!r} is used in a JS-built HTML string (onclick) in '
                        f'{js_info.rel_path} but is not imported into this file. '
                        f'It is {"exported" if is_exported else "defined (not exported)"} '
                        f'in: {", ".join(all_origins)}. '
                        f'Add the import so the function is available to this module, '
                        f'then also ensure window.{fname} = {fname} is set in that file.'
                    )
                else:
                    suggested = '// Function not found in any scanned file -- verify name or add source file.'
                    comment = (
                        f'Function {fname!r} is used in a JS-built HTML string (onclick) in '
                        f'{js_info.rel_path} but is not imported and was not found in any '
                        f'scanned JS file. Verify the function name or add the missing source file.'
                    )

                rows.append({
                    'Sub Audit': '1d - Unimported Func in JS-built HTML',
                    'Source': js_info.rel_path,
                    'Destination': origin or '',
                    'Status': 'Error',
                    'Comment': comment,
                    'Suggested Import': suggested,
                })

    return rows
