#!/usr/bin/env bash
# bashbasicsbyvk_xui_chmmenucommands.sh — commands of the Change Mode screen (it runs inside _xui_loop, handler _chm_cmd).
# Hand-kept: the screen shares _xui_loop with the other xui screens, so bashbasicsbyvk_mapgen cannot harvest it.
# A row number, N-R N-W N-X (with A / D) and the ←/→ tab keys are not words of the command layer: _chm_cmd reads them itself.
cmd_def rf     exact   -  local  "Refresh — read the permissions of the items again"
