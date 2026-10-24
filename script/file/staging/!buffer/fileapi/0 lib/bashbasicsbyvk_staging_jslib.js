'use strict';
// bashbasicsbyvk_staging_jslib.js — the ONE copy of what the node transfer tools share:
//   · the status-line helpers (dw / scols / live / fitv)           used by  staging_ux_crypto, staging_pending_xfer, the node fallbacks in staging_upload.sh
//   · packStatus()   the "📦 Packing tar.gz → 🔐 Encrypting …" line of a streamed pack
//   · writeChunks()  stdin stream → fixed-size chunks → seal → one file per chunk
// Bash finds this file (_bb_jslib in bashbasicsbyvk_fileapi_lib.sh) and hands its path to every node tool as  BB_JSLIB;
// the tools do  require(process.env.BB_JSLIB).  Change a helper HERE and every tool gets it.
const fs = require('fs');

const fmtMB = (b) => (b / 1048576).toFixed(1);

// ---- ONE way to draw a \r-redrawn status line ------------------------------------------
// dw(): display width in terminal cells (emoji / CJK = 2).  live(): erases the row and
// writes with auto-wrap OFF (DECAWM), so a line that is wider than the screen -- or a
// terminal that reports the wrong width (Cloud Shell Android app) -- is clipped instead
// of wrapping, and every \r redraw lands on the SAME row.  fitv(): first variant that fits.
const dw = (s) => { let w = 0; for (const ch of String(s).replace(/\u001b\[[0-9;]*m/g, '')) { const c = ch.codePointAt(0);
  if (c === 0xFE0F || c === 0xFE0E || c === 0x200D || (c >= 0x300 && c <= 0x36F)) continue;
  w += ((c >= 0x1100 && c <= 0x115F) || (c >= 0x2E80 && c <= 0xA4CF) || (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0xFF00 && c <= 0xFF60) || /\p{Emoji_Presentation}/u.test(ch)) ? 2 : 1; } return w; };
const scols = () => Math.max(20, (process.stderr.columns || process.stdout.columns || 60) - 1);
const live = (s) => process.stderr.write('\u001b[?7l\r\u001b[K' + s + '\u001b[?7h');
const fitv = (vs) => { const c = scols(); for (const v of vs) if (dw(v) <= c) return v; return vs[vs.length - 1]; };

// The status line of a streamed pack: add(n) after every piece read from stdin (redraws at most every 150 ms), done() = last draw + newline.
function packStatus() {
  const TTY = process.stderr.isTTY, t0 = Date.now();
  let lastDraw = 0, seen = 0;
  const draw = (final) => {
    if (!TTY) return;
    const now = Date.now(); if (!final && now - lastDraw < 150) return; lastDraw = now;
    const mb = fmtMB(seen), sec = Math.floor((now - t0) / 1000);
    live('\u001b[36m' + fitv([`📦 Packing tar.gz → 🔐 Encrypting  ${mb} MB packed  (${sec}s)`, `📦 Packing → 🔐 Encrypting  ${mb} MB (${sec}s)`, `📦→🔐 ${mb} MB (${sec}s)`, `📦→🔐 ${mb} MB`]) + '\u001b[0m');
    if (final) process.stderr.write('\n');
  };
  return { add(n) { seen += n; draw(false); }, done() { draw(true); } };
}

// writeChunks(stream, { chunk, seal, fileFor, onBytes })
//   Cuts `stream` into pieces of `chunk` bytes (the last one may be shorter); for piece number idx writes  seal(piece, idx)  (a Buffer)
//   to  fileFor(idx)  with mode 0600.  onBytes(n) is called for every block read.  Memory use = one chunk, however big the stream.
//   Resolves { idx: how many chunks, plainTotal, cipherTotal }; read / write errors reject (the caller reports them).
async function writeChunks(stream, { chunk, seal, fileFor, onBytes }) {
  const buf = Buffer.allocUnsafe(chunk);
  let fill = 0, idx = 0, plainTotal = 0, cipherTotal = 0;
  const flush = () => {
    if (fill === 0) return;
    const rec = seal(buf.subarray(0, fill), idx);
    fs.writeFileSync(fileFor(idx), rec, { mode: 0o600 });
    cipherTotal += rec.length; plainTotal += fill; idx++; fill = 0;
  };
  for await (const piece of stream) {
    let off = 0;
    while (off < piece.length) {
      const n = Math.min(chunk - fill, piece.length - off);
      piece.copy(buf, fill, off, off + n);
      fill += n; off += n;
      if (fill === chunk) flush();
    }
    if (onBytes) onBytes(piece.length);
  }
  flush();
  return { idx, plainTotal, cipherTotal };
}

module.exports = { fmtMB, dw, scols, live, fitv, packStatus, writeChunks };
