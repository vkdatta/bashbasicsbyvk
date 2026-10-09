#!/usr/bin/env bash
# bashbasicsbyvk_adf_import_link.sh
# adf-staging='file_fx/import/import.from.link'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — import.from.link   (same as do-)
#  Paste an upload link (with its #k=… key) and import it into the current path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_import_link() { handle_do_import; }
_fx_adf_register "import.from.link" "_fx_adf_import_link" "file_fx/import/import.from.link"
