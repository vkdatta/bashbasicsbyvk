_get_rc_file() {
    local current_shell
    current_shell="$(basename "${SHELL:-bash}")"
    case "$current_shell" in
        zsh)  echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.bashrc" ;;
    esac
}

_MARKER_BEGIN="# bashbasicsbyvk colors BEGIN"
_MARKER_END="# bashbasicsbyvk colors END"

_normalize_hex() {
    echo "${1#\#}" | tr '[:lower:]' '[:upper:]'
}

_valid_hex() {
    local hex
    hex="$(_normalize_hex "$1")"
    [[ "$hex" =~ ^[0-9A-F]{6}$ ]]
}

_hex_to_rgb() {
    local hex
    hex="$(_normalize_hex "$1")"
    printf "%d %d %d" \
        "$((16#${hex:0:2}))" \
        "$((16#${hex:2:2}))" \
        "$((16#${hex:4:2}))"
}

apply_colors() {
    if [ -n "$terminal_bg_color" ] && _valid_hex "$terminal_bg_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_bg_color")"
        printf "\e]11;#%s\a" "$hex"
    fi
    if [ -n "$terminal_text_color" ] && _valid_hex "$terminal_text_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_text_color")"
        printf "\e]10;#%s\a" "$hex"
    fi
    if [ -n "$terminal_bg_color" ] || [ -n "$terminal_text_color" ]; then
        printf "\e[2J\e[H"
    fi
}

_apply_bg_color() {
    local hex
    hex="$(_normalize_hex "$1")"
    terminal_bg_color="$hex"
    save_settings
    _persist_colors_to_rc
    apply_colors
}

_apply_text_color() {
    local hex
    hex="$(_normalize_hex "$1")"
    terminal_text_color="$hex"
    save_settings
    _persist_colors_to_rc
    apply_colors
}

_persist_colors_to_rc() {
    local rc_file
    rc_file="$(_get_rc_file)"
    touch "$rc_file"

    _remove_colors_from_rc

    local block=""
    block+="$_MARKER_BEGIN\n"

    if [ -n "$terminal_bg_color" ] && _valid_hex "$terminal_bg_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_bg_color")"
        block+="printf \"\\e]11;#${hex}\\a\"\n"
    fi

    if [ -n "$terminal_text_color" ] && _valid_hex "$terminal_text_color"; then
        local hex
        hex="$(_normalize_hex "$terminal_text_color")"
        block+="printf \"\\e]10;#${hex}\\a\"\n"
    fi

    if [ -n "$terminal_bg_color" ] || [ -n "$terminal_text_color" ]; then
        block+="printf \"\\e[2J\\e[H\"\n"
    fi

    block+="$_MARKER_END"

    printf "\n%b\n" "$block" >> "$rc_file"
}

_remove_colors_from_rc() {
    local rc_file
    rc_file="$(_get_rc_file)"
    [ -f "$rc_file" ] || return

    local tmp_file="${rc_file}.bbvk_tmp"

    awk '
    /^# bashbasicsbyvk colors BEGIN$/ {skip=1}
    !skip {print}
    /^# bashbasicsbyvk colors END$/ {skip=0}
    ' "$rc_file" > "$tmp_file"

    mv "$tmp_file" "$rc_file"
}


# ── Settings screens: pick a preset, or choose Custom… and type a hex ────────
_st_bg_build() {
  _st_reset
  _st_eq "$terminal_bg_color" "$DEFAULT_TERMINAL_BG_COLOR"
  _st_add r "Black (default)" "$_o" "#$DEFAULT_TERMINAL_BG_COLOR" default
  (( _o )) && _o=0 || _o=1
  _st_add r "Custom…" "$_o" "$( (( _o )) && echo "#$terminal_bg_color" )" custom
}
_st_bg_act() {
  case "${_st_tag[$1]}" in
    default) _apply_bg_color "$DEFAULT_TERMINAL_BG_COLOR" ;;
    custom)
      builtin printf '\033[2K'
      if _st_ask "Hex color (e.g. 1e1e2e)"; then
        if _valid_hex "$_st_in"; then _apply_bg_color "$_st_in"; else _st_note "⚠️  Needs 6 hex digits"; fi
      fi ;;
  esac
}
terminal_bg_color_settings() { _st_run "Background color" _st_bg_build _st_bg_act; }

_st_fg_build() {
  _st_reset
  local n=0 c=0
  _st_eq "$terminal_text_color" "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL"; n=$_o
  _st_eq "$terminal_text_color" "$DEFAULT_TERMINAL_TEXT_COLOR_CODER";  c=$_o
  _st_add r "White (normal)" "$n" "#$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" normal
  _st_add r "Green (coder)"  "$c" "#$DEFAULT_TERMINAL_TEXT_COLOR_CODER"  coder
  local cu=0; (( n || c )) || cu=1
  _st_add r "Custom…" "$cu" "$( (( cu )) && echo "#$terminal_text_color" )" custom
}
_st_fg_act() {
  case "${_st_tag[$1]}" in
    normal) _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_NORMAL" ;;
    coder)  _apply_text_color "$DEFAULT_TERMINAL_TEXT_COLOR_CODER" ;;
    custom)
      if _st_ask "Hex color (e.g. cdd6f4)"; then
        if _valid_hex "$_st_in"; then _apply_text_color "$_st_in"; else _st_note "⚠️  Needs 6 hex digits"; fi
      fi ;;
  esac
}
terminal_text_color_settings() { _st_run "Text color" _st_fg_build _st_fg_act; }

apply_colors
