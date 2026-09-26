source "bashbasicsbyvk_staging_helpers.sh"

# Stage / apply logic lives in _sp_stage_buffer / _sp_apply_buffer (helpers.sh).
route_shortcut_stage() { _sp_stage_buffer sc "$1" "$2"; }
route_shortcut_apply() { _sp_apply_buffer  sc "$1" "$2"; }
