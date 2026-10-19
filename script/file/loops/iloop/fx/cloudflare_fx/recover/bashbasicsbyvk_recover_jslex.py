"""bashbasicsbyvk_recover_jslex - tiny JavaScript lexer + the esbuild clean-ups that need it (keepNames, PURE marks, void 0)."""
import re

SUFFIXED = re.compile(r'^([A-Za-z_$][\w$]*?)(\d+)$')
RESERVED = set("""break case catch class const continue debugger default delete do else enum export extends false finally for
function if import in instanceof new null return super switch this throw true try typeof var void while with yield let static
await async of get set undefined NaN Infinity arguments eval""".split())
_ID = re.compile(r'[A-Za-z_$][\w$]*')
_REGEX_AFTER = {"return", "typeof", "case", "throw", "in", "of", "void", "delete", "new", "else", "do", "instanceof", "yield", "await"}

_PURE = re.compile(r'/\*\s*@__(?:PURE|NO_SIDE_EFFECTS)__\s*\*/[ \t]*')
_CLOSER = {"(": ")", "[": "]", "{": "}"}

def _scan_group(code, j, closer, commas=None):
    """Scan from just after an opener to just after its matching `closer`; skips strings, templates, comments, regex
    literals. If `commas` is a list, depth-0 comma positions are appended to it."""
    n, last = len(code), ""
    while j < n:
        c = code[j]
        if c in " \t\r\n": j += 1; continue
        if c in "\"'":
            j += 1
            while j < n and code[j] != c: j += 2 if code[j] == "\\" else 1
            j += 1; last = '"s"'; continue
        if c == "`":
            j += 1
            while j < n and code[j] != "`":
                if code[j] == "\\": j += 2; continue
                if code[j] == "$" and code[j + 1:j + 2] == "{": j = _scan_group(code, j + 2, "}"); continue
                j += 1
            j += 1; last = "`t`"; continue
        if c == "/":
            d = code[j + 1:j + 2]
            if d == "/": k = code.find("\n", j); j = n if k < 0 else k; continue
            if d == "*": k = code.find("*/", j + 2); j = n if k < 0 else k + 2; continue
            if last == "" or last in _REGEX_AFTER or (len(last) == 1 and last in "(,=:[!&|?{};+-*%<>~^"):
                j += 1; incls = False
                while j < n:
                    ch = code[j]
                    if ch == "\\": j += 2; continue
                    if ch == "[": incls = True
                    elif ch == "]": incls = False
                    elif ch == "/" and not incls: break
                    elif ch == "\n": break
                    j += 1
                j += 1
                while j < n and code[j].isalpha(): j += 1
                last = "/re/"; continue
            j += 1; last = "/"; continue
        if c in _CLOSER: j = _scan_group(code, j + 1, _CLOSER[c]); last = ")"; continue
        if c == closer: return j + 1
        if c == "," and commas is not None: commas.append(j)
        m = _ID.match(code, j)
        if m: last = m.group(); j = m.end(); continue
        if c.isdigit(): last = "0"; j += 1; continue
        last = c; j += 1
    return n

_STR_ONLY = re.compile(r'^(?:"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\')$')

def strip_keepnames(code):
    """Remove esbuild's keepNames wrapper `__name(<expr>, "name")` -> `<expr>` (any expression, nested calls included),
    plus bundler `/* @__PURE__ */` annotations. The `__name` helper itself is not part of the original program."""
    if "__name" in code:
        ids = lex_idents(code)[0]
        spots = sorted((o for o in ids if o[2] == "__name" and not o[6] and o[5] == "("), key=lambda o: -o[0])
        for o in spots:
            op = code.index("(", o[1])
            commas = []; end = _scan_group(code, op + 1, ")", commas)
            if len(commas) != 1 or not _STR_ONLY.match(code[commas[0] + 1:end - 1].strip()): continue
            first = code[op + 1:commas[0]].strip()
            start = o[0]
            pm = re.search(r'/\*\s*@__PURE__\s*\*/[ \t]*$', code[:start])
            if pm: start = pm.start()
            simple = re.fullmatch(r'[A-Za-z_$][\w$.]*', first) is not None
            nxt = code[end:end + 1]
            bol = code[:start].rstrip(" \t").endswith("\n") or start == 0
            if simple and first != "this" and bol and nxt == ";":          # bare `__name(fn, "fn");` statement
                e2 = end + 1
                if code[e2:e2 + 1] == "\n": e2 += 1
                code = code[:start] + code[e2:]; continue
            rest = code[end:].lstrip(" \t\r\n")[:1]
            repl = first if simple or rest not in (".", "(", "[", "`", "?") else "(" + first + ")"
            code = code[:start] + repl + code[end:]
    return _PURE.sub("", code)

def restore_undefined(code):
    """esbuild lowers `undefined` to `void 0` (same value, primary vs unary expression), so the reverse is always safe."""
    if "void 0" not in code or re.search(r"\b(?:var|let|const|function|class)\s+undefined\b|\bundefined\s*=[^=]", code): return code
    spots = [o for o in lex_idents(code)[0] if o[2] == "void" and not o[6]]
    for o in sorted(spots, key=lambda o: -o[0]):
        m = re.match(r"void\s+0(?![\w$.])", code[o[0]:o[0] + 12])
        if m: code = code[:o[0]] + "undefined" + code[o[0] + m.end():]
    return code

def clean(code):
    code = strip_keepnames(code)
    code = re.sub(r'static \{\n\s*this;\n\s*\}\n\s*', '', code)
    return code.strip("\n") + "\n"


def lex_idents(code):
    """Tiny JS lexer: returns identifier occurrences (start,end,name,bracket,prev,next,is_prop),
    skipping strings, comments, regex literals and template text (but not ${...} code)."""
    n, i, out, stack, prev_tok, starts = len(code), 0, [], [], "", []
    pstack, blocks, last_rp = [], [], None          # pstack: (extent_start, is_block) parallel to stack
    def regex_ok():
        return prev_tok == "" or prev_tok in _REGEX_AFTER or (len(prev_tok) == 1 and prev_tok in "(,=:[!&|?{};+-*%<>~^")
    def tmpl(j):                         # scan template text from j; returns (new_i, pushed_expr)
        while j < n:
            ch = code[j]
            if ch == "\\": j += 2; continue
            if ch == "`": return j + 1, False
            if ch == "$" and code[j + 1:j + 2] == "{": stack.append("T"); pstack.append((j, False)); return j + 2, True
            j += 1
        return n, False
    while i < n:
        c = code[i]
        if c in " \t\r\n": i += 1; continue
        if not stack and (i == 0 or code[i - 1] == "\n") and c not in "})]": starts.append(i)   # top-level statement start
        if c == "/":
            d = code[i + 1:i + 2]
            if d == "/": j = code.find("\n", i); i = n if j < 0 else j; continue
            if d == "*": j = code.find("*/", i + 2); i = n if j < 0 else j + 2; continue
            if regex_ok():
                j, incls = i + 1, False
                while j < n:
                    ch = code[j]
                    if ch == "\\": j += 2; continue
                    if ch == "[": incls = True
                    elif ch == "]": incls = False
                    elif ch == "/" and not incls: break
                    elif ch == "\n": break
                    j += 1
                j += 1
                while j < n and code[j].isalpha(): j += 1
                i, prev_tok = j, "/re/"; continue
            i += 1; prev_tok = "/"; continue
        if c in "\"'":
            j = i + 1
            while j < n and code[j] != c: j += 2 if code[j] == "\\" else 1
            i, prev_tok = j + 1, '"s"'; continue
        if c == "`":
            i, _ = tmpl(i + 1); prev_tok = "`t`"; continue
        if c.isdigit() or (c == "." and code[i + 1:i + 2].isdigit()):
            j = i + 1
            while j < n and (code[j].isalnum() or code[j] in "._" or (code[j] in "+-" and code[j - 1] in "eE" and not code[i:j].lower().startswith("0x"))): j += 1
            i, prev_tok = j, "0"; continue
        m = _ID.match(code, i)
        if m:
            s, e = m.start(), m.end()
            j = s - 1
            while j >= 0 and code[j] in " \t\r\n": j -= 1
            prev = code[j] if j >= 0 else ""
            is_prop = prev == "." and code[max(0, j - 2):j + 1] != "..."
            k = e
            while k < n and code[k] in " \t\r\n": k += 1
            out.append((s, e, m.group(), stack[-1] if stack else "", prev, code[k:k + 1], is_prop))
            i, prev_tok = e, m.group(); continue
        if c in "([{":
            if c == "{":
                # statement/function/class body (a scope) vs object literal / pattern (not a scope)
                is_blk = prev_tok in (")", "{", "}", ";", "", "else", "try", "finally", "do", "static", ">") or \
                         (bool(re.match(r"[A-Za-z_$]", prev_tok or "")) and prev_tok not in _REGEX_AFTER and prev_tok not in RESERVED)
                ext = i
                if is_blk and prev_tok == ")" and last_rp: ext = last_rp[1]          # include the (params) / (for-header)
                elif is_blk and prev_tok == ">" and last_rp and code[last_rp[0] + 1:i].replace(" ", "").replace("\n", "") == "=>": ext = last_rp[1]
                pstack.append((ext, is_blk))
            else:
                pstack.append((i, False))
            stack.append(c)
        elif c in ")]}":
            if c == "}" and stack and stack[-1] == "T":
                stack.pop(); pstack.pop(); i, pushed = tmpl(i + 1); prev_tok = "`t`"; continue
            if stack:
                stack.pop(); ent = pstack.pop()
                if c == "}" and ent[1]: blocks.append((ent[0], i))
                elif c == ")": last_rp = (i, ent[0])
        prev_tok = c; i += 1
    blocks.sort()
    occ_block, bi, act = [], 0, []                    # innermost enclosing block (index into blocks) per identifier, -1 = top level
    for o in out:
        p = o[0]
        while bi < len(blocks) and blocks[bi][0] <= p: act.append(bi); bi += 1
        while act and blocks[act[-1]][1] < p: act.pop()
        occ_block.append(act[-1] if act else -1)
    return out, starts, blocks, occ_block

def occ_kind(o):
    _, _, _, br, prev, nxt, is_prop = o
    if is_prop: return "prop"
    if br == "{" and prev in ("{", ",") and nxt == ":": return "key"
    if br == "{" and prev in ("{", ",") and nxt in (",", "}"): return "shorthand"
    return "var"

def apply_positions(code, positions):
    """positions: list of (start, end, new_name)."""
    for st, en, new in sorted(positions, reverse=True):
        code = code[:st] + new + code[en:]
    for new in {p[2] for p in positions}:      # `{ env: env }` -> `{ env }` (esbuild expands shorthand when it renames)
        code = re.sub(r'([{,]\s*)' + re.escape(new) + r'\s*:\s*' + re.escape(new) + r'(?=\s*[,}])', r'\1' + new, code)
    return code

