#!/usr/bin/env bash
# bashbasicsbyvk_adf_cloudshell.sh
# adf-staging='cloudshell/launch.cloudshell'
# ════════════════════════════════════════════════════════════════════════════
#  ADF — cloudshell → launch.cloudshell      (the screens; the gcloud work lives in bashbasicsbyvk_cslib.sh)
#
#  Google Cloud Shell from inside the app, with any number of Google accounts ("profiles").
#
#    1. gcloud is installed on first use by the app's own installer (the `gcloud` recipe of the deps engine: official build, no root).
#    2. the screen lists the saved profiles (nothing is fetched except ONE `gcloud auth list` to show who is signed in).
#         a number   opens Cloud Shell as that profile:  gcloud config set account <e-mail>  on EVERY switch, then the session
#                    (a profile that is not signed in yet is signed in first: browser on this device, or a link)
#         c          create profiles: type e-mails (comma separated) or choose file(s) that hold them  (saved on this machine)
#         x          remove profiles (and, if you say so, sign them out of gcloud)
#         k          switch Cloud Shell OFF for a profile: the cure for a hung session
#                    (gcloud cloud-shell ssh --command='tmux kill-server || pkill -u $USER')
#         rf         reload who is signed in      u  back
#
#  Your password and tokens are never typed into, shown by or stored by the app: gcloud does the sign-in itself and keeps its own login.
#  The same login is what  fx → transfer  uses for its Cloud Shell targets (cloudshell:), so switching profile here switches it there too.
# ════════════════════════════════════════════════════════════════════════════

_CSH_UFILE=""
declare -ga _CSH_ADDED=()

# ── create (c)
_csh_add() {                     # _csh_add "a@x.com, b@y.com" → rc 0 when something was added; the added ones pile up in _CSH_ADDED
  _cs_accounts_add "$1" || return 1
  _CSH_ADDED+=("${_CS_NEW[@]}")
  return 0
}

_csh_signin() {                  # _csh_signin ACCOUNT → rc 0 when gcloud now holds a login for it
  local how=""
  _bvk_menu how -t "Sign in $1" -i "🔑" -q "How do you want to sign in?" \
    "b:Browser on this device (a link opens, then it comes back by itself)" \
    "l:Link only (open it on any device, paste the code back here)" || return 1
  _cs_login "$1" "$how" || { echo "❌ The sign-in did not finish."; return 1; }
  _cs_status_load
  _cs_is_authed "$1" || { echo "❌ gcloud holds no login for $1 (was another Google account chosen in the browser?)"; return 1; }
  echo "✅ Signed in as $1"
  return 0
}

_csh_create() {
  local how="" line again="" changed=0 a n=0 ans=""
  _CSH_ADDED=()
  _bvk_menu how -t "Create Cloud Shell profile" -i "☁️" \
    "t:Type Google account e-mails (comma separated)" "f:Choose file(s) with e-mails (comma separated)" || return 1
  case "$how" in
    t) _xui_ask "E-mails, comma separated (e.g. me@gmail.com,work@gmail.com)" || return 1
       _csh_add "$_XUI_IN" && changed=1 ;;
    f) while :; do
         _file_picker "csv txt" _CSH_UFILE || break
         [ -n "$_CSH_UFILE" ] || break
         line="$(cat -- "$_CSH_UFILE" 2>/dev/null)"
         if [ -z "$line" ]; then echo "   (the file is empty)"; else _csh_add "$line" && changed=1; fi
         _bvk_yn again "Choose another file?" || break
         [ "$again" = y ] || break
       done ;;
    *) return 1 ;;
  esac
  [ "$changed" = 1 ] || return 0
  _cs_accounts_save || return 1
  for a in "${_CSH_ADDED[@]}"; do _cs_is_authed "$a" || n=$((n+1)); done
  [ "$n" -gt 0 ] || return 0                              # every new profile already has a gcloud login
  _bvk_yn ans "Sign in $n new profile(s) now? (Opening a profile later asks for it too.)" || return 0
  [ "$ans" = y ] || return 0
  for a in "${_CSH_ADDED[@]}"; do _cs_is_authed "$a" || _csh_signin "$a" || break; done
  return 0
}

# ── remove (x)
_csh_remove() {
  local picked="" ans="" i k n keep=() rows=() gone=()
  [ "${#_CS_ACCOUNTS[@]}" -gt 0 ] || { echo "📜  No saved profiles."; return 1; }
  for i in "${!_CS_ACCOUNTS[@]}"; do rows+=("$((i+1)):${_CS_ACCOUNTS[$i]}"); done
  _bvk_menu picked -m -t "Remove Cloud Shell profiles" -i "🗑️" -q "Which profiles do you want to remove?" "${rows[@]}" || return 1
  [ -n "$picked" ] || { echo "🚫 Nothing chosen."; return 1; }
  n=0; for k in $picked; do n=$((n+1)); done
  _xui_yes "Remove $n profile(s) from this list? gcloud keeps its logins unless you sign them out next." || return 1
  for i in "${!_CS_ACCOUNTS[@]}"; do
    case " $picked " in *" $((i+1)) "*) gone+=("${_CS_ACCOUNTS[$i]}") ;; *) keep+=("${_CS_ACCOUNTS[$i]}") ;; esac
  done
  _CS_ACCOUNTS=("${keep[@]}")
  _cs_accounts_save || return 1
  for k in "${gone[@]}"; do
    _cs_is_authed "$k" || continue
    _bvk_yn ans "Also sign $k out of gcloud (gcloud auth revoke)?" || break
    [ "$ans" = y ] && { _cs_gc auth revoke "$k" --quiet >/dev/null 2>&1 && echo "   ✅ signed out: $k" || echo "   ❌ could not sign out: $k"; }
  done
  _cs_status_load
  return 0
}

# ── open (a number) and switch off (k)
_csh_activate() {                # sign in when needed, then gcloud config set account  → rc 0 = gcloud is on that account
  local acct="$1"
  if ! _cs_is_authed "$acct"; then
    echo "🔑 $acct is not signed in on this machine yet."
    _csh_signin "$acct" || return 1
  fi
  _cs_use "$acct" || { echo "❌ gcloud could not switch to $acct."; return 1; }
  _CS_ACTIVE="${acct,,}"
  return 0
}

_csh_open() {
  local acct="$1" rc
  _csh_activate "$acct" || return 1
  echo "☁️  Opening Cloud Shell as $acct …"
  _bvk_mouse_off
  _cs_launch; rc=$?
  _bvk_mouse_on
  printf '\033[?25h'
  if [ "$rc" -ne 0 ]; then echo "☁️  Cloud Shell closed (exit $rc)."; _bvk_info_wait; fi
  return 0
}

_csh_kill() {
  local acct="" pick="" i rows=() rc
  if [ "${#_CS_ACCOUNTS[@]}" -eq 1 ]; then
    acct="${_CS_ACCOUNTS[0]}"
  else
    for i in "${!_CS_ACCOUNTS[@]}"; do rows+=("$((i+1)):${_CS_ACCOUNTS[$i]}"); done
    _bvk_menu pick -t "Switch off Cloud Shell" -i "🛑" -q "Which profile's Cloud Shell do you want to switch off?" "${rows[@]}" || return 1
    acct="${_CS_ACCOUNTS[$((pick-1))]}"
  fi
  [ -n "$acct" ] || return 1
  _xui_yes "Switch off Cloud Shell for $acct? Everything running in it stops (tmux first, else all its processes)." || return 1
  _csh_activate "$acct" || return 1
  echo "🛑 Switching Cloud Shell off …"
  _cs_kill; rc=$?
  if [ "$rc" -eq 0 ]; then echo "✅ Switched off. The next launch starts a fresh session."
  else echo "ℹ️  Done (exit $rc). The connection closes when everything stops; if an error shows above, Cloud Shell could not be reached."; fi
  _bvk_info_wait
  return 0
}

# ── the screen (csh): the saved profiles
csh_build() { _xui_begin_items "${_CS_ACCOUNTS[@]}"; }

csh_row() {
  _xui_slot "$1"; local s="$_XUI_SLOT" a st tag=""
  a="${_CS_ACCOUNTS[$s]}"
  if _cs_is_authed "$a"; then st="✓ signed in"; else st="⚠ sign-in needed"; fi
  [ "${a,,}" = "$_CS_ACTIVE" ] && tag="  💫 active"
  printf -v _vp_line ' %2d) 👤 %-30s %s%s' "$1" "$(_xui_trunc "$a" 30)" "$st" "$tag"
}

csh_header() { _tpl_list_header "☁️  Cloud Shell   ${#_CS_ACCOUNTS[@]} profile(s)" "💫 active: ${_CS_ACTIVE:-none}"$'\n'"🔌 a profile runs  gcloud config set account  then opens Cloud Shell"; }

csh_footer() { _mc_std_items -b; _tpl_footer 7P68NA "#Select a number to open Cloud Shell as that profile" "c:Create profile" "x:Remove profiles" "k:Switch off Cloud Shell" "rf" "|" "${_MC_STD[@]}"; }

_csh_cmd() {
  case "$1" in
    c)  _csh_create; return 0 ;;
    x)  _csh_remove; return 0 ;;
    k)  _csh_kill; return 0 ;;
    rf) _cs_status_load || echo "❌ Could not read the gcloud accounts."; return 0 ;;
    [0-9]*)
      _xui_row "$1" || { _bvk_invalid; return 1; }
      _csh_open "${_CS_ACCOUNTS[$_XUI_SLOT]}"
      return 0 ;;
    fx|sw|api|.r|-u) echo "↩️  Go back with  u  first."; return 1 ;;
    *) return 9 ;;
  esac
}

# ── the button
_fx_adf_cloudshell() {
  _dep_need -c "Cloud Shell" cloudshell || return 1          # gcloud (installed by the deps engine) + an ssh client
  _cs_locate || { echo "❌ gcloud is installed but could not be found on this machine."; return 1; }
  _cs_accounts_load
  _cs_status_load || echo "⚠️  Could not read the gcloud accounts (sign-in marks may be missing)."
  if [ "${#_CS_ACCOUNTS[@]}" -eq 0 ]; then                    # nothing saved yet: ask first (u = leave)
    echo "👥 No Cloud Shell profiles saved yet."
    _csh_create
    [ "${#_CS_ACCOUNTS[@]}" -gt 0 ] || return 1
  fi
  _xui_enter
  _xui_screen csh
  _xui_loop _csh_cmd
  _xui_leave
}

_fx_adf_register "launch.cloudshell" "_fx_adf_cloudshell" "cloudshell/launch.cloudshell"
