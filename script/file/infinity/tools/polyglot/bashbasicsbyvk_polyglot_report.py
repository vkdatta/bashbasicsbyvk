"""JSON export and console rendering."""
from __future__ import annotations

import datetime
import json
from dataclasses import asdict
from pathlib import Path
from typing import List

from bashbasicsbyvk_polyglot_constants import TOOL_NAME, VERSION, WARNING
from bashbasicsbyvk_polyglot_verify import confidence_label as confidence
from bashbasicsbyvk_polyglot_pipeline import Result

try:
    from rich import box
    from rich.console import Console
    from rich.table import Table
    HAVE_RICH = True
except ImportError:                                           # pragma: no cover
    HAVE_RICH = False


def pct(x: float) -> str:
    return f"{100.0 * x:.1f}%"


def build_report(res: Result) -> dict:
    f, m = res.funcs, res.metrics
    cluster_metric = {c["cluster_id"]: c for c in m["clusters"]}
    clusters = []
    for c in res.clusters:
        langs = sorted({f[i].language for i in c.members})
        cm = cluster_metric[c.id]
        clusters.append({
            "cluster_id": c.id,
            "size": len(c.members),
            "languages": langs,
            "cross_language": len(langs) > 1,
            "confidence": confidence(c.avg_similarity),
            "avg_similarity_pct": round(100 * c.avg_similarity, 2),
            "min_similarity_pct": round(100 * c.min_similarity, 2),
            "embedding_avg_similarity_pct": round(100 * c.embedding_avg_similarity, 2),
            "total_loc": cm["total_loc"],
            "redundant_loc": cm["redundant_loc"],
            "share_of_project_pct": cm["share_of_project_pct"],
            "members": [{
                "file": f[i].file, "function": f[i].name, "language": f[i].language,
                "start_line": f[i].start_line, "end_line": f[i].end_line, "loc": f[i].loc,
                "similarity_to_cluster_pct": round(100 * c.member_similarity[i], 2),
            } for i in c.members],
            "matches": [{
                "a": {"file": f[i].file, "function": f[i].name, "language": f[i].language,
                      "lines": [f[i].start_line, f[i].end_line]},
                "b": {"file": f[j].file, "function": f[j].name, "language": f[j].language,
                      "lines": [f[j].start_line, f[j].end_line]},
                "similarity_pct": round(100 * s, 2),
            } for i, j, s in c.pairs],
        })
    return {
        "tool": TOOL_NAME, "version": VERSION, "disclaimer": WARNING,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "root": str(Path(res.cfg.root).resolve()),
        "config": {k: v for k, v in asdict(res.cfg).items() if k != "root"},
        "summary": {
            "total_files_scanned": len(res.files),
            "total_functions_extracted": res.functions_extracted,
            "functions_analyzed": len(res.funcs),
            "functions_in_duplicate_clusters": sum(len(c.members) for c in res.clusters),
            "duplicate_clusters": len(res.clusters),
            "total_loc": m["total_loc"],
            "duplicate_loc": m["duplicate_loc"],
            "overall_duplication_pct": m["duplication_pct"],
            "redundant_loc": m["redundant_loc"],
            "redundant_pct": m["redundant_pct"],
            "cross_language_clusters": sum(1 for c in clusters if c["cross_language"]),
            "similarity_threshold": res.threshold_used,
            "verification": ({"enabled": True, "threshold": res.cfg.verify_threshold,
                              "min_size_ratio": res.cfg.min_size_ratio, **res.verify_stats}
                             if res.verify_stats is not None else {"enabled": False}),
            "embedder": res.embedder_name, "similarity_backend": res.search_backend,
            "parser_backend_by_language": res.parser_usage,
            "elapsed_seconds": round(res.elapsed_s, 2),
        },
        "clusters": clusters,
        "files": m["files"],
        "notes": res.notes,
    }


def write_json(report: dict, path: str) -> None:
    Path(path).write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")


def _loc(m: dict) -> str:
    return f"{m['file']}:{m['start_line']}-{m['end_line']}"


def print_report(report: dict, written: str, max_clusters: int = 20, top_files: int = 10,
                 plain: bool = False) -> None:
    s = report["summary"]
    shown = report["clusters"][:max_clusters]
    top = [r for r in sorted(report["files"], key=lambda r: -r["duplication_pct"]) if r["duplicate_loc"]][:top_files]
    if HAVE_RICH and not plain:
        con = Console()
        t = Table(title="PolyglotCloneFinder - Summary", box=box.ROUNDED, show_header=False)
        t.add_column(style="bold"); t.add_column(justify="right")
        for k, v in [("Total Files Scanned", s["total_files_scanned"]),
                     ("Total Functions Extracted", s["total_functions_extracted"]),
                     ("Functions Analyzed (>= min size)", s["functions_analyzed"]),
                     ("Duplicate Clusters", f"{s['duplicate_clusters']} ({s['cross_language_clusters']} cross-language)"),
                     ("Functions in Clusters", s["functions_in_duplicate_clusters"]),
                     ("Total LOC / Duplicate LOC", f"{s['total_loc']} / {s['duplicate_loc']}"),
                     ("Overall Project Duplication", f"[bold red]{s['overall_duplication_pct']:.2f}%[/]"),
                     ("Index / Search", f"feature-hashing / {s['similarity_backend']}")]:
            t.add_row(k, str(v))
        con.print(t)
        for n in report["notes"]:
            con.print(f"[yellow]note:[/yellow] {n}", highlight=False)
        for c in shown:
            tag = "cross-language: " + ", ".join(c["languages"]) if c["cross_language"] else c["languages"][0]
            ct = Table(title=f"Cluster #{c['cluster_id']}  |  {c['size']} functions  |  avg {c['avg_similarity_pct']:.1f}% "
                             f"(min {c['min_similarity_pct']:.1f}%, {c['confidence']})  |  {c['total_loc']} LOC  |  {tag}",
                       box=box.SIMPLE_HEAD, title_justify="left", title_style="bold cyan")
            for col in ("Function", "File : Lines", "Lang", "LOC", "Match"):
                ct.add_column(col, justify="right" if col in ("LOC", "Match") else "left")
            for m in c["members"]:
                ct.add_row(m["function"], _loc(m), m["language"], str(m["loc"]), f"{m['similarity_to_cluster_pct']:.1f}%")
            con.print(ct)
            for mt in c["matches"][:5]:
                con.print(f"   [green]{mt['a']['function']}[/] ({mt['a']['file']}) <-> "
                          f"[green]{mt['b']['function']}[/] ({mt['b']['file']})  [bold]{mt['similarity_pct']:.1f}%[/]",
                          highlight=False)
        if len(report["clusters"]) > len(shown):
            con.print(f"... {len(report['clusters']) - len(shown)} more clusters in {written}")
        if top:
            ft = Table(title="Most duplicated files", box=box.SIMPLE_HEAD, title_justify="left")
            for col in ("File", "Lang", "LOC", "Dup LOC", "Dup %"):
                ft.add_column(col, justify="left" if col in ("File", "Lang") else "right")
            for r in top:
                ft.add_row(r["path"], r["language"], str(r["loc"]), str(r["duplicate_loc"]), f"{r['duplication_pct']:.1f}%")
            con.print(ft)
        con.print(f"Full report written to [bold]{written}[/]", highlight=False)
        con.print(f"\n[bold yellow]\u26a0  {WARNING}[/]", highlight=False)
        return
    # ---- plain-text fallback ----
    out: List[str] = ["=" * 64, "PolyglotCloneFinder - Summary", "=" * 64,
                      f"Total Files Scanned          : {s['total_files_scanned']}",
                      f"Total Functions Extracted    : {s['total_functions_extracted']}",
                      f"Functions Analyzed           : {s['functions_analyzed']}",
                      f"Duplicate Clusters           : {s['duplicate_clusters']} ({s['cross_language_clusters']} cross-language)",
                      f"Total LOC / Duplicate LOC    : {s['total_loc']} / {s['duplicate_loc']}",
                      f"Overall Project Duplication  : {s['overall_duplication_pct']:.2f}%",
                      f"Index / Search               : feature-hashing / {s['similarity_backend']}"]
    out += [f"note: {n}" for n in report["notes"]]
    for c in shown:
        out += ["", f"Cluster #{c['cluster_id']} - {c['size']} functions, avg {c['avg_similarity_pct']:.1f}% "
                    f"(min {c['min_similarity_pct']:.1f}%, {c['confidence']} confidence), {c['total_loc']} LOC, langs: {', '.join(c['languages'])}"]
        for m in c["members"]:
            out.append(f"   {m['function']:<28} {_loc(m):<40} {m['language']:<11} {m['loc']:>4} LOC  {m['similarity_to_cluster_pct']:.1f}%")
        for mt in c["matches"][:5]:
            out.append(f"   {mt['a']['function']} ({mt['a']['file']}) <-> {mt['b']['function']} ({mt['b']['file']})  {mt['similarity_pct']:.1f}%")
    if top:
        out += ["", "Most duplicated files:"]
        out += [f"   {r['path']:<44} {r['duplicate_loc']:>4}/{r['loc']:<5} LOC  {r['duplication_pct']:.1f}%" for r in top]
    out.append(f"\nFull report written to {written}")
    out += ["", "WARNING: " + WARNING]
    print("\n".join(out))
