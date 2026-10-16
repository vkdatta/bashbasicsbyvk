# Services built on top of the fileapi: Backup (before delete), Saved Surf (save-), Snapshots (snap-).
# Order matters: the core first (it pulls in the fileapi staging + lib), then the three services.
source "bashbasicsbyvk_svc_core.sh"
source "bashbasicsbyvk_backup.sh"
source "bashbasicsbyvk_saved.sh"
source "bashbasicsbyvk_snapshot.sh"
