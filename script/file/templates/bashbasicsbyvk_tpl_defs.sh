# ============================================================
#  bashbasicsbyvk_tpl_defs.sh — THE GLOBAL DEFINER of the template architecture
#
#  The chain, in this order, and nowhere else:
#      1. this file          defines every $section and every {placeholder} ONCE
#      2. *.sh.tpl           (bashbasicsbyvk_<ID>.sh.tpl) lays out a screen with them; a template never defines anything
#      3. bashbasicsbyvk_tpl.sh   the processor: reads a template, resolves each placeholder through this file
#      4. the menu files     set their DATA (_tpl_set menu_name "..."), then call _tpl_section / _tpl_render with a template ID
#
#  A template is named by its 6-character ID (the ID 🧶 tidy prints). Screens that look alike share one template.
#
#  Section markers (a line of a template that is only  $name):
#      $menu_header   $menu_body   $menu_footer
#
#  Placeholder kinds  ( _tpl_def NAME KIND SPEC "what it is" [DEFAULT] ):
#      var     text the screen sets with  _tpl_set NAME VALUE  (DEFAULT when it did not). May be several lines. Usable inside a line: "Select {what} to {action}"
#      text    a constant (SPEC). The wording lives HERE only.
#      fn      SPEC = a function that prints the rows itself, in the current shell (it declares into the advert registry,
#              sets _MC_PRINTED ...: never run in a $( ) subshell). A line that is only {name}.
#      slot    the screen supplies the function:  _tpl_set NAME function_name. Empty = prints nothing. A line that is only {name}.
#      prompt  the word the prompt shows (SPEC). Never printed as a row: the prompt drawers read it (_TPL_ACCEPTOR).
#
#  A template line:   text with {placeholders}  ·  {name} alone on a line  ·  a blank line (= one blank row)  ·  # comment
#                     ?name <line>   the line is printed only when {name} is not empty   (?name alone = a blank row that is conditional)
#
#  Rules: print through echo / printf, never `builtin` (the smart-menu layer records echo to redraw the screen).
#         Adding a placeholder = ONE _tpl_def line here. A template that uses a name this file does not define fails
#         `bashbasicsbyvk_tidy_gen --check`, and so does a name defined here that no template uses.
# ============================================================

declare -gA _TPL_SECTION=()     # section name -> what it is
declare -gA _TPL_KIND=()        # placeholder -> var | text | fn | slot | prompt
declare -gA _TPL_SPEC=()        # placeholder -> function (fn) / constant (text, prompt) / default (var)
declare -gA _TPL_DESC=()        # placeholder -> one line: what it is
declare -gA _TPL_VAL=()         # placeholder -> the value a screen set (_tpl_set)
declare -g  _TPL_ACCEPTOR=""    # the prompt word, set below from {footer_acceptor}

_tpl_defsection() { _TPL_SECTION[$1]="$2"; }
_tpl_def()     { _TPL_KIND[$1]="$2"; _TPL_SPEC[$1]="$3"; _TPL_DESC[$1]="$4"; }

# ── the sections ────────────────────────────────────────────
_tpl_defsection menu_header "the top of a screen: title, location rows, what to do"
_tpl_defsection menu_body   "the rows the person chooses from"
_tpl_defsection menu_footer "the keys, the suggestion, then the prompt"

# ── the placeholders ────────────────────────────────────────
# header
_tpl_def menu_name        var  ""      "the screen's title line (icon + name)"
_tpl_def menu_description var  ""      "plain words under the title: what the screen is (may be several rows)"
_tpl_def action           var  ""      "the verb of a picker: rename, delete, copy ..."
_tpl_def what             var  "items" "what is being picked: items, groups, Destination ..."
_tpl_def job              var  ""      "the job a picker is for: Transfer, Delete ..."
_tpl_def icon             var  "🛷"    "the icon in front of a picker's title (🛷 Transfer, 🗑️ Delete ...)"
_tpl_def job_word         var  "for"   "the word between what and job in a picker's title: for (Select Items for Transfer) · to (Select extensions to delete)"
_tpl_def cd_path          fn   _tpl_p_cd_path          "the row  📂 cd path: <folder the app is in>"
_tpl_def nav_path         fn   _tpl_p_nav_path         "the row  ☁️ nav path: <where the list is>  (+ group / filter text; a picker sets nav_path_text)"
_tpl_def imaginary_banner fn   _tpl_p_imaginary_banner "the banner of an imaginary (grouped) list, when there is one"
_tpl_def pick_note        fn   _tpl_p_pick_note        "the dim line under a picker's title: the s-N suggestion, or the Settings description"
_tpl_def status_row       fn   _tpl_p_status_row       "the top of the folder view: 💫 greeting, 🧠 insanity meter (while signed in), then the buttons [🔔 Notifications n]  [🐌 Pending n]; a blank row between the parts"
_tpl_def header_notes     slot ""                      "the notice rows under the location rows (a screen supplies the function that prints them: banners, hints)"
_tpl_def filter_line      fn   _tpl_p_filter_line      "the row  🔍 filter: ABC*  (n/total)  while a filter is set (prints nothing otherwise)"
_tpl_def tab_bar          fn   _tpl_p_tab_bar          "the tab bar of a tabbed menu: [Tab1]  Tab2 ...  (data key tab_name = the name the tabbed screen was defined with)"
_tpl_def tab_description  fn   _tpl_p_tab_description  "the plain-words row under the tab bar (data keys tab_name, tab_folder)"
_tpl_def count_line       fn   _tpl_p_count_line       "the row  X out of N here  of a tabbed menu (data key count_total adds  · T total)"
_tpl_def tab_gap          var  "1"                     "a conditional blank row between the count row and the notes of a tabbed menu (a screen sets it empty to drop it)"
# body
_tpl_def menu_list        slot ""      "the rows of a menu (the screen supplies the function that prints them)"
_tpl_def file_list        slot ""      "the rows of a file / folder list (the screen supplies the function that prints them)"
# footer
# data keys a screen may set (not placeholders, no template names them):
#   footer_items = the keys, space separated, bare keys or key:Label (default "u.up q.close"); a registered footer is  @name  (chrome style)
#   footer_style = row (one plain row, the default) | chrome (_mc_footer: advert registry, wrapping; items from _TPL_FOOTER_ARR)
#   tab_name · tab_folder · count_total = the tabbed menu's data (_tm_head sets them)
# A screen whose keys come from the chrome calls  _tpl_footer ID item...  (one call: style chrome + the items)
_tpl_def footer_commands  fn   _tpl_p_footer_commands  "the keys row: u) Up   q) Close ... (bare keys take their label from _MC_KEYLABEL)"
_tpl_def footer_note      slot ""      "a note row under the keys (a screen supplies the function that prints it)"
_tpl_def menu_suggestions slot ""      "the suggestion rows (what the typed text would do)"
_tpl_def footer_acceptor  prompt "Select:" "the word at the prompt"

_TPL_ACCEPTOR="${_TPL_SPEC[footer_acceptor]}"

# ── the placeholders that print rows in the current shell (kind fn) ──
# cd path / nav path: the two location rows of the folder view, split so a template can place them (browse.sh holds the rows)
_tpl_p_cd_path()  { _loc_cd_row; }
_tpl_p_nav_path() {
  if [ -n "${_TPL_VAL[nav_path_text]-}" ]; then echo "☁️ nav path: ${_TPL_VAL[nav_path_text]}"; else _loc_nav_row; fi
}
_tpl_p_imaginary_banner() { [ "${_vp_mode:-}" == "imaginary" ] && [ -n "${_imag_banner:-}" ] && echo "$_imag_banner"; return 0; }
# the top of the folder view (greeting, insanity meter, the two buttons; all read caches only: they never wait for the network)
_tpl_p_status_row() { _bvk_hdr_greeting; _bvk_hdr_insanity; _bvk_hdr_status; }
# a filter that is set shows its row under the header of every list screen
_tpl_p_filter_line() { _vp_filter_header_line; }
# the tabbed menu's rows: the tab bar, the description of the tab and the count (the builders live in tabmenu.sh)
_tpl_p_tab_bar() { printf '%s\n' "$(_tm_bar "${_TPL_VAL[tab_name]-}")"; }
_tpl_p_tab_description() { _tm_desc_line "${_TPL_VAL[tab_name]-}" "${_TPL_VAL[tab_folder]-}"; }
_tpl_p_count_line() { _tm_count_line "${_TPL_VAL[count_total]-}"; }
# the picker's dim line under the title (+ the blank row after it); the caller's own wording or the Settings description
_tpl_p_pick_note() {
  if [ "${_TPL_VAL[pick_suggest]-}" = 1 ]; then
    _pick_suggest "${_TPL_VAL[pick_suggest_noun]-}"
    [ -n "${_TPL_VAL[pick_desc]-}" ] && _desc_print_dim "${_TPL_VAL[pick_desc]}"      # a caller's own wording (the python file picker's rules); no caller of -s passed one before
    echo
  else _desc_print_dim "${_TPL_VAL[pick_desc]:-Select ${_TPL_VAL[what],,}|*}" && echo; fi
  return 0
}
# the keys row. row: one line, the same words as _mc_footer prints (labels from _MC_KEYLABEL) · chrome: _mc_footer itself
_tpl_p_footer_commands() {
  local items="${_TPL_VAL[footer_items]:-u.up q.close}" style="${_TPL_VAL[footer_style]:-row}" it line="" cell
  if [ "$style" = chrome ]; then
    local -a _tp_arr=(); [ -n "${_TPL_FOOTER_ARR[*]+x}" ] && _tp_arr=("${_TPL_FOOTER_ARR[@]}") || read -r -a _tp_arr <<< "$items"
    _mc_footer "${_tp_arr[@]}"; return 0
  fi
  for it in $items; do
    if [[ "$it" == *:* ]]; then cell="${it%%:*}) ${it#*:}"
    else cell="${it%%.*}) ${_MC_KEYLABEL[$it]:-${it%%.*}}"; fi
    line+="${line:+   }${cell//_/ }"
  done
  echo "$line"
}
declare -ga _TPL_FOOTER_ARR=()  # chrome style: the footer items as an array (items with spaces, "|" and "#note" lines)
