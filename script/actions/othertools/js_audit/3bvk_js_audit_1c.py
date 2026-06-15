"""
3bvk_js_audit_1c.py.py
Audit 1c -- HTML Inline Event Resolution

For every inline event handler (onclick="...", etc.) found in an HTML file,
checks that the referenced function is:
  1. Defined in at least one loaded JS file.
  2. That JS file is referenced from index.html.
  3. If the script is a module, the function is exposed via window.<name>.
  4. No duplicate definitions cause a load-order race condition.
"""

from 3bvk_js_audit_helpers.py import resolve_script_ref, _find_index_html, rel
from 3bvk_js_audit_helpers.py import HTMLFileInfo


def audit_1c_html_events(html_info, all_js, root):
    rows        = []
    index_html  = _find_index_html(root)
    loaded_scripts = []

    if index_html:
        for sr in HTMLFileInfo(index_html).script_refs:
            rp = resolve_script_ref(sr.src_attr, root, index_html)
            if rp:
                loaded_scripts.append((rp, sr))

    for (event_code, func_names) in html_info.inline_events:
        for fname in func_names:
            definers = [
                (fpath, finfo)
                for fpath, finfo in all_js.items()
                if fname in finfo.functions
            ]

            # Function not found anywhere
            if not definers:
                rows.append({
                    'Sub Audit': '1c - HTML Event Resolution',
                    'Source': html_info.rel_path,
                    'Destination': '',
                    'Status': 'Error',
                    'Comment': (
                        f'{event_code} -- function {fname!r} not found in any JS file.'
                    ),
                    'Suggested Import': '',
                })
                continue

            # Function found but its file is not loaded by index.html
            loaded_definers = [
                (fpath, finfo, sr)
                for (fpath, finfo) in definers
                for (lpath, sr) in loaded_scripts
                if lpath == fpath
            ]

            if not loaded_definers:
                paths_str = ', '.join(rel(fp) for fp, _ in definers)
                rows.append({
                    'Sub Audit': '1c - HTML Event Resolution',
                    'Source': html_info.rel_path,
                    'Destination': paths_str,
                    'Status': 'Error',
                    'Comment': (
                        f'{event_code} -- {fname!r} found only in [{paths_str}] '
                        f'but that JS file is not referred in index.html.'
                    ),
                    'Suggested Import': '',
                })
                continue

            winner_path, winner_info, winner_sr = _resolve_race(
                fname, loaded_definers, loaded_scripts
            )
            winner_rel = rel(winner_path)

            if len(loaded_definers) == 1:
                fpath, finfo, sr = loaded_definers[0]
                if sr.is_module and fname not in finfo.window_globals:
                    rows.append({
                        'Sub Audit': '1c - HTML Event Resolution',
                        'Source': html_info.rel_path,
                        'Destination': rel(fpath),
                        'Status': 'Error',
                        'Comment': (
                            f'{event_code} -- {fname!r} found in {rel(fpath)} which is a '
                            f'module script, but the function is not declared globally using '
                            f'window.{fname} = ... Modular scripts require window-scoped '
                            f'assignments for HTML inline events.'
                        ),
                        'Suggested Import': '',
                    })
                else:
                    rows.append({
                        'Sub Audit': '1c - HTML Event Resolution',
                        'Source': html_info.rel_path,
                        'Destination': rel(fpath),
                        'Status': 'OK',
                        'Comment': (
                            f'{event_code} is defined in source file and respective function '
                            f'{fname!r} is defined in destination file.'
                        ),
                        'Suggested Import': '',
                    })
            else:
                conflict_paths = ', '.join(rel(fp) for fp, _, _ in loaded_definers)
                rows.append({
                    'Sub Audit': '1c - HTML Event Resolution',
                    'Source': html_info.rel_path,
                    'Destination': winner_rel,
                    'Status': 'Error',
                    'Comment': (
                        f'{event_code} -- {fname!r} defined in multiple loaded JS files: '
                        f'[{conflict_paths}]. Winner by race-condition rules: {winner_rel}.'
                    ),
                    'Suggested Import': '',
                })

    return rows


def _resolve_race(fname, loaded_definers, loaded_scripts):
    """
    Determine which definition 'wins' when a function is found in multiple
    loaded scripts, following browser load-order rules.
    """
    ordered = []
    for lpath, lsr in loaded_scripts:
        for fpath, finfo, sr in loaded_definers:
            if lpath == fpath:
                ordered.append((fpath, finfo, sr))

    if not ordered:
        return loaded_definers[-1]

    def globally_exposed(fpath, finfo, sr):
        return (not sr.is_module) or (fname in finfo.window_globals)

    exposed = [(fp, fi, sr) for fp, fi, sr in ordered if globally_exposed(fp, fi, sr)]
    if not exposed:
        non_mod = [(fp, fi, sr) for fp, fi, sr in ordered if not sr.is_module]
        return non_mod[-1] if non_mod else ordered[-1]
    return exposed[-1]
