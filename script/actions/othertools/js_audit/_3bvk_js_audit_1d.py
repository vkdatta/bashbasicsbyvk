"""
_3bvk_js_audit_1d.py.py
Audit 1d -- Imported Function in JS-built HTML
           (also covers "1d - Local Func in ES Module HTML" and
            "1d - Unimported Func in JS-built HTML")

Checks that any function referenced inside a JS template-literal HTML string
(e.g.  `<button onclick="myFunc()">`)  is properly reachable:
  A) If imported → must be window-exposed in the destination file.
  B) If local in an ES module → must be window-exposed in this file.
  C) If neither imported nor local → must be window-exposed in another file,
     or imported from a file that exports it.
"""

from _3bvk_js_audit_helpers import resolve_js_path, rel, _extract_template_literals
from _3bvk_js_audit_constants import _RE_EVT_ATTR, _RE_EVT_CALL, _EVT_KNOWN


def _extract_event_functions(attr_value: str) -> list:
    """Return all user-defined function names called in an event-attr value."""
    return [
        m.group(1)
        for m in _RE_EVT_CALL.finditer(attr_value)
        if m.group(1) not in _EVT_KNOWN
    ]


def audit_1d_imported_in_html_string(js_info, all_js, root):
    rows = []

    # Build map: imported name → (ImportSpec, resolved dest_path)
    imported_names = {}
    for imp in js_info.imports:
        dest_path = resolve_js_path(imp.from_path, root, js_info.path)
        for n in imp.names:
            imported_names[n] = (imp, dest_path)

    template_bodies = _extract_template_literals(js_info.source)
    local_funcs = set(js_info.functions.keys())

    for tl_body in template_bodies:
        for attr_m in _RE_EVT_ATTR.finditer(tl_body):
            attr_value = attr_m.group(1) or attr_m.group(2) or attr_m.group(3) or ''
            for fname in _extract_event_functions(attr_value):
                
                # ------------------------------------------------------------------
                # Sub-check A: imported function used in JS-built HTML string
                # ------------------------------------------------------------------
                if fname in imported_names:
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
                    continue

                # ------------------------------------------------------------------
                # Sub-check B: locally defined function in an ES-module used in
                # a JS-built HTML string but not window-exposed
                # ------------------------------------------------------------------
                if js_info.is_es_module and fname in local_funcs:
                    if fname not in js_info.window_globals:
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
                    continue

                # ------------------------------------------------------------------
                # Sub-check C: function used in JS-built HTML string but neither
                # imported nor locally defined -- check other files
                # ------------------------------------------------------------------
                found_in    = []
                exported_in = []
                window_in   = []
                for fpath, finfo in all_js.items():
                    if fpath == js_info.path:
                        continue
                    if fname in finfo.functions:
                        found_in.append(finfo.rel_path)
                        if fname in finfo.exports:
                            exported_in.append(finfo.rel_path)
                        elif fname in finfo.window_globals:
                            window_in.append(finfo.rel_path)

                if not found_in:
                    continue

                if window_in:
                    rows.append({
                        'Sub Audit': '1d - Unimported Func in JS-built HTML',
                        'Source': js_info.rel_path,
                        'Destination': ', '.join(window_in),
                        'Status': 'OK',
                        'Comment': (
                            f'Function {fname!r} is used in a JS-built HTML string '
                            f'and is globally available via window.{fname} in '
                            f'{", ".join(window_in)}. No import required for inline events.'
                        ),
                        'Suggested Import': '',
                    })
                elif exported_in:
                    primary = exported_in[0]
                    rows.append({
                        'Sub Audit': '1d - Unimported Func in JS-built HTML',
                        'Source': js_info.rel_path,
                        'Destination': ', '.join(found_in),
                        'Status': 'Error',
                        'Comment': (
                            f'Function {fname!r} is used in a JS-built HTML string '
                            f'(e.g. onclick="{fname}()") but is not imported into '
                            f'{js_info.rel_path}. It is exported from: {", ".join(exported_in)}. '
                            f'Add an import statement or expose it via window.{fname} = ... '
                            f'in the defining file.'
                        ),
                        'Suggested Import': f'import {{ {fname} }} from "{primary}";',
                    })
                else:
                    rows.append({
                        'Sub Audit': '1d - Unimported Func in JS-built HTML',
                        'Source': js_info.rel_path,
                        'Destination': ', '.join(found_in),
                        'Status': 'Error',
                        'Comment': (
                            f'Function {fname!r} is used in a JS-built HTML string '
                            f'(e.g. onclick="{fname}()") but is not imported into '
                            f'{js_info.rel_path}. It is defined in: {", ".join(found_in)} '
                            f'but NOT exported or window-exposed. '
                            f'Add export or window.{fname} = {fname} to make it reachable.'
                        ),
                        'Suggested Import': (
                            f'// Add export or window.{fname} = {fname} to {found_in[0]} first'
                        ),
                    })

    return rows
