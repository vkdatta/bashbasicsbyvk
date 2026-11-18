# tests/

Two folders. Nothing else lives here except this file, `CHANGES.md` and the runner `run.sh`.

```
tests/
  run.sh          the one runner
  static/         THE DEFAULT. Reads code and command maps. No terminal, no app start, no sleeps.   bash tests/run.sh
    t_*.py        one suite per kind of bug (structure, lint, footer, intent, arms, readloop, shell, replay) + t_advert.sh
    suites.list   the suites the default run executes
    baseline/     findings the owner accepted as known drift (one file per suite); agents never edit them
    lib/          loader, resolver dump, report library
  pty/            real terminal / old shell tests. Use only by the decision matrix in AGENTS.md.
    pty.list      every pty test: name | folder | timeout | command | needs
    fast/         menus/  terminal/  engine/     seconds to a few minutes each      bash tests/run.sh pty fast [name..]
    slow/         input/  apps/                  minutes each, release time         bash tests/run.sh pty slow [name..]
    lib/          ptyapp.py  vt.py  wait_lib.sh  e2e_common.sh  bg.sh  stresstest/  covers.map
    retired/      old advert pty tests and runner, kept for reference, not run, paths not maintained
    known_failing.txt   pty tests that were already red
```

## Which one
Static unless it cannot show the thing. The decision matrix is in `AGENTS.md` ("Workflow and tests").

## Static findings
`kind:where:what` ids. `known` = in `static/baseline/<suite>.txt` (owner's accepted drift). `NEW` = yours. Output is at most 40 lines. First run after a change to `script/` rebuilds the per-map cache (about 25-35 s on 2 cores); later runs about 1-4 s.

## Adding tests
- Static: a new `static/t_<name>.py` using `lib/bvk.py` `Report`; register in `suites.list`.
- Pty: file it under `pty/<fast|slow>/<topic>/`, register in `pty/pty.list`, use `pty/lib/ptyapp.py`, never sleep.

Moving a pty test changes its depth below the repo root: compute the root from `__file__`/`BASH_SOURCE` with the right number of `..` (a pty test sits 4-5 levels below the repo root) or find files by name.
