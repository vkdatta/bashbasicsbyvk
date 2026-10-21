#!/usr/bin/env bash
# Builds bvk-xfer for every machine the app runs on:  bvk-xfer-{linux,android}-{amd64,arm64,arm}
# Needs only the Go toolchain (>= 1.21).  Pure Go, no cgo, fully static, cross-compiled from any host.
#
# "android-*": a static Linux binary runs fine on Android (Termux, adb shell) because netx.go brings its own DNS fallback and CA
# loading.  With the NDK present (ANDROID_NDK_HOME …) they are built as real GOOS=android binaries instead (cgo + NDK clang).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
command -v go >/dev/null || { echo "Go toolchain not found (https://go.dev/dl/)" >&2; exit 1; }

build() {   # build <outname> <GOOS> <GOARCH> [GOARM]
  local out="$1" os="$2" arch="$3" arm="${4:-}"
  env CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" ${arm:+GOARM="$arm"} \
    go build -trimpath -ldflags="-s -w" -o "$out" .
  echo "built $out"
}

for a in amd64 arm64; do build "bvk-xfer-linux-$a" linux "$a"; done
build bvk-xfer-linux-arm linux arm 7

find_ndk() {
  local d
  for d in "${ANDROID_NDK_LATEST_HOME:-}" "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [ -n "$d" ] && [ -d "$d/toolchains/llvm/prebuilt" ] && { echo "$d"; return 0; }
  done
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME/ndk" ]; then
    d="$(ls -d "$ANDROID_HOME"/ndk/*/ 2>/dev/null | sort -V | tail -n 1)"; d="${d%/}"
    [ -n "$d" ] && [ -d "$d/toolchains/llvm/prebuilt" ] && { echo "$d"; return 0; }
  fi
  return 1
}

ANDROID_API="${ANDROID_API:-24}"
if NDK="$(find_ndk)"; then
  BIN="$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)"
  for t in "arm64 arm64 aarch64-linux-android" "amd64 amd64 x86_64-linux-android" "arm arm armv7a-linux-androideabi"; do
    set -- $t
    if [ "$2" = arm ]; then export GOARM=7; else unset GOARM; fi
    CC="$BIN/$3${ANDROID_API}-clang" CGO_ENABLED=1 GOOS=android GOARCH="$2" go build -trimpath -ldflags="-s -w" -o "bvk-xfer-android-$1" .
    echo "built bvk-xfer-android-$1 (NDK)"
  done
  unset GOARM
else
  for a in amd64 arm64; do cp "bvk-xfer-linux-$a" "bvk-xfer-android-$a"; echo "bvk-xfer-android-$a = static linux build (no NDK found; works on Android)"; done
  cp bvk-xfer-linux-arm bvk-xfer-android-arm; echo "bvk-xfer-android-arm = static linux build"
fi
