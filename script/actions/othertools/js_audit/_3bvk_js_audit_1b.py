"""
3bvk_js_audit_1b.py.py
Audit 1b -- Export Matching

For every named import in a JS file, verifies that the destination file
actually exports each requested name.  Mismatches are surfaced as Annexure
entries on the Excel Annexure sheet.
"""

from 3bvk_js_audit_helpers import resolve_js_path, rel

# Module-level counter shared across all calls within a single run.
_annexure_counter = [0]


def audit_1b_export_match(js_info, all_js, root):
    """
    Returns (rows, annexures) where
      rows      – list of IE-sheet row dicts
      annexures – list of (ann_id, ann_row_list) tuples
    """
    rows       = []
    annexures  = []

    for imp in js_info.imports:
        dest_path = resolve_js_path(imp.from_path, root, js_info.path)
        dest_rel  = rel(dest_path) if dest_path else imp.from_path

        # Namespace imports (import *) cannot be enumerated
        if imp.names == ['*']:
            rows.append({
                'Sub Audit': '1b - Export Match',
                'Source': js_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Info',
                'Comment': (
                    f'Namespace import (import *) from {imp.from_path} '
                    f'-- cannot enumerate specific exports.'
                ),
                'Suggested Import': '',
            })
            continue

        # Destination file not found or not in scope
        if dest_path is None or dest_path not in all_js:
            rows.append({
                'Sub Audit': '1b - Export Match',
                'Source': js_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Error',
                'Comment': f'Destination file not found for: {imp.raw_stmt}',
                'Suggested Import': '',
            })
            continue

        dest_info = all_js[dest_path]
        missing   = [n for n in imp.names if n not in dest_info.exports]

        if not missing:
            rows.append({
                'Sub Audit': '1b - Export Match',
                'Source': js_info.rel_path,
                'Destination': dest_rel,
                'Status': 'OK',
                'Comment': f'All export functions found for statement {imp.raw_stmt}',
                'Suggested Import': '',
            })
        else:
            _annexure_counter[0] += 1
            ann_id = _annexure_counter[0]
            rows.append({
                'Sub Audit': '1b - Export Match',
                'Source': js_info.rel_path,
                'Destination': dest_rel,
                'Status': 'Error',
                'Comment': (
                    f'In the statement {imp.raw_stmt}, '
                    f'find status report in Annexure {ann_id}'
                ),
                'Suggested Import': '',
            })
            annexures.append((
                ann_id,
                _build_annexure(ann_id, missing, imp, dest_path, dest_info, js_info, all_js, root),
            ))

    return rows, annexures


def _build_annexure(ann_id, missing_names, imp, dest_path, dest_info,
                    source_info, all_js, root):
    """Build the per-function detail rows for one Annexure block."""
    ann_rows = []
    for fname in missing_names:
        if fname in dest_info.functions:
            if fname in source_info.functions:
                comment = (
                    f'Function found in destination {dest_info.rel_path} but no export declaration. '
                    f'Also directly declared in source {source_info.rel_path}, '
                    f'which overrides the import.'
                )
            else:
                comment = (
                    f'Function found in {dest_info.rel_path} but no export declaration.'
                )
        elif fname in source_info.functions:
            comment = (
                f'Function found in source file {source_info.rel_path} itself '
                f'-- no export needed for this import.'
            )
        else:
            found_in    = []
            exported_in = []
            for fpath, finfo in all_js.items():
                if fpath == source_info.path:
                    continue
                if fname in finfo.functions:
                    found_in.append(finfo.rel_path)
                    if fname in finfo.exports:
                        exported_in.append(finfo.rel_path)
            if not found_in:
                comment = (
                    'Function not found in any file including '
                    'the destination and source file.'
                )
            elif len(found_in) == 1:
                comment = (
                    f'Function found in {found_in[0]} '
                    f'{"with" if exported_in else "without"} an export declaration.'
                )
            else:
                comment = (
                    f'Function declared in multiple files [{", ".join(found_in)}] '
                    f'but not in destination.'
                )

        ann_rows.append({
            'Annexure': ann_id,
            'Source': source_info.rel_path,
            'Destination': dest_info.rel_path,
            'Function Name': fname,
            'Comment': comment,
        })

    return ann_rows
