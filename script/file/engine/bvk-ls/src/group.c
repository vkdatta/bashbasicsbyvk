/* group.c — "Group by" view (Settings → Display → Group by), done natively.
 *
 *   bvk-ls group PATHS_FILE LEVELS HL OUT_PREFIX
 *
 *   PATHS_FILE  one full path per line, in the CURRENT display order
 *   LEVELS      comma list, outermost first, from: ext year month date
 *   HL          1-based index of the highlighted item (0 = none)
 *   OUT_PREFIX  writes   OUT_PREFIX.items   the paths, re-ordered so every group is contiguous
 *                        OUT_PREFIX.rows    one line per screen row:
 *                                             "H<text>"  a group header row
 *                                             "<N>"      item number N (1-based, in .items order)
 *                        OUT_PREFIX.irow    one line per item: the screen row it sits on
 *   stdout      "<items> <rows> <new HL> <depth>"
 *
 * Ordering rules (hierarchical, so a year header appears ONCE with its months
 * under it, instead of being repeated for every month):
 *   - groups of the first level keep the order in which they first appear in
 *     the input; inside one group the sub-groups do the same, and so on;
 *   - inside the innermost group the items keep their input order (so the
 *     Settings → Sort order still decides the order of the files themselves).
 * Keys:  year  2025          month  2025-Mar        date  2025-Mar-14
 *        ext   .pdf (ASCII case folded)  [dir]  [shortcut]  (no ext)
 * Times are local time (honours TZ, like the shell's printf %(…)T).
 *
 * Any failure returns non-zero and the shell falls back to the Python twin
 * (_py_group_python in bashbasicsbyvk_displayer.sh), which has the same output.
 */
#include "bvk.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { L_EXT = 0, L_YEAR, L_MONTH, L_DATE };
static const char *const LNAME[] = {"EXT", "YEAR", "MONTH", "DATE"};
static const char *const MON[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};

typedef struct {
    const char *path;
    const char *base;
    int64_t mtime;
    int ok;         /* stat succeeded */
    int isdir;
    int year, mon, day; /* local time, mon 0-11 */
} gi_t;

typedef struct {
    gi_t *g;
} gctx_t;

static void stat_one(size_t i, void *p) {
    gi_t *x = &((gctx_t *)p)->g[i];
    struct stat st;
    x->mtime = 0;
    x->ok = 0;
    x->isdir = 0;
    if (stat(x->path, &st) == 0) {
        x->ok = 1;
        x->isdir = S_ISDIR(st.st_mode);
        x->mtime = mtime_sec(&st);
    }
    time_t t = (time_t)x->mtime;
    struct tm tmv;
    if (localtime_r(&t, &tmv)) {
        x->year = tmv.tm_year + 1900;
        x->mon = tmv.tm_mon;
        x->day = tmv.tm_mday;
    } else {
        x->year = 1970; x->mon = 0; x->day = 1;
    }
}

/* ext label of one item into buf (ASCII-lowercased) */
static void ext_label(const gi_t *x, char *buf, size_t cap) {
    const char *bn = x->base;
    size_t bl = strlen(bn);
    if (bl >= 9 && !strcmp(bn + bl - 9, ".shortcut")) { snprintf(buf, cap, "[shortcut]"); return; }
    if (x->isdir) { snprintf(buf, cap, "[dir]"); return; }
    const char *dot = strrchr(bn, '.');
    if (!dot) { snprintf(buf, cap, "(no ext)"); return; }
    size_t k = 0;
    buf[k++] = '.';
    for (const char *c = dot + 1; *c && k + 1 < cap; c++) buf[k++] = (char)((*c >= 'A' && *c <= 'Z') ? *c + 32 : *c);
    buf[k] = 0;
}

/* ---- tiny open-addressing map: (a,b) -> first-seen ordinal ---------------- */
typedef struct { uint64_t a, b; uint32_t v; } slot_t; /* v==0 means empty; ordinal = v-1 */
typedef struct { slot_t *s; size_t mask; uint32_t next; } map_t;

static void map_init(map_t *m, size_t n) {
    size_t cap = 16;
    while (cap < n * 2 + 8) cap <<= 1;
    m->s = calloc(cap, sizeof *m->s);
    if (!m->s) bvk_fatal("out of memory");
    m->mask = cap - 1;
    m->next = 0;
}
static void map_clear(map_t *m) {
    memset(m->s, 0, (m->mask + 1) * sizeof *m->s);
    m->next = 0;
}
static uint32_t map_ord(map_t *m, uint64_t a, uint64_t b) {
    uint64_t h = a * 0x9E3779B97F4A7C15ULL ^ (b + 0x7F4A7C15ULL) * 0xC2B2AE3D27D4EB4FULL;
    h ^= h >> 29;
    size_t i = (size_t)h & m->mask;
    for (;;) {
        slot_t *s = &m->s[i];
        if (!s->v) { s->a = a; s->b = b; s->v = ++m->next; return s->v - 1; }
        if (s->a == a && s->b == b) return s->v - 1;
        i = (i + 1) & m->mask;
    }
}

/* string interning for ext labels */
typedef struct { char **v; size_t n, cap; map_t m; } intern_t;
static uint64_t fnv(const char *s) {
    uint64_t h = 1469598103934665603ULL;
    for (; *s; s++) { h ^= (unsigned char)*s; h *= 1099511628211ULL; }
    return h;
}
static uint64_t ext_intern(intern_t *t, const char *s) {
    uint64_t h = fnv(s);
    size_t i = (size_t)h & t->m.mask;
    for (;;) {
        slot_t *sl = &t->m.s[i];
        if (!sl->v) {
            if (t->n == t->cap) { t->cap = t->cap ? t->cap * 2 : 64; t->v = xrealloc(t->v, t->cap * sizeof *t->v); }
            t->v[t->n] = strdup(s);
            if (!t->v[t->n]) bvk_fatal("out of memory");
            sl->a = h; sl->b = (uint64_t)t->n; sl->v = (uint32_t)(t->n + 1);
            return t->n++;
        }
        if (sl->a == h && !strcmp(t->v[sl->b], s)) return sl->b;
        i = (i + 1) & t->m.mask;
    }
}

static int parse_levels(const char *s, int *lv) {
    int d = 0, seen[4] = {0, 0, 0, 0};
    const char *p = s;
    while (*p) {
        const char *e = strchr(p, ',');
        size_t l = e ? (size_t)(e - p) : strlen(p);
        int k = -1;
        if (l == 3 && !strncmp(p, "ext", 3)) k = L_EXT;
        else if (l == 4 && !strncmp(p, "year", 4)) k = L_YEAR;
        else if (l == 5 && !strncmp(p, "month", 5)) k = L_MONTH;
        else if (l == 4 && !strncmp(p, "date", 4)) k = L_DATE;
        if (k >= 0 && !seen[k]) { seen[k] = 1; lv[d++] = k; }
        if (!e) break;
        p = e + 1;
    }
    return d;
}

static void label_of(int lvl, const gi_t *x, char *buf, size_t cap) {
    switch (lvl) {
    case L_EXT:   ext_label(x, buf, cap); break;
    case L_YEAR:  snprintf(buf, cap, "%d", x->year); break;
    case L_MONTH: snprintf(buf, cap, "%d-%s", x->year, MON[x->mon]); break;
    default:      snprintf(buf, cap, "%d-%s-%02d", x->year, MON[x->mon], x->day); break;
    }
}

int group_cmd(const char *paths_file, const char *levels, long hl, const char *prefix) {
    size_t n;
    char *buf;
    char **paths = read_lines(paths_file, &n, &buf);
    int lv[4];
    int d = parse_levels(levels, lv);

    gi_t *g = xmalloc((n ? n : 1) * sizeof *g);
    for (size_t i = 0; i < n; i++) {
        g[i].path = paths[i];
        size_t bl;
        const char *b = path_base(paths[i], &bl);
        g[i].base = b;
    }
    gctx_t c = {g};
    if (d > 0) pool_run(n, 16, 16, stat_one, &c);

    /* per-level first-seen ordinals of the PREFIX key (levels 1..k) */
    uint32_t *rank = xmalloc((n ? n : 1) * (size_t)(d ? d : 1) * sizeof *rank);
    uint32_t nuniq[4] = {0, 0, 0, 0};
    map_t m;
    map_init(&m, n);
    intern_t it = {0};
    if (d > 0) map_init(&it.m, n);

    for (int k = 0; k < d; k++) {
        map_clear(&m);
        for (size_t i = 0; i < n; i++) {
            uint64_t key;
            switch (lv[k]) {
            case L_EXT: { char lab[256]; ext_label(&g[i], lab, sizeof lab); key = ext_intern(&it, lab); break; }
            case L_YEAR:  key = (uint64_t)(int64_t)g[i].year + 100000; break;
            case L_MONTH: key = ((uint64_t)((int64_t)g[i].year + 100000) << 4) | (uint64_t)g[i].mon; break;
            default:      key = ((((uint64_t)((int64_t)g[i].year + 100000) << 4) | (uint64_t)g[i].mon) << 5) | (uint64_t)g[i].day; break;
            }
            uint64_t prev = k ? rank[i * d + (size_t)(k - 1)] : 0;
            rank[i * d + (size_t)k] = map_ord(&m, prev, key);
        }
        nuniq[k] = m.next;
    }

    /* stable LSD counting sort: last level first, ties keep input order */
    size_t *ord = xmalloc((n ? n : 1) * sizeof *ord), *tmp = xmalloc((n ? n : 1) * sizeof *tmp);
    for (size_t i = 0; i < n; i++) ord[i] = i;
    for (int k = d - 1; k >= 0; k--) {
        size_t *cnt = calloc((size_t)nuniq[k] + 2, sizeof *cnt);
        if (!cnt) bvk_fatal("out of memory");
        for (size_t i = 0; i < n; i++) cnt[rank[ord[i] * d + (size_t)k] + 1]++;
        for (uint32_t r = 0; r <= nuniq[k]; r++) cnt[r + 1] += cnt[r];
        for (size_t i = 0; i < n; i++) tmp[cnt[rank[ord[i] * d + (size_t)k]]++] = ord[i];
        free(cnt);
        size_t *sw = ord; ord = tmp; tmp = sw;
    }

    /* group sizes per level (index = prefix ordinal) */
    size_t *gsz[4] = {0, 0, 0, 0};
    for (int k = 0; k < d; k++) {
        gsz[k] = calloc((size_t)nuniq[k] + 1, sizeof *gsz[k]);
        if (!gsz[k]) bvk_fatal("out of memory");
        for (size_t i = 0; i < n; i++) gsz[k][rank[i * d + (size_t)k]]++;
    }

    size_t pl = strlen(prefix);
    char *fn = xmalloc(pl + 16);
    FILE *fi, *fr, *fw;
    memcpy(fn, prefix, pl);
    memcpy(fn + pl, ".items", 7);
    fi = fopen(fn, "w");
    memcpy(fn + pl, ".rows", 6);
    fr = fopen(fn, "w");
    memcpy(fn + pl, ".irow", 6);
    fw = fopen(fn, "w");
    if (!fi || !fr || !fw) return 1;
    static char b1[1 << 18], b2[1 << 18], b3[1 << 18];
    setvbuf(fi, b1, _IOFBF, sizeof b1);
    setvbuf(fr, b2, _IOFBF, sizeof b2);
    setvbuf(fw, b3, _IOFBF, sizeof b3);

    size_t rows = 0, newhl = (hl >= 1 && (size_t)hl <= n) ? 0 : (size_t)(hl > 0 ? hl : 0);
    for (size_t j = 0; j < n; j++) {
        size_t i = ord[j];
        int first_diff = 0;
        if (j > 0) {
            size_t p = ord[j - 1];
            first_diff = d;
            for (int k = 0; k < d; k++)
                if (rank[i * d + (size_t)k] != rank[p * d + (size_t)k]) { first_diff = k; break; }
        }
        for (int k = first_diff; k < d; k++) {
            char lab[320];
            label_of(lv[k], &g[i], lab, sizeof lab);
            fprintf(fr, "H%*s\xE2\x94\x80\xE2\x94\x80 %s: %s (%zu)\n", k * 2, "", LNAME[lv[k]], lab,
                    gsz[k][rank[i * d + (size_t)k]]);
            rows++;
        }
        fprintf(fr, "%zu\n", j + 1);
        rows++;
        fprintf(fw, "%zu\n", rows);
        fputs(g[i].path, fi);
        fputc('\n', fi);
        if (hl >= 1 && (size_t)hl == i + 1) newhl = j + 1;
    }
    if (fclose(fi) || fclose(fr) || fclose(fw)) return 1;
    printf("%zu %zu %zu %d\n", n, rows, newhl, d);
    return 0;
}
