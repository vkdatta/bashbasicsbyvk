#!/usr/bin/env bash
# Central dependency installer: registry shape, detection, the Installer menu, install lanes (fake package manager, nothing real is installed),
# yes / no / no-terminal answers, optional-decline memory, quiet mode, and a run under `set -Eeuo pipefail`.   bash tests/deps/deps_test.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$ROOT/tests/wait_lib.sh"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
DEPS="$(bvk_need bashbasicsbyvk_deps.sh)"; REG="$(bvk_need bashbasicsbyvk_deps.list)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME" "$W/bin"; export BVK_DEPS_STATE="$W/state" BVK_DEPS_LOG="$W/log"

# (1) registry: every line well formed, every feature token and every `needs` names a dependency, no id used twice
python3 -I - "$REG" <<'PY' && ok "registry is well formed" || bad "registry is malformed"
import sys
D, F, G = {}, {}, []
for n, l in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    l = l.rstrip("\n")
    if not l.strip() or l.startswith("#"): continue
    f = l.split("|"); t = f[0]
    if t == "D":
        assert len(f) == 10, f"line {n}: D needs 10 fields, has {len(f)}"
        assert f[1] not in D, f"line {n}: duplicate id {f[1]}"; D[f[1]] = f
        assert f[2] in ("cmd", "pymod", "pip", "npm", "file"), f"line {n}: kind {f[2]}"
    elif t == "G": assert len(f) == 7, f"line {n}: G needs 7 fields"; G.append(f)
    elif t == "F":
        assert len(f) == 5, f"line {n}: F needs 5 fields"; assert f[1] not in F and f[1] not in D, f"line {n}: duplicate {f[1]}"; F[f[1]] = f
    else: raise SystemExit(f"line {n}: unknown type {t!r}")
known = lambda x: x in D or any(x.startswith(g[1]) for g in G)
for f in D.values():
    for x in f[7].split(): assert known(x), f"{f[1]} needs unknown {x}"
for f in F.values():
    for x in (f[3] + " " + f[4]).split():
        for a in x.split("/"): assert known(a), f"feature {f[1]}: unknown dependency {a}"
for g in G:
    for x in g[4].split(): assert known(x), f"group {g[1]} needs unknown {x}"
PY

# (2) a fake world: a fake package manager "apt-get" that creates the program it was asked for
cat > "$W/bin/apt-get" <<'FAKE'
#!/usr/bin/env bash
echo "apt-get $*" >> "$FAKELOG"
[ "$1" = install ] || exit 0
[ -n "$FAKE_RC" ] && [ "$FAKE_RC" != 0 ] && exit "$FAKE_RC"
shift; [ "$1" = -y ] && shift
for p in "$@"; do case "$p" in 7zip|p7zip-full) printf '#!/bin/sh\n' > "$FAKEBIN/7zz" ;; zstd|lz4|rclone|sqlite3) printf '#!/bin/sh\n' > "$FAKEBIN/${p}" ;; esac; done
for p in "$@"; do [ -f "$FAKEBIN/7zz" ] && chmod +x "$FAKEBIN/7zz"; [ -f "$FAKEBIN/$p" ] && chmod +x "$FAKEBIN/$p"; done
exit "${FAKE_RC:-0}"
FAKE
chmod +x "$W/bin/apt-get"; export FAKELOG="$W/fake.log" FAKEBIN="$W/bin"
# PATH: the fake dir first, then only what a clean machine has (no 7z / zstd / rclone)
run() { PATH="$W/bin:$SAFE" BVK_DEPS_MANAGER=apt "$@"; }
SAFE="$PATH"; for t in 7zz 7z 7za 7zr zstd rclone lz4 sqlite3; do p="$(command -v $t 2>/dev/null)" && SAFE="$(echo "$SAFE" | tr ':' '\n' | grep -vxF "$(dirname "$p")" | paste -sd:)"; done
export BVK_DEPS_REGISTRY="$REG"

# (3) nothing missing: silent, rc 0
out="$(run bash "$DEPS" python3 2>&1)"; rc=$?
[ $rc = 0 ] && [ -z "$out" ] && ok "present dependency: silent, rc 0" || bad "present dependency printed '$out' rc=$rc"

# (4) missing + check only: the Installer text, the exact command, rc 1, nothing installed
out="$(run bash "$DEPS" -n -c "Make a .7z" archive.create.7z 2>&1)"; rc=$?
[ $rc = 1 ] && echo "$out" | grep -q "Installer" && echo "$out" | grep -q '"Make a .7z" requires' && echo "$out" | grep -q "apt-get install -y 7zip" && ok "menu lists the dependency and its command" || bad "check-only output wrong rc=$rc: $out"
[ ! -e "$FAKELOG" ] && ok "check only installs nothing" || bad "check only ran the package manager"

# (5) no terminal and no answer: nothing installed, rc 1, says how to proceed
out="$(run bash "$DEPS" archive.create.7z 2>&1 </dev/null)"; rc=$?
[ $rc = 1 ] && echo "$out" | grep -q "BVK_DEPS_ASSUME=yes" && ok "no terminal: asks nothing, explains" || bad "no-terminal handling wrong rc=$rc"

# (6) the answer no: rc 1, nothing installed
out="$(run env BVK_DEPS_ASSUME=no bash "$DEPS" archive.create.7z 2>&1)"; rc=$?
[ $rc = 1 ] && [ ! -e "$FAKELOG" ] && ok "answer no: rc 1, nothing installed" || bad "answer no wrong rc=$rc"

# (7) the answer yes: installed with ONE package-manager call, found afterwards, rc 0
out="$(run env BVK_DEPS_ASSUME=yes bash "$DEPS" archive.create.7z zstd lz4 2>&1)"; rc=$?
[ $rc = 0 ] && ok "answer yes: rc 0" || bad "answer yes rc=$rc: $out"
[ "$(grep -c '^apt-get install' "$FAKELOG")" = 1 ] && grep -q 'install -y .*7zip' "$FAKELOG" && grep -q zstd "$FAKELOG" && ok "all system packages in ONE call" || bad "expected one apt-get install: $(cat "$FAKELOG")"
out="$(run bash "$DEPS" archive.create.7z 2>&1)"; [ $? = 0 ] && [ -z "$out" ] && ok "installed dependency is found afterwards" || bad "not found after install: $out"

# (8) a failing install is reported and rc 1
rm -f "$W/bin/7zz" "$FAKELOG"
out="$(run env BVK_DEPS_ASSUME=yes FAKE_RC=1 bash "$DEPS" archive.create.7z 2>&1)"; rc=$?
[ $rc = 1 ] && echo "$out" | grep -q "could not be installed" && ok "failed install: rc 1 and says so" || bad "failed install wrong rc=$rc"

# (9) either-or token: unzip/7z is satisfied by 7-Zip alone
printf '#!/bin/sh\n' > "$W/bin/7zz"; chmod +x "$W/bin/7zz"
NOUNZIP="$W/nounzip"; mkdir -p "$NOUNZIP"
rm -f "$FAKELOG"; out="$(PATH="$W/bin:$SAFE" BVK_DEPS_MANAGER=apt bash -c 'source "$1"; _dep_have archive.extract.zip; echo $?' _ "$DEPS")"
[ "$out" = 0 ] && ok "unzip/7z: either one is enough (7z present)" || bad "alt token failed ($out)"
rm -f "$W/bin/7zz"

# (10) optional dependency: declined once is not offered again; a missing REQUIRED one still fails
out="$(run env BVK_DEPS_ASSUME=no bash "$DEPS" python3 '?zstd' 2>&1)"; rc=$?
[ $rc = 0 ] && ok "declined optional: rc 0 (required is there)" || bad "optional decline rc=$rc"
mkdir -p "$BVK_DEPS_STATE"; : > "$BVK_DEPS_STATE/lz4.declined"
out="$(run bash "$DEPS" python3 '?lz4' 2>&1 </dev/null)"; [ -z "$out" ] && ok "a recently declined optional is not offered again" || bad "declined optional offered again: $out"

# (11) platform without an install route (termux-only dependency on apt): says so, no command
out="$(run bash "$DEPS" -n termux-api 2>&1)"; echo "$out" | grep -q "no automatic install" && ok "not installable here is said plainly" || bad "N/A not reported: $out"

# (12) unknown name: rc 2
run bash "$DEPS" no_such_thing >/dev/null 2>&1; [ $? = 2 ] && ok "unknown id: rc 2" || bad "unknown id rc"

# (13) pip family member is synthesised from its G line
out="$(run bash "$DEPS" -n tree_sitter_python 2>&1)"; echo "$out" | grep -q "tree-sitter-python" && ok "tree_sitter_<lang> resolves to its pip package" || bad "group id not resolved: $out"

# (14) the same call works under set -Eeuo pipefail (gitpush / py_audit run that way)
out="$(PATH="$W/bin:$SAFE" BVK_DEPS_MANAGER=apt BVK_DEPS_ASSUME=yes bash -c 'set -Eeuo pipefail; source "$1"; _dep_need -c t zstd || exit 7; command -v zstd >/dev/null' _ "$DEPS" 2>&1)"; rc=$?
[ $rc = 0 ] && ok "works under set -Eeuo pipefail" || bad "set -Eeuo pipefail run failed rc=$rc: $out"

# (15) the registry is the one source: no private installers / hints left in script/
leftover="$(grep -rnE 'pkg install|apt(-get)? install|pip3? install|npm install|brew install|please install' "$ROOT/script" --include='*' 2>/dev/null | grep -vE 'bashbasicsbyvk_deps\.(sh|list|py)|_3bvk_import|README|health|bashbasicsbyvk_upgrade_install|# ' | head -5)"
[ -z "$leftover" ] && ok "no private install hints left outside the registry" || { bad "private install hints remain:"; echo "$leftover"; }
exit $fail
