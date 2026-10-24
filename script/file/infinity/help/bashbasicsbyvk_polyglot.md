### `polyglot` — Polyglot Clone Finder (duplicate-function candidates)

Scans a folder for functions and methods that look like copies of each other — **even across languages** (Python, JavaScript/TypeScript, Java, C/C++, Go, Rust, Ruby, C#, Bash) — and reports duplication per project, file and cluster. Replaces `dupscan`.

> **Warning:** Polyglot finds **possible candidates** for deduplication. It is **not a 100% reliable mechanism**: it can miss real duplicates and flag functions that only look alike. Review every cluster by hand before merging or deleting code.

Runs like the JavaScript / Python audits: pick it in the Infinity Stones menu (`i` → 7) and it scans the current folder, writes `Polyglot Report.xlsx` (Summary, Clusters, Files) and `Polyglot Report.json` there, and prints the clusters. From a shell: `bashbasicsbyvk_polyglot [PATH] [options]`.

<details>
<summary>Self-install, options & how it works</summary>

<br/>

**Self-bootstrapping.** Each run installs what is missing: `numpy` (required), `rich`, `openpyxl`, `tree-sitter` and the grammar of every language found in the folder. One attempt per package; a failed install is not retried for a day (`~/.bashbasicsbyvk/polyglot_install/`, log: `polyglot_install.log`). Without a grammar a language falls back to the standard-library `ast` (Python) or a regex extractor. On Termux, if numpy cannot be built: `pkg install python-numpy`.

| Option | Meaning |
|---|---|
| `--min-confidence medium` | only clusters with ≥ 70 % verified similarity (`high` ≥ 80 %) |
| `--cross-language-only` | only matches across different languages |
| `--lang python --lang go` | restrict to languages |
| `--exclude "tests/*"` | extra ignore glob (repeatable) |
| `--parser treesitter` | strict: error if a grammar is missing |
| `--no-install` / `--no-xlsx` | never pip-install / write only the JSON |
| `--fail-above PCT` | exit 1 if duplication exceeds PCT (CI gate) |

**Pipeline:** crawl → AST extraction → token normalisation → feature-hashing candidate search → exact LCS verification → average-linkage clustering → metrics. No ML model, no GPU, no downloads.

</details>
