open_help() {
  local SCRIPT_DIR HELP_FILE

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  HELP_FILE="$SCRIPT_DIR/bashbasicsbyvk_help.xlsx"

  if [ ! -f "$HELP_FILE" ]; then
    echo "❌ bashbasicsbyvk_help.xlsx not found at: $HELP_FILE"
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