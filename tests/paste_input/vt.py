"""A tiny terminal emulator (no dependencies): enough of CSI to follow the app's input rows.
Screen(cols, rows).feed(bytes) -> .lines() / .cursor (row, col)."""
import re, unicodedata
class Screen:
    def __init__(self, cols=80, rows=30):
        self.cols, self.rows = cols, rows
        self.buf = [[' '] * cols for _ in range(rows)]
        self.r = self.c = 0; self.pend = b''; self.wrap = False; self.saved = (0, 0)
    @property
    def cursor(self): return (self.r, self.c)
    def _lf(self):
        if self.r == self.rows - 1:
            self.buf.pop(0); self.buf.append([' '] * self.cols)
        else: self.r += 1
    def _put(self, ch):
        w = 2 if unicodedata.east_asian_width(ch) in 'WF' else (0 if unicodedata.combining(ch) else 1)
        if w == 0: return
        if self.wrap or self.c + w > self.cols:
            self.c = 0; self._lf()
        self.wrap = False
        self.buf[self.r][self.c] = ch
        if w == 2 and self.c + 1 < self.cols: self.buf[self.r][self.c + 1] = ''
        self.c += w
        if self.c >= self.cols: self.c = self.cols - 1; self.wrap = True
    def feed(self, data):
        s = (self.pend + data).decode('utf-8', 'ignore'); self.pend = b''
        i = 0; n = len(s)
        while i < n:
            ch = s[i]
            if ch == '\x1b':
                m = re.match(r'\x1b\[([0-9;?]*)([A-Za-z])', s[i:])
                if not m:
                    if re.match(r'\x1b(\[[0-9;?]*)?$', s[i:]): break
                    m2 = re.match(r'\x1b\][^\x07]*\x07', s[i:])
                    i += len(m2.group(0)) if m2 else 1; continue
                self._csi(m.group(1), m.group(2)); i += len(m.group(0)); continue
            if ch == '\r': self.c = 0; self.wrap = False
            elif ch == '\n': self._lf(); self.wrap = False
            elif ch == '\x08': self.c = max(0, self.c - 1); self.wrap = False
            elif ch == '\x07' or ord(ch) < 32: pass
            else: self._put(ch)
            i += 1
    def _csi(self, a, f):
        n = int(a.split(';')[0]) if a and a.split(';')[0].isdigit() else None
        self.wrap = False if f in 'ABCDGKJ' else self.wrap
        if f == 'A': self.r = max(0, self.r - (n or 1))
        elif f == 'B': self.r = min(self.rows - 1, self.r + (n or 1))
        elif f == 'C': self.c = min(self.cols - 1, self.c + (n or 1))
        elif f == 'D': self.c = max(0, self.c - (n or 1))
        elif f == 'G': self.c = max(0, (n or 1) - 1)
        elif f == 'K':
            if (n or 0) == 0: self.buf[self.r][self.c:] = [' '] * (self.cols - self.c)
            elif n == 2: self.buf[self.r] = [' '] * self.cols
        elif f == 'J':
            if (n or 0) == 0:
                self.buf[self.r][self.c:] = [' '] * (self.cols - self.c)
                for k in range(self.r + 1, self.rows): self.buf[k] = [' '] * self.cols
            elif n == 2: self.buf = [[' '] * self.cols for _ in range(self.rows)]
        elif f == 's': self.saved = (self.r, self.c)          # save / restore cursor (the app repaints list rows that way)
        elif f == 'u': self.r, self.c = self.saved
        elif f == 'H':
            p = a.split(';'); self.r = min(self.rows - 1, int(p[0] or 1) - 1) if p[0] else 0
            self.c = min(self.cols - 1, int(p[1] or 1) - 1) if len(p) > 1 and p[1] else 0
    def lines(self): return [''.join(x).rstrip() for x in self.buf]
