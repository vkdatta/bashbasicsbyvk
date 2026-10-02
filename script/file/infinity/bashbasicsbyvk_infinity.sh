infinity_stones_menu() {
  printf "\n💎 Infinity Stones\n1) Extract Tables and Links from Web\n2) JavaScript Audit\n3) Python Audit\n4) Git Push\n5) Generate SQL\n6) LocalHost\nq) Exit\n"

  printf "\n"
  printf "⚠️  DEVELOPMENT / EXTREME-RISK WARNING\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
  printf "All Infinity Stones features above are currently in DEVELOPMENT STAGE and\n"
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
  printf "DO NOT USE THE ABOVE FUNCTIONS, EVEN AT YOUR OWN RISK, until they have been\n"
  printf "fully tested and declared production-ready.\n"
  printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

  read -p "Choice: " is_choice

  case "$is_choice" in
    1) python "$SCRIPT_DIR/_3bvk_xtract_core" "$path" ;;
    2) python "$SCRIPT_DIR/_3bvk_js_audit_core" "$path" ;;
    3) bash "$SCRIPT_DIR/_3bvk_py_audit_core" "$path" ;;
    4) bash "$SCRIPT_DIR/_3bvk_gitpush_core" "$path" ;;
    5) python "$SCRIPT_DIR/_3bvk_gen_sql_core" "$path" ;;
    6) bash "$SCRIPT_DIR/_3bvk_localhost_core" "$path" ;;
    q|"") return ;;
    *) printf '⚠️  Invalid choice\n'; return ;;
  esac
}