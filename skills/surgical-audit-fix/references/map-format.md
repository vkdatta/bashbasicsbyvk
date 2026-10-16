# canvas_xd.md format

A compact hierarchical Markdown mindmap. No prose paragraphs. Current state only, not a changelog.

Contents: Header, Sections, Example, Sharding, Lazy growth.

## Header
First lines: `# PROJECT MAP` then `synced: <git commit hash>` (used by `scripts/map_check.py`).

## Sections (omit what doesn't apply)
PROJECT, ENTRYPOINTS, MODULES, DEPENDENCIES, DATA_FLOW, CONTROL_FLOW, STATE, PERSISTENCE, EXTERNAL_SERVICES, API, WORKFLOWS, ERROR_PATHS, INVARIANTS, CONFIG, BUILD, DEPLOYMENT.

For each important module record: path in backticks (the checker reads these), responsibility, what it DEFINES, what it REEXPORTS FROM where, key imports, data read/written, workflows, public APIs, error boundaries, invariants. Use directional relations: `A -> B`, `A DEFINES X`, `A REEXPORTS X FROM B`, `A WRITES -> table/key`.

A good map answers: where does the request enter, which file owns the behaviour, what feeds it, what state is involved, what is downstream, where can failure propagate, which invariant could break, which files are safe to ignore.

## Example
```
# PROJECT MAP
synced: 3f2a9c1
- ENTRYPOINTS
  - `src/server.ts` -> HTTP router, mounts `routes/*`
- MODULES
  - `src/orders/service.ts`
    - DEFINES createOrder, cancelOrder
    - -> `src/payments/client.ts`, `src/db/orders.ts`
    - WRITES -> table orders
    - INVARIANT: order total recomputed only here
  - `src/orders/index.ts`
    - REEXPORTS createOrder FROM `src/orders/service.ts`
  - `src/legacy/` UNMAPPED
```

## Sharding (large repos)
Root `canvas_xd.md` = entry points + one block per module with one-line purpose and link to `canvas_xd/<module>.md` shard holding the detail. Read the root and a single shard per task.

## Lazy growth
Start at T0/T1 skeleton. Mark unvisited areas `UNMAPPED`. When a task enters a branch, map just that branch, then update `synced`. Never document every line or every file.
