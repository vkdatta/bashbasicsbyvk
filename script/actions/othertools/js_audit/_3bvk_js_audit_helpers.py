import re
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
)
ROOT = Path(__file__).resolve().parent
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
class ScriptRef:
    def __init__(self, src_attr, is_module):
        self.src_attr  = src_attr
        self.is_module = is_module
class HTMLFileInfo:
    def __init__(self, path: Path):
        self.path          = path
        self.rel_path      = rel(path)
        self.source        = read_file(path)
        self.script_refs   = []
        self.inline_events = []
        self._parse()
    def _parse(self):
        for m in _RE_SCRIPT_TAG.finditer(self.source):
            attrs  = m.group(1)
            src_m  = _RE_SCRIPT_SRC.search(attrs)
            type_m = _RE_SCRIPT_TYPE.search(attrs)
            is_module = bool(type_m and 'module' in type_m.group(1).lower())
            if src_m:
                self.script_refs.append(ScriptRef(src_m.group(1), is_module))
        for m in _RE_INLINE_EVT.finditer(self.source):
            code  = m.group(1)
            funcs = [f for f in _RE_FUNC_CALL.findall(code) if f not in _HTML_KW]
            if funcs:
                self.inline_events.append((code, funcs))
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
