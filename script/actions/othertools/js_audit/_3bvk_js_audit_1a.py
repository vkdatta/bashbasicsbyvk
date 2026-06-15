"""
3bvk_js_audit_1a.py.py
Audit 1a -- Import at Top

Checks that every import statement in a JS file appears at the top of the
file (before any function declarations or expressions).
"""


def audit_1a_import_top(js_info):
    """
    Returns a list of IE-sheet rows for any import that is not at the
    top of *js_info*.
    """
    rows = []
    for imp in js_info.imports:
        if not imp.is_top:
            rows.append({
                'Sub Audit': '1a - Import at Top',
                'Source': js_info.rel_path,
                'Destination': '',
                'Status': 'Error',
                'Comment': (
                    f'{imp.raw_stmt} not at the top of the file. '
                    f'It is highly recommended to keep import statements at the top of the file.'
                ),
                'Suggested Import': '',
            })
    return rows
