source "bashbasicsbyvk_staging_helpers.sh"

# Stage / apply logic lives in _sp_stage_buffer / _sp_apply_buffer (helpers.sh).
staging_copy_stage() { _sp_stage_buffer cp "$1" "$2"; }
staging_copy_apply() { _sp_apply_buffer  cp "$1" "$2"; }
