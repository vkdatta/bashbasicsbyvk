@AGENTS.md

Before running ANY test, read the section "Workflow and tests" at the top of AGENTS.md: deliver first, test after, a minor change runs no tests, and the decision matrix there picks static or pty.

Owner-only: no agent may edit AGENTS.md, CLAUDE.md or GEMINI.md unless a human explicitly permits it in the current conversation. Tests: static by default (`bash tests/run.sh`); pty tests only by the decision matrix in AGENTS.md.
