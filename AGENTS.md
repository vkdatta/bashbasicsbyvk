# AGENTS.md — read this BEFORE doing anything else

Every AI agent working in this repo must read this file first and follow it exactly.
If a task seems to need breaking a rule, stop and ask the owner. Do not improvise.

## Workflow and tests (owner's rule: overrides every other mention of tests, tokens or "run" in this file)

**Why:** an agent can finish the work with 60% of its budget and then spend the rest on tests. If the budget runs out inside the tests, the owner gets NOTHING and waits for the
usage limit to reset. So: **deliver first, test after, deliver again after every fix. Tests must never be the reason the owner has no output.**

### The loop (every task, no exceptions)
1. **Do ALL the tasks.** Do not start any test yet.
2. **DELIVER NOW, before the first test.** The delivery is the finished work, complete and usable as it stands:
   - **In chat** (a chat window, or no shell on the owner's machine): put the result in the reply: send every changed file (or one archive) with the file-sending tool when you have one,
     otherwise paste each changed file in full (a diff only when the file is huge). A summary alone is not a delivery.
   - **In a terminal** (a CLI agent working in the repo): the files are already on disk in the working tree; leave them there (no commit, no push unless asked) and PRINT the summary to the terminal.
   - Either way, the first line is the **status line**: `<task name> (tests: x/y/n)`, then 3-6 lines: what changed, which files, which test tier runs next.
     `<task name>` = the name of the owner's original task / PR (or, if it had none, a 3-6 word name you pick); it stays the SAME on every later delivery.
     `x/y/n` = **x passed / y completed / n total** tests of the tier you chose. Before any test it is `0/0/<n>` (add "not started"). A skipped test is NOT completed and NEVER passed.
     Example: `Footer rename (tests: 0/0/22 not started)` ... later `Footer rename (tests: 21/22/22, github_ui failed)` ... finally `Footer rename (tests: 22/22/22)`.
     `bash tests/run.sh ...` prints this as its `STATUS:` line: copy it, do not retype it.
   - A MINOR change has no tests (see below): deliver with `<task name> (tests: none needed, minor change)` and you are done; the loop stops here.
3. **Run the tests** of the tier below, once, through `tests/run.sh` (parallel, see below).
4. **Red? Fix it on the BASE.** There is ONE working copy (the base). Fix the failing code THERE. Never patch the copy you already delivered, never stack a patch on a patch, never
   hand over a diff against an earlier delivery. Read the failing test's log first. Then rerun only the failed tests by name, plus `bash tests/run.sh for <files the fix touched>`;
   never the whole tier again. The status line counts the latest result of each test.
5. **DELIVER AGAIN**: the whole current base (every changed file, not only the fix), the same `<task name>`, the new `x/y/n`, one line on what the fix was.
6. Repeat 4-5 until `x = y = n`. **Stop the loop and deliver as it stands** (with the honest status line and the names of the red tests) when you notice your budget or context
   running low, when a red test survives 3 fix rounds, or when the cause is outside your change (then say so). A delivered copy with a true label is always better than a perfect copy that never arrives.

### What to test: decide by what you changed, before the first delivery
- **MINOR change: NO test. Not the fast tier, not `run.sh for`, not a baseline run.** Minor = nothing the app *does* changes, only what it *says* or how it *looks*: comments, docstrings,
  descriptions, hint / help / prompt / message wording, Settings descriptions, headers, footers, banners, labels, icons, spacing, colours, menu titles, command codes / aliases / cheat-code *names*
  or a command-map line that only renames or re-points a key (no new code behind it), README / llms*.txt / SECURITY.md / corpus notes, renames, moves, reformatting, and ANY group of these.
  Do only the free checks: `bash -n <file>` (`python3 -m py_compile`, `node --check`) on every edited file, in parallel; `bash tests/cmd_docs.sh --write` (0.4 s, a generator, not a test) if a
  command was added / renamed / re-described; checks 1-4 and 6 at the bottom if a file or note was added, renamed or deleted. Never call a minor change "tested" or "verified".
- **LOGIC change in up to 5 files under `script/`: the fast tier is enough: `bash tests/run.sh fast`.** Logic = behaviour can differ (function bodies, conditions, parsing, key / input / paste /
  mouse handling, file operations, transfers, GitHub / network code, the C engine, a bug fix). Files that only got minor edits do not count towards the 5.
- **REVAMP: more than 5 files under `script/` changed with logic: `bash tests/run.sh all`** (fast + slow). A mixed task is judged by its logic files.
- The owner's prompt wins: if it names tests, says "full suite" or says "no tests", do exactly that. An agent never widens the tier on its own, never "to be safe".
- Unsure whether a change is minor or logic? Ask the owner in one line. Do not run tests to find out.

### Run in maximum parallel
- Tests run ONLY through `bash tests/run.sh`: it runs one job per CPU, slowest tests first, each with a hard timeout. Never write `for t in ...; do bash $t; done`, never run tests one
  command after another, never lower `JOBS`. Do not run two `run.sh` at once either (they would fight for the same CPUs).
- The only exception is a test that really needs a sequential order (shared port, file or state): mark it `serial` in field 6 of `tests/tests.list` with the reason; `run.sh` then runs it
  alone after the parallel ones. Mark a test serial only when you have seen it fail in parallel, never "just in case".
- Other independent commands (`bash -n` on many files, greps) also go in ONE command, in parallel (`xargs -P`, or `&` and `wait`), not as a series of calls.

### Never
- run tests before AND after a change, or again after a green result; run them "to double-check", or because another rule says "run the tests that cover it" (that means a LOGIC change, once);
- rerun a whole tier after a red; add a `sleep`, a retry loop or a polyglot scan on your own;
- print whole test logs into the conversation: `run.sh` already prints only the failures with their last lines (tokens are the owner's money).

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

## The rules

1. **Every file lives under `script/`.** Every file under `script/` is named with the prefix
   `bashbasicsbyvk_` (py, c, h, txt, md, map, list, Makefile, extension-less python/node/bash tools, everything),
   with exactly two exceptions: the entry point `script/o`, and import files (rule 2).
   Directories are not prefixed. Do not create files anywhere else (no new files in the repo root).
   The only other exception is the agent-instruction files at the repo root: `AGENTS.md` (the one real copy of these rules) and the 3-line bridges that only point to it
   (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`). A bridge never holds a rule of its own: change the rule in `AGENTS.md`, nowhere else.
   The only exception is `corpus/` (rule 5): it sits at the repo root, is not installed, and its
   notes are named by timestamp (inside year/month/day folders), not `bashbasicsbyvk_`.
2. **`_3bvk_` is reserved for import files.** An import file is a `.sh` whose only job is to `source` other files,
   named `_3bvk_import_<topic>.sh` (e.g. `_3bvk_import_engine.sh`). Nothing else may start with `_3bvk_`
   — no helpers, libs, python modules or tools. Use `bashbasicsbyvk_` for those.
3. **`source` (and `.`) is allowed only in `o` and in import files.** No other file may source anything:
   not libs, not other scripts, not config files. This keeps the dependency graph in one place and free of cycles.
   - An import file holds only lines like `_lt_b "load x"; source "bashbasicsbyvk_x.sh"; _lt_e`, written in load order.
   - If file A needs file B, B must be loaded *earlier* by `o` or an import file. A never loads B itself.
   - To load a new file: add one line to the right `_3bvk_import_*.sh` (or to `o`, which keeps the global load order).
   - Config/data files (e.g. the settings file) are parsed as data (`_bvk_settings_read`), never sourced.
   - Stand-alone executables run as their own process (`script/cmd/*`, `bashbasicsbyvk_gitpush`) cannot inherit `o`'s
     functions. They may `source` exactly ONE thing: their own `_3bvk_import_cmd_*.sh` / `_3bvk_import_gitpush.sh`
     (plain `source` lines, no `_lt_*`, because loadtime is not loaded there). Never a lib directly.
4. **No `_core` / `_main` suffix unless it is really necessary.** Name a file for what it does
   (`bashbasicsbyvk_gitpush`, `bashbasicsbyvk_recover`). `main` is only allowed as the name of the *main menu*
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
   - **No emoji in any `read ... -p` prompt**, and none in a variable that becomes one. A terminal and the width table can disagree about an emoji's
     width, and then the caret lands in the wrong cell on some devices; text without emoji cannot disagree. Emoji stay in headers, `echo` lines and menu icons.
     `tests/width` fails on one; the `read` shim also strips them at run time (`_bvk_noemoji`) as a net, never as the fix: write the prompt without them.
   - **A question with fixed answers is never a one-line `read -p "... (y/N): "` and never a hand-made key row (`c) copy   x) nuke   Enter) back:`).**
     Use `script/file/settings/bashbasicsbyvk_choose.sh` (it is the Settings screen engine in a small box: same look, arrows, touch/click, `u`/`q`):
     `_bvk_yn VAR "Question" [-d y|n] [-c]` gives `y`/`n`/`c` (`-c` adds the Cancel row; `c` and `x` both cancel; `-d` is what a bare Enter answers, `n` unless the
     question is harmless; **`-d none` = no default at all**: nothing is highlighted and a bare Enter does nothing, the person must answer. Every question that deletes or removes something uses `-d none`, and `_bvk_yn` enforces it itself: a question whose text names a destructive action (delete, remove, nuke, clear, wipe, erase, discard, purge, overwrite, revoke, "for good", "can't be undone") gets no default whatever `-d` says (`_bvk_destructive`, checked by `tests/delete_confirm.sh`); `_bvk_menu VAR [-t Title] [-i Icon] [-q Question] [-d key] [-k] [-m] key:Label ...` for one-of-many, many-of-many (`-m`) and actions.
     Both return 1 and leave VAR empty when the user backs out (`u`/`q`): stop the flow, as for every prompt. Keep the old `case` on the answer; the keys are `y n c`.
   - **The shape** (do not invent another): `{emoji} Title`, a rule, numbered rows, a rule, `u) Back   q) Close`, an optional second line with the answer keys
     (`y) Yes   n) No   c/x) Cancel`), then `Select:`. Rows are `N) [ ] Label`; the answer is a number, a tap or click, the arrows + Enter, or the printed key + Enter.
   - **Marks: `[o]` radio = exactly one is on (one-of-many, the mark follows the highlight); `[x]` checkbox = any number can be on (many-of-many); `[ ]` off.**
     Settings rows use the same marks (`_st_add r` radio, `_st_add t` checkbox). Never use `[x]` for a radio or `[o]` for a checkbox.
   - A stand-alone tool (rule 3) cannot load the menu; its plain prompt still has no emoji. New code in the app uses the menu, and a new test goes in `tests/choose`.

7. **Never wire a loading bar by hand: smartload draws it.** (`script/file/engine/bashbasicsbyvk_smartload.sh`; same idea as smartmenu.)
   - Wait time > loading bar. A wait starts at the person's Enter / tap (`_lt_enter`) and ends when the next prompt is up (`_lt_ready`, the `read` shim, or an engine about to
     draw a screen: `_st_draw`, `_vp_render_fresh`, `_cm_text_read`). If it lasts more than ~2 s and the screen is quiet, the bar appears by itself ON the cursor's own row, in the cursor's place (the cursor is hidden while it shows; never a row below it);
     `echo` / `printf` / `clear` wipe it before they write and restart its clock. So a new command, menu or function that waits gets its bar with **no line of code**.
   - Do NOT add a `_lb_run`-style wrapper, a spinner, `\r` progress text or a bar of your own around a call that may be slow. (The old `bashbasicsbyvk_loadingbar.sh` and every `_lb_*` call are gone.)
   - Engine code that writes the terminal with `builtin printf` during a wait (moving the cursor, redrawing) calls `[ "${_SL_WANT:-0}" = 1 ] && _sl_pulse` first. Code that draws its OWN progress
     (a transfer bar, a tool with its own bar) wraps it in `_sl_hold` / `_sl_release` (or runs with `BVK_GD_BAR=0`-style switches when it is a separate process).
   - **Loading bar and progress bar are two different things, and the progress bar always wins.** The loading bar is smartload's bouncing block for a wait of unknown length. A progress bar
     is a tool's own bar with real numbers (`[███░░] 45%  12.3/27.4 MB  3.1 MB/s  ETA 5s  3/7`: the fileapi pack, send, fetch and pending transfers, rclone, git ...). They are never on the screen together: when a progress bar starts, a loading bar
     that is showing is wiped and none is drawn until it ends. Every fileapi call that lets a transfer tool draw its bar sits between `_bb_progress_begin` and `_bb_progress_end` (one shared pair in
     `bashbasicsbyvk_fileapi_lib.sh`, outside any `$( )`); `tests/smartload` fails on a transfer call that is not wrapped.
   - Full-screen programs (nano, vim, less, htop ...) are not a wait: smartload wraps those names (end of `bashbasicsbyvk_smartload.sh`) so no bar is drawn while they run; a new full-screen tool adds its name to that list, never a hand-made `_sl_hold`.
   - A child program that has the terminal (its own prompt or progress bar: gitpush, bvk-xfer, rclone, git ...) is not a wait: smartload sees it by itself (`_sl_owned`, via /proc) and draws no bar while it runs. Never put `exec ... 2>/dev/null` in app code: with no command, `exec` makes the redirect permanent (stderr = prompts and tool progress bars).
   - `VK_SMARTLOAD=0` turns it off, `VK_SMARTLOAD_GRACE_MS=2000` sets the delay (default 2 s). No terminal (pipes, tests) = every call is a no-op.

8. **Every Settings screen and row explains itself.** `script/file/settings/bashbasicsbyvk_settings_desc.sh` holds one plain-words text per screen and per row
   (key `<screen title>|<row tag>`, `<screen title>|*` for the screen; `<parent>›<title>|<tag>` when two screens share a title). `_st_draw` shows the text of the highlighted row
   above the suggestion row, `?` shows all of it. A new Settings row or screen adds its line there, written for a person who has never heard of the feature.

9. **A list that exists twice is generated from one source, and a test fails when a copy goes stale.** What is generated today (add to this list, do not hand-copy):
   - **Footer keys.** A generic key (`u` `q` `z` `rf`) is passed to `_mc_footer` / `_mc_footer_register` as the BARE key and takes its label from `_MC_KEYLABEL`
     (`script/file/engine/bashbasicsbyvk_menuchrome.sh`). It is never written `key:Label`, in any spelling. A key that really means something else gets a NAMED variant in the same
     table (`u.up` = `u) Up`, `u.prefix`); the part after the dot is only a name. Menu-specific keys (`bk:Close`, `n:New profile`) stay `key:Label`. `tests/cmd_drift.sh` fails on a retyped
     generic label, on an undefined variant, and on a footer key no command map wires. There is no exceptions list: a new meaning is a new table entry.
   - **ADF actions.** A `file_fx` action registers with `_fx_adf_register_fx LABEL FN` (the tree path comes from the label), never with a typed `file_fx/...` path. `tests/adf_registry.sh`.
   - **The command reference.** `o --map-doc` prints it from `cmd_def`; `llms-full.txt` section 9 holds the pasted copy between `cmd-ref:start` / `cmd-ref:end`.
     After adding or changing a command run `bash tests/cmd_docs.sh --write`. `tests/cmd_docs.sh`.
   - **The CPU-to-binary mapping** (`uname -m`, android / linux) lives only in `_bvk_engine_target` (`engine/bashbasicsbyvk_engine_target.sh`). `tests/engine_target.sh`.

10. **No dead files.** A file that nothing loads is deleted, not left "untouched" or listed as legacy: `tests/adf_registry.sh` has no allowlist, and a test with an exceptions list is where drift hides.
    A file that another file depends on loads that dependency itself or degrades without it (`settings_ui.sh` works without `settings_desc.sh`: stand-alone callers and tests source it alone).

11. **GitHub talks through ONE engine and ONE helper file.** (`fx → github_fx → open github`, and the `-u` upgrade loop.)
    - All GitHub API / git work lives in `script/file/loops/iloop/fx/github_fx/gh/bashbasicsbyvk_github` (python); the screens in `.../open_github/bashbasicsbyvk_adf_github.sh` only ask and show.
      Parsing releases / tags / commits, tag order and body printing live in `script/file/functions/bashbasicsbyvk_ghlib.sh`, shared by the GitHub screens and `bashbasicsbyvk_upgrade.sh`: never parse the GitHub JSON a second time.
    - The GitHub screens follow rules 6-9 like every other screen: no hand-wired loading bar (a `git clone` that prints its own progress is wrapped in `_sl_hold` / `_sl_release`), bare generic footer keys (`rf`, `u`), `-d none` on every delete question.
    - The map of a loop the generator cannot read is `block()`, never "keep or block": a map line is a claim about the loop. A list screen that reads keys itself (`_st_run`) lets a typed word through `_st_cm_gate`, so the hint row, `cc` and Enter agree (`tests/cc_truth`).
    - Tests: `tests/github/` (mock GitHub server, no network), `tests/cc_truth`. The upgrade loop's output must stay byte-identical to `tests/github/fixtures/upgrade_golden.txt`.

12. **Every external dependency goes through ONE registry and ONE installer.** (`script/file/engine/bashbasicsbyvk_deps.list`, `bashbasicsbyvk_deps.sh`, `bashbasicsbyvk_deps.py`.)
    - An outside program or package (curl, node, 7z, rclone, gh, a pip / npm package, a tz database ...) is declared ONCE, as a `D` line in `bashbasicsbyvk_deps.list`: how to detect it, its package name per package manager
      (termux apt dnf yum pacman apk zypper brew, pip, npm), what it is for. A menu / command / tool that needs it gets an `F` line (feature -> required / optional dependencies): that file IS the dependency map.
      Build-time toolchains (C compiler, make, Go) are not listed: they are compiled before distribution.
    - **Ask the engine, never roll your own.** In the app and in import-file tools: `_dep_need -c "what the person is doing" <feature|id>... || return` (menu: lists what is missing, yes/no, installs, re-checks);
      `_dep_have <feature|id>...` for a silent check (never installs; `_DEP_MISSING` says what). Stand-alone bash tools: `bashbasicsbyvk_deps.sh -c "..." <feature|id> || exit 1`.
      Python: `import bashbasicsbyvk_deps as deps; deps.ensure("feature", "?optional_id", context="...")`. A background job with no terminal never opens a menu: it uses `_dep_have`, or quiet mode (`-q` / `quiet=True`, only `auto` user-space pip packages).
    - **Forbidden:** a private `command -v X || echo "please install X"` that exits, a private `pkg install` / `apt install` / `pip install` / `npm install` / `npx --yes` recipe, a package-name table, a sentinel / retry file for installs, a hand-made "install now? y/n" prompt for a dependency.
      The old ones (pipboot, polyglot_bootstrap, gitpush's gh installer, the daemon's pip call, timezone's package table, the archive tool tables) are gone; do not bring one back.
      A tool may still PROBE with `command -v` to choose between alternatives it can work without (clipboard tools, `xdg-open` / `termux-open`), but a dependency it cannot work without is asked for through the engine.
    - A new dependency = one `D` line (+ one `F` line for the menu that needs it) + `bash tests/deps/deps_test.sh`. A pip family (`tree_sitter_<lang>`) is a `G` line. A multi-step install is a `@recipe` in the engine, never a copy in the caller.
    - Scripted runs (CI, agents, e.g. the polyglot check above): `BVK_DEPS_ASSUME=yes` answers the menu, `BVK_DEPS_ASSUME=no` refuses, `--dry-run` prints the commands. The engine installs system packages in one call and pip / npm in parallel lanes.

## Tests: seconds, not half an hour (the rules the owner and the agents framed)

A bug fix takes seconds; its tests must too. The tests used to take ~30 minutes because they slept for guessed times, started the app dozens of times with a blind
4 s start-up wait, and an agent then added its own `sleep 600` on top. **A test waits for the thing it needs and fails the moment that thing is clearly not coming.**

**Running tests (agents follow this, do not improvise). First read "Workflow and tests" at the top of this file: it decides IF and WHICH tier runs; this section only describes the tools.**
- `bash tests/run.sh for <the files you changed>` runs only the tests that cover them (`tests/covers.map`), in parallel, each with a hard timeout, and prints a failure *the moment
  it happens* with the last lines of its output. `bash tests/run.sh fast` = the quick tier. `bash tests/run.sh all` = everything: only before a release or when the prompt asks
  for the full suite. `bash tests/run.sh list` shows every test, its tier and timeout.
- A test that cannot run here (needs `tmux`, node, the `../fileapi` repo) is printed as **SKIP and counted as NOT verified**; say so in HOW DID YOU DEBUG. Never report a skip as a pass.
- Red from the start? `tests/known_failing.txt` lists tests that were already failing, with the reason; a failure that is not listed there is yours. Do not add a line to hide
  a failure you caused. Before blaming the app for a red test, check the usual suspects: UTF-8 locale (`wait_lib.sh` forces it), files moved (find them by name, `bvk_need`),
  a missing tool (a SKIP, not a fail), the app's telemetry ping (the test marks today as reported, see `PtyApp.seed_telemetry`).
- Run each test once after your change, not before-and-after pairs of the whole suite: run the covering tests before only when you need a baseline for a failure.

**Long commands: never `sleep 600` (or any `sleep` over 30 s).**
- `bash tests/bg.sh start <name> <command...>` starts it in the background (log in `/tmp/bvk_bg/<name>.log`); `bash tests/bg.sh wait <name> [max-secs]` returns THE MOMENT it ends
  (exit code = the command's) and prints new log lines as they appear; if it is still running after 25 s it says so, and you call `wait` again. `status`, `tail`, `kill`, `list` also exist.
- Look at the output while it runs and stop a clearly stuck job; a job with no output for a minute is stuck, not slow.

**Writing a test (every new test and every edit of an old one):**
1. **Wait for a condition, never for a time.** bash: `source tests/wait_lib.sh`, then `wait_until <secs> "<what>" <cmd...>`, `wait_file`, `wait_gone`, `wait_port`, `wait_grep`,
   `wait_count`, and for tmux `tmx_start`, `tmx_wait`, `tmx_line`, `tmx_do`, `tmx_until`. python/pty: `tests/paste_input/ptyapp.py` (`PtyApp`): `a.wait(cond)`, `a.wait_text(t)`,
   `a.send(keys, until=cond)`, `a.settle()`; the app is ready when it shows its prompt (the constructor waits for that), not after 4 s. Do not write a new pty/VT driver: use `PtyApp`
   and `tests/paste_input/vt.py`.
2. **A timeout is a failure with evidence.** Every wait has a maximum; on timeout it prints what it waited for and what was on screen instead (`WAIT_DUMP` / the screen dump), then the test
   fails at once. Never `sleep` and then assert; never a retry loop that hides a failure.
3. **No sleep in tests.** `tests/lint_waits.sh` (part of `run.sh fast`) rejects `sleep N` with N > 0.1, `time.sleep`, and blind `pump(N >= 0.5)`. The only allowed wait is one that IS the behaviour
   under test (an app timer, a double-click window, "nothing else may happen"), marked on its own line `# lint-wait-ok: <why>`. "Nothing may happen" checks use `settle` / `a.settle()` (a short quiet window), not a long sleep.
4. **Real tests, not name-sake skims.** Keep every assertion. Speeding a test up means changing how it waits, never what it checks. A test must be able to fail: after writing or changing one, break the code on
   purpose (comment out the fix, change a value) and see it go red, then restore. State in HOW DID YOU DEBUG that you did. A check that also passes when the app never answered (e.g. result `-1` counted as "refused") is a bug in the test.
5. **Find files by name** (`bvk_need <basename>` in bash, `find_script(root, name)` in python): files move between folders and a hard-coded path made a test fail "from the start". UTF-8 locale is set by `wait_lib.sh` / `PtyApp`.
6. **No network, no real clock ticks.** Tests never talk to the internet and never wait for the wall clock: set mtimes with `touch -d`, pre-mark the telemetry ping as done, point tools at a local mock. Do not wait for a one-second tick.
7. **Start the app once per test file when you can**, not once per assertion; each start costs a second of CPU. Independent checks go in separate files only if they can run in parallel (`run.sh` does).
8. **Register the test.** Add it to `tests/tests.list` (name, tier, timeout, command, needs) and to `tests/covers.map` for the files it covers. A test with a timeout over 5 minutes needs a reason in the list.
9. **Tests live in `tests/`** (rule 1 covers `script/` only): helpers shared by tests are `tests/wait_lib.sh` and `tests/paste_input/ptyapp.py`; find them with grep before writing another.

## How the install works (why names matter)

`setup.py` installs every file under `script/` **flat** into one `bin/` directory that is on `PATH`
(only `*.txt`/`*.xlsx` go to the data dir; `bvk-ls/` is build-only). So:
- **Every basename must be unique across all of `script/`** (that is why the prefix exists).
- Files are found by bare name (`source "bashbasicsbyvk_x.sh"`, `command -v bashbasicsbyvk_x`), never by relative path.
- The command map finds `*commands.sh` / `*.map` by those suffixes: keep `bashbasicsbyvk_<menu>.map` and
  `bashbasicsbyvk_<menu>menucommands.sh`. `bashbasicsbyvk_mapgen` writes exactly those names.
- Built `bvk-ls-<os>-<arch>` binaries are build output, not source: they keep that name (`setup.py`, `MANIFEST.in`, health check match it).

## When you add, rename or delete a file

1. Pick the folder by feature, name it `bashbasicsbyvk_<what_it_does>.<ext>`.
2. If it is shell code that `o` needs, add its `source` line to an import file (rule 3). Do not source it anywhere else.
3. When renaming: grep the old name across the WHOLE repo (script/, tests/, README, llms*.txt, SECURITY.md, setup.py,
   MANIFEST.in, python `import`s, comments, user-facing messages) and fix every hit. Python modules are imported by
   their file stem, so the import lines change too.
4. Run the checks below before you finish.

```bash
# 1. naming: nothing but o, bashbasicsbyvk_* and _3bvk_import_*.sh under script/
find script -type f ! -name 'bashbasicsbyvk_*' ! -name '_3bvk_import_*.sh' ! -path script/o
# 2. _3bvk_ only for import files
find script -name '_3bvk_*' ! -name '_3bvk_import_*.sh'
# 3. source only in o and import files (stand-alone entry points that source their own import file are filtered out)
grep -rnE '(^|[;&|({]|[[:space:]])(source|\.)[[:space:]]+["$]' script | grep -vE '^script/o:|_3bvk_import_'
# 4. no basename collisions, no stale names
find script -type f -printf '%f\n' | sort | uniq -d
grep -rnI '_3bvk_' script tests setup.py MANIFEST.in README.md | grep -v '_3bvk_import_'
# 5. ONLY when the prompt asks to dedupe / find duplicates (never as part of an ordinary fix or feature): duplicate-function candidates (polyglot: parses the code, finds renamed and cross-language copies too) — prints clusters, writes nothing into the repo
PYTHONPATH=script/file/engine BVK_DEPS_ASSUME=yes python3 script/file/infinity/tools/polyglot/bashbasicsbyvk_polyglot . --no-xlsx --plain --exclude sample_project -o /tmp/polyglot_report.json
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
Checks 1-4 and 6 are cheap: run them whenever you add, rename or delete a file or a note. Checks 1-4 must print nothing; check 6 must print `[] [] [] []`. **Check 5 (polyglot) is NOT part of the routine run**: it scans the whole repo (and installs numpy / tree-sitter on first run), so on an ordinary job it costs minutes for nothing. Run it ONLY when the prompt asks to dedupe, find duplicates or clean up copies; an ordinary job covers rule 1-4 of the principle with `grep -rn <keyword> script tests` instead (search before you write). When it IS asked for: Check 5 lists CANDIDATES, not proven copies: polyglot is NOT a 100% reliable
mechanism (it can miss real copies and flag look-alikes). Run it before and after your dedupe change, read every cluster your change touches or adds, and say
in HOW DID YOU DEBUG how you judged each; your change must not add a cluster that is a real copy (the clusters already there are not yours to fix
unless the task says so). It asks the central installer for numpy / tree-sitter on first run (`BVK_DEPS_ASSUME=yes` answers the menu in scripted runs, `--no-install` to forbid). If it finds a real copy, do NOT edit the copies in step: move the code into ONE helper
that every place calls (a function in a lib that `o` / an import file loads earlier; for node tools `bashbasicsbyvk_staging_jslib.js`, found
through `_bb_jslib`; for tests `tests/e2e_common.sh`, `tests/wait_lib.sh`, `tests/paste_input/ptyapp.py`). Before you write a block that looks like one you have
seen elsewhere, grep for the helper first.
