#!/usr/bin/env bash
# Build bvk-ls for every platform we ship (developer machine only).
# Output lands next to the source; commit the binaries so users never need a compiler.
#   ./build.sh          all targets (arm64 amd64 arm), static PIE
#   ./build.sh native   just this machine, as ./bvk-ls
#
# Cross compilers: override with CC_arm64 / CC_amd64 / CC_arm, e.g.
#   CC_arm64="zig cc -target aarch64-linux-musl" ./build.sh
# Defaults: musl-gcc style names, falling back to Debian's cross-gcc packages.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

CFLAGS_COMMON=(-std=c11 -O2 -Wall -Wextra -fPIE -Iinclude -D_FILE_OFFSET_BITS=64 -D_DEFAULT_SOURCE)
SRCS=(src/*.c)

if [ "${1:-}" = native ]; then
  make -s clean && make -s CC="${CC:-cc}"
  echo "built ./bvk-ls"; exit 0
fi

default_cc() {
  case "$1" in
    arm64) echo "${CC_arm64:-aarch64-linux-gnu-gcc}" ;;
    amd64) echo "${CC_amd64:-x86_64-linux-gnu-gcc}" ;;
    arm)   echo "${CC_arm:-arm-linux-gnueabihf-gcc}" ;;
  esac
}

for a in arm64 amd64 arm; do
  cc="$(default_cc "$a")"
  # shellcheck disable=SC2086  # $cc may be a multi-word command (zig cc ...)
  $cc "${CFLAGS_COMMON[@]}" -static-pie -s "${SRCS[@]}" -o "bvk-ls-linux-$a" -pthread
  echo "built bvk-ls-linux-$a"
done
