#!/usr/bin/env bash

set -euo pipefail

# One build script for both C engines: bvk-fr/bashbasicsbyvk_build.sh runs this one with BVK_NAME=bvk-fr BVK_DIR=<its folder>.
# Targets, in four groups (BVK_ONLY="linux darwin" builds just those; default = every group this machine can build):
#   linux    {arm64 amd64 arm 386}   glibc cross gcc, static            (apt: gcc-aarch64-linux-gnu gcc-x86-64-linux-gnu gcc-arm-linux-gnueabihf gcc-i686-linux-gnu)
#   android  {arm64 amd64 arm}       NDK clang, bionic                  (REQUIRE_ANDROID=1 makes a missing NDK an error)
#   darwin   {arm64 amd64}           Apple clang on a Mac, else zig cc  (REQUIRE_DARWIN=1)
#   freebsd  {amd64}                 zig cc                             (REQUIRE_FREEBSD=1)
NAME="${BVK_NAME:-bvk-ls}"
cd "${BVK_DIR:-$(dirname "${BASH_SOURCE[0]}")}"

CFLAGS_COMMON=(
  -std=c11
  -O2
  -Wall
  -Wextra
  -fPIE
  -Iinclude
  -D_FILE_OFFSET_BITS=64
  -D_DEFAULT_SOURCE
  ${BVK_EXTRA_DEFS:+$BVK_EXTRA_DEFS}
)

SRCS=(src/*.c)

want() { case " ${BVK_ONLY:-linux android darwin freebsd} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# macOS / FreeBSD headers hide POSIX / BSD names under strict -std=c11; gnu11 drops __STRICT_ANSI__ (same code, no extra names needed)
CFLAGS_BSD=("${CFLAGS_COMMON[@]/-std=c11/-std=gnu11}")

if [ "${1:-}" = native ]; then
  make -s -f bashbasicsbyvk_Makefile clean
  make -s -f bashbasicsbyvk_Makefile CC="${CC:-cc}"
  echo "built ./$NAME"
  exit 0
fi

default_cc() {
  case "$1" in
    arm64) echo "${CC_arm64:-aarch64-linux-gnu-gcc}" ;;
    amd64) echo "${CC_amd64:-x86_64-linux-gnu-gcc}" ;;
    arm)   echo "${CC_arm:-arm-linux-gnueabihf-gcc}" ;;
    386)   echo "${CC_386:-i686-linux-gnu-gcc}" ;;
    *)     echo "Unsupported architecture: $1" >&2; return 1 ;;
  esac
}

if want linux; then
  for a in arm64 amd64 arm 386; do
    cc="$(default_cc "$a")"
    # static-pie where glibc supports it everywhere (64-bit); plain static for the 32-bit CPUs
    case "$a" in arm|386) link=(-static) ;; *) link=(-static-pie) ;; esac
    $cc "${CFLAGS_COMMON[@]}" "${link[@]}" -s "${SRCS[@]}" -o "${NAME}-linux-$a" -pthread
    echo "built ${NAME}-linux-$a"
  done
fi

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

if want android && NDK="$(find_ndk)"; then
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
      -o "${NAME}-android-$a"
    echo "built ${NAME}-android-$a"
  done
elif want android; then
  echo "Android NDK not found; skipping ${NAME}-android-* (set ANDROID_NDK_HOME)" >&2
  if [ "${REQUIRE_ANDROID:-0}" = 1 ]; then exit 1; fi
fi

# ── macOS (darwin) builds ─────────────────────────────────────────────────────────────────────────────────────────────
# On a Mac: Apple clang, one -arch per CPU (the macos runner can build both).  Elsewhere: zig cc (bundles the macOS SDK stubs).
# macOS has no static linking, so these are normal dynamic executables; the minimum macOS is the oldest Go supports (10.15 / 11).
if want darwin; then
  built=0
  for pair in "arm64:aarch64-macos:11.0" "amd64:x86_64-macos:10.15"; do
    a="${pair%%:*}"; rest="${pair#*:}"; zt="${rest%%:*}"; minos="${rest#*:}"
    out="${NAME}-darwin-$a"
    if [ "$(uname -s)" = Darwin ]; then
      arch="$a"; [ "$a" = amd64 ] && arch=x86_64
      cc -arch "$arch" -mmacosx-version-min="$minos" "${CFLAGS_BSD[@]}" "${SRCS[@]}" -o "$out" -pthread
      strip -x "$out"
    elif command -v zig >/dev/null 2>&1; then
      zig cc -target "$zt" "${CFLAGS_BSD[@]}" -s "${SRCS[@]}" -o "$out" -pthread
    else
      continue
    fi
    echo "built $out"; built=1
  done
  if [ "$built" = 0 ]; then
    echo "no macOS toolchain (a Mac, or zig); skipping ${NAME}-darwin-*" >&2
    if [ "${REQUIRE_DARWIN:-0}" = 1 ]; then exit 1; fi
  fi
fi

# ── FreeBSD builds (zig cc: cross-compiles against FreeBSD libc stubs; the result is a normal dynamic FreeBSD executable) ─────────
# Needs zig >= 0.15 and an explicit FreeBSD version: older zig has no FreeBSD libc headers, and the default target (freebsd.13) has no libc in zig.
if want freebsd; then
  if command -v zig >/dev/null 2>&1; then
    zig cc -target x86_64-freebsd.14.0 "${CFLAGS_BSD[@]}" -s "${SRCS[@]}" -o "${NAME}-freebsd-amd64" -pthread
    echo "built ${NAME}-freebsd-amd64"
  else
    echo "zig not found; skipping ${NAME}-freebsd-* (https://ziglang.org/download/)" >&2
    if [ "${REQUIRE_FREEBSD:-0}" = 1 ]; then exit 1; fi
  fi
fi
