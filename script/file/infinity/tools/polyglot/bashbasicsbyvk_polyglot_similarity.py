"""All-pairs candidate search and clustering (numpy only)."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Tuple

import numpy as np


def find_similar_pairs(x: np.ndarray, threshold: float, ui=None, block: int = 1024,
                       max_neighbors: int = 25) -> Tuple[List[Tuple[int, int, float]], str]:
    """Pairs (i<j) with cosine similarity >= threshold, at most `max_neighbors` (best) per function
    so memory stays bounded when a codebase contains thousands of near-identical functions.
    Blocked float32 matrix products: O(n^2 * dim) with O(block * n) memory.
    Returns (pairs, backend name)."""
    n = len(x)
    pairs: List[Tuple[int, int, float]] = []
    x = np.ascontiguousarray(x, dtype=np.float32)
    ctx = ui.task("Comparing functions", n) if ui else None
    advance = ctx.__enter__() if ctx else (lambda k=1: None)
    try:
        for a in range(0, n, block):
            sims = x[a:a + block] @ x.T
            for r in range(sims.shape[0]):
                i = a + r
                row = sims[r]
                cols = np.flatnonzero(row[i + 1:] >= threshold) + i + 1      # only j > i
                if len(cols) > max_neighbors:
                    cols = cols[np.argpartition(-row[cols], max_neighbors)[:max_neighbors]]
                pairs.extend((i, int(c), float(min(row[c], 1.0))) for c in cols)
            advance(min(block, n - a))
    finally:
        if ctx:
            ctx.__exit__(None, None, None)
    return pairs, "numpy"


@dataclass
class Cluster:
    id: int
    members: List[int]
    pairs: List[Tuple[int, int, float]]
    avg_similarity: float = 0.0
    min_similarity: float = 0.0
    member_similarity: Dict[int, float] = field(default_factory=dict)
    embedding_avg_similarity: float = 0.0     # mean cosine of the hashing index (before verification)


def _components(nodes_pairs: List[Tuple[int, int, float]]) -> List[List[int]]:
    parent: Dict[int, int] = {}

    def find(a: int) -> int:
        parent.setdefault(a, a)
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for i, j, _ in nodes_pairs:
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[ri] = rj
    groups: Dict[int, List[int]] = {}
    for node in list(parent):
        groups.setdefault(find(node), []).append(node)
    return [sorted(g) for g in groups.values()]


def _split_oversized(members: List[int], edges: List[Tuple[int, int, float]], limit: int,
                     start: float) -> List[List[int]]:
    """A huge connected component is almost always single-linkage chaining.  Re-cut it at ever stricter edge
    thresholds until every piece has <= `limit` members (pieces of size 1 vanish)."""
    if len(members) <= limit:
        return [members]
    thr, out, inside = start, [], set(members)
    for _ in range(40):
        thr = min(thr + 0.02, 1.01)
        keep = [e for e in edges if e[2] >= thr and e[0] in inside and e[1] in inside]
        parts = _components(keep)
        if all(len(p) <= limit for p in parts) or thr >= 1.0:
            out = [p for p in parts if len(p) <= limit]
            break
    return out


def build_clusters(x: np.ndarray, pairs: List[Tuple[int, int, float]], max_dense: int = 300,
                   sim_fn: Optional[Callable[[int, int], float]] = None, prune_below: float = 0.0,
                   max_refine: int = 40) -> List[Cluster]:
    """Connected components over the similarity graph, with intra-cluster stats.

    With `sim_fn` (verified pairwise similarity) every component is refined with average-linkage pruning: the
    member with the lowest mean similarity to the others is dropped until every remaining member averages
    >= `prune_below`.  Components larger than `max_refine` are first re-cut at stricter edge thresholds, so
    no oversized "chained" cluster can survive.  Reported similarities are then `sim_fn` values.
    """
    comps = _components(pairs)
    edge_by_node: Dict[int, List[Tuple[int, int, float]]] = {}
    for p in pairs:
        edge_by_node.setdefault(p[0], []).append(p)
        edge_by_node.setdefault(p[1], []).append(p)

    def emb_avg(members: List[int]) -> float:
        sub = x[members]
        sims = np.clip(sub @ sub.T, -1.0, 1.0)
        return float(sims[np.triu_indices(len(members), k=1)].mean())

    clusters: List[Cluster] = []
    for members in comps:
        es = sorted({e for m in members for e in edge_by_node.get(m, [])}, key=lambda e: -e[2])
        if sim_fn is not None:
            pieces = _split_oversized(members, es, max_refine, prune_below) if len(members) > max_refine else [members]
            for piece in pieces:
                piece = list(piece)
                while len(piece) >= 2:
                    m = np.array([[sim_fn(a, b) if a != b else 0.0 for b in piece] for a in piece])
                    means = m.sum(axis=1) / (len(piece) - 1)
                    worst = int(means.argmin())
                    if means[worst] >= prune_below:
                        break
                    piece.pop(worst)
                if len(piece) < 2:
                    continue
                m = np.array([[sim_fn(a, b) if a != b else 0.0 for b in piece] for a in piece])
                iu = np.triu_indices(len(piece), k=1)
                vals = m[iu]
                if not (vals >= prune_below).any():
                    continue
                per = {mem: float(m[r].sum() / (len(piece) - 1)) for r, mem in enumerate(piece)}
                kept = sorted(((piece[a], piece[b], float(m[a, b])) for a, b in zip(*iu) if m[a, b] >= prune_below),
                              key=lambda e: -e[2])
                clusters.append(Cluster(0, piece, kept, float(vals.mean()), float(vals.min()), per, emb_avg(piece)))
            continue
        if len(members) <= max_dense:                      # exact all-pairs stats within the cluster
            sub = x[members]
            sims = np.clip(sub @ sub.T, -1.0, 1.0)
            iu = np.triu_indices(len(members), k=1)
            vals = sims[iu]
            avg, mn = float(vals.mean()), float(vals.min())
            per = {m: float((sims[r].sum() - sims[r, r]) / (len(members) - 1)) for r, m in enumerate(members)}
        else:                                              # huge cluster: use graph edges only
            vals = np.array([e[2] for e in es])
            avg, mn = float(vals.mean()), float(vals.min())
            acc: Dict[int, List[float]] = {}
            for i, j, s_ in es:
                acc.setdefault(i, []).append(s_)
                acc.setdefault(j, []).append(s_)
            per = {m: float(np.mean(acc.get(m, [0.0]))) for m in members}
        clusters.append(Cluster(0, members, es, avg, mn, per, avg))
    return clusters
