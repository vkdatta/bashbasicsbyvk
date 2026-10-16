#!/usr/bin/env bash
# bashbasicsbyvk_saved.sh — Service 3: save-   (like up-, but no link is ever shown)
#
#   save-<items> [as <name>]       e.g.   save-1-3     save-2 as tax papers
#
# The files are packed and encrypted on this computer exactly like up-. The difference: you never get a link, and the key
# chain is client-side (CSE) like ux-:  dinons → FEK → K.  K is wrapped with your FEK here; the server keeps only that
# wrapped key (kdk) and has nothing that opens it, so neither a copy of the database/bucket nor the operator can read the data:
#   • open it from any device that has your e-mail + diseps + API key AND your dinons  →  Home → Saved Surf (sv)
#   • the data and kdk are only ever served to their owner (no public URL exists for it); kdk is destroyed when it expires
# Named   DDMMYYYY HHMM NAME   (or  DDMMYYYY HHMM  without a name). Rename, extend / shorten, restore, nuke: Saved Surf.
# Settings → File API → Saved → Default nuke time (30 days).

source "bashbasicsbyvk_svc_core.sh"

handle_save_upload() {
  local raw="$1"
  _bb_split_alias "${raw#save-}" || return 1
  local itemlist="$_BB_ITEMLIST" nm="$_BB_LINK_ALIAS" alias rc
  _BB_LINK_ALIAS=""
  _sp_guard_and_resolve "$itemlist" "save-" || return 1
  if ! alias=$(_bb_svc_alias "$nm"); then
    echo "⚠️  A name may use letters, digits, spaces and . _ @ + -  (up to ~34 characters after the date)."; return 1
  fi
  # hidden files inside chosen folders: same Settings → Upload hidden rule as up-
  _hidden_decide "${upload_hidden_mode:-follow}" "the save" "${sp_resolved[@]}" || return 1
  _SVC_INC_HIDDEN="$_hid_inc"
  _svc_upload saved "$alias" "${sp_resolved[@]}"; rc=$?
  _SVC_INC_HIDDEN=true
  case $rc in
    0)
      echo "💾 Saved as '$alias' — no link exists. Open it from any device: Home → Saved Surf (sv)."
      [ -n "$_SVC_DEDUCTED" ] && echo "💳 Credits deducted: $_SVC_DEDUCTED   |   Balance: $_SVC_BALANCE"
      echo "🕐 Nuke time: $(_bb_fmt_duration "$_SVC_TTL")  →  gone at $(_bb_fmt_when "$_SVC_EXPIRES")   (change or extend it in Saved Surf)"
      return 0 ;;
    2) return 1 ;;
    *) return 1 ;;
  esac
}
