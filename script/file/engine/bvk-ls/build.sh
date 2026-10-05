#!/usr/bin/env bash
# Build bvk-ls for every platform we ship. Needs Go >= 1.21 (developer machine only).
# Output lands next to the source; commit the binaries so users never need Go.
#   ./build.sh          all targets
#   ./build.sh native   just this machine, as ./bvk-ls
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
FLAGS=(-trimpath -ldflags "-s -w")
export CGO_ENABLED=0
if [ "${1:-}" = native ]; then
  go build "${FLAGS[@]}" -o bvk-ls .
  echo "built ./bvk-ls"; exit 0
fi
for a in arm64 amd64 arm; do
  GOOS=linux GOARCH=$a go build "${FLAGS[@]}" -o "bvk-ls-linux-$a" .
  echo "built bvk-ls-linux-$a"
done
