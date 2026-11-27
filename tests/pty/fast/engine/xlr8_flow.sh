#!/usr/bin/env bash
# xlr8 (workflows): if / else / end if and {$variables}.   bash tests/pty/fast/engine/xlr8_flow.sh
# No terminal: it calls the hooks the way the app does (_wf_list, _wf_box, _wf_prompt) and reads what they answer.
# (1) the parser: nested ifs close, every mistake is refused with a reason  (2) an if is decided when the app asks its NEXT question:
# asked / not asked (the clean-tree git push), else, option, screen, nesting  (3) {$name}: command line (one name, name=value, in order), asked
# when missing, used in value= / where name= / from, never read twice  (4) the guard still stops a wrong answer
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
W="$(find "$ROOT/script" -name bashbasicsbyvk_wf.sh | head -1)"; X="$(find "$ROOT/script" -name bashbasicsbyvk_xlr8.sh | head -1)"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export BVK_WF_HOME="$T/wf"; mkdir -p "$BVK_WF_HOME" "$T/start" "$T/other"
LOG="$T/log"
# shellcheck disable=SC1090
source "$X"; source "$W"
_cm_ctx_find() { _CM_MAP=main; }
_bvk_read() { local _v="$1"; printf -v "$_v" '%s' "${TYPED:-}"; [ -n "${TYPED+x}" ]; }
path="$T/start"; group_prefix=""; force_show=false; _sw_in_mode=0; _WF_MENU=0

wf_write() { printf '%s\n' "$2" > "$BVK_WF_HOME/$1.xlr8"; }
run() { _wf_off; : > "$LOG"; _wf_run "$@" >>"$LOG" 2>&1; }                 # start a run (the one before it is over)
list() { choice=""; _wf_list play >>"$LOG" 2>&1; }               # the app shows a list and asks
menu() {                                                         # QUESTION yn LABEL...  : a choice box; -> _WF_ANSWER
  local q="$1" yn="$2" i=1; shift 2
  _bc_question="$q"; _bc_title=""; _bc_yn="$yn"; _bc_key=(); _bc_lbl=(); _bc_var=_bc_got
  for l in "$@"; do _bc_key+=("$i"); _bc_lbl+=("$l"); i=$(( i + 1 )); done
  _WF_ANSWER=""; _wf_box play >>"$LOG" 2>&1; MRC=$?
}
rmenu() {                                                        # RECORD: QUESTION CHOSEN-KEY LABEL...   (what the person picked in a choice box)
  local q="$1" got="$2" i=1; shift 2
  _bc_question="$q"; _bc_title=""; _bc_yn=0; _bc_key=(); _bc_lbl=(); _bc_var=_bc_got; _bc_got="$got"
  for l in "$@"; do _bc_key+=("$i"); _bc_lbl+=("$l"); i=$(( i + 1 )); done
  _wf_box record >>"$LOG" 2>&1
}
steps() { cat "$BVK_WF_DIR/steps"; }
typed() { _WF_ANSWER=""; _wf_prompt play "$1" >>"$LOG" 2>&1; }  # a typed line
alive() { [ -n "${BVK_WF_DIR:-}" ] && [ -d "$BVK_WF_DIR" ]; }
said() { grep -qF -- "$1" "$LOG"; }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; sed 's/^/        | /' "$LOG" | tail -8; fi; }

# ── (1) the parser ───────────────────────────────────────────────────────
echo "(1) parser"
cat > "$T/good.xlr8" <<'EOF'
start
from here
on main
if asked "Select version bump type"
  "Select version bump type" where option="Patch"
  if not option "Skip"
    input "Enter commit message" value="{$msg}"
  else
    input "Enter commit message" default
  end if
endif
if menu "Case sensitive?" => "Case sensitive?" where option="Yes" => end if
if screen switch
end If
goto start
end
EOF
_xl_load "$T/good.xlr8" && ok "nested if / else / end if / endif / => load" || bad "good file refused: $_XL_ERR"
[ "${_XL_VN[*]}" = msg ] && ok "variable names are collected (msg)" || bad "variables: ${_XL_VN[*]}"
[ "${_XL_J[2]}" = 9 ] && ok "the outer if points at its end if" || bad "jump of the outer if: ${_XL_J[2]:-none}"
n=0
while IFS='|' read -r why text; do
  printf 'start\n%b\n' "$text" > "$T/bad.xlr8"; n=$(( n + 1 ))
  if _xl_load "$T/bad.xlr8"; then bad "refused? $why"; else ok "refused: $why  ($_XL_ERR)"; fi
done <<'EOF'
if without end if|if asked "x"
else without if|else
end if without if|end if
two elses|if asked "x"\nelse\nelse\nend if
unknown kind|if sometimes "x"
no value|if asked
junk after value|if asked "x" junk
open variable|input "q" value="{$ok"
bad variable name|input "q" value="{$1x}"
EOF

# ── (2) if: decided at the NEXT question ─────────────────────────────────
echo "(2) if / else"
PUSH='start
from here
on main
cmd i
where option="Git Push"
if asked "Select version bump type"
  where option="Patch"
  input "Enter commit message" value="{$msg}"
  "Create this commit" where option="Yes"
end if
"override the remote" where option="Yes"
goto start
end'
wf_write push "$PUSH"
run push "fix the login bug"
check "the run starts and keeps {\$msg} in a file" bash -c "[ \"\$(cat \"$BVK_WF_DIR/var.msg\")\" = 'fix the login bug' ]"
list;  check "list: cmd i is typed"                   [ "$choice" = i ]
menu "Infinity" 0 "Git Push" "Open GitHub"; check "menu: Git Push is picked" [ "$_WF_ANSWER" = 1 ]
menu "Select version bump type:" 0 "Patch  (#patch)" "Minor  (#minor)" "Major  (#major)" "None   (skip the version tag)"
check "dirty tree: the version menu comes, the if-side runs, Patch" [ "$_WF_ANSWER" = 1 ]
typed "Enter commit message: "; check "the typed line is {\$msg} from the command line" [ "$_WF_ANSWER" = "fix the login bug" ]
menu "Create this commit?" 1 "Yes" "No"; check "Create this commit: Yes" [ "$_WF_ANSWER" = 1 ]
list
said "not asked this time: \"override the remote\"" && ok "the optional 'override' Yes is skipped (not asked)" || bad "override not skipped"
said "finished: all" && ok "workflow finished" || bad "workflow did not finish"
alive && bad "run state left behind" || ok "run state removed"

# the same workflow, but there is nothing to commit: the app goes straight back to the list (the failure this was made for)
run push "unused"
list; menu "Infinity" 0 "Git Push" "Open GitHub"
list
said "skipped: if asked \"Select version bump type\"" && ok "clean tree: the if-block is skipped and said so" || bad "no skip message"
said "❌" && bad "clean tree: the run FAILED" || ok "clean tree: no failure"
said "finished: all" && ok "clean tree: the workflow finished" || bad "clean tree: not finished"

# else / not / option
wf_write pick 'start
from here
on main
if option "Skip"
  "Pick" where option="Skip"
else
  "Pick" where option="Patch"
end if
if not asked "Never asked"
  "Second" where option="B"
end if'
run pick
menu "Pick" 0 "Skip" "Patch"; check "if option: the option is there -> the if-side" [ "$_WF_ANSWER" = 1 ]
menu "Second" 0 "A" "B";      check "if not asked: runs when something else is asked" [ "$_WF_ANSWER" = 2 ]
run pick
menu "Pick" 0 "Minor" "Patch"; check "else-side: the option is not there -> Patch" [ "$_WF_ANSWER" = 2 ]
run pick
menu "Pick" 0 "Skip" "Patch"; menu "Second" 0 "A" "B"
alive && ok "run is alive after both questions (the closing list is not asked yet)" || bad "run ended early"

# nesting: a skipped outer block skips the inner one too
wf_write nest 'start
from here
on main
if asked "Outer"
  if asked "Inner"
    "Inner" where option="X"
  end if
  "Outer" where option="Y"
end if
"Last" where option="Z"'
run nest
menu "Last" 0 "Q" "Z"; check "a skipped outer if skips the inner one: Last is answered" [ "$_WF_ANSWER" = 2 ]
run nest
menu "Outer" 0 "Y"; check "outer true, inner false: the outer answer after it" [ "$_WF_ANSWER" = 1 ]
said "skipped: if asked \"Inner\"" && ok "inner skip is said" || bad "inner skip not said"

# if screen
wf_write scr 'start
from here
on main
if screen main
  cmd c-a
end if'
run scr; list; check "if screen main on the main list -> cmd c-a" [ "$choice" = c-a ]

# ── (3) {$variables} ─────────────────────────────────────────────────────
echo "(3) variables"
wf_write two 'start
from here
on main
input "Enter commit message" value="{$msg}"
input "Branch" value="{$branch}"
where name="{$msg}"'
run two 'msg="hello world" branch=dev'
typed "Enter commit message:"; check "name=\"value\" with a space" [ "$_WF_ANSWER" = "hello world" ]
typed "Branch:";                check "name=value" [ "$_WF_ANSWER" = dev ]
run two 'first "second one"'
typed "Enter commit message:"; check "bare values go in the order the names appear: 1st" [ "$_WF_ANSWER" = first ]
typed "Branch:";                check "bare values: 2nd, quoted" [ "$_WF_ANSWER" = "second one" ]
run two 'nope=1';   said "no {\$nope}" && ok "an unknown name is refused" || bad "unknown name accepted"; alive && bad "a refused run started" || ok "a refused run is not started"
run two 'a b c';    said "More values" && ok "too many values are refused" || bad "too many values accepted"
run two 'msg="open'; said "quote is not closed" && ok "an open quote is refused" || bad "open quote accepted"
TYPED="typed branch"; run two 'msg=m'
typed "Enter commit message:"; typed "Branch:"
check "a missing value is asked now (and used)" [ "$_WF_ANSWER" = "typed branch" ]
TYPED=""; run two 'msg=m'; said "nothing was run" && ok "an empty answer cancels the run" || bad "empty answer accepted"; unset TYPED
wf_write one 'start
from here
on main
input "Enter commit message" value="{$input}"'
run one 'fix {$msg} the "quoted" thing'; typed "Enter commit message:"
check "ONE name: the whole rest of the line, even with braces and quotes, is the value (read once)" [ "$_WF_ANSWER" = 'fix {$msg} the "quoted" thing' ]
run one '"just quoted"'; typed "Enter commit message:"; check "ONE name: a lone quoted text loses its quotes" [ "$_WF_ANSWER" = "just quoted" ]
wf_write novar 'start
from here
on main
cmd c-a'
run novar 'surplus'; said "no {\$name} to fill" && ok "values for a workflow without names are refused" || bad "surplus accepted"
wf_write fromvar 'start
from "{$dir}"
on main
cmd c-a'
run fromvar "dir=$T/other"; check "from \"{\$dir}\" starts in that folder" [ "$path" = "$T/other" ]
path="$T/start"; run fromvar "dir=$T/gone"; said "folder that is gone" && ok "a missing from-folder is refused" || bad "missing folder accepted"
path="$T/start"
: > "$LOG"; handle_wf_cmd "wf one typed through the command" >>"$LOG" 2>&1; typed "Enter commit message:"
check "handle_wf_cmd 'wf NAME values...' hands the values over" [ "$_WF_ANSWER" = "typed through the command" ]

# ── (4) the guard is still there ─────────────────────────────────────────
echo "(4) guard"
wf_write guard 'start
from here
on main
if asked "Pick one"
  where option="Nope"
end if'
run guard; menu "Pick one" 0 "A" "B"
said "no option called 'Nope'" && ok "a true if does not weaken the guard: a wrong option stops the run" || bad "wrong option not caught"
alive && bad "run state left after a failure" || ok "failure cleans up"

# ── (5) the recorder writes if for the questions that can be switched off ─
echo "(5) recorder"
_wf_off; : > "$LOG"; _wf_start_record >>"$LOG" 2>&1
rmenu "🔠 Match case?" 1 "Exact  (Aa)" "Any"
rmenu "'my file' has no extension. The old one is .txt" 1 "Use old extension" "Create without extension"
rmenu "Where to copy?" 2 "Here" "There"
rmenu "Delete these?" 1 "Yes" "No"
_WF_MENU=0; _wf_prompt record "Enter commit message: " "my message" >>"$LOG" 2>&1
_wf_prompt record "Branch: " "" >>"$LOG" 2>&1
S="$(steps)"
check "a question Settings can hide is written inside if asked / end if" bash -c "grep -qx 'if asked \"Match case?\"' <<<'$S' && grep -qx '  \"Match case?\" where option=\"Exact\"' <<<'$S'"
check "the block is named by the short text, not the file-specific question" grep -q 'if asked "has no extension"' <<<"$S"
check "a question that is always asked stays a plain step (the guard keeps its bite)" bash -c "grep -qx '\"Delete these?\" where option=\"Yes\"' <<<'$S'"
check "=Where? is the WHOLE question: Where to copy? is not wrapped" bash -c "! grep -q 'if asked \"Where' <<<'$S' && grep -q '\"Where to copy?\" where option=\"There\"' <<<'$S'"
check "a typed answer for a switched-off question is wrapped too" bash -c "grep -qx 'if asked \"Enter commit message\"' <<<'$S' && grep -qx '  input \"Enter commit message\" ask' <<<'$S'"
check "an ordinary typed question is not" bash -c "grep -qx 'input \"Branch\" default' <<<'$S'"
n_if="$(grep -c '^if ' <<<"$S")"; n_end="$(grep -c '^end if' <<<"$S")"
check "every recorded if is closed ($n_if if / $n_end end if)" [ "$n_if" = "$n_end" ] && [ "$n_if" -ge 3 ]
{ cat "$BVK_WF_DIR/steps"; printf 'goto start\nend\n'; } > "$T/rec.xlr8"
check "the recorded file loads" _xl_load "$T/rec.xlr8"
# the recorded workflow, replayed with a different file name and with the setting switched to 'exact'
cp "$T/rec.xlr8" "$BVK_WF_HOME/rec.xlr8"; find_case_mode=exact
run rec
menu "'other file' has no extension. The old one is .md" 0 "Use old extension" "Create without extension"
check "a question with another file name still gets its answer" [ "$_WF_ANSWER" = 1 ]
: > "$LOG"; run rec
menu "Where to copy?" 0 "Here" "There"
check "the setting hides Match case: skipped with the setting named" bash -c "grep -q \"find_case_mode is 'exact'\" '$LOG'"
check "...and the next question is answered, nothing failed" bash -c "[ '$_WF_ANSWER' = 2 ] && ! grep -q '❌' '$LOG'"
unset find_case_mode

# ── (6) you do it by hand: pause, select ask, input ask on a menu, the multi-select at stop_record ──
echo "(6) by hand"
wf_write hand 'start
from here
on main
cmd d
pause "pick the files yourself"
"Delete these?" where option="Yes"
goto start
end'
run hand; list
_WF_LABS=(); _wf_ctx pick "pick items"; _wf_pick play >>"$LOG" 2>&1; rc=$?
check "pause: the pick screen is left to you (rc 1 = the app asks)" [ "$rc" = 1 ]
said "Your turn: pick the files yourself" && ok "pause says what you are to do" || bad "pause message missing"
alive && ok "the run is still alive after the pause" || bad "the pause ended the run"
menu "Delete these?" 1 "Yes" "No"; check "after your answer the next step goes on" [ "$_WF_ANSWER" = 1 ]
wf_write selask 'start
from here
on main
cmd d
select ask
"Delete these?" where option="Yes"'
run selask; list; _WF_LABS=(); _wf_ctx pick "pick items"; _buf=""; _wf_pick play >>"$LOG" 2>&1; rc=$?
check "select ask: you pick the items (rc 1)" [ "$rc" = 1 ]
said "select ask" && ok "select ask is said" || bad "select ask not said"
wf_write menuask 'start
from here
on main
input "Select version bump type" ask
"Create this commit?" where option="Yes"'
run menuask
menu "Select version bump type:" 0 "Patch" "Minor"
check "input \"Question\" ask on a menu: you choose (rc 1)" [ "$MRC" = 1 ]
menu "Create this commit?" 1 "Yes" "No"; check "...and the run goes on afterwards" [ "$_WF_ANSWER" = 1 ]
printf 'start\npause "a" extra\n' > "$T/bad.xlr8"; _xl_load "$T/bad.xlr8" && bad "pause with junk accepted" || ok "pause with junk is refused"
printf 'start\nselect maybe\n' > "$T/bad.xlr8"; _xl_load "$T/bad.xlr8" && bad "select maybe accepted" || ok "select maybe is refused"

# the end of a recording: the steps that name exact files can be left to you
_bvk_menu() { local -n _o="$1"; _o="${PICK:-}"; return "${PICKRC:-0}"; }
mk() { printf 'start\nfrom "/x"\non main\ncmd d\nselect name="a.txt" name="b.txt"\ncmd c- name="x.txt"\nif asked "Match case?"\n  "Match case?" where option="Exact"\nend if\nwhere name="proj"\n"Delete these?" where option="Yes"\n' > "$T/steps"; }
mk; PICK="1 2"; _wf_manual_pass "$T/steps" >>"$LOG" 2>&1
check "chosen: a select becomes select ask" grep -qx 'select ask' "$T/steps"
check "chosen: a command on a name becomes a pause that says what was recorded" grep -q '^pause "recorded: cmd c- name=' "$T/steps"
check "not chosen: a where name stays" grep -qx 'where name="proj"' "$T/steps"
check "an option answer is never offered or changed" bash -c "grep -qx '\"Delete these?\" where option=\"Yes\"' '$T/steps' && grep -qx '  \"Match case?\" where option=\"Exact\"' '$T/steps'"
mk; cp "$T/steps" "$T/steps0"; PICK=""; _wf_manual_pass "$T/steps"; check "Enter alone changes nothing" cmp -s "$T/steps" "$T/steps0"
PICK="1"; PICKRC=1; _wf_manual_pass "$T/steps"; check "u / q changes nothing" cmp -s "$T/steps" "$T/steps0"; PICKRC=0
printf 'start\nfrom "/x"\n"Delete these?" where option="Yes"\n' > "$T/steps"; cp "$T/steps" "$T/steps0"; PICK="1"; _wf_manual_pass "$T/steps"
check "no step names a file: nothing is asked, nothing changes" cmp -s "$T/steps" "$T/steps0"
mk; PICK="1 3"; _wf_manual_pass "$T/steps"; { cat "$T/steps"; printf 'goto start\nend\n'; } > "$T/hand.xlr8"
check "the file after the pass still loads (pause inside the file, if kept whole)" _xl_load "$T/hand.xlr8"

# ── (8) a workflow runs another one:  wf NAME [values]  /  cmd wf NAME ───
echo "(8) wf calls wf"
printf 'start\nwf b\ncmd wf b.xlr8 msg="x y"\nwf b fix it\nif asked "Q"\n  wf b\nend if\n' > "$T/c.xlr8"
_xl_load "$T/c.xlr8" && ok "wf NAME / cmd wf NAME / with values / inside an if load" || bad "call refused: $_XL_ERR"
[ "${_XL_T[0]}|${_XL_Q[0]}|${_XL_Q[1]}|${_XL_V[1]}|${_XL_V[2]}" = 'call|b|b|msg="x y"|fix it' ] && ok "the call keeps the name (without .xlr8) and the values" || bad "call fields: ${_XL_T[0]}|${_XL_Q[0]}|${_XL_Q[1]}|${_XL_V[1]}|${_XL_V[2]}"
for t in 'wf' 'wf "x"' 'cmd wf'; do printf 'start\n%s\n' "$t" > "$T/bad.xlr8"; _xl_load "$T/bad.xlr8" && bad "'$t' accepted" || ok "refused: $t"; done

wf_write b 'start
from "'"$T"'/other"
on main
pause "pick the files"
goto start
end'
wf_write a 'start
from here
on main
cmd d
wf b
"Delete these?" where option="Yes"
goto start
end'
run a; S="$(steps)"
has() { grep -qxF -- "$1" <<<"$S"; }
check "the called steps are put in the caller's list, in place" bash -c "[ \"\$(grep -n 'cmd d\|pause\|Delete' <<<'$S' | cut -d: -f2 | tr '\n' '|')\" = 'cmd d|pause \"pick the files\"|\"Delete these?\" where option=\"Yes\"|' ]"
check "the called workflow's from is dropped (the caller's start stays)" bash -c "[ \"\$(grep -c '^from' <<<'$S')\" = 1 ] && [ '$path' = '$T/start' ]"
check "its closing goto start is dropped, the caller's stays" bash -c "[ \"\$(grep -c '^goto start' <<<'$S')\" = 1 ]"
list; check "replay: the caller's cmd d" [ "$choice" = d ]
_WF_LABS=(); _wf_ctx pick "pick items"; _wf_pick play >>"$LOG" 2>&1; rc=$?
check "replay: the called workflow's pause hands the pick screen to you" [ "$rc" = 1 ] && said "Your turn: pick the files"
menu "Delete these?" 1 "Yes" "No"; check "replay: back in the caller, the next step is answered" [ "$_WF_ANSWER" = 1 ]

# a plain workflow is not rewritten
run guard; check "a workflow with no call is copied as it is" cmp -s "$BVK_WF_DIR/steps" "$BVK_WF_HOME/guard.xlr8"

# nesting, a circle, a missing one, too deep
wf_write n3 'start
on main
cmd c-a
goto start'
wf_write n2 'start
on main
cmd c-b
wf n3
cmd c-c
goto start'
wf_write n1 'start
on main
wf n2
cmd c-d
goto start'
run n1; S="$(steps)"
check "three levels deep, in order" bash -c "[ \"\$(grep '^cmd' <<<'$S' | tr '\n' ' ')\" = 'cmd c-b cmd c-a cmd c-c cmd c-d ' ]"
wf_write ca 'start
wf cb
goto start'
wf_write cb 'start
wf ca
goto start'
run ca; said "circle: ca → cb → ca" && ok "a circle is refused and shows the way round" || bad "circle not caught"; alive && bad "a refused run started" || ok "a refused run is not started"
wf_write self 'start
wf self
goto start'
run self; said "circle" && ok "a workflow calling itself is refused" || bad "self call accepted"
wf_write gone 'start
on main
wf nothere'
run gone; said "no workflow called 'nothere'" && ok "a missing called workflow is refused before anything runs" || bad "missing callee accepted"; alive && bad "started" || ok "nothing started"
for i in 1 2 3 4 5 6 7 8 9 10; do wf_write "d$i" "$(printf 'start\nwf d%s\n' "$(( i + 1 ))")"; done; wf_write d11 'start
cmd c-a'
run d1; said "more than 8 deep" && ok "calls more than 8 deep are refused" || bad "depth limit missing"
wf_write badcallee 'start
if asked "x"'
wf_write usesbad 'start
wf badcallee'
run usesbad; said "'badcallee' has a mistake" && ok "a mistake in the called workflow is named" || bad "callee mistake not named"

# values given in the call, and names the callee shares with the caller
wf_write ask1 'start
from here
on main
input "Message" value="{$msg}"
goto start'
wf_write v1 'start
from here
on main
wf ask1 msg="say \"hi\" & bye"
goto start'
run v1; typed "Message:"; check "a value in the call, with quotes and &, arrives whole" [ "$_WF_ANSWER" = 'say "hi" & bye' ]
wf_write v2 'start
from here
on main
wf ask1 just the words
goto start'
run v2; typed "Message:"; check "one name: the rest of the call line is the value" [ "$_WF_ANSWER" = "just the words" ]
wf_write v3 'start
from here
on main
wf ask1
goto start'
run v3 'given at the start'; typed "Message:"
check "a name the call does not give is shared: the value of the run fills it" [ "$_WF_ANSWER" = "given at the start" ]
TYPED="asked once"; run v3; typed "Message:"; check "...and is asked when the run starts if nobody gave it" [ "$_WF_ANSWER" = "asked once" ]; unset TYPED
wf_write v4 'start
from here
on main
wf two nope=1
goto start'
run v4; said "no {\$nope}" && ok "a call with an unknown name is refused (two names to fill)" || bad "unknown name in call accepted"
wf_write v5 'start
from here
on main
wf ask1 msg="{$who}, hello"
goto start'
run v5 'Sam'; typed "Message:"; check "a call can pass the caller's own {\$name}" [ "$_WF_ANSWER" = "Sam, hello" ]

# a call inside an if
wf_write ci 'start
from here
on main
if asked "Select version bump type"
  wf pk
end if
cmd c-z'
wf_write pk 'start
on main
"Select version bump type" where option="Patch"
goto start'
run ci; menu "Select version bump type:" 0 "Patch" "Minor"
check "a call inside an if runs when the question is asked" [ "$_WF_ANSWER" = 1 ]
run ci; list; check "...and is left out when it is not (the step after end if is next)" [ "$choice" = c-z ]

# wf while something is recording / running
_wf_off; : > "$LOG"; _wf_start_record >>"$LOG" 2>&1; _wf_run a >>"$LOG" 2>&1
said "add the line  wf NAME" && ok "typing wf while recording says how to call one instead" || bad "recording hint missing"
_wf_off; run a; : > "$LOG"; _wf_run b >>"$LOG" 2>&1
said "make  wf NAME  a step" && ok "typing wf during a run says how to call one instead" || bad "run hint missing"

# the registry itself: every question and setting it names still exists in the app
echo "(9) registry"
python3 - "$ROOT" <<'PYEOF' || fail=1
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]) / "script"
reg = next(root.rglob("bashbasicsbyvk_wf_when.txt"))
text = {p: p.read_text(encoding="utf-8", errors="ignore") for p in root.rglob("*") if p.is_file() and p.suffix in (".sh", ".txt", ".list") and p != reg}
blob = "\n".join(text.values()).lower()
bad = 0
for raw in reg.read_text(encoding="utf-8").splitlines():
    if not raw.strip() or raw.lstrip().startswith("#"): continue
    q, s, v = [x.strip() for x in raw.split("|")]
    q = q.lstrip("=")
    if q.lower() not in blob: print("  FAIL registry question is gone from the app:", q); bad = 1
    if s != "-" and s not in blob: print("  FAIL registry setting is gone from the app:", s); bad = 1
print("  ok   every registry question and setting still exists in the app" if not bad else "")
sys.exit(bad)
PYEOF

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
