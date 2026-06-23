open_help() {
  local HELP_FILE

  HELP_FILE="$(find "${PREFIX:-/usr}" -type f -name "bashbasicsbyvk_help.xlsx" 2>/dev/null | head -n 1)"

  if [ -z "$HELP_FILE" ] || [ ! -f "$HELP_FILE" ]; then
    echo "❌ bashbasicsbyvk_help.xlsx not found"
    return 1
  fi

  echo "📖 Opening command index: $HELP_FILE"

  if command -v termux-open >/dev/null 2>&1; then
    termux-open "$HELP_FILE"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$HELP_FILE" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then
    open "$HELP_FILE"
  else
    echo "⚠️ No opener found (termux-open / xdg-open / open)."
    echo "File is at: $HELP_FILE"
    return 1
  fi
}