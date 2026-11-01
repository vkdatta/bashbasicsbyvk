#!/usr/bin/env bash
# Start-up work that must not launch a process (each costs ~20 ms on a phone).     bash tests/startup_spawns.sh
# (1) _bvk_pathfind = the PATH search of $(command -v) without the fork  (2) a stale exported temp folder is replaced when displayer.sh loads
# (3) _bvk_tmp / the sort temp file / the size reuse use no mktemp and no rm once the temp folder exists
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D="$(find "$ROOT/script" -name bashbasicsbyvk_displayer.sh -print -quit)"; ET="$(find "$ROOT/script" -name bashbasicsbyvk_engine_target.sh -print -quit)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
mkdir -p "$T/a" "$T/b bin" "$T/nox"; printf '#!/bin/sh\n' >"$T/a/tool-x"; chmod +x "$T/a/tool-x"; cp "$T/a/tool-x" "$T/b bin/tool-y"; chmod +x "$T/b bin/tool-y"; : >"$T/nox/tool-z"

# (1) the PATH search
r() ( PATH="$1"; source "$D" 2>/dev/null; _bvk_pathfind "$2"; echo "rc=$? [$_BVK_PF]" )
[ "$(r "/nonexistent:$T/a:/usr/bin" tool-x)" = "rc=0 [$T/a/tool-x]" ] && ok "finds an executable on PATH" || bad "pathfind: $(r "/nonexistent:$T/a" tool-x)"
[ "$(r "$T/a:$T/b bin" tool-y)" = "rc=0 [$T/b bin/tool-y]" ] && ok "a folder with a space in its name" || bad "pathfind space: $(r "$T/a:$T/b bin" tool-y)"
[ "$(r "$T/nox:$T/a" tool-z)" = "rc=1 []" ] && ok "a file without the executable bit is skipped" || bad "pathfind non-exec: $(r "$T/nox:$T/a" tool-z)"
[ "$(r "$T/a" nothing-here)" = "rc=1 []" ] && ok "not found: rc 1 and empty" || bad "pathfind missing"
[ "$(r "$T/b bin:$T/a" tool-x)" = "rc=0 [$T/a/tool-x]" ] && ok "the first folder that has it wins" || bad "pathfind order"
cmp_v="$(PATH="$T/a:/usr/bin:/bin" bash -c 'command -v tool-x')"; [ "$cmp_v" = "$T/a/tool-x" ] && ok "same answer as command -v" || bad "command -v differs"

# (2) a stale exported temp folder
got="$(_BVK_DSIZE_TMP="$T/gone" bash -c "source '$D' 2>/dev/null; [ -d \"\$_BVK_DSIZE_TMP\" ] && [ \"\$_BVK_DSIZE_TMP\" != '$T/gone' ] && echo fresh")"
[ "$got" = fresh ] && ok "a removed temp folder from the environment is replaced at load" || bad "stale temp folder kept"
got="$(_BVK_DSIZE_TMP="$T/a" bash -c "source '$D' 2>/dev/null; echo \$_BVK_DSIZE_TMP")"
[ "$got" = "$T/a" ] && ok "a valid inherited temp folder is kept (no mktemp at start)" || bad "valid temp folder replaced: $got"

# (3) no mktemp / rm once the folder exists: PATH holds neither
mkdir -p "$T/nomk"; for c in bash cat sort cut; do ln -s "$(command -v $c)" "$T/nomk/$c" 2>/dev/null; done
out="$(PATH="$T/nomk" _BVK_DSIZE_TMP="$T/a" "$T/nomk/bash" -c "source '$D' 2>/dev/null; f=\$(_bvk_tmp x); [ -f \"\$f\" ] && case \$f in '$T/a'/*) echo in-dir;; esac; g=\$(_bvk_tmp x); [ \"\$f\" = \"\$g\" ] && echo same-file")"
grep -q in-dir <<<"$out" && ok "_bvk_tmp makes its file inside the session folder with no mktemp on PATH" || bad "_bvk_tmp needed mktemp: $out"
grep -q same-file <<<"$out" && ok "the same tag gives the same re-used file" || bad "tag not re-used"
grep -q 'tmp_in=$(_bvk_tmp sort_in)' "$D" && ! grep -q 'local tmp_in; tmp_in=$(mktemp)' "$D" && ok "the sort temp file (new / old / big / small) uses _bvk_tmp" || bad "sort still calls mktemp"
grep -q '_vp_probe_ttl' "$(find "$ROOT/script" -name bashbasicsbyvk_viewport.sh -print -quit)" && ok "the size probe reuse time is one variable" || bad "probe ttl"

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
