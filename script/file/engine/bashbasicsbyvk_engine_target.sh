#!/usr/bin/env bash
# Loaded by _3bvk_import_engine.sh (the app) and by the stand-alone cmd import files (copy, delete), which cannot load displayer.sh.
# _bvk_engine_target — which prebuilt engine binary fits this machine: sets _bet_m (arm64 | amd64 | arm | "" = none) and
# _bet_os (android | linux).  ONE place for bvk-ls, bvk-fr (find & replace) and anything else that ships per-CPU binaries.
#   Android (bionic) cannot run the static glibc "linux" builds: its linker needs PT_PHDR, which a glibc static-pie binary
#   does not have, and aborts ("Could not find a PHDR: broken executable?"). Android uses the NDK "android" builds.
_bvk_engine_target() {
  case "$(uname -m)" in
    aarch64|arm64) _bet_m=arm64 ;;
    x86_64|amd64)  _bet_m=amd64 ;;
    armv7*|armv8l) _bet_m=arm ;;
    *)             _bet_m="" ;;
  esac
  # $OSTYPE says "linux-android" on Android: saves a process (~20 ms on a phone); else ask uname
  case "$OSTYPE" in
    *android*) _bet_os=android ;;
    *) case "$(uname -o 2>/dev/null)" in Android) _bet_os=android ;; *) _bet_os=linux ;; esac ;;
  esac
}
