# Apply logic lives in _sp_apply_buffer (helpers.sh);  <names-csv> (3rd argument) = only those named sets.
staging_move_apply() { _sp_apply_buffer  mv "$1" "$2" "${3:-}"; }
