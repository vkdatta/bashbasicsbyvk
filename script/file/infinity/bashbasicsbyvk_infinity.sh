# The risk warning is printed FIRST (plain scroll-back text). The menu itself —
# title, options, key hints — is drawn by the shared menu chrome (_mc_*), so it is
# the last thing above the prompt and the viewport can take it over like any
# other menu (a warning printed after the options hid the menu from it).
_infinity_warning() {
  printf "\n"
  printf "⚠️  DEVELOPMENT / EXTREME-RISK WARNING\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  printf "All Infinity Stones features below are currently in DEVELOPMENT STAGE and\n"
  printf "are subject to extreme stress, failure, data-loss, corruption, and incorrect\n"
  printf "result cases. HIGHLY ADVISED: DO NOT USE THESE FUNCTIONS.\n"
  printf "\n"
  printf "These functions may break, modify, overwrite, corrupt, or otherwise affect\n"
  printf "existing files/data, produce incorrect or incomplete results, or perform\n"
  printf "adverse actions such as force-pushes, overwrites, or other destructive changes.\n"
  printf "\n"
  printf "The developer is NOT responsible for any wrong data generated, data loss,\n"
  printf "file damage, repository changes, production impact, or other adverse\n"
  printf "consequences resulting from use of these functions.\n"
  printf "\n"
  printf "DO NOT USE THE FUNCTIONS BELOW, EVEN AT YOUR OWN RISK, until they have been\n"
  printf "fully tested and declared production-ready.\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
}

infinity_stones_menu() {
  _infinity_warning

  while true; do
    _mc_menu "💎 Infinity Stones" -- \
      "Extract Tables and Links from Web" "JavaScript Audit" "Python Audit" \
      "Git Push" "Generate SQL" "LocalHost" -- @infinity

    read -e -p "Select: " is_choice

    case "$is_choice" in
    u|U|"") return ;;
    q|Q) _bvk_quit; return 1 ;;
      1) python "$SCRIPT_DIR/bashbasicsbyvk_xtract" "$path" ;;
      2) python "$SCRIPT_DIR/bashbasicsbyvk_js_audit" "$path" ;;
      3) bash "$SCRIPT_DIR/bashbasicsbyvk_py_audit" "$path" ;;
      4) bash "$SCRIPT_DIR/bashbasicsbyvk_gitpush" "$path" ;;
      5) python "$SCRIPT_DIR/bashbasicsbyvk_gen_sql" "$path" ;;
      6) bash "$SCRIPT_DIR/bashbasicsbyvk_localhost" "$path" ;;
      *) _bvk_invalid; continue ;;      # redraw THIS menu, not the parent
    esac
    return
  done
}
