# Shared endpoint (WORKER_URL), curl hardening (_BB_CURL_OPTS) and _bb_* helpers

_SP_SOFT_UPLOAD_BYTES=$((10*1024*1024*1024))
_SP_HARD_LIMIT_BYTES=$((32*1024*1024*1024))

# Streaming-upload tuning. CHUNK_BYTES must match the worker's CHUNK_BYTES (90 MiB):
# any blob at or below this goes up in one PUT, anything larger uses R2 multipart.
# _BB_MAX_PAR is how many blobs/parts upload concurrently.
_BB_CHUNK_BYTES=$((90*1024*1024))
# (the values come from Settings > File API > Transfer speed: xfer_streams / xfer_chunk_mb; the FILEAPI_BASHBASICS_* variables still win, for tests and scripts)
_BB_MAX_PAR=16
# The tar.gz stream is cut into encrypted chunks of this size (default 4 MiB) => no file-size limit.  A blob is also the unit of RESUME
# (a cut PUT is thrown away), so what an outage can cost = blobs in flight x blob size.  Small blobs let MANY streams run in parallel
# (full speed on fast links) while only ~FILEAPI_BASHBASICS_INFLIGHT_MB (64) is ever at risk.  Was 16 MiB x 16 streams = 256 MB at risk.
_BB_PACK_BYTES=$((4 * 1024 * 1024))
# _bb_xfer_apply: (re)compute stream count and chunk size from the settings.  Called once here and again whenever the person changes them.
# Anything outside the limits (1-64 streams, 1-64 MB) falls back to the setting, never beyond: the worker refuses the rest anyway.
_bb_xfer_apply() {
  local st="${FILEAPI_BASHBASICS_PARALLEL:-${xfer_streams:-16}}" mb="${FILEAPI_BASHBASICS_PACK_MB:-${xfer_chunk_mb:-4}}"
  [[ "$st" =~ ^[0-9]{1,3}$ ]] && [ "$((10#$st))" -ge 1 ] && [ "$((10#$st))" -le "${XFER_MAX_STREAMS:-64}" ] || st=${xfer_streams:-16}
  [[ "$mb" =~ ^[0-9]{1,3}$ ]] && [ "$((10#$mb))" -ge 1 ] && [ "$((10#$mb))" -le "${XFER_MAX_CHUNK_MB:-64}" ] || mb=${xfer_chunk_mb:-4}
  _BB_MAX_PAR=$((10#$st)); _BB_PACK_BYTES=$(( 10#$mb * 1024 * 1024 ))
}
_bb_xfer_apply

_bb_authed_put() {
  local endpoint="$1" est_size="$2"; shift 2
  local -a extra_args=("$@")

  _bb_get_credentials || return 1

  _bb_alias_prepare
  local attempt=0 confirmed=false
  while :; do
    attempt=$((attempt + 1))

    local cfg
    cfg=$({ _bb_auth_cfg
            _bb_link_cfg
            [ -n "$est_size" ] && _bb_cfg_header X-Estimated-Size "$est_size"
            $confirmed && _bb_cfg_header X-Confirm-Oversized yes
            true; })
    local hdrfile response http_status body
    hdrfile=$(mktemp)
    response=$(curl -s "${_BB_CURL_OPTS[@]}" -K - -D "$hdrfile" -w "\n%{http_code}" -H "Expect:" -X PUT "${extra_args[@]}" "$WORKER_URL$endpoint" <<<"$cfg")
    http_status=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_status" == "201" ]; then
      _bb_created_emit "$hdrfile" "$body"
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
      echo "🔴  ${msg}" >&2
      _bvk_yn ans "Proceed at 1.2x credit cost?"
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
  _dep_have fileapi && return 0
  if [ "${_SVC_QUIET:-0}" = 1 ]; then echo "❌ ${_DEP_MISSING} missing: a background upload never opens a menu (start an upload from the menu once to install it)."; return 1; fi
  _dep_need -c "Encryption and upload (up- / c2c- / do-)" fileapi
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

# After a new link: keep it (encrypted, for any device) and tell the sender what recipients will see.
_bb_link_store_and_explain() {
  local url="$1" base id d3 mail="${FILEAPI_BASHBASICS_EMAIL:-}"
  if [ "${FILEAPI_BASHBASICS_STORE_KEYS:-1}" != "0" ]; then
    base="${url%%#*}"; base="${base%/}"; id="${base##*/}"
    if [ "${FILEAPI_BASHBASICS_LINK_SYNC:-0}" = 1 ]; then
      if _bb_link_secret_put "$id" "$url"; then
        echo "☁️  Kept (encrypted — the server cannot read it) in Home → Links: copy it again with  c-N  from any device."
      else
        echo "📜  Not kept in the cloud (needs your dinons on this computer, or the server was unreachable). It is still saved on this computer."
      fi
    else
      # fetching the key chain + storing the encrypted link takes a few round trips: do it in the background, nothing to wait for
      ( _bb_link_secret_put "$id" "$url" >/dev/null 2>&1 ) >/dev/null 2>&1 &
      disown 2>/dev/null
      echo "☁️  Saving it (encrypted — the server cannot read it) to Home → Links in the background: copy it again with  c-N  from any device."
    fi
  fi
  d3=$(_bb_d3 "${FILEAPI_BASHBASICS_DISEPS:-}")
  echo "🪪 Anyone who opens this link sees WHO shared it:  ${mail:-?}${d3:+  ·  $d3}   (+ Copy and Report-abuse → ${WORKER_URL%/}/help)"
  echo "   Links are encrypted so nobody can look inside; reports about pirated, adult or illegal content go to the admin and can"
  echo "   restrict the link and suspend the account. Only share what you may share."
}

_announce_link() {
  local final_url="$1"
  local url_payload
  _bb_key_remember "$final_url"          # so the api loop can copy / rebuild this link later (no re-upload)
  url_payload=$(printf "%s" "$final_url" | base64 | tr -d '\n')

  if [[ "$TERM" == "screen"* ]] || [[ "$TERM" == "tmux"* ]]; then
    printf "\033Ptmux;\033\033]52;c;%s\a\033\\" "$url_payload"
  else
    printf "\033]52;c;%s\a" "$url_payload"
  fi

  echo "💫 Link copied to clipboard (best effort). Key is embedded after # — keep the whole link intact."
  echo "-------------------------------------------"
  echo "Link: $final_url"
  echo "-------------------------------------------"
  _bb_link_store_and_explain "$final_url"

  if [ "${FILEAPI_BASHBASICS_OPEN:-0}" = "1" ]; then
    ( open "$final_url" || xdg-open "$final_url" || termux-open-url "$final_url" ) &> /dev/null &
  else
    echo "📜  Not auto-opened: the browser viewer runs code delivered by the server, which could in theory read the key."
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
  local outdir="$1" arcname="$2" jl
  jl=$(_bb_jslib) || return 1
  BB_JSLIB="$jl" BB_PACK_BYTES="${_BB_PACK_BYTES}" BB_ARC_NAME="$arcname" node -e '
    // status line, pack status and chunk writer: shared with the other node transfer tools (bashbasicsbyvk_staging_jslib.js)
    const { packStatus, writeChunks } = require(process.env.BB_JSLIB);
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

    const TTY = process.stderr.isTTY, status = packStatus();

    (async () => {
      let res;
      try {
        res = await writeChunks(process.stdin, { chunk: CHUNK, onBytes: status.add,
          seal: (piece, i) => encrypt(piece, "bbvk4|blob|" + i), fileFor: (i) => path.join(outdir, "blob" + i) });
      } catch (e) {
        if (TTY) process.stderr.write("\n");
        console.error("  \u274c " + (e && e.code === "ENOSPC" ? "Disk full while writing encrypted blobs." : "Packing failed: " + (e && e.message)));
        process.exit(3);
      }
      const { idx, plainTotal, cipherTotal } = res;
      status.done();
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
  if _bvk_xfer_bin; then           # the Go engine (no node start-up, one HTTP/2 connection); node below is the fallback
    local gv; gv=$(BB_KEY="$key" "$_BVK_XFER_BIN" fetch "$link" "$outfile" "$_BB_MAX_PAR" | tail -n 1)
    case "${gv%%$'\t'*}" in
      OK|EXPIRED|BADKEY|FAILED) printf '%s\n' "$gv"; return 0 ;;
    esac
    _bb_xfer_note go-fallback "fetch gave no verdict (crashed?) — continued with node"
  fi
  local jl; jl=$(_bb_jslib) || { echo FAILED; return 0; }
  BB_JSLIB="$jl" BB_KEY="$key" node -e '
    // status-line helpers: shared with the other node transfer tools (bashbasicsbyvk_staging_jslib.js)
    const { live } = require(process.env.BB_JSLIB);
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
    // owner-only items (Saved Surf / Snapshots) are fetched with the account headers; public links need none
    const AUTH = process.env.BB_FETCH_AUTH === "1" ? { "X-User-Email": process.env.BB_EMAIL || "", "X-User-Diseps": process.env.BB_DISEPS || "", "X-User-Key": process.env.BB_APIKEY || "" } : {};
    async function get(url) {
      for (let a = 0; a < 4; a++) {
        try {
          const res = await fetch(url, { redirect: "error", credentials: "omit", headers: AUTH });
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
        live( (done >= n ? "\u001b[32m" : "\u001b[36m") + "[" + "\u2588".repeat(f) + "\u2591".repeat(COLS - f) + "] " +
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
      await Promise.all(Array.from({ length: Math.min(Math.max(CONC, Math.min(24, Math.floor(134217728 / C))), n) }, worker));   // small blobs: keep ~128 MB in flight
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
  local stage nfiles expanded go_ok=0
  if _bvk_xfer_bin; then      # Go: ONE pass that checks and extracts (the tar way below reads the archive three times)
    local ures ukind umsg
    stage=$(mktemp -d "$dest/.bbvk_x.XXXXXX") || { echo "❌ Could not write to $dest"; return 1; }
    ures=$("$_BVK_XFER_BIN" untar "$arc" "$stage" 2>/dev/null | tail -n 1)
    IFS=$'\t' read -r ukind nfiles expanded <<<"$ures"
    case "$ukind" in
      OK) go_ok=1; echo "📂 Unpacked $nfiles file(s), $((expanded/1024/1024)) MB" ;;
      ERR) umsg="$nfiles"; echo "❌ ${umsg:-Unpacking failed.}"; rm -rf "$stage"; return 1 ;;
      *)  rm -rf "$stage"; _bb_xfer_note go-fallback "untar gave no verdict (crashed?) — continued with tar" ;;
    esac
  fi
  if [ $go_ok = 0 ]; then
  command -v tar &>/dev/null || { echo "❌ 'tar' not found — install it first."; return 1; }

  local ls_tmp; ls_tmp=$(mktemp "$dest/.bbvk_ls.XXXXXX") || { echo "❌ Could not write to $dest"; return 1; }
  if ! tar -tzvf "$arc" --numeric-owner > "$ls_tmp" 2>/dev/null; then
    echo "❌ The decrypted archive is not a valid tar.gz — refusing to unpack."
    rm -f "$ls_tmp"; return 1
  fi

  local nbad nnames stats free
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
  stage=$(mktemp -d "$dest/.bbvk_x.XXXXXX") || return 1
  local errf; errf=$(mktemp)
  if ! tar -xzf "$arc" -C "$stage" --no-same-owner --no-same-permissions --no-overwrite-dir 2> "$errf"; then
    echo "❌ Unpacking failed:"; head -n 3 "$errf" | sed 's/^/   /'
    rm -rf "$stage" "$errf"; return 1
  fi
  rm -f "$errf"
  fi

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
  echo "💫 Imported $nfiles file(s) into: $dest"
  return 0
}

# Phase 1: authorize + credit precheck, get an upload id back. Echoes the id.
# _bb_upload_init <estimated-bytes> [blob-count]   — X-Pending: 1 makes the server NOTE this upload (pending.js): it can then be paused,
# continued after a lost connection / Ctrl-C / kill, or stopped, and the server keeps its blobs for 3 days instead of ~2.5 hours.
_bb_upload_init() {
  local est_size="$1" nblobs_hint="${2:-}"
  _bb_get_credentials || return 1

  _bb_alias_prepare
  local attempt=0 confirmed=false
  [ -n "${_BB_OVERSIZE_OK:-}" ] && confirmed=true     # the price prompt already covered the 1.2x rate
  while :; do
    attempt=$((attempt + 1))
    local cfg
    cfg=$({ _bb_auth_cfg
            _bb_link_cfg
            _bb_cfg_header X-Estimated-Size "$est_size"
            _bb_cfg_header X-Pending 1
            [[ "$nblobs_hint" =~ ^[0-9]+$ ]] && _bb_cfg_header X-Blob-Count "$nblobs_hint"
            $confirmed && _bb_cfg_header X-Confirm-Oversized yes
            true; })
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

    # a glitch right at the start (offline, 5xx): nothing was sent yet, so just try again a few times
    if { [ "$http_status" == "000" ] || [[ "$http_status" == 5* ]]; } && [ "$attempt" -lt 4 ]; then
      [ "${_SVC_QUIET:-0}" = 1 ] || echo "⏳ Server not reachable — trying again in $((attempt * 3))s…" >&2
      sleep $((attempt * 3)); continue
    fi

    # 401 = the saved profile's credentials are wrong. Retrying would just reload
    # the same profile and fail identically, so report once and stop.
    if [ "$http_status" == "401" ]; then
      echo "❌ ${msg:-Authentication failed.}" >&2
      echo "🔁 Fix the active user with  -auth  inside 'o', then try again." >&2
      return 1
    fi

    if [ "$http_status" == "409" ] && [ "$err_type" == "oversized_confirmation_required" ] && ! $confirmed; then
      echo "🔴  ${msg}" >&2
      _bvk_yn ans "Proceed at 1.2x credit cost?"
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then confirmed=true; continue; fi
      echo "🚫 Cancelled." >&2
      return 1
    fi

    echo "❌ $(_bb_fail_reason "$body" "$http_status")" >&2
    return 1
  done
}

# Phase 2 (sending the blobs) now lives in bashbasicsbyvk_staging_pending.sh (_pn_complete → bashbasicsbyvk_staging_pending_xfer):
# one Node process, keep-alive pool, byte-based progress bar — and it waits out a lost connection, skips the blobs the server
# already holds, and honours pause / stop.

# Phase 3: upload the manifest, settle credits, return the link + credit headers.
_BB_COMMIT_HDRS=()        # extra commit headers (X-Vault-Kdk, X-Snap-*) set by the Backup / Saved / Snapshot services
_bb_upload_commit() {
  local id="$1" fcount="$2" mpath="$3" token="$4"
  _BB_COMMIT_STATUS=""; _BB_COMMIT_ERR=""
  local cfg
  local h
  cfg=$({ _bb_cfg_header X-User-Email "$FILEAPI_BASHBASICS_EMAIL"
          _bb_cfg_header X-Upload-Token "$token"
          _bb_cfg_header X-File-Count "$fcount"
          for h in "${_BB_COMMIT_HDRS[@]}"; do _bb_cfg_header "${h%%:*}" "${h#*: }"; done; })

  local hdrfile response http_status body
  hdrfile=$(mktemp)
  response=$(curl -s "${_BB_CURL_OPTS[@]}" -K - -D "$hdrfile" -w "\n%{http_code}" -H "Expect:" -X PUT \
    --data-binary "@$mpath" "$WORKER_URL/upload/$id/commit" <<<"$cfg")
  http_status=$(echo "$response" | tail -n 1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_status" == "201" ]; then
    _bb_created_emit "$hdrfile" "$body"
    return 0
  fi
  rm -f "$hdrfile"
  _BB_COMMIT_STATUS="$http_status"; _BB_COMMIT_ERR=$(_bb_json_get "$body" error)
  echo "❌ $(_bb_fail_reason "$body" "$http_status")" >&2
  return 1
}

# ════════════════════════════════════════════════════════════════════════════
#  _bb_fast_send <dir> <total-bytes> <blobs> [pack-ms]      the Go engine's FAST PATH, shared by up- · backup · save- · snapshot
#  ONE request for a small upload (blob + manifest + commit); for a big one the init rides on blob 0 and the commit on the last blob.  Auth, size and
#  credits are checked by the server on the very first request.  Above FILEAPI_BASHBASICS_FAST_MAX_MB (default 64) the upload is HANDED OVER to the
#  resumable path after blob 0, so a long transfer keeps pause · Ctrl-C · offline waiting · continue-later.
#  Reads _BB_COMMIT_HDRS (vault key, snapshot target) and the usual _BB_SVC / alias / ttl state.
#    return 0 done (_FS_URL _FS_DEDUCTED _FS_BALANCE _FS_EXPIRES) · 1 refused (message printed) · 2 continue in the resumable path (_FS_ID: the
#    server's id, or empty = it has nothing yet) · 3 interrupted by Ctrl-C (_FS_ID: keep in Pending when set) · 4 not used (no Go engine / credentials)
# ════════════════════════════════════════════════════════════════════════════
_FS_URL=""; _FS_DEDUCTED=""; _FS_BALANCE=""; _FS_EXPIRES=""; _FS_ID=""
_bb_fast_send() {
  local dir="$1" est="$2" nb="$3" pack_ms="${4:-0}"
  _FS_URL=""; _FS_DEDUCTED=""; _FS_BALANCE=""; _FS_EXPIRES=""; _FS_ID=""
  _bvk_xfer_bin || return 4
  _bb_get_credentials >/dev/null 2>&1 || return 4
  _bb_alias_prepare
  local fcfg fh fconc fbudget="${FILEAPI_BASHBASICS_INFLIGHT_MB:-64}" fbsz=$_BB_PACK_BYTES fmax="${FILEAPI_BASHBASICS_FAST_MAX_MB:-64}"
  [[ "$fbudget" =~ ^[0-9]{1,4}$ ]] && [ "$fbudget" -ge 4 ] || fbudget=64
  [[ "$fmax" =~ ^[0-9]{1,6}$ ]] || fmax=64
  _bb_xfer_apply; fbsz=$_BB_PACK_BYTES
  fconc=$_BB_MAX_PAR
  if [ -n "${FILEAPI_BASHBASICS_INFLIGHT_MB:-}" ] && [ -z "${FILEAPI_BASHBASICS_PARALLEL:-}" ]; then   # an explicit byte budget still sets the count
    fconc=$(( fbudget * 1048576 / fbsz )); [ "$fconc" -lt 2 ] && fconc=2; [ "$fconc" -gt "${XFER_MAX_STREAMS:-64}" ] && fconc=${XFER_MAX_STREAMS:-64}
  fi
  fcfg=$({ _bb_auth_cfg
           _bb_link_cfg
           [ -n "${_BB_OVERSIZE_OK:-}" ] && _bb_cfg_header X-Confirm-Oversized yes
           for fh in "${_BB_COMMIT_HDRS[@]}"; do _bb_cfg_header "${fh%%:*}" "${fh#*: }"; done
           true; })
  [ -t 2 ] || [ "${_SVC_QUIET:-0}" = 1 ] || echo "☁️  Uploading $nb encrypted blob(s)..."
  local fout fverdict tline
  _bb_progress_begin      # the send bar owns the screen: no loading bar until it is done
  fout=$("$_BVK_XFER_BIN" send --dir "$dir" --url "$WORKER_URL" --est "$est" --n "$nb" --conc "$fconc" --handover-over "$((fmax * 1048576))" <<<"$fcfg")
  _bb_progress_end
  fverdict=$(printf '%s\n' "$fout" | sed -n '1p')
  tline=$(printf '%s\n' "$fout" | grep -m1 $'^TIME\t')
  _bb_xfer_note go-timing "pack=${pack_ms}ms ${tline#TIME$'\t'}"
  case "${fverdict%%$'\t'*}" in
    OK)
      _FS_URL=$(printf '%s\n' "$fout" | sed -n '2p'); _FS_DEDUCTED=$(printf '%s\n' "$fout" | sed -n '3p')
      _FS_BALANCE=$(printf '%s\n' "$fout" | sed -n '4p'); _FS_EXPIRES=$(printf '%s\n' "$fout" | sed -n '5p')
      return 0 ;;
    HANDOVER)
      IFS=$'\t' read -r _ _FS_ID <<<"$fverdict"; return 2 ;;
    INTERRUPTED)
      IFS=$'\t' read -r _ _FS_ID <<<"$fverdict"; [ "$_FS_ID" = "-" ] && _FS_ID=""; return 3 ;;
    REFUSED)
      local fst fer fmsg
      IFS=$'\t' read -r _ fst fer fmsg <<<"$fverdict"
      [ "$fer" = oversized_confirmation_required ] && return 2     # a question, not a refusal: the old path asks it
      echo "❌ ${fmsg:-The server refused the upload (HTTP $fst).}" >&2
      [ "$fst" = 401 ] && echo "🔁 Fix the active user with  -auth  inside 'o', then try again." >&2
      return 1 ;;
    FALLBACK)
      local fwhy; IFS=$'\t' read -r _ _FS_ID fwhy <<<"$fverdict"
      [ "$_FS_ID" = "-" ] && _FS_ID=""
      _bb_xfer_note go-fallback "${fwhy:-interrupted}${_FS_ID:+ (upload $_FS_ID continued on the resumable path)}"
      [ "${_SVC_QUIET:-0}" = 1 ] || echo "↪️  Switching to the resumable path (${fwhy:-interrupted})…" >&2
      return 2 ;;
    *)
      _bb_xfer_note go-fallback "send gave no verdict (crashed?)"; return 2 ;;
  esac
}

_up_do_multipart_upload() {
  local -a paths=("$@")
  local use_go=0; _bvk_xfer_bin && use_go=1             # the Go engine packs, encrypts and sends; node / tar / gzip are only the fallback
  if [ $use_go = 0 ]; then
    _bb_xfer_note node-engine "${_BVK_XFER_WHY:-engine unavailable}"
    _crypto_check || return 1
    _dep_need -c "Uploading with up-" fileapi.pack || return 1
  fi
  local -a gz; local lvl; _bb_gzip_setup

  echo "🔎 Scanning selection..."
  # Stage the selection by name as symlinks so the archive holds "<name>/..." entries relative
  # to nothing absolute (same layout the old per-file upload produced).
  local stage tmpdir rcfile errfile
  stage=$(mktemp -d) && tmpdir=$(_pn_mkpack) && rcfile=$(mktemp) && errfile=$(mktemp) \
    || { echo "❌ Could not create temp files."; return 1; }
  _up_cleanup() { rm -rf "$stage" ${tmpdir:+"$tmpdir"} "$rcfile" "$errfile"; }

  local -a rel_items=()
  _bb_stage_links "$stage" echo "${paths[@]}"
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
  local packout _tp0=${EPOCHREALTIME/./} _tp1; _tp0=${_tp0:-0}
  _bb_progress_begin      # the pack bar owns the screen
  if [ $use_go = 1 ]; then
    packout=$(
      cd "$stage" || exit 1
      _hid_find0 "$hid_inc" 1 "${rel_items[@]}" 2>> "$errfile" \
        | "$_BVK_XFER_BIN" pack --out "$tmpdir" --name "$arcname" --level "$lvl" --chunk "$_BB_PACK_BYTES" --rc "$rcfile" --warn "$errfile"
    )
  else
    packout=$(
      cd "$stage" || exit 1
      _hid_find0 "$hid_inc" 1 "${rel_items[@]}" 2>> "$errfile" \
        | { tar --null --no-recursion -h -T - -cf - 2>> "$errfile"; echo $? > "$rcfile"; } \
        | "${gz[@]}" "-$lvl" -c \
        | _crypto_stream_pack "$tmpdir" "$arcname"
    )
  fi
  _bb_progress_end

  _tp1=${EPOCHREALTIME/./}; _tp1=${_tp1:-0}
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
    echo "🔴  Some files changed or were unreadable while packing (they may be missing/partial):"
    head -n 3 "$errfile" | sed 's/^/   /'
  fi
  echo "   $((total_size/1024/1024)) MB after tar.gz + encryption, in $nblobs blob(s)."

  if [ "$total_size" -gt "$_SP_HARD_LIMIT_BYTES" ]; then
    echo "❌ Packed size is $((total_size/1024/1024/1024))GB — exceeds the absolute upload ceiling"
    _up_cleanup; return 1
  fi
  if [ "$total_size" -gt "$_SP_SOFT_UPLOAD_BYTES" ]; then
    echo "📜  Packed size is over the 10GB soft limit — the server will ask you to confirm at 1.2x credit cost."
  fi

  # ---- price check: cost 1 → silent; more → continue / reduce time / increase time / stop ----
  _bb_get_credentials >/dev/null 2>&1 && { _bb_credit_gate "$total_size" "This upload" || { _up_cleanup; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1; }; }

  # ---- FAST PATH (Go engine) — see _bb_fast_send.  Anything that goes wrong half-way continues in the resumable path below (nothing is lost). ----
  local fast_id="" fast_intr=0 pack_ms=$(( (_tp1 - _tp0) / 1000 ))
  if [ $use_go = 1 ]; then
    _bb_fast_send "$tmpdir" "$total_size" "$nblobs" "$pack_ms"; local frc=$?
    case $frc in
      0) _up_cleanup
         _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""
         _announce_link "${_FS_URL}#k=${key}"
         [ -n "$_FS_DEDUCTED" ] && echo "💳 Credits deducted: $_FS_DEDUCTED   |   Balance: $_FS_BALANCE"
         _bb_print_expiry "$_FS_EXPIRES"
         return 0 ;;
      1) _up_cleanup; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1 ;;
      2) fast_id="$_FS_ID" ;;
      3) fast_id="$_FS_ID"; fast_intr=1
         if [ -z "$fast_id" ]; then _up_cleanup; echo "⏹  Cancelled — nothing was kept."; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1; fi ;;
    esac
  fi

  # ---- Phase 1: init (auth + credit precheck) → the unique service id; the encrypted blobs move to the pending folder ----
  local init_out id token pdir
  if [ -n "$fast_id" ]; then
    id="$fast_id"; token="resume"                        # the server already knows this upload (init rode on blob 0): just continue it
  else
    init_out=$(_bb_upload_init "$total_size" "$nblobs") || { _up_cleanup; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1; }
    id=$(printf '%s' "$init_out" | sed -n '1p'); token=$(printf '%s' "$init_out" | sed -n '2p')
  fi
  if [ -z "$id" ] || [ -z "$token" ]; then
    echo "❌ Upload init failed (no id returned)"; _up_cleanup; return 1
  fi
  pdir=$(_pn_adopt "$tmpdir" "$id" upload "$nblobs" "$total_size" "$arcname" "key=$key") || { echo "❌ Could not keep the upload folder."; _up_cleanup; return 1; }
  tmpdir=""; _up_cleanup

  # ---- Phase 2 + 3: send what the server lacks (waits out a lost connection) → commit.  Ctrl-C / kill / offline keep it in Pending. ----
  if [ "$fast_intr" = 1 ]; then
    _pn_set "$pdir" status interrupted
    echo "⏸  Stopped for now — nothing is lost. Continue it from Pending (pn)."
    echo "   (Pending → type  pn  — the encrypted data waits in $(_pn_root))"
    _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1
  fi
  [ -t 2 ] || [ $use_go = 1 ] || echo "☁️  Uploading $nblobs encrypted blob(s) — up to $_BB_MAX_PAR in parallel..."
  _pn_complete "$pdir" 0; local prc=$?
  if [ $prc -ne 0 ]; then
    [ $prc -ge 20 ] && echo "   (Pending → type  pn  — the encrypted data waits in $(_pn_root))"
    _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1
  fi
  local final_url="$_PN_URL" deducted="$_PN_DEDUCTED" balance="$_PN_BALANCE" expires="$_PN_EXPIRES"

  _announce_link "${final_url}#k=${key}"
  [ -n "$deducted" ] && echo "💳 Credits deducted: $deducted   |   Balance: $balance"
  _bb_print_expiry "$expires"
}

# up-<items> [as <alias>]     e.g.  up-1-5   ·   up-a-1-5 as user data
# The alias is the label the api loop shows for this link instead of its address.
handle_up_upload() {
  local raw="$1"
  _bb_split_alias "${raw#up-}" || return
  local itemlist="$_BB_ITEMLIST" rc
  _sp_guard_and_resolve "$itemlist" "up-" || { _BB_LINK_ALIAS=""; return; }
  _up_do_multipart_upload "${sp_resolved[@]}"; rc=$?
  _BB_LINK_ALIAS=""; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""
  return $rc
}

# c2c-<items> [as <alias>]    e.g.  c2c-2,4 as notes
handle_c2c_upload() {
  local raw="$1"
  _bb_split_alias "${raw#c2c-}" || return
  local itemlist="$_BB_ITEMLIST" rc
  _sp_guard_and_resolve "$itemlist" "c2c-" || { _BB_LINK_ALIAS=""; return; }
  _c2c_paths "${sp_resolved[@]}"; rc=$?
  _BB_LINK_ALIAS=""
  return $rc
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
    if [ -f "$p" ]; then nvalid=$((nvalid + 1)); else echo "  🔴  Skipping missing item: $p"; fi
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
  local result final_url deducted balance expires
  if ! result=$(_bb_authed_put "/copy" "" --data-binary "@$enc_tmp"); then
    rm -f "$enc_tmp"
    return 1
  fi
  rm -f "$enc_tmp"

  final_url=$(echo "$result" | sed -n '1p')
  deducted=$(echo "$result" | sed -n '2p')
  balance=$(echo "$result" | sed -n '3p')
  expires=$(echo "$result" | sed -n '4p')

  _announce_link "${final_url}#k=${key}"
  [ -n "$deducted" ] && echo "💳 Credits deducted: $deducted   |   Balance: $balance"
  _bb_print_expiry "$expires"
}

handle_do_import() {
  _crypto_check || return 1

  read -e -r -p "Paste link to import (include the #k=... part): " link
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
    read -r -s -p "No key found in the pasted link — paste the decryption key separately: " key
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
    echo "🔴  This link points to '$lhost', not your configured server ($whost)."
    local ans; _bvk_yn ans "Continue anyway?"
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
      read -e -r -p "Save as filename in $path (blank = print to terminal): " fname
    else
      fname=""
    fi

    if [ -n "$fname" ]; then
      if [[ "$fname" == */* || "$fname" == "." || "$fname" == ".." ]]; then
        echo "❌ Invalid file name."; rm -f "$plain_tmp"; return 1
      fi
      if _bvk_name_too_long "$fname"; then
        _bvk_name_refuse "$fname" "File"; rm -f "$plain_tmp"; return 1
      fi
      if [ -e "$path/$fname" ]; then
        echo "❌ $path/$fname already exists — refusing to overwrite."; rm -f "$plain_tmp"; return 1
      fi
      mv -n -- "$plain_tmp" "$path/$fname"
      echo "💫 Imported as: $path/$fname"
    else
      # Received text is untrusted: strip control characters / escape sequences before it
      # reaches the terminal (they can retitle the window, rewrite the screen or set the clipboard).
      LC_ALL=C tr -d '\000-\010\013-\037\177' < "$plain_tmp"
      if [ "$(LC_ALL=C tr -d '\000-\010\013-\037\177' < "$plain_tmp" | wc -c)" != "$(wc -c < "$plain_tmp")" ]; then
        echo; echo "📜  Control characters were removed for display. Save to a file to keep the raw text."
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

  local res; _bb_progress_begin; res=$(_crypto_fetch_archive "$link" "$key" "$arc"); _bb_progress_end      # the download bar owns the screen
  case "${res%%$'\t'*}" in
    OK) ;;
    EXPIRED) echo "❌ Link expired, invalid, or already nuked."; rm -f "$arc"; return 1 ;;
    BADKEY)  echo "❌ Decryption failed — wrong key, tampered data, or a link made by an older client version (those expire after 30 minutes)."; rm -f "$arc"; return 1 ;;
    *)       echo "❌ Download failed — some chunks could not be fetched or failed their integrity check. Nothing was unpacked."; rm -f "$arc"; return 1 ;;
  esac

  _unpack_targz_safe "$arc" "$path"
  local rc=$?
  rm -f "$arc"
  [ $rc -eq 0 ] && echo "📜  The remote copy is left in place and will be nuked on its own when its nuke time runs out (or nuke it earlier from  api)."
  return $rc
}
