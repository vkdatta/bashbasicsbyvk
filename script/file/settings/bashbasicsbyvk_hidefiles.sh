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


# ════════════════════════════════════════════════════════════════════════════
#  Hidden files in up- (upload) and z- (zip)
#     follow  = use the "Hidden files" setting above (default)
#     always  = always include hidden files inside the chosen folders
#     never   = never include them
#     ask     = ask every time (only when a chosen folder really has hidden files)
#  Items you pick by hand are always sent; the setting only decides about the
#  hidden files and folders found INSIDE the folders you picked.
# ════════════════════════════════════════════════════════════════════════════
_hidden_mode_label() {
  case "$1" in
    always) echo "always include" ;;
    never)  echo "never include" ;;
    ask)    echo "ask every time" ;;
    *)      echo "follow hidden files" ;;
  esac
}

# _st_hm_build VAR  → radio rows for the mode stored in variable VAR
_st_hm_build() {
  local cur="${!_st_hm_var}"
  _st_reset
  _st_eq "$cur" follow; _st_add r "Follow hidden-files setting" "$_o" "(default)" follow
  _st_eq "$cur" always; _st_add r "Always include (yes)"       "$_o" ""          always
  _st_eq "$cur" never;  _st_add r "Never include (no)"         "$_o" ""          never
  _st_eq "$cur" ask;    _st_add r "Ask every time"             "$_o" ""          ask
}
_st_hm_act() { printf -v "$_st_hm_var" '%s' "${_st_tag[$1]}"; save_settings; }

_st_hm_var=""
upload_hidden_settings() { _st_hm_var=upload_hidden_mode; _st_run "Upload hidden files  (up-)" _st_hm_build _st_hm_act; }
zip_hidden_settings()    { _st_hm_var=zip_hidden_mode;    _st_run "Zip hidden files  (z-)"      _st_hm_build _st_hm_act; }

# _hidden_any PATH...  → 0 when a chosen folder contains at least one hidden entry
_hidden_any() {
  local p
  for p in "$@"; do
    [ -d "$p" ] || continue
    [ -n "$(find -H "$p" -mindepth 1 -name '.*' -print -quit 2>/dev/null)" ] && return 0
  done
  return 1
}

# _hidden_decide MODE LABEL PATH...
#   sets _hid_inc=true|false ; returns 1 when the user cancels (u) — q quits.
_hidden_decide() {
  local mode="$1" what="$2" a; shift 2
  _hid_inc=true
  case "$mode" in
    always) return 0 ;;
    never)  _hid_inc=false; return 0 ;;
    ask)
      _hid_inc=false
      _hidden_any "$@" || return 0            # nothing hidden in there: no need to ask
      read -r -p "👁️  Include hidden files in $what? [y/N, u = cancel]: " a
      a="${a%$'\r'}"
      case "${a,,}" in
        y|yes) _hid_inc=true ;;
        u)     echo "🚫 Cancelled."; return 1 ;;
        q)     _bvk_quit ;;
      esac
      return 0 ;;
    *) [ "${show_hidden_files:-false}" = true ] && _hid_inc=true || _hid_inc=false ;;
  esac
  return 0
}

# _hid_find0 INCLUDE TYPEFILTER ITEM...   (run from the folder the ITEMs are relative to)
#   NUL-separated list of every ITEM and everything inside it. With INCLUDE=false
#   hidden files/folders INSIDE an item are left out (the item itself is kept).
#   TYPEFILTER=1 → regular files and folders only.
_hid_find0() {
  local inc="$1" tf="$2" r; shift 2
  local -a typ=()
  [ "$tf" = 1 ] && typ=( \( -type f -o -type d \) )
  for r in "$@"; do
    if [ "$inc" = true ]; then
      find -H "$r" "${typ[@]}" -print0
    else
      find -H "$r" -maxdepth 0 "${typ[@]}" -print0
      find -H "$r" -mindepth 1 \( -name '.*' -prune \) -o "${typ[@]}" -print0
    fi
  done
}
