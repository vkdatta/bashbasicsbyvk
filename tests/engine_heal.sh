#!/usr/bin/env bash
# The start-up engine check (_bvk_engine_heal): an install made for another CPU / OS offers a reinstall, builds fresh, restarts.   bash tests/engine_heal.sh
# Runs the real function under a pty (it needs a terminal) with stubs for the menu (_bvk_yn), the installer and `o`.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; S="$ROOT/script"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
T="$(find "$S" -name bashbasicsbyvk_engine_target.sh -print -quit)"; H="$(find "$S" -name bashbasicsbyvk_engine_heal.sh -print -quit)"
[ -n "$T" ] && [ -n "$H" ] || { bad "engine_target.sh / engine_heal.sh not found"; echo FAILED; exit 1; }
command -v python3 >/dev/null || { echo "SKIP: python3 missing"; exit 0; }
read -r OS M < <(bash -c 'source "$1"; _bvk_engine_target; echo "$_bet_os $_bet_m"' _ "$T")
[ -n "$M" ] || { echo "SKIP: no prebuilt engine for this CPU, nothing to heal"; exit 0; }
WANT="$OS-$M"; FOREIGN="darwin-arm64"; [ "$WANT" = "$FOREIGN" ] && FOREIGN="linux-amd64"

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/prefix/bin" "$W/prefix/bashbasicsbyvk/bin" "$W/cfg"
cat > "$W/prefix/bin/o" <<'X'
#!/usr/bin/env bash
echo "RESTARTED healed=${BVK_HEALED:-0} args=$*"
X
cat > "$W/prefix/bin/bashbasicsbyvk_upgrade_install" <<'X'
#!/usr/bin/env bash
echo "INSTALLER fresh=${BVK_REINSTALL_FRESH:-0}" >> "$BVK_TEST_LOG"
for e in ls fr xfer; do : > "$BVK_PREFIX/bashbasicsbyvk/bin/bvk-$e-$BVK_WANT"; done      # what a real reinstall does
exit "${BVK_INSTALL_RC:-0}"
X
chmod +x "$W/prefix/bin/o" "$W/prefix/bin/bashbasicsbyvk_upgrade_install"

# run <answer y|n> [extra env...]  -> prints what the shell printed (under a pty)
run() {
  local ans="$1"; shift
  env "$@" BVK_TEST_LOG="$W/log" BVK_PREFIX="$W/prefix" BVK_WANT="$WANT" BVK_ANS="$ans" CONFIG_DIR="$W/cfg" PATH="$W/prefix/bin:$PATH" \
    python3 - "$T" "$H" <<'PY'
import os, pty, sys
t, h = sys.argv[1:3]
code = 'source "%s"; source "%s"; _bvk_yn() { printf -v "$1" %%s "$BVK_ANS"; echo "ASKED: $2"; }; _bvk_engine_heal first-arg; echo "CONTINUED"' % (t, h)
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c", code])
out = b""
while True:
    try: d = os.read(fd, 4096)
    except OSError: break
    if not d: break
    out += d
os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
PY
}
fresh() { rm -f "$W/prefix/bashbasicsbyvk/bin"/bvk-* "$W/log" "$W/cfg/engine_heal_asked"; for e in ls fr xfer; do : > "$W/prefix/bashbasicsbyvk/bin/bvk-$e-$1"; done; }

fresh "$WANT"; out="$(run y)"
case "$out" in *ASKED*|*INSTALLER*) bad "engines of this machine present, but it asked / reinstalled: $out" ;; *CONTINUED*) ok "engines present: silent" ;; *) bad "did not continue: $out" ;; esac

fresh "$FOREIGN"; out="$(run y)"
case "$out" in *"made for $FOREIGN"*"is $WANT"*) ok "names both machines ($FOREIGN -> $WANT)" ;; *) bad "message missing: $out" ;; esac
case "$out" in *ASKED*) ok "asks before reinstalling" ;; *) bad "did not ask: $out" ;; esac
[ "$(cat "$W/log" 2>/dev/null)" = "INSTALLER fresh=1" ] && ok "installer ran once, with BVK_REINSTALL_FRESH=1" || bad "installer log: $(cat "$W/log" 2>/dev/null)"
case "$out" in *"RESTARTED healed=1 args=first-arg"*) ok "restarted the app with its arguments, healed=1" ;; *) bad "no restart: $out" ;; esac
case "$out" in *CONTINUED*) bad "kept running the old process after the restart" ;; *) ok "old process replaced (exec)" ;; esac

fresh "$FOREIGN"; out="$(run n)"
[ ! -f "$W/log" ] && ok "answer n: nothing installed" || bad "installed although the answer was n"
case "$out" in *CONTINUED*) ok "answer n: app continues" ;; *) bad "answer n: app stopped: $out" ;; esac
out="$(run y)"; case "$out" in *ASKED*) bad "asked again within a day" ;; *) ok "does not ask twice in one day" ;; esac

fresh "$FOREIGN"; out="$(run y BVK_NO_HEAL=1)"; case "$out" in *ASKED*|*INSTALLER*) bad "BVK_NO_HEAL=1 ignored" ;; *) ok "BVK_NO_HEAL=1 switches it off" ;; esac
fresh "$FOREIGN"; out="$(run y BVK_HEALED=1)"; case "$out" in *ASKED*|*INSTALLER*) bad "asked right after a heal (restart loop)" ;; *) ok "never loops after a heal" ;; esac
fresh "$FOREIGN"; out="$(run y BVK_INSTALL_RC=1)"; case "$out" in *"did not finish"*CONTINUED*) ok "failed reinstall: says so and the app continues" ;; *) bad "failed reinstall handled wrongly: $out" ;; esac

[ "$fail" = 0 ] && echo "ALL OK" || echo "FAILED"
exit "$fail"
