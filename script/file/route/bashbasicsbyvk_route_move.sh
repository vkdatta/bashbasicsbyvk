source "bashbasicsbyvk_route_helpers.sh"

# Stage / apply logic lives in _sp_stage_buffer / _sp_apply_buffer (helpers.sh).
route_move_stage() { _sp_stage_buffer mv "$1" "$2"; }
route_move_apply() { _sp_apply_buffer  mv "$1" "$2"; }
