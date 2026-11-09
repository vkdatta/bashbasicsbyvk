# Apply logic lives in _sp_apply_buffer (helpers.sh);  <names-csv> (3rd argument) = only those named sets.
staging_copy_apply() { _sp_apply_buffer  cp "$1" "$2" "${3:-}"; }
