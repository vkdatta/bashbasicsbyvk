WORKER_URL="https://fileapi.bashbasics.workers.dev"

_SP_SOFT_UPLOAD_BYTES=$((10*1024*1024*1024))
_SP_HARD_LIMIT_BYTES=$((32*1024*1024*1024))

# Streaming-upload tuning. CHUNK_BYTES must match the worker's CHUNK_BYTES (90 MiB):
# any blob at or below this goes up in one PUT, anything larger uses R2 multipart.
# _BB_MAX_PAR is how many blobs/parts upload concurrently.
_BB_CHUNK_BYTES=$((90*1024*1024))
_BB_MAX_PAR="${FILEAPI_BASHBASICS_PARALLEL:-16}"

_bb_get_credentials() {
  local email="${FILEAPI_BASHBASICS_EMAIL:-}"
  local apikey="${FILEAPI_BASHBASICS_KEY:-}"

  if [ -z "$email" ] || [ -z "$apikey" ]; then
    if [ ! -t 0 ]; then
      echo "❌ Error: fileapi.bashbasics.email / fileapi.bashbasics.key are not set, and no terminal is available to prompt for them."
      echo "   Set them with: export FILEAPI_BASHBASICS_EMAIL=you@example.com; export FILEAPI_BASHBASICS_KEY=your_api_key"
      return 1
    fi
    echo "🔑 No saved credentials found (FILEAPI_BASHBASICS_EMAIL / FILEAPI_BASHBASICS_KEY)."
    [ -z "$email" ] && read -p "   Enter email: " email
    if [ -z "$apikey" ]; then
      read -s -p "   Enter API key: " apikey
      echo
    fi
    if [ -z "$email" ] || [ -z "$apikey" ]; then
      echo "❌ Email and API key are both required."
      return 1
    fi
    export FILEAPI_BASHBASICS_EMAIL="$email"
    export FILEAPI_BASHBASICS_KEY="$apikey"
    echo "ℹ️  Using these for the rest of this session. Export them yourself beforehand to skip this prompt next time."
  fi
  return 0
}

# ---- transport hardening ---------------------------------------------------
# HTTPS only, TLS>=1.2, never follow redirects (a redirect could carry headers elsewhere).
_BB_CURL_OPTS=(--proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 0)

# Secrets must never appear in argv (visible to every local user via `ps`).
# They are fed to curl as a config file on stdin:  curl -K - ... <<< "$cfg"
_bb_cfg_escape() {
  local v="$1"
  v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/}; v=${v//$'\r'/}
  printf '%s' "$v"
}
_bb_cfg_header() { printf 'header = "%s: %s"\n' "$1" "$(_bb_cfg_escape "$2")"; }
_bb_auth_cfg() {
  _bb_cfg_header X-User-Email "$FILEAPI_BASHBASICS_EMAIL"
  _bb_cfg_header X-User-Key   "$FILEAPI_BASHBASICS_KEY"
}

# Crypto format v2: AES-256-GCM, blob = [12B IV][ciphertext][16B tag], with Additional
# Authenticated Data binding each ciphertext to its role/position:
#   "bbvk2|copy"  "bbvk2|manifest"  "bbvk2|blob|<index>"
# so a hostile server cannot swap, replay or substitute pieces undetected.

_bb_json_get() {
  local json="$1" field="$2"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      try {
        const o = JSON.parse(d);
        process.stdout.write(o[process.argv[1]] !== undefined ? String(o[process.argv[1]]) : "");
      } catch (e) {}
    });
  ' "$field" <<< "$json"
}

_bb_fail_reason() {
  local body="$1" http_status="$2"
  local reason
  reason=$(_bb_json_get "$body" message)
  if [ -n "$reason" ]; then
    printf '%s' "$reason"
    return
  fi
  local trimmed
  trimmed=$(printf '%s' "$body" | tr '\n\r' '  ' | sed 's/  */ /g; s/^ *//; s/ *$//')
  if [ -n "$trimmed" ]; then
    printf 'HTTP %s: %s' "$http_status" "${trimmed:0:300}"
  else
    printf 'Request failed (HTTP %s)' "$http_status"
  fi
}

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

    if [ "$http_status" == "401" ] && [ "$attempt" -le 2 ]; then
      echo "❌ ${msg:-Authentication failed.}" >&2
      unset FILEAPI_BASHBASICS_EMAIL FILEAPI_BASHBASICS_KEY
      echo "🔁 Please re-enter your credentials." >&2
      _bb_get_credentials || return 1
      continue
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

_crypto_check() {
  if ! command -v node &>/dev/null; then
    echo "❌ 'node' is required for encryption (up-/ups-/do-) but wasn't found in PATH."
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

_crypto_pack_upload() {
  local outdir="$1" listfile="$2"
  node -e '
    const fs = require("fs"), path = require("path"), crypto = require("crypto");
    const outdir = process.argv[1];
    const listfile = process.argv[2];
    const lines = fs.readFileSync(listfile, "utf8").split("\n").filter(Boolean);

    const key = crypto.randomBytes(32);
    const keyB64url = key.toString("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");

    function encrypt(buf, aad) {
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
      cipher.setAAD(Buffer.from(aad, "utf8"));
      const ct = Buffer.concat([cipher.update(buf), cipher.final()]);
      const tag = cipher.getAuthTag();
      return Buffer.concat([iv, ct, tag]);
    }

    const COLS = 24, TTY = process.stderr.isTTY;
    let lastPct = -1;
    function bar(done, total, label) {
      if (!TTY) return;
      const pct = total > 0 ? Math.floor(done * 100 / total) : 100;
      if (pct === lastPct && done < total) return;   // only redraw when % changes
      lastPct = pct;
      const filled = Math.floor(pct * COLS / 100);
      const b = "\u2588".repeat(filled) + "\u2591".repeat(COLS - filled);
      const color = done >= total ? "\u001b[32m" : "\u001b[36m";
      process.stderr.write("\r\u001b[K" + color + "[" + b + "] " +
        String(pct).padStart(3) + "%\u001b[0m  " + label + " " + done + "/" + total);
      if (done >= total) process.stderr.write("\n");
    }

    const entries = [];
    let totalBytes = 0;
    const totalFiles = lines.length;
    lines.forEach((line, idx) => {
      const tabIdx = line.indexOf("\t");
      const relpath = line.slice(0, tabIdx);
      const abspath = line.slice(tabIdx + 1);
      if (fs.statSync(abspath).size > 2000000000) {
        console.error("\n  \u274c " + relpath + " is larger than 2 GB; single-blob encryption holds a file in memory and cannot handle it.");
        process.exit(2);
      }
      const data = fs.readFileSync(abspath);
      const enc = encrypt(data, "bbvk2|blob|" + idx);
      totalBytes += enc.length;   // billed/validated size = real ciphertext bytes stored
      fs.writeFileSync(path.join(outdir, "blob" + idx), enc, { mode: 0o600 });
      entries.push({ path: relpath, size: data.length, blobIndex: idx });
      bar(idx + 1, totalFiles, "\uD83D\uDD10 Encrypting");
    });

    let idCounter = 0;
    const nextId = () => "n" + (idCounter++);
    const root = [];
    const folderCache = new Map();
    for (const entry of entries) {
      const parts = entry.path.split("/").filter(Boolean);
      let children = root, acc = "";
      for (let i = 0; i < parts.length - 1; i++) {
        acc += (acc ? "/" : "") + parts[i];
        let folder = folderCache.get(acc);
        if (!folder) {
          folder = { id: nextId(), name: parts[i], type: "folder", children: [] };
          children.push(folder);
          folderCache.set(acc, folder);
        }
        children = folder.children;
      }
      const name = parts[parts.length - 1] || entry.path;
      children.push({ id: nextId(), name, type: "file", size: entry.size, blobIndex: entry.blobIndex });
    }

    const manifest = { version: 2, fileCount: entries.length, tree: root };
    fs.writeFileSync(path.join(outdir, "manifest.enc"), encrypt(Buffer.from(JSON.stringify(manifest), "utf8"), "bbvk2|manifest"), { mode: 0o600 });

    process.stdout.write(keyB64url + "\n" + totalBytes);
  ' "$outdir" "$listfile"
}

_crypto_import_upload() {
  local link="$1" key="$2" dest="$3"
  BB_KEY="$key" node -e '
    const fs = require("fs"), path = require("path"), crypto = require("crypto");
    const link = process.argv[1];
    const key = Buffer.from(process.env.BB_KEY.replace(/-/g,"+").replace(/_/g,"/"), "base64");
    const dest = path.resolve(process.argv[2]);
    const CONC = Math.max(1, parseInt(process.argv[3], 10) || 16);
    const MAX_FILES = 200000;

    function decrypt(buf, aad) {
      if (buf.length < 28) throw new Error("short");
      const iv = buf.subarray(0, 12);
      const tag = buf.subarray(buf.length - 16);
      const ct = buf.subarray(12, buf.length - 16);
      const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
      decipher.setAuthTag(tag);
      decipher.setAAD(Buffer.from(aad, "utf8"));
      return Buffer.concat([decipher.update(ct), decipher.final()]);
    }

    // A malicious sender controls every filename. Never let one escape `dest`.
    function safeParts(rel) {
      if (typeof rel !== "string" || rel.length === 0 || rel.length > 4096) return null;
      if (rel.indexOf("\0") !== -1 || rel.indexOf("\\") !== -1 || rel[0] === "/") return null;
      const parts = rel.split("/");
      for (const p of parts) { if (p === "" || p === "." || p === ".." || p.length > 255) return null; }
      return parts;
    }
    // Create directories one level at a time and refuse to traverse symlinks.
    function safeMkdirs(parts) {
      let cur = dest;
      for (const p of parts) {
        cur = path.join(cur, p);
        let st;
        try { st = fs.lstatSync(cur); } catch (e) { fs.mkdirSync(cur); continue; }
        if (st.isSymbolicLink() || !st.isDirectory()) throw new Error("unsafe path component");
      }
      return cur;
    }
    // Never overwrite an existing file; "wx" also refuses to follow a planted symlink.
    function writeNoClobber(dir, name, data) {
      const ext = path.extname(name), stem = name.slice(0, name.length - ext.length);
      for (let n = 0; n < 100; n++) {
        const cand = path.join(dir, n === 0 ? name : stem + " (" + n + ")" + ext);
        try { fs.writeFileSync(cand, data, { flag: "wx", mode: 0o644 }); return cand; }
        catch (e) { if (e.code !== "EEXIST") throw e; }
      }
      throw new Error("too many name collisions");
    }

    (async () => {
      fs.mkdirSync(dest, { recursive: true });
      const manifestRes = await fetch(link + "/manifest", { redirect: "error", credentials: "omit" });
      if (!manifestRes.ok) { console.error("Manifest fetch failed (HTTP " + manifestRes.status + ")"); console.log(0); return; }
      let manifest;
      try {
        manifest = JSON.parse(decrypt(Buffer.from(await manifestRes.arrayBuffer()), "bbvk2|manifest").toString("utf8"));
      } catch (e) {
        console.error("Decryption failed \u2014 wrong key, corrupted link, or the data was tampered with.");
        console.log(0);
        return;
      }
      if (!manifest || manifest.version !== 2 || !Array.isArray(manifest.tree)) {
        console.error("Unsupported or modified manifest (expected format v2).");
        console.log(0);
        return;
      }

      const files = [];
      const seen = new Set();
      let bad = 0;
      (function walk(nodes, prefix, depth) {
        if (depth > 64) { bad++; return; }
        for (const n of nodes) {
          if (!n || typeof n.name !== "string") { bad++; continue; }
          if (n.type === "file") {
            const bi = n.blobIndex;
            if (!Number.isInteger(bi) || bi < 0 || bi >= MAX_FILES || seen.has(bi)) { bad++; continue; }
            seen.add(bi);
            files.push({ relpath: prefix + n.name, blobIndex: bi });
          } else if (n.type === "folder" && Array.isArray(n.children)) {
            walk(n.children, prefix + n.name + "/", depth + 1);
          }
          if (files.length > MAX_FILES) return;
        }
      })(manifest.tree, "", 0);

      const COLS = 24, TTY = process.stderr.isTTY, TOTAL = files.length;
      let lastPct = -1;
      function bar(done) {
        if (!TTY) return;
        const pct = TOTAL > 0 ? Math.floor(done * 100 / TOTAL) : 100;
        if (pct === lastPct && done < TOTAL) return;
        lastPct = pct;
        const filled = Math.floor(pct * COLS / 100);
        const b = "\u2588".repeat(filled) + "\u2591".repeat(COLS - filled);
        const color = done >= TOTAL ? "\u001b[32m" : "\u001b[36m";
        process.stderr.write("\r\u001b[K" + color + "[" + b + "] " +
          String(pct).padStart(3) + "%\u001b[0m  \uD83D\uDCE5 Downloading " + done + "/" + TOTAL);
        if (done >= TOTAL) process.stderr.write("\n");
      }

      let ok = 0, done = 0, failed = bad, next = 0;
      async function worker() {
        while (true) {
          const i = next++;
          if (i >= files.length) return;
          const f = files[i];
          try {
            const parts = safeParts(f.relpath);
            if (!parts) { failed++; done++; bar(done); continue; }
            const fileRes = await fetch(link + "/file/" + f.blobIndex, { redirect: "error", credentials: "omit" });
            if (!fileRes.ok) { failed++; done++; bar(done); continue; }
            const plain = decrypt(Buffer.from(await fileRes.arrayBuffer()), "bbvk2|blob|" + f.blobIndex);
            const dir = safeMkdirs(parts.slice(0, -1));
            writeNoClobber(dir, parts[parts.length - 1], plain);
            ok++; done++; bar(done);
          } catch (e) {
            failed++; done++; bar(done);
          }
        }
      }
      await Promise.all(Array.from({ length: Math.min(CONC, files.length || 1) }, worker));

      if (TTY && TOTAL === 0) process.stderr.write("\n");
      if (failed > 0) process.stderr.write("  \u26a0\ufe0f  " + failed + " file(s) failed (download error, failed integrity check, or unsafe path rejected).\n");
      console.log(ok);
    })();
  ' "$link" "$dest" "$_BB_MAX_PAR"
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

    if [ "$http_status" == "401" ] && [ "$attempt" -le 2 ]; then
      echo "❌ ${msg:-Authentication failed.}" >&2
      unset FILEAPI_BASHBASICS_EMAIL FILEAPI_BASHBASICS_KEY
      echo "🔁 Please re-enter your credentials." >&2
      _bb_get_credentials || return 1
      continue
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
    const { Readable } = require("stream");

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

    // Fresh body each attempt: a stream can only be consumed once, so retries
    // need a factory rather than a reusable body value.
    function bodyFor(fp, size, start, end) {
      if (start === undefined && size <= INLINE) return fs.readFileSync(fp);
      const opts = (start === undefined) ? {} : { start, end };
      return Readable.toWeb(fs.createReadStream(fp, opts));
    }

    async function send(url, method, makeBody, extraHeaders) {
      let lastErr;
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const body = makeBody();
          const init = {
            method,
            headers: Object.assign({}, auth, extraHeaders || {}),
            body,
            redirect: "error",
            duplex: "half"
          };
          const res = await fetch(url, init);
          if (res.ok) return res;
          // 4xx other than 429 will not fix themselves — fail fast.
          if (res.status < 500 && res.status !== 429) {
            throw new Error("HTTP " + res.status);
          }
          lastErr = new Error("HTTP " + res.status);
        } catch (e) {
          lastErr = e;
        }
        await sleep(250 * Math.pow(2, attempt));
      }
      throw lastErr;
    }

    const COLS = 24, TTY = process.stderr.isTTY;
    let lastPct = -1, done = 0;
    function bar() {
      if (!TTY) return;
      const pct = N > 0 ? Math.floor(done * 100 / N) : 100;
      if (pct === lastPct && done < N) return;
      lastPct = pct;
      const filled = Math.floor(pct * COLS / 100);
      const b = "\u2588".repeat(filled) + "\u2591".repeat(COLS - filled);
      const color = done >= N ? "\u001b[32m" : "\u001b[36m";
      process.stderr.write("\r\u001b[K" + color + "[" + b + "] " +
        String(pct).padStart(3) + "%\u001b[0m  \u2601\uFE0F  Uploading " + done + "/" + N);
      if (done >= N) process.stderr.write("\n");
    }

    async function uploadOne(idx) {
      const fp = path.join(dir, "blob" + idx);
      const size = fs.statSync(fp).size;

      if (size <= CHUNK) {
        await send(base + "/upload/" + id + "/blob/" + idx, "PUT",
                   () => bodyFor(fp, size));
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
            "PUT", () => bodyFor(fp, size, r.start, r.end));
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
          done++; bar();
        }
      }
      bar();
      await Promise.all(Array.from({ length: Math.min(CONC, N || 1) }, worker));
      if (TTY && N === 0) process.stderr.write("\n");
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

  echo "🔎 Scanning selection..."
  local listfile; listfile=$(mktemp)
  local p base file
  # Build the file list WITHOUT forking a `stat` per file. For a 50k-file tree
  # that per-file subprocess was why nothing printed for minutes. The whole
  # loop redirects to the list once (one open, not one per line), and the exact
  # byte total is computed by the encryption pass instead.
  {
    for p in "${paths[@]}"; do
      if [ -d "$p" ]; then
        base=$(basename -- "$p")
        while IFS= read -r -d '' file; do
          printf '%s\t%s\n' "${base}/${file#$p/}" "$file"
        done < <(find "$p" -type f -print0)
      elif [ -f "$p" ]; then
        printf '%s\t%s\n' "$(basename -- "$p")" "$p"
      else
        echo "  ⚠️  Skipping missing item: $p" >&2
      fi
    done
  } >> "$listfile"

  if [ ! -s "$listfile" ]; then
    echo "❌ No valid files found in selection"
    rm -f "$listfile"
    return 1
  fi

  local file_count; file_count=$(wc -l < "$listfile" | tr -d ' ')
  if [ "$file_count" -gt 2000 ]; then
    echo "⏳ $file_count files — this is packed one blob per file, so it will take a while."
  fi

  local tmpdir; tmpdir=$(mktemp -d)
  local packout; packout=$(_crypto_pack_upload "$tmpdir" "$listfile")
  rm -f "$listfile"

  local key total_size
  key=$(printf '%s' "$packout" | sed -n '1p')
  total_size=$(printf '%s' "$packout" | sed -n '2p')

  if [[ ! "$key" =~ ^[A-Za-z0-9_-]{43}$ ]] || [[ ! "$total_size" =~ ^[0-9]+$ ]]; then
    echo "❌ Local encryption failed"
    rm -rf "$tmpdir"
    return 1
  fi

  if [ "$total_size" -gt "$_SP_HARD_LIMIT_BYTES" ]; then
    echo "❌ Selection is $((total_size/1024/1024/1024))GB — exceeds the absolute upload ceiling"
    rm -rf "$tmpdir"
    return 1
  fi
  local oversized=0
  if [ "$total_size" -gt "$_SP_SOFT_UPLOAD_BYTES" ]; then
    oversized=1
    echo "ℹ️  Selection is over the 10GB soft limit — the server will ask you to confirm at 1.2x credit cost."
  fi

  local nblobs=0
  while [ -f "$tmpdir/blob$nblobs" ]; do nblobs=$((nblobs + 1)); done

  # ---- Phase 1: init (auth + credit precheck) ----
  local init_out id token
  init_out=$(_bb_upload_init "$total_size") || { rm -rf "$tmpdir"; return 1; }
  id=$(printf '%s' "$init_out" | sed -n '1p'); token=$(printf '%s' "$init_out" | sed -n '2p')
  if [ -z "$id" ] || [ -z "$token" ]; then
    echo "❌ Upload init failed (no id returned)"
    rm -rf "$tmpdir"
    return 1
  fi

  # ---- Phase 2: parallel streaming blob uploads (single Node process) ----
  [ -t 2 ] || echo "☁️  Uploading $nblobs encrypted file entr(y/ies) — up to $_BB_MAX_PAR in parallel..."

  local upres
  upres=$(_bb_upload_blobs "$id" "$tmpdir" "$nblobs" "$token")
  if [ "$upres" != "OK" ]; then
    rm -rf "$tmpdir"
    echo "❌ One or more parts failed to upload. Nothing was finalized; partial objects auto-expire in 30 min."
    return 1
  fi

  # ---- Phase 3: commit (manifest + credit settlement) ----
  local result final_url deducted balance
  result=$(_bb_upload_commit "$id" "$nblobs" "$tmpdir/manifest.enc" "$token") \
    || { rm -rf "$tmpdir"; return 1; }
  rm -rf "$tmpdir"

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

handle_ups_upload() {
  local raw="$1"
  local itemlist="${raw#ups-}"
  _sp_guard_and_resolve "$itemlist" "ups-" || return
  _ups_upload_paths "${sp_resolved[@]}"
}

# Merge the given files into ONE encrypted text blob and upload it.
# Shared by ups- (numbered items) and the fx *.upload.text.* functions
# (CSV / .s selection), so every entry point behaves identically.
_ups_upload_paths() {
  local -a paths=("$@")
  local p
  for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
      echo "❌ ups- doesn't support folder upload. Try up- instead."
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

  echo "📦 Multi-file link detected."
  local dest="$path"
  mkdir -p "$dest"

  echo "🔐 Decrypting and importing..."
  local n
  n=$(_crypto_import_upload "$link" "$key" "$dest")

  if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt 0 ]; then
    echo "✅ Imported $n file(s) into: $dest"
    echo "ℹ️  The remote copy is left in place and will auto-delete on its own after 30 minutes."
  else
    echo "❌ Import failed — nothing was decrypted."
  fi
}
