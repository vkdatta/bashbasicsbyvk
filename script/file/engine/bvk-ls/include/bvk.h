/* bvk-ls: shared types and module interfaces.
 *
 * Module map (src/):
 *   util.c   fatal(), path helpers, arena allocator, line reader
 *   pool.c   tiny pthread worker pool (dynamic chunk scheduling)
 *   scan_linux.c / scan_posix.c   directory listing backends (one is built)
 *   list.c   filtered listing + parallel stat + sorting
 *   icon.c   file-kind label (archive/image/plugin/exec/...)
 *   meta.c   "path|size|mtime|children|icon" rows
 *   dsize.c  recursive directory size
 *   main.c   command dispatch (scan/meta/dsize/count/window)
 */
#ifndef BVK_H
#define BVK_H

#ifndef _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS 64
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>

/* ---- util.c ---------------------------------------------------------- */

void bvk_fatal(const char *fmt, ...) __attribute__((noreturn, format(printf, 1, 2)));
void *xmalloc(size_t n);
void *xrealloc(void *p, size_t n);

/* "dir" + "/" + "name", no doubled slash. Caller frees. */
char *path_join(const char *dir, const char *name);
/* Go filepath.Base semantics (trailing slashes stripped, "" -> "."). */
const char *path_base(const char *p, size_t *len);
/* ASCII lowercase copy into dst (dst must hold strlen(s)+1). */
void ascii_lower(char *dst, const char *s);

/* Bump allocator for names: a few big blocks instead of one malloc each. */
typedef struct arena_block arena_block_t;
typedef struct {
    arena_block_t *head;
} arena_t;

char *arena_strndup(arena_t *a, const char *s, size_t n);
void arena_free(arena_t *a);

/* Reads FILE, splits on '\n', drops blank lines. Lines point into *buf_out
 * (caller frees it and the returned array). */
char **read_lines(const char *file, size_t *n_out, char **buf_out);

/* ---- pool.c ---------------------------------------------------------- */

typedef void (*pool_fn)(size_t index, void *ctx);

int pool_ncpu(void);
/* Runs fn(0..n-1) on up to `workers` threads (caller counts as one). */
void pool_run(size_t n, int workers, size_t chunk, pool_fn fn, void *ctx);

/* ---- list.c / scan_*.c ----------------------------------------------- */

typedef struct {
    const char *name;
    const char *low; /* lowercase name, set only for az/za sorts */
    unsigned char typ;
    int64_t size;
    int64_t mtime;
} ent_t;

typedef struct {
    ent_t *v;
    size_t n, cap;
} ents_t;

typedef struct {
    bool hidden;
    char *lp; /* lowercase prefix, "" = none */
    size_t lplen;
} filter_t;

void ents_push(ents_t *e, ent_t x);

/* Backend: lists dir, applying filter and storing names in arena.
 * Returns 0 or an errno value; entries read before an error are kept. */
int scan_dir(const char *dir, const filter_t *f, ents_t *out, arena_t *ar);

bool filter_keep(const filter_t *f, const char *nm, size_t len);

/* Filtered listing; dies if the directory cannot be read at all. */
void list_dir(const char *dir, bool hidden, const char *prefix, ents_t *out, arena_t *ar);
void sort_ents(const char *dir, const char *mode, ents_t *es, arena_t *ar);

/* ---- icon.c / meta.c / dsize.c --------------------------------------- */

const char *icon_for(const char *name, size_t len, bool is_dir, uint32_t mode);
char *meta_line(const char *path); /* malloc'd */
char **meta_many(char *const *paths, size_t n);
int64_t dir_size(const char *root);
int count_children(const char *path); /* -1 on error */

static inline int64_t mtime_sec(const struct stat *st) {
#if defined(__APPLE__)
    return (int64_t)st->st_mtimespec.tv_sec;
#else
    return (int64_t)st->st_mtim.tv_sec;
#endif
}

#endif
