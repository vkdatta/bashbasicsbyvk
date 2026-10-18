# Services built on top of the fileapi: Backup (before delete), Saved Surf (save-), Snapshots (snap-).
# Order matters: the core first (it pulls in the fileapi staging + lib), then the three services.
_lt_b "load svc_core"; source "bashbasicsbyvk_svc_core.sh"; _lt_e
_lt_b "load backup"; source "bashbasicsbyvk_backup.sh"; _lt_e
_lt_b "load saved"; source "bashbasicsbyvk_saved.sh"; _lt_e
_lt_b "load snapshot"; source "bashbasicsbyvk_snapshot.sh"; _lt_e
