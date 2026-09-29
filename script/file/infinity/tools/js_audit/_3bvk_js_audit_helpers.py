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
    _RE_CLASS_DECL, _RE_FUNC_PARAMS,
    _JS_KEYWORDS, _HTML_KW,
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
def extract_param_names(source):
    """
    Return every parameter name from any function/arrow signature in source.
    Parameters are locally scoped and must never be flagged as missing imports.

    Handles all JS function forms:
      function foo(a, b)          -> {a, b}
      function(resolve, reject)   -> {resolve, reject}
      (a, b) =>                   -> {a, b}
      res =>                      -> {res}
    """
    params = set()
    for m in _RE_FUNC_PARAMS.finditer(source):
        # group(3): single bare-param arrow  e.g.  res =>  /  predicate =>
        if m.group(3):
            name = m.group(3).strip()
            if name and re.match(r'^[A-Za-z_$]\w*$', name) and name not in _JS_KEYWORDS:
                params.add(name)
            continue
        # group(1): function(...)  /  function name(...)
        # group(2): (a, b) =>  — may have a leading '(' from outer call context
        raw = m.group(1) or m.group(2) or ''
        for token in raw.split(','):
            token = token.strip().lstrip('({[').strip()
            name = re.split(r'[=:\s]', token)[0].strip().strip("'\"")
            if name and re.match(r'^[A-Za-z_$]\w*$', name) and name not in _JS_KEYWORDS:
                params.add(name)
    return params


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
        self.class_names    = set()
        self.param_names    = set()   # all param names from function signatures
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
        self.param_names    = extract_param_names(clean)
        for m in _RE_CLASS_DECL.finditer(clean):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.class_names.add(name)
        self.window_globals = set(_RE_WINDOW_ASSIGN.findall(clean))
        self.iife_present   = bool(_RE_IIFE.search(clean))
    def _regex_is_top(self, clean, pos):
        before = clean[:pos]
        return not (_RE_FUNC_DECL.search(before) or _RE_FUNC_EXPR.search(before))

# ── HTML global-name collection (used by audits 1c, 1d, 1e) ─────────────
def _is_external_url(src):
    s = src.strip().lower()
    return s.startswith('http://') or s.startswith('https://') or s.startswith('//')


def _strip_js_comments(src):
    src = _RE_COMMENT_BLOCK.sub('', src)
    return re.sub(r'//[^\n]*', '', src)


# Matches loadScript("url") or loadScript('url') anywhere in the document,
# including inside CDATA blocks and Blogger widget-setting wrappers.
_RE_LOAD_SCRIPT_GLOBAL = re.compile(
    r'(?<![.\w])loadScript\s*\(\s*(?:"([^"]+)"|\'([^\']+)\')\s*[,)]',
    re.MULTILINE,
)
_RE_LOAD_MODULE_GLOBAL = re.compile(
    r'(?<![.\w])loadModule\s*\(\s*(?:"([^"]+)"|\'([^\']+)\')\s*[,)]',
    re.MULTILINE,
)


def _collect_global_names_from_classic_scripts(html_path: Path, all_js: dict, root: Path) -> set:
    """
    Scan the entire HTML file text for every script loaded as a classic
    (non-module) script -- via static <script src>, loadScript(), or any
    equivalent pattern anywhere in the file (including CDATA / Blogger
    widget-setting blocks).

    Collect every function name defined in those scripts.  These names land
    on window/global scope and are legitimately callable from any other
    classic script on the same page without an import.

    loadModule() calls are excluded: module top-level bindings are NOT global.
    Remote/external URLs are skipped (source not available locally).
    """
    global_names = set()

    try:
        html_src = read_file(html_path)
    except Exception:
        return global_names

    script_srcs = []  # list of (src_attr, is_module)

    # 1. Static <script src="..."> tags (existing behaviour)
    _re_script_tag = re.compile(r'<script([^>]*)>', re.IGNORECASE)
    _re_src        = re.compile(r'\bsrc=["\']([^"\']+)["\']', re.IGNORECASE)
    _re_type       = re.compile(r'\btype=["\']([^"\']+)["\']', re.IGNORECASE)
    for m in _re_script_tag.finditer(html_src):
        attrs     = m.group(1)
        src_m     = _re_src.search(attrs)
        type_m    = _re_type.search(attrs)
        is_module = bool(type_m and 'module' in type_m.group(1).lower())
        if src_m:
            script_srcs.append((src_m.group(1), is_module))

    # 2. loadScript("url") calls anywhere in the document (covers CDATA,
    #    Blogger b:widget-setting blocks, inline <script> bodies, etc.)
    for m in _RE_LOAD_SCRIPT_GLOBAL.finditer(html_src):
        src = m.group(1) or m.group(2)
        if src:
            script_srcs.append((src, False))   # classic

    # 3. loadModule("url") calls -- is_module=True, will be excluded below
    for m in _RE_LOAD_MODULE_GLOBAL.finditer(html_src):
        src = m.group(1) or m.group(2)
        if src:
            script_srcs.append((src, True))    # module -- excluded below

    # Build a filename -> JSFileInfo map for fallback matching of CDN URLs
    filename_to_finfo = {}
    for fpath, finfo in all_js.items():
        filename_to_finfo.setdefault(fpath.name, []).append(finfo)

    # Functions and classes defined directly in inline <script> blocks are
    # globally available to all classic scripts on the same page.
    # HTMLFileInfo._parse() already extracts these into inline_script_globals.
    try:
        global_names |= HTMLFileInfo(html_path).inline_script_globals
    except Exception:
        pass

    for src_attr, is_module in script_srcs:
        if is_module:       # modules are scoped, not global
            continue

        finfo = None

        if not _is_external_url(src_attr):
            # Try local path resolution first
            rp = resolve_script_ref(src_attr, root, html_path)
            if rp is not None and rp in all_js:
                finfo = all_js[rp]
        else:
            # For CDN / external URLs, match by filename.
            # e.g. "https://cdn.../notes-state.js" -> notes-state.js in all_js.
            fname = src_attr.rstrip('/').split('/')[-1].split('?')[0]
            candidates = filename_to_finfo.get(fname, [])
            if len(candidates) == 1:
                finfo = candidates[0]
            # If multiple local files share the same name, skip (ambiguous).

        if finfo is None:
            continue

        clean = _strip_js_comments(finfo.source)

        global_names.update(finfo.functions.keys())
        global_names.update(getattr(finfo, "class_names", set()))   # classes are also global in classic scripts
        for m in re.finditer(r'\bfunction\s+(\w+)\s*\(', clean):
            global_names.add(m.group(1))
        for m in re.finditer(
            r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|\w+)\s*=>',
            clean,
        ):
            global_names.add(m.group(1))
        for m in re.finditer(
            r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function\s*\(',
            clean,
        ):
            global_names.add(m.group(1))

    return global_names


def _collect_window_globals(all_js) -> set:
    """
    Return the union of window_globals across every JS file in the project.

    Any file -- classic or module -- can do  window.foo = ...  which puts foo
    on the global scope unconditionally.  JSFileInfo already tracks these via
    window_globals; we just aggregate them here.
    """
    names = set()
    for finfo in all_js.values():
        names |= getattr(finfo, "window_globals", set())
    return names


def build_html_global_names(js_info, all_js, root) -> set:
    """
    Build the complete set of names that are legitimately on the global scope
    for the page that loads js_info, combining two sources:

    1. Functions defined in classic (non-module) scripts loaded by the HTML --
       these land on window automatically because classic scripts share the
       global scope.

    2. Explicit window.X = ... assignments from ANY JS file (classic or
       module).  A module that does  window.saveFoldState = saveFoldState
       is deliberately publishing to the global scope; callers that reach for
       it as a bare  saveFoldState()  call are correct and must not be flagged.
    """
    html_files = sorted(root.rglob('*.html')) + sorted(root.rglob('*.htm'))

    loading_html = []
    js_name = js_info.path.name
    for html_path in html_files:
        try:
            html_src = read_file(html_path)
        except Exception:
            continue
        if js_name in html_src:
            loading_html.append(html_path)

    if not loading_html:
        idx = _find_index_html(root)
        if idx:
            loading_html = [idx]

    global_names = set()
    for html_path in loading_html:
        global_names |= _collect_global_names_from_classic_scripts(html_path, all_js, root)

    # Explicit window.X = ... assignments from any JS file publish to the
    # global scope regardless of whether the file is a module or classic script.
    global_names |= _collect_window_globals(all_js)

    return global_names



class ScriptRef:
    def __init__(self, src_attr, is_module):
        self.src_attr  = src_attr
        self.is_module = is_module
class HTMLFileInfo:
    def __init__(self, path: Path):
        self.path                  = path
        self.rel_path              = rel(path)
        self.source                = read_file(path)
        self.script_refs           = []
        self.inline_events         = []
        self.inline_script_globals = set()   # function/class names defined in inline <script> blocks
        self._parse()

    def _parse(self):
        for m in _RE_SCRIPT_TAG.finditer(self.source):
            attrs     = m.group(1)
            body      = m.group(2)
            src_m     = _RE_SCRIPT_SRC.search(attrs)
            type_m    = _RE_SCRIPT_TYPE.search(attrs)
            is_module = bool(type_m and 'module' in type_m.group(1).lower())
            if src_m:
                self.script_refs.append(ScriptRef(src_m.group(1), is_module))
            # Collect names defined in inline <script> bodies regardless of
            # whether the block also has a src= attribute.  Functions and
            # classes defined here are globally visible to all classic scripts
            # on the same page.
            if body and body.strip():
                self._extract_inline_globals(body)
        for m in _RE_INLINE_EVT.finditer(self.source):
            code  = m.group(1)
            funcs = [f for f in _RE_FUNC_CALL.findall(code) if f not in _HTML_KW]
            if funcs:
                self.inline_events.append((code, funcs))

    def _extract_inline_globals(self, js_body):
        """
        Collect every function and class name defined at the top level of an
        inline <script> block.  These land on the global scope and are
        available to all classic scripts loaded by the same page.
        """
        import re as _re
        # function declarations:  function foo(...)  /  async function foo(...)
        for m in _re.finditer(r'\bfunction\s+(\w+)\s*\(', js_body):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.inline_script_globals.add(name)
        # function expressions assigned to var/let/const:  const foo = function / const foo = () =>
        for m in _re.finditer(
            r'\b(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:function\b|(?:\([^)]*\)|\w+)\s*=>)',
            js_body,
        ):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.inline_script_globals.add(name)
        # class declarations:  class Foo  /  class Foo extends Bar
        for m in _re.finditer(r'\bclass\s+(\w+)(?:\s+extends\s+\w+)?\s*\{', js_body):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.inline_script_globals.add(name)
        # window.foo = ...  explicit global assignments
        for m in _re.finditer(r'\bwindow\.(\w+)\s*=', js_body):
            name = m.group(1)
            if name and name not in _JS_KEYWORDS:
                self.inline_script_globals.add(name)
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
