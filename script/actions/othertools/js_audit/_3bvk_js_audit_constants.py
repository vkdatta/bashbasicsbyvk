import re

CLR_HEADER_BG   = "1F3864"
CLR_HEADER_FG   = "FFFFFF"
CLR_TITLE_BG    = "2E4D8A"
CLR_TITLE_FG    = "FFFFFF"
CLR_OK_BG       = "C6EFCE"
CLR_OK_FG       = "276221"
CLR_ERROR_BG    = "FFC7CE"
CLR_ERROR_FG    = "9C0006"
CLR_WARN_BG     = "FFEB9C"
CLR_WARN_FG     = "9C5700"
CLR_INFO_BG     = "DDEBF7"
CLR_INFO_FG     = "2F5496"
CLR_DEAD_BG     = "D9D9D9"
CLR_DEAD_FG     = "595959"
CLR_ROW_ODD     = "F2F2F2"
CLR_ROW_EVEN    = "FFFFFF"
CLR_ANN_BG      = "4A4A4A"
CLR_ANN_FG      = "FFFFFF"
CLR_1E_MERGE_BG = "EAF0FB"
CLR_1E_MERGE_FG = "1F3864"

FONT_NAME = "Arial"

_RE_IMPORT_NAMED   = re.compile(r'\bimport\s*\{([^}]+)\}\s*from\s*["\']([^"\']+)["\']', re.MULTILINE)
_RE_IMPORT_STAR    = re.compile(r'\bimport\s*\*\s*as\s+\w+\s*from\s*["\']([^"\']+)["\']', re.MULTILINE)
_RE_EXPORT_FUNC    = re.compile(r'\bexport\s+(?:async\s+)?function\s+(\w+)', re.MULTILINE)
_RE_EXPORT_CONST   = re.compile(r'\bexport\s+(?:const|let|var)\s+(\w+)', re.MULTILINE)
_RE_EXPORT_CLASS   = re.compile(r'\bexport\s+class\s+(\w+)', re.MULTILINE)
_RE_EXPORT_LIST    = re.compile(r'\bexport\s*\{([^}]+)\}', re.MULTILINE)
_RE_EXPORT_FUNC_EXPR = re.compile(
    r'\bexport\s+(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function[\s(]', re.MULTILINE)
_RE_EXPORT_ARROW   = re.compile(
    r'\bexport\s+(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$]\w*)\s*=>', re.MULTILINE)
_RE_FUNC_DECL      = re.compile(r'\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)\s*\(')
_RE_FUNC_EXPR      = re.compile(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function[\s(]')
_RE_ARROW_PAREN    = re.compile(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)\s*=>')
_RE_ARROW_BARE     = re.compile(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?([A-Za-z_$]\w*)\s*=>')
_RE_METHOD_SHORTHAND = re.compile(r'(?:^|\n|\{)\s*(\w+)\s*\([^)]*\)\s*\{')
_RE_WINDOW_ASSIGN  = re.compile(r'window\.(\w+)\s*=', re.MULTILINE)
_RE_IIFE           = re.compile(r'(?:^|\n)\s*\(\s*(?:async\s+)?function', re.MULTILINE)
_RE_COMMENT_BLOCK  = re.compile(r'/\*.*?\*/', re.DOTALL)

_RE_SCRIPT_TAG  = re.compile(r'<script([^>]*)>(.*?)</script>', re.IGNORECASE | re.DOTALL)
_RE_SCRIPT_SRC  = re.compile(r'src=["\']([^"\']+)["\']', re.IGNORECASE)
_RE_SCRIPT_TYPE = re.compile(r'type=["\']([^"\']+)["\']', re.IGNORECASE)
_RE_INLINE_EVT  = re.compile(r'(?:on\w+)=["\']([^"\']+)["\']', re.IGNORECASE)
_RE_FUNC_CALL   = re.compile(r'(?<![.\w])(\w+)\s*\(')

_RE_EVT_ATTR = re.compile(
    r'on\w+='
    r'(?:'
        r'"([^"]*)"'
        r"|'([^']*)'"
        r'|([^\s>\'\"]+)'
    r')',
    re.IGNORECASE,
)
_RE_EVT_CALL = re.compile(r'(?<![.\w])([A-Za-z_$]\w*)\s*\(')

_RE_STRING_LITERAL = re.compile(
    r'"(?:[^"\\]|\\.)*"'
    r"|'(?:[^'\\]|\\.)*'"
    r"|`(?:[^`\\]|\\.)*`",
    re.DOTALL,
)
_RE_BARE_CALL = re.compile(r'(?<![.\w])([A-Za-z_$]\w*)\s*\(')

_JS_KEYWORDS = {
    'if','else','for','while','do','switch','case','break','continue',
    'return','typeof','instanceof','new','delete','void','in','of',
    'true','false','null','undefined','this','class','extends',
    'import','export','default','await','yield','async','let','const',
    'var','function','try','catch','finally','throw','super','static',
}

_NATIVE_GLOBALS = {
    'alert','confirm','prompt','console','window','document','navigator',
    'location','history','screen','localStorage','sessionStorage',
    'parseInt','parseFloat','isNaN','isFinite','encodeURIComponent',
    'decodeURIComponent','encodeURI','decodeURI',
    'setTimeout','clearTimeout','setInterval','clearInterval',
    'requestAnimationFrame','cancelAnimationFrame',
    'fetch','eval','escape','unescape','atob','btoa',
    'Array','Object','String','Number','Boolean','Function',
    'RegExp','Date','Error','Symbol','BigInt',
    'Map','Set','WeakMap','WeakSet',
    'Promise','Proxy','Reflect','Intl',
    'Math','JSON','NaN','Infinity',
    'Int8Array','Uint8Array','Uint8ClampedArray',
    'Int16Array','Uint16Array','Int32Array','Uint32Array',
    'Float32Array','Float64Array','ArrayBuffer','DataView',
    'MutationObserver','IntersectionObserver','ResizeObserver',
    'CustomEvent','Event','EventTarget',
    'XMLHttpRequest','WebSocket','Worker','SharedWorker',
    'URL','URLSearchParams',
    'performance','crypto','queueMicrotask','structuredClone',
    'getComputedStyle','matchMedia',
}

_SAFE_LITERALS = {
    'all', 'active', 'none', 'auto', 'manual', 'single', 'multi', 'range',
    'lookback', 'specific', 'fgi', 'ledger', 'debug', 'stocks', 'indices',
    'yes', 'no', 'on', 'off', 'enabled', 'disabled', 'true', 'false',
}

_HTML_KW = {
    'if', 'else', 'for', 'while', 'do', 'switch', 'case',
    'return', 'typeof', 'instanceof', 'new', 'delete', 'void',
    'true', 'false', 'null', 'undefined',
    'alert', 'confirm', 'prompt',
    'parseInt', 'parseFloat', 'isNaN', 'isFinite',
    'encodeURIComponent', 'decodeURIComponent', 'encodeURI', 'decodeURI',
    'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval',
    'requestAnimationFrame', 'cancelAnimationFrame',
    'fetch', 'eval', 'escape', 'unescape',
    'Array', 'Object', 'String', 'Number', 'Boolean', 'Function',
    'RegExp', 'Date', 'Error', 'Symbol', 'BigInt',
    'Map', 'Set', 'WeakMap', 'WeakSet',
    'Promise', 'Proxy', 'Reflect',
    'Math', 'JSON', 'console',
    'Int8Array', 'Uint8Array', 'Uint8ClampedArray',
    'Int16Array', 'Uint16Array', 'Int32Array', 'Uint32Array',
    'Float32Array', 'Float64Array',
}

_EVT_KNOWN = _NATIVE_GLOBALS | _JS_KEYWORDS | {
    'stopPropagation', 'preventDefault', 'target', 'currentTarget',
    'event', 'e', 'evt',
}

_IE_KEY_FIELDS = ('Sub Audit', 'Source', 'Destination', 'Status', 'Comment')
_AD_KEY_FIELDS = ('Source', 'Function Name', 'Status', 'Usage Count', 'Comment')
