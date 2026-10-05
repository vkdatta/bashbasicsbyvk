/* bvk-ls: fast directory lister for bashbasicsbyvk. Drop-in replacement for
 * the Python scan / meta / recursive-size helpers, plus a one-shot "window"
 * call so the shell never has to hold a 500k-element array.
 *
 *   bvk-ls scan   DIR MODE HIDDEN [PREFIX]        sorted full paths
 *   bvk-ls meta   PATHS_FILE                      path|size|mtime|children|icon
 *   bvk-ls dsize  PATHS_FILE                      path|recursive_size
 *   bvk-ls count  DIR HIDDEN                      number of entries
 *   bvk-ls window DIR MODE HIDDEN PREFIX START N  "#total" then meta rows for [START, START+N)
 *
 * MODE: az za new old big small   HIDDEN: 1|0   START is 1-based.
 */
#include "bvk.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *g_argv0cmd;
static char **g_a;
static int g_na;

static const char *arg(int i) { return i < g_na ? g_a[i] : ""; }

/* Go strconv.Atoi semantics as used here: garbage -> 0. */
static long to_int(const char *s) {
    char *end;
    errno = 0;
    long v = strtol(s, &end, 10);
    return (*s == 0 || *end != 0 || errno) ? 0 : v;
}

static void emit_path(FILE *out, const char *dir, const char *name) {
    size_t dl = strlen(dir);
    fputs(dir, out);
    if (!(dl > 0 && dir[dl - 1] == '/')) fputc('/', out);
    fputs(name, out);
    fputc('\n', out);
}

static void cmd_scan(FILE *out) {
    const char *dir = arg(0);
    arena_t ar = {0};
    ents_t es = {0};
    list_dir(dir, !strcmp(arg(2), "1"), arg(3), &es, &ar);
    sort_ents(dir, arg(1), &es, &ar);
    for (size_t i = 0; i < es.n; i++) emit_path(out, dir, es.v[i].name);
}

static void cmd_count(FILE *out) {
    arena_t ar = {0};
    ents_t es = {0};
    list_dir(arg(0), !strcmp(arg(1), "1"), "", &es, &ar);
    fprintf(out, "%zu\n", es.n);
}

static void print_rows(FILE *out, char **rows, size_t n) {
    for (size_t i = 0; i < n; i++) {
        fputs(rows[i], out);
        fputc('\n', out);
    }
}

static void cmd_meta(FILE *out) {
    size_t n;
    char *buf;
    char **paths = read_lines(arg(0), &n, &buf);
    char **rows = meta_many(paths, n);
    print_rows(out, rows, n);
}

typedef struct {
    char **paths;
    int64_t *res;
} dsize_ctx_t;

static void dsize_one(size_t i, void *p) {
    dsize_ctx_t *c = p;
    c->res[i] = dir_size(c->paths[i]);
}

static void cmd_dsize(FILE *out) {
    size_t n;
    char *buf;
    char **paths = read_lines(arg(0), &n, &buf);
    int64_t *res = xmalloc((n ? n : 1) * sizeof *res);
    dsize_ctx_t c = {paths, res};
    pool_run(n, pool_ncpu() * 2, 1, dsize_one, &c);
    for (size_t i = 0; i < n; i++) fprintf(out, "%s|%lld\n", paths[i], (long long)res[i]);
}

static void cmd_window(FILE *out) {
    const char *dir = arg(0);
    long start = to_int(arg(4));
    long n = to_int(arg(5));
    if (start < 1) start = 1;

    arena_t ar = {0};
    ents_t es = {0};
    list_dir(dir, !strcmp(arg(2), "1"), arg(3), &es, &ar);
    sort_ents(dir, arg(1), &es, &ar);
    fprintf(out, "#%zu\n", es.n);

    long lo = start - 1, hi = start - 1 + n;
    if (hi > (long)es.n) hi = (long)es.n;
    if (lo < hi) {
        size_t cnt = (size_t)(hi - lo);
        char **ps = xmalloc(cnt * sizeof *ps);
        for (size_t i = 0; i < cnt; i++) ps[i] = path_join(dir, es.v[lo + (long)i].name);
        char **rows = meta_many(ps, cnt);
        print_rows(out, rows, cnt);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) bvk_fatal("usage: bvk-ls scan|meta|dsize|count|window ...");
    g_argv0cmd = argv[1];
    g_a = argv + 2;
    g_na = argc - 2;

    FILE *out = stdout;
    static char obuf[1 << 20];
    setvbuf(out, obuf, _IOFBF, sizeof obuf);

    if (!strcmp(g_argv0cmd, "scan")) cmd_scan(out);
    else if (!strcmp(g_argv0cmd, "count")) cmd_count(out);
    else if (!strcmp(g_argv0cmd, "meta")) cmd_meta(out);
    else if (!strcmp(g_argv0cmd, "dsize")) cmd_dsize(out);
    else if (!strcmp(g_argv0cmd, "window")) cmd_window(out);
    else bvk_fatal("unknown command \"%s\"", g_argv0cmd);

    if (fflush(out) != 0 || ferror(out)) return 1;
    return 0; /* process exit reclaims all memory */
}
