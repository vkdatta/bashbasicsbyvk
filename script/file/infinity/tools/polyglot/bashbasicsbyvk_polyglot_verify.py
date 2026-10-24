"""Second-stage verification of candidate clone pairs.

The feature-hashing index is a *recall* tool: it surfaces functions that share vocabulary and shape.  It cannot
tell a real copy from two functions that merely use the same idioms (argument parsing, ``local x`` preambles,
``if err != nil`` blocks ...).  This module re-scores every candidate pair with an exact, order-aware comparison
of the normalised token streams and drops pairs that fail it.

    dice_lcs(a, b) = 2 * LCS(a, b) / (|a| + |b|)
    verified       = max( dice_lcs(raw tokens),  W_ALPHA * dice_lcs(alpha tokens) )

* raw   - the normalised token stream, identifier sub-words kept        -> rewards real copies
* alpha - "consistent renaming": every identifier is replaced by the index of its first occurrence in the
          function (v0, v1, ...), so a copy with renamed variables is *identical*, while two functions that merely
          share a control-flow skeleton are not (their identifiers bind differently).  A blind <id> skeleton was
          tried first and rejected: it inflated shell/Go boilerplate matches (see calibration below).

LCS is computed with the bit-parallel algorithm of Hyyro (2004) on Python integers: exact, symmetric, and about two
orders of magnitude faster than difflib on long functions.

Calibration (43k-LOC Bash+Python+Go+C project, 900 sampled candidate pairs vs an independent character-level diff):
raw LCS AUC 0.990 / 16 false positives per 598 negatives at 90% recall; adding the alpha stream keeps that
(0.988 / 16) and raises AUC against a rename-insensitive reference from 0.890 to 0.946, which is what lets
renamed clones through.  The old 50/50 blind-skeleton blend had 32 false positives.
"""
from __future__ import annotations

from collections import Counter
from typing import Dict, List, Sequence, Tuple

from bashbasicsbyvk_polyglot_embeddings import _STRUCTURAL
from bashbasicsbyvk_polyglot_extractor import FunctionBlock

W_ALPHA = 0.9                          # an alpha-equivalent (renamed) copy scores 0.9, an exact copy 1.0
MAX_TOKENS = 4000                      # compare at most this many leading tokens


CONFIDENCE_RANK = {"low": 0, "medium": 1, "high": 2}


def confidence_label(avg_similarity: float) -> str:
    """Reliability band of a cluster's average verified similarity (bands checked against an independent diff)."""
    return "high" if avg_similarity >= 0.80 else "medium" if avg_similarity >= 0.70 else "low"


def alpha_tokens(tokens: Sequence[str]) -> List[str]:
    """Consistent renaming: identifiers -> v0, v1, ... by first occurrence; keywords, operators, <str>/<num> stay."""
    seen: Dict[str, str] = {}
    out: List[str] = []
    for t in tokens:
        if t in _STRUCTURAL or not (t[0].isalpha() or t[0] == "_"):
            out.append(t)
        else:
            out.append(seen.setdefault(t, "v%d" % len(seen)))
    return out


def lcs_len(a: Sequence[str], b: Sequence[str]) -> int:
    """Exact longest-common-subsequence length (bit-parallel, O(len(a) * len(b) / word))."""
    if not a or not b:
        return 0
    if len(a) < len(b):
        a, b = b, a
    m = len(b)
    full = (1 << m) - 1
    pos: Dict[str, int] = {}
    for i, t in enumerate(b):
        pos[t] = pos.get(t, 0) | (1 << i)
    v = full
    for t in a:
        u = v & pos.get(t, 0)
        if u:
            v = ((v + u) | (v - u)) & full
    return m - (v.bit_count() if hasattr(v, "bit_count") else bin(v).count("1"))


def dice_lcs(a: Sequence[str], b: Sequence[str]) -> float:
    n = len(a) + len(b)
    return 2.0 * lcs_len(a, b) / n if n else 0.0


class PairVerifier:
    """Memoised verified similarity between functions (by index into `funcs`)."""

    def __init__(self, funcs: List[FunctionBlock], floor: float = 0.0) -> None:
        self.funcs = funcs
        self.floor = floor
        self._raw: Dict[int, List[str]] = {}
        self._alpha: Dict[int, List[str]] = {}
        self._cr: Dict[int, Counter] = {}
        self._ca: Dict[int, Counter] = {}
        self._cache: Dict[Tuple[int, int], float] = {}

    def _prep(self, i: int) -> None:
        if i not in self._raw:
            t = self.funcs[i].tokens[:MAX_TOKENS]
            a = alpha_tokens(t)
            self._raw[i], self._alpha[i] = t, a
            self._cr[i], self._ca[i] = Counter(t), Counter(a)

    def size_ratio(self, i: int, j: int) -> float:
        a, b = len(self.funcs[i].tokens), len(self.funcs[j].tokens)
        return min(a, b) / max(a, b) if max(a, b) else 0.0

    def overlaps(self, i: int, j: int) -> bool:
        a, b = self.funcs[i], self.funcs[j]
        return a.file == b.file and a.start_line <= b.end_line and b.start_line <= a.end_line

    @staticmethod
    def _upper(ca: Counter, cb: Counter, la: int, lb: int) -> float:
        """Cheap upper bound on dice_lcs: LCS can never exceed the multiset intersection."""
        if len(ca) > len(cb):
            ca, cb = cb, ca
        inter = sum(min(n, cb.get(t, 0)) for t, n in ca.items())
        return 2.0 * inter / (la + lb) if la + lb else 0.0

    def components(self, i: int, j: int) -> Tuple[float, float]:
        """(raw, alpha) dice-LCS; a component is 0.0 when an upper bound already shows it cannot matter."""
        return self._components(i, j)

    def _components(self, i: int, j: int) -> Tuple[float, float]:
        self._prep(i)
        self._prep(j)
        ra, rb, aa, ab = self._raw[i], self._raw[j], self._alpha[i], self._alpha[j]
        if ra == rb:
            return 1.0, 1.0
        raw = alpha = 0.0
        if self._upper(self._cr[i], self._cr[j], len(ra), len(rb)) >= self.floor:
            raw = dice_lcs(ra, rb)
        if W_ALPHA * self._upper(self._ca[i], self._ca[j], len(aa), len(ab)) > max(raw, self.floor - 1e-9):
            alpha = dice_lcs(aa, ab)
        return raw, alpha

    def sim(self, i: int, j: int) -> float:
        key = (i, j) if i < j else (j, i)
        hit = self._cache.get(key)
        if hit is None:
            raw, alpha = self._components(i, j)
            hit = self._cache[key] = max(raw, W_ALPHA * alpha)
        return hit


def verify_pairs(funcs: List[FunctionBlock], pairs: List[Tuple[int, int, float]], threshold: float,
                 min_size_ratio: float, verifier: PairVerifier, ui=None) -> Tuple[List[Tuple[int, int, float]], dict]:
    """Keep only pairs that survive the guards; return (pairs with verified similarity, rejection stats)."""
    stats = {"candidates": len(pairs), "rejected_overlap": 0, "rejected_size": 0, "rejected_verify": 0}
    out: List[Tuple[int, int, float]] = []
    ctx = ui.task("Verifying candidate pairs", max(len(pairs), 1)) if ui else None
    advance = ctx.__enter__() if ctx else (lambda k=1: None)
    try:
        for i, j, _emb in pairs:
            advance(1)
            if verifier.overlaps(i, j):                       # one function contains / is the other
                stats["rejected_overlap"] += 1
            elif verifier.size_ratio(i, j) < min_size_ratio:  # 200-line vs 30-line "clones"
                stats["rejected_size"] += 1
            else:
                s = verifier.sim(i, j)
                if s >= threshold:
                    out.append((i, j, s))
                else:
                    stats["rejected_verify"] += 1
    finally:
        if ctx:
            ctx.__exit__(None, None, None)
    return out, stats
