#!/usr/bin/env bash
# bvk-fr (find & replace engine): same targets and flags as bvk-ls, so the one build script of bvk-ls does the work.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BVK_NAME=bvk-fr BVK_DIR="$here" BVK_EXTRA_DEFS=-D_GNU_SOURCE exec "$here/../bvk-ls/bashbasicsbyvk_build.sh" "$@"
