/* Group-menu helpers: C twins of the Python get_imaginary_groups /
 * _bvk_fallback_scan code, same rules as group_key() in the shell:
 *   next char after the prefix: letter -> UPPER, digit -> itself,
 *   one of SPECIALS -> itself, anything else -> '#'.
 * Only ASCII is decided here. A non-ASCII char at the group position (or a
 * non-ASCII prefix) needs Unicode rules, so the commands return
 * BVK_NEED_FALLBACK and the shell lets Python answer instead. */
#include "bvk.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char group_key_ascii(unsigned char c) {
    if (c >= 'a' && c <= 'z') return (char)(c - 32);
    if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return (char)c;
    if (c && strchr("_.-()[]{}@!~+=^&%$,;' ", c)) return (char)c;
    return '#';
}

static bool ascii_only(const char *s) {
    for (; *s; s++)
        if ((unsigned char)*s >= 0x80) return false;
    return true;
}

/* groups DIR HIDDEN PREFIX -> "CH<TAB>count" per group, first-seen order. */
int groups_cmd(FILE *out, const char *dir, bool hidden, const char *pfx) {
    if (!ascii_only(pfx)) return BVK_NEED_FALLBACK;
    size_t plen = strlen(pfx);
    arena_t ar = {0};
    ents_t es = {0};
    list_dir(dir, hidden, pfx, &es, &ar);

    long cnt[256] = {0};
    unsigned char order[256];
    int no = 0;
    for (size_t i = 0; i < es.n; i++) {
        const char *nm = es.v[i].name;
        if (strlen(nm) <= plen) continue;
        unsigned char c = (unsigned char)nm[plen];
        if (c >= 0x80) return BVK_NEED_FALLBACK;
        unsigned char k = (unsigned char)group_key_ascii(c);
        if (!cnt[k]++) order[no++] = k;
    }
    for (int j = 0; j < no; j++) fprintf(out, "%c\t%ld\n", order[j], cnt[order[j]]);
    return 0;
}

/* hashscan DIR HIDDEN PREFIX -> full paths whose group key is '#'. */
int hashscan_cmd(FILE *out, const char *dir, bool hidden, const char *pfx) {
    if (!ascii_only(pfx)) return BVK_NEED_FALLBACK;
    size_t plen = strlen(pfx);
    arena_t ar = {0};
    ents_t es = {0};
    list_dir(dir, hidden, pfx, &es, &ar);

    for (size_t i = 0; i < es.n; i++) { /* decide first, print after */
        const char *nm = es.v[i].name;
        if (strlen(nm) > plen && (unsigned char)nm[plen] >= 0x80) return BVK_NEED_FALLBACK;
    }
    size_t dl = strlen(dir);
    for (size_t i = 0; i < es.n; i++) {
        const char *nm = es.v[i].name;
        if (strlen(nm) <= plen || group_key_ascii((unsigned char)nm[plen]) != '#') continue;
        fputs(dir, out);
        if (!(dl > 0 && dir[dl - 1] == '/')) fputc('/', out);
        fputs(nm, out);
        fputc('\n', out);
    }
    return 0;
}

/* ---- gfilter: the "=" filter inside the group menu ---------------------- */

static unsigned char lc(unsigned char c) { return (c >= 'A' && c <= 'Z') ? (unsigned char)(c + 32) : c; }

static bool ci_prefix(const char *s, const char *q) {
    for (; *q; s++, q++)
        if (!*s || lc((unsigned char)*s) != lc((unsigned char)*q)) return false;
    return true;
}

static bool ci_contains(const char *s, const char *q) {
    if (!*q) return true;
    for (; *s; s++)
        if (ci_prefix(s, q)) return true;
    return false;
}

/* gfilter DIR HIDDEN PREFIX QUERY MODE -> "G<TAB>ch<TAB>count" lines, then
 * "F<TAB>path" lines for every entry whose text after PREFIX matches QUERY
 * (MODE "exact" = starts with, anything else = contains). */
int gfilter_cmd(FILE *out, const char *dir, bool hidden, const char *pfx, const char *q,
                const char *mode) {
    if (!ascii_only(pfx) || !ascii_only(q)) return BVK_NEED_FALLBACK;
    bool exact = !strcmp(mode, "exact");
    size_t plen = strlen(pfx);
    arena_t ar = {0};
    ents_t es = {0};
    list_dir(dir, hidden, pfx, &es, &ar);

    unsigned char *keep = calloc(es.n ? es.n : 1, 1);
    if (!keep) bvk_fatal("out of memory");
    long cnt[256] = {0};
    unsigned char order[256];
    int no = 0;
    for (size_t i = 0; i < es.n; i++) {
        const char *nm = es.v[i].name;
        if (strlen(nm) <= plen) continue;
        const char *tail = nm + plen;
        if (*q && !(exact ? ci_prefix(tail, q) : ci_contains(tail, q))) continue;
        unsigned char c = (unsigned char)tail[0];
        if (c >= 0x80) { free(keep); return BVK_NEED_FALLBACK; }
        unsigned char k = (unsigned char)group_key_ascii(c);
        if (!cnt[k]++) order[no++] = k;
        keep[i] = 1;
    }
    for (int j = 0; j < no; j++) fprintf(out, "G\t%c\t%ld\n", order[j], cnt[order[j]]);
    size_t dl = strlen(dir);
    for (size_t i = 0; i < es.n; i++) {
        if (!keep[i]) continue;
        fputs("F\t", out);
        fputs(dir, out);
        if (!(dl > 0 && dir[dl - 1] == '/')) fputc('/', out);
        fputs(es.v[i].name, out);
        fputc('\n', out);
    }
    free(keep);
    return 0;
}
