"""_3bvk_recover_names - scope-aware reversal of esbuild's collision suffixes (`dk2` -> `dk`) for local names."""
import bisect, re
from _3bvk_recover_jslex import SUFFIXED, RESERVED, _ID, occ_kind

_TYPED_ARRAYS = re.compile(r'^(Big)?(Float|Int|Uint)\d+(Clamped)?Array$')

def restore_local_names(k, path, code, lexed, Mk, all_top, positions, log, known=None):
    """Scope-aware reversal of esbuild's collision suffixes for function/block-local names."""
    occ, starts, blocks, ob = lexed
    var_kinds = ("var", "shorthand")
    short = {o[2] for o in occ if occ_kind(o) == "shorthand"}
    by_name = {}                                   # original token -> occurrence indexes (var-kind)
    for i, o in enumerate(occ):
        if occ_kind(o) in var_kinds: by_name.setdefault(o[2], []).append(i)
    byeff = {}                                     # effective (post-rename) name -> sorted [(pos, idx)]
    for name, idxs in by_name.items():
        byeff.setdefault(Mk.get(name, name), []).extend((occ[i][0], i) for i in idxs)
    for v in byeff.values(): v.sort()
    def region_of(idxs):
        """Group occurrences of one name into disjoint scope regions [(lo, hi, idx_list)]."""
        chunk = lambda i: bisect.bisect_right(starts, occ[i][0]) - 1
        by_chunk = {}
        for i in idxs: by_chunk.setdefault(chunk(i), []).append(i)
        out = []
        for ci, lst in by_chunk.items():
            if any(ob[i] < 0 for i in lst):          # touches top-level statement text -> whole statement is the region
                lo = starts[ci] if ci >= 0 else 0
                hi = starts[ci + 1] if ci + 1 < len(starts) else len(code)
                out.append((lo, hi, lst, None)); continue
            roots = []                                # outermost of the innermost blocks (blocks are properly nested)
            for bi in sorted({ob[i] for i in lst}):
                if roots and blocks[bi][1] <= blocks[roots[-1]][1]: continue
                roots.append(bi)
            for bi in roots:
                lo, hi = blocks[bi][0], blocks[bi][1] + 1
                out.append((lo, hi, [i for i in lst if lo <= occ[i][0] < hi], bi))
        return out
    def used_in(x, lo, hi):
        lst = byeff.get(x)
        if not lst: return False
        j = bisect.bisect_left(lst, (lo, -1))
        return j < len(lst) and lst[j][0] < hi
    def bound_outside(x, lo, hi, is_block):
        if x in all_top: return True
        if not is_block: return False
        return any(not (lo <= p < hi) and ob[i] >= 0 and blocks[ob[i]][0] <= lo and blocks[ob[i]][1] >= hi - 1 for p, i in byeff.get(x, ()))
    cands = []
    for name in by_name:
        m = SUFFIXED.match(name)
        if not m or name in Mk or name in all_top or name in short or _TYPED_ARRAYS.match(name): continue
        base, num = m.group(1), int(m.group(2))
        if num < 2 or base in RESERVED or not _ID.fullmatch(base): continue
        if known is not None and (name in known or base not in known): continue     # project source says what the author wrote
        cands.append((base, num, name))
    for base, num, name in sorted(cands):
        groups = region_of(by_name[name])
        ok = [(lo, hi, lst, bi) for lo, hi, lst, bi in groups
              if not used_in(base, lo, hi) and bound_outside(base, lo, hi, bi is not None)]
        if len(ok) != len(groups) and re.search(r"\bvar\s[^;]*\b" + re.escape(name) + r"\b", code):
            continue                                   # `var` is function-scoped: rename all of its regions or none
        for lo, hi, lst, bi in ok:
            positions += [(occ[i][0], occ[i][1], base) for i in lst if occ_kind(occ[i]) == "var"]
            ps = {occ[i][0] for i in lst}
            byeff[name] = [t for t in byeff.get(name, []) if t[0] not in ps]
            byeff.setdefault(base, []).extend((occ[i][0], i) for i in lst); byeff[base].sort()
            log.append(f"{path}: {name} -> {base}  (local scope" + (", confirmed by project source)" if known is not None else ")"))

