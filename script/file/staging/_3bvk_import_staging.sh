# !buffer
_lt_b "load staging_helpers"; source "bashbasicsbyvk_staging_helpers.sh"; _lt_e   # before map/move/copy/shortcut/bookmark: they use its _sp_* helpers
_lt_b "load staging_archive"; source "bashbasicsbyvk_staging_archive.sh"; _lt_e
_lt_b "load staging_map"; source "bashbasicsbyvk_staging_map.sh"; _lt_e

# buffer!
_lt_b "load staging_move"; source "bashbasicsbyvk_staging_move.sh"; _lt_e
_lt_b "load staging_copy"; source "bashbasicsbyvk_staging_copy.sh"; _lt_e
_lt_b "load staging_shortcut"; source "bashbasicsbyvk_staging_shortcut.sh"; _lt_e
_lt_b "load staging_shortcut_registry"; source "bashbasicsbyvk_staging_shortcut_registry.sh"; _lt_e
_lt_b "load staging_bookmark"; source "bashbasicsbyvk_staging_bookmark.sh"; _lt_e
_lt_b "load staging_buffer"; source "bashbasicsbyvk_staging_buffer.sh"; _lt_e