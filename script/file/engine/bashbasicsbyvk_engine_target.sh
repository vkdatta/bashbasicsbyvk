#!/usr/bin/env bash
# Loaded by the load mapper (the app) and by the stand-alone cmd import files (copy, delete), which cannot load displayer.sh.
# Also run by setup.py at install time (bash -c 'source <this file>; _bvk_engine_target') so the wheel ships only this machine's binaries.
# _bvk_engine_target — which prebuilt engine binary fits this machine: sets _bet_m (arm64 | amd64 | arm | 386 | "" = none) and
# _bet_os (android | linux | darwin | freebsd).  ONE place for bvk-ls, bvk-fr (find & replace), bvk-xfer and anything else that ships per-CPU binaries.
#   Android (bionic) cannot run the static glibc "linux" builds: its linker needs PT_PHDR, which a glibc static-pie binary
#   does not have, and aborts ("Could not find a PHDR: broken executable?"). Android uses the NDK "android" builds.
_bvk_engine_target() {
  case "$(uname -m)" in
    aarch64|arm64) _bet_m=arm64 ;;
    x86_64|amd64)  _bet_m=amd64 ;;
    i[3-6]86)      _bet_m=386 ;;
    armv7*|armv8l) _bet_m=arm ;;
    *)             _bet_m="" ;;
  esac
  # $OSTYPE says "linux-android" / "darwin23.0" / "freebsd14.0" : saves a process (~20 ms on a phone); else ask uname
  case "$OSTYPE" in
    *android*) _bet_os=android ;;
    darwin*)   _bet_os=darwin ;;
    freebsd*)  _bet_os=freebsd ;;
    *) case "$(uname -o 2>/dev/null)" in Android) _bet_os=android ;; *) _bet_os=linux ;; esac ;;
  esac
  # no android build for 386, and no 32-bit arm / 386 build for darwin / freebsd: report "no binary" instead of a wrong name
  case "$_bet_os/$_bet_m" in android/386|darwin/arm|darwin/386|freebsd/arm|freebsd/386|freebsd/arm64) _bet_m="" ;; esac
}
