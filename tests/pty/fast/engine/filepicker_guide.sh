#!/usr/bin/env bash
# The file picker guide stays true.   bash tests/pty/fast/engine/filepicker_guide.sh
# script/agents_guide/filepicker.txt is the file a user's own agent reads to use the file picker, so it must not go stale:
#  (1) every example in it (between "--- example: NAME ---" and "--- end example ---") is accepted by the real rule parser (_pf_parse)
#  (2) every verb / kind / extension word the parser knows, every exit code of the shell door and every name of the python door is in the guide
#  (3) every repository path the guide names exists
#  (4) llms.txt and llms-full.txt point agents at the guide
#  (5) AGENTS.md carries the rule that keeps the guide current
# When this fails you changed the file picker: update script/agents_guide/filepicker.txt in the same change (AGENTS.md rule 19).
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
GUIDE="$ROOT/script/agents_guide/filepicker.txt"
PF="$(find "$ROOT/script" -name bashbasicsbyvk_pickfilter.sh | head -1)"
DOOR="$(find "$ROOT/script" -name bashbasicsbyvk_filepicker -type f | head -1)"
PYDOOR="$(find "$ROOT/script" -name bashbasicsbyvk_filepicker.py | head -1)"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

[ -r "$GUIDE" ] && ok "the agent guide exists: script/agents_guide/filepicker.txt" || { bad "script/agents_guide/filepicker.txt is missing"; exit 1; }
[ -r "$PF" ] && [ -r "$DOOR" ] && [ -r "$PYDOOR" ] && ok "the picker files are found" || { bad "cannot find the picker files (pickfilter.sh, the shell door, the python door)"; exit 1; }
# shellcheck disable=SC1090
source "$PF"

# (1) the examples
python3 - "$GUIDE" "$T" <<'PYEOF'
import re, sys, pathlib
text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
out = pathlib.Path(sys.argv[2]); n = 0
for m in re.finditer(r"^--- example: ([A-Za-z0-9_]+) ---\n(.*?)^--- end example ---$", text, re.M | re.S):
    (out / f"ex_{m.group(1)}.txt").write_text(m.group(2), encoding="utf-8"); n += 1
opens = len(re.findall(r"^--- example: ", text, re.M)); closes = len(re.findall(r"^--- end example ---$", text, re.M))
if not (opens == closes == n and n >= 5): print(f"BAD {opens} opens, {closes} closes, {n} found (at least 5 expected)"); sys.exit(1)
print(f"found {n}")
PYEOF
[ $? = 0 ] && ok "the examples are fenced and paired" || bad "the example fences are broken"
for f in "$T"/ex_*.txt; do
  rules="$(cat "$f")"
  if _pf_parse "$rules"; then ok "example is accepted: $(basename "$f" .txt | sed 's/^ex_//')"; else bad "example is refused: $(basename "$f") : $_PF_ERR"; fi
done

# the parser must still refuse what the guide says it refuses
_pf_parse "allow(csv)" && bad "allow(csv) is accepted, the guide says it is an error" || ok "allow(csv) is refused, as the guide says"
_pf_parse "allow()" && bad "allow() is accepted, the guide says it is an error" || ok "allow() is refused, as the guide says"
_pf_parse "" && ok "an empty rule string is accepted (files and folders), as the guide says" || bad "an empty rule string is refused, the guide says it means files and folders"
mkdir -p "$T/d"; : > "$T/f.csv"; : > "$T/g.txt"
_pf_parse "allow.ext(csv)"; _pf_allows "$T/d" && bad "allow.ext(csv) lets a folder be picked, the guide says it does not" || ok "allow.ext(csv) alone: folders cannot be picked"
_pf_parse "allow(files,folders); allow.ext(csv)"; _pf_allows "$T/d" && _pf_allows "$T/f.csv" && ! _pf_allows "$T/g.txt" && ok "allow(files,folders); allow.ext(csv): .csv files and folders" || bad "the combination rule no longer behaves as the guide says"
_pf_parse "allow(files); block(files)"; _pf_allows "$T/f.csv" && bad "block does not beat allow, the guide says it does" || ok "block beats allow"

# (2) the words, exit codes and python names are in the guide
python3 - "$PF" "$DOOR" "$PYDOOR" "$GUIDE" <<'PYEOF' || fail=1
import re, sys, pathlib
pf, door, pydoor, guide = (pathlib.Path(a).read_text(encoding="utf-8") for a in sys.argv[1:5])
g = guide.lower(); words = set(); miss = []
m = re.search(r"\^\((\w+(?:\|\w+)+)\)\(\\\.ext\)\?", pf)                         # the verbs: ^(allow|block)(\.ext)?
words |= set(m.group(1).split("|")) if m else set()
if not m: print("  FAIL cannot find the verbs in the parser: this test needs updating"); sys.exit(1)
k = re.search(r"_pf_kind\(\) \{.*?^\}", pf, re.M | re.S)                         # the kinds: case words of _pf_kind
if not k: print("  FAIL cannot find _pf_kind: this test needs updating"); sys.exit(1)
for lab in re.findall(r"^\s+([a-z|]+)\)", k.group(0), re.M): words |= set(lab.split("|"))
words |= {"ext", "3bvk.filepicker.", "bvk.filepicker.", "filepicker."}
for w in sorted(words):
    if not re.search(r"(?<![a-z0-9_])%s(?![a-z0-9_])" % re.escape(w.lower()), g): miss.append(f"the parser knows '{w}' but the guide never says it")
for code in sorted(set(re.findall(r"exit\s+(\d+)", door))):                      # the exit codes of the shell door
    if not re.search(r"exit\s+%s\b" % code, g): miss.append(f"the shell door uses exit {code} but the guide never says it")
for opt in re.findall(r"^\s+(-[a-z])\)", door, re.M):                            # the options of the shell door
    if not re.search(r"(?<![a-z0-9_-])%s(?![a-z0-9_-])" % re.escape(opt), g): miss.append(f"the shell door takes {opt} but the guide never says it")
names = set(re.findall(r"^def ([a-z][A-Za-z0-9_]*)\(", pydoor, re.M)) | set(re.findall(r"^class ([A-Za-z][A-Za-z0-9_]*)", pydoor, re.M))
names = {n for n in names if not n.startswith("_")}
for n in sorted(names | {"strict", "start", "EOFError", "ValueError", "RuntimeError", "KeyboardInterrupt"}):
    if not re.search(r"(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % re.escape(n), guide): miss.append(f"the python door has '{n}' but the guide never says it")
for x in miss: print("  FAIL", x)
if not miss: print(f"  ok   all {len(words)} grammar words, the exit codes, the options and the python names are in the guide")
sys.exit(1 if miss else 0)
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
  grep -q "script/agents_guide/filepicker.txt" "$ROOT/$f" && ok "$f points to script/agents_guide/filepicker.txt" || bad "$f does not point to script/agents_guide/filepicker.txt"
  grep -qi "bashbasicsbyvk_filepicker" "$ROOT/$f" && ok "$f names bashbasicsbyvk_filepicker" || bad "$f never names bashbasicsbyvk_filepicker"
done

# (5) AGENTS.md keeps the guide current
grep -q "agents_guide/filepicker.txt" "$ROOT/AGENTS.md" && ok "AGENTS.md carries the rule that keeps the picker guide current" || bad "AGENTS.md has no rule about script/agents_guide/filepicker.txt"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
