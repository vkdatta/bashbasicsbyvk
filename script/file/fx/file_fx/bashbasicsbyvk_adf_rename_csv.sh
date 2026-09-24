#!/usr/bin/env bash
# bashbasicsbyvk_adf_rename_csv.sh
# adf-route='file_fx/rename/rename.select.items.csv'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — rename.select.items.csv
#  CSV batch rename: col1=old_name, col2=new_name, result written to col3.
#  Identical to the old "Multi Mutation (CSV)" rename path.
# ════════════════════════════════════════════════════════════════════════════

_fx_adf_rename_csv() {
  _rename_multi_mutation
}
_fx_adf_register "rename.select.items.csv" "_fx_adf_rename_csv" "rename/rename.select.items.csv"
