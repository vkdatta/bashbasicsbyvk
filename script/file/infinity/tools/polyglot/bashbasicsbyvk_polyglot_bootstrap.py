"""bashbasicsbyvk_polyglot_bootstrap - polyglot installs what it needs itself, every time it runs.

Whenever polyglot starts and a library or tree-sitter grammar it can use is missing, it pip-installs it through the shared
bashbasicsbyvk_pipboot recipe (the same one the recents daemon uses for watchdog): one attempt per package, outcome kept in a
sentinel file under ~/.bashbasicsbyvk/polyglot_install/, a failed package is not retried for a day.  Nothing here is fatal except
numpy: a missing grammar degrades that language to the stdlib `ast` (Python) or the regex extractor, a missing rich / openpyxl
only drops the coloured console / the xlsx report.  Only the grammars of languages actually found in the scanned folder are installed.
"""
import time
from pathlib import Path

import bashbasicsbyvk_pipboot as pipboot
from bashbasicsbyvk_polyglot_languages import LANGUAGES

HOME_DIR = Path.home() / ".bashbasicsbyvk"
SENTINEL_DIR = HOME_DIR / "polyglot_install"
LOG_FILE = HOME_DIR / "polyglot_install.log"
RETRY = 86400            # seconds: do not retry a failed install before this
PIP_TIMEOUT = 300        # seconds per package (a grammar may have to compile)
TS_CORE = ("tree_sitter", "tree-sitter", "tree-sitter>=0.23", (0, 22))     # module, distribution, pip spec, oldest usable version
REQUIRED = (("numpy", "numpy"),)                                           # (module, pip spec): polyglot cannot run without these
OPTIONAL = (("rich", "rich"), ("openpyxl", "openpyxl"))


def grammar_spec(module):
    """tree_sitter_c_sharp -> tree-sitter-c-sharp>=0.23 (the pip name is the module name with dashes)."""
    return module.replace("_", "-") + ">=0.23"


def _log(msg):
    try:
        HOME_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S %Z')} {msg}\n")
    except OSError:
        pass


def ensure(module, spec, say, dist=None, min_version=None):
    """True if `module` imports afterwards: installs `spec` first when it is missing and the retry window allows."""
    if pipboot.have(module, dist, min_version):
        return True
    sentinel = SENTINEL_DIR / ("." + "".join(c if c.isalnum() else "_" for c in spec) + ".attempted")
    if not pipboot.retry_due(sentinel, RETRY):
        say(f"   {spec}: not installed; the last install attempt failed less than a day ago, not retrying (see {LOG_FILE})")
        return False
    say(f"📦 Installing {spec} ...")
    _log(f"{module} missing - installing {spec}")
    pipboot.install(spec, sentinel, _log, PIP_TIMEOUT)
    ok = pipboot.have(module, dist, min_version)
    say(f"   {'✅ installed' if ok else '⚠️  could not install'} {spec}")
    return ok


def bootstrap(languages_found, parser, say, want_xlsx=True):
    """Make sure everything polyglot can use is installed.  `languages_found` = language names present in the scanned folder,
    `parser` = auto | treesitter | regex.  Returns the list of required modules that are still missing (empty = go ahead)."""
    missing = [m for m, spec in REQUIRED if not ensure(m, spec, say)]
    for m, spec in OPTIONAL:
        if m == "openpyxl" and not want_xlsx:
            continue
        ensure(m, spec, say)
    if parser != "regex" and languages_found:
        module, dist, spec, floor = TS_CORE
        if ensure(module, spec, say, dist, floor):
            for gm in sorted({LANGUAGES[l].ts_module for l in languages_found}):
                ensure(gm, grammar_spec(gm), say)
    return missing
