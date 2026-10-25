_st_cf_build() {
  _st_reset
  local _f
  for _f in "${_ARC_FORMATS[@]}"; do
    _st_eq "$compress_format" "$_f"; _st_add r "${_ARC_LABEL[$_f]}" "$_o" "always" "$_f"
  done
  _st_eq "$compress_format" ask;   _st_add r "Ask each time"   "$_o" "(default)"     ask
}
_st_cf_act() { compress_format="${_st_tag[$1]}"; save_settings; }
compress_format_settings() { _st_run "Compress format  (z-)" _st_cf_build _st_cf_act; }
