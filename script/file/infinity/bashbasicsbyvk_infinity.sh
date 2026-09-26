infinity_stones_menu() {
  printf "\n💎 Infinity Stones\n1) Extract Tables and Links from Web\n2) JavaScript Audit\n3) Python Audit\n4) Git Push\n5) Generate SQL\n6) LocalHost\nq) Exit\n"

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