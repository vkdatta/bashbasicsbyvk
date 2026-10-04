# Hidden files is a plain [x] toggle on the main Settings screen.
# This keeps the old function name working for anything that still calls it.
hidden_file_settings() {
  if [ "$show_hidden_files" = true ]; then show_hidden_files=false; else show_hidden_files=true; fi
  save_settings
}
