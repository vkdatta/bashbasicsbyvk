#!/usr/bin/env bash
# bashbasicsbyvk_svc_core.sh — shared engine of the fileapi services built on top of up-:
#     Backup (copies taken before a delete) · Saved Surf (save-) · Snapshots
#
#   _svc_upload  <service> <alias> <path>...     pack (tar.gz) → price check → encrypt → upload → commit
#   _svc_restore <service> <id> <label>          download + decrypt + unpack safely into the current folder
#
# Same pipeline, same encryption and the same server rules as up-; the differences are only
#   • the item is filed under a service (X-Service), so it shows in its own menu and never in Links
#   • backup / saved / snapshot : client-side encryption (CSE), the same key chain as ux-:   dinons → FEK → K
#     (a backup used to keep K in ~/.bashbasicsbyvk/backup_keys on one computer; now it works from every device like the others;
#      backups made before this change are still restored with that local key)
#       K     fresh random key per item; encrypts the data
#       kdk   K wrapped with your FEK on this computer — the ONLY thing about K the server keeps
#     The server holds no key it can open (no Worker-secret wrapping), so the operator — even with the database, the
#     bucket and every Worker secret — cannot read an item. No link is ever shown; the data and kdk are served to the
#     owner only. To open an item on another device you need e-mail + diseps + API key AND the dinons.
#     Names are CSE too: sent as "e1.<ciphertext>" under the per-user label key (see _bb_alias_prepare).
# Sourced by: o (via _3bvk_import_services.sh) and the stand-alone bashbasicsbyvk_delete command.

source "bashbasicsbyvk_staging_fileapi.sh"     # also pulls in _3bvk_fileapi_lib.sh
source "bashbasicsbyvk_staging_ux.sh"          # key chain helpers (_ux_self_fek, _ux_core dk-wrap / dk-unwrap)

_SVC_QUIET=0            # 1 = background work: no price prompt, no progress chatter
_SVC_SNAP_TGT=""        # snapshot only: id of the watched path
_SVC_SNAP_SIG=""        # snapshot only: change signature of what was packed
_SVC_INC_HIDDEN=true    # false = leave out hidden files inside the chosen folders (save- follows Settings → Upload hidden)
_SVC_ID=""; _SVC_KEY=""; _SVC_EXPIRES=""; _SVC_BYTES=""; _SVC_DEDUCTED=""; _SVC_BALANCE=""

_svc_say() { [ "$_SVC_QUIET" = 1 ] || echo "$@"; }

# _svc_upload <service> <alias|""> <path>...      returns 0 ok · 1 failed · 2 stopped at the price prompt · 3 not enough credits (quiet mode)
# Everything under the given paths is included, hidden files too (a backup or snapshot must be complete).
_svc_upload() {
  local svc="$1" alias="$2"; shift 2
  local -a paths=("$@")
  _SVC_ID=""; _SVC_KEY=""; _SVC_EXPIRES=""; _SVC_BYTES=""; _SVC_DEDUCTED=""; _SVC_BALANCE=""
  _crypto_check || return 1
  if ! command -v tar &>/dev/null || ! command -v gzip &>/dev/null; then
    echo "❌ 'tar' and 'gzip' are required (pkg install tar gzip)."; return 1
  fi
  _bb_get_credentials || return 1
  # backup / saved / snapshot are client-side encrypted: open the FEK (dinons) BEFORE packing, so a missing key chain fails fast
  if [ "$svc" = backup ] || [ "$svc" = saved ] || [ "$svc" = snapshot ]; then
    if [ "$_SVC_QUIET" = 1 ]; then _ux_self_fek 2>/dev/null; else _ux_self_fek; fi \
      || { [ "$_SVC_QUIET" = 1 ] || echo "❌ Nothing was uploaded: backups, save- and snap- encrypt with your FEK, which needs the dinons on this computer." >&2; return 1; }
  fi
  local -a gz=(gzip)
  command -v pigz &>/dev/null && gz=(pigz)
  local lvl="${FILEAPI_BASHBASICS_GZIP_LEVEL:-6}"
  [[ "$lvl" =~ ^[1-9]$ ]] || lvl=6

  local stage tmpdir rcfile errfile
  stage=$(mktemp -d) && tmpdir=$(mktemp -d) && rcfile=$(mktemp) && errfile=$(mktemp) \
    || { echo "❌ Could not create temp files."; return 1; }
  _svc_cleanup() { rm -rf "$stage" "$tmpdir" "$rcfile" "$errfile"; }

  local -a rel_items=()
  local p bn cand n
  for p in "${paths[@]}"; do
    p="${p%/}"; [[ "$p" == /* ]] || p="$PWD/$p"
    if [ ! -f "$p" ] && [ ! -d "$p" ]; then _svc_say "  ⚠️  Skipping missing item: $p" >&2; continue; fi
    bn="${p##*/}"; cand="$bn"; n=1
    while [ -e "$stage/$cand" ] || [ -L "$stage/$cand" ]; do n=$((n + 1)); cand="${bn}_$n"; done
    ln -s "$p" "$stage/$cand"
    rel_items+=("./$cand")
  done
  if [ ${#rel_items[@]} -eq 0 ]; then echo "❌ Nothing to pack."; _svc_cleanup; return 1; fi

  local arcname="files.tar.gz"
  [ ${#rel_items[@]} -eq 1 ] && arcname="${rel_items[0]#./}.tar.gz"
  arcname=$(printf '%s' "$arcname" | LC_ALL=C tr -c 'A-Za-z0-9._ -' '_' | cut -c1-120)

  _svc_say "📦 Packing tar.gz → 🔐 encrypting (streamed: the unencrypted archive never touches the disk)"
  local packout r
  packout=$(
    cd "$stage" || exit 1
    for r in "${rel_items[@]}"; do
      if [ "${_SVC_INC_HIDDEN:-true}" = true ]; then
        find -H "$r" \( -type f -o -type d \) -print0
      else   # leave out hidden files/folders INSIDE the chosen items (the items themselves stay)
        find -H "$r" -maxdepth 0 \( -type f -o -type d \) -print0
        find -H "$r" -mindepth 1 \( -name '.*' -prune \) -o \( -type f -o -type d \) -print0
      fi
    done 2>> "$errfile" \
      | { tar --null --no-recursion -h -T - -cf - 2>> "$errfile"; echo $? > "$rcfile"; } \
      | "${gz[@]}" "-$lvl" -c \
      | _crypto_stream_pack "$tmpdir" "$arcname"
  )
  local key total_size nblobs tar_rc
  key=$(printf '%s' "$packout" | sed -n '1p'); total_size=$(printf '%s' "$packout" | sed -n '2p'); nblobs=$(printf '%s' "$packout" | sed -n '3p')
  tar_rc=$(cat "$rcfile" 2>/dev/null)
  if [[ ! "$key" =~ ^[A-Za-z0-9_-]{43}$ ]] || [[ ! "$total_size" =~ ^[0-9]+$ ]] || [[ ! "$nblobs" =~ ^[0-9]+$ ]]; then
    echo "❌ Packing/encryption failed"; [ -s "$errfile" ] && head -n 3 "$errfile" | sed 's/^/   /'
    _svc_cleanup; return 1
  fi
  if [ -z "$tar_rc" ] || [ "$tar_rc" -ge 2 ]; then
    echo "❌ tar failed (exit ${tar_rc:-?}) — nothing was uploaded."; [ -s "$errfile" ] && head -n 3 "$errfile" | sed 's/^/   /'
    _svc_cleanup; return 1
  fi
  if [ "$tar_rc" -eq 1 ]; then
    _svc_say "⚠️  Some files changed or were unreadable while packing (they may be missing/partial):"
    [ "$_SVC_QUIET" = 1 ] || head -n 3 "$errfile" | sed 's/^/   /'
  fi
  _svc_say "   $((total_size/1024/1024)) MB after tar.gz + encryption, in $nblobs blob(s)."
  if [ "$total_size" -gt "$_SP_HARD_LIMIT_BYTES" ]; then
    echo "❌ Packed size is $((total_size/1024/1024/1024))GB — over the absolute ceiling."; _svc_cleanup; return 1
  fi

  # ---- price check ----
  local what
  case "$svc" in backup) what="This backup" ;; saved) what="This save" ;; snapshot) what="This snapshot" ;; *) what="This upload" ;; esac
  _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""
  if [ "$_SVC_QUIET" = 1 ]; then
    _bb_credit_check_quiet "$total_size" "$(_bb_svc_ttl "$svc")"
    if [ $? -eq 1 ]; then _svc_cleanup; return 3; fi
    [ "$total_size" -gt "$_SP_SOFT_UPLOAD_BYTES" ] && _BB_OVERSIZE_OK=1
  else
    if ! _bb_credit_gate "$total_size" "$what" "$svc"; then _svc_cleanup; _BB_TTL_OVERRIDE=""; return 2; fi
  fi

  _BB_SVC="$svc"; _BB_LINK_ALIAS="$alias"
  local rc=1 init_out id token
  init_out=$(_bb_upload_init "$total_size") && rc=0
  if [ $rc -ne 0 ]; then _svc_cleanup; _BB_SVC=""; _BB_LINK_ALIAS=""; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1; fi
  id=$(printf '%s' "$init_out" | sed -n '1p'); token=$(printf '%s' "$init_out" | sed -n '2p')
  if [ -z "$id" ] || [ -z "$token" ]; then echo "❌ Upload init failed (no id returned)"; _svc_cleanup; _BB_SVC=""; _BB_LINK_ALIAS=""; return 1; fi

  local upres
  upres=$(_bb_upload_blobs "$id" "$tmpdir" "$nblobs" "$token")
  if [ "$upres" != "OK" ]; then
    _svc_cleanup; _BB_SVC=""; _BB_LINK_ALIAS=""; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""
    echo "❌ One or more parts failed to upload. Nothing was finalized; partial objects are removed automatically within a few hours."
    return 1
  fi

  # K → kdk (wrapped with the FEK, here). The server is only ever given kdk.
  local kdk=""
  if [ "$svc" = backup ] || [ "$svc" = saved ] || [ "$svc" = snapshot ]; then
    kdk=$(BB_FEK="$_UX_FEK" BB_K="$key" _ux_core dk-wrap 2>/dev/null)
    if [[ ! "$kdk" =~ ^[A-Za-z0-9_-]{60,200}$ ]]; then
      echo "❌ Could not wrap the item key — nothing was finalized."; _svc_cleanup; _BB_SVC=""; _BB_LINK_ALIAS=""; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""; return 1
    fi
  fi
  _BB_COMMIT_HDRS=()
  case "$svc" in
    backup|saved) _BB_COMMIT_HDRS=("X-Vault-Kdk: $kdk") ;;
    snapshot) _BB_COMMIT_HDRS=("X-Vault-Kdk: $kdk" "X-Snap-Target: $_SVC_SNAP_TGT" "X-Snap-Sig: ${_SVC_SNAP_SIG:-0}") ;;
  esac
  local result
  result=$(_bb_upload_commit "$id" "$nblobs" "$tmpdir/manifest.enc" "$token"); rc=$?
  _BB_COMMIT_HDRS=()
  local _ttl_used; _ttl_used=$(_bb_svc_ttl "$svc")
  _svc_cleanup
  local was_svc="$_BB_SVC"; _BB_SVC=""; _BB_LINK_ALIAS=""; _BB_TTL_OVERRIDE=""; _BB_OVERSIZE_OK=""
  [ $rc -eq 0 ] || return 1

  _SVC_ID="$id"; _SVC_KEY="$key"; _SVC_BYTES="$total_size"
  _SVC_DEDUCTED=$(printf '%s' "$result" | sed -n '2p'); _SVC_BALANCE=$(printf '%s' "$result" | sed -n '3p'); _SVC_EXPIRES=$(printf '%s' "$result" | sed -n '4p')
  _SVC_TTL="$_ttl_used"
  return 0
}

# the item key K of a Backup / Saved / Snapshot item: the server returns kdk (opaque to it), this computer opens it with the FEK
_svc_vault_key() {
  local id="$1" kdk k
  _ux_self_fek || return 1
  _bb_call GET "/vault/$id/key" || return 1
  [ "$_BB_STATUS" = 404 ] && [ "$(_bb_json_get "$_BB_BODY" error)" = no_key ] && return 3   # made before backups were CSE
  [ "$_BB_STATUS" = 200 ] || { echo "❌ $(_bb_fail_reason "$_BB_BODY" "$_BB_STATUS")" >&2; return 1; }
  kdk=$(_bb_json_get "$_BB_BODY" kdk)
  [[ "$kdk" =~ ^[A-Za-z0-9_-]{60,200}$ ]] || { echo "❌ The server returned no usable key." >&2; return 1; }
  k=$(printf '%s' "$kdk" | BB_FEK="$_UX_FEK" _ux_core dk-unwrap) && [[ "$k" =~ $_BB_KEY_RE ]] \
    || { echo "❌ This item's key failed its integrity check with your key (wrong dinons, or it was made with a different key)." >&2; return 1; }
  printf '%s' "$k"
}

# _svc_restore <backup|saved|snapshot> <id> <label> [dest-folder]   — never overwrites: name clashes become "name (1)"
_svc_restore() {
  local svc="$1" id="$2" label="$3" dest="${4:-${path:-$PWD}}" key link auth=0
  _crypto_check || return 1
  _bb_get_credentials || return 1
  case "$svc" in
    backup|saved|snapshot)
      key=$(_svc_vault_key "$id"); local krc=$?
      if [ "$krc" = 3 ] && [ "$svc" = backup ]; then
        # an older backup: its key was only ever kept on the computer that made it
        key=$( _BB_KEY_FILE="${HOME}/.bashbasicsbyvk/backup_keys"; _bb_key_get "$id" ) || {
          echo "❌ That backup was made by an older version: its key exists only on the computer that made it (not this one, or the file was lost)."; return 1; }
      elif [ "$krc" != 0 ]; then return 1
      fi
      link="$WORKER_URL/vault/$id"; auth=1 ;;
    *) echo "❌ Unknown service."; return 1 ;;
  esac
  echo "📥 Restoring '$label' into $dest …"
  mkdir -p "$dest" 2>/dev/null
  local arc; arc=$(mktemp "$dest/.bbvk_dl.XXXXXX") || { echo "❌ Cannot write to $dest"; return 1; }
  local res
  res=$(BB_FETCH_AUTH=$auth BB_EMAIL="$FILEAPI_BASHBASICS_EMAIL" BB_DISEPS="$FILEAPI_BASHBASICS_DISEPS" BB_APIKEY="$FILEAPI_BASHBASICS_KEY" \
        _crypto_fetch_archive "$link" "$key" "$arc")
  case "${res%%$'\t'*}" in
    OK) ;;
    EXPIRED) echo "❌ It expired or was nuked."; rm -f "$arc"; return 1 ;;
    BADKEY)  echo "❌ Decryption failed — wrong key or tampered data."; rm -f "$arc"; return 1 ;;
    *)       echo "❌ Download failed — some chunks could not be fetched or failed their integrity check. Nothing was unpacked."; rm -f "$arc"; return 1 ;;
  esac
  _unpack_targz_safe "$arc" "$dest"; local rc=$?
  rm -f "$arc"
  return $rc
}
