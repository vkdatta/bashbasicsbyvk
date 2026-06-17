"""
_3bvk_js_audit_1f.py.py
Audit 1f -- Script Tag Module Type

For every <script src="..."> in an HTML file, checks whether the JS file it
loads uses ES-module syntax (import/export).  If so, the tag must carry
type="module"; if it already does but the file has no ES-module syntax, a
warning is emitted.
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

        if finfo.is_es_module and not sr.is_module:
            uses = []
            if any(imp for imp in finfo.imports):
                uses.append('import')
            if finfo.exports:
                uses.append('export')
            uses_str = '/'.join(uses) if uses else 'import/export'
            rows.append({
                'Sub Audit': '1f - Module Script Type',
                'Source': html_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Error',
                'Comment': (
                    f'<script src="{sr.src_attr}"> loads {dest_rel}, which uses {uses_str} '
                    f'statements. This requires the script tag to be declared as '
                    f'<script type="module" src="{sr.src_attr}"></script>, otherwise the '
                    f'browser will throw a SyntaxError and the script will fail to run.'
                ),
                'Suggested Import': f'<script type="module" src="{sr.src_attr}"></script>',
            })
        elif sr.is_module and not finfo.is_es_module:
            rows.append({
                'Sub Audit': '1f - Module Script Type',
                'Source': html_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Warn',
                'Comment': (
                    f'<script type="module" src="{sr.src_attr}"> loads {dest_rel}, which '
                    f'contains no import/export statements. Module scripts are deferred and '
                    f'run in strict mode -- confirm this is intentional.'
                ),
                'Suggested Import': '',
            })

    return rows
