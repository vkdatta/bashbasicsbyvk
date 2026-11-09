"""bashbasicsbyvk_recover_creds - Cloudflare credentials, looked up in the NAVIGATION path (not the current directory).

Order, per value:   1. files in the navigation path   2. process environment   3. ask (hidden for the token)

Files read from the navigation path (first hit wins, order = priority):
    .dev.vars  .env  .env.local  .env.production  .env.development      KEY=value / export KEY="value"
    wrangler.jsonc | wrangler.json | wrangler.toml                      (account_id only - it is not a secret)

Names understood:  token   CLOUDFLARE_API_TOKEN, CF_API_TOKEN
                   account CLOUDFLARE_ACCOUNT_ID, CF_ACCOUNT_ID

Values are never printed, logged or written anywhere: only the NAME of the file that supplied them is reported.
All prompts go to stderr so a caller can capture stdout.
"""
import getpass, os, re, sys
from pathlib import Path
from bashbasicsbyvk_recover_api import ApiError, get_json
from bashbasicsbyvk_recover_project import WRANGLER_FILES, read_wrangler
from bashbasicsbyvk_recover_util import RecoverError

TOKEN_KEYS = ("CLOUDFLARE_API_TOKEN", "CF_API_TOKEN")
ACCOUNT_KEYS = ("CLOUDFLARE_ACCOUNT_ID", "CF_ACCOUNT_ID")
SECRET_FILES = (".dev.vars", ".env", ".env.local", ".env.production", ".env.development")
_LINE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")


def _err(msg=""):
    print(msg, file=sys.stderr, flush=True)


def parse_env_text(text):
    """dotenv / .dev.vars text -> dict. No shell evaluation, no variable expansion."""
    out = {}
    for line in text.lstrip("\ufeff").splitlines():
        if line.lstrip().startswith("#"):
            continue
        m = _LINE.match(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        q = val[:1]
        if q in ("\"", "'") and q in val[1:]:
            val = val[1:val.index(q, 1)]                 # quoted: up to the closing quote, a trailing `# comment` is ignored
        else:
            val = re.split(r"\s+#", val, 1)[0].strip()
        if val:
            out[key] = val
    return out


def scan_nav_path(nav):
    """{KEY: (value, source file name)} for every key found directly in the navigation path."""
    found = {}
    nav = Path(nav)
    for fname in SECRET_FILES:
        f = nav / fname
        if not f.is_file():
            continue
        try:
            data = parse_env_text(f.read_text("utf-8", "replace"))
        except OSError:
            continue
        for k, v in data.items():
            found.setdefault(k, (v, fname))
    return found


def _account_from_wrangler(nav):
    for w in WRANGLER_FILES:
        f = Path(nav) / w
        if not f.is_file():
            continue
        cfg = read_wrangler(f)
        acc = cfg.get("account_id")
        if isinstance(acc, str) and re.fullmatch(r"[0-9a-fA-F]{32}", acc.strip()):
            return acc.strip(), w
    return None, None


def _first(found, keys):
    for k in keys:
        if k in found:
            return found[k]
    return None, None


def resolve(nav):
    """(token, account, token_source, account_source) - anything not found in nav path / environment is None."""
    found = scan_nav_path(nav)
    token, tsrc = _first(found, TOKEN_KEYS)
    account, asrc = _first(found, ACCOUNT_KEYS)
    if not account:
        account, asrc = _account_from_wrangler(nav)
    if not token:
        for k in TOKEN_KEYS:
            if os.environ.get(k):
                token, tsrc = os.environ[k].strip(), f"environment ({k})"; break
    if not account:
        for k in ACCOUNT_KEYS:
            if os.environ.get(k):
                account, asrc = os.environ[k].strip(), f"environment ({k})"; break
    return token or None, account or None, tsrc, asrc


def credentials(nav, interactive=True):
    """Return (token, account). Looks in the navigation path first; asks only for what is still missing."""
    token, account, tsrc, asrc = resolve(nav)
    if token:
        _err(f"  API token  : from {tsrc}")
    elif interactive:
        try:
            token = getpass.getpass(f"Cloudflare API token (hidden) - not found in {nav}: ").strip()
        except EOFError:
            token = ""
    if not token:
        raise RecoverError(
            f"No Cloudflare API token. Put CLOUDFLARE_API_TOKEN=... in {Path(nav) / '.dev.vars'} (or .env) in this folder.")
    if account:
        _err(f"  Account ID : from {asrc}")
    else:
        try:
            accts = get_json("/accounts", token).get("result", [])
        except ApiError as e:
            raise RecoverError(f"Could not read your accounts with this token: {e}")
        if len(accts) == 1:
            account = accts[0]["id"]
            _err(f"  Account    : {accts[0].get('name', account)} (auto-detected)")
        elif accts and interactive:
            for i, a in enumerate(accts):
                _err(f"  [{i}] {a.get('name')}  {a['id']}")
            sys.stderr.write("Choose account number: "); sys.stderr.flush()
            try:
                account = accts[int(sys.stdin.readline().strip())]["id"]
            except (ValueError, IndexError):
                raise RecoverError("Invalid account number.")
        elif interactive:
            sys.stderr.write("Cloudflare account ID: "); sys.stderr.flush()
            account = sys.stdin.readline().strip()
    if not account:
        raise RecoverError(
            f"No Cloudflare account ID. Put CLOUDFLARE_ACCOUNT_ID=... in {Path(nav) / '.dev.vars'} (or .env) in this folder.")
    return token, account
