"""Cross-language token normalisation.

Both the tree-sitter AST walk and the regex fallback funnel every leaf through
`canon_text`, so the embedding input is built from one shared vocabulary:
comments are dropped, literals collapse to <str>/<num>, identifiers are split
into lower-case sub-words (calculateTax -> calculate tax), declaration/type/
visibility keywords are removed, and equivalent operators are unified.
"""
from __future__ import annotations

import re
from typing import List

_IDENT = re.compile(r"^[A-Za-z_$][\w$]*$")
_SPLIT = re.compile(r"[A-Z]+(?![a-z])|[A-Z]?[a-z]+|\d+")
_DROP_PUNCT = frozenset("{}()[];,:.@#$`")

DROP_WORDS = frozenset("""
let var const val auto final static public private protected async export default override
virtual inline extern pub mut new def function func fn void int float double long short string
String bool boolean number char byte unsigned signed self this cls i8 i16 i32 i64 u8 u16 u32 u64
f32 f64 usize isize str Integer Double Long Boolean Object dynamic throws throw
local declare typeset readonly
""".split())

CANON = {
    "elif": "elif", "elsif": "elif", "elseif": "elif", "foreach": "for", "until": "while",
    "True": "true", "False": "false", "true": "true", "false": "false",
    "null": "null", "nil": "null", "None": "null", "nullptr": "null", "undefined": "null",
    "and": "&&", "or": "||", "not": "!", "===": "==", "!==": "!=", "=>": "->",
}


def split_identifier(name: str) -> List[str]:
    parts: List[str] = []
    for chunk in re.split(r"[_$]+", name):
        parts.extend(m.group(0).lower() for m in _SPLIT.finditer(chunk))
    return parts


def canon_text(text: str, kind: str = "auto") -> List[str]:
    """Normalise one lexical leaf into zero or more canonical tokens."""
    if kind == "comment":
        return []
    if kind == "str":
        return ["<str>"]
    if kind == "num":
        return ["<num>"]
    text = text.strip()
    if not text or text == "$":                  # bare `$` (shell expansion marker / jQuery alias) carries no meaning
        return []
    if _IDENT.match(text):
        if text in DROP_WORDS:
            return []
        if text in CANON:
            return [CANON[text]]
        return split_identifier(text) or [text.lower()]
    if text[0].isdigit():
        return ["<num>"]
    if all(c in _DROP_PUNCT for c in text):
        return []
    return [CANON.get(text, text)]


# --------------------------------------------------------------------------
# Regex tokenizer (used when tree-sitter is unavailable)
# --------------------------------------------------------------------------
STR_RE = (r'"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"(?:\\.|[^"\\\n])*"|'
          r"'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`")
# bash: `#` starts a comment only at a word boundary (not in $#, ${#x}, a#b); strings may span lines, single quotes
# have no escapes, and here-documents are opaque text (they may contain unbalanced quotes and braces).
BASH_STR_RE = (r"<<-?[ \t]*(?P<hq>['\"]?)(?P<hd>[A-Za-z_]\w*)(?P=hq)[^\n]*\n[\s\S]*?\n[ \t]*(?P=hd)[ \t]*(?=\n|\Z)|"
               r"\$'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"|'[^']*'|`(?:\\.|[^`\\])*`")
COMMENT_RE = {"c": r"//[^\n]*|/\*[\s\S]*?\*/", "hash": r"#[^\n]*", "bash": r"(?<![^\s;|&(])#[^\n]*"}
# the bash *scanner* must also skip backslash escapes (`\\"`, `\\'`, `\\{`) that sit outside quotes
STR_RES = {"c": STR_RE, "hash": STR_RE, "bash": r"\\[\s\S]|" + BASH_STR_RE}

_TOKEN_RES = {
    style: re.compile(
        rf"(?P<comment>{c})|(?P<str>{STR_RE})|"
        r"(?P<num>\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?[A-Za-z]*)|"
        r"(?P<id>[A-Za-z_$][\w$]*)|"
        r"(?P<op>===|!==|==|!=|<=|>=|&&|\|\||\+\+|--|->|=>|::|[-+*/%<>=!&|^~?])"
    )
    for style, c in COMMENT_RE.items() if style != "bash"
}
# bash tokens: $var / ${var} / ${#var} / $1 -> the variable name; flags (-n, --force) are kept as words
_TOKEN_RES["bash"] = re.compile(
    rf"(?P<comment>{COMMENT_RE['bash']})|(?P<esc>\\[\s\S])|(?P<str>{BASH_STR_RE})|"
    r"\$\{?[#!]?(?P<var>[A-Za-z_]\w*)|\$[0-9@#?*!$-]|"
    r"(?P<flag>--?[A-Za-z][\w-]*)|"
    r"(?P<num>\d[\d_]*)|"
    r"(?P<id>[A-Za-z_][\w]*)|"
    r"(?P<op>\[\[|\]\]|&&|\|\||;;|>>|<<|==|!=|=~|<=|>=|[-+*/%<>=!&|^~?])"
)


def regex_tokens(text: str, comment_style: str) -> List[str]:
    out: List[str] = []
    for m in _TOKEN_RES[comment_style].finditer(text):
        g = m.lastgroup
        if comment_style == "bash":
            if g == "esc":
                continue
            if g == "var":
                out.extend(canon_text(m.group("var")))
            elif g == "flag":
                out.append(m.group())
            elif g in ("comment", "str", "num"):
                out.extend(canon_text(m.group(), g))
            elif g in ("id", "op"):
                out.extend(canon_text(m.group()))
            # lone special parameters ($1, $@, $?) carry no information
            continue
        out.extend(canon_text(m.group(), g if g in ("comment", "str", "num") else "auto"))
    return out
