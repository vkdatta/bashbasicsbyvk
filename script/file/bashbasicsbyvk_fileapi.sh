WORKER_URL="https://fileapi.bashbasics.workers.dev"

_SP_SOFT_UPLOAD_BYTES=$((10*1024*1024*1024))
_SP_HARD_LIMIT_BYTES=$((32*1024*1024*1024))

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

    local -a hdrs=(
      -H "X-User-Email: $FILEAPI_BASHBASICS_EMAIL"
      -H "X-User-Key: $FILEAPI_BASHBASICS_KEY"
    )
    [ -n "$est_size" ] && hdrs+=(-H "X-Estimated-Size: $est_size")
    $confirmed && hdrs+=(-H "X-Confirm-Oversized: yes")

    local hdrfile response http_status body
    hdrfile=$(mktemp)
    response=$(curl -s -D "$hdrfile" -w "\n%{http_code}" -H "Expect:" -X PUT "${hdrs[@]}" "${extra_args[@]}" "$WORKER_URL$endpoint")
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

_crypto_encrypt_stdin() {
  local keyb64url="$1"
  node -e '
    const crypto = require("crypto");
    const chunks = [];
    process.stdin.on("data", c => chunks.push(c));
    process.stdin.on("end", () => {
      const data = Buffer.concat(chunks);
      const key = Buffer.from(process.argv[1].replace(/-/g,"+").replace(/_/g,"/"), "base64");
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
      const ct = Buffer.concat([cipher.update(data), cipher.final()]);
      const tag = cipher.getAuthTag();
      process.stdout.write(Buffer.concat([iv, ct, tag]));
    });
  ' "$keyb64url"
}

_crypto_decrypt_stdin() {
  local keyb64url="$1"
  node -e '
    const crypto = require("crypto");
    const chunks = [];
    process.stdin.on("data", c => chunks.push(c));
    process.stdin.on("end", () => {
      const buf = Buffer.concat(chunks);
      if (buf.length < 28) { process.exit(1); }
      const iv = buf.subarray(0, 12);
      const tag = buf.subarray(buf.length - 16);
      const ct = buf.subarray(12, buf.length - 16);
      const key = Buffer.from(process.argv[1].replace(/-/g,"+").replace(/_/g,"/"), "base64");
      try {
        const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
        decipher.setAuthTag(tag);
        const pt = Buffer.concat([decipher.update(ct), decipher.final()]);
        process.stdout.write(pt);
      } catch (e) {
        process.exit(1);
      }
    });
  ' "$keyb64url"
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

  ( open "$final_url" || xdg-open "$final_url" || termux-open-url "$final_url" ) &> /dev/null &
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

    function encrypt(buf) {
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
      const ct = Buffer.concat([cipher.update(buf), cipher.final()]);
      const tag = cipher.getAuthTag();
      return Buffer.concat([iv, ct, tag]);
    }

    const entries = [];
    lines.forEach((line, idx) => {
      const tabIdx = line.indexOf("\t");
      const relpath = line.slice(0, tabIdx);
      const abspath = line.slice(tabIdx + 1);
      const data = fs.readFileSync(abspath);
      fs.writeFileSync(path.join(outdir, "blob" + idx), encrypt(data));
      entries.push({ path: relpath, size: data.length, blobIndex: idx });
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

    const manifest = { version: 1, fileCount: entries.length, tree: root };
    fs.writeFileSync(path.join(outdir, "manifest.enc"), encrypt(Buffer.from(JSON.stringify(manifest), "utf8")));

    process.stdout.write(keyB64url);
  ' "$outdir" "$listfile"
}

_crypto_import_upload() {
  local link="$1" key="$2" dest="$3"
  node -e '
    const fs = require("fs"), path = require("path"), crypto = require("crypto");
    const link = process.argv[1];
    const key = Buffer.from(process.argv[2].replace(/-/g,"+").replace(/_/g,"/"), "base64");
    const dest = process.argv[3];

    function decrypt(buf) {
      const iv = buf.subarray(0, 12);
      const tag = buf.subarray(buf.length - 16);
      const ct = buf.subarray(12, buf.length - 16);
      const decipher = crypto.createDecipheriv("aes-256-gcm", key, iv);
      decipher.setAuthTag(tag);
      return Buffer.concat([decipher.update(ct), decipher.final()]);
    }

    (async () => {
      const manifestRes = await fetch(link + "/manifest");
      if (!manifestRes.ok) { console.error("Manifest fetch failed (HTTP " + manifestRes.status + ")"); console.log(0); return; }
      let manifest;
      try {
        manifest = JSON.parse(decrypt(Buffer.from(await manifestRes.arrayBuffer())).toString("utf8"));
      } catch (e) {
        console.error("Decryption failed — wrong key or corrupted link.");
        console.log(0);
        return;
      }

      const files = [];
      (function walk(nodes, prefix) {
        for (const n of (nodes || [])) {
          if (n.type === "file") files.push({ relpath: prefix + n.name, blobIndex: n.blobIndex });
          if (n.children) walk(n.children, prefix + n.name + "/");
        }
      })(manifest.tree, "");

      let ok = 0;
      for (const f of files) {
        const fileRes = await fetch(link + "/file/" + f.blobIndex);
        if (!fileRes.ok) { console.error("  \u2717 " + f.relpath + " (HTTP " + fileRes.status + ")"); continue; }
        let plain;
        try { plain = decrypt(Buffer.from(await fileRes.arrayBuffer())); }
        catch (e) { console.error("  \u2717 " + f.relpath + " (decrypt failed)"); continue; }
        const outPath = path.join(dest, f.relpath);
        fs.mkdirSync(path.dirname(outPath), { recursive: true });
        fs.writeFileSync(outPath, plain);
        console.error("  \u2713 " + f.relpath);
        ok++;
      }
      console.log(ok);
    })();
  ' "$link" "$key" "$dest"
}

_up_do_multipart_upload() {
  local -a paths=("$@")
  _crypto_check || return 1

  local listfile; listfile=$(mktemp)
  local total_size=0 p file base rel sz

  for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
      base=$(basename -- "$p")
      while IFS= read -r -d '' file; do
        rel="${file#$p/}"
        printf '%s\t%s\n' "${base}/${rel}" "$file" >> "$listfile"
        sz=$(stat -c%s "$file" 2>/dev/null || echo 0)
        total_size=$((total_size + sz))
      done < <(find "$p" -type f -print0)
    elif [ -f "$p" ]; then
      printf '%s\t%s\n' "$(basename -- "$p")" "$p" >> "$listfile"
      sz=$(stat -c%s "$p" 2>/dev/null || echo 0)
      total_size=$((total_size + sz))
    else
      echo "  ⚠️  Skipping missing item: $p"
    fi
  done

  if [ ! -s "$listfile" ]; then
    echo "❌ No valid files found in selection"
    rm -f "$listfile"
    return 1
  fi

  if [ "$total_size" -gt "$_SP_HARD_LIMIT_BYTES" ]; then
    echo "❌ Selection is $((total_size/1024/1024/1024))GB — exceeds the absolute upload ceiling"
    rm -f "$listfile"
    return 1
  fi
  if [ "$total_size" -gt "$_SP_SOFT_UPLOAD_BYTES" ]; then
    echo "ℹ️  Selection is over the 10GB soft limit — the server will ask you to confirm at 1.2x credit cost."
  fi

  local file_count; file_count=$(wc -l < "$listfile" | tr -d ' ')
  echo "🔐 Encrypting $file_count file entr(y/ies) locally (key never leaves this machine)..."

  local tmpdir; tmpdir=$(mktemp -d)
  local key; key=$(_crypto_pack_upload "$tmpdir" "$listfile")
  rm -f "$listfile"

  if [ -z "$key" ]; then
    echo "❌ Local encryption failed"
    rm -rf "$tmpdir"
    return 1
  fi

  local -a form_args=()
  local i=0
  while [ -f "$tmpdir/blob$i" ]; do
    form_args+=(-F "files=@${tmpdir}/blob${i}")
    i=$((i + 1))
  done
  form_args+=(-F "manifest=@${tmpdir}/manifest.enc")

  echo "☁️  Uploading $i encrypted file entr(y/ies)..."
  local result final_url deducted balance
  if ! result=$(_bb_authed_put "/upload" "$total_size" "${form_args[@]}"); then
    rm -rf "$tmpdir"
    return 1
  fi
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

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: up-1,3,5  or  up-1-3,7  (files and folders both supported)"
    return
  fi
  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using up-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return
  _up_do_multipart_upload "${sp_resolved[@]}"
}

handle_ups_upload() {
  local raw="$1"
  local itemlist="${raw#ups-}"

  if [ -z "$itemlist" ]; then
    echo "⚠️  Usage: ups-1,3,5  or  ups-1-3,7  (files only — no folders)"
    return
  fi
  if $imaginary_mode; then
    echo "⚠️  Too many items to index directly — narrow the view before using ups-."
    return
  fi

  _sp_resolve_itemlist "$itemlist" || return

  local p
  for p in "${sp_resolved[@]}"; do
    if [ -d "$p" ]; then
      echo "❌ ups- doesn't support folder upload. Try up- instead."
      return 1
    fi
  done

  _crypto_check || return 1

  local tmp
  tmp=$(mktemp)
  for p in "${sp_resolved[@]}"; do
    if [ ! -f "$p" ]; then
      echo "  ⚠️  Skipping missing item: $p"
      continue
    fi
    echo "===== ${p##*/} =====" >> "$tmp"
    cat -- "$p" >> "$tmp"
    echo >> "$tmp"
  done

  if [ ! -s "$tmp" ]; then
    echo "❌ No valid files found in selection"
    rm -f "$tmp"
    return 1
  fi

  echo "🔐 Encrypting merged text locally (key never leaves this machine)..."
  local key
  key=$(node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+\$/,''))")
  if [ -z "$key" ]; then
    echo "❌ Local encryption failed"
    rm -f "$tmp"
    return 1
  fi

  local enc_tmp; enc_tmp=$(mktemp)
  _crypto_encrypt_stdin "$key" < "$tmp" > "$enc_tmp"
  rm -f "$tmp"

  echo "☁️  Uploading ${#sp_resolved[@]} encrypted file(s) merged into a single blob..."
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

  read -p "🔗 Paste link to import (include the #k=... part): " link
  [ -z "$link" ] && echo "🚫 Cancelled" && return

  if [[ "$link" != http*://* ]]; then
    link="$WORKER_URL/$link"
  fi

  local key=""
  if [[ "$link" == *"#k="* ]]; then
    key="${link#*#k=}"
    link="${link%%#*}"
  fi
  link="${link%/}"

  if [ -z "$key" ]; then
    read -p "🔑 No key found in the pasted link — paste the decryption key separately: " key
    if [ -z "$key" ]; then
      echo "❌ No decryption key — cannot proceed."
      return 1
    fi
  fi

  local tmp_body raw_status
  tmp_body=$(mktemp)
  raw_status=$(curl -s -o "$tmp_body" -w "%{http_code}" "$link/raw")

  if [ "$raw_status" == "200" ]; then
    echo "📄 Text link detected. Decrypting locally..."
    local plain_tmp; plain_tmp=$(mktemp)
    if ! _crypto_decrypt_stdin "$key" < "$tmp_body" > "$plain_tmp" 2>/dev/null; then
      echo "❌ Decryption failed — wrong key, or the link was already used/corrupted."
      rm -f "$tmp_body" "$plain_tmp"
      return 1
    fi
    rm -f "$tmp_body"

    if [ -t 1 ] && [ -t 0 ]; then
      read -p "💾 Save as filename in $path (blank = print to terminal): " fname
    else
      fname=""
    fi

    if [ -n "$fname" ]; then
      mv "$plain_tmp" "$path/$fname"
      echo "✅ Imported as: $path/$fname"
    else
      cat "$plain_tmp"
      rm -f "$plain_tmp"
    fi
    return 0
  fi

  rm -f "$tmp_body"

  local manifest_status
  manifest_status=$(curl -s -o /dev/null -w "%{http_code}" "$link/manifest")
  if [ "$manifest_status" != "200" ]; then
    echo "❌ Link expired, invalid, or already nuked."
    return 1
  fi

  echo "📦 Multi-file link detected."
  local dest="$path"
  if [ -t 0 ]; then
    read -p "📂 Extract into which folder? (blank = current dir: $path): " dest_in
    [ -n "$dest_in" ] && dest="$dest_in"
  fi
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
