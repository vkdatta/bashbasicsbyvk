### `xtract` — Web Scraper

Extracts **all** HTML tables and hyperlinks from one or more paginated web pages in a single invocation. Perfect for harvesting catalogues, reports, and dashboards spread across multiple pages.

<details>
<summary>URL Patterns & Examples</summary>

<br/>

| Intent | Format | Example |
|---|---|---|
| Single page | Plain URL | `example.com/article/p.html` |
| Specific page number | URL ending in page number | `example.com/article/100` |
| Page range (1 to N) | URL with `{N}` | `example.com/article/{100}` |

> **Note:** `{100}` means pages **1 through 100**. Curly braces signal a range — no braces means that exact page only.

</details>

---
