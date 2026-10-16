---
name: surgical-audit-fix
description: Cost-aware bug finding, fixing, refactoring and independent verification for any codebase, including very large ones (1k-10k+ files), plus an architecture navigation map (canvas_xd.md) and a web UI/UX audit path. Use whenever the user reports a bug, asks to fix, patch, debug, trace, refactor, audit or review code, names specific files or symptoms, or asks about UI/UX, responsiveness, accessibility, spacing, touch targets or frontend defects - even if they never say "audit". Reads the minimum files needed (named files plus bounded upstream/downstream dependencies), never crawls the whole repo, and edits surgically. Not for pure file operations (copy, zip, move, rename, list).
---

# Surgical Audit & Fix

One workflow for finding, fixing and verifying defects in any codebase, built around a single constraint: **tokens and time are the budget, and most of a repo is irrelevant to any one issue.** Every rule below exists to read less, ask tools instead of reasoning by hand, and change as little as possible while still reaching the root cause.

Three parts are merged here: a navigation map (CANVAS) that tells you *where* to look, a bug audit-and-fix pipeline that tells you *what to do*, and a web UI/UX path for frontend issues.

Bundled helpers (if the package is installed): `scripts/symbols.py` (locate bugs), `scripts/closure.py` (neighbours), `scripts/scan_repo.py` (skim), `scripts/map_check.py` (map freshness), and `references/` (web-ui, rendering, deep-checks, map-format, report-template). If they are absent, use the `rg` / language-server equivalents named below.

## 0. Pick the mode first

| Mode | Trigger | Scope |
|---|---|---|
| **A. Targeted** (default) | User names files, symptoms, an error, a feature | Named files + bounded dependency closure |
| **B. Area** | "audit the checkout flow", "review the sidebar" | One subsystem found via the map |
| **C. Whole-repo** | User explicitly asks for a full audit | Sample by risk, never read everything |

If unsure, use A and say so. Widening scope is cheap later; a wasted crawl is not. Write the ledger before touching anything:

| ID | Issue (user's wording) | Area | Suspected files | Status |

Read every issue before fixing the first. Words like "also", "only after", "sometimes" often reveal a dependency chain, so keep them in the ledger text.

## 1. Locate the bug fast (cheapest path first)

Most of the time and tokens in a bug task go to *finding* the code, so use exact locators before reading anything. Pick the first row that applies:

| You have | Run | Then |
|---|---|---|
| Stack trace, compiler or test failure text | `python scripts/symbols.py <repo> trace < error.txt` | `slice PATH:LINE` on the top repo frame, then the caller; the root cause is often a caller, not the throwing line |
| A function, class, method, CSS class or HTML id name | `symbols.py <repo> find NAME` | `slice NAME` (accepts `Class.method`) |
| A file and a line | `symbols.py <repo> at PATH:LINE` | `slice PATH:LINE` |
| A file you must understand | `symbols.py <repo> file PATH` (outline with line ranges) | `slice` only the symbols that matter |
| Only a symptom or message | `rg -n "<distinctive string>"` | `at` / `slice` on the hits |

`slice` prints exactly one symbol's lines, typically 1-3% of the file's size. Static parsing misses dynamic definitions (generated code, decorators that register handlers, string-based routing), so when `find` returns nothing, confirm with `rg` before concluding something doesn't exist. `find` matches by name, so check imports before trusting a reference from an unrelated module.

**Speed never comes from skipping checks.** Save tokens on *reading*, not on *verifying*: reproduction, the consumer check (section 3) and a test run are still required. A fast fix that skipped the consumer check is how regressions happen.

## 2. Read in tiers, stop at the cheapest that answers

| Tier | What | How |
|---|---|---|
| T0 | Names and folder shape | directory listing, `scripts/scan_repo.py` |
| T1 | What a file *does*: purpose line, exports, signatures, imports | `scripts/closure.py`, `symbols.py file`, `rg`, `head -n 40` |
| T2 | The exact function or lines involved | `symbols.py slice` (or `rg -n` then a line range) |
| T3 | Whole file | only files you will edit or that contain the root cause |

Rules that keep this honest:
- A fresh project with no named files: T0 on the root and entry points, then T1 on the one relevant folder. Do not map everything. Propose or ask for a narrower scope if the issue doesn't point anywhere.
- Never full-read a file over ~400 lines at the first look; take T1, then a T2 slice.
- **Checkpoint after ~5 full-file reads** (T3) without a confirmed root-cause hypothesis: state what you know, what you would read next and why, then continue only if that is still the best next step.
- Don't re-read a file you already summarised. Keep a one-line note per file in your working notes.
- Batch independent searches into one step.

## 3. Bounded dependency closure (the key cost control)

For named files, the audit surface is: **those files + one hop upstream (who imports/calls them) + one hop downstream (what they import/call)**, each at T1. Go to T2 on a neighbour only when the changed symbol crosses into it.

Go beyond one hop only when evidence points there (a type, contract or state key you are changing is consumed further out). Stop at depth 2 by default. Whenever you stop, record it: `not traced beyond X because Y`. That line lets the user widen scope on purpose instead of discovering a silent gap.

Get the closure from a tool, not by reading:
```
python scripts/closure.py <repo> path/a.ts path/b.ts --up 1 --down 1
```
It prints each reached file with its purpose line and exports. Without the script, use `rg -n "from .*<module>|require\(.*<module>"` for upstream and the file's import block for downstream, or the language server's find-references. Exact tool queries cost almost nothing; speculative reading costs a lot.

Chain bugs (A causes state B which shows up as symptom C) are the main reason to go deeper. Follow the actual data/state path the evidence reveals, one file at a time, not the whole neighbourhood.

## 4. The navigation map (`canvas_xd.md`)

A compact architecture mindmap that lets a future session skip rediscovery. Navigation authority is the map; behaviour authority is source; build/runtime truth is compiler, tests and logs. The map never overrides stronger evidence.

- **Find it first:** look for `canvas_xd.md` (then `architecture.md`, `ARCHITECTURE_MINDMAP.md`). Keep exactly one authoritative map.
- **Build it lazily.** On a big repo do not document everything. Create a root map with T0/T1 skeleton (entry points, top-level modules, one-line purposes), mark untouched areas `UNMAPPED`, and expand a branch only when a task enters it.
- **Shard when large.** Root `canvas_xd.md` lists modules and links to `canvas_xd/<module>.md`. Read the root plus only the relevant shard, located by grep on a path or symbol.
- **Staleness is cheap to check.** The map header records `synced: <git commit>`; run `python scripts/map_check.py <repo>` to list mapped files changed or deleted since then. Repair only those branches.
- **Update in the same task** whenever modules, imports/exports, APIs, workflow/state/persistence, config or invariants change. Skip it for comments, formatting and internal-only edits. Keep it a current-state mindmap, not a changelog or prose.
- Distinguish `DEFINES` from `REEXPORTS`; a re-export is never a second definition.

Format, an example and sharding layout: `references/map-format.md`. Read it when creating or restructuring a map.

## 5. Use the strongest tool, never fake one

Before reasoning manually about something a tool can answer exactly, use the tool: compiler/type checker for errors and symbols, `rg`/AST search for consumers, linters and dead-code finders, the project's own tests, `git diff/blame/log/bisect` for "when did this break", profilers for performance, browser automation for UI. Generate repetitive or boundary inputs with a script (seeded when reproducibility matters).

Token hygiene when running tools: cap output (`--max`, `| head -40`, `| tail -40` for test logs), run the single relevant test before the suite, view changes with `git diff -U2` rather than re-reading files, and never print a whole file when `slice` can print one symbol.

Order checks cheapest first: syntax/type check, then the single relevant test file, then the broader suite. If a tool is unavailable (no network, missing dependency, no credentials), say so, use the best accessible equivalent, and never report output you did not obtain.

## 6. Find the root cause

For each ledger item: reproduce, record expected vs actual, then trace **backward** from symptom to the earliest wrong state or decision (who created, transformed, cached, consumed the value; which assumption became false), and **forward** to every other consumer of the root. A symptom disappearing is not proof the root is fixed. Validate the hypothesis with a tool or a failing test before editing. Do not merge issues unless you proved a shared root.

## 7. Fix at the smallest correct level

1. Shared root fix (the common helper/primitive/state transition)
2. Local surgical fix (intentionally local behaviour)
3. Targeted refactor (extract when structure blocks a safe fix or duplicates logic)
4. Subsystem revamp, 5. Rewrite: only when evidence shows the structure prevents a safe fix

After a shared change, find every consumer (closure tool) and verify them. Remove code the fix made obsolete (unused imports/helpers, dead branches, stale flags) once static analysis or search confirms it is unused; don't remove dynamic or public API without evidence. Prefer one authoritative implementation per behaviour, but don't abstract two snippets that merely look alike.

File size: under 800 lines preferred, 800-1200 a warning, over 1200 needs a split plan. Apply this only to files you are already touching, split by responsibility, never mechanically.

## 8. Edit surgically

Don't rewrite a file to change two lines. Use patches, the Edit tool, a script or an AST codemod, with uniqueness checks on search-and-replace. After every edit inspect the diff: intended lines changed, nothing else did. Whole-file replacement only for generated files, tiny modules, or justified structural replacement.

## 9. Verify independently, scaled to risk

Verification must not be the author grading their own work. Scale the effort:

- **Trivial / low-risk** (one local change, strong passing test, no shared code): self-check with the exact reproduction, the diff and the relevant tool run.
- **Non-trivial / shared code / chain bugs / user asks for rigor:** run a **Senior pass from scratch**. If you can spawn a subagent, give it only the original issues, the patched files and the closure, not your conclusions. It independently reproduces, re-derives the consumer closure with the same bounded tools, runs its own checks, and returns PASS or FAIL with exact findings. Without subagents, redo the reproduction and consumer query fresh and say that independence was limited.

FAIL means: fix, then repeat the Senior pass. PASS needs original issues resolved, chain symptoms resolved, no regressions in consumers, obsolete code removed, and tool evidence. Re-running the *bounded* consumer query keeps independence at low cost; it does not need a whole-repo trace.

## 10. Specialist paths: load only when relevant

- **Web UI/UX** (layout, responsive, a11y, touch, motion, browser-native styling, frontend state): `references/web-ui.md`. Audit only the surfaces rendered by the files in scope (ask the map or closure which files render them). A full-app UI audit is Mode C only, by sampling representative routes and components.
- **Canvas element / 2D-3D rendering** (render loop, DPR, hit testing, redraws): `references/rendering.md`. Applies only if a canvas/rendering surface exists; never add one. (Note: this is the HTML canvas surface, unrelated to the CANVAS map in section 4.)
- **Concurrency, error handling, lifecycle, performance, security:** `references/deep-checks.md`. Open only the section the issue touches.
- If another installed skill owns an area (navigation system, database, security), use its conventions instead of inventing a competing one.

## 11. Finish

Do not paste whole files. Report: the ledger with status, root cause per issue, changed files, tools/tests run and results, Senior pass result (or the limited-independence note), the recorded cut-offs (`not traced beyond…`), and any remaining risk. Template: `references/report-template.md`. Update the map if architecture changed.

Done means: every issue read and investigated, roots traced backward and forward, consumers in the closure checked, fix surgical, obsolete code gone, tool evidence real, scope cut-offs stated, map in sync.
