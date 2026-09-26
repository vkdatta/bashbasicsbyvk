# ---------------------------------------------------------------------------
# compress_format_settings
# Lets the user choose the default compression format for z-.
# ---------------------------------------------------------------------------
compress_format_settings() {
  echo ""
  echo "Compress format (used by z-):"
  echo "1) zip    — always create .zip"
  echo "2) tar.gz — always create .tar.gz"
  echo "3) ask    — prompt each time (default)"
  read -r -p "Choice [1-3]: " cf_choice
  cf_choice="${cf_choice%$'\r'}"
  case "$cf_choice" in
    1) compress_format="zip" ;;
    2) compress_format="targz" ;;
    3) compress_format="ask" ;;
    *) echo "Invalid choice — no changes made." ; return ;;
  esac
  save_settings
  echo "✅ Compress format set to: $compress_format"
}
