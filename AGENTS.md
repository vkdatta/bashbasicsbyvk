# AGENTS.md — read this BEFORE doing anything else

Every AI agent working in this repo must read this file first and follow it exactly.
If a task seems to need breaking a rule, stop and ask the owner. Do not improvise.

## The rules

1. **Every file lives under `script/`.** Every file under `script/` is named with the prefix
   `bashbasicsbyvk_` (py, c, h, txt, md, map, list, Makefile, extension-less python/node/bash tools, everything),
   with exactly two exceptions: the entry point `script/o`, and import files (rule 2).
   Directories are not prefixed. Do not create files anywhere else (no new files in the repo root).
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
```
All four checks must print nothing.
