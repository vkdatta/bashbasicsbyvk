# What changed
Added: run.sh (new), suites.list, README.md, lib/{load.sh,dump_resolve.sh,bvk.py}, t_structure.py, t_lint.py, t_footer.py, t_intent.py, t_advert.sh, baseline/*.txt, legacy.list, smoke.list.
Moved to retired/ (not deleted, not run): advert_pty.py, advert_static.py, advert_dump.sh, advert_score.sh, cc_audit.sh, cc_footer_truth.sh (ported to t_advert.sh), cc_truth/, cc_footer/, cheatcode.sh, the old run.sh, the old tests.list.
Untouched: every other old test. They are listed in legacy.list (40, no terminal) and smoke.list (22, drives a terminal). The split is a heuristic: a file that mentions a pty helper counts as terminal.
Not done: porting those 62 old tests; the scripted-replay layer (see the message: the app spins on EOF, so it needs a small test hook in the input reader first).

## Layout round 3
- `tests/` now has two folders: `static/` and `pty/{fast,slow,lib,retired}`. Old tests were regrouped by topic (fast: menus, terminal, engine; slow: input, apps), shared helpers moved to `pty/lib/`, every path rewritten, `pty/pty.list` replaces `legacy.list` + `smoke.list`.
- `run.sh`: default = static; `pty fast|slow|list [name..]`; `baseline` rewrites every static baseline.
- `AGENTS.md`: decision matrix (static ~95%, pty only when reading the code cannot show it) and the owner-only rule for `AGENTS.md`/`CLAUDE.md`/`GEMINI.md`.
