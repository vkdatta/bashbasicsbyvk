_st_cf_build() {
  _st_reset
  _st_head="Used by the z- command"
  _st_eq "$compress_format" zip;   _st_add r ".zip"            "$_o" "always"       zip
  _st_eq "$compress_format" targz; _st_add r ".tar.gz"         "$_o" "always"       targz
  _st_eq "$compress_format" ask;   _st_add r "Ask each time"   "$_o" "(default)"     ask
}
_st_cf_act() { compress_format="${_st_tag[$1]}"; save_settings; }
compress_format_settings() { _st_run "Compress format  (z-)" _st_cf_build _st_cf_act; }
