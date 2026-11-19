#include "bashbasicsbyvk_fr.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

/* ======================================================================== */
/* exclusions                                                               */
/* ======================================================================== */

void ops_mark_excluded(const runopt_t *o, items_t *its) {
    struct { const char *base; dev_t dev; ino_t ino; } ex[64];
    size_t nex = 0;
    for (size_t i = 0; i < o->nexclude && nex < 64; i++) {
        struct stat st;
        if (stat(o->exclude[i], &st) != 0) continue;
        const char *b = strrchr(o->exclude[i], '/');
        ex[nex].base = b ? b + 1 : o->exclude[i];
        ex[nex].dev = st.st_dev;
        ex[nex].ino = st.st_ino;
        nex++;
    }
    for (size_t i = 0; i < its->n; i++) {
        item_t *it = &its->v[i];
        if (o->only && strcmp(it->path, o->only) != 0) { it->excl = 1; continue; }
        if (!nex) continue;
        const char *nm = it->path + it->nameoff;
        for (size_t k = 0; k < nex; k++) {
            if (strcmp(nm, ex[k].base) != 0) continue;
            struct stat st;
            if (lstat(it->path, &st) == 0 && st.st_dev == ex[k].dev && st.st_ino == ex[k].ino) { it->excl = 1; break; }
        }
    }
}

/* ======================================================================== */
/* contents                                                                 */
/* ======================================================================== */

#define SMALL_FILE (8u << 20)

typedef struct {
    uchar *p;
    size_t cap;
} rbuf_t;

typedef struct {
    const runopt_t *o;
    items_t *its;
    int mode;
    size_t *next;
    stats_t st;
    mctx_t **cx;
    rbuf_t rb;
    buf_t A, B;
} worker_t;

static void make_snippet(item_t *it, const uchar *buf, size_t n, size_t off) {
    size_t a = off, b = off;
    while (a > 0 && buf[a - 1] != '\n') a--;
    while (b < n && buf[b] != '\n') b++;
    uint32_t line = 1;
    const uchar *q = buf, *e = buf + a;
    while (q < e) {
        const uchar *nl = memchr(q, '\n', (size_t)(e - q));
        if (!nl) break;
        line++;
        q = nl + 1;
    }
    it->line = line;
    size_t s0 = a, s1 = b;
    if (off > a + 40) s0 = off - 40;
    if (s1 > off + 120) s1 = off + 120;
    while (s0 < s1 && (buf[s0] & 0xC0) == 0x80) s0++;
    while (s1 > s0 && s1 < n && (buf[s1] & 0xC0) == 0x80) s1--;
    char *t = fr_xmalloc(s1 - s0 + 1);
    size_t w = 0;
    for (size_t i = s0; i < s1; i++) {
        uchar c = buf[i];
        if (c == '\r') continue;
        t[w++] = (c < 0x20 || c == 0x7f) ? ' ' : (char)c;
    }
    t[w] = 0;
    free(it->snippet);
    it->snippet = t;
}

static int write_all(int fd, const uchar *d, size_t n) {
    while (n) {
        ssize_t w = write(fd, d, n);
        if (w < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        d += w;
        n -= (size_t)w;
    }
    return 0;
}

static int write_in_place(const char *path, const uchar *d, size_t n) {
    int fd = open(path, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) return -1;
    int r = write_all(fd, d, n);
    int e = errno;
    if (close(fd) != 0 && r == 0) { r = -1; e = errno; }
    errno = e;
    return r;
}

/* temp file next to the original + rename: the file is never seen half written */
static int write_file_atomic(const char *path, const struct stat *st, const uchar *d, size_t n) {
    if (st->st_nlink > 1) return write_in_place(path, d, n);   /* keep hard links together */
    size_t pl = strlen(path);
    char *tmp = fr_xmalloc(pl + 24);
    const char *slash = strrchr(path, '/');
    size_t dl = slash ? (size_t)(slash - path) + 1 : 0;
    memcpy(tmp, path, dl);
    memcpy(tmp + dl, ".bvkfr.XXXXXX", 14);
    int fd = mkstemp(tmp);
    if (fd < 0) {
        int e = errno;
        free(tmp);
        if (e == EACCES || e == EROFS || e == EPERM) return write_in_place(path, d, n);
        errno = e;
        return -1;
    }
    int rc = write_all(fd, d, n);
    int e = errno;
    if (rc == 0) {
        if (fchmod(fd, st->st_mode & 07777) != 0) { /* best effort */ }
        if (fchown(fd, st->st_uid, st->st_gid) != 0) { /* best effort */ }
    }
    if (close(fd) != 0 && rc == 0) { rc = -1; e = errno; }
    if (rc == 0 && rename(tmp, path) != 0) { rc = -1; e = errno; }
    if (rc != 0) unlink(tmp);
    free(tmp);
    errno = e;
    return rc;
}

static const uchar *load_file(int fd, size_t size, rbuf_t *rb, void **map, size_t *maplen) {
    *map = NULL;
    if (size == 0) return rb->p ? rb->p : (const uchar *)"";
    if (size > SMALL_FILE) {
        void *m = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
        if (m != MAP_FAILED) {
            *map = m;
            *maplen = size;
            return m;
        }
    }
    if (rb->cap < size + 1) {
        rb->cap = size + 1 + size / 4;
        rb->p = fr_xrealloc(rb->p, rb->cap);
    }
    size_t got = 0;
    while (got < size) {
        ssize_t r = read(fd, rb->p + got, size - got);
        if (r < 0) {
            if (errno == EINTR) continue;
            return NULL;
        }
        if (r == 0) break;
        got += (size_t)r;
    }
    *maplen = got;
    return rb->p;
}

static void process_file(worker_t *w, item_t *it) {
    const runopt_t *o = w->o;
    int fd = open(it->path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        it->cstate = CS_ERROR;
        it->cerr = errno;
        w->st.content_errors++;
        return;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        close(fd);
        return;
    }
    it->size = (uint64_t)st.st_size;
    if (o->maxsize && (uint64_t)st.st_size > o->maxsize) {
        close(fd);
        it->cstate = CS_LARGE;
        w->st.skipped_large++;
        return;
    }
    void *map = NULL;
    size_t n = (size_t)st.st_size;
    const uchar *data = load_file(fd, n, &w->rb, &map, &n);
    close(fd);
    if (!data) {
        it->cstate = CS_ERROR;
        it->cerr = EIO;
        w->st.content_errors++;
        return;
    }
    w->st.files_scanned++;
    if (!o->binary && n && memchr(data, 0, n < 8000 ? n : 8000)) {
        it->cstate = CS_BINARY;
        w->st.skipped_binary++;
        goto out;
    }
    {
        const uchar *cur = data;
        size_t curn = n;
        bool changed = false, snip = false;
        uint64_t total = 0;
        buf_t *outb = &w->A;
        bool build = (w->mode == M_APPLY) || o->nrules > 1;
        for (size_t r = 0; r < o->nrules; r++) {
            size_t first;
            size_t cnt;
            if (build) {
                outb = (cur == w->A.p) ? &w->B : &w->A;
                outb->n = 0;
                cnt = matcher_replace(o->rules[r], w->cx[r], cur, curn, outb, &first);
            } else {
                cnt = matcher_replace(o->rules[r], w->cx[r], cur, curn, NULL, &first);
            }
            if (w->cx[r] && mctx_error(w->cx[r])) {
                it->cstate = CS_ERROR;
                it->cerr = FR_E_REGEX;
                w->st.content_errors++;
                goto out;
            }
            if (!cnt) continue;
            w->st.rule_occ[r] += cnt;
            w->st.rule_files[r]++;
            total += cnt;
            if (!snip && o->want_snippet) {
                make_snippet(it, cur, curn, first);
                snip = true;
            }
            if (build) {
                cur = outb->p;
                curn = outb->n;
                changed = true;
            }
        }
        if (!total) goto out;
        it->occ = total;
        it->cstate = CS_MATCH;
        w->st.files_matched++;
        w->st.occ_total += total;
        if (w->mode == M_APPLY && changed && !(curn == n && memcmp(cur, data, n) == 0)) {
            if (write_file_atomic(it->path, &st, cur, curn) == 0) {
                it->cstate = CS_DONE;
                w->st.files_changed++;
            } else {
                it->cstate = CS_ERROR;
                it->cerr = errno;
                w->st.content_errors++;
            }
        } else if (w->mode == M_APPLY) {
            it->cstate = CS_DONE;   /* matched, replacement identical to the match: nothing to write */
        }
    }
out:
    if (map) munmap(map, n);
}

static void *worker_main(void *arg) {
    worker_t *w = arg;
    items_t *its = w->its;
    const size_t CH = 8;
    for (;;) {
        size_t i0 = __atomic_fetch_add(w->next, CH, __ATOMIC_RELAXED);
        if (i0 >= its->n) break;
        size_t i1 = i0 + CH < its->n ? i0 + CH : its->n;
        for (size_t i = i0; i < i1; i++) {
            item_t *it = &its->v[i];
            if (it->typ != IT_FILE || it->excl) continue;
            process_file(w, it);
        }
    }
    return NULL;
}

#define MAX_THREADS 64

/* the matcher recurses: give each worker a big (lazily committed) stack, smaller ones when that is refused */
static int spawn(pthread_t *t, worker_t *w) {
    static const size_t sizes[] = {256u << 20, 64u << 20, 16u << 20, 2u << 20};
    int rc = -1;
    for (size_t k = 0; k < sizeof sizes / sizeof *sizes; k++) {
        pthread_attr_t at;
        pthread_attr_init(&at);
        pthread_attr_setstacksize(&at, sizes[k]);
        rc = pthread_create(t, &at, worker_main, w);
        pthread_attr_destroy(&at);
        if (rc == 0) break;
    }
    return rc;
}

static int auto_threads(size_t nfiles) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1) n = 1;
    long t = n * 2;
    if (t > 16) t = 16;
    if ((size_t)t > nfiles / 8 + 1) t = (long)(nfiles / 8 + 1);
    return (int)t;
}

void ops_contents(const runopt_t *o, items_t *its, int mode, stats_t *st) {
    size_t nfiles = 0;
    for (size_t i = 0; i < its->n; i++) if (its->v[i].typ == IT_FILE) nfiles++;
    int nt = o->threads > 0 ? o->threads : auto_threads(nfiles);
    if (nt < 1) nt = 1;
    if (nt > MAX_THREADS) nt = MAX_THREADS;
    worker_t *ws = calloc((size_t)nt, sizeof *ws);
    pthread_t *th = calloc((size_t)nt, sizeof *th);
    if (!ws || !th) fr_fatal("out of memory");
    size_t next = 0;
    for (int t = 0; t < nt; t++) {
        worker_t *w = &ws[t];
        w->o = o;
        w->its = its;
        w->mode = mode;
        w->next = &next;
        w->st.rule_occ = calloc(o->nrules, sizeof(uint64_t));
        w->st.rule_files = calloc(o->nrules, sizeof(uint64_t));
        w->cx = calloc(o->nrules, sizeof *w->cx);
        for (size_t r = 0; r < o->nrules; r++) w->cx[r] = mctx_new(o->rules[r]);
    }
    bool started[MAX_THREADS] = {false};
    for (int t = 0; t < nt; t++) {
        if (spawn(&th[t], &ws[t]) == 0) started[t] = true;
        else if (t == 0) { worker_main(&ws[0]); break; }   /* could not start a thread at all: work here */
        else break;
    }
    for (int t = 0; t < nt; t++) if (started[t]) pthread_join(th[t], NULL);
    for (int t = 0; t < nt; t++) {
        worker_t *w = &ws[t];
        st->files_scanned += w->st.files_scanned;
        st->files_matched += w->st.files_matched;
        st->files_changed += w->st.files_changed;
        st->skipped_binary += w->st.skipped_binary;
        st->skipped_large += w->st.skipped_large;
        st->content_errors += w->st.content_errors;
        st->occ_total += w->st.occ_total;
        for (size_t r = 0; r < o->nrules; r++) {
            st->rule_occ[r] += w->st.rule_occ[r];
            st->rule_files[r] += w->st.rule_files[r];
            mctx_free(w->cx[r]);
        }
        free(w->st.rule_occ);
        free(w->st.rule_files);
        free(w->cx);
        free(w->rb.p);
        buf_free(&w->A);
        buf_free(&w->B);
    }
    free(ws);
    free(th);
}

/* ======================================================================== */
/* names                                                                    */
/* ======================================================================== */

static const items_t *g_its;

static int cmp_parent_new(const void *a, const void *b) {
    const item_t *x = &g_its->v[*(const uint32_t *)a], *y = &g_its->v[*(const uint32_t *)b];
    if (x->parent != y->parent) return x->parent < y->parent ? -1 : 1;
    int c = strcmp(x->newname, y->newname);
    if (c) return c;
    uint32_t i = *(const uint32_t *)a, j = *(const uint32_t *)b;
    return i < j ? -1 : i > j ? 1 : 0;
}

static int cmp_parent_old(const void *a, const void *b) {
    const item_t *x = &g_its->v[*(const uint32_t *)a], *y = &g_its->v[*(const uint32_t *)b];
    if (x->parent != y->parent) return x->parent < y->parent ? -1 : 1;
    return strcmp(x->path + x->nameoff, y->path + y->nameoff);
}

/* index (into cand[]) of a candidate whose current name is `name` inside directory `parent`, or -1 */
static long find_cand(const items_t *its, const uint32_t *cand, size_t nc, uint32_t parent, const char *name) {
    size_t lo = 0, hi = nc;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        const item_t *x = &its->v[cand[mid]];
        int c;
        if (x->parent != parent) c = x->parent < parent ? -1 : 1;
        else c = strcmp(x->path + x->nameoff, name);
        if (c < 0) lo = mid + 1;
        else if (c > 0) hi = mid;
        else return (long)mid;
    }
    return -1;
}

static char *dest_path(const item_t *it, const char *newname) {
    size_t dl = it->nameoff, nl = strlen(newname);
    char *d = fr_xmalloc(dl + nl + 1);
    memcpy(d, it->path, dl);
    memcpy(d + dl, newname, nl + 1);
    return d;
}

static bool ascii_ieq(const char *a, const char *b) {
    for (;; a++, b++) {
        unsigned char x = (unsigned char)*a, y = (unsigned char)*b;
        if (x >= 'A' && x <= 'Z') x += 32;
        if (y >= 'A' && y <= 'Z') y += 32;
        if (x != y) return false;
        if (!x) return true;
    }
}

static bool same_file_case_only(const char *old, const char *nw, const char *oldname, const char *newname) {
    if (!ascii_ieq(oldname, newname)) return false;
    struct stat a, b;
    if (lstat(old, &a) != 0 || lstat(nw, &b) != 0) return false;
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_nlink == 1;
}

static bool valid_newname(const uchar *s, size_t n) {
    if (n == 0 || n > 255) return false;
    if ((n == 1 && s[0] == '.') || (n == 2 && s[0] == '.' && s[1] == '.')) return false;
    for (size_t i = 0; i < n; i++) if (s[i] == '/' || s[i] == 0) return false;
    return true;
}

void ops_names_plan(const runopt_t *o, items_t *its, int mode, stats_t *st) {
    mctx_t **cx = calloc(o->nrules, sizeof *cx);
    for (size_t r = 0; r < o->nrules; r++) cx[r] = mctx_new(o->rules[r]);
    buf_t A = {0}, B = {0};
    uint32_t *rl = fr_xmalloc((o->nrules ? o->nrules : 1) * sizeof *rl);
    for (size_t i = 0; i < its->n; i++) {
        item_t *it = &its->v[i];
        if (it->excl) continue;
        bool isdir = it->typ == IT_DIR;
        if (isdir ? !o->target_dirs : !o->target_files) continue;
        const uchar *name = (const uchar *)it->path + it->nameoff;
        size_t n = strlen((const char *)name);
        if (mode == M_FIND) {
            bool hit = false;
            for (size_t r = 0; r < o->nrules; r++) {
                if (matcher_test(o->rules[r], cx[r], name, n)) {
                    hit = true;
                    st->rule_names[r]++;
                }
            }
            if (hit) {
                it->nstate = NS_PLAN;
                st->names_matched++;
            }
            continue;
        }
        const uchar *cur = name;
        size_t curn = n;
        size_t nr = 0;
        bool failed = false;
        for (size_t r = 0; r < o->nrules; r++) {
            buf_t *outb = (cur == A.p) ? &B : &A;
            outb->n = 0;
            size_t cnt = matcher_replace(o->rules[r], cx[r], cur, curn, outb, NULL);
            if (mctx_error(cx[r])) { failed = true; break; }
            if (!cnt) continue;
            rl[nr++] = (uint32_t)r;
            cur = outb->p;
            curn = outb->n;
        }
        if (failed) {
            it->nstate = NS_ERROR;
            it->nerr = FR_E_REGEX;
            st->names_error++;
            continue;
        }
        if (!nr || (curn == n && memcmp(cur, name, n) == 0)) continue;
        st->names_matched++;
        it->rules = fr_xmalloc(nr * sizeof *rl);
        memcpy(it->rules, rl, nr * sizeof *rl);
        it->nrules = (uint32_t)nr;
        it->newname = fr_xmalloc(curn + 1);
        memcpy(it->newname, cur, curn);
        it->newname[curn] = 0;
        if (!valid_newname(cur, curn)) {
            it->nstate = NS_INVALID;
            st->names_invalid++;
            continue;
        }
        it->nstate = NS_PLAN;
    }
    for (size_t r = 0; r < o->nrules; r++) mctx_free(cx[r]);
    free(cx);
    free(rl);
    buf_free(&A);
    buf_free(&B);
    if (mode == M_FIND) return;

    /* ---- conflicts ---- */
    g_its = its;
    size_t nc = 0;
    uint32_t *cand = fr_xmalloc((its->n + 1) * sizeof *cand);
    for (size_t i = 0; i < its->n; i++) if (its->v[i].nstate == NS_PLAN) cand[nc++] = (uint32_t)i;
    qsort(cand, nc, sizeof *cand, cmp_parent_new);
    for (size_t k = 1; k < nc; k++) {
        /* several items would get the same new name in one folder: the first (sorted order) keeps it */
        item_t *a = &its->v[cand[k - 1]], *b = &its->v[cand[k]];
        if (a->parent == b->parent && !strcmp(a->newname, b->newname)) {
            b->nstate = NS_CONFLICT;
            b->nerr = EEXIST;
            st->names_conflict++;
        }
    }
    size_t w = 0;
    for (size_t k = 0; k < nc; k++) if (its->v[cand[k]].nstate == NS_PLAN) cand[w++] = cand[k];
    nc = w;
    qsort(cand, nc, sizeof *cand, cmp_parent_old);
    for (size_t k = 0; k < nc; k++) {
        item_t *it = &its->v[cand[k]];
        char *dest = dest_path(it, it->newname);
        struct stat sb;
        if (lstat(dest, &sb) == 0) {
            long s = find_cand(its, cand, nc, it->parent, it->newname);
            bool vacates = s >= 0 && cand[s] != cand[k] && its->v[cand[s]].nstate == NS_PLAN;
            if (!vacates && !same_file_case_only(it->path, dest, it->path + it->nameoff, it->newname)) {
                it->nstate = NS_CONFLICT;
                it->nerr = EEXIST;
                st->names_conflict++;
            }
        }
        free(dest);
    }
    free(cand);
    for (size_t i = 0; i < its->n; i++) {
        item_t *it = &its->v[i];
        if (it->nstate != NS_PLAN) continue;
        st->names_planned++;
        for (uint32_t k = 0; k < it->nrules; k++) st->rule_names[it->rules[k]]++;
    }
}

static int rename_noreplace(const char *a, const char *b) {
#if defined(__linux__) && !defined(__ANDROID__) && defined(SYS_renameat2)
    /* Android's seccomp filter may kill the process on a syscall it does not know: the portable path is used there */
    long r = syscall(SYS_renameat2, AT_FDCWD, a, AT_FDCWD, b, 1 /* RENAME_NOREPLACE */);
    if (r == 0) return 0;
    if (errno != ENOSYS && errno != EINVAL && errno != ENOTSUP) return -1;
#endif
    struct stat st;
    if (lstat(b, &st) == 0) {
        errno = EEXIST;
        return -1;
    }
    if (errno != ENOENT) return -1;
    return rename(a, b);
}

static bool log_ok(const char *s) { return !strpbrk(s, "\t\n"); }

void ops_names_apply(const runopt_t *o, items_t *its, stats_t *st) {
    size_t nc = 0;
    uint32_t *cand = fr_xmalloc((its->n + 1) * sizeof *cand);
    for (size_t i = 0; i < its->n; i++) if (its->v[i].nstate == NS_PLAN) cand[nc++] = (uint32_t)i;
    g_its = its;
    /* lookup table of current names (sorted) to know whether a destination is about to be vacated */
    uint32_t *byold = fr_xmalloc((nc + 1) * sizeof *byold);
    memcpy(byold, cand, nc * sizeof *cand);
    qsort(byold, nc, sizeof *byold, cmp_parent_old);
    FILE *lf = o->logfile ? fopen(o->logfile, "a") : NULL;
    bool deferred_any = false, progress;
    do {
        progress = false;
        bool deferred = false;
        for (size_t k = nc; k-- > 0;) {                     /* children before their folder */
            item_t *it = &its->v[cand[k]];
            if (it->nstate != NS_PLAN) continue;
            if (it->typ == IT_DIR && (deferred || deferred_any)) {         /* keep paths below valid: wait for pending children */
                bool wait = false;
                for (uint32_t j = cand[k] + 1; j < it->subend && j < its->n; j++)
                    if (its->v[j].nstate == NS_PLAN) { wait = true; break; }
                if (wait) { deferred = true; continue; }
            }
            char *dest = dest_path(it, it->newname);
            const char *oldname = it->path + it->nameoff;
            int rc = rename_noreplace(it->path, dest);
            int e = errno;
            if (rc != 0 && (e == EEXIST || e == ENOTEMPTY)) {
                if (same_file_case_only(it->path, dest, oldname, it->newname)) {
                    rc = rename(it->path, dest);
                    e = errno;
                } else {
                    long s = find_cand(its, byold, nc, it->parent, it->newname);
                    if (s >= 0 && byold[s] != cand[k] && its->v[byold[s]].nstate == NS_PLAN) {
                        deferred = true;                     /* its owner moves away first */
                        free(dest);
                        continue;
                    }
                }
            }
            if (rc == 0) {
                it->nstate = NS_DONE;
                st->names_renamed++;
                for (uint32_t q = 0; q < it->nrules; q++) st->rule_names[it->rules[q]]++;
                if (lf && log_ok(it->path) && log_ok(dest)) fprintf(lf, "%s\t%s\n", it->path, dest);
                progress = true;
            } else if (e == EEXIST || e == ENOTEMPTY) {
                it->nstate = NS_CONFLICT;
                it->nerr = EEXIST;
                st->names_conflict++;
            } else {
                it->nstate = NS_ERROR;
                it->nerr = e;
                st->names_error++;
            }
            free(dest);
        }
        deferred_any = deferred;
        if (!deferred) break;
    } while (progress);
    for (size_t k = 0; k < nc; k++) {                       /* still waiting = a cycle: left alone */
        item_t *it = &its->v[cand[k]];
        if (it->nstate == NS_PLAN) {
            it->nstate = NS_CONFLICT;
            it->nerr = EEXIST;
            st->names_conflict++;
        }
    }
    if (lf) fclose(lf);
    free(byold);
    free(cand);
}
