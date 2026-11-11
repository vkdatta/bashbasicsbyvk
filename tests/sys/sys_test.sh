#!/usr/bin/env bash
# The `sys` command (bashbasicsbyvk_sys): the screen prints every field and never crashes; --device names the kind of device (the id the dependency
# installer picks its install steps by) for each environment we can fake without the real thing.   bash tests/sys/sys_test.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; source "$ROOT/tests/wait_lib.sh"
fail=0; ok() { echo "  ok   $*"; }; bad() { echo "  FAIL $*"; fail=1; }
SYS="$(bvk_need bashbasicsbyvk_sys)"
dev() { env -i PATH="$PATH" HOME="${HOME:-/tmp}" "$@" python3 -I "$SYS" --device 2>&1; }

out="$(python3 -I "$SYS" 2>&1)"; rc=$?
missing=""; for k in OS Host Kernel Uptime Packages Shell Display WM Terminal CPU Activity Temperature Memory Disk Battery; do echo "$out" | grep -qE "^$k +[^ ]" || missing="$missing $k"; done
[ $rc = 0 ] && [ -z "$missing" ] && ! echo "$out" | grep -q Traceback && ok "sys prints all 15 fields" || bad "sys screen wrong rc=$rc missing:$missing"

id="$(dev)"; echo "$id" | grep -qxE "termux|linux|server|wsl2|wsl1|macos-arm|macos-intel|rpi|chromeos|container|gcloud|awscs|azurecs|codespaces|notebook|freebsd|android-other|other" \
  && ok "--device answers one known id ($id)" || bad "--device answered '$id'"
[ "$(dev CODESPACES=1)" = codespaces ]           && ok "GitHub Codespaces"        || bad "codespaces: $(dev CODESPACES=1)"
[ "$(dev CLOUD_SHELL=true)" = gcloud ]           && ok "Google Cloud Shell"       || bad "gcloud: $(dev CLOUD_SHELL=true)"
[ "$(dev AWS_EXECUTION_ENV=CloudShell)" = awscs ] && ok "AWS CloudShell"          || bad "awscs: $(dev AWS_EXECUTION_ENV=CloudShell)"
[ "$(dev ACC_CLOUD=1)" = azurecs ]               && ok "Azure Cloud Shell"        || bad "azurecs: $(dev ACC_CLOUD=1)"
[ "$(dev COLAB_RELEASE_TAG=x)" = notebook ]      && ok "Colab / Kaggle / Replit"  || bad "notebook: $(dev COLAB_RELEASE_TAG=x)"
t="$(dev ANDROID_ROOT=/system PREFIX=/data/data/com.termux/files/usr)"; [ "$t" = termux ] && ok "Termux" || bad "termux: $t"
t="$(dev ANDROID_ROOT=/system)"; [ "$t" = android-other ] && ok "Android without Termux" || bad "android-other: $t"
python3 -I "$SYS" --nonsense >/dev/null 2>&1; [ $? = 2 ] && ok "an unknown option is refused (rc 2)" || bad "unknown option accepted"
exit $fail
