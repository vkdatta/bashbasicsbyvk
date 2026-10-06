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

# ── Android (bionic) builds ────────────────────────────────────────────────
# The glibc static builds above cannot run on Android: the Android linker
# rejects a static-pie binary (no PT_PHDR) and aborts. These are normal
# dynamically linked PIE executables built with the NDK clang against bionic.
# Needs the Android NDK: set ANDROID_NDK_HOME / ANDROID_NDK_LATEST_HOME, or have
# $ANDROID_HOME/ndk/<version> installed (GitHub's ubuntu runners do).
ANDROID_API="${ANDROID_API:-24}"

find_ndk() {
  local d
  for d in "${ANDROID_NDK_LATEST_HOME:-}" "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [ -n "$d" ] && [ -d "$d/toolchains/llvm/prebuilt" ] && { echo "$d"; return 0; }
  done
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk" ]; then
    d="$(ls -d "$ANDROID_HOME"/ndk/*/ 2>/dev/null | sort -V | tail -n 1)"
    d="${d%/}"
    [ -n "$d" ] && [ -d "$d/toolchains/llvm/prebuilt" ] && { echo "$d"; return 0; }
  fi
  return 1
}

if NDK="$(find_ndk)"; then
  BIN="$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)"
  for pair in \
    "arm64:aarch64-linux-android${ANDROID_API}-clang" \
    "arm:armv7a-linux-androideabi${ANDROID_API}-clang" \
    "amd64:x86_64-linux-android${ANDROID_API}-clang"; do
    a="${pair%%:*}"
    cc="$BIN/${pair#*:}"
    "$cc" \
      "${CFLAGS_COMMON[@]}" \
      -pie \
      -s \
      "${SRCS[@]}" \
      -o "bvk-ls-android-$a"
    echo "built bvk-ls-android-$a"
  done
else
  echo "Android NDK not found; skipping bvk-ls-android-* (set ANDROID_NDK_HOME)" >&2
  if [ "${REQUIRE_ANDROID:-0}" = 1 ]; then exit 1; fi
fi
