"""Language registry: extensions, tree-sitter bindings and function node types."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class LangSpec:
    name: str
    extensions: tuple
    ts_module: str          # python package providing the tree-sitter grammar
    ts_factory: str         # callable in that package returning the language pointer
    function_nodes: frozenset
    comment_style: str = "c"        # "c" (// and /* */), "hash" (#) or "bash" (# at word boundary + here-docs)
    block_style: str = "brace"      # brace | indent | end (regex fallback only)


_JS_NODES = frozenset({
    "function_declaration", "generator_function_declaration", "method_definition",
    "arrow_function", "function_expression", "function",
})

_SPECS = (
    LangSpec("python", (".py",), "tree_sitter_python", "language",
             frozenset({"function_definition"}), "hash", "indent"),
    LangSpec("javascript", (".js", ".jsx", ".mjs", ".cjs"), "tree_sitter_javascript", "language", _JS_NODES),
    LangSpec("typescript", (".ts",), "tree_sitter_typescript", "language_typescript", _JS_NODES),
    LangSpec("tsx", (".tsx",), "tree_sitter_typescript", "language_tsx", _JS_NODES),
    LangSpec("java", (".java",), "tree_sitter_java", "language",
             frozenset({"method_declaration", "constructor_declaration"})),
    LangSpec("c", (".c", ".h"), "tree_sitter_c", "language", frozenset({"function_definition"})),
    LangSpec("cpp", (".cpp", ".cc", ".cxx", ".hpp", ".hh", ".hxx"), "tree_sitter_cpp", "language",
             frozenset({"function_definition"})),
    LangSpec("go", (".go",), "tree_sitter_go", "language",
             frozenset({"function_declaration", "method_declaration"})),
    LangSpec("rust", (".rs",), "tree_sitter_rust", "language", frozenset({"function_item"})),
    LangSpec("ruby", (".rb",), "tree_sitter_ruby", "language",
             frozenset({"method", "singleton_method"}), "hash", "end"),
    LangSpec("bash", (".sh", ".bash"), "tree_sitter_bash", "language",
             frozenset({"function_definition"}), "bash", "brace"),
    LangSpec("csharp", (".cs",), "tree_sitter_c_sharp", "language",
             frozenset({"method_declaration", "constructor_declaration", "local_function_statement"})),
)

LANGUAGES = {s.name: s for s in _SPECS}
SHEBANG_LANGS = (("python", ("python",)), ("javascript", ("node", "deno", "bun")), ("ruby", ("ruby",)),
                 ("bash", ("bash", "/sh", " sh", "/dash", "/ash", "/ksh")))   # `#!` interpreter -> language
EXT_TO_LANG = {ext: s.name for s in _SPECS for ext in s.extensions}
