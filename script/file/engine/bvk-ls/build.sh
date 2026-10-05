#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CFLAGS_COMMON=(
  -std=c11
  -O2
  -Wall
  -Wextra
  -fPIE
  -Iinclude
  -D_FILE_OFFSET_BITS=64
  -D_DEFAULT_SOURCE
)

SRCS=(src/*.c)

if [ "${1:-}" = native ]; then
  make -s clean
  make -s CC="${CC:-cc}"
  echo "built ./bvk-ls"
  exit 0
fi

default_cc() {
  case "$1" in
    arm64)
      echo "${CC_arm64:-aarch64-linux-gnu-gcc}"
      ;;
    amd64)
      echo "${CC_amd64:-x86_64-linux-gnu-gcc}"
      ;;
    arm)
      echo "${CC_arm:-arm-linux-gnueabihf-gcc}"
      ;;
    *)
      echo "Unsupported architecture: $1" >&2
      return 1
      ;;
  esac
}

for a in arm64 amd64 arm; do
  cc="$(default_cc "$a")"

  if [ "$a" = arm ]; then
    $cc \
      "${CFLAGS_COMMON[@]}" \
      -static \
      -s \
      "${SRCS[@]}" \
      -o "bvk-ls-linux-$a" \
      -pthread
  else
    $cc \
      "${CFLAGS_COMMON[@]}" \
      -static-pie \
      -s \
      "${SRCS[@]}" \
      -o "bvk-ls-linux-$a" \
      -pthread
  fi

  echo "built bvk-ls-linux-$a"
done