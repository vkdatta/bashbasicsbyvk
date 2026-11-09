# bashbasicsbyvk_deepsearch.sh — the  ==  deep filter of every Settings / Home style screen (the _st_run engine)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
#   =text     filters the rows of the screen you are on, live            (bashbasicsbyvk_settings_ui.sh)
#   ==text    + Enter  searches EVERY screen below Settings and Home, however deep: the screen titles and the
#             plain-words explanation of every row (the table of bashbasicsbyvk_settings_desc.sh).  The matching
#             screens are listed; a number opens one.  Same idea as "==" in the folder lists, which searches the
#             sub-folders: the list you are looking at is not the limit.
#   ==  + Enter alone clears, like  =  + Enter.
#
#  Where the answers come from (nothing is opened or run to find them, so a search is quick and has no side effects):
#    • the description table  (_ST_DESC: "<screen>|<row tag>" -> text; "<parent>›<screen>|…" keys name their screen after the last ›)
#    • the Home rows (their labels come from _home_build, caught with _st_add stubbed — nothing is drawn)
#    • which function opens a screen: one scan of the script files for  _st_run "Title" … , once per session
#  A result opens only a plain  <name>_settings  screen (it needs nothing from the screen above it).  Anything else — a screen that
#  works on data its parent hands it, "Reset all settings" — is shown with its way in ("Open it from: …") and is never run from here.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════════════

declare -gA _SD_FN=()          # screen title -> the function that opens it
declare -g  _SD_READY=0
declare -ga _SD_T=() _SD_G=() _SD_L=() _SD_S=()     # the hits: screen title · Home tag ("" = a Settings screen) · label · snippet
declare -g  _SD_Q=""
_SD_MAX=60                     # most screens / rows listed

# "Parent›Title|tag" or "Title|tag"  →  _SD_title _SD_tag     (a " › " WITH spaces belongs to the title, e.g. "Timezone › Manual")
_sd_split_key() {
  local k="${1%%|*}"
  _SD_tag="${1#*|}"
  if [[ "$k" =~ ^(.*[^\ ])›([^\ ].*)$ ]]; then _SD_title="${BASH_REMATCH[2]}"; else _SD_title="$k"; fi
}

# one scan of the script files: which function opens which screen
_sd_scan() {
  (( _SD_READY )) && return 0
  _SD_READY=1
  local p dir t fn f
  p=$(command -v bashbasicsbyvk_settings_ui.sh 2>/dev/null) || p=""
  dir="${p%/*}"; [ -n "$p" ] && [ -d "$dir" ] || return 0
  while IFS=$'\t' read -r t fn f; do
    [ -n "$t" ] && [ -n "$fn" ] || continue
    # only a plain public  xxx_settings  function: it needs nothing from a parent screen; "menu_context_*" works on the menu it was opened from
    [[ "$fn" =~ ^[a-z][a-z0-9_]*_settings$ ]] || continue
    [[ "$fn" == *context* ]] && continue
    if [ -z "${_SD_FN[$t]:-}" ] || [[ "$f" == *bashbasicsbyvk_settings_groups.sh || "$f" == *bashbasicsbyvk_settings.sh ]]; then _SD_FN["$t"]="$fn"; fi
  done < <(awk '
      /^[A-Za-z_][A-Za-z0-9_]*\(\)/ { fn = $0; sub(/\(\).*/, "", fn) }
      /^[ \t]*#/ { next }
      { s = $0
        while (match(s, /_st_run +"[^"$]+"/)) {
          t = substr(s, RSTART, RLENGTH); sub(/^_st_run +"/, "", t); sub(/"$/, "", t)
          print t "\t" fn "\t" FILENAME
          s = substr(s, RSTART + RLENGTH)
        } }' "$dir"/bashbasicsbyvk_*.sh 2>/dev/null)
  return 0
}

# the Home rows:  tag -> label   (the builder is run with _st_reset / _st_add stubbed, in a subshell: nothing is drawn or changed)
_sd_home_labels() {
  declare -F _home_build >/dev/null 2>&1 || return 0
  ( _st_reset() { :; }; _st_add() { printf '%s\t%s\n' "${5:-}" "$2"; }; _home_build ) 2>/dev/null
}

# _sd_search <text>  →  _SD_T / _SD_G / _SD_L / _SD_S   (best matches first: a screen whose NAME matches, then the most matching rows)
_sd_search() {
  local q="${1,,}" key text tl title tag pos pre sn n=0 t l s ranked
  _SD_Q="$1"; _SD_T=(); _SD_G=(); _SD_L=(); _SD_S=()
  [ -n "$q" ] || return 0
  declare -F _st_desc_load >/dev/null 2>&1 && _st_desc_load
  declare -A cnt=() snip=() tname=() hlab=() inorder=() texthit=()
  while IFS=$'\t' read -r t l; do [ -n "$t" ] && hlab["$t"]="$l"; done < <(_sd_home_labels)
  local -a order=()
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    _sd_split_key "$key"; title="$_SD_title"; tag="$_SD_tag"
    text="${_ST_DESC[$key]}"; tl="${text,,}"
    if [ "$title" = "Home" ]; then                                  # Home: every row is its own way in
      [ "$tag" = "*" ] || [ "$tag" = "local" ] && continue
      if [[ "${hlab[$tag],,}" == *"$q"* || "$tl" == *"$q"* ]]; then
        pre="${tl%%"$q"*}"; [[ "$tl" == *"$q"* ]] && pos=${#pre} || pos=0
        order+=("Home|$tag"); cnt["Home|$tag"]=1; tname["Home|$tag"]="${hlab[$tag]:-$tag}"
        snip["Home|$tag"]="${text:$(( pos > 24 ? pos - 24 : 0 )):60}"
      fi
      continue
    fi
    if [[ "$tl" == *"$q"* ]]; then
      [ -n "${inorder[$title]:-}" ] || { order+=("$title"); inorder["$title"]=1; }
      if [ -z "${texthit[$title]:-}" ]; then                         # the snippet is the first matching sentence (it replaces a name-only one)
        texthit["$title"]=1
        pre="${tl%%"$q"*}"; pos=${#pre}
        sn="${text:$(( pos > 24 ? pos - 24 : 0 )):60}"; (( pos > 24 )) && sn="…$sn"
        snip["$title"]="$sn"
      fi
      cnt["$title"]=$(( ${cnt[$title]:-0} + 1 ))
    elif [[ "${title,,}" == *"$q"* ]] && [ -z "${inorder[$title]:-}" ]; then    # the screen's NAME matches, no row text does (yet)
      order+=("$title"); inorder["$title"]=1; snip["$title"]="$(_sd_first_text "$title")"
    fi
  done < <(printf '%s\n' "${!_ST_DESC[@]}" | LC_ALL=C sort)
  # rank: a title that matches first, then more matching rows; ties alphabetical
  ranked=$(for key in "${order[@]}"; do
      nm="$key"; [[ "$key" == Home\|* ]] && nm="${tname[$key]}"
      s=1; [[ "${nm,,}" == *"$q"* ]] && s=0
      printf '%s\t%03d\t%s\n' "$s" $(( 999 - ${cnt[$key]:-0} )) "$key"
    done | LC_ALL=C sort -t$'\t' -k1,1 -k2,2 -k3,3 | cut -f3)
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    (( n >= _SD_MAX )) && break
    if [[ "$key" == Home\|* ]]; then
      _SD_T+=("Home"); _SD_G+=("${key#Home|}"); _SD_L+=("Home › ${tname[$key]}")
    else
      _SD_T+=("$key"); _SD_G+=(""); _SD_L+=("$key")
    fi
    sn="${snip[$key]:-}"
    if [[ "$key" != Home\|* ]] && (( ${cnt[$key]:-0} > 1 )); then sn="${cnt[$key]} matches · $sn"; fi
    _SD_S+=("$sn")
    n=$(( n + 1 ))
  done <<<"$ranked"
  return 0
}
# the screen's own description, for a screen that matched by its NAME only
_sd_first_text() { local t="${_ST_DESC[$1|*]:-}"; printf '%s' "${t:0:60}"; }

_sd_build() {
  local i n=${#_SD_T[@]}
  _st_reset
  if (( n == 0 )); then _st_add h "Nothing found for “$_SD_Q” in any screen"; return 0; fi
  _st_add h "$n result$([ "$n" = 1 ] || echo s) for “$_SD_Q”  (a number opens the screen)"
  for (( i=0; i<n; i++ )); do _st_add a "${_SD_L[$i]}" 0 "${_SD_S[$i]}" "hit$i"; done
}
_sd_act() {
  local i="${_st_tag[$1]#hit}" fn t
  [[ "$i" =~ ^[0-9]+$ ]] && [ -n "${_SD_T[$i]+x}" ] || return 0
  t="${_SD_T[$i]}"
  if [ "$t" = "Home" ]; then                       # a Home row opens what Home opens: the same function, the row's own tag
    declare -F _home_act >/dev/null 2>&1 || return 0
    _st_tag[$1]="${_SD_G[$i]}"; _home_act "$1"; return 0
  fi
  _sd_scan
  fn="${_SD_FN[$t]:-}"
  if [ -n "$fn" ] && declare -F "$fn" >/dev/null 2>&1; then "$fn"; return 0; fi
  _st_note "“$t” cannot be opened from a search (it works on what the screen above it hands it). Open it from Settings, then the screen that holds it."
  return 0
}

# the entry point  (called by _st_run when  ==text  + Enter  is typed)
st_deep_search() {
  _sd_scan
  _sd_search "$1"
  _st_run "Search results" _sd_build _sd_act
}
