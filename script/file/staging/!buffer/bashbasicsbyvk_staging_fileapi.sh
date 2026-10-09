# Shared endpoint (WORKER_URL), curl hardening (_BB_CURL_OPTS) and _bb_* helpers
source "_3bvk_fileapi_lib.sh"

_SP_SOFT_UPLOAD_BYTES=$((10*1024*1024*1024))
_SP_HARD_LIMIT_BYTES=$((32*1024*1024*1024))

# Streaming-upload tuning. CHUNK_BYTES must match the worker's CHUNK_BYTES (90 MiB):
# any blob at or below this goes up in one PUT, anything larger uses R2 multipart.
# _BB_MAX_PAR is how many blobs/parts upload concurrently.
_BB_CHUNK_BYTES=$((90*1024*1024))
_BB_MAX_PAR="${FILEAPI_BASHBASICS_PARALLEL:-16}"
# The tar.gz stream is cut into encrypted chunks of this size (default 16 MiB) => few requests, no file-size limit.
_BB_PACK_BYTES=$(( ${FILEAPI_BASHBASICS_PACK_MB:-16} * 1024 * 1024 ))

_bb_authed_put() {
  local endpoint="$1" est_size="$2"; shift 2
  local -a extra_args=("$@")

  _bb_get_credentials || return 1

  local attempt=0 confirmed=false
  while :; do
    attempt=$((attempt + 1))

    local cfg
    cfg=$({ _bb_auth_cfg
            [ -n "$est_size" ] && _bb_cfg_header X-Estimated-Size "$est_size"
            $confirmed && _bb_cfg_header X-Confirm-Oversized yes
            true; })
    local hdrfile response http_status body
    hdrfile=$(mktemp)
    response=$(curl -s "${_BB_CURL_OPTS[@]}" -K - -D "$hdrfile" -w "\n%{http_code}" -H "Expect:" -X PUT "${extra_args[@]}" "$WORKER_URL$endpoint" <<<"$cfg")
    http_status=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_status" == "201" ]; then
      local deducted balance
      deducted=$(grep -i '^X-Credits-Deducted:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
      balance=$(grep -i '^X-Credits-Balance:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
      rm -f "$hdrfile"
      printf '%s\n%s\n%s\n' "$body" "$deducted" "$balance"
      return 0
    fi
    rm -f "$hdrfile"

    local err_type msg
    err_type=$(_bb_json_get "$body" error)
    msg=$(_bb_json_get "$body" message)

    # 401 = the saved profile's credentials are wrong. Retrying would just reload
    # the same profile and fail identically, so report once and stop.
    if [ "$http_status" == "401" ]; then
      echo "❌ ${msg:-Authentication failed.}" >&2
      echo "🔁 Fix the active user with  -auth  inside 'o', then try again." >&2
      return 1
    fi

    if [ "$http_status" == "409" ] && [ "$err_type" == "oversized_confirmation_required" ] && ! $confirmed; then
      echo "⚠️  ${msg}" >&2
      read -p "   Proceed at 1.2x credit cost? (y/n): " ans
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        confirmed=true
        continue
      else
        echo "🚫 Cancelled." >&2
        return 1
      fi
    fi

    echo "❌ $(_bb_fail_reason "$body" "$http_status")" >&2
    return 1
  done
}

# Crypto format v2: AES-256-GCM, blob = [12B IV][ciphertext][16B tag], with Additional
# Authenticated Data binding each ciphertext to its role/position:
#   "bbvk2|copy" (c2c-/copy text)   "bbvk4|manifest"   "bbvk4|blob|<index>" (up- archives)
# so a hostile server cannot swap, replay or substitute pieces undetected.

_crypto_check() {
  if ! command -v node &>/dev/null; then
    echo "❌ 'node' is required for encryption (up-/c2c-/do-) but wasn't found in PATH."
    return 1
  fi
  return 0
}

_crypto_new_key() {
  node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+\$/,''))"
}

# usage: _crypto_encrypt_stdin <key-b64url> <aad-string>   (plaintext on stdin, v2 blob on stdout)
_crypto_encrypt_stdin() {
  BB_KEY="$1" BB_AAD="$2" node -e '
    const crypto = require("crypto");
    const chunks = [];
    process.stdin.on("data", c => chunks.push(c));
    process.stdin.on("end", () => {
      const data = Buffer.concat(chunks);
      const key = Buffer.from(process.env.BB_KEY.replace(/-/g,"+").replace(/_/g,"/"), "base64");
      if (key.length !== 32) process.exit(2);
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
      cipher.setAAD(Buffer.from(process.env.BB_AAD, "utf8"));
      const ct = Buffer.concat([cipher.update(data), cipher.final()]);
      const tag = cipher.getAuthTag();
      process.stdout.write(Buffer.concat([iv, ct, tag]));
    });
  '
}

_crypto_decrypt_stdin() {
  BB_KEY="$1" BB_AAD="$2" node -e '
    const crypto = require("crypto");
    const chunks = [];
    process.stdin.on("data", c => chunks.push(c));
    process.stdin.on("end", () => {
      const buf = Buffer.concat(chunks);
      if (buf.length < 28) { process.exit(1); }
      const iv = buf.subarray(0, 12);
      const tag = buf.subarray(buf.length - 16);
      const ct = buf.subarray(12, buf.length - 16);
      const key = Buffer.from(process.env.BB_KEY.replace(/-/g,"+").replace(/_/g,"/"), "base64");
      if (key.length !== 32) process.exit(1);
      try {
        const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
        decipher.setAuthTag(tag);
        decipher.setAAD(Buffer.from(process.env.BB_AAD, "utf8"));
        const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
        process.stdout.write(pt);
      } catch (e) {
        process.exit(1);
      }
    });
  '
}

_announce_link() {
  local final_url="$1"
  local url_payload
  url_payload=$(printf "%s" "$final_url" | base64 | tr -d '\n')

  if [[ "$TERM" == "screen"* ]] || [[ "$TERM" == "tmux"* ]]; then
    printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$url_payload"
  else
    printf "\033]52;c;%s\a" "$url_payload"
  fi

  echo "✅ Link copied to clipboard (best effort). Key is embedded after # — keep the whole link intact."
  echo "-------------------------------------------"
  echo "Link: $final_url"
  echo "-------------------------------------------"

  if [ "${FILEAPI_BASHBASICS_OPEN:-0}" = "1" ]; then
    ( open "$final_url" || xdg-open "$final_url" || termux-open-url "$final_url" ) &> /dev/null &
  else
    echo "ℹ️  Not auto-opened: the browser viewer runs code delivered by the server, which could in theory read the key."
    echo "   Use 'do-' (decrypts on your machine) for the strongest protection, or export FILEAPI_BASHBASICS_OPEN=1 to auto-open."
  fi
}

# Format v4 ("tar.gz stream"): the selection is packed as ONE tar.gz stream, cut into fixed-size
# chunks (default 16 MiB, FILEAPI_BASHBASICS_PACK_MB) and every chunk is encrypted on its own
# with AES-256-GCM: blob record = [12B IV][ciphertext][16B tag], AAD "bbvk4|blob|<index>".
# The manifest (AAD "bbvk4|manifest") holds {version:4, format, name, size, chunkBytes, blobCount}.
# Chunking means NO file-size limit: memory use is one chunk, whatever the archive size, and
# a 58k-file tree is ~50 uploads instead of 58k.  Reads the tar.gz on stdin.
# usage: <tar.gz stream> | _crypto_stream_pack <outdir> <display-name>
# prints: key \n total-cipher-bytes \n blob-count
_crypto_stream_pack() {
  local outdir="$1" arcname="$2"
  BB_PACK_BYTES="${_BB_PACK_BYTES}" BB_ARC_NAME="$arcname" node -e '
    const fs = require("fs"), path = require("path"), crypto = require("crypto");
    const outdir = process.argv[1];
    const CHUNK = parseInt(process.env.BB_PACK_BYTES, 10) || 16 * 1024 * 1024;
    const key = crypto.randomBytes(32);
    const keyB64url = key.toString("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");

    function encrypt(buf, aad) {
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
      cipher.setAAD(Buffer.from(aad, "utf8"));
      const ct = Buffer.concat([cipher.update(buf), cipher.final()]);
      return Buffer.concat([iv, ct, cipher.getAuthTag()]);
    }

    const TTY = process.stderr.isTTY, t0 = Date.now();
    let lastDraw = 0, seen = 0;
    function status(final) {
      if (!TTY) return;
      const now = Date.now();
      if (!final && now - lastDraw < 150) return;
      lastDraw = now;
      const mb = (seen / 1048576).toFixed(1), s = Math.floor((now - t0) / 1000);
      process.stderr.write("\r\u001b[K\u001b[36m\uD83D\uDCE6 Packing tar.gz \u2192 \uD83D\uDD10 Encrypting\u001b[0m  " + mb + " MB packed  (" + s + "s)");
      if (final) process.stderr.write("\n");
    }

    (async () => {
      const buf = Buffer.allocUnsafe(CHUNK);
      let fill = 0, idx = 0, plainTotal = 0, cipherTotal = 0;
      function flush() {
        if (fill === 0) return;
        const rec = encrypt(buf.subarray(0, fill), "bbvk4|blob|" + idx);
        fs.writeFileSync(path.join(outdir, "blob" + idx), rec, { mode: 0o600 });
        cipherTotal += rec.length; plainTotal += fill; idx++; fill = 0;
      }
      try {
        for await (const piece of process.stdin) {
          let off = 0;
          while (off < piece.length) {
            const n = Math.min(CHUNK - fill, piece.length - off);
            piece.copy(buf, fill, off, off + n);
            fill += n; off += n;
            if (fill === CHUNK) flush();
          }
          seen += piece.length;
          status(false);
        }
        flush();
      } catch (e) {
        if (TTY) process.stderr.write("\n");
        console.error("  \u274c " + (e && e.code === "ENOSPC" ? "Disk full while writing encrypted blobs." : "Packing failed: " + (e && e.message)));
        process.exit(3);
      }
      status(true);
      if (idx === 0) { console.error("  \u274c Nothing to pack."); process.exit(2); }

      const manifest = { version: 4, format: "tar.gz", name: process.env.BB_ARC_NAME || "files.tar.gz",
                         size: plainTotal, chunkBytes: CHUNK, blobCount: idx };
      fs.writeFileSync(path.join(outdir, "manifest.enc"), encrypt(Buffer.from(JSON.stringify(manifest), "utf8"), "bbvk4|manifest"), { mode: 0o600 });
      process.stdout.write(keyB64url + "\n" + cipherTotal + "\n" + idx);
    })();
  ' "$outdir"
}

# Download + decrypt a v4 link into <outfile> (a pre-created empty file).
# Chunks are fetched in parallel and written at their exact offset, so order doesn't matter
# and memory stays at a few chunks no matter how big the archive is.
# stdout: "OK<TAB>name" | "EXPIRED" | "BADKEY" | "FAILED"
_crypto_fetch_archive() {
  local link="$1" key="$2" outfile="$3"
  BB_KEY="$key" node -e '
    const fs = require("fs"), crypto = require("crypto");
    const link = process.argv[1], outfile = process.argv[2];
    const key = Buffer.from(process.env.BB_KEY.replace(/-/g,"+").replace(/_/g,"/"), "base64");
    const CONC = Math.max(1, Math.min(parseInt(process.argv[3], 10) || 8, 8));   // 8 x 16 MiB in flight
    const sleep = ms => new Promise(r => setTimeout(r, ms));

    function decrypt(buf, aad) {
      if (buf.length < 28) throw new Error("short");
      const d = crypto.createDecipheriv("aes-256-gcm", key, buf.subarray(0, 12));
      d.setAuthTag(buf.subarray(buf.length - 16));
      d.setAAD(Buffer.from(aad, "utf8"));
      return Buffer.concat([d.update(buf.subarray(12, buf.length - 16)), d.final()]);
    }
    async function get(url) {
      for (let a = 0; a < 4; a++) {
        try {
          const res = await fetch(url, { redirect: "error", credentials: "omit" });
          if (res.ok) return Buffer.from(await res.arrayBuffer());
          if (res.status === 404) return null;
        } catch (e) {}
        await sleep(300 * (a + 1));
      }
      return null;
    }

    (async () => {
      const mbuf = await get(link + "/manifest");
      if (!mbuf) { console.log("EXPIRED"); return; }
      let m;
      try { m = JSON.parse(decrypt(mbuf, "bbvk4|manifest").toString("utf8")); }
      catch (e) { console.log("BADKEY"); return; }
      const n = m && m.blobCount, C = m && m.chunkBytes, size = m && m.size;
      if (m.version !== 4 || m.format !== "tar.gz" || !Number.isInteger(n) || n < 1 || n > 199999 ||
          !Number.isInteger(C) || C < 1048576 || C > 94371840 ||
          !Number.isInteger(size) || size <= (n - 1) * C || size > n * C) {
        console.log("BADKEY"); return;
      }

      const fd = fs.openSync(outfile, "r+");
      const COLS = 24, TTY = process.stderr.isTTY;
      let done = 0, lastPct = -1, failed = false, next = 0;
      function bar() {
        if (!TTY) return;
        const pct = Math.floor(done * 100 / n);
        if (pct === lastPct && done < n) return;
        lastPct = pct;
        const f = Math.floor(pct * COLS / 100);
        process.stderr.write("\r\u001b[K" + (done >= n ? "\u001b[32m" : "\u001b[36m") + "[" + "\u2588".repeat(f) + "\u2591".repeat(COLS - f) + "] " +
          String(pct).padStart(3) + "%\u001b[0m  \uD83D\uDCE5 Downloading + \uD83D\uDD13 decrypting " + done + "/" + n);
        if (done >= n) process.stderr.write("\n");
      }
      async function worker() {
        while (!failed) {
          const i = next++;
          if (i >= n) return;
          try {
            const blob = await get(link + "/file/" + i);
            if (!blob) throw new Error("missing");
            const plain = decrypt(blob, "bbvk4|blob|" + i);
            const want = i < n - 1 ? C : size - (n - 1) * C;
            if (plain.length !== want) throw new Error("length");
            fs.writeSync(fd, plain, 0, plain.length, i * C);
            done++; bar();
          } catch (e) { failed = true; return; }
        }
      }
      bar();
      await Promise.all(Array.from({ length: Math.min(CONC, n) }, worker));
      fs.closeSync(fd);
      if (TTY && failed) process.stderr.write("\n");
      console.log(failed ? "FAILED" : "OK\t" + String(m.name || "files.tar.gz"));
    })();
  ' "$link" "$outfile" "$_BB_MAX_PAR"
}

# Unpack a downloaded tar.gz into <dest> SAFELY. The archive comes from a link, so it is untrusted:
#  * only regular files + directories are accepted (no symlinks/hardlinks/devices => no way to
#    write outside the target through a planted link)
#  * absolute names and ".." components are refused
#  * it extracts into a brand-new hidden folder, never over your files; top-level items are then
#    moved into <dest>, renamed "name (1)" if the name is already taken
#  * expanded size is checked against free disk space first (tar.gz "bombs")
# prints the number of files on stdout is NOT used; messages go to the terminal. Returns 0 on success.
_unpack_targz_safe() {
  local arc="$1" dest="$2"
  command -v tar &>/dev/null || { echo "❌ 'tar' not found — install it first."; return 1; }

  local ls_tmp; ls_tmp=$(mktemp "$dest/.bbvk_ls.XXXXXX") || { echo "❌ Could not write to $dest"; return 1; }
  if ! tar -tzvf "$arc" --numeric-owner > "$ls_tmp" 2>/dev/null; then
    echo "❌ The decrypted archive is not a valid tar.gz — refusing to unpack."
    rm -f "$ls_tmp"; return 1
  fi

  local nbad nnames stats nfiles expanded free
  nbad=$(LC_ALL=C awk '{ c = substr($0,1,1); if (c != "-" && c != "d") n++ } END { print n+0 }' "$ls_tmp")
  if [ "$nbad" -gt 0 ]; then
    echo "❌ Archive contains $nbad link/special entr(y/ies) — refusing to unpack (possible path-escape attack)."
    rm -f "$ls_tmp"; return 1
  fi
  nnames=$(tar -tzf "$arc" 2>/dev/null | LC_ALL=C awk '/^\// || /(^|\/)\.\.(\/|$)/ { n++ } END { print n+0 }')
  if [ "$nnames" -gt 0 ]; then
    echo "❌ Archive contains absolute or '..' paths — refusing to unpack."
    rm -f "$ls_tmp"; return 1
  fi
  stats=$(LC_ALL=C awk 'substr($0,1,1)=="-" { s += $3; n++ } END { printf "%d %d", n+0, s+0 }' "$ls_tmp")
  nfiles="${stats% *}"; expanded="${stats#* }"
  rm -f "$ls_tmp"

  free=$(df -Pk "$dest" 2>/dev/null | awk 'NR==2 { print $4 * 1024 }')
  if [[ "$free" =~ ^[0-9]+$ ]] && [ "$expanded" -gt "$free" ]; then
    echo "❌ Not enough free space: archive expands to $((expanded/1024/1024)) MB, only $((free/1024/1024)) MB free in $dest."
    return 1
  fi

  echo "📂 Unpacking $nfiles file(s), $((expanded/1024/1024)) MB..."
  local stage; stage=$(mktemp -d "$dest/.bbvk_x.XXXXXX") || return 1
  local errf; errf=$(mktemp)
  if ! tar -xzf "$arc" -C "$stage" --no-same-owner --no-same-permissions --no-overwrite-dir 2> "$errf"; then
    echo "❌ Unpacking failed:"; head -n 3 "$errf" | sed 's/^/   /'
    rm -rf "$stage" "$errf"; return 1
  fi
  rm -f "$errf"

  # Move top-level items into place without ever overwriting anything.
  local _shopts; _shopts=$(shopt -p nullglob dotglob)
  shopt -s nullglob dotglob
  local e bn cand stem ext i
  for e in "$stage"/*; do
    bn="${e##*/}"; cand="$bn"; i=0
    stem="$bn"; ext=""
    if [ -f "$e" ] && [[ "$bn" == ?*.* ]]; then stem="${bn%.*}"; ext=".${bn##*.}"; fi
    while [ -e "$dest/$cand" ] || [ -L "$dest/$cand" ]; do
      i=$((i + 1)); cand="${stem} (${i})${ext}"
    done
    mv -- "$e" "$dest/$cand"
  done
  eval "$_shopts"
  rmdir "$stage" 2>/dev/null
  echo "✅ Imported $nfiles file(s) into: $dest"
  return 0
}

# Phase 1: authorize + credit precheck, get an upload id back. Echoes the id.
_bb_upload_init() {
  local est_size="$1"
  _bb_get_credentials || return 1

  local attempt=0 confirmed=false
  while :; do
    attempt=$((attempt + 1))
    local cfg
    cfg=$({ _bb_auth_cfg
            _bb_cfg_header X-Estimated-Size "$est_size"
            $confirmed && _bb_cfg_header X-Confirm-Oversized yes
            true; })
    local response http_status body
    local response http_status body
    response=$(curl -s "${_BB_CURL_OPTS[@]}" -K - -w "\n%{http_code}" -H "Expect:" -X PUT "$WORKER_URL/upload/init" <<<"$cfg")
    http_status=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_status" == "200" ]; then
      local up_id up_token
      up_id=$(_bb_json_get "$body" id); up_token=$(_bb_json_get "$body" token)
      if [ -z "$up_id" ] || [ -z "$up_token" ]; then
        echo "❌ Server did not return an upload id/token" >&2
        return 1
      fi
      printf '%s\n%s\n' "$up_id" "$up_token"
      return 0
    fi

    local err_type msg
    err_type=$(_bb_json_get "$body" error)
    msg=$(_bb_json_get "$body" message)

    # 401 = the saved profile's credentials are wrong. Retrying would just reload
    # the same profile and fail identically, so report once and stop.
    if [ "$http_status" == "401" ]; then
      echo "❌ ${msg:-Authentication failed.}" >&2
      echo "🔁 Fix the active user with  -auth  inside 'o', then try again." >&2
      return 1
    fi

    if [ "$http_status" == "409" ] && [ "$err_type" == "oversized_confirmation_required" ] && ! $confirmed; then
      echo "⚠️  ${msg}" >&2
      read -p "   Proceed at 1.2x credit cost? (y/n): " ans
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then confirmed=true; continue; fi
      echo "🚫 Cancelled." >&2
      return 1
    fi

    echo "❌ $(_bb_fail_reason "$body" "$http_status")" >&2
    return 1
  done
}

# Phase 2: upload ALL encrypted blobs from a single Node process.
#
# This used to fork one `curl` per blob from bash. That was the reason upload
# lagged download so badly:
#   * one process spawn per blob (forking is expensive on Termux/Android)
#   * a fresh TCP + TLS handshake per blob — no connection reuse at all
#   * a `wait` barrier every _BB_MAX_PAR blobs, so each batch ran at the speed
#     of its slowest member (convoy effect) instead of refilling continuously
#   * `split` writing a second full copy of every large blob to disk
# Node keeps one process, reuses keep-alive connections across all workers,
# refills the pool the instant any slot frees, and streams byte ranges straight
# off the original file. Same pool design the download path uses.
_bb_upload_blobs() {
  local id="$1" tmpdir="$2" nblobs="$3" token="$4"
  BB_EMAIL="$FILEAPI_BASHBASICS_EMAIL" BB_UTOKEN="$token" node -e '
    const fs = require("fs");
    const path = require("path");
    const { Readable, Transform } = require("stream");

    const base   = process.argv[1];
    const id     = process.argv[2];
    const dir    = process.argv[3];
    const N      = parseInt(process.argv[4], 10);
    const CONC   = Math.max(1, parseInt(process.argv[5], 10) || 16);
    const email  = process.env.BB_EMAIL;
    const utoken = process.env.BB_UTOKEN;
    const CHUNK  = parseInt(process.argv[6], 10);
    const INLINE = 4 * 1024 * 1024;   // read small blobs into memory; stream bigger ones

    // Only the per-upload token travels with blobs; the API key is never re-sent.
    const auth = { "X-User-Email": email, "X-Upload-Token": utoken };
    const sleep = (ms) => new Promise(r => setTimeout(r, ms));

    // ---- progress is measured in BYTES, never in blobs ----------------------
    // sent  = request-body bytes handed to the network so far (counted as the
    //         file streams out, so it moves smoothly while a blob is in flight).
    // total = sum of every blob file size, known up front.
    // A failed attempt gives its bytes back (see send), so a retry never
    // double-counts. Small blobs are sent from memory: they are credited when
    // the server accepts them.
    let sent = 0, total = 0, done = 0, shown = 0;
    for (let i = 0; i < N; i++) {
      try { total += fs.statSync(path.join(dir, "blob" + i)).size; } catch (e) {}
    }

    function counted(rs, ctr) {
      const t = new Transform({
        transform(chunk, _enc, cb) { sent += chunk.length; ctr.n += chunk.length; cb(null, chunk); }
      });
      rs.on("error", (e) => t.destroy(e));
      return rs.pipe(t);
    }

    // Fresh body each attempt: a stream can only be consumed once, so retries
    // need a factory rather than a reusable body value.
    function bodyFor(fp, size, start, end, ctr) {
      if (start === undefined && size <= INLINE) return fs.readFileSync(fp);
      const opts = { highWaterMark: 64 * 1024 };
      if (start !== undefined) { opts.start = start; opts.end = end; }
      return Readable.toWeb(counted(fs.createReadStream(fp, opts), ctr));
    }

    // credit = body bytes this request carries (0 for control requests).
    async function send(url, method, makeBody, extraHeaders, credit) {
      let lastErr;
      for (let attempt = 0; attempt < 3; attempt++) {
        const ctr = { n: 0 };
        try {
          const body = makeBody(ctr);
          const init = {
            method,
            headers: Object.assign({}, auth, extraHeaders || {}),
            body,
            redirect: "error",
            duplex: "half"
          };
          const res = await fetch(url, init);
          if (res.ok) { sent += (credit || 0) - ctr.n; return res; }
          sent -= ctr.n;
          // 4xx other than 429 will not fix themselves: fail fast.
          if (res.status < 500 && res.status !== 429) {
            throw new Error("HTTP " + res.status);
          }
          lastErr = new Error("HTTP " + res.status);
        } catch (e) {
          if (e && /^HTTP 4/.test(e.message || "") ) throw e;
          sent -= ctr.n;
          lastErr = e;
        }
        await sleep(250 * Math.pow(2, attempt));
      }
      throw lastErr;
    }

    // ---- the bar --------------------------------------------------------------
    const TTY = process.stderr.isTTY;
    const t0 = Date.now();
    const samples = [];                         // [time, sent] over the last ~8 s
    function fmtB(b) {
      if (total >= 1048576) return (b / 1048576).toFixed(1);
      return (b / 1024).toFixed(0);
    }
    const unit = () => (total >= 1048576 ? "MB" : "KB");
    function fmtT(s) {
      s = Math.max(0, Math.round(s));
      if (s >= 3600) return Math.floor(s / 3600) + "h" + String(Math.floor(s % 3600 / 60)).padStart(2, "0") + "m";
      if (s >= 60) return Math.floor(s / 60) + "m" + String(s % 60).padStart(2, "0") + "s";
      return s + "s";
    }
    function speed() {
      const now = Date.now();
      samples.push([now, sent]);
      while (samples.length > 2 && now - samples[0][0] > 8000) samples.shift();
      const a = samples[0], b = samples[samples.length - 1];
      const dt = (b[0] - a[0]) / 1000;
      return dt > 0.4 ? Math.max(0, (b[1] - a[1]) / dt) : 0;
    }
    function draw(final) {
      if (!TTY) return;
      shown = Math.max(shown, Math.min(sent, total));            // never goes backwards
      const finished = final && done >= N;
      let pct = total > 0 ? Math.floor(shown * 100 / total) : 100;
      if (!finished && pct > 99) pct = 99;                       // 100% only once the server has everything
      const sp = speed();
      const cols = process.stderr.columns || 60;
      const left = fmtB(finished ? total : shown) + "/" + fmtB(total) + " " + unit();
      const parts = [String(pct).padStart(3) + "%", left];
      const extra = [];
      if (!finished) {
        extra.push(sp > 0 ? (fmtB(sp) + " " + unit() + "/s") : "...");
        if (sp > 0) extra.push("ETA " + fmtT((total - shown) / sp));
        extra.push(done + "/" + N);
      }
      // drop the least important pieces until the line fits the screen
      let barW = 22, info;
      for (;;) {
        info = parts.concat(extra).join("  ");
        if (cols - info.length - 4 >= 8 || extra.length === 0) break;
        extra.pop();
      }
      barW = Math.max(6, Math.min(22, cols - info.length - 4));
      const filled = Math.floor(pct * barW / 100);
      const b = "\u2588".repeat(filled) + "\u2591".repeat(barW - filled);
      const color = finished ? "\u001b[32m" : "\u001b[36m";
      process.stderr.write("\r\u001b[K" + color + "[" + b + "] " + info + "\u001b[0m");
      if (finished) {
        const secs = (Date.now() - t0) / 1000;
        process.stderr.write("\n  \u2705 " + fmtB(total) + " " + unit() + " in " + fmtT(secs) +
          (secs > 0 ? "  (avg " + fmtB(total / secs) + " " + unit() + "/s)" : "") + "\n");
      }
    }

    async function uploadOne(idx) {
      const fp = path.join(dir, "blob" + idx);
      const size = fs.statSync(fp).size;

      if (size <= CHUNK) {
        await send(base + "/upload/" + id + "/blob/" + idx, "PUT",
                   (ctr) => bodyFor(fp, size, undefined, undefined, ctr), undefined, size);
        return;
      }

      // Large blob -> R2 multipart. Ranges are streamed straight off the
      // original file, so nothing extra is written to disk.
      const cRes = await send(base + "/upload/" + id + "/blob/" + idx + "/mpu", "POST", () => undefined);
      const uploadId = (await cRes.json()).uploadId;
      if (!uploadId) throw new Error("no uploadId");

      const ranges = [];
      for (let off = 0, pn = 1; off < size; off += CHUNK, pn++) {
        ranges.push({ pn, start: off, end: Math.min(off + CHUNK, size) - 1 });
      }

      const parts = new Array(ranges.length);
      let nextPart = 0;
      async function partWorker() {
        while (true) {
          const i = nextPart++;
          if (i >= ranges.length) return;
          const r = ranges[i];
          const res = await send(
            base + "/upload/" + id + "/blob/" + idx + "/mpu/" + uploadId + "/" + r.pn,
            "PUT", (ctr) => bodyFor(fp, size, r.start, r.end, ctr), undefined, r.end - r.start + 1);
          const j = await res.json();
          parts[i] = { partNumber: j.partNumber, etag: j.etag };
        }
      }
      await Promise.all(Array.from({ length: Math.min(CONC, ranges.length) }, partWorker));

      await send(base + "/upload/" + id + "/blob/" + idx + "/mpu/" + uploadId + "/complete",
                 "POST", () => JSON.stringify(parts), { "Content-Type": "application/json" });
    }

    (async () => {
      let next = 0, failed = 0;
      const errors = [];
      async function worker() {
        while (true) {
          const i = next++;
          if (i >= N) return;
          try {
            await uploadOne(i);
          } catch (e) {
            failed++;
            if (errors.length < 3) errors.push("blob " + i + ": " + (e && e.message ? e.message : e));
          }
          done++;
        }
      }
      const timer = setInterval(() => draw(false), 200);
      draw(false);
      await Promise.all(Array.from({ length: Math.min(CONC, N || 1) }, worker));
      clearInterval(timer);
      if (failed === 0) draw(true);
      else if (TTY) process.stderr.write("\n");
      for (const m of errors) process.stderr.write("  \u26a0\uFE0F  " + m + "\n");
      console.log(failed === 0 ? "OK" : "FAIL");
    })();
  
  ' "$WORKER_URL" "$id" "$tmpdir" "$nblobs" "$_BB_MAX_PAR" "$_BB_CHUNK_BYTES"
}

# Phase 3: upload the manifest, settle credits, return the link + credit headers.
_bb_upload_commit() {
  local id="$1" fcount="$2" mpath="$3" token="$4"
  local cfg
  cfg=$({ _bb_cfg_header X-User-Email "$FILEAPI_BASHBASICS_EMAIL"
          _bb_cfg_header X-Upload-Token "$token"
          _bb_cfg_header X-File-Count "$fcount"; })

  local hdrfile response http_status body
  hdrfile=$(mktemp)
  response=$(curl -s "${_BB_CURL_OPTS[@]}" -K - -D "$hdrfile" -w "\n%{http_code}" -H "Expect:" -X PUT \
    --data-binary "@$mpath" "$WORKER_URL/upload/$id/commit" <<<"$cfg")
  http_status=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_status" == "201" ]; then
    local deducted balance
    deducted=$(grep -i '^X-Credits-Deducted:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
    balance=$(grep -i '^X-Credits-Balance:' "$hdrfile" | tr -d '\r' | cut -d' ' -f2-)
    rm -f "$hdrfile"
    printf '%s\n%s\n%s\n' "$body" "$deducted" "$balance"
    return 0
  fi
  rm -f "$hdrfile"
  echo "❌ $(_bb_fail_reason "$body" "$http_status")" >&2
  return 1
}

_up_do_multipart_upload() {
  local -a paths=("$@")
  _crypto_check || return 1
  if ! command -v tar &>/dev/null || ! command -v gzip &>/dev/null; then
    echo "❌ 'tar' and 'gzip' are required for up- (pkg install tar gzip)."
    return 1
  fi
  local -a gz=(gzip)
  command -v pigz &>/dev/null && gz=(pigz)          # parallel gzip when available
  local lvl="${FILEAPI_BASHBASICS_GZIP_LEVEL:-6}"
  [[ "$lvl" =~ ^[1-9]$ ]] || lvl=6

  echo "🔎 Scanning selection..."
  # Stage the selection by name as symlinks so the archive holds "<name>/..." entries relative
  # to nothing absolute (same layout the old per-file upload produced).
  local stage tmpdir rcfile errfile
  stage=$(mktemp -d) && tmpdir=$(mktemp -d) && rcfile=$(mktemp) && errfile=$(mktemp) \
    || { echo "❌ Could not create temp files."; return 1; }
  _up_cleanup() { rm -rf "$stage" "$tmpdir" "$rcfile" "$errfile"; }

  local -a rel_items=()
  local p bn cand n
  for p in "${paths[@]}"; do
    p="${p%/}"; [[ "$p" == /* ]] || p="$PWD/$p"
    if [ ! -f "$p" ] && [ ! -d "$p" ]; then echo "  ⚠️  Skipping missing item: $p" >&2; continue; fi
    bn="${p##*/}"; cand="$bn"; n=1
    while [ -e "$stage/$cand" ] || [ -L "$stage/$cand" ]; do n=$((n + 1)); cand="${bn}_$n"; done
    ln -s "$p" "$stage/$cand"
    rel_items+=("./$cand")                            # "./" so a name starting with "-" is never an option
  done
  if [ ${#rel_items[@]} -eq 0 ]; then
    echo "❌ No valid files found in selection"; _up_cleanup; return 1
  fi

  # hidden files inside the chosen folders: Settings → Upload hidden (up-)
  _hidden_decide "${upload_hidden_mode:-follow}" "the upload" "${paths[@]}" || { _up_cleanup; return 1; }
  local hid_inc="$_hid_inc"

  local arcname="files.tar.gz"
  [ ${#rel_items[@]} -eq 1 ] && arcname="${rel_items[0]#./}.tar.gz"
  arcname=$(printf '%s' "$arcname" | LC_ALL=C tr -c 'A-Za-z0-9._ -' '_' | cut -c1-120)

  echo "📦 Packing tar.gz → 🔐 encrypting (streamed: the unencrypted archive never touches the disk)"
  # find lists regular files + folders only (symlinks inside the tree are skipped, as before);
  # tar -h resolves the staging symlinks at the top level.  tar's exit status goes to $rcfile.
  local packout
  packout=$(
    cd "$stage" || exit 1
    _hid_find0 "$hid_inc" 1 "${rel_items[@]}" 2>> "$errfile" \
      | { tar --null --no-recursion -h -T - -cf - 2>> "$errfile"; echo $? > "$rcfile"; } \
      | "${gz[@]}" "-$lvl" -c \
      | _crypto_stream_pack "$tmpdir" "$arcname"
  )

  local key total_size nblobs tar_rc
  key=$(printf '%s' "$packout" | sed -n '1p')
  total_size=$(printf '%s' "$packout" | sed -n '2p')
  nblobs=$(printf '%s' "$packout" | sed -n '3p')
  tar_rc=$(cat "$rcfile" 2>/dev/null)

  if [[ ! "$key" =~ ^[A-Za-z0-9_-]{43}$ ]] || [[ ! "$total_size" =~ ^[0-9]+$ ]] || [[ ! "$nblobs" =~ ^[0-9]+$ ]]; then
    echo "❌ Packing/encryption failed"
    [ -s "$errfile" ] && head -n 3 "$errfile" | sed 's/^/   /'
    _up_cleanup; return 1
  fi
  if [ -z "$tar_rc" ] || [ "$tar_rc" -ge 2 ]; then
    echo "❌ tar failed (exit ${tar_rc:-?}) — upload aborted."
    [ -s "$errfile" ] && head -n 3 "$errfile" | sed 's/^/   /'
    _up_cleanup; return 1
  fi
  if [ "$tar_rc" -eq 1 ]; then
    echo "⚠️  Some files changed or were unreadable while packing (they may be missing/partial):"
    head -n 3 "$errfile" | sed 's/^/   /'
  fi
  echo "   $((total_size/1024/1024)) MB after tar.gz + encryption, in $nblobs blob(s)."

  if [ "$total_size" -gt "$_SP_HARD_LIMIT_BYTES" ]; then
    echo "❌ Packed size is $((total_size/1024/1024/1024))GB — exceeds the absolute upload ceiling"
    _up_cleanup; return 1
  fi
  if [ "$total_size" -gt "$_SP_SOFT_UPLOAD_BYTES" ]; then
    echo "ℹ️  Packed size is over the 10GB soft limit — the server will ask you to confirm at 1.2x credit cost."
  fi

  # ---- Phase 1: init (auth + credit precheck) ----
  local init_out id token
  init_out=$(_bb_upload_init "$total_size") || { _up_cleanup; return 1; }
  id=$(printf '%s' "$init_out" | sed -n '1p'); token=$(printf '%s' "$init_out" | sed -n '2p')
  if [ -z "$id" ] || [ -z "$token" ]; then
    echo "❌ Upload init failed (no id returned)"; _up_cleanup; return 1
  fi

  # ---- Phase 2: parallel streaming blob uploads (single Node process) ----
  [ -t 2 ] || echo "☁️  Uploading $nblobs encrypted blob(s) — up to $_BB_MAX_PAR in parallel..."
  local upres
  upres=$(_bb_upload_blobs "$id" "$tmpdir" "$nblobs" "$token")
  if [ "$upres" != "OK" ]; then
    _up_cleanup
    echo "❌ One or more parts failed to upload. Nothing was finalized; partial objects auto-expire in 30 min."
    return 1
  fi

  # ---- Phase 3: commit (manifest + credit settlement) ----
  local result final_url deducted balance
  result=$(_bb_upload_commit "$id" "$nblobs" "$tmpdir/manifest.enc" "$token") \
    || { _up_cleanup; return 1; }
  _up_cleanup

  final_url=$(echo "$result" | sed -n '1p')
  deducted=$(echo "$result" | sed -n '2p')
  balance=$(echo "$result" | sed -n '3p')

  _announce_link "${final_url}#k=${key}"
  [ -n "$deducted" ] && echo "💳 Credits deducted: $deducted   |   Balance: $balance"
}

handle_up_upload() {
  local raw="$1"
  local itemlist="${raw#up-}"
  _sp_guard_and_resolve "$itemlist" "up-" || return
  _up_do_multipart_upload "${sp_resolved[@]}"
}

handle_c2c_upload() {
  local raw="$1"
  local itemlist="${raw#c2c-}"
  _sp_guard_and_resolve "$itemlist" "c2c-" || return
  _c2c_paths "${sp_resolved[@]}"
}

# Merge the given files into ONE encrypted text blob and upload it.
# Shared by c2c- (numbered items) and the fx *.upload.text.* functions
# (CSV / .s selection), so every entry point behaves identically.
_c2c_paths() {
  local -a paths=("$@")
  local p
  for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
      echo "❌ c2c- doesn't support folders. Try up- instead."
      return 1
    fi
  done

  _crypto_check || return 1

  local nvalid=0
  for p in "${paths[@]}"; do
    if [ -f "$p" ]; then nvalid=$((nvalid + 1)); else echo "  ⚠️  Skipping missing item: $p"; fi
  done
  if [ "$nvalid" -eq 0 ]; then
    echo "❌ No valid files found in selection"
    return 1
  fi

  echo "🔐 Encrypting merged text locally (key never leaves this machine)..."
  local key
  key=$(_crypto_new_key)
  if [[ ! "$key" =~ ^[A-Za-z0-9_-]{43}$ ]]; then
    echo "❌ Local encryption failed"
    return 1
  fi

  # Merge -> encrypt in one pipe: the plaintext never touches the disk.
  local enc_tmp; enc_tmp=$(mktemp)
  {
    for p in "${paths[@]}"; do
      [ -f "$p" ] || continue
      echo "===== ${p##*/} ====="
      cat -- "$p"
      echo
    done
  } | _crypto_encrypt_stdin "$key" "bbvk2|copy" > "$enc_tmp"
  if [ ! -s "$enc_tmp" ]; then
    echo "❌ Local encryption failed"
    rm -f "$enc_tmp"
    return 1
  fi

  echo "☁️  Uploading ${#paths[@]} encrypted file(s) merged into a single blob..."
  local result final_url deducted balance
  if ! result=$(_bb_authed_put "/copy" "" --data-binary "@$enc_tmp"); then
    rm -f "$enc_tmp"
    return 1
  fi
  rm -f "$enc_tmp"

  final_url=$(echo "$result" | sed -n '1p')
  deducted=$(echo "$result" | sed -n '2p')
  balance=$(echo "$result" | sed -n '3p')

  _announce_link "${final_url}#k=${key}"
  [ -n "$deducted" ] && echo "💳 Credits deducted: $deducted   |   Balance: $balance"
}

handle_do_import() {
  _crypto_check || return 1

  read -r -p "🔗 Paste link to import (include the #k=... part): " link
  [ -z "$link" ] && echo "🚫 Cancelled" && return

  if [[ "$link" != *://* ]]; then
    link="$WORKER_URL/$link"
  fi

  local key=""
  if [[ "$link" == *"#k="* ]]; then
    key="${link#*#k=}"
    link="${link%%#*}"
  fi
  link="${link%/}"

  if [ -z "$key" ]; then
    read -r -s -p "🔑 No key found in the pasted link — paste the decryption key separately: " key
    echo
    if [ -z "$key" ]; then
      echo "❌ No decryption key — cannot proceed."
      return 1
    fi
  fi

  if [[ ! "$key" =~ ^[A-Za-z0-9_-]{43}$ ]]; then
    echo "❌ That doesn't look like a valid decryption key."
    return 1
  fi
  # HTTPS only + strict shape: also prevents option/argument injection into curl/node.
  if [[ ! "$link" =~ ^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/[A-Za-z0-9_-]{16,255}$ ]]; then
    echo "❌ Only well-formed https:// links are accepted."
    return 1
  fi
  local lhost="${link#https://}"; lhost="${lhost%%/*}"
  local whost="${WORKER_URL#https://}"
  if [ "$lhost" != "$whost" ]; then
    echo "⚠️  This link points to '$lhost', not your configured server ($whost)."
    local ans; read -r -p "   Continue anyway? (y/n): " ans
    [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "🚫 Cancelled."; return 1; }
  fi

  local tmp_body raw_status
  tmp_body=$(mktemp)
  raw_status=$(curl -s "${_BB_CURL_OPTS[@]}" --max-filesize 2097152 -o "$tmp_body" -w "%{http_code}" "$link/raw")

  if [ "$raw_status" == "200" ]; then
    echo "📄 Text link detected. Decrypting locally..."
    local plain_tmp; plain_tmp=$(mktemp)
    if ! _crypto_decrypt_stdin "$key" "bbvk2|copy" < "$tmp_body" > "$plain_tmp" 2>/dev/null; then
      echo "❌ Decryption failed — wrong key, or the link was already used/corrupted."
      rm -f "$tmp_body" "$plain_tmp"
      return 1
    fi
    rm -f "$tmp_body"

    if [ -t 1 ] && [ -t 0 ]; then
      read -r -p "💾 Save as filename in $path (blank = print to terminal): " fname
    else
      fname=""
    fi

    if [ -n "$fname" ]; then
      if [[ "$fname" == */* || "$fname" == "." || "$fname" == ".." ]]; then
        echo "❌ Invalid file name."; rm -f "$plain_tmp"; return 1
      fi
      if [ -e "$path/$fname" ]; then
        echo "❌ $path/$fname already exists — refusing to overwrite."; rm -f "$plain_tmp"; return 1
      fi
      mv -n -- "$plain_tmp" "$path/$fname"
      echo "✅ Imported as: $path/$fname"
    else
      # Received text is untrusted: strip control characters / escape sequences before it
      # reaches the terminal (they can retitle the window, rewrite the screen or set the clipboard).
      LC_ALL=C tr -d '\000-\010\013-\037\177' < "$plain_tmp"
      if [ "$(LC_ALL=C tr -d '\000-\010\013-\037\177' < "$plain_tmp" | wc -c)" != "$(wc -c < "$plain_tmp")" ]; then
        echo; echo "ℹ️  Control characters were removed for display. Save to a file to keep the raw text."
      fi
      rm -f "$plain_tmp"
    fi
    return 0
  fi

  rm -f "$tmp_body"

  local manifest_status
  manifest_status=$(curl -s "${_BB_CURL_OPTS[@]}" -o /dev/null -w "%{http_code}" "$link/manifest")
  if [ "$manifest_status" != "200" ]; then
    echo "❌ Link expired, invalid, or already nuked."
    return 1
  fi

  echo "📦 Archive link detected."
  mkdir -p "$path"
  local arc; arc=$(mktemp "$path/.bbvk_dl.XXXXXX") || { echo "❌ Cannot write to $path"; return 1; }

  local res; res=$(_crypto_fetch_archive "$link" "$key" "$arc")
  case "${res%%$'\t'*}" in
    OK) ;;
    EXPIRED) echo "❌ Link expired, invalid, or already nuked."; rm -f "$arc"; return 1 ;;
    BADKEY)  echo "❌ Decryption failed — wrong key, tampered data, or a link made by an older client version (those expire after 30 minutes)."; rm -f "$arc"; return 1 ;;
    *)       echo "❌ Download failed — some chunks could not be fetched or failed their integrity check. Nothing was unpacked."; rm -f "$arc"; return 1 ;;
  esac

  _unpack_targz_safe "$arc" "$path"
  local rc=$?
  rm -f "$arc"
  [ $rc -eq 0 ] && echo "ℹ️  The remote copy is left in place and will auto-delete on its own after 30 minutes."
  return $rc
}
