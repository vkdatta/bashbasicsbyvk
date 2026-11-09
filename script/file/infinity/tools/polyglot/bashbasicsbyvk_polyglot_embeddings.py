"""Candidate-generation index: dependency-free feature hashing of the normalised token stream.

HashingEmbedder returns L2-normalised float32 matrices of shape (n_functions, dim).  It is deliberately a
*recall* tool (fast, deterministic, no model download, no GPU); every candidate pair it proposes is then
verified exactly by `verify.py`, so precision never depends on the quality of this stage.
"""
from __future__ import annotations

import math
import zlib
from typing import List

import numpy as np


def _l2(x: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(x, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return (x / norms).astype(np.float32)


_STRUCTURAL = frozenset("""
if else elif for while do in return break continue try catch except finally switch case yield await
with not is range len append push insert split join round null true false <str> <num>
= == != < > <= >= + - * / % ++ -- && || ! -> ? ^ & | then fi done esac
""".split())


class HashingEmbedder:
    """Rename-robust feature hashing.

    Three feature families over the normalised token stream:
      * skeleton n-grams (bi/tri-grams with every identifier replaced by <id>) -> survives renaming
      * identifier unigrams (sub-words such as 'tax', 'amount')                -> semantic hints
      * raw bigrams                                                            -> exact copies
    """
    name = "hashing"

    def __init__(self, dim: int = 2048) -> None:
        self.dim = dim

    @staticmethod
    def _features(toks: List[str]) -> dict:
        skel = [t if t in _STRUCTURAL else "<id>" for t in toks]
        feats: dict = {}

        def add(key: str, w: float) -> None:
            feats[key] = feats.get(key, 0.0) + w

        for a, b in zip(skel, skel[1:]):
            add("S2|" + a + "|" + b, 1.0)
        for a, b, c in zip(skel, skel[1:], skel[2:]):
            add("S3|" + a + "|" + b + "|" + c, 1.0)
        for t in toks:
            if t not in _STRUCTURAL:
                add("I|" + t, 0.6)
        for a, b in zip(toks, toks[1:]):
            add("R2|" + a + "|" + b, 0.4)
        return feats

    def embed(self, texts: List[str], ui=None) -> np.ndarray:
        out = np.zeros((len(texts), self.dim), dtype=np.float32)
        ctx = ui.task("Indexing (feature hashing)", len(texts)) if ui else None
        advance = ctx.__enter__() if ctx else (lambda n=1: None)
        for i, text in enumerate(texts):
            for k, c in self._features(text.split()).items():
                h = zlib.crc32(k.encode())
                out[i, h % self.dim] += (1.0 if (h >> 31) & 1 else -1.0) * math.log1p(c)
            advance(1)
        if ctx:
            ctx.__exit__(None, None, None)
        return _l2(out)
