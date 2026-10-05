#include "bvk.h"

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void bvk_fatal(const char *fmt, ...) {
    va_list ap;
    fflush(stdout);
    fputs("bvk-ls: ", stderr);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void *xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) bvk_fatal("out of memory");
    return p;
}

void *xrealloc(void *p, size_t n) {
    p = realloc(p, n ? n : 1);
    if (!p) bvk_fatal("out of memory");
    return p;
}

char *path_join(const char *dir, const char *name) {
    size_t dl = strlen(dir), nl = strlen(name);
    int slash = !(dl > 0 && dir[dl - 1] == '/');
    char *r = xmalloc(dl + slash + nl + 1);
    memcpy(r, dir, dl);
    if (slash) r[dl] = '/';
    memcpy(r + dl + slash, name, nl + 1);
    return r;
}

const char *path_base(const char *p, size_t *len) {
    size_t n = strlen(p);
    if (n == 0) {
        *len = 1;
        return ".";
    }
    while (n > 1 && p[n - 1] == '/') n--;
    if (n == 1 && p[0] == '/') {
        *len = 1;
        return p;
    }
    size_t i = n;
    while (i > 0 && p[i - 1] != '/') i--;
    *len = n - i;
    return p + i;
}

void ascii_lower(char *dst, const char *s) {
    for (; *s; s++) *dst++ = (char)tolower((unsigned char)*s);
    *dst = 0;
}

/* ---- arena ------------------------------------------------------------ */

#define ARENA_BLOCK (1u << 20)

struct arena_block {
    arena_block_t *next;
    size_t used, cap;
    char data[];
};

char *arena_strndup(arena_t *a, const char *s, size_t n) {
    size_t need = n + 1;
    if (!a->head || a->head->cap - a->head->used < need) {
        size_t cap = need > ARENA_BLOCK ? need : ARENA_BLOCK;
        arena_block_t *b = xmalloc(sizeof *b + cap);
        b->next = a->head;
        b->used = 0;
        b->cap = cap;
        a->head = b;
    }
    char *d = a->head->data + a->head->used;
    memcpy(d, s, n);
    d[n] = 0;
    a->head->used += need;
    return d;
}

void arena_free(arena_t *a) {
    while (a->head) {
        arena_block_t *n = a->head->next;
        free(a->head);
        a->head = n;
    }
}

/* ---- line reader ------------------------------------------------------ */

char **read_lines(const char *file, size_t *n_out, char **buf_out) {
    FILE *f = fopen(file, "rb");
    if (!f) bvk_fatal("open %s: %s", file, strerror(errno));
    size_t cap = 1 << 16, len = 0;
    char *buf = xmalloc(cap + 1);
    for (;;) {
        size_t r = fread(buf + len, 1, cap - len, f);
        len += r;
        if (len < cap) break;
        cap *= 2;
        buf = xrealloc(buf, cap + 1);
    }
    if (ferror(f)) bvk_fatal("read %s: %s", file, strerror(errno));
    fclose(f);
    buf[len] = 0;

    size_t lcap = 1024, n = 0;
    char **lines = xmalloc(lcap * sizeof *lines);
    for (char *p = buf; p < buf + len;) {
        char *nl = memchr(p, '\n', (size_t)(buf + len - p));
        char *end = nl ? nl : buf + len;
        char *q = p;
        while (q < end && isspace((unsigned char)*q)) q++;
        if (q < end) { /* not blank: keep the line verbatim */
            if (n == lcap) {
                lcap *= 2;
                lines = xrealloc(lines, lcap * sizeof *lines);
            }
            *end = 0;
            lines[n++] = p;
        }
        p = end + 1;
    }
    *n_out = n;
    *buf_out = buf;
    return lines;
}
