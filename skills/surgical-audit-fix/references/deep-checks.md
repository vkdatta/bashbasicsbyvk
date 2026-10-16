# Deep checks (open only the section the issue touches)

Contents: Concurrency, Error handling, Lifecycle, Performance, Security, Data/DB.

## Concurrency and async
Races, ordering assumptions, stale reads, duplicate execution, lost updates, deadlock, starvation, cancellation, timeouts, retry multiplication, idempotency, locking, atomicity, task cleanup. Use race detectors, stress tests or tracing when available.

## Error handling
Swallowed errors, wrong error conversion, misleading messages, missing cleanup, partial mutation, retry loops, inconsistent rollback, invalid fallbacks, error state that persists. Never fix an error by hiding it.

## Lifecycle and architecture
Ownership, initialisation, teardown, subscriptions, threads/tasks, caches, global state, cancellation, serialization, transaction boundaries, external contracts. Many bugs are lifecycle-ownership errors, not wrong lines.

## Performance
Measure first: profiler, benchmark, trace, allocation analysis. For non-UI software use domain metrics (latency, throughput, memory, startup, I/O) rather than UI frame budgets. Latency references: ~100ms feels instant, ~1s interrupts thought.

## Security (authorised testing only)
Injection, authn/authz, secrets, unsafe deserialisation, dependency vulnerabilities, path traversal, command execution, data exposure, insecure defaults, crypto misuse. Use scanners and static analysis; never run intrusive tests against systems you aren't authorised to test.

## Data and databases
Schema/migration validation, query plans, integrity checks, generated fixtures with deterministic seeds.
