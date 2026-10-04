_st_im_build() {
  _st_reset
  _st_head="Folders with more than $index_mode_threshold items use big-folder mode"
  _st_add a "Change limit"      0 "$index_mode_threshold"          set
  _st_add a "Reset to default"  0 "$DEFAULT_INDEX_MODE_THRESHOLD"  reset
}
_st_im_act() {
  case "${_st_tag[$1]}" in
    set)
      if _st_ask "New limit (number of items)" "$index_mode_threshold"; then
        if [[ "$_st_in" =~ ^[0-9]+$ ]] && [ "$_st_in" -gt 0 ]; then
          index_mode_threshold=$_st_in; save_settings
        else
          _st_note "⚠️  Not a valid number"
        fi
      fi ;;
    reset) index_mode_threshold=$DEFAULT_INDEX_MODE_THRESHOLD; save_settings ;;
  esac
}
index_mode_threshold_settings() { _st_run "Big-folder limit" _st_im_build _st_im_act; }
