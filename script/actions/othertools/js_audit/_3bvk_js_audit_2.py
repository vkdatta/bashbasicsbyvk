"""
_3bvk_js_audit_2.py.py
Audit 2 -- Active / Dead Function Analysis

For every function found in every JS file, counts how many times it is called
across all JS files and HTML files.  Functions with zero usage count (and not
exported or in an IIFE file) are marked Dead; all others are Active.
"""

import re
from _3bvk_js_audit_helpers import rel
from _3bvk_js_audit_helpers import _is_traditional_decl


def _count_calls(fname, src):
    return len(re.findall(r'\b' + re.escape(fname) + r'\s*\(', src))


def audit_2_active_dead(all_js, all_html):
    rows         = []
    all_js_srcs  = {fpath: fi.source for fpath, fi in all_js.items()}
    all_html_text = ' '.join(hi.source for hi in all_html)

    for fpath, finfo in all_js.items():
        for fname, func in finfo.functions.items():
            usage_count = 0
            locations   = []

            # Self-calls (subtract 1 for the declaration itself)
            self_count = _count_calls(fname, finfo.source)
            if _is_traditional_decl(fname, finfo.source):
                self_count = max(0, self_count - 1)
            if self_count > 0:
                usage_count += self_count
                locations.append(f'{finfo.rel_path} (self, {self_count}x)')

            # Calls from other JS files
            for other_path, other_src in all_js_srcs.items():
                if other_path == fpath:
                    continue
                c = _count_calls(fname, other_src)
                if c > 0:
                    usage_count += c
                    locations.append(f'{rel(other_path)} ({c}x)')

            # Calls from HTML files
            html_count = _count_calls(fname, all_html_text)
            if html_count > 0:
                usage_count += html_count
                locations.append(f'HTML ({html_count}x)')

            # IIFE files: treat unexported, uncalled functions as used
            if finfo.iife_present and usage_count == 0 and fname not in finfo.exports:
                usage_count += 1
                locations.append('IIFE (self-invoking)')

            # Exported functions count as used
            if fname in finfo.exports:
                usage_count += 1
                locations.append('exported')

            is_active = usage_count > 0
            rows.append({
                'Source': finfo.rel_path,
                'Function Name': fname,
                'Status': 'Active' if is_active else 'Dead',
                'Usage Count': usage_count,
                'Comment': (
                    f'Used {usage_count} time(s): {"; ".join(locations)}'
                    if is_active
                    else 'Not used anywhere in the scanned codebase.'
                ),
            })

    return rows
