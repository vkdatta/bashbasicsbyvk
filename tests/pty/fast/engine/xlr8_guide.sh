#!/usr/bin/env bash
# The xlr8 guides stay true.   bash tests/pty/fast/engine/xlr8_guide.sh
# script/agents_guide/xlr8.txt is the file a user's own agent reads to write workflows, so it must not go stale:
#  (1) every example in it (between "--- example: NAME ---" and "--- end example ---") is loaded by the real parser
#  (2) every word the parser knows (found in the parser source, plus the words a pattern hides) is in the guide
#  (3) every repository path the guide names exists
#  (4) llms.txt and llms-full.txt point agents at the guide
# When this fails you changed xlr8: update script/agents_guide/xlr8.txt in the same change.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
X="$(find "$ROOT/script" -name bashbasicsbyvk_xlr8.sh | head -1)"
GUIDE="$ROOT/script/agents_guide/xlr8.txt"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# shellcheck disable=SC1090
source "$X"

[ -r "$GUIDE" ] && ok "the agent guide exists: script/agents_guide/xlr8.txt" || { bad "script/agents_guide/xlr8.txt is missing"; exit 1; }

# (1) the examples
python3 - "$GUIDE" "$T" <<'PYEOF'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
out = pathlib.Path(sys.argv[2])
n = 0
for m in re.finditer(r"^--- example: ([A-Za-z0-9_]+) ---\n(.*?)^--- end example ---$", text, re.M | re.S):
    (out / f"ex_{m.group(1)}.xlr8").write_text(m.group(2), encoding="utf-8"); n += 1
opens = len(re.findall(r"^--- example: ", text, re.M)); closes = len(re.findall(r"^--- end example ---$", text, re.M))
if not (opens == closes == n and n >= 5): print(f"BAD {opens} opens, {closes} closes, {n} found (at least 5 expected)"); sys.exit(1)
print(f"found {n}")
PYEOF
[ $? = 0 ] && ok "the examples are fenced and paired" || bad "the example fences are broken"
for f in "$T"/ex_*.xlr8; do
  if _xl_load "$f"; then ok "example parses: $(basename "$f" .xlr8 | sed 's/^ex_//')"; else bad "example does not parse: $(basename "$f") : $_XL_ERR"; fi
done

# (2) every word the parser knows is in the guide
python3 - "$X" "$GUIDE" <<'PYEOF' || fail=1
import re, sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
guide = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").lower()
def func(name):
    m = re.search(r"^%s\(\) \{.*?^\}" % re.escape(name), src, re.M | re.S)
    return m.group(0) if m else ""
words = set()
for fn in ("_xl_segment", "_xl_if"):
    body = func(fn)
    if not body: print("  FAIL cannot find", fn, "in the parser: this test needs updating"); sys.exit(1)
    for lab in re.findall(r"^\s{2,8}([a-z][a-z0-9|*]*)\)", body, re.M):          # case labels:  wf)  select)  ask|"from user")
        words |= {w.strip("*") for w in lab.split("|") if w.strip("*")}
    for m in re.finditer(r"^\s{2,8}(?:[a-z0-9|*\"\\ ?\[\]-]*\|)?\s*(value)\*=\*\)", body, re.M): words.add(m.group(1))
# the keys, from the alternation the parser uses
for m in re.finditer(r"\(((?:name|names)\|[a-z|]+)", src): words |= set(m.group(1).split("|"))
# what a quoted or glob pattern hides from the regex above
words |= {"except", "auto", "as", "first", "last", "endif", "not", "ask", "default", "value", "all", "asked", "option", "screen", "menu", "question",
          "start", "end", "from", "on", "goto", "cmd", "wf", "where", "select", "input", "confirm", "pause", "if", "else", "name", "path", "number"}
missing = sorted(w for w in words if not re.search(r"(?<![a-z0-9_])%s(?![a-z0-9_])" % re.escape(w), guide))
for w in missing: print(f"  FAIL the parser knows '{w}' but script/agents_guide/xlr8.txt never says it")
if not missing: print(f"  ok   all {len(words)} words of the grammar are in the agent guide")
sys.exit(1 if missing else 0)
PYEOF

# (3) the paths the guide names exist
python3 - "$ROOT" "$GUIDE" <<'PYEOF' || fail=1
import re, sys, pathlib
root = pathlib.Path(sys.argv[1]); text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
paths = sorted(set(re.findall(r"\b((?:script|tests)/[A-Za-z0-9_./-]*[A-Za-z0-9_/])", text)))
gone = [p for p in paths if not (root / p).exists()]
for p in gone: print("  FAIL the guide names a path that does not exist:", p)
if not gone: print(f"  ok   all {len(paths)} repository paths named in the guide exist")
sys.exit(1 if gone else 0)
PYEOF

# (4) llms.txt and llms-full.txt show agents the way
for f in llms.txt llms-full.txt; do
  grep -q "script/agents_guide/xlr8.txt" "$ROOT/$f" && ok "$f points to script/agents_guide/xlr8.txt" || bad "$f does not point to script/agents_guide/xlr8.txt"
  grep -qi "workflow" "$ROOT/$f" && ok "$f talks about workflows" || bad "$f never mentions workflows"
done

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
