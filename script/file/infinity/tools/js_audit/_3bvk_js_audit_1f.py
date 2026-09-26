"""
_3bvk_js_audit_1f.py
Audit 1f -- Script Tag Module Type

For every script dependency (static OR dynamic) in an HTML file, checks
whether the JS file it loads uses ES-module syntax (import/export).  If so,
the dependency must be declared as a module; if it already is but the file
has no ES-module syntax, a warning is emitted.

Dynamic dependencies (loadScript / loadModule / createElement) flow through
the canonical html_info.script_refs; no independent detection is needed here.

Remote/external URLs (http://…, https://…, //…) are recognised as
dependencies but cannot be inspected locally, so module-syntax analysis is
skipped for them.
"""

from _3bvk_js_audit_helpers import resolve_script_ref, rel


def audit_1f_module_script_type(html_info, all_js, root):
    rows = []

    for sr in html_info.script_refs:
        rp = resolve_script_ref(sr.src_attr, root, html_info.path)
        if rp is None or rp not in all_js:
            continue

        finfo    = all_js[rp]
        dest_rel = rel(rp)

        # Build a human-readable description of how this script is loaded
        # (static tag vs dynamic call) for use in error messages.
        # getattr guards: old ScriptRef only has src_attr and is_module;
        # new ones also carry source and loader.
        sr_source = getattr(sr, 'source', 'static')
        sr_loader = getattr(sr, 'loader', None)
        sr_is_mod = getattr(sr, 'is_module', False)

        if sr_source == 'dynamic' and sr_loader:
            load_desc = f'{sr_loader}("{sr.src_attr}")'
        else:
            load_desc = f'<script src="{sr.src_attr}">'

        if finfo.is_es_module and not sr_is_mod:
            uses = []
            if finfo.imports:
                uses.append('import')
            if finfo.exports:
                uses.append('export')
            uses_str = '/'.join(uses) if uses else 'import/export'

            if sr_source == 'dynamic' and sr_loader == 'loadScript':
                suggestion = f'Use loadModule("{sr.src_attr}") instead of loadScript(…)'
            else:
                suggestion = f'<script type="module" src="{sr.src_attr}"></script>'

            rows.append({
                'Sub Audit': '1f - Module Script Type',
                'Source': html_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Error',
                'Comment': (
                    f'{load_desc} loads {dest_rel}, which uses {uses_str} '
                    f'statements. This requires the script to be loaded as a module; '
                    f'otherwise the browser will throw a SyntaxError and the script '
                    f'will fail to run.'
                ),
                'Suggested Import': suggestion,
            })

        elif sr_is_mod and not finfo.is_es_module:
            if sr_source == 'dynamic' and sr_loader == 'loadModule':
                suggestion = f'Use loadScript("{sr.src_attr}") — file has no import/export'
            else:
                suggestion = ''

            rows.append({
                'Sub Audit': '1f - Module Script Type',
                'Source': html_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Warn',
                'Comment': (
                    f'{load_desc} loads {dest_rel}, which contains no '
                    f'import/export statements. Module scripts are deferred and run '
                    f'in strict mode -- confirm this is intentional.'
                ),
                'Suggested Import': suggestion,
            })

    return rows
