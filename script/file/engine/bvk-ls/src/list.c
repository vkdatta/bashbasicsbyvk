#include "bvk.h"

#include <errno.h>
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
    ent_t *es;
} stat_ctx_t;

static void stat_one(size_t i, void *p) {
    stat_ctx_t *c = p;
    char *full = path_join(c->dir, c->es[i].name);
    struct stat st;
    if (stat(full, &st) == 0) {
        c->es[i].mtime = mtime_sec(&st);
        if (!S_ISDIR(st.st_mode)) c->es[i].size = (int64_t)st.st_size;
    }
    free(full);
}

static void stat_all(const char *dir, ents_t *es) {
    int w = pool_ncpu();
    if (w > 16) w = 16;
    stat_ctx_t c = {dir, es->v};
    pool_run(es->n, w, 64, stat_one, &c);
}

/* ---- sorting: one comparator per mode (qsort has no portable context) -- */

static int by_name(const ent_t *a, const ent_t *b) { return strcmp(a->name, b->name); }

static int cmp_az(const void *pa, const void *pb) {
    const ent_t *a = pa, *b = pb;
    int c = strcmp(a->low, b->low);
    return c ? c : by_name(a, b);
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
        for (size_t i = 0; i < es->n; i++) {
            size_t len = strlen(es->v[i].name);
            char *low = arena_strndup(ar, es->v[i].name, len);
            ascii_lower(low, es->v[i].name);
            es->v[i].low = low;
        }
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
