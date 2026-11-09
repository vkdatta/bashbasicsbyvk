"""Analysis pipeline: crawl -> parse (AST) -> index (feature hashing) -> search -> verify (exact LCS) -> cluster -> metrics."""
from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

from bashbasicsbyvk_polyglot_crawler import crawl, read_text
from bashbasicsbyvk_polyglot_embeddings import HashingEmbedder
from bashbasicsbyvk_polyglot_extractor import FileInfo, FunctionBlock, TreeSitterBackend, extract_file
from bashbasicsbyvk_polyglot_languages import LANGUAGES
from bashbasicsbyvk_polyglot_metrics import compute_metrics
from bashbasicsbyvk_polyglot_similarity import Cluster, build_clusters, find_similar_pairs
from bashbasicsbyvk_polyglot_verify import CONFIDENCE_RANK, PairVerifier, confidence_label, verify_pairs


class AnalysisError(Exception):
    pass


@dataclass
class Config:
    root: str
    threshold: Optional[float] = None      # candidate-search cosine threshold (default 0.65); verification does the filtering
    min_lines: int = 6
    min_tokens: int = 20
    parser: str = "auto"                   # auto (tree-sitter > python-ast > regex) | treesitter (strict) | regex
    use_names: bool = False
    cross_language_only: bool = False
    excludes: List[str] = field(default_factory=list)
    languages: Optional[List[str]] = None
    max_file_kb: int = 1024
    verify: bool = True                    # exact ordered-token verification of candidate pairs
    verify_threshold: float = 0.60         # min verified similarity for a pair / average a cluster member must keep
    min_size_ratio: float = 0.4            # drop pairs whose token counts differ by more than this ratio
    min_confidence: str = "low"            # report only clusters at/above this band: low | medium | high


@dataclass
class Result:
    cfg: Config
    files: Dict[str, FileInfo]
    funcs: List[FunctionBlock]
    clusters: List[Cluster]
    metrics: dict
    functions_extracted: int
    parser_usage: Dict[str, str]
    embedder_name: str
    search_backend: str
    notes: List[str]
    elapsed_s: float
    threshold_used: float = 0.0
    verify_stats: Optional[dict] = None


def run(cfg: Config, ui, paths=None) -> Result:
    t0 = time.time()
    root = Path(cfg.root).resolve()
    if not root.is_dir():
        raise AnalysisError(f"not a directory: {root}")
    if cfg.threshold is not None and not 0.0 < cfg.threshold <= 1.0:
        raise AnalysisError("--threshold must be in (0, 1]")
    if not 0.0 <= cfg.verify_threshold <= 1.0 or not 0.0 <= cfg.min_size_ratio <= 1.0:
        raise AnalysisError("--verify-threshold and --min-size-ratio must be in [0, 1]")
    if cfg.min_confidence not in CONFIDENCE_RANK:
        raise AnalysisError("--min-confidence must be low, medium or high")
    notes: List[str] = []

    if paths is None:                      # the launcher crawls first (to know which grammars to install) and passes the list in
        paths = list(crawl(root, cfg.excludes, cfg.languages))
    ts = TreeSitterBackend() if cfg.parser != "regex" else None
    files: Dict[str, FileInfo] = {}
    funcs: List[FunctionBlock] = []
    usage: Dict[str, str] = {}
    extracted = 0

    with ui.task("Parsing files", len(paths)) as advance:
        for fp, lang in paths:
            text = read_text(fp, cfg.max_file_kb * 1024)
            if text is None:
                advance(1)
                continue
            rel = fp.relative_to(root).as_posix()
            prefix = [0]
            for line in text.splitlines():
                prefix.append(prefix[-1] + (1 if line.strip() else 0))
            files[rel] = FileInfo(rel, lang, prefix[-1], prefix)
            blocks, used = extract_file(rel, text, LANGUAGES[lang], ts, cfg.use_names)
            if cfg.parser == "treesitter" and used != "tree-sitter":
                raise AnalysisError(f"tree-sitter grammar for '{lang}' is not installed (declined, the install failed or --no-install; install it with: bashbasicsbyvk_deps.sh {LANGUAGES[lang].ts_module})")
            usage[lang] = used
            extracted += len(blocks)
            for b in blocks:
                b.loc = prefix[min(b.end_line, len(prefix) - 1)] - prefix[b.start_line - 1]
                if b.loc >= cfg.min_lines and len(b.tokens) >= cfg.min_tokens:
                    funcs.append(b)
            advance(1)
    for i, f in enumerate(funcs):
        f.id = i
    regex_langs = sorted(l for l, u in usage.items() if u == "regex")
    ast_langs = sorted(l for l, u in usage.items() if u == "python-ast")
    if cfg.parser == "auto":
        if regex_langs:
            notes.append("tree-sitter grammar unavailable for: " + ", ".join(regex_langs) +
                         " (regex extractor used - install tree-sitter and the grammar packages for full AST parsing)")
        if ast_langs:
            notes.append("python parsed with the standard-library ast (exact); install tree-sitter-python to use tree-sitter")

    clusters: List[Cluster] = []
    vstats: Optional[dict] = None
    embedder_name, search_backend = "-", "-"
    thr = cfg.threshold if cfg.threshold is not None else 0.65
    if len(funcs) >= 2:
        embedder = HashingEmbedder()
        embedder_name = embedder.name
        x = embedder.embed([f.text for f in funcs], ui)
        pair_map: Dict[tuple, float] = {(i, j): s for i, j, s in find_similar_pairs(x, thr, ui)[0]}
        search_backend = "numpy"
        # exact (type-1/2) clones: identical normalised token streams are linked directly, no similarity search needed
        by_sig: Dict[int, List[int]] = {}
        for f in funcs:
            by_sig.setdefault(hash(tuple(f.tokens)), []).append(f.id)
        exact = 0
        for ids in by_sig.values():
            for other in ids[1:]:
                exact += 1
                pair_map.setdefault((ids[0], other), 1.0)
        pairs = [(i, j, s) for (i, j), s in pair_map.items()]
        if cfg.cross_language_only:
            pairs = [p for p in pairs if funcs[p[0]].language != funcs[p[1]].language]
        if cfg.verify:
            verifier = PairVerifier(funcs, cfg.verify_threshold)
            pairs, vstats = verify_pairs(funcs, pairs, cfg.verify_threshold, cfg.min_size_ratio, verifier, ui)
            vstats["exact_clone_links"] = exact
            clusters = build_clusters(x, pairs, sim_fn=verifier.sim, prune_below=cfg.verify_threshold)
        else:
            clusters = build_clusters(x, pairs)
        floor = CONFIDENCE_RANK[cfg.min_confidence]
        clusters = [c for c in clusters if CONFIDENCE_RANK[confidence_label(c.avg_similarity)] >= floor]
        clusters.sort(key=lambda c: (-sum(funcs[m].loc for m in c.members), -c.avg_similarity))
        for n, c in enumerate(clusters, 1):
            c.id = n
    if not cfg.verify:
        notes.append("verification is OFF: the hashing index is a recall tool and will report many false positives.")
    metrics = compute_metrics(files, funcs, clusters)
    return Result(cfg, files, funcs, clusters, metrics, extracted, usage, embedder_name,
                  search_backend, notes, time.time() - t0, thr, vstats)
