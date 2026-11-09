"""Function/method extraction.

Backends, in order of preference (chosen per language, reported in the JSON as parser_backend_by_language):
  1. tree-sitter   - real ASTs for every supported language (bashbasicsbyvk_polyglot installs them itself when they are missing).
  2. python-ast    - the standard-library `ast` + `tokenize` modules; exact for Python with zero dependencies.
  3. regex         - a comment/string-aware regex + brace/indent scanner (last resort).
"""
from __future__ import annotations

import importlib
import re
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from bashbasicsbyvk_polyglot_languages import LangSpec
from bashbasicsbyvk_polyglot_normalize import COMMENT_RE, STR_RE, STR_RES, canon_text, regex_tokens, split_identifier


@dataclass
class FunctionBlock:
    file: str
    name: str
    language: str
    start_line: int          # 1-based, inclusive
    end_line: int
    tokens: List[str] = field(repr=False, default_factory=list)
    loc: int = 0             # non-blank lines
    backend: str = ""
    id: int = -1

    @property
    def text(self) -> str:
        return " ".join(self.tokens)


@dataclass
class FileInfo:
    path: str
    language: str
    loc: int
    prefix: List[int] = field(repr=False, default_factory=list)   # prefix[n] = non-blank lines in first n lines


# ============================================================================
# tree-sitter backend
# ============================================================================
class TreeSitterBackend:
    def __init__(self) -> None:
        self._parsers: dict = {}

    def parser_for(self, spec: LangSpec):
        if spec.name in self._parsers:
            return self._parsers[spec.name]
        parser = None
        try:
            from tree_sitter import Language, Parser
            mod = importlib.import_module(spec.ts_module)
            lang = Language(getattr(mod, spec.ts_factory)())
            try:
                parser = Parser(lang)               # py-tree-sitter >= 0.22
            except TypeError:
                parser = Parser()
                parser.set_language(lang)           # py-tree-sitter < 0.22
        except Exception:
            parser = None
        self._parsers[spec.name] = parser
        return parser


_TYPE_NODES = frozenset({
    "type", "type_annotation", "type_identifier", "primitive_type", "predefined_type",
    "type_arguments", "type_parameters", "generic_type", "integral_type", "floating_point_type",
    "void_type", "boolean_type", "array_type", "pointer_type", "return_type", "type_spec",
    "sized_type_specifier", "builtin_type", "predefined_type", "nullable_type",
})
_NUM_KEYS = ("integer", "float", "number", "decimal", "hex_", "octal", "int_literal",
             "float_literal", "imaginary_literal", "binary_literal")
_IDENT_TYPES = frozenset({"identifier", "field_identifier", "property_identifier",
                          "qualified_identifier", "destructor_name", "operator_name",
                          "shorthand_property_identifier", "constant", "simple_identifier"})


def _is_str(t: str) -> bool:
    return "string" in t or t in ("template_string", "char_literal", "character_literal", "rune_literal",
                                  "heredoc_body")


def _is_num(t: str) -> bool:
    return any(k in t for k in _NUM_KEYS)


def _text(node) -> str:
    return node.text.decode("utf-8", errors="replace")


def _node_name(node) -> Optional[str]:
    n = node.child_by_field_name("name")
    if n is not None:
        return _text(n)
    d = node.child_by_field_name("declarator")      # C / C++
    while d is not None:
        if d.type in _IDENT_TYPES:
            return _text(d)[:80]
        nxt = d.child_by_field_name("declarator")
        if nxt is None:
            for c in d.children:
                if c.type in _IDENT_TYPES:
                    return _text(c)[:80]
            return None
        d = nxt
    p = node.parent                                  # anonymous fn assigned to a name
    if p is not None:
        n = None
        if p.type in ("variable_declarator", "public_field_definition", "field_definition", "pair"):
            n = p.child_by_field_name("name") or p.child_by_field_name("key")
        elif p.type == "assignment_expression":
            n = p.child_by_field_name("left")
        if n is not None:
            return _text(n)[:80]
    return None


def _ast_tokens(node, skip_span: Optional[Tuple[int, int]]) -> List[str]:
    out: List[str] = []
    stack = [node]
    while stack:
        n = stack.pop()
        t = n.type
        if skip_span and (n.start_byte, n.end_byte) == skip_span:
            continue
        if "comment" in t or t in _TYPE_NODES:
            continue
        if _is_str(t):
            out.append("<str>")
            continue
        if _is_num(t):
            out.append("<num>")
            continue
        if n.child_count == 0:
            out.extend(canon_text(_text(n)))
        else:
            stack.extend(reversed(n.children))
    return out


def _extract_ast(tree_root, spec: LangSpec, rel: str, use_names: bool) -> List[FunctionBlock]:
    blocks: List[FunctionBlock] = []
    stack = [tree_root]
    while stack:
        node = stack.pop()
        if node.type in spec.function_nodes:
            name = _node_name(node)
            if name:
                name_node = node.child_by_field_name("name")
                skip = (name_node.start_byte, name_node.end_byte) if name_node is not None else None
                toks = _ast_tokens(node, skip)
                if use_names:
                    toks = split_identifier(name) + toks
                blocks.append(FunctionBlock(rel, name, spec.name, node.start_point[0] + 1,
                                            node.end_point[0] + 1, toks, backend="tree-sitter"))
                continue                       # do not descend: nested closures belong to the parent
        stack.extend(reversed(node.children))
    blocks.sort(key=lambda b: b.start_line)
    return blocks


# ============================================================================
# regex / scanner fallback
# ============================================================================
_CTRL = frozenset("if for while switch catch else return sizeof synchronized foreach using lock do try "
                  "new delete throw case elif with".split())


@dataclass
class _Raw:
    name: str
    start_line: int
    end_line: int
    body: str            # source text after the function name (params + body)


def _scan_re(style: str):
    return re.compile(rf"(?P<c>{COMMENT_RE[style]})|(?P<s>{STR_RES[style]})|(?P<b>[{{}}])")


_SCAN = {k: _scan_re(k) for k in COMMENT_RE}


def _match_brace(text: str, open_idx: int, style: str) -> Optional[int]:
    depth = 0
    for m in _SCAN[style].finditer(text, open_idx):
        if m.lastgroup != "b":
            continue
        depth += 1 if m.group() == "{" else -1
        if depth == 0:
            return m.start()
    return None


def _open_brace(text: str, pos: int, style: str) -> Optional[int]:
    """First '{' after pos that opens a body (skips interface{}/struct{}); None for bodiless decls."""
    while True:
        b, s = text.find("{", pos), text.find(";", pos)
        if b == -1 or (s != -1 and s < b):
            return None
        head = text[:b].rstrip()
        if head.endswith("interface") or head.endswith("struct"):
            e = _match_brace(text, b, style)
            if e is None:
                return None
            pos = e + 1
            continue
        return b


_B = re.M
_HEADERS = {
    "js": [
        (re.compile(r"\bfunction\s*\*?\s*(?P<name>[A-Za-z_$][\w$]*)\s*\("), "search"),
        (re.compile(r"\b(?:const|let|var)\s+(?P<name>[A-Za-z_$][\w$]*)\s*(?::[^=\n]+)?=\s*(?:async\s*)?"
                    r"(?:function\b[^(]*\(|\([^)]*\)\s*(?::\s*[^={\n]+)?\s*=>|[A-Za-z_$][\w$]*\s*=>)"), "arrow"),
        (re.compile(r"^[ \t]*(?:(?:public|private|protected|static|async|readonly|override|get|set)\s+)*"
                    r"(?P<name>[A-Za-z_$][\w$]*)\s*\([^)]*\)\s*(?::\s*[^{;\n]+)?\s*\{", _B), "ends_brace"),
    ],
    "clike": [
        (re.compile(r"^[ \t]*(?:[\w<>\[\],.:*&~?]+[ \t]+)+(?P<name>[A-Za-z_~][\w:~<>]*)[ \t]*\([^;{}]*\)"
                    r"[ \t\r\n]*(?:(?:const|noexcept|override|final|throws[ \t]+[\w., \t]+)[ \t\r\n]*)*\{", _B),
         "ends_brace"),
    ],
    "go": [(re.compile(r"^func[ \t]*(?:\([^)]*\)[ \t]*)?(?P<name>[A-Za-z_]\w*)[ \t]*(?:\[[^\]]*\])?[ \t]*\(", _B),
            "search")],
    "rust": [(re.compile(r"\bfn\s+(?P<name>[A-Za-z_]\w*)"), "search")],
    "bash": [   # `function f {`, `function f() {`  and  `f() {`  (the brace may sit on the next line)
        (re.compile(r"^[ \t]*function[ \t]+(?P<name>[\w.:@+-]+)[ \t]*(?:\([ \t]*\))?[ \t\r\n]*\{", _B), "ends_brace"),
        (re.compile(r"^[ \t]*(?P<name>[\w.:@+-]+)[ \t]*\([ \t]*\)[ \t\r\n]*\{", _B), "ends_brace"),
    ],
}
_HEADER_GROUP = {"javascript": "js", "typescript": "js", "tsx": "js", "java": "clike", "c": "clike",
                 "cpp": "clike", "csharp": "clike", "go": "go", "rust": "rust", "bash": "bash"}


def _brace_functions(text: str, spec: LangSpec) -> List[_Raw]:
    cands = []
    for pat, mode in _HEADERS[_HEADER_GROUP[spec.name]]:
        for m in pat.finditer(text):
            if m.group("name") in _CTRL:
                continue
            cands.append((m.start(), m, mode))
    cands.sort(key=lambda c: c[0])
    out: List[_Raw] = []
    last_end = -1
    for start, m, mode in cands:
        if start < last_end:
            continue
        if mode == "ends_brace":
            ob: Optional[int] = m.end() - 1
        elif mode == "arrow":
            rest = text[m.end():m.end() + 80]
            ob = m.end() + (len(rest) - len(rest.lstrip())) if rest.lstrip().startswith("{") else None
        else:
            ob = _open_brace(text, m.end(), spec.comment_style)
        if ob is None:
            continue
        end = _match_brace(text, ob, spec.comment_style)
        if end is None:
            continue
        # header regexes anchor at line start with indentation; report the keyword's line
        out.append(_Raw(m.group("name"), text.count("\n", 0, start + (len(m.group()) - len(m.group().lstrip()))) + 1,
                        text.count("\n", 0, end) + 1, text[m.end("name"):end + 1]))
        last_end = end + 1
    return out


def _indent(line: str) -> int:
    e = line.expandtabs(4)
    return len(e) - len(e.lstrip())


_PY_STR = re.compile(STR_RE)


def _py_code(line: str) -> str:
    """Line with string literals blanked and the trailing comment removed (for bracket / colon scanning)."""
    return re.sub(r"#.*", "", _PY_STR.sub('""', line))


def _python_functions(lines: List[str]) -> List[_Raw]:
    pat = re.compile(r"^([ \t]*)(?:async[ \t]+)?def[ \t]+(\w+)")
    out, i, n = [], 0, len(lines)
    while i < n:
        m = pat.match(lines[i])
        if not m:
            i += 1
            continue
        base, depth, j, colon = _indent(lines[i]), 0, i, None
        while j < n and j - i < 40 and colon is None:    # find the ':' that ends the (multi-line) header
            seg = _py_code(lines[j])
            for k in range(m.end(2) if j == i else 0, len(seg)):
                ch = seg[k]
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
                elif ch == ":" and depth == 0:
                    colon = k
                    break
            if colon is None:
                j += 1
        if colon is None:                                 # not a real def header
            i += 1
            continue
        rest = _py_code(lines[j])[colon + 1:].strip()
        last = j
        if rest:                                          # one-liner: `def f(x): return x`
            d = sum(rest.count(c) for c in "([{") - sum(rest.count(c) for c in ")]}")
            while d > 0 and last + 1 < n:                 # inline body continues inside open brackets
                last += 1
                seg = _py_code(lines[last])
                d += sum(seg.count(c) for c in "([{") - sum(seg.count(c) for c in ")]}")
        else:
            k = j + 1
            while k < n:
                if lines[k].strip():
                    if _indent(lines[k]) <= base:
                        break
                    last = k
                k += 1
        body = "\n".join([lines[i][m.end(2):]] + lines[i + 1:last + 1])
        out.append(_Raw(m.group(2), i + 1, last + 1, body))
        i = last + 1
    return out


def _ruby_functions(lines: List[str]) -> List[_Raw]:
    pat = re.compile(r"^([ \t]*)def[ \t]+(?:self\.)?([\w?!=]+)")
    out, i, n = [], 0, len(lines)
    while i < n:
        m = pat.match(lines[i])
        if not m:
            i += 1
            continue
        base, k = _indent(lines[i]), i + 1
        while k < n and not (_indent(lines[k]) == base and re.match(r"^[ \t]*end\b", lines[k])):
            k += 1
        k = min(k, n - 1)
        out.append(_Raw(m.group(2), i + 1, k + 1, "\n".join([lines[i][m.end(2):]] + lines[i + 1:k + 1])))
        i = k + 1
    return out


def _extract_regex(text: str, spec: LangSpec, rel: str, use_names: bool) -> List[FunctionBlock]:
    if spec.block_style == "indent":
        raws = _python_functions(text.splitlines())
    elif spec.block_style == "end":
        raws = _ruby_functions(text.splitlines())
    else:
        raws = _brace_functions(text, spec)
    blocks = []
    for r in raws:
        toks = regex_tokens(r.body, spec.comment_style)
        if use_names:
            toks = split_identifier(r.name) + toks
        blocks.append(FunctionBlock(rel, r.name, spec.name, r.start_line, r.end_line, toks, backend="regex"))
    return blocks


# ============================================================================
# python stdlib backend (ast for function extents, tokenize for the token stream)
# ============================================================================
def _py_tokens(segment: str) -> List[str]:
    """Normalised tokens via the real Python lexer (exact strings / f-strings / comments)."""
    import io
    import tokenize
    out: List[str] = []
    fdepth = 0
    for tok in tokenize.generate_tokens(io.StringIO(segment).readline):
        name = tokenize.tok_name.get(tok.type, "")
        if name == "FSTRING_START":
            if fdepth == 0:
                out.append("<str>")
            fdepth += 1
        elif name == "FSTRING_END":
            fdepth = max(0, fdepth - 1)
        elif fdepth:
            continue                                    # f-string internals are one <str>
        elif name == "NAME":
            out.extend(canon_text(tok.string))
        elif name == "NUMBER":
            out.append("<num>")
        elif name == "STRING":
            out.append("<str>")
        elif name == "OP":
            out.extend(canon_text(tok.string))
    return out


def _extract_python_ast(text: str, rel: str, use_names: bool) -> Optional[List[FunctionBlock]]:
    """Exact function extents from `ast`; None if the file does not parse (e.g. Python 2, broken code)."""
    import ast
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError, RecursionError, MemoryError):
        return None
    lines = text.splitlines()
    found = []
    stack = [tree]
    while stack:
        node = stack.pop()
        for ch in ast.iter_child_nodes(node):
            if isinstance(ch, (ast.FunctionDef, ast.AsyncFunctionDef)):
                found.append(ch)                        # nested closures belong to the parent: do not descend
            else:
                stack.append(ch)
    blocks: List[FunctionBlock] = []
    for n in sorted(found, key=lambda f: f.lineno):
        end = getattr(n, "end_lineno", None) or n.lineno
        seg = "\n".join(lines[n.lineno - 1:end])
        head = seg.find(n.name)
        body = seg[head + len(n.name):] if head >= 0 else seg
        try:
            toks = _py_tokens(body)
        except Exception:                               # tokenize can choke on odd dedents: fall back per function
            toks = regex_tokens(body, "hash")
        if use_names:
            toks = split_identifier(n.name) + toks
        blocks.append(FunctionBlock(rel, n.name, "python", n.lineno, end, toks, backend="python-ast"))
    return blocks


# ============================================================================
def extract_file(rel: str, text: str, spec: LangSpec, ts: Optional[TreeSitterBackend],
                 use_names: bool = False, force_regex: bool = False) -> Tuple[List[FunctionBlock], str]:
    """Return (function blocks, backend used)."""
    if ts is not None and not force_regex:
        parser = ts.parser_for(spec)
        if parser is not None:
            try:
                tree = parser.parse(text.encode("utf-8"))
                return _extract_ast(tree.root_node, spec, rel, use_names), "tree-sitter"
            except Exception:
                pass
        if spec.name == "python":                      # no grammar installed -> the stdlib parser is still exact
            blocks = _extract_python_ast(text, rel, use_names)
            if blocks is not None:
                return blocks, "python-ast"
    return _extract_regex(text, spec, rel, use_names), "regex"
