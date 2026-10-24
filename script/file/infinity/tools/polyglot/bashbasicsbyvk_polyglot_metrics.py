"""Duplication metrics."""
from __future__ import annotations

from typing import Dict, List

from bashbasicsbyvk_polyglot_extractor import FileInfo, FunctionBlock
from bashbasicsbyvk_polyglot_similarity import Cluster


def _merge(intervals):
    out = []
    for a, b in sorted(intervals):
        if out and a <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out


def compute_metrics(files: Dict[str, FileInfo], funcs: List[FunctionBlock], clusters: List[Cluster]) -> dict:
    """
    project duplication % = non-blank LOC inside functions that belong to a
    duplicate cluster / total non-blank LOC of all scanned source files * 100.
    Line ranges are merged per file, so no line is ever counted twice.
    """
    per_file_iv: Dict[str, list] = {}
    per_file_funcs: Dict[str, set] = {}
    for c in clusters:
        for m in c.members:
            f = funcs[m]
            per_file_iv.setdefault(f.file, []).append((f.start_line, f.end_line))
            per_file_funcs.setdefault(f.file, set()).add(m)

    file_rows, dup_total = [], 0
    for path, info in sorted(files.items()):
        dup = 0
        for a, b in _merge(per_file_iv.get(path, [])):
            dup += info.prefix[min(b, len(info.prefix) - 1)] - info.prefix[a - 1]
        dup_total += dup
        file_rows.append({
            "path": path, "language": info.language, "loc": info.loc,
            "functions_in_duplicate_clusters": len(per_file_funcs.get(path, ())),
            "duplicate_loc": dup,
            "duplication_pct": round(100.0 * dup / info.loc, 2) if info.loc else 0.0,
        })
    total_loc = sum(i.loc for i in files.values())

    cluster_rows, redundant = [], 0
    for c in clusters:
        locs = [funcs[m].loc for m in c.members]
        red = sum(locs) - max(locs)
        redundant += red
        cluster_rows.append({"cluster_id": c.id, "total_loc": sum(locs), "redundant_loc": red,
                             "share_of_project_pct": round(100.0 * sum(locs) / total_loc, 2) if total_loc else 0.0})
    return {
        "total_loc": total_loc,
        "duplicate_loc": dup_total,
        "duplication_pct": round(100.0 * dup_total / total_loc, 2) if total_loc else 0.0,
        "redundant_loc": redundant,
        "redundant_pct": round(100.0 * redundant / total_loc, 2) if total_loc else 0.0,
        "files": file_rows,
        "clusters": cluster_rows,
    }
