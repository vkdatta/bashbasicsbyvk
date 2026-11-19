# Apply logic lives in _sp_apply_buffer (helpers.sh);  <names-csv> (3rd argument) = only those named sets.
# The stage command is  k-  (k-1,3 · k-a as set1);  s- is the select buffer.
staging_shortcut_apply() { _sp_apply_buffer  sc "$1" "$2" "${3:-}"; }
