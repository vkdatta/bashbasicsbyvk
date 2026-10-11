"""_3bvk_recover_wasm - disassemble a .wasm binary to WebAssembly text (.wat)."""
import re

import struct as _st

_VT = {0x7f: "i32", 0x7e: "i64", 0x7d: "f32", 0x7c: "f64", 0x7b: "v128", 0x70: "funcref", 0x6f: "externref"}
_NUM = {}
for _op, _n in zip(range(0x45, 0xc5), """i32.eqz i32.eq i32.ne i32.lt_s i32.lt_u i32.gt_s i32.gt_u i32.le_s i32.le_u i32.ge_s i32.ge_u
i64.eqz i64.eq i64.ne i64.lt_s i64.lt_u i64.gt_s i64.gt_u i64.le_s i64.le_u i64.ge_s i64.ge_u
f32.eq f32.ne f32.lt f32.gt f32.le f32.ge f64.eq f64.ne f64.lt f64.gt f64.le f64.ge
i32.clz i32.ctz i32.popcnt i32.add i32.sub i32.mul i32.div_s i32.div_u i32.rem_s i32.rem_u i32.and i32.or i32.xor i32.shl i32.shr_s i32.shr_u i32.rotl i32.rotr
i64.clz i64.ctz i64.popcnt i64.add i64.sub i64.mul i64.div_s i64.div_u i64.rem_s i64.rem_u i64.and i64.or i64.xor i64.shl i64.shr_s i64.shr_u i64.rotl i64.rotr
f32.abs f32.neg f32.ceil f32.floor f32.trunc f32.nearest f32.sqrt f32.add f32.sub f32.mul f32.div f32.min f32.max f32.copysign
f64.abs f64.neg f64.ceil f64.floor f64.trunc f64.nearest f64.sqrt f64.add f64.sub f64.mul f64.div f64.min f64.max f64.copysign
i32.wrap_i64 i32.trunc_f32_s i32.trunc_f32_u i32.trunc_f64_s i32.trunc_f64_u i64.extend_i32_s i64.extend_i32_u i64.trunc_f32_s i64.trunc_f32_u i64.trunc_f64_s i64.trunc_f64_u
f32.convert_i32_s f32.convert_i32_u f32.convert_i64_s f32.convert_i64_u f32.demote_f64 f64.convert_i32_s f64.convert_i32_u f64.convert_i64_s f64.convert_i64_u f64.promote_f32
i32.reinterpret_f32 i64.reinterpret_f64 f32.reinterpret_i32 f64.reinterpret_i64 i32.extend8_s i32.extend16_s i64.extend8_s i64.extend16_s i64.extend32_s""".split()):
    _NUM[_op] = _n
_MEM = {}
for _op, _n, _a in zip(range(0x28, 0x3f), """i32.load i64.load f32.load f64.load i32.load8_s i32.load8_u i32.load16_s i32.load16_u i64.load8_s i64.load8_u i64.load16_s i64.load16_u i64.load32_s i64.load32_u i32.store i64.store f32.store f64.store i32.store8 i32.store16 i64.store8 i64.store16 i64.store32""".split(),
                       [2, 3, 2, 3, 0, 0, 1, 1, 0, 0, 1, 1, 2, 2, 2, 3, 2, 3, 0, 1, 0, 1, 2]):
    _MEM[_op] = (_n, _a)
_FC = {0: "i32.trunc_sat_f32_s", 1: "i32.trunc_sat_f32_u", 2: "i32.trunc_sat_f64_s", 3: "i32.trunc_sat_f64_u",
       4: "i64.trunc_sat_f32_s", 5: "i64.trunc_sat_f32_u", 6: "i64.trunc_sat_f64_s", 7: "i64.trunc_sat_f64_u"}

class _R:
    def __init__(self, b, i=0): self.b, self.i = b, i
    def u8(self): v = self.b[self.i]; self.i += 1; return v
    def uleb(self):
        r = s = 0
        while True:
            x = self.u8(); r |= (x & 0x7f) << s; s += 7
            if x < 0x80: return r
    def sleb(self):
        r = s = 0
        while True:
            x = self.u8(); r |= (x & 0x7f) << s; s += 7
            if x < 0x80:
                if x & 0x40: r -= 1 << s
                return r
    def take(self, n): v = self.b[self.i:self.i + n]; self.i += n; return v
    def name(self): return self.take(self.uleb()).decode("utf-8", "replace")

def _fmt_f(raw, bits):
    v = _st.unpack("<f" if bits == 32 else "<d", raw)[0]
    if v != v:
        sign = "-" if raw[-1] & 0x80 else ""
        return sign + "nan"
    if v in (float("inf"), float("-inf")): return "inf" if v > 0 else "-inf"
    return repr(v) if bits == 64 else "%.9g" % v

def _esc(bs):
    return "".join(chr(c) if 0x20 <= c < 0x7f and c not in (0x22, 0x5c) else "\\%02x" % c for c in bs)

def decode_expr(r, end_pos=None):
    """Decode instructions until the matching final `end`. Returns list of (opcode_tuple, immediates)."""
    out, depth = [], 0
    while True:
        op = r.u8(); imm = ()
        if op in (0x02, 0x03, 0x04):
            bt = r.b[r.i]
            if bt == 0x40: r.i += 1; imm = ("empty",)
            elif bt in _VT: r.i += 1; imm = ("val", bt)
            else: imm = ("type", r.sleb())
            depth += 1
        elif op == 0x0b:
            if depth == 0: out.append(((op,), ())); return out
            depth -= 1
        elif op in (0x0c, 0x0d, 0x10, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0xd2): imm = (r.uleb(),)
        elif op == 0x0e:
            n = r.uleb(); imm = tuple(r.uleb() for _ in range(n + 1))
        elif op == 0x11: imm = (r.uleb(), r.uleb())
        elif op == 0x1c:
            n = r.uleb(); imm = tuple(r.u8() for _ in range(n))
        elif op in _MEM: imm = (r.uleb(), r.uleb())
        elif op in (0x3f, 0x40): imm = (r.u8(),)
        elif op in (0x41, 0x42): imm = (r.sleb(),)
        elif op == 0x43: imm = (bytes(r.take(4)),)
        elif op == 0x44: imm = (bytes(r.take(8)),)
        elif op == 0xd0: imm = (r.u8(),)
        elif op == 0xfc:
            sub = r.uleb(); op = (0xfc, sub)
            if sub == 8: imm = (r.uleb(), r.u8())
            elif sub == 9: imm = (r.uleb(),)
            elif sub == 10: imm = (r.u8(), r.u8())
            elif sub == 11: imm = (r.u8(),)
            elif sub == 12: imm = (r.uleb(), r.uleb())
            elif sub == 13: imm = (r.uleb(),)
            elif sub == 14: imm = (r.uleb(), r.uleb())
            elif sub in (15, 16, 17): imm = (r.uleb(),)
            elif sub > 7: raise ValueError(f"unsupported 0xfc sub-opcode {sub}")
        elif op == 0xfd: raise ValueError("SIMD (0xfd) instructions are not supported by this disassembler")
        elif not (op in _NUM or op in (0x00, 0x01, 0x05, 0x0f, 0x1a, 0x1b, 0xd1)):
            raise ValueError(f"unknown opcode 0x{op:02x}")
        out.append((op if isinstance(op, tuple) else (op,), imm))

def encode_expr(instrs):
    """Inverse of decode_expr (used to prove the decode is lossless)."""
    def uleb(v):
        o = bytearray()
        while True:
            b = v & 0x7f; v >>= 7
            if v: o.append(b | 0x80)
            else: o.append(b); return bytes(o)
    def sleb(v):
        o = bytearray()
        while True:
            b = v & 0x7f; v >>= 7
            if (v == 0 and not b & 0x40) or (v == -1 and b & 0x40): o.append(b); return bytes(o)
            o.append(b | 0x80)
    o = bytearray()
    for op, imm in instrs:
        o += bytes([op[0]])
        c = op[0]
        if len(op) == 2: o += uleb(op[1])
        if c in (0x02, 0x03, 0x04):
            if imm[0] == "empty": o.append(0x40)
            elif imm[0] == "val": o.append(imm[1])
            else: o += sleb(imm[1])
        elif c == 0x0e: o += uleb(len(imm) - 1) + b"".join(uleb(x) for x in imm)
        elif c == 0x1c: o += uleb(len(imm)) + bytes(imm)
        elif c in (0x41, 0x42): o += sleb(imm[0])
        elif c in (0x43, 0x44): o += imm[0]
        elif c in (0x3f, 0x40, 0xd0): o.append(imm[0])
        elif c == 0xfc:
            sub = op[1]
            if sub in (8, 10): o += (uleb(imm[0]) + bytes([imm[1]])) if sub == 8 else bytes(imm)
            elif sub == 11: o += bytes(imm)
            else: o += b"".join(uleb(x) for x in imm)
        else:
            for x in imm: o += uleb(x)
    return bytes(o)

def wasm_to_wat(data, source_name="module.wasm"):
    """Disassemble a .wasm binary to WebAssembly text. Names/comments of the original .wat are not in the binary."""
    if data[:4] != b"\0asm": raise ValueError("not a wasm binary")
    r = _R(data, 8)
    types, imports, funcs, tables, mems, globs, exports, elems, datas, codes = [], [], [], [], [], [], [], [], [], []
    start = None; names = {}
    while r.i < len(data):
        sid = r.u8(); size = r.uleb(); end = r.i + size
        if sid == 1:
            for _ in range(r.uleb()):
                assert r.u8() == 0x60
                p = [r.u8() for _ in range(r.uleb())]; q = [r.u8() for _ in range(r.uleb())]
                types.append((p, q))
        elif sid == 2:
            for _ in range(r.uleb()):
                m, n, kind = r.name(), r.name(), r.u8()
                if kind == 0: imports.append((m, n, 0, r.uleb()))
                elif kind == 1: rt = r.u8(); fl = r.uleb(); lim = (r.uleb(), r.uleb() if fl & 1 else None); imports.append((m, n, 1, (rt, lim)))
                elif kind == 2: fl = r.uleb(); lim = (r.uleb(), r.uleb() if fl & 1 else None); imports.append((m, n, 2, lim))
                else: vt = r.u8(); mu = r.u8(); imports.append((m, n, 3, (vt, mu)))
        elif sid == 3: funcs = [r.uleb() for _ in range(r.uleb())]
        elif sid == 4:
            for _ in range(r.uleb()):
                rt = r.u8(); fl = r.uleb(); tables.append((rt, (r.uleb(), r.uleb() if fl & 1 else None)))
        elif sid == 5:
            for _ in range(r.uleb()):
                fl = r.uleb(); mems.append((r.uleb(), r.uleb() if fl & 1 else None))
        elif sid == 6:
            for _ in range(r.uleb()):
                vt = r.u8(); mu = r.u8(); globs.append((vt, mu, decode_expr(r)))
        elif sid == 7:
            for _ in range(r.uleb()):
                n = r.name(); k = r.u8(); exports.append((n, k, r.uleb()))
        elif sid == 8: start = r.uleb()
        elif sid == 9:
            for _ in range(r.uleb()):
                fl = r.uleb()
                if fl == 0:
                    off = decode_expr(r); elems.append((0, off, [r.uleb() for _ in range(r.uleb())]))
                else:
                    elems.append((fl, None, None)); r.i = end; break
        elif sid == 10:
            for _ in range(r.uleb()):
                sz = r.uleb(); bend = r.i + sz
                locs = []
                for _ in range(r.uleb()):
                    cnt = r.uleb(); locs.append((cnt, r.u8()))
                body = decode_expr(r)
                if r.i != bend: raise ValueError("function body length mismatch")
                codes.append((locs, body))
        elif sid == 11:
            for _ in range(r.uleb()):
                fl = r.uleb()
                if fl == 0: off = decode_expr(r); datas.append((0, off, r.take(r.uleb())))
                elif fl == 1: datas.append((1, None, r.take(r.uleb())))
                else: mi = r.uleb(); off = decode_expr(r); datas.append((2, off, r.take(r.uleb())))
        r.i = end
    n_imp_f = sum(1 for x in imports if x[2] == 0)
    fname = {}
    for n, k, idx in exports:
        if k == 0 and idx not in fname: fname[idx] = "$" + re.sub(r"[^A-Za-z0-9_.$-]", "_", n)
    for i, imp in enumerate([x for x in imports if x[2] == 0]): fname.setdefault(i, f"$import_{imp[0]}_{imp[1]}".replace("-", "_"))
    def FN(i): return fname.get(i, f"$f{i}")
    def vts(l): return " ".join(_VT[x] for x in l)
    def lim(l): return f"{l[0]}" + (f" {l[1]}" if l[1] is not None else "")
    def sig(ti):
        p, q = types[ti]
        return (f" (param {vts(p)})" if p else "") + (f" (result {vts(q)})" if q else "")
    def inline(ex):
        parts = []
        for op, imm in ex[:-1]:
            if op[0] in _NUM or op[0] in (0x41, 0x42, 0x43, 0x44, 0x23): parts.append(_ins(op, imm))
            else: parts.append(_ins(op, imm))
        return "(" + ") (".join(parts) + ")" if parts else ""
    def _ins(op, imm):
        c = op[0]
        if len(op) == 2:
            sub = op[1]
            if sub in _FC: return _FC[sub]
            nm = {8: "memory.init", 9: "data.drop", 10: "memory.copy", 11: "memory.fill", 12: "table.init", 13: "elem.drop", 14: "table.copy", 15: "table.grow", 16: "table.size", 17: "table.fill"}[sub]
            return nm + ("" if not imm or nm in ("memory.copy", "memory.fill") else " " + " ".join(map(str, imm)))
        if c in _NUM: return _NUM[c]
        if c in _MEM:
            n, nat = _MEM[c]; a, off = imm
            return n + (f" offset={off}" if off else "") + (f" align={1 << a}" if a != nat else "")
        simple = {0x00: "unreachable", 0x01: "nop", 0x05: "else", 0x0b: "end", 0x0f: "return", 0x1a: "drop", 0x1b: "select", 0xd1: "ref.is_null"}
        if c in simple: return simple[c]
        if c in (0x02, 0x03, 0x04):
            nm = {2: "block", 3: "loop", 4: "if"}[c]
            if imm[0] == "val": return f"{nm} (result {_VT[imm[1]]})"
            if imm[0] == "type": return f"{nm} (type $t{imm[1]})"
            return nm
        if c in (0x0c, 0x0d): return ("br" if c == 0x0c else "br_if") + f" {imm[0]}"
        if c == 0x0e: return "br_table " + " ".join(map(str, imm))
        if c == 0x10: return f"call {FN(imm[0])}"
        if c == 0x11: return f"call_indirect (type $t{imm[0]})" if imm[1] == 0 else f"call_indirect {imm[1]} (type $t{imm[0]})"
        if c == 0x1c: return "select (result " + vts(imm) + ")"
        names = {0x20: "local.get", 0x21: "local.set", 0x22: "local.tee", 0x23: "global.get", 0x24: "global.set", 0x25: "table.get", 0x26: "table.set", 0xd2: "ref.func"}
        if c in names: return f"{names[c]} {imm[0]}"
        if c in (0x3f, 0x40): return "memory.size" if c == 0x3f else "memory.grow"
        if c == 0x41 or c == 0x42:
            v = imm[0]; return ("i32.const " if c == 0x41 else "i64.const ") + str(v)
        if c == 0x43: return "f32.const " + _fmt_f(imm[0], 32)
        if c == 0x44: return "f64.const " + _fmt_f(imm[0], 64)
        if c == 0xd0: return "ref.null " + _VT[imm[0]]
        raise ValueError(f"cannot print opcode {op}")
    L = [f";; Disassembled from {source_name} by recover_worker.py.",
         ";; This is a faithful text form of the compiled binary, NOT your original .wat:",
         ";; original comments, local/label names and layout were not stored in the binary.", "(module"]
    for i, (p, q) in enumerate(types): L.append(f"  (type $t{i} (func{' (param ' + vts(p) + ')' if p else ''}{' (result ' + vts(q) + ')' if q else ''}))")
    fi = 0
    for m, n, k, d in imports:
        if k == 0: L.append(f'  (import "{_esc(m.encode())}" "{_esc(n.encode())}" (func {FN(fi)} (type $t{d})))'); fi += 1
        elif k == 1: L.append(f'  (import "{m}" "{n}" (table {lim(d[1])} {_VT[d[0]]}))')
        elif k == 2: L.append(f'  (import "{m}" "{n}" (memory {lim(d)}))')
        else: L.append(f'  (import "{m}" "{n}" (global {"(mut " + _VT[d[0]] + ")" if d[1] else _VT[d[0]]}))')
    for rt, l in tables: L.append(f"  (table {lim(l)} {_VT[rt]})")
    for l in mems: L.append(f"  (memory {lim(l)})")
    for i, (vt, mu, ex) in enumerate(globs):
        L.append(f"  (global $g{i} {'(mut ' + _VT[vt] + ')' if mu else _VT[vt]} {inline(ex)})")
    for n, k, idx in exports:
        kind = ["func", "table", "memory", "global"][k]
        ref = FN(idx) if k == 0 else (f"$g{idx - sum(1 for x in imports if x[2] == 3)}" if k == 3 and idx >= sum(1 for x in imports if x[2] == 3) else str(idx))
        L.append(f'  (export "{_esc(n.encode())}" ({kind} {ref}))')
    if start is not None: L.append(f"  (start {FN(start)})")
    for fl, off, fl_idx in elems:
        if fl == 0: L.append(f"  (elem {inline(off)} func " + " ".join(FN(x) for x in fl_idx) + ")")
        else: L.append(f"  ;; element segment (flags={fl}) not disassembled")
    for i, (ti, (locs, body)) in enumerate(zip(funcs, codes)):
        L.append(f"  (func {FN(n_imp_f + i)} (type $t{ti}){sig(ti)}")
        if locs: L.append("    (local " + " ".join(" ".join([_VT[t]] * c) for c, t in locs) + ")")
        ind = 1
        for op, imm in body[:-1]:
            t = _ins(op, imm)
            if op[0] in (0x05, 0x0b): ind -= 1
            L.append("  " * (ind + 1) + t)
            if op[0] in (0x02, 0x03, 0x04, 0x05): ind += 1
        L.append("  )")
    for fl, off, bs in datas:
        if fl == 1: L.append(f'  (data "{_esc(bs)}")')
        else: L.append(f'  (data {inline(off)} "{_esc(bs)}")')
    L.append(")")
    return "\n".join(L) + "\n"

