# Settings → Hidden files   (the [x] lives here, not on the main Settings screen)
_st_hf_build() {
  _st_reset
  [ "$show_hidden_files" = true ] && _st_head="Hidden files are shown" || _st_head="Hidden files are hidden"
  _st_eq "$show_hidden_files" true
  _st_add t "Show hidden files" "$_o" "" show
}
_st_hf_act() {
  if [ "$show_hidden_files" = true ]; then show_hidden_files=false; else show_hidden_files=true; fi
  save_settings
}
hidden_file_settings() { _st_run "Hidden files" _st_hf_build _st_hf_act; }
