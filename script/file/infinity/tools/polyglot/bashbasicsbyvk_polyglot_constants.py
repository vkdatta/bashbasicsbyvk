"""bashbasicsbyvk_polyglot_constants - names and the reliability warning shared by every polyglot module."""

VERSION = "1.3.0"
TOOL_NAME = "PolyglotCloneFinder"
REPORT_NAME = "Polyglot Report"            # -> "Polyglot Report.xlsx" and "Polyglot Report.json", written into the scanned folder

WARNING = ("Polyglot finds POSSIBLE CANDIDATES for deduplication. It is NOT a 100% reliable mechanism: it can miss real "
           "duplicates and it can flag functions that only look alike. Review every cluster by hand before merging or "
           "deleting any code.")
