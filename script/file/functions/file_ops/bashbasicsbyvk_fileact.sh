#!/usr/bin/env bash
# bashbasicsbyvk_fileact.sh — the file menu's three destructive rows, NATIVE to the app (they used to be stand-alone programs in their own process:
# a second copy of every menu, prompt and backup rule that could drift from the app).  They are plain functions now: the app's own menus (_bvk_ask,
# _mc_steps: u = one question back), the app's own Backup service (_bk_guard, bashbasicsbyvk_staging_backup.sh) and the app's own lock gate.
#
#   _fa_delete    FILE    "Delete File"                     Confirm delete (+ the 6-digit key for a locked item) → Backup → remove
#   _fa_erase     FILE    "Erase Content"                   Confirm erase → Backup → empty the file
#   _fa_overwrite FILE    "Replace With Clipboard Content"  read the clipboard → Backup → write it
#
# Called from handle_file (bashbasicsbyvk_run.sh), always through _hf_tracked for erase / overwrite so a real change lands in Recents.
# Every one returns 0 (also when the person said no / u: the file menu comes back); nothing is changed until the backup step has answered.
#
# Needs: _bvk_ask / _mc_steps (menuchrome), _lk_delete_gate (lock), _bk_guard (Backup), _carry_forget (carry).

_fa_delete() {
  local target="$1"
  if [ -z "$target" ]; then echo "Usage: delete <filename or folder>"; return 1; fi
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then echo "File or directory not found: $target"; return 1; fi
  local -a selected_items=("$target")           # the lock gate works on selected_items (the same ONE gate as the multi-item delete)
  _lk_load
  _lk_delete_gate "Are you sure you want to delete '$target'? You may not recover this. (y/n): " || return 0
  rm -rf -- "$target" && _carry_forget "$target"
  echo "Deleted: $target"
}

# the questions share _fa_erase's locals (f ans)
_fae_confirm() {
  local rc
  _bvk_ask ans "Erase all contents of '$f'?" -d none -t "Confirm erase" -i "🧹"; rc=$?
  (( rc == 1 )) && return 1
  [ "$rc" = 0 ] && [[ "$ans" == [yY] ]] && return 0
  return 3
}
_fae_backup() {
  [ -s "$f" ] || return 0                       # nothing to lose in an empty file
  local rc
  _bk_guard erase "$f"; rc=$?
  (( rc == 0 )) && return 0
  (( rc == 6 )) && return 1                     # 6 = u at a backup question
  return 3
}
_fa_erase() {
  local f="$1" ans=""
  if [ -z "$f" ]; then echo "Usage: erase <filename>"; return 1; fi
  if [ ! -f "$f" ]; then echo "File '$f' not found."; return 1; fi
  _mc_steps _fae_confirm _fae_backup || { echo "Canceled."; return 0; }
  : > "$f"
  echo "Contents of $f erased."
}

# _fa_clip_cmd → CMD (the command that prints the clipboard); empty when this device has no clipboard tool (then the content is pasted by hand)
_fa_clip_cmd() {
  CMD=""
  [ -n "${DEVSHELL_PROJECT_ID:-}" ] && return 0
  if   command -v pbpaste >/dev/null 2>&1;            then CMD="pbpaste"
  elif command -v xclip >/dev/null 2>&1;              then CMD="xclip -selection clipboard -o"
  elif command -v xsel >/dev/null 2>&1;               then CMD="xsel --clipboard --output"
  elif command -v wl-paste >/dev/null 2>&1;           then CMD="wl-paste"
  elif command -v termux-clipboard-get >/dev/null 2>&1; then CMD="termux-clipboard-get"
  elif command -v powershell.exe >/dev/null 2>&1;     then CMD="powershell.exe -Command Get-Clipboard"
  fi
}
_fao_backup() {
  local rc
  _bk_guard overwrite "$f"; rc=$?
  (( rc == 0 )) && return 0
  (( rc == 6 )) && return 1
  return 3
}
_fa_overwrite() {
  local f="$1" CMD="" tmp line
  if [ -z "$f" ]; then echo "Usage: overwrite <filename>"; return 1; fi
  tmp=$(mktemp) || { echo "🔴  Cannot make a temporary file."; return 1; }
  _fa_clip_cmd
  if [ -n "$CMD" ]; then
    $CMD > "$tmp" 2>/dev/null
    if [ ! -s "$tmp" ]; then rm -f "$tmp"; echo "📋 The clipboard is empty — '$f' was not changed."; return 0; fi
  else
    echo "📥 Headless Environment Detected."
    echo "1. Paste your content (Ctrl+V or Long-press)."
    echo "2. On a NEW LINE, type 'DONE' and press Enter to save."
    echo "--------------------------------------------------"
    while IFS= read -r line; do     # bvk-read-ok: pasted lines are CONTENT, not answers (u / q here are text)
      [[ "$line" == "DONE" ]] && break
      printf '%s\n' "$line" >> "$tmp"
    done
  fi
  if [ -e "$f" ] && [ -s "$f" ]; then
    _mc_steps _fao_backup || { rm -f "$tmp"; echo "Canceled — the file was not changed."; return 0; }
  fi
  cat "$tmp" > "$f"; rm -f "$tmp"
  if [ -n "$CMD" ]; then echo "💫 Success: Overwrote '$f' using ${CMD%% *}."
  else echo "--------------------------------------------------"; echo "💫 Success: Clipboard content saved to '$f'."; fi
}
