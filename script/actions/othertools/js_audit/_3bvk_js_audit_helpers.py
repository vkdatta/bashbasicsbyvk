import re
import sys
from pathlib import Path
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
try:
    import esprima
    HAS_ESPRIMA = True
except ImportError:
    HAS_ESPRIMA = False
    print("[WARN] esprima not installed. Falling back to regex-based parsing.")
from _3bvk_js_audit_constants import (
    CLR_OK_BG, CLR_OK_FG, CLR_ERROR_BG, CLR_ERROR_FG,
    CLR_WARN_BG, CLR_WARN_FG, CLR_INFO_BG, CLR_INFO_FG,
    CLR_DEAD_BG, CLR_DEAD_FG, CLR_ROW_ODD,
    FONT_NAME,
    _RE_IMPORT_NAMED, _RE_IMPORT_STAR,
    _RE_EXPORT_FUNC, _RE_EXPORT_CONST, _RE_EXPORT_CLASS,
    _RE_EXPORT_LIST, _RE_EXPORT_FUNC_EXPR, _RE_EXPORT_ARROW,
    _RE_FUNC_DECL, _RE_FUNC_EXPR, _RE_ARROW_PAREN, _RE_ARROW_BARE,
    _RE_METHOD_SHORTHAND, _RE_WINDOW_ASSIGN, _RE_IIFE, _RE_COMMENT_BLOCK,
    _RE_SCRIPT_TAG, _RE_SCRIPT_SRC, _RE_SCRIPT_TYPE,
    _RE_INLINE_EVT, _RE_FUNC_CALL,
    _JS_KEYWORDS, _HTML_KW,
    _RE_LOAD_SCRIPT, _RE_LOAD_MODULE,
    _RE_CREATE_SCRIPT, _RE_SCRIPT_SRC_ASSIGN,
    _RE_SCRIPT_TYPE_MODULE, _RE_SCRIPT_APPEND,
)
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
def _fill(hex_color):
    return PatternFill("solid", fgColor=hex_color)
def _font(bold=False, color="000000", size=10):
    return Font(name=FONT_NAME, bold=bold, color=color, size=size)
def _border_thin():
    s = Side(style="thin", color="D0D0D0")
    return Border(left=s, right=s, top=s, bottom=s)
def _align(wrap=True, h="left", v="center"):
    return Alignment(horizontal=h, vertical=v, wrap_text=wrap)
def _status_style(status):
    s = (status or "").strip().upper()
    if s == "OK":
        return _fill(CLR_OK_BG),    _font(color=CLR_OK_FG,    bold=True)
    if s == "ERROR":
        return _fill(CLR_ERROR_BG), _font(color=CLR_ERROR_FG, bold=True)
    if s in ("WARN", "WARNING"):
        return _fill(CLR_WARN_BG),  _font(color=CLR_WARN_FG,  bold=True)
    if s == "INFO":
        return _fill(CLR_INFO_BG),  _font(color=CLR_INFO_FG,  bold=True)
    if s == "DEAD":
        return _fill(CLR_DEAD_BG),  _font(color=CLR_DEAD_FG,  bold=True)
    if s == "ACTIVE":
        return _fill(CLR_OK_BG),    _font(color=CLR_OK_FG,    bold=True)
    return _fill(CLR_ROW_ODD), _font()
def collect_files(root: Path):
    js_files   = sorted(root.rglob("*.js"))
    html_files = sorted(root.rglob("*.html")) + sorted(root.rglob("*.htm"))
    return js_files, html_files
def strip_comments(src):
    src = _RE_COMMENT_BLOCK.sub('', src)
    return re.sub(r'//[^\n]*', '', src)
def rel(path: Path) -> str:
    try:
        return '/' + path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)
def read_file(path: Path) -> str:
    for enc in ('utf-8', 'utf-8-sig', 'latin-1'):
        try:
            return path.read_text(encoding=enc)
        except UnicodeDecodeError:
            continue
    return ''
def _is_traditional_decl(fname: str, source: str) -> bool:
    pat = re.compile(
        r'(?:^|\n)\s*(?:export\s+)?(?:async\s+)?function\s+' + re.escape(fname) + r'\s*\('
        r'|\(\s*(?:async\s+)?function\s+' + re.escape(fname) + r'\s*\(',
        re.MULTILINE,
    )
    return bool(pat.search(source))
class FuncInfo:
    def __init__(self, name, path):
        self.name = name
        self.path = path
class ImportSpec:
    def __init__(self, from_path, names, raw_stmt, is_top, line):
        self.from_path = from_path
        self.names     = names
        self.raw_stmt  = raw_stmt
        self.is_top    = is_top
        self.line      = line
class JSFileInfo:
    def __init__(self, path: Path):
        self.path           = path
        self.rel_path       = rel(path)
        self.source         = read_file(path)
        self.is_es_module   = False
        self.imports        = []
        self.exports        = set()
        self.functions      = {}
        self.window_globals = set()
        self.iife_present   = False
        self._parse()
    def _parse(self):
        if HAS_ESPRIMA:
            self._parse_esprima()
        else:
            self._parse_regex()
    def _parse_esprima(self):
        src = self.source
        try:
            tree = esprima.parseModule(src, {'tolerant': True, 'range': True, 'loc': True})
            self._walk_tree(tree, src)
        except Exception:
            self.is_es_module   = False
            self.imports        = []
            self.exports        = set()
            self.functions      = {}
            self.window_globals = set()
            self.iife_present   = False
            try:
                tree = esprima.parseScript(src, {'tolerant': True, 'range': True, 'loc': True})
                self._walk_tree(tree, src)
            except Exception:
                self._parse_regex()
    def _walk_tree(self, tree, src):
        body = getattr(tree, 'body', [])
        for i, node in enumerate(body):
            typ = node.type
            if typ == 'ImportDeclaration':
                self.is_es_module = True
                raw   = src[node.range[0]:node.range[1]]
                names = []
                for s in node.specifiers:
                    if s.type == 'ImportSpecifier':
                        names.append(s.imported.name)
                    elif s.type == 'ImportNamespaceSpecifier':
                        names.append('*')
                    elif s.type == 'ImportDefaultSpecifier':
                        names.append(s.local.name)
                self.imports.append(ImportSpec(
                    node.source.value, names, raw.strip(),
                    self._esprima_is_top(body, i), node.loc.start.line,
                ))
            elif typ == 'ExportNamedDeclaration':
                self.is_es_module = True
                if node.declaration:
                    d = node.declaration
                    if getattr(d, 'id', None):
                        self.exports.add(d.id.name)
                    elif getattr(d, 'declarations', None):
                        for decl in d.declarations:
                            if getattr(decl, 'id', None):
                                self.exports.add(decl.id.name)
                    self._collect_func_node(node.declaration)
                for s in node.specifiers:
                    self.exports.add(s.exported.name)
            elif typ == 'ExportDefaultDeclaration':
                self.is_es_module = True
                self.exports.add('default')
                if getattr(node, 'declaration', None):
                    self._collect_func_node(node.declaration)
            elif typ == 'ExportAllDeclaration':
                self.is_es_module = True
                self.exports.add('*')
            self._collect_func_node(node)
        self.window_globals = set(_RE_WINDOW_ASSIGN.findall(self.source))
    def _esprima_is_top(self, body, idx):
        for node in body[:idx]:
            if node.type not in ('ImportDeclaration', 'ExpressionStatement'):
                return False
        return True
    def _collect_func_node(self, node):
        typ  = node.type
        name = None
        if typ == 'FunctionDeclaration' and getattr(node, 'id', None):
            name = node.id.name
        elif typ == 'VariableDeclaration':
            for d in node.declarations:
                if d.init and d.init.type in ('FunctionExpression', 'ArrowFunctionExpression'):
                    if getattr(d, 'id', None):
                        name = d.id.name
        elif typ == 'ExpressionStatement':
            expr = node.expression
            if getattr(expr, 'type', None) == 'CallExpression':
                c = expr.callee
                if getattr(c, 'type', None) in ('FunctionExpression', 'ArrowFunctionExpression'):
                    self.iife_present = True
            if getattr(expr, 'type', None) == 'AssignmentExpression':
                left = expr.left
                if getattr(left, 'type', None) == 'MemberExpression':
                    if getattr(left.object, 'name', None) == 'window':
                        self.window_globals.add(left.property.name)
        if name:
            self.functions[name] = FuncInfo(name, self.path)
    def _parse_regex(self):
        src   = self.source
        clean = strip_comments(src)
        if (_RE_IMPORT_NAMED.search(clean) or _RE_IMPORT_STAR.search(clean) or
                _RE_EXPORT_FUNC.search(clean) or _RE_EXPORT_LIST.search(clean)):
            self.is_es_module = True
        for m in _RE_IMPORT_NAMED.finditer(clean):
            names  = [n.strip() for n in m.group(1).split(',') if n.strip()]
            pos    = m.start()
            is_top = self._regex_is_top(clean, pos)
            self.imports.append(ImportSpec(
                m.group(2), names, m.group(0).strip(), is_top,
                clean[:pos].count('\n') + 1,
            ))
        for m in _RE_IMPORT_STAR.finditer(clean):
            pos    = m.start()
            is_top = self._regex_is_top(clean, pos)
            self.imports.append(ImportSpec(
                m.group(1), ['*'], m.group(0).strip(), is_top,
                clean[:pos].count('\n') + 1,
            ))
        for m in _RE_EXPORT_FUNC.finditer(clean):
            name = m.group(1)
            self.exports.add(name)
            self.functions[name] = FuncInfo(name, self.path)
        for m in _RE_EXPORT_CONST.finditer(clean):
            self.exports.add(m.group(1))
        for m in _RE_EXPORT_CLASS.finditer(clean):
            self.exports.add(m.group(1))
        for m in _RE_EXPORT_LIST.finditer(clean):
            for n in m.group(1).split(','):
                n = n.strip().split(' as ')[0].strip()
                if n:
                    self.exports.add(n)
        for m in _RE_EXPORT_FUNC_EXPR.finditer(clean):
            self.functions[m.group(1)] = FuncInfo(m.group(1), self.path)
        for m in _RE_EXPORT_ARROW.finditer(clean):
            self.functions[m.group(1)] = FuncInfo(m.group(1), self.path)
        for m in _RE_FUNC_DECL.finditer(clean):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.functions[name] = FuncInfo(name, self.path)
        for m in _RE_FUNC_EXPR.finditer(clean):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.functions[name] = FuncInfo(name, self.path)
        for m in _RE_ARROW_PAREN.finditer(clean):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.functions[name] = FuncInfo(name, self.path)
        for m in _RE_ARROW_BARE.finditer(clean):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.functions[name] = FuncInfo(name, self.path)
        for m in re.finditer(r'\(\s*function\s+(\w+)\s*\(', clean):
            name = m.group(1)
            if name not in _JS_KEYWORDS:
                self.functions[name] = FuncInfo(name, self.path)
        for m in _RE_METHOD_SHORTHAND.finditer(clean):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.functions[name] = FuncInfo(name, self.path)
        self.window_globals = set(_RE_WINDOW_ASSIGN.findall(clean))
        self.iife_present   = bool(_RE_IIFE.search(clean))
    def _regex_is_top(self, clean, pos):
        before = clean[:pos]
        return not (_RE_FUNC_DECL.search(before) or _RE_FUNC_EXPR.search(before))
def _is_external_url(src):
    """Return True if src is an absolute URL (http/https/protocol-relative)."""
    sl = src.strip().lower()
    return sl.startswith('http://') or sl.startswith('https://') or sl.startswith('//')


class ScriptRef:
    """
    Represents one JavaScript dependency of an HTML file.

    Fields (all existing callers use only src_attr and is_module):
        src_attr   – the raw URL/path string as written in the source
        is_module  – True when the script is loaded as an ES module
        source     – 'static' | 'dynamic'
        loader     – None | 'loadScript' | 'loadModule' (dynamic only)
        is_external – True when src_attr is an absolute/protocol-relative URL
    """
    def __init__(self, src_attr, is_module,
                 source='static', loader=None, is_external=None):
        self.src_attr    = src_attr
        self.is_module   = is_module
        self.source      = source          # 'static' or 'dynamic'
        self.loader      = loader          # None / 'loadScript' / 'loadModule'
        self.is_external = (
            is_external if is_external is not None
            else _is_external_url(src_attr)
        )

    def __repr__(self):
        return (
            f'ScriptRef(src_attr={self.src_attr!r}, is_module={self.is_module}, '
            f'source={self.source!r}, loader={self.loader!r}, '
            f'is_external={self.is_external})'
        )
class HTMLFileInfo:
    def __init__(self, path: Path):
        self.path          = path
        self.rel_path      = rel(path)
        self.source        = read_file(path)
        self.script_refs   = []
        self.inline_events = []
        self._parse()

    # ------------------------------------------------------------------
    # Public parse entry point
    # ------------------------------------------------------------------
    def _parse(self):
        seen_srcs = {}   # src_attr (normalised) -> index in self.script_refs

        # ── 1. Static <script src="..."> tags ──────────────────────────
        for m in _RE_SCRIPT_TAG.finditer(self.source):
            attrs  = m.group(1)
            body   = m.group(2)
            src_m  = _RE_SCRIPT_SRC.search(attrs)
            type_m = _RE_SCRIPT_TYPE.search(attrs)
            is_module = bool(type_m and 'module' in type_m.group(1).lower())

            if src_m:
                src = src_m.group(1)
                sr  = ScriptRef(src, is_module, source='static')
                self._add_script_ref(sr, seen_srcs)

            # ── 2. Dynamic dependencies inside inline <script> blocks ──
            if body.strip():
                self._parse_inline_js(body, seen_srcs)

        # ── 3. Inline event handlers ───────────────────────────────────
        for m in _RE_INLINE_EVT.finditer(self.source):
            code  = m.group(1)
            funcs = [f for f in _RE_FUNC_CALL.findall(code) if f not in _HTML_KW]
            if funcs:
                self.inline_events.append((code, funcs))

    # ------------------------------------------------------------------
    # Dynamic dependency detection inside a single inline JS block
    # ------------------------------------------------------------------
    def _parse_inline_js(self, js_text, seen_srcs):
        """
        Scan one inline <script>…</script> body for dynamic script-loading
        operations and add any discovered ScriptRef objects.

        We use a two-phase approach to handle false positives correctly:
          1. Build a character-position 'mask' where every character that is
             inside a comment or the *outer* quotes of a string literal is
             replaced with a space.  String *delimiters* themselves are kept.
          2. Run detection regexes against the *original* text so the URL
             content is readable, but reject any match whose keyword start
             position falls inside a masked-out (comment/string-content) zone.

        This correctly suppresses:
            // loadScript("fake.js")          ← comment
            const s = 'loadScript("fake")'   ← string content
            console.log(`loadScript("fake")`) ← template literal content
        while still detecting:
            loadScript("real.js")
        """
        mask = self._build_mask(js_text)

        def _keyword_is_real_code(m):
            """True when the match start is not inside a masked-out region."""
            pos = m.start()
            # mask[pos] is a space only when that position was inside a
            # comment or a string literal's content in the original text.
            # If the original character is also a space, that doesn't mean
            # it is masked — we check that mask differs from original.
            return mask[pos] != ' ' or js_text[pos] == ' '

        # 2a. loadScript("url")
        for m in _RE_LOAD_SCRIPT.finditer(js_text):
            if not _keyword_is_real_code(m):
                continue
            src = m.group(1) or m.group(2)
            if src:
                sr = ScriptRef(src, False, source='dynamic', loader='loadScript')
                self._add_script_ref(sr, seen_srcs)

        # 2b. loadModule("url")
        for m in _RE_LOAD_MODULE.finditer(js_text):
            if not _keyword_is_real_code(m):
                continue
            src = m.group(1) or m.group(2)
            if src:
                sr = ScriptRef(src, True, source='dynamic', loader='loadModule')
                self._add_script_ref(sr, seen_srcs)

        # 2c. Generic createElement("script") → .src / .type / appendChild
        # Pass both the original (for URL extraction) and the mask (for
        # filtering) so that only real code positions are used.
        self._parse_create_element_blocks(js_text, mask, seen_srcs)

    # ------------------------------------------------------------------
    # Generic createElement("script") block parser
    # ------------------------------------------------------------------
    def _parse_create_element_blocks(self, js_text, mask, seen_srcs):
        """
        Detect patterns of the form:
            [const|let|var] <varname> = document.createElement("script");
            <varname>.src = "…";
            [<varname>.type = "module";]
            document.body.appendChild(<varname>);

        Variable names are not hard-coded; we track which identifiers were
        assigned a script element and look for their .src/.type/.appendChild
        usage anywhere in the same block.

        We deliberately do NOT track a function-definition body separately
        here; the point is to detect the *calls*, not the definition.  The
        definition of window.loadScript / window.loadModule is already
        handled by detecting the call sites via _RE_LOAD_SCRIPT/_RE_LOAD_MODULE.
        """
        # Collect all var names assigned document.createElement("script").
        # Only consider positions that are real code (not masked out).
        script_vars = set()
        for m in _RE_CREATE_SCRIPT.finditer(js_text):
            if mask[m.start()] == ' ' and js_text[m.start()] != ' ':
                continue   # inside a comment or string literal
            varname = m.group(1)
            if varname:
                script_vars.add(varname)

        if not script_vars:
            return

        # For each script var, collect .src and .type = "module" assignments
        # and verify there is an appendChild call.
        src_by_var    = {}   # varname -> src string
        module_by_var = {}   # varname -> bool (True if .type = "module" seen)
        appended_vars = set()

        for m in _RE_SCRIPT_SRC_ASSIGN.finditer(js_text):
            if mask[m.start()] == ' ' and js_text[m.start()] != ' ':
                continue
            varname = m.group(1)
            if varname in script_vars:
                src = m.group(2) or m.group(3)
                if src and varname not in src_by_var:
                    src_by_var[varname] = src

        for m in _RE_SCRIPT_TYPE_MODULE.finditer(js_text):
            if mask[m.start()] == ' ' and js_text[m.start()] != ' ':
                continue
            varname = m.group(1)
            if varname in script_vars:
                module_by_var[varname] = True

        for m in _RE_SCRIPT_APPEND.finditer(js_text):
            if mask[m.start()] == ' ' and js_text[m.start()] != ' ':
                continue
            varname = m.group(1)
            if varname in script_vars:
                appended_vars.add(varname)

        for varname in script_vars:
            src = src_by_var.get(varname)
            if not src:
                continue
            if varname not in appended_vars:
                continue   # element was created but never inserted → not a dep
            is_module = module_by_var.get(varname, False)
            sr = ScriptRef(src, is_module, source='dynamic', loader=None)
            self._add_script_ref(sr, seen_srcs)

    # ------------------------------------------------------------------
    # Deduplication helper
    # ------------------------------------------------------------------
    def _add_script_ref(self, sr, seen_srcs):
        """
        Add sr to self.script_refs.  If the same src_attr was already seen
        (normalised), update the existing entry rather than adding a duplicate
        so that downstream audits never see the same logical dependency twice.

        The normalisation key strips query strings and fragments for identity
        comparison while preserving the original src_attr string on the object.
        """
        key = sr.src_attr.split('?')[0].split('#')[0].strip()
        if key in seen_srcs:
            existing = self.script_refs[seen_srcs[key]]
            # Prefer static over dynamic; preserve module=True if either says so
            if sr.source == 'static' and existing.source == 'dynamic':
                existing.source    = 'static'
                existing.loader    = None
                existing.is_module = existing.is_module or sr.is_module
            else:
                existing.is_module = existing.is_module or sr.is_module
            return
        seen_srcs[key] = len(self.script_refs)
        self.script_refs.append(sr)

    # ------------------------------------------------------------------
    # Build a same-length mask string for false-positive detection
    # ------------------------------------------------------------------
    @staticmethod
    def _build_mask(js_text):
        """
        Return a string the same length as js_text where every character
        that is inside a // line comment, a /* … */ block comment, or the
        *content* of a string literal (single-quoted, double-quoted, or
        template literal) is replaced with a space.  All other characters
        are copied as-is.

        Callers compare mask[pos] against js_text[pos]: if mask[pos] is a
        space but js_text[pos] is not, that position is inside a
        comment/string and should be ignored by detection regexes.

        This is intentionally lightweight — it is not a full JS parser.
        """
        chars  = list(js_text)
        n      = len(chars)
        i      = 0

        while i < n:
            ch = js_text[i]

            # ── block comment /* … */ ──
            if ch == '/' and i + 1 < n and js_text[i + 1] == '*':
                j = js_text.find('*/', i + 2)
                end = j + 2 if j != -1 else n
                for k in range(i, end):
                    chars[k] = ' '
                i = end
                continue

            # ── line comment // … ──
            if ch == '/' and i + 1 < n and js_text[i + 1] == '/':
                j = js_text.find('\n', i + 2)
                end = j if j != -1 else n
                for k in range(i, end):
                    chars[k] = ' '
                i = end
                continue

            # ── string literals: blank the *content* between quotes ──
            if ch in ('"', "'", '`'):
                quote = ch
                j = i + 1
                while j < n:
                    c = js_text[j]
                    if c == '\\':
                        # escaped character — blank both and skip
                        chars[j] = ' '
                        if j + 1 < n:
                            chars[j + 1] = ' '
                        j += 2
                        continue
                    if c == quote:
                        # closing quote — leave both delimiters visible
                        j += 1
                        break
                    chars[j] = ' '
                    j += 1
                i = j
                continue

            i += 1

        return ''.join(chars)
def resolve_js_path(from_path_str, root, source_file):
    p         = from_path_str.strip()
    candidate = root / p.lstrip('/') if p.startswith('/') else source_file.parent / p
    for t in [candidate, Path(str(candidate) + '.js')]:
        if t.exists():
            return t.resolve()
    return None
def resolve_script_ref(src_attr, root, index_html):
    p = src_attr.strip()
    if p.startswith('/'):
        candidate = root / p.lstrip('/')
    elif index_html:
        candidate = index_html.parent / p
    else:
        candidate = root / p
    for t in [candidate, Path(str(candidate) + '.js')]:
        if t.exists():
            return t.resolve()
    return None
def _find_index_html(root):
    candidates = list(root.glob('index.html')) + list(root.rglob('index.html'))
    return candidates[0] if candidates else None
def _dedup(rows, key_fields):
    seen = set()
    out  = []
    for row in rows:
        key = tuple(row.get(f, '') for f in key_fields)
        if key not in seen:
            seen.add(key)
            out.append(row)
    return out
def _recompute_1e_merge_metadata(ie_rows):
    groups = {}
    for idx, row in enumerate(ie_rows):
        if not row.get('Sub Audit', '').startswith('1e'):
            continue
        mk = (row.get('Source', ''), row.get('Destination', ''))
        groups.setdefault(mk, []).append(idx)
    for mk, indices in groups.items():
        for rank, idx in enumerate(indices):
            ie_rows[idx]['_merge_key']         = mk
            ie_rows[idx]['_is_first_in_group']  = (rank == 0)
            ie_rows[idx]['_group_size']         = len(indices)
            if rank > 0:
                ie_rows[idx]['Suggested Import'] = ''
