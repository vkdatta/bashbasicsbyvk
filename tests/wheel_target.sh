#!/usr/bin/env bash
# A wheel carries the binaries of ONE machine and is tagged for it (never py3-none-any):   bash tests/wheel_target.sh
# Builds wheels offline from a scratch copy of the tree (fake binaries fill in whatever CI has not built yet) and checks, per BVK_TARGET:
#   (1) exactly bvk-{ls,fr,xfer}-<that target> is inside   (2) the wheel is a platform wheel with the matching tag   (3) a native build picks the running machine
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
python3 -c 'import setuptools' 2>/dev/null || { echo "SKIP: python3 setuptools missing"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/src"; cp -r "$ROOT/script" "$ROOT/setup.py" "$ROOT/setup.cfg" "$ROOT/MANIFEST.in" "$ROOT/pyproject.toml" "$ROOT/README.md" "$ROOT/LICENSE" "$W/src/" 2>/dev/null
TARGETS="android-amd64 android-arm android-arm64 linux-amd64 linux-arm linux-arm64 linux-386 darwin-amd64 darwin-arm64 freebsd-amd64"
for e in ls fr xfer; do d="$(find "$W/src/script" -type d -name "bvk-$e" -print -quit)"; for t in $TARGETS; do [ -e "$d/bvk-$e-$t" ] || printf '\177ELFfake' > "$d/bvk-$e-$t"; done; done

build() { # build <outdir> [BVK_TARGET]   -> prints the wheel path
  rm -rf "$W/src/build" "$W/src"/*.egg-info; mkdir -p "$1"
  ( cd "$W/src" && BVK_TARGET="${2:-}" python3 -m pip wheel -q --no-build-isolation --no-deps -w "$1" . >"$1/log" 2>&1 ) || { cat "$1/log" | tail -5; return 1; }
  ls "$1"/*.whl
}
inside() { python3 -c 'import sys,zipfile; print(" ".join(sorted(n.rsplit("/",1)[1] for n in zipfile.ZipFile(sys.argv[1]).namelist() if "/bvk-" in n)))' "$1"; }

for t in $TARGETS; do
  w="$(build "$W/o_$t" "$t")" || { bad "$t: wheel did not build"; continue; }
  got="$(inside "$w")"; want="bvk-fr-$t bvk-ls-$t bvk-xfer-$t"
  [ "$got" = "$want" ] && ok "$t: only its own 3 binaries" || bad "$t: has [$got] want [$want]"
  case "$w" in *-py3-none-any.whl) bad "$t: tagged py3-none-any (pip would reuse it on another CPU)" ;; *-py3-none-*.whl) ok "$t: platform tag $(basename "$w" .whl | sed 's/.*-py3-none-//')" ;; *) bad "$t: odd name $w" ;; esac
done

# native build = the machine we run on
read -r _os _m < <(bash -c 'source "$1"; _bvk_engine_target; echo "$_bet_os $_bet_m"' _ "$(find "$ROOT/script" -name bashbasicsbyvk_engine_target.sh -print -quit)")
if [ -n "$_m" ]; then
  w="$(build "$W/o_native")" && { got="$(inside "$w")"; want="bvk-fr-$_os-$_m bvk-ls-$_os-$_m bvk-xfer-$_os-$_m"; [ "$got" = "$want" ] && ok "native ($_os-$_m): only its own binaries" || bad "native: has [$got] want [$want]"; } || bad "native wheel did not build"
else ok "native: no prebuilt engine for this CPU (nothing to check)"; fi
[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
