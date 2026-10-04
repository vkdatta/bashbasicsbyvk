# Hidden files: a sub menu like every other setting, with two choices.
_st_hf_build() {
  _st_reset
  _st_eq "$show_hidden_files" true
  (( _o )) && _o=0 || _o=1
  _st_add r "Hide hidden files" "$_o" "" hide
  _st_eq "$show_hidden_files" true
  _st_add r "Show hidden files" "$_o" "" show
}
_st_hf_act() {
  case "${_st_tag[$1]}" in
    hide) show_hidden_files=false ;;
    show) show_hidden_files=true ;;
  esac
  save_settings
}
hidden_file_settings() { _st_run "Hidden files" _st_hf_build _st_hf_act; }
