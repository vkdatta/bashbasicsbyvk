#include "bvk.h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void ents_push(ents_t *e, ent_t x) {
    if (e->n == e->cap) {
        e->cap = e->cap ? e->cap * 2 : 4096;
        e->v = xrealloc(e->v, e->cap * sizeof *e->v);
    }
    e->v[e->n++] = x;
}

bool filter_keep(const filter_t *f, const char *nm, size_t len) {
    if (!f->hidden && nm[0] == '.') return false;
    if (f->lplen == 0) return true;
    if (len < f->lplen) return false;
    for (size_t i = 0; i < f->lplen; i++) {
        char c = nm[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c + 32);
        if (c != f->lp[i]) return false;
    }
    return true;
}

void list_dir(const char *dir, bool hidden, const char *prefix, ents_t *out, arena_t *ar) {
    filter_t f = {.hidden = hidden, .lplen = strlen(prefix)};
    f.lp = xmalloc(f.lplen + 1);
    ascii_lower(f.lp, prefix);

    int rc = scan_dir(dir, &f, out, ar);
    free(f.lp);
    if (rc != 0 && out->n == 0) bvk_fatal("open %s: %s", dir, strerror(rc));
}

/* ---- parallel stat ---------------------------------------------------- */

typedef struct {
    const char *dir;
    int dfd; /* open directory fd, or -1 -> fall back to full-path stat() */
    ent_t *es;
} stat_ctx_t;

static void stat_one(size_t i, void *p) {
    stat_ctx_t *c = p;
    struct stat st;
    int rc;
    if (c->dfd >= 0) {
        /* relative to the dir fd: no per-entry malloc, no path walk from / */
        rc = fstatat(c->dfd, c->es[i].name, &st, 0); /* 0 = follow symlinks, like stat() */
    } else {
        char *full = path_join(c->dir, c->es[i].name);
        rc = stat(full, &st);
        free(full);
    }
    if (rc == 0) {
        c->es[i].mtime = mtime_sec(&st);
        if (!S_ISDIR(st.st_mode)) c->es[i].size = (int64_t)st.st_size;
    }
}

static void stat_all(const char *dir, ents_t *es) {
    int w = pool_ncpu();
    if (w > 16) w = 16;
    stat_ctx_t c = {dir, open(dir, O_RDONLY | O_DIRECTORY), es->v};
    pool_run(es->n, w, 256, stat_one, &c);
    if (c.dfd >= 0) close(c.dfd);
}

/* ---- sorting: one comparator per mode (qsort has no portable context) -- */

static int by_name(const ent_t *a, const ent_t *b) { return strcmp(a->name, b->name); }

/* ASCII fold table: A-Z -> a-z, every other byte unchanged (unsigned compare,
 * identical ordering to strcmp over ascii_lower()'d copies). */
static unsigned char g_fold[256];
static void fold_init(void) {
    for (int i = 0; i < 256; i++) g_fold[i] = (unsigned char)((i >= 'A' && i <= 'Z') ? i + 32 : i);
}

/* 8 folded bytes starting at s, big-endian, zero padded after the NUL. */
static uint64_t fold_key8(const char *s) {
    uint64_t k = 0;
    int i = 0;
    for (; i < 8 && s[i]; i++) k = (k << 8) | g_fold[(unsigned char)s[i]];
    return i == 8 ? k : k << (8 * (8 - i));
}

static int cmp_az(const void *pa, const void *pb) {
    const ent_t *a = pa, *b = pb;
    if (a->key != b->key) return a->key < b->key ? -1 : 1;
    if (a->key2 != b->key2) return a->key2 < b->key2 ? -1 : 1;
    /* first 16 bytes folded-equal: walk the rest (only names >= 16 bytes get here
     * with a non-trivial tail; shorter equal names are identical when folded). */
    if ((a->key2 & 0xff) != 0) { /* byte 15 present => name is >= 16 long */
        const unsigned char *x = (const unsigned char *)a->name + 16, *y = (const unsigned char *)b->name + 16;
        for (;; x++, y++) {
            unsigned char cx = g_fold[*x], cy = g_fold[*y];
            if (cx != cy) return cx < cy ? -1 : 1;
            if (!cx) break;
        }
    }
    return by_name(a, b);
}
static int cmp_za(const void *pa, const void *pb) { return -cmp_az(pa, pb); }

static inline int cmp_i64(int64_t x, int64_t y) { return x < y ? -1 : x > y; }

static int cmp_new(const void *pa, const void *pb) {
    const ent_t *a = pa, *b = pb;
    int c = -cmp_i64(a->mtime, b->mtime);
    return c ? c : by_name(a, b);
}
static int cmp_old(const void *pa, const void *pb) {
    const ent_t *a = pa, *b = pb;
    int c = cmp_i64(a->mtime, b->mtime);
    return c ? c : by_name(a, b);
}
static int cmp_big(const void *pa, const void *pb) {
    const ent_t *a = pa, *b = pb;
    int c = -cmp_i64(a->size, b->size);
    return c ? c : by_name(a, b);
}
static int cmp_small(const void *pa, const void *pb) {
    const ent_t *a = pa, *b = pb;
    int c = cmp_i64(a->size, b->size);
    return c ? c : by_name(a, b);
}

void sort_ents(const char *dir, const char *mode, ents_t *es, arena_t *ar) {
    int (*cmp)(const void *, const void *) = NULL;

    if (!strcmp(mode, "az") || !strcmp(mode, "za")) {
        (void)ar;
        fold_init();
        for (size_t i = 0; i < es->n; i++) { const char *nm = es->v[i].name; es->v[i].key = fold_key8(nm); es->v[i].key2 = (strlen(nm) > 8) ? fold_key8(nm + 8) : 0; }
        cmp = mode[0] == 'a' ? cmp_az : cmp_za;
    } else if (!strcmp(mode, "new") || !strcmp(mode, "old") || !strcmp(mode, "big") ||
               !strcmp(mode, "small")) {
        stat_all(dir, es);
        cmp = !strcmp(mode, "new") ? cmp_new
              : !strcmp(mode, "old") ? cmp_old
              : !strcmp(mode, "big") ? cmp_big
                                     : cmp_small;
    }
    if (cmp && es->n > 1) qsort(es->v, es->n, sizeof *es->v, cmp);
}
