# AGENTS.md — read this BEFORE doing anything else

Every AI agent working in this repo must read this file first and follow it exactly.
If a task seems to need breaking a rule, stop and ask the owner. Do not improvise.

> **OWNER-ONLY FILES.** `AGENTS.md`, `CLAUDE.md` and `GEMINI.md` are written by the owner. **No agent may edit, rewrite, "tidy", extend or add rules to any of them unless a human has explicitly
> permitted that edit in the current conversation** (a request like "update AGENTS.md" counts; a rule you think would be useful does not). If you believe a rule is wrong, outdated or missing, say so
> in one line in your reply and change nothing. The same goes for `tests/static/baseline/*` (owner accepts known findings; agents never run `bash tests/run.sh baseline` on their own).

## Workflow and tests (owner's rule: overrides every other mention of tests, tokens or "run" in this file)

**Why:** an agent can finish the work with 60% of its budget and then spend the rest on tests. If the budget runs out inside the tests, the owner gets NOTHING and waits for the
usage limit to reset. So: **deliver first, test after, deliver again after every fix. Tests must never be the reason the owner has no output.**

### The loop (every task, no exceptions)
1. **Do ALL the tasks.** Do not start any test yet.
2. **DELIVER NOW, before the first test.** The delivery is the finished work, complete and usable as it stands:
   - **In chat** (a chat window, or no shell on the owner's machine): put the result in the reply: send every changed file (or one archive) with the file-sending tool when you have one,
     otherwise paste each changed file in full (a diff only when the file is huge). A summary alone is not a delivery.
   - **In a terminal** (a CLI agent working in the repo): the files are already on disk in the working tree; leave them there (no commit, no push unless asked) and PRINT the summary to the terminal.
   - Either way, the first line is the **status line**: `<task name> (tests: x/y/n)`, then 3-6 lines: what changed, which files, which test runs next (static or pty, and why).
     `<task name>` = the name of the owner's original task / PR (or, if it had none, a 3-6 word name you pick); it stays the SAME on every later delivery.
     `x/y/n` = **x passed / y completed / n total** checks of what you chose. Before any test it is `0/0/<n>` (add "not started"). A skipped test is NOT completed and NEVER passed.
     For the static run n = the number of suites (`RESULT:` line); for pty runs n = the tests you named.
   - A MINOR change has no tests (see below): deliver with `<task name> (tests: none needed, minor change)` and you are done; the loop stops here.
3. **Run the test** the decision matrix below picks, once.
4. **Red? Fix it on the BASE.** There is ONE working copy (the base). Fix the failing code THERE. Never patch the copy you already delivered, never stack a patch on a patch, never
   hand over a diff against an earlier delivery. Read the failing finding first. Then rerun the same command once.
5. **DELIVER AGAIN**: the whole current base (every changed file, not only the fix), the same `<task name>`, the new `x/y/n`, one line on what the fix was.
6. Repeat 4-5 until green. **Stop the loop and deliver as it stands** (with the honest status line and the names of the red findings) when you notice your budget or context
   running low, when a red finding survives 3 fix rounds, or when the cause is outside your change (then say so). A delivered copy with a true label is always better than a perfect copy that never arrives.

### The test folders (two, and only two)
```
tests/
  static/   the DEFAULT. Reads the code and the command maps, no terminal, no app start, no sleeps. All suites together: 30 s cold, about 1 s warm.
  pty/
    fast/   old shell tests and short real-terminal tests (menus/  terminal/  engine/).  Seconds to a few minutes each.
    slow/   long real-terminal tests (input/  apps/): mouse, paste, resize, transfers, GitHub, full find-replace.  Minutes each. Release time or the owner asks.
    lib/    shared helpers of the pty tests (ptyapp.py, vt.py, wait_lib.sh, e2e_common.sh, bg.sh, stresstest/).
    pty.list  every pty test: name | folder | timeout | command | needs
```
`bash tests/run.sh` (static) · `bash tests/run.sh pty fast [name..]` · `bash tests/run.sh pty slow [name..]` · `bash tests/run.sh pty list` · `bash tests/run.sh list` (the static suites).

### DECISION MATRIX — which test, decided by what you changed and what you need to know
The default is **static: about 95% of tasks end there.** Ask yourself one question: *can I find the cause, or confirm the fix, by reading the script files and the static findings?* Yes → static. No → pty.

| What you changed / what you need | Run | Why |
|---|---|---|
| **MINOR**: comments, descriptions, hint / help / prompt / message wording, labels, headers, footers, colours, spacing, renames of a key or alias (no new code behind it), README / llms*.txt / corpus notes, formatting, ANY group of these | **nothing.** Only the free checks: `bash -n <file>` (`python3 -m py_compile`, `node --check`), and `bash tests/pty/fast/menus/cmd_docs.sh --write` (a generator) if a command was added / renamed / re-described | nothing the app does has changed |
| **LOGIC, any size**: functions, conditions, parsing, a command / menu / key added, renamed or removed, a map or footer line, a handler, a loop that reads input, file operations, GitHub / network code | **`bash tests/run.sh`** (static), once | it checks wiring, maps, cc / footer truth, every menu's accepted words, undefined or dead functions, read loops and EOF, shell hazards, and replays the real app from a pipe (crashes, hangs, shell errors) |
| A **new command or menu** | write it in its definer / map / `cmd_def`, then run static | the static suites derive everything from the maps; there is no test file to write for it |
| A **new class of bug** you want guarded (a rule you just fixed) | add one `tests/static/t_<name>.py` (stable finding ids, baseline, under 1 s), register it in `tests/static/suites.list`, run static | one more suite, still no terminal |
| A bug you **cannot find by reading** the script files: timing, a race, redraw, cursor, terminal emulation, "works once then not" | **`bash tests/run.sh pty fast <name>`** the one covering test (see `pty list`), or write a pty test next to it | needs a live terminal |
| You **must see the screen**: layout, wrapping, colours, a screenshot to judge | **`pty fast`** (`vt.py` renders the screen; print the rows, do not paste logs) | needs rendered output |
| **Real terminal behaviour**: mouse, bracketed paste, resize, wide characters, loading bar timer, transfers, GitHub, install flows | **`pty slow <name>`** | cannot be simulated |
| **Release** or the owner says "full suite" | static, then `pty fast`, then `pty slow` | the owner decides |

Rules of the matrix:
- **Static first, always.** A pty test is justified in the delivery in one line: `pty: <why static cannot show it>`. No reason, no pty.
- Never run a pty test "to be safe", never widen the choice on your own, never run the whole of `pty slow` unless the owner says so. The owner's prompt wins ("no tests", "full suite").
- Unsure whether a change is minor or logic? Ask the owner in one line. Do not run tests to find out.
- Static runs are parallel and capped already: run `bash tests/run.sh` ONCE per round, not before and after, not again on green, not twice at once.
- The static output is at most 40 lines: one line per NEW finding (`known` findings are the owner's accepted baseline and are not yours). A new finding is yours: fix the code, or, if the finding is a
  false positive, fix the suite (and say so); never add it to a baseline.

### Never
- run tests before AND after a change, or again after a green result; run them "to double-check";
- rerun a whole tier after a red; add a `sleep`, a retry loop or a polyglot scan on your own;
- print whole test logs into the conversation (tokens are the owner's money);
- write a new pty test for something a static suite can check; add `sleep` to any test.

## The principle: dedupe. reuse. share. integrate

Every task starts from what already exists. Copied code drifts: one copy gets fixed, the others are forgotten, and regressions follow.
So before you create anything, work in this order:

1. **Search before you write.** Before writing any function, block, test helper or script, grep for code that already does the same or nearly
   the same (`grep -rn <keyword> script tests`: function names, distinctive commands, messages). When the task is a bug, also read the corpus
   index first (rule 5): `corpus/fixed_issues_index.jsonl`.
2. **Reuse as is; otherwise extend.** If an existing function does the job, call it. If it almost does, modify that function so every current
   caller behaves exactly as before (read all callers; for a logic change run the tests that cover them once, see "Workflow and tests" at the top) instead of writing a lookalike next to it.
3. **Share, never copy.** Logic needed in two places lives in ONE helper that both call (where helpers go: see check 5 below). Never paste a block
   and edit it.
4. **Dedupe whatever you meet.** If you find a duplicate, a near-duplicate (same logic, other names), drift (copies that now behave differently) or a
   regression, do not walk past it: merge it into one helper, prove old and new behave the same (run both and compare), and record it per rule 5.
   Less code, fewer places to forget.
5. **No regressions.** A reuse or dedupe change must not change behaviour. For a LOGIC change run the tests of the tier chosen in "Workflow and tests" ONCE, after the change and after delivering; a MINOR change runs none (see "Workflow and tests" at the top). Say in HOW DID YOU DEBUG what you ran and what you did not.

6. **Reuse a screen by feeding it DATA, and wire it; never print a lookalike list.** A screen that shows paths already exists: the folder view,
   and the recursive `==` filter that fills it. A new list of paths (Find hits and the replace preview already do; the Transfer and csv pickers
   still use `_pick_rows` and are to be moved) is shown by `_results_view` (`script/file/engine/ui/bashbasicsbyvk_results.sh`), which borrows that
   same viewport, header and footer. The caller only fills data
   (`_RES_LIST` = the paths, `_RES_NOTE[path]` = text after the name, `_RES_HDR` = what the nav-path row says, `_RES_APPLY` = an extra `a` key) and
   reads `_RES_CHOICE` / `_RES_PICK` back; Find's example is `_fr_results_fill` + `_results_view -p handle_selection`. When a caller needs one more
   thing, extend the shared function for every caller (rule 2); do not patch the caller's own printing. The steps of a switch:
   1. find what the target screen is made of (`grep` the strings the person sees: `more below`, `nav path`, the footer text) and call THAT;
   2. wire its typed words: a screen that reads words is claimed by a `.map` (rule 14) and every key its footer prints is really handled by its loop
      (`results` wires `cd`, `-u`, `=` like the main list; a footer must never advertise a blocked key); a key that exists only in one state
      (`a` in a preview) is declared with `_dp_when MENU WHEN_FN KEY` (see ADVERT below), so cc and the footer stop advertising it elsewhere;
   3. delete the old display in the SAME task, with its settings, descriptions and tests (rule 10): a capped list (`Results shown`) or a hand-made
      `printf "%2d) "` row is the old display, not a feature to keep;
   4. test it in the real app through a pty (`tests/pty/fast/menus/results/pty_test.py` is the template), at phone size for scrolling and tall for messages.
   A patch that only restyles the old print (BB-171120261240-1) is the thing this step exists to stop.

## The rules

1. **Every file lives under `script/`.** Every file under `script/` is named with the prefix
   `bashbasicsbyvk_` (py, c, h, txt, md, map, list, Makefile, extension-less python/node/bash tools, everything),
   with exactly two exceptions: the entry point `script/o`, and import files (rule 2).
   Directories are not prefixed. Do not create files anywhere else (no new files in the repo root).
   The only other exception is the agent-instruction files at the repo root: `AGENTS.md` (the one real copy of these rules) and the 3-line bridges that only point to it
   (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`). A bridge never holds a rule of its own: change the rule in `AGENTS.md`, nowhere else.
   The only exception is `corpus/` (rule 5): it sits at the repo root, is not installed, and its
   notes are named by timestamp (inside year/month/day folders), not `bashbasicsbyvk_`.
2. **`_3bvk_` is reserved for import files of stand-alone tools.** An import file is a `.sh` whose only job is to `source` other files,
   named `_3bvk_import_<topic>.sh` (e.g. `_3bvk_import_cmd_copy.sh`). The app itself has none: `o` loads through the load mapper (rule 13). Nothing else may start with `_3bvk_`
   — no helpers, libs, python modules or tools. Use `bashbasicsbyvk_` for those.
3. **`source` (and `.`) is allowed only in `o` (one line: the loader), in the loader `bashbasicsbyvk_loadmap.sh` (the one `source` that loads the app's files) and in the import files of stand-alone tools.** No other file may source anything:
   not libs, not other scripts, not config files. This keeps the dependency graph in one place and free of cycles.
   - An import file (stand-alone tools only) holds only plain `source "bashbasicsbyvk_x.sh"` lines.
   - If file A needs file B at load time (top-level code, or a variable B sets), B must be loaded *earlier*: the load mapper checks it (rule 13). A never loads B itself, except `_lm_need B` in a function that reads B's variables.
   - To load a new file: add ONE line to the load mapper (rule 13), nowhere else.
   - Config/data files (e.g. the settings file) are parsed as data (`_bvk_settings_read`), never sourced.
   - Stand-alone executables run as their own process (`script/cmd/*`) cannot inherit `o`'s
     functions. They may `source` exactly ONE thing: their own `_3bvk_import_cmd_*.sh`
     (plain `source` lines, no `_lt_*`, because loadtime is not loaded there). Never a lib directly.
   - **The Infinity Stones tools are NOT stand-alone.** They run inside the app (bashbasicsbyvk_infinity_run.sh): a bash tool is a
     function loaded by the load mapper and started with `_inf_sub` (its `exit` / `set -e` / `trap EXIT` end only the tool); a python tool is
     started with `_inf_py` and its questions are asked by the app (`bashbasicsbyvk_qbridge.py`), so the hint row, `cc`, the typed commands and
     `u` / `q` are the app's own. A new Infinity tool follows the same two paths; never `bash tool` / `python tool` from the menu.
4. **No `_core` / `_main` suffix unless it is really necessary.** Name a file for what it does
   (`bashbasicsbyvk_gitpush.sh`, `bashbasicsbyvk_recover`). `main` is only allowed as the name of the *main menu*
   (`bashbasicsbyvk_main.map`, `bashbasicsbyvk_maincommands.sh`).
5. **Use the corpus before you fix a bug; add to it after.** The corpus is the repo's memory of past fixes, written for humans and AI agents.
   - Layout: notes in `corpus/fixed_issues_ref/YYYY/MM/DD/DDMMYYYYHHMM.txt` (year, month, day folders, zero-padded), and one index,
     `corpus/fixed_issues_index.jsonl` (JSON Lines: one self-contained JSON object per line, so a grep hit is a complete record with its field names). Both sit at the repo root, outside `script/`; `setup.py` only globs `script/`, so they are not installed.
   - **BEFORE fixing any bug, open the index.** Filter by `issue_category`, `issue_type` and keywords
     (`grep -i <keyword> corpus/fixed_issues_index.jsonl`; by field: `grep '"issue_category":"Input & Paste"' corpus/fixed_issues_index.jsonl`;
     `jq` works too if installed), then read the notes in the `path` column: earlier patches for the same symptom, file or
     function, their causes, their lessons, and what else they touched. Your fix must keep every earlier fix in that area working.
     If a bug is a follow-up of an old one, say so in the new note and link the old `issue_id`.
   - **AFTER fixing**, write ONE note per task in the folder of the local date-time of the fix (e.g. 23 Oct 2026, 04:22 =
     `corpus/fixed_issues_ref/2026/10/23/231020260422.txt`; if that minute exists, use the next free minute; create folders as needed).
     Exactly these four sections, in this order, headings in capitals:
     `ISSUE IN BRIEF` (the issue in YOUR OWN words: what is wrong or wanted, where, and the symptom a future agent would see; 1-3 neutral sentences;
     no quotes of the user, no pasted screens, no story), `HOW DID YOU DEBUG` (what you read/ran and what each step showed),
     `CAUSE` (the root cause, not the symptom), `FIX` (files and functions changed, what changed, any lesson for similar code).
   - Several issues in one task: one file, the four sections repeated per issue with a number prefix (`1. ISSUE IN BRIEF`, `2. ISSUE IN BRIEF`, ...).
   - Say honestly in HOW DID YOU DEBUG if something was verified by reading only and not by running.
   - **Add one line per issue** to the index in the same change, appended at the end (date order). Each line is one compact JSON object, no
     spaces after `:` or `,`, UTF-8, keys in this order: `issue_id` = `BB-<note id>-<n>` (n = the issue's number in the note, 1 if single);
     `issue_category`; `issue_type`; `issue` = the same text as ISSUE IN BRIEF; `path` = repo-relative path of the note.
     Pick category and type from these lists; add a new value only when none fits, and add it here in the same change.
     - Categories: Input & Paste · Menus & Navigation · Command Map & Drift · File Transfer & Pending · Cloud Backend · Google Drive ·
       Platform Compatibility · Code Health · Repo Process & Docs · Data Safety
     - Types: Bug · Regression · Platform Bug · Data Safety · Performance · Resilience · Scalability · UX Change · Enhancement · Refactor · Not Reproduced
   - Old notes are history: do not rename or rewrite them (a new note that points to the old `issue_id` is how you follow up).
   - The naming checks below only scan `script/`, so they do not apply to `corpus/`; check 6 covers the corpus.

6. **Ask with the shared choice menu, and keep emoji off the line the caret sits on.** (Follow-up of `BB-211020261500-1`.)
   - **Typed prompts go through `_bvk_read` / `bashbasicsbyvk_ask`, never a bare `read` (rule 16).**
   - **No emoji in any `read ... -p` prompt**, and none in a variable that becomes one. A terminal and the width table can disagree about an emoji's
     width, and then the caret lands in the wrong cell on some devices; text without emoji cannot disagree. Emoji stay in headers, `echo` lines and menu icons.
     `tests/pty/fast/terminal/width` fails on one; the `read` shim also strips them at run time (`_bvk_noemoji`) as a net, never as the fix: write the prompt without them.
   - **A question with fixed answers is never a one-line `read -p "... (y/N): "` and never a hand-made key row (`c) copy   x) nuke   Enter) back:`).**
     Use `script/file/engine/ui/bashbasicsbyvk_choose.sh` (it is the Settings screen engine in a small box: same look, arrows, touch/click, `u`/`q`):
     `_bvk_yn VAR "Question" [-c]` gives `y`/`n`/`c` (`-c` adds the Cancel row; `c` and `x` both cancel). **A yes/no question never has a default**: nothing is highlighted and a bare Enter does nothing, the person must answer; `_bvk_yn` enforces it itself and ignores any `-d` it is given (do not write one). `_bvk_menu VAR [-t Title] [-i Icon] [-q Question] [-d key] [-k] [-m] key:Label ...` for one-of-many, many-of-many (`-m`) and actions. **A tool that runs as its own process (bash or python) asks yes/no through `bashbasicsbyvk_yn "Question?" [-t Title] [-i Icon]` (exit 0 yes, 1 no, 2 no answer; python: `import bashbasicsbyvk_yn as yn; yn.ask(...)`): never `read -p "(y/n)"`, `input("(y/n)")` or "type yes". A plain line may remain only as the fallback beside it; `tests/pty/slow/input/yn/yn_test.py` lints for it.**
     Both return 1 and leave VAR empty when the user backs out (`u`/`q`): stop the flow, as for every prompt. Keep the old `case` on the answer; the keys are `y n c`.
   - **The shape** (do not invent another): `{emoji} Title`, a rule, numbered rows, a rule, the common footer `u) Up   q) Quit   h) Home   cc) Cheat codes`, an optional second line with the answer keys
     (`y) Yes   n) No   c/x) Cancel`), then `Select:`. Rows are `N) [ ] Label`; the answer is a number, a tap or click, or the arrows + Enter. Only a yes/no box also takes its printed keys (`y n c x`) + Enter.
   - **A numbered choice needs no second way to answer it.** Never add a typed word, letter or printed key line for the rows of a pick-one or many-of-many menu (`usd`, `sane`, `c) copy`, `r) restore`): the row number already answers it, and a second printed key is a duplicate that costs footer space, tests and upkeep for nothing. The `key` in `key:Label` is only the value `_bvk_menu` hands back to the code; `_bvk_menu` does not accept or advertise it typed (only `--yn` boxes do). Do not add `-k`, aliases (`key|alt`) or a second footer line to a menu that has numbered rows. Follow-up of `BB-251120261625-1`.
   - **Marks: `[o]` radio = exactly one is on (one-of-many, the mark follows the highlight); `[x]` checkbox = any number can be on (many-of-many); `[ ]` off.**
     Settings rows use the same marks (`_st_add r` radio, `_st_add t` checkbox). Never use `[x]` for a radio or `[o]` for a checkbox.
   - **A stand-alone tool (rule 3) uses the SAME menu as the app, through its doors (rule 18): `bashbasicsbyvk_yn` (yes/no), `bashbasicsbyvk_choose` (one-of-many / many-of-many), `bashbasicsbyvk_ask` (typed line).** It never draws its own menu, rows, rules or footer. A dependency question still goes through `bashbasicsbyvk_deps.sh` (rule 12). Any other plain prompt of such a tool has no emoji. A new test goes in `tests/pty/slow/input/choose`.

7. **Never wire a loading bar by hand: smartload draws it.** (`script/file/engine/ui/bashbasicsbyvk_smartload.sh`; same idea as smartmenu.)
   - Wait time > loading bar. A wait starts at the person's Enter / tap (`_lt_enter`) and ends when the next prompt is up (`_lt_ready`, the `read` shim, or an engine about to
     draw a screen: `_st_draw`, `_vp_render_fresh`, `_cm_text_read`). If it lasts more than 0.5 s and the screen is quiet, the bar appears by itself ON the cursor's own row, in the cursor's place (the cursor is hidden while it shows; never a row below it);
     `echo` / `printf` / `clear` wipe it before they write and restart its clock. So a new command, menu or function that waits gets its bar with **no line of code**.
   - Do NOT add a `_lb_run`-style wrapper, a spinner, `\r` progress text or a bar of your own around a call that may be slow. (The old `bashbasicsbyvk_loadingbar.sh` and every `_lb_*` call are gone.)
   - Engine code that writes the terminal with `builtin printf` during a wait (moving the cursor, redrawing) calls `[ "${_SL_WANT:-0}" = 1 ] && _sl_pulse` first. Code that draws its OWN progress
     (a transfer bar, a tool with its own bar) wraps it in `_sl_hold` / `_sl_release` (or runs with `BVK_GD_BAR=0`-style switches when it is a separate process).
   - **Loading bar and progress bar are two different things, and the progress bar always wins.** The loading bar is smartload's bouncing block for a wait of unknown length. A progress bar
     is a tool's own bar with real numbers (`[███░░] 45%  12.3/27.4 MB  3.1 MB/s  ETA 5s  3/7`: the fileapi pack, send, fetch and pending transfers, rclone, git ...). They are never on the screen together: when a progress bar starts, a loading bar
     that is showing is wiped and none is drawn until it ends. Every fileapi call that lets a transfer tool draw its bar sits between `_bb_progress_begin` and `_bb_progress_end` (one shared pair in
     `bashbasicsbyvk_fileapi_lib.sh`, outside any `$( )`); `tests/pty/fast/terminal/smartload` fails on a transfer call that is not wrapped.
   - Full-screen programs (nano, vim, less, htop ...) are not a wait: smartload wraps those names (end of `bashbasicsbyvk_smartload.sh`) so no bar is drawn while they run; a new full-screen tool adds its name to that list, never a hand-made `_sl_hold`.
   - A child program that DRAWS on the terminal (its own prompt or progress bar: gitpush, bvk-xfer, rclone, git ...) is not a wait: smartload sees it by itself (`_sl_owned`, via /proc) and draws no bar while it runs.
     The test is positive: the child is exec'd, its stdout or stderr is the terminal AND it has written something (wchar in /proc/<pid>/io); a silent helper (python, node, a Go engine that is only computing) is still a wait and gets the bar. Never add a tool's name to a list to "fix" this. Never put `exec ... 2>/dev/null` in app code: with no command, `exec` makes the redirect permanent (stderr = prompts and tool progress bars).
   - `VK_SMARTLOAD=0` turns it off, `VK_SMARTLOAD_GRACE_MS=500` sets the delay (default 0.5 s). **One delay for everything**: Enter, click, Space, Left / Right, the app start and a program's start-up (`_sl_launch`) all use it; never add a "light" or "slow" variant of it. No terminal (pipes, tests) = every call is a no-op.
   - **Every `_lt_enter` site names what was chosen** (2nd argument: the row's name; `_sl_label` strips colours, the `3)` number and the `[ ]` mark), so the bar never says just "Working" when a name is known.
   - **Why did it show / not show?** `VK_SMARTLOAD_DEBUG=1` (file: `VK_SMARTLOAD_DEBUG_FILE`, default `$TMPDIR/bvk-smartload.log`) logs one line per decision: the Enter that opened a wait and who called it, an Enter that was ignored (subshell, hold), what closed the wait, the child that owned the terminal, when the bar was drawn and wiped. Read it before changing any smartload rule.

8. **Every Settings screen and row explains itself.** `script/file/settings/core/bashbasicsbyvk_settings_desc.sh` holds one plain-words text per screen and per row
   (key `<screen title>|<row tag>`, `<screen title>|*` for the screen; `<parent>›<title>|<tag>` when two screens share a title). `_st_draw` shows the text of the screen
   in the header (between the title and the first rule); the text of a row is read with `?` on the highlighted row. A new Settings row or screen adds its line there, written for a person who has never heard of the feature.

9. **A list that exists twice is generated from one source, and a test fails when a copy goes stale.** What is generated today (add to this list, do not hand-copy):
   - **Footer keys.** A generic key (`u` `q` `z` `rf`) is passed to `_mc_footer` / `_mc_footer_register` as the BARE key and takes its label from `_MC_KEYLABEL`
     (`script/file/engine/ui/bashbasicsbyvk_menuchrome.sh`). It is never written `key:Label`, in any spelling. A key that really means something else gets a NAMED variant in the same
     table (`u.up` = `u) Up`, `u.prefix`; `u` is ALWAYS `Up` and `q` ALWAYS `Quit`: no `Back`, no `Close`, no `Close settings`); the part after the dot is only a name. Menu-specific keys (`bk:Close`, `n:New profile`) stay `key:Label`. `tests/pty/fast/menus/cmd_drift.sh` fails on a retyped
     generic label, on an undefined variant, and on a footer key no command map wires. There is no exceptions list: a new meaning is a new table entry.
   - **ADF actions.** A `file` action registers with `_fx_adf_register_fx LABEL FN` (the tree path comes from the label), never with a typed `file/...` path. `tests/pty/fast/menus/adf_registry.sh`.
   - **The command reference.** `o --map-doc` prints it from `cmd_def`; `llms-full.txt` section 9 holds the pasted copy between `cmd-ref:start` / `cmd-ref:end`.
     After adding or changing a command run `bash tests/pty/fast/menus/cmd_docs.sh --write`. `tests/pty/fast/menus/cmd_docs.sh`.
   - **The CPU-to-binary mapping** (`uname -m` -> arm64 / amd64 / arm / 386; android / linux / darwin / freebsd) lives only in `_bvk_engine_target` (`engine/native/bashbasicsbyvk_engine_target.sh`). `setup.py` asks that function (it runs it with bash) to decide which binaries a wheel carries; it never repeats the table. `tests/pty/fast/engine/engine_target.sh`, `tests/pty/fast/engine/wheel_target.sh`.

10. **No dead files.** A file that nothing loads (not in the load mapper, rule 13, and not run as a process) is deleted, not left "untouched" or listed as legacy: `tests/pty/fast/menus/adf_registry.sh` has no allowlist, and a test with an exceptions list is where drift hides.
    A file that another file depends on loads that dependency itself or degrades without it (`settings_ui.sh` works without `settings_desc.sh`: stand-alone callers and tests source it alone).

11. **GitHub talks through ONE engine and ONE helper file.** (`fx → github → open github`, and the `-u` upgrade loop.)
    - All GitHub API / git work lives in `script/file/loops/iloop/fx/github_fx/gh/bashbasicsbyvk_github` (python); the screens in `.../open_github/bashbasicsbyvk_adf_github.sh` only ask and show.
      Parsing releases / tags / commits, tag order and body printing live in `script/file/functions/github/bashbasicsbyvk_ghlib.sh`, shared by the GitHub screens and `bashbasicsbyvk_upgrade.sh`: never parse the GitHub JSON a second time.
    - The GitHub screens follow rules 6-9 like every other screen: no hand-wired loading bar (a `git clone` that prints its own progress is wrapped in `_sl_hold` / `_sl_release`), bare generic footer keys (`rf`, `u`), `-d none` on every delete question.
    - The map of a loop the generator cannot read is `block()`, never "keep or block": a map line is a claim about the loop. A list screen that reads keys itself (`_st_run`) lets a typed word through `_st_cm_gate`, so the hint row, `cc` and Enter agree (`tests/pty/retired/cc_truth`).
    - Tests: `tests/pty/slow/apps/github/` (mock GitHub server, no network), `tests/pty/retired/cc_truth`. The upgrade loop's output must stay byte-identical to `tests/pty/slow/apps/github/fixtures/upgrade_golden.txt`.

12. **Every external dependency goes through ONE registry and ONE installer.** (`script/file/engine/deps/bashbasicsbyvk_deps.list`, `bashbasicsbyvk_deps.sh`, `bashbasicsbyvk_deps.py`.)
    - An outside program or package (curl, node, 7z, rclone, gh, a pip / npm package, a tz database ...) is declared ONCE, as a `D` line in `bashbasicsbyvk_deps.list`: how to detect it, its package name per package manager
      (termux apt dnf yum pacman apk zypper brew, pip, npm), what it is for. A menu / command / tool that needs it gets an `F` line (feature -> required / optional dependencies): that file IS the dependency map.
      Build-time toolchains (C compiler, make, Go) are not listed: they are compiled before distribution.
    - **Ask the engine, never roll your own.** In the app and in import-file tools: `_dep_need -c "what the person is doing" <feature|id>... || return` (menu: lists what is missing, yes/no, installs, re-checks);
      `_dep_have <feature|id>...` for a silent check (never installs; `_DEP_MISSING` says what). Stand-alone bash tools: `bashbasicsbyvk_deps.sh -c "..." <feature|id> || exit 1`.
      Python: `import bashbasicsbyvk_deps as deps; deps.ensure("feature", "?optional_id", context="...")`. A background job with no terminal never opens a menu: it uses `_dep_have`, or quiet mode (`-q` / `quiet=True`, only `auto` user-space pip packages).
    - **Forbidden:** a private `command -v X || echo "please install X"` that exits, a private `pkg install` / `apt install` / `pip install` / `npm install` / `npx --yes` recipe, a package-name table, a sentinel / retry file for installs, a hand-made "install now? y/n" prompt for a dependency.
      The old ones (pipboot, polyglot_bootstrap, gitpush's gh installer, the daemon's pip call, timezone's package table, the archive tool tables) are gone; do not bring one back.
      A tool may still PROBE with `command -v` to choose between alternatives it can work without (clipboard tools, `xdg-open` / `termux-open`), but a dependency it cannot work without is asked for through the engine.
    - A new dependency = one `D` line (+ one `F` line for the menu that needs it) + `bash tests/pty/fast/engine/deps/deps_test.sh`. A pip family (`tree_sitter_<lang>`) is a `G` line. A multi-step install is a `@recipe` in the engine, never a copy in the caller.
    - Scripted runs (CI, agents, e.g. the polyglot check above): `BVK_DEPS_ASSUME=yes` answers the menu, `BVK_DEPS_ASSUME=no` refuses, `--dry-run` prints the commands. The engine installs system packages in one call and pip / npm in parallel lanes.

13. **Every file passes through the load mapper; nothing is loaded outside it.** (`script/file/loadmap/`: `bashbasicsbyvk_loadmap.list`, `bashbasicsbyvk_loadmap.sh`, `bashbasicsbyvk_loadmap_gen`, generated `bashbasicsbyvk_loadmap_stubs.sh`.)
    - **Why:** first paint used to wait for ~130 files that the first screen never calls. `o` now sources only the loader, which reads `bashbasicsbyvk_loadmap.list` BEFORE anything else is loaded and loads only what it says. The first-paint time is the product: every byte in `[fg]` costs it.
    - **Three sections, one line per file** (`file|needs|with|note`, the note says WHY it sits there):
      `[fg]` loaded before the first paint, in the order listed: ONLY what the first screen needs.
      `[bg]` loaded after the first paint, one file at a time, only while no key is waiting (`_lm_idle`, called by `o` before every prompt); a key stops it at once. `@call fn args` lines run a function after the files above them (start-ups that must not delay the paint: the usage ping, the snapshot daemon).
      `[no]` never loaded unless something calls one of its functions: every function of a `[bg]` / `[no]` file is a generated one-line stub; the first call loads the file (and the files it needs) and runs the real function. Python / C / data / stand-alone commands and `*.map` files are `[no]` too (they are run or read, never sourced).
      "Background" is idle time inside the same shell: bash cannot hand functions from a child process to its parent, so a real background process cannot load a library.
    - **A new file = one mapper line.** Default to `[no]`; use `[bg]` for what the person will probably use in the first seconds (Enter on a file, a common key); `[fg]` ONLY if the first paint cannot happen without it. Say why in the note. A new helper that an `[fg]` file calls goes to the file that already is `[fg]` only if it is needed before the paint; otherwise it lives in a `[bg]` / `[no]` file and its stub loads it on the first call.
    - **After any change** (a file added / renamed / moved between sections / deleted, a function added / renamed, a line moved) run `python3 script/file/loadmap/bashbasicsbyvk_loadmap_gen --write`, then `--check` (or `bash tests/pty/fast/engine/loadmap.sh`). The check fails on: a file without a line or a line without a file; an `[fg]` file that needs a later or non-`[fg]` file (top-level call, a variable the other file sets, a redefined function); a `[bg]` file that needs a `[no]` file; a stale stubs file; a top-level `declare` without `-g` (a file loads inside a function: a plain `declare` would stay local).
    - **Code in `[fg]` never assumes a `[bg]` / `[no]` variable exists:** read it as `${VAR:-default}`, or call a function of that file first (its stub loads it), or put `_lm_need bashbasicsbyvk_x.sh` at the top of the function. Guard optional features by their own flag (`[ "${_GD_ACTIVE:-0}" = 1 ] && _gd_...`), never with `declare -F` (a stub makes `declare -F` true and the call would load the whole file).
    - **Registries and wrappers:** a file that fills a registry another file reads (the `adf_*` files fill the fx menu) is listed in that file's WITH column; a file that wraps another file's functions at load time (`gdrive.sh`) lists the wrapped files in NEEDS (a dependency no text search can see).
    - **The stubs are sourced at the end of `[fg]`, before the first paint.** `[fg]` code calls functions of `[bg]` / `[no]` files at run time (the first paint of a folder with a `.shortcut` calls `_shortcut_read_field`, `transfer.sh`); a call with no stub yet is `command not found`. `tests/pty/fast/engine/loadmap.sh` checks it.
    - `BVK_LOADMAP=all` loads everything before the first paint (the old behaviour): use it to tell a load-order bug from a real one. `loadtime` shows every load, before and after the paint.
    - **Measure it:** `loadtime` (rule 7's recorder) and the `[fg]` percentage in `bashbasicsbyvk_loadmap_gen --report`. Before you move a file to `[fg]`, say what needs it before the paint.

14. **Every screen that reads a typed word is WIRED; a typed word always goes through the command layer.** (`script/file/cmdmap/`, `script/file/engine/commands/bashbasicsbyvk_cmdmap.sh`, `tests/pty/fast/menus/xui_wiring.sh`.)
    - The standard: a plain word is a command (`q`, `s`, `h`, the screen's own `r`, `rf` ...); `@word` is that text, typed literally. Inside a menu the screen's own key beats the main command of the same name; inside a question the main command wins and a blocked one cancels the flow.
    - **Which table applies is decided by the function that reads the word, by NAME** (`_cm_ctx_find`: the `@func` of a `.map`, or `xui_<prefix>` for a `_xui_loop` screen). A screen no map claims does NOT fail loudly: it silently inherits another table (`xui`, or `main`) whose rules were written for other screens, so its own keys are blocked ("Invalid command: r - not available in xui") or swallowed (`rf` = the main redraw, the screen never reloads). `o --map-lint` cannot see it (it only reads maps that exist). That is how `cfw`, `gdp`, `cs_pp`, `ct`, `ru` stayed broken.
    - **A new `_xui_screen X` + `_xui_loop` handler = a new `script/file/cmdmap/xui_X/` in the same change**: copy `xui_ghr` (`bashbasicsbyvk_xui_X.map` + `bashbasicsbyvk_xui_Xmenucommands.sh`), one `cmd_def` line per key the handler (`_X_cmd`) accepts or the footer prints (`local`, kind `exact` / `prefix`), two loadmap lines (`[no]`), `bashbasicsbyvk_loadmap_gen --write`. `bash tests/pty/fast/menus/xui_wiring.sh` fails on a screen without a map and on any own key that does not resolve to the screen. Never "keep" an own key by hoping the parent allows it.
    - **A `cmd_fn` of `_st_run` (the 5th argument) returns 1 for every word it does not own**, so `_st_cm_gate` (or `_bc_word` in the choice boxes) decides. A `cmd_fn` that returns 0 for "anything else" swallows commands: the hint row (`_cm_hint`) says "s -> Settings" and Enter drops it (that was `_bc_cmd`). `tests/pty/slow/input/choose/typed_test.py` types a command into a question.
    - A typed-word prompt is read with `_bvk_read` (rule 16): one editor for all of them.
   - Do not give a list screen its own `read` / `case` for typed words, and do not add a second dispatcher: the gates are `_cm_gate_choice` (list loops), `_cm_gate_sm` (smart menus), `_cm_gate_dispatch` (text, boxes), `_st_cm_gate` (`_st_run`). A new kind of screen uses one of them.

## Tests: seconds, not half an hour (the rules the owner and the agents framed)

A bug fix takes seconds; its tests must too. **The static suites (`tests/static/`) are the way: read the code, no terminal, no sleep.** The pty tests (`tests/pty/`) are the exception for what
only a live terminal can show (decision matrix at the top: "Workflow and tests").

**Running (agents follow this, do not improvise).**
- `bash tests/run.sh` = the static suites: structure (maps, `cmd_def`, handlers), lint (undefined and dead functions, syntax, hand-drawn menus), footer, intent (every word of every menu through the real
  resolver: valid result, garbage, case, hints), arms (what each loop handles vs cc and footer), readloop (a prompt in an endless loop must leave on EOF), shell (word-splitting hazards), advert (registry unit),
  replay (the real app with stdin from a pipe: crashes, hangs, shell errors). Findings have stable ids; those in `tests/static/baseline/<suite>.txt` are `known` (the owner's accepted drift), the rest are `NEW` and yours.
- `bash tests/run.sh pty fast|slow [name..]` runs pty tests from `tests/pty/pty.list`; `pty list` shows them. A pty test that cannot run here (needs `tmux`, node, the `../fileapi` repo) is printed as
  **SKIP and counted as NOT verified**; say so. Never report a skip as a pass. `tests/pty/known_failing.txt` lists pty tests that were already red; a failure not listed there is yours.
- Long commands: never `sleep 600` (or any `sleep` over 30 s). `bash tests/pty/lib/bg.sh start <name> <command...>` runs it in the background; `bg.sh wait <name> [max-secs]` returns THE MOMENT it ends.

**Writing a STATIC test (the default).**
1. Put it in `tests/static/t_<name>.py`; report through `lib/bvk.py` `Report` (stable finding ids `kind:where:what`, `R.check()` per thing checked, `R.add(id, text)` per finding, `sys.exit(R.finish())`).
2. Read the data, never start the app per check. Per-map resolver answers come from `lib/dump_resolve.sh` through `bvk.dump_all` (cached per map hash). A scripted run of the real app goes through
   `t_replay.py` (stdin from a pipe: one line per prompt, EOF = `q`).
3. Under 1 s warm, under 10 s cold. Register it in `tests/static/suites.list`. A finding that is a false positive means the suite is wrong: fix the suite, not the baseline.
4. A test must be able to fail: after writing one, break the code on purpose, see it go red, restore. State in HOW DID YOU DEBUG that you did.

**Writing a PTY test (only when the decision matrix says so).**
1. **Wait for a condition, never for a time.** bash: `source tests/pty/lib/wait_lib.sh`, then `wait_until <secs> "<what>" <cmd...>`, `wait_file`, `wait_gone`, `wait_port`, `wait_grep`, `wait_count`, and for
   tmux `tmx_start`, `tmx_wait`, `tmx_line`, `tmx_do`, `tmx_until`. python/pty: `tests/pty/lib/ptyapp.py` (`PtyApp`): `a.wait(cond)`, `a.wait_text(t)`, `a.send(keys, until=cond)`, `a.settle()`; the app is ready when it
   shows its prompt, not after 4 s. Do not write a new pty/VT driver: use `PtyApp` and `tests/pty/lib/vt.py`.
2. **A timeout is a failure with evidence** (what it waited for, what was on screen). Never `sleep` then assert; never a retry loop that hides a failure.
3. **No sleep in tests.** `tests/pty/fast/engine/lint_waits.sh` rejects `sleep N` with N > 0.1, `time.sleep`, and blind `pump(N >= 0.5)`. The only allowed wait is one that IS the behaviour under test, marked
   on its own line `# lint-wait-ok: <why>`.
4. **Real tests, not name-sake skims.** Keep every assertion; speeding up means changing how it waits, never what it checks.
5. **Find files by name** (`bvk_need <basename>` in bash, `find_script(root, name)` in python): files move between folders.
6. **No network, no real clock ticks.** Mock servers, `touch -d`, pre-marked telemetry (`PtyApp.seed_telemetry`).
7. **Start the app once per test file when you can.**
8. **Register the test** in `tests/pty/pty.list` (name, folder, timeout, command, needs) and file it under `tests/pty/<fast|slow>/<topic>/` (fast: menus, terminal, engine; slow: input, apps). Paths inside a pty test are
   relative to its own location or found by name, never hard-coded from the old `tests/` layout. Helpers shared by pty tests live in `tests/pty/lib/`; grep before writing another.

## How the install works (why names matter)

`setup.py` installs every file under `script/` **flat** into one `bin/` directory that is on `PATH`
(only `*.txt`/`*.xlsx` go to the data dir; `bvk-ls/` is build-only). So:
- **Every basename must be unique across all of `script/`** (that is why the prefix exists).
- Files are found by bare name (`source "bashbasicsbyvk_x.sh"`, `command -v bashbasicsbyvk_x`), never by relative path.
- The command map finds `*commands.sh` / `*.map` by those suffixes: keep `bashbasicsbyvk_<menu>.map` and
  `bashbasicsbyvk_<menu>menucommands.sh`. `bashbasicsbyvk_mapgen` writes exactly those names.
- Built `bvk-<engine>-<os>-<arch>` binaries (engines `ls`, `fr`, `xfer`; os `android linux darwin freebsd`; arch `amd64 arm64 arm 386`) are build output, not source: they keep that name (`setup.py`, `MANIFEST.in`, health check match it).
- **A wheel carries the binaries of ONE machine.** pip builds the wheel on the machine it installs to; `setup.py` keeps only that machine's three binaries and tags the wheel `py3-none-<platform>` (never `any`, so pip's wheel cache cannot hand it to another CPU / OS). `BVK_TARGET=<os>-<arch>` builds one for another machine (CI). When an install is carried to a different machine, `_bvk_engine_heal` (`engine/native/bashbasicsbyvk_engine_heal.sh`, called from `o`) offers a reinstall that builds fresh. `tests/pty/fast/engine/wheel_target.sh`, `tests/pty/fast/engine/engine_heal.sh`.

## When you add, rename or delete a file

1. Pick the folder by feature, name it `bashbasicsbyvk_<what_it_does>.<ext>`.
2. If it is shell code (`*.sh`) `o` may need, add ONE line to the load mapper (rule 13) and run `bashbasicsbyvk_loadmap_gen --write`; every other file (python, data, tools) gets a `[no]` line. Do not source it anywhere else.
3. When renaming: grep the old name across the WHOLE repo (script/, tests/, README, llms*.txt, SECURITY.md, setup.py,
   MANIFEST.in, python `import`s, comments, user-facing messages) and fix every hit. Python modules are imported by
   their file stem, so the import lines change too.
4. Run the checks below before you finish.

```bash
# 1. naming: nothing but o, bashbasicsbyvk_* and _3bvk_import_*.sh under script/
find script -type f ! -name 'bashbasicsbyvk_*' ! -name '_3bvk_import_*.sh' ! -path script/o
# 2. _3bvk_ only for import files
find script -name '_3bvk_*' ! -name '_3bvk_import_*.sh'
# 3. source only in o, the loader and import files (stand-alone entry points that source their own import file are filtered out)
grep -rnE '(^|[;&|({]|[[:space:]])(source|\.)[[:space:]]+["$]' script | grep -vE '^script/o:|_3bvk_import_|bashbasicsbyvk_loadmap.sh:'
# 7. the load mapper: every file mapped, no impossible [fg], stubs current (rule 13)
python3 script/file/loadmap/bashbasicsbyvk_loadmap_gen --check
# 4. no basename collisions, no stale names
find script -type f -printf '%f\n' | sort | uniq -d
grep -rnI '_3bvk_' script tests setup.py MANIFEST.in README.md | grep -v '_3bvk_import_'
# 5. ONLY when the prompt asks to dedupe / find duplicates (never as part of an ordinary fix or feature): duplicate-function candidates (polyglot: parses the code, finds renamed and cross-language copies too) — prints clusters, writes nothing into the repo
PYTHONPATH=script/file/engine BVK_DEPS_ASSUME=yes python3 script/file/infinity/tools/polyglot/bashbasicsbyvk_polyglot . --no-xlsx --plain --exclude sample_project -o /tmp/polyglot_report.json
# 8. no bare typed-line read (rule 16); also part of `bash tests/run.sh pty fast`
python3 tests/pty/slow/input/prompt_template/read_lint.py
# 6. corpus index: valid JSON lines, unique ids, every line's note exists, every note has a line, note sits in its YYYY/MM/DD folder
python3 - <<'EOF'
import glob, json, os
R = [json.loads(l) for l in open('corpus/fixed_issues_index.jsonl', encoding='utf-8') if l.strip()]
P = {r['path'] for r in R}
n = lambda p: os.path.basename(p)[:-4]
print([r['issue_id'] for r in R if sum(x['issue_id'] == r['issue_id'] for x in R) > 1],
      [p for p in P if not os.path.isfile(p)],
      [p for p in glob.glob('corpus/fixed_issues_ref/*/*/*/*.txt') if p not in P],
      [p for p in P if p.split('/')[-4:-1] != [n(p)[4:8], n(p)[2:4], n(p)[0:2]]])
EOF
```
Checks 1-4, 6 and 7 are cheap: run them whenever you add, rename or delete a file or a note. Checks 1-4 must print nothing; check 6 must print `[] [] [] []`. **Check 5 (polyglot) is NOT part of the routine run**: it scans the whole repo (and installs numpy / tree-sitter on first run), so on an ordinary job it costs minutes for nothing. Run it ONLY when the prompt asks to dedupe, find duplicates or clean up copies; an ordinary job covers rule 1-4 of the principle with `grep -rn <keyword> script tests` instead (search before you write). When it IS asked for: Check 5 lists CANDIDATES, not proven copies: polyglot is NOT a 100% reliable
mechanism (it can miss real copies and flag look-alikes). Run it before and after your dedupe change, read every cluster your change touches or adds, and say
in HOW DID YOU DEBUG how you judged each; your change must not add a cluster that is a real copy (the clusters already there are not yours to fix
unless the task says so). It asks the central installer for numpy / tree-sitter on first run (`BVK_DEPS_ASSUME=yes` answers the menu in scripted runs, `--no-install` to forbid). If it finds a real copy, do NOT edit the copies in step: move the code into ONE helper
that every place calls (a function in a lib that `o` / an import file loads earlier; for node tools `bashbasicsbyvk_staging_jslib.js`, found
through `_bb_jslib`; for tests `tests/pty/lib/e2e_common.sh`, `tests/pty/lib/wait_lib.sh`, `tests/pty/lib/ptyapp.py`). Before you write a block that looks like one you have
seen elsewhere, grep for the helper first.

15. **`u` is "go back ONE step", everywhere.** (`script/file/engine/ui/bashbasicsbyvk_menuchrome.sh`: `_mc_steps`, `_mc_read`; `bashbasicsbyvk_cmdmap.sh`: `_CM_BACKED`; `tests/pty/slow/input/nav_back/`.)
    - `u` at a prompt cancels only that prompt (empty answer, no abort flag). `_mc_read` returns 1 for back and 3 for cancel / EOF; `_mc_select`, `_mc_text`, `_mc_review` pass it on. A blocked command still aborts the whole flow (`_CM_ABORT`).
    - **A flow with more than one question runs its questions with `_mc_steps`** (rc 1 = the question before; rc 1 on the first = the caller goes back one level; rc 5 = not applicable, skipped in the direction of travel). Never `|| return` after the first `u`.
    - A text prompt inside a flow is `read ... || return 3` and the parent menu loops on 3. Prompts with "Enter = default" never take the default on `u`.
    - The choice boxes (`_bvk_yn` / `_bvk_menu`, rule 14) follow the same contract: `u` in a box leaves that box only.

16. **ONE typed-line prompt: every place that waits for the person to TYPE calls the app's native prompt, never `read`, `input()` or `getpass` itself.** (`_bvk_read` in `script/file/engine/ui/bashbasicsbyvk_smartmenu.sh`; `bashbasicsbyvk_ask` + `bashbasicsbyvk_ask.py` for tools; `tests/pty/slow/input/prompt_template/read_lint.py`.) The key-loop files (viewport, browse, mouse, smartmenu, cmdmap, settings_ui, textedit, smartload, loadmap) are exempt for KEY reads only (`-n` / `-N` / `-t` / `-d` / `-u`); a `read ... -p` there is a typed line and must use `_bvk_read` (read_lint flags it).
    - **Why:** a prompt that calls `read` itself is a copy of the line editor. Every later improvement (selection, Shift / Ctrl keys, cut / copy / paste, undo, the cursor and highlight fixes, tap / click) lands in the ONE editor (`_cm_line_edit`, `bashbasicsbyvk_textedit.sh`) and so only reaches the prompts that go through it. The bare ones (`switch.sh`, `localhost`, `xtract` ...) stayed behind: that is the drift.
    - **In the app:** `_bvk_read VAR "Prompt: " [-i INITIAL] [-I] [-s] [-1]` (`-i` starting text, `-I` keep surrounding spaces = the old `IFS= read`, `-s` a secret, `-1` one key / "press any key"). It returns exactly what `read` returned (0 line, 1 back / EOF, 3 cancelled flow), so `|| return N` stays as it was. The prompt text has no emoji (rule 6) and is ONE argument: do not `printf` a prompt and then call a prompt-less `read`.
    - **In a tool that runs as its own process (rule 3):** bash `ans=$(bashbasicsbyvk_ask "Prompt: " [-i text] [-s])` (exit 0 line, 2 no answer, 3 not installed); python `import bashbasicsbyvk_ask as bvk; bvk.ask("Prompt: ")` (raises `EOFError` like `input()`). Same editor, so a change to it reaches the tool too. Fixed answers use the choice doors: `bashbasicsbyvk_yn` / `bashbasicsbyvk_choose` (rule 18).
    - **A raw `read` is allowed only** (a) in the key-loop files that ARE the editors (the `ENGINE_ALLOW` list in `tests/pty/slow/input/prompt_template/read_lint.py`: viewport, browse, mouse, smartmenu, cmdmap, settings_ui, textedit, smartload, loadmap); (b) when it reads DATA: `< file`, `<<< "$x"`, a pipe, a `while read` loop; (c) on a line that ends with `# bvk-read-ok: <why>` (the plain last fallback beside `bashbasicsbyvk_yn` / `bashbasicsbyvk_ask` for a broken install; a pager that reads nothing). A new marker needs a real reason, and a new `ENGINE_ALLOW` file needs the owner's say.
    - **New or changed prompt = call `_bvk_read` / `bashbasicsbyvk_ask` in the same change.** Never add `read -p` / `read -e` / `read VAR` / `input(` / `getpass` / `sys.stdin.readline` and never an `ENGINE_ALLOW` entry to make a lint go green. `python3 tests/pty/slow/input/prompt_template/read_lint.py` (in `run.sh fast`) fails on the first one.
    - **To change how typing behaves** (a key, a highlight, tap, paste): change the shared loop `_bvk_edit_run` (rule 17) or the key helpers (`bashbasicsbyvk_textedit.sh`), once. Never patch one prompt, and never write a second line editor beside it.

17. **ONE typed-line LOOP and ONE typed-line DRAWER: `_bvk_edit_run` and `_bvk_draw_input` (`script/file/engine/ui/bashbasicsbyvk_viewport.sh`) are the only code that reads keys for a typed line and the only code that paints it.** Main `Select:`, the item / group picker, smart menus, Settings (every screen and choice box) and the line editor behind `_bvk_read` / `bashbasicsbyvk_ask` all run them; each supplies only HOOKS (`_ED_REDRAW`, `_ED_CLICK`, `_ED_NAV`, `_ED_BYTE` ...: the contract is the comment above `_bvk_edit_run`). (Follow-up of rule 16: rule 16 unified the editing KEYS; this unifies the LOOP and the DRAWING around them.)
    - **Why:** the shared helpers (`_te_esc`, `_te_byte`, `_bvk_prompt_tap`, the paste helpers) were called by five hand-written loops and five draw functions, each wired by hand. A fix went into the loop the agent was looking at and the others drifted: the line editor never got tap, drew its suggestion BELOW the text, flattened pasted line breaks and had its own length-limit message. A static "is the function name in the file" test could not see it.
    - **Everything the person can DO to the typed line lives in the engine:** editing keys, bracketed + burst paste, the length limit, mouse reports on / off and the hand-back, the tap on the typed text, the idle tick, WINCH, raw keys and their teardown (it restores what it found, so a screen can run inside a screen). Add a behaviour THERE and every prompt has it. A loop keeps only what is its own (the list rows, the tabs, the footer, the Settings rows).
    - **Everything that is PAINTED of the typed line is `_bvk_draw_input`:** the cursor / selection, a long text as rows (line breaks are kept), the one scrolling row, the tap geometry. The suggestion sits ABOVE the prompt on every prompt: `_bvk_hint_area_on` reserves it, `_input_hint_sync` fills it, `_bvk_hint_paint` paints it. Settings builds its whole screen in one write and draws the prompt through `_bvk_draw_input` too.
    - **Never** write a `read -rsn1` key loop, call `_te_begin` with a registered editor, switch paste / mouse reports on (`_bvk_tty_raw` is the pair for leaving and re-entering raw mode), call `_bvk_row_multi` / `_te_cursor` / `_bvk_prompt_tap` outside the engine and the drawer. `tests/pty/slow/input/prompt_template/drift.sh` fails on it; its `PENDING` list is EMPTY and a new loop never goes on it.
    - **One notice, one wording:** a notice (too large, not available here) goes in the suggestion rows ABOVE the prompt on every prompt kind, with the sentence written once in `_bvk_too_large_text` (Settings builds its block in one write but puts its notice in that same row). The line editor always reserves the area, also without a command layer (`drift.sh` checks the wording).
    - **A typed-line answer is ONE line:** a paste with line breaks is SHOWN as rows (so nothing is lost on screen) but `_bvk_read`, `read -p` and `bashbasicsbyvk_ask` return it joined by spaces. A caller that wants the rows (a commit message) passes `-m` (`multiline=True` in Python). Never write `mkdir "$name"` on an answer that may carry a newline.
    - **Stand-alone imports** (`_3bvk_import_*.sh`) that source a file calling the engine must source `bashbasicsbyvk_viewport.sh` first (the deps installer failed for it).
    - **Chained questions in a stand-alone tool:** `bashbasicsbyvk_ask`, `bashbasicsbyvk_yn` and `bashbasicsbyvk_choose` take `-b` (u exits 4 = one question back; q / Ctrl-D exit 2; the `ask` door gives a secret `-s` the same two words). A tool that asks 2+ questions makes each one a step on `_mc_steps` (see `bashbasicsbyvk_gitpush`, `bashbasicsbyvk_delete`): never `|| die` after the first u, never read u as an answer. A Python tool uses `bashbasicsbyvk_ask.steps(...)` (`bashbasicsbyvk_choose.ask(..., back=True)` raises the same `Back`) (a step returns `False` when it had nothing to ask: `u` skips it; `Back` is an `EOFError`, so a tool that does not chain just leaves). A question that is asked again after `u` passes `-S` / `select=True`: its old answer starts selected, so typing `u` again replaces it. `drift.sh` `PENDING_CHAIN` is EMPTY and a new tool never goes on it. A tool with `set -u` sources only `bashbasicsbyvk_menuchrome.sh`, never the engine import (it hooks echo / printf).
    - **A new prompt kind = a new set of hooks around `_bvk_edit_run`**, plus one opener in `tests/pty/slow/input/prompt_template/prompt_test.py` (OPENERS), which runs the same selection / tap / suggestion-above / pasted-line-break checks on every kind. A prompt kind that has no opener there is not covered.
18. **ONE menu layout for the whole project. No hand-drawn menus, no exemptions for stand-alone tools, no legacy.** (`_bvk_menu` in `script/file/engine/ui/bashbasicsbyvk_choose.sh`; the doors `bashbasicsbyvk_choose` + `bashbasicsbyvk_choose.py`, `bashbasicsbyvk_yn`, `bashbasicsbyvk_ask`; `tests/pty/fast/menus/menu_templates.sh`, `tests/pty/slow/input/choose/`.) This rule REPLACES the old exemption that a tool running as its own process may draw its own menu.
    - **A question with fixed answers is asked through the menu, never printed.** In the app: `_bvk_menu` / `_bvk_yn` (rule 6) or the `_mc_select` family when the engine is loaded. In a tool that runs as its own process (bash or python, any file name, with or without an extension): `answer=$(bashbasicsbyvk_choose "Question?" [-t Title] [-i emoji] [-d key] [-k] [-m] [-b] key:Label ...)` (exit 0 answered and the key on stdout, 2 no answer, 3 not installed, 4 u with `-b`); `-m` boxes take the app's row grammar (`N` toggles; `1,3-5` · `a` · `a-2` set the selection, parsed by `parse_selection`): never a second syntax. python `import bashbasicsbyvk_choose as choose; choose.ask("Question?", [("1", "Label"), ...], default="1", multi=False, back=False)` (a key, or a list of keys with `multi=True`; raises `EOFError`, or `Back` with `back=True`). Yes/no stays `bashbasicsbyvk_yn`.
    - **Forbidden in any tool or menu:** `echo "1) ..."` / `print("  1 = ...")` option rows, a hand-made `Select ...:` / `Enter choice [1-4]:` prompt, a hand-drawn rule (`━━━`, `───`) around options, a hand-typed `u) Up   q) Quit   h) Home   cc) Cheat codes` row, and an `(a/b)` / `(1/2)` / `(t/l)` typed question. The look (header, rules, rows, footer, prompt) belongs to ONE place, so a change to it reaches every menu at once.
    - **The only plain `read` / `input()` left** is the last fallback for exit 3 (a broken install: no menu installed), marked `# bvk-read-ok: ...`.
    - **Legacy is rewritten, not kept.** A hand-drawn menu found in the code is migrated in the same change; the lint (`tests/pty/fast/menus/menu_templates.sh`, hand-drawn-menu check) scans every file under `script/`, also files with no extension, so none can hide. A file that really needs an exception is listed in `tests/known_failing.txt` WITH a reason and a date; it never gets a silent pass.
    - **A migrated tool keeps its flow:** the answer keys keep their old values (`1` `2` `t` `l`), so the code after the question does not change; `u` / `q` follow rule 15.

19. **The file picker's agent guide stays true: change anything in the file picker, update `script/agents_guide/filepicker.txt` in the same change.** (`script/agents_guide/filepicker.txt`; `tests/pty/fast/engine/filepicker_guide.sh`; `llms.txt` and `llms-full.txt`.) That file is what a user's own AI agent reads when the user says "use the bashbasicsbyvk filepicker instead of your native file picking tool or typing a path", so a stale guide makes someone else's agent call the picker wrongly.
    - **"Anything" is:** a command word or kind (`allow`, `block`, `.ext`, `files`, `folders`), how commands are joined or prefixed, an option of the shell door (`-s`, `-f`), an exit code, a Python function / argument / exception, a message the caller or the person sees, the keys typed inside the picker, or any change to `bashbasicsbyvk_filepicker`, `bashbasicsbyvk_filepicker.py`, `bashbasicsbyvk_qbridge.py`, `bashbasicsbyvk_pickfilter.sh` or the picker (`local_navigator`) in `bashbasicsbyvk_transfer.sh`. Update the matching sections of the guide (commands, doors, keys, procedure, examples, errors, limits).
    - **Every example in the guide is a rule string between `--- example: NAME ---` and `--- end example ---` and must be accepted by the real parser** (`_pf_parse`). `tests/pty/fast/engine/filepicker_guide.sh` loads each one, fails when a command word of the parser, an exit code or a Python name is missing from the guide, and fails when a path the guide names does not exist or when `llms.txt` / `llms-full.txt` stop pointing at the guide. A red guide test means the guide is stale: fix the guide, not the test.
    - **Keep `llms.txt` and `llms-full.txt` true** when the picker changes (the File picker section and the answer pattern), and add a corpus note like for any change.
    - **A guide-only edit is a MINOR change** (see the decision matrix): free checks only. A change to the picker's code is not minor; the guide test runs with it.
20. **Every icon is a 2-cell emoji: never use a 1-cell (text-default) emoji, with or without U+FE0F.** (Owner's rule, permitted in the conversation of 2026-11-28: a ⚙️ drew with a gap between the icon and the text on one device and not on another.)
    - **Why:** an emoji that is text-by-default (⚙ ☁ 🗑 🗄 ⚠ ℹ ✏ ✂ 👁 🖥 ▶ ◀ ⏸ ⏱ ↩ ...) is 1 cell in the width table (`_vp_cpw`) but some terminals paint it 2 cells wide once U+FE0F follows it (or 1 cell without), so the row, the highlight and the caret disagree. A wide emoji (`Emoji_Presentation=Yes`: 📁 📄 🧩 ✅ ❌ ⭐) is 2 cells everywhere, so the table and every terminal agree.
    - **Do:** pick an icon that `_vp_cpw` measures as 2 and write it bare (no U+FE0F). One space after it, like every other icon (`🔧 Executing`, not `⚙️  Executing`). Never "fix" a width problem by adding spaces or by teaching the width table that a text-default emoji is 2 cells.
    - **The replacements already made (use the same ones, do not invent a second set):** ⚙→🔧 · 🛠→🔨 · ⚠→❗ · ☁ and 🌤→⛅ · ☀→🌞 · 🗑→🚮 · 🗄→💾 · 🗂→📂 · 🗃→📇 · 🗜→📦 · ✏ and ✍→📝 · ✂→🔪 · ✉→📧 · ℹ→💡 · 👁→👀 · 🖥→💻 · 🛡→🔰 · 🛰→📡 · 🛋→🪑 · 🕊→🐦 · 🏷→🔖 · 🗺→🌍 · 🗝→🔑 · ✳→✨ · ▶ and ⏭→⏩ · ◀→⏪ · ⏸→⏳ · ⏹→🛑 · ⏱→⏰ · ⬇→⏬ · ⬆→⏫ · ⬅→👈 · ➡→👉 · ↩→🔙 · ↪→🔀. A new text-default emoji needs a wide one that looks closest; add the pair here.
    - **Not icons, so they stay 1 cell:** typographic marks inside text and aligned tables (→ ← ↑ ↓ ↳ ▲ ▼ ✓ ✗ ★ − ≥ ≤ ≠ ≈ ∩ ↔ ⇥ ↵ ⏎ ■ ©), the `▶ ` cursor mark in the smart menu and the `◀`/`▶` markers of the loadtime table (their columns are padded by hand), and an arrow inside a sentence (`name ↪ moved to x`).
    - **The check:** `tests/static/t_icons.py` (suite `icons`) fails on any text-default emoji or U+FE0F in `script/`; the few exceptions above are listed in it. `tests/pty/fast/terminal/width` and `cell_width.sh` keep their 1-cell fixtures on purpose: they test the width table, not the icons.

## FOOTER and CC HOUSEKEEPING — one common footer, one budgeted menu footer, cc in alphabetical order  (owner's rule, applies to every menu and every new one)
- **One common footer on every screen except the main menu:** exactly `u) Up   q) Quit   h) Home   cc) Cheat codes`. It is the first footer line, it costs nothing, and it comes from ONE place
  (`_MC_FOOTERS[std_nav]` in `script/file/engine/ui/bashbasicsbyvk_menuchrome.sh`, `_AD_STD_LINE` in `advert.sh` for the Settings engine). A screen never prints `Back`, `Close`, `Close settings`,
  `↑↓) Move` or any other wording of `u` / `q`, and never builds this line by hand (`_mc_footer_std`, `_tm_footer`, `_tpl_footer ID @std_nav` are the only ways).
- **A menu's own keys go on their OWN line(s) BELOW the common footer** (`ux) Export   ui) Import`). Budget per menu = 50 = five commands (`_AD_BUDGET`, cost 10 each); the highest PRIO wins, the rest stay in cc only.
  A footer key that is not specific to that menu is not advertised there.
- **General commands are never printed in a footer:** `rf`, `=` and `clr` (`_AD_GENERAL_KEYS` in `advert.sh`) work on every menu, so cc lists them and no footer does. Do not pass them to `_mc_footer_std` / `_tpl_footer`.
- **There is no second profile.** `std_nav_back`, `back_quit`, `back_only`, `file_menu`, `infinity`, `tabmenu_back`, the `-b` / `-l` flags, `_mc_std_items` / `_MC_STD` and the `_st_f1_custom` / `_st_f2_custom` overrides were
  deleted. Do not bring one back: a screen that "needs a different footer" gets its extra keys on the menu-specific line, not a new common line. The main menu (`browse_main`, `results_apply`, `browse_gd`) is the only other footer.
- **cc lists its rows in alphabetical order of the typed key** (`_ad_cc_rows`, byte order: `=`, `a-`, `a-2`, `b-`, `cc`, `clr`, `h`, `rf`, `u` ...). Never sort by declaration order, never add a hand-ordered cc.
- Changing any of this is a LOGIC change (static run). `tests/pty/fast/menus/menu_templates.sh` fails when a retired profile or override reappears.

## ADVERT — what a menu accepts is declared once; cc and the footer only render it  (script/file/engine/commands/bashbasicsbyvk_advert.sh)
- A menu DECLARES the commands it accepts into the registry: `_ad_open`, `_ad_accept KEY "desc" [PRIO] [SHOWN] [FREE] [SHORT]`, `_ad_free` (u q z rf h cc), or the helpers
  `_ad_from_map`, `_ad_from_cmdfn` (a screen's own typed commands: `"$cmdfn --cc"` prints `key|description|prio|shown|short`), `_ad_from_footer_items` (what `_mc_footer` is handed).
- cc lists EVERY declared command (cost 0). The footer prints the free keys + the declared commands the budget buys (cost 10 each, budget 50 per menu = 5 commands, highest PRIO first; `rf` `=` `clr` are general: cc only; cc rows are alphabetical).
  Neither looks anything up, parses a screen, or judges; the footer is always a subset of cc. A new command is added in ONE place: the menu's declaration.
- Never type a footer string by hand, and never add a typed command a menu takes without declaring it (a screen's `cmdfn` must answer `--cc`).
- DISPATCHER acceptor (same file): `_dp_accept MENU KEY HANDLER "desc" [FOOT_PRIO] [SHOWN] [WHEN_FN]` tells the dispatcher what a menu accepts (FOOT_PRIO > 0 = "show this in the footer"),
  `_dp_when MENU WHEN_FN KEY…` marks keys that exist only while WHEN_FN is true (a tab, a mode: fx's UDF tab), `_dp_accepts` is the judge, `_dp_run` runs the handler.
  cc and every footer pick these up through `_ad_from_dispatcher`. A state-dependent command MUST use `_dp_when`, otherwise cc advertises it where the menu refuses it.
- Tests (all menus, no terminal): `bash tests/run.sh` (static): `advert` = unit test of the registry, `footer` = every footer key is accepted and listed by cc, `arms` = declared (cc) vs handled by the loop vs footer
  (coverage = handled ∩ declared / handled × 100), `intent` = every word of every menu through the real resolver. The old live cross-check that typed into the real app (`advert_pty.py`, about an hour) is retired in `tests/pty/retired/`.
  The test must never type `kl` (`kill -9 -1`).
