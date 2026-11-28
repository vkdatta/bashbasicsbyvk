#include "bashbasicsbyvk_bvk.h"

#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Recursive size (apparent size, like `ls -l` / `du -b`): directories (by d_type, symlinks not
 * followed) are walked; EVERY other entry (file, symlink, fifo, socket, device) contributes its
 * lstat size, which is exactly what the Python fallback counts (the two engines must agree).
 * A file with several hard links is counted ONCE per call (dev+inode), like du.
 * A folder that cannot be opened at all returns -1 (the list shows "---"), never a made-up 0.
 * A sub-folder that cannot be opened counts 0, as du does. */

typedef struct { dev_t dev; ino_t ino; int64_t size; } hl_t;
typedef struct { hl_t *v; size_t n, cap; } hlv_t;

static int hl_cmp(const void *a, const void *b) {
    const hl_t *x = a, *y = b;
    if (x->dev != y->dev) return x->dev < y->dev ? -1 : 1;
    if (x->ino != y->ino) return x->ino < y->ino ? -1 : 1;
    return 0;
}

static void hl_add(hlv_t *h, const struct stat *st) {
    if (h->n == h->cap) {
        h->cap = h->cap ? h->cap * 2 : 64;
        h->v = xrealloc(h->v, h->cap * sizeof *h->v);
    }
    h->v[h->n].dev = st->st_dev;
    h->v[h->n].ino = st->st_ino;
    h->v[h->n].size = (int64_t)st->st_size;
    h->n++;
}

/* returns the total of this tree; multi-link files go to h instead of the total */
static int64_t walk(const char *d, hlv_t *h, bool *opened) {
    DIR *dp = opendir(d);
    if (!dp) { if (opened) *opened = false; return 0; }
    if (opened) *opened = true;
    int64_t total = 0;
    struct dirent *e;
    while ((e = readdir(dp)) != NULL) {
        const char *nm = e->d_name;
        if (nm[0] == '.' && (nm[1] == 0 || (nm[1] == '.' && nm[2] == 0))) continue;

        char *full = path_join(d, nm);
        if (e->d_type == DT_DIR) {
            total += walk(full, h, NULL);
        } else {
            struct stat st;
            if (lstat(full, &st) == 0) {
                if (S_ISDIR(st.st_mode)) total += walk(full, h, NULL);
                else if (st.st_nlink > 1 && !S_ISLNK(st.st_mode)) hl_add(h, &st);
                else total += (int64_t)st.st_size;
            }
        }
        free(full);
    }
    closedir(dp);
    return total;
}

int64_t dir_size(const char *root) {
    hlv_t h = {0};
    bool opened = true;
    int64_t total = walk(root, &h, &opened);
    if (!opened) { free(h.v); return -1; }
    if (h.n) {
        qsort(h.v, h.n, sizeof *h.v, hl_cmp);
        for (size_t i = 0; i < h.n; i++)
            if (i == 0 || hl_cmp(&h.v[i], &h.v[i - 1]) != 0) total += h.v[i].size;
    }
    free(h.v);
    return total;
}
