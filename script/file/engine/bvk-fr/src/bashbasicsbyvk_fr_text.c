#include "bashbasicsbyvk_fr.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

void fr_fatal(const char *fmt, ...) {
    va_list ap;
    fflush(stdout);
    fputs("bvk-fr: ", stderr);
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(2);
}

void *fr_xmalloc(size_t n) {
    void *p = malloc(n ? n : 1);
    if (!p) fr_fatal("out of memory");
    return p;
}

void *fr_xrealloc(void *p, size_t n) {
    p = realloc(p, n ? n : 1);
    if (!p) fr_fatal("out of memory");
    return p;
}

char *fr_xstrdup(const char *s) {
    size_t n = strlen(s) + 1;
    char *r = fr_xmalloc(n);
    memcpy(r, s, n);
    return r;
}

/* ---- buffer ---------------------------------------------------------- */

void buf_reserve(buf_t *b, size_t extra) {
    if (b->n + extra + 1 <= b->cap) return;
    size_t cap = b->cap ? b->cap : 256;
    while (cap < b->n + extra + 1) cap += cap / 2 + 64;
    b->p = fr_xrealloc(b->p, cap);
    b->cap = cap;
}

void buf_add(buf_t *b, const void *d, size_t n) {
    if (!n) return;
    buf_reserve(b, n);
    memcpy(b->p + b->n, d, n);
    b->n += n;
}

void buf_addc(buf_t *b, int c) {
    buf_reserve(b, 1);
    b->p[b->n++] = (uchar)c;
}

void buf_free(buf_t *b) {
    free(b->p);
    b->p = NULL;
    b->n = b->cap = 0;
}

/* ---- UTF-8 ----------------------------------------------------------- */

#define ISCONT(x) (((x) & 0xC0) == 0x80)

int fr_decode(const uchar *s, const uchar *end, uint32_t *cp) {
    uint32_t c = s[0];
    if (c < 0x80) {
        *cp = c;
        return 1;
    }
    size_t avail = (size_t)(end - s);
    if (c >= 0xC2 && c <= 0xDF) {
        if (avail >= 2 && ISCONT(s[1])) {
            *cp = ((c & 0x1F) << 6) | (s[1] & 0x3F);
            return 2;
        }
    } else if (c >= 0xE0 && c <= 0xEF) {
        if (avail >= 3 && ISCONT(s[1]) && ISCONT(s[2])) {
            if ((c == 0xE0 && s[1] < 0xA0) || (c == 0xED && s[1] > 0x9F)) goto bad;
            *cp = ((c & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | (s[2] & 0x3F);
            return 3;
        }
    } else if (c >= 0xF0 && c <= 0xF4) {
        if (avail >= 4 && ISCONT(s[1]) && ISCONT(s[2]) && ISCONT(s[3])) {
            if ((c == 0xF0 && s[1] < 0x90) || (c == 0xF4 && s[1] > 0x8F)) goto bad;
            *cp = ((c & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12) | ((uint32_t)(s[2] & 0x3F) << 6) | (s[3] & 0x3F);
            return 4;
        }
    }
bad:
    *cp = 0xDC00 + c;
    return 1;
}

int fr_prev(const uchar *beg, const uchar *p, uint32_t *cp) {
    uchar b = p[-1];
    if (b < 0x80) {
        *cp = b;
        return 1;
    }
    for (int len = 2; len <= 4; len++) {
        if (p - len < beg) break;
        uint32_t c;
        int l = fr_decode(p - len, p, &c);
        if (l == len) {
            *cp = c;
            return len;
        }
    }
    *cp = 0xDC00 + b;
    return 1;
}

int fr_encode(uint32_t cp, uchar *o) {
    if (cp >= 0xDC80 && cp <= 0xDCFF) {
        o[0] = (uchar)(cp - 0xDC00);
        return 1;
    }
    if (cp < 0x80) {
        o[0] = (uchar)cp;
        return 1;
    }
    if (cp < 0x800) {
        o[0] = (uchar)(0xC0 | (cp >> 6));
        o[1] = (uchar)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        o[0] = (uchar)(0xE0 | (cp >> 12));
        o[1] = (uchar)(0x80 | ((cp >> 6) & 0x3F));
        o[2] = (uchar)(0x80 | (cp & 0x3F));
        return 3;
    }
    o[0] = (uchar)(0xF0 | (cp >> 18));
    o[1] = (uchar)(0x80 | ((cp >> 12) & 0x3F));
    o[2] = (uchar)(0x80 | ((cp >> 6) & 0x3F));
    o[3] = (uchar)(0x80 | (cp & 0x3F));
    return 4;
}

/* ---- case + classes -------------------------------------------------- */

static uint32_t map_pair(const uint32_t (*tab)[2], size_t n, uint32_t cp) {
    size_t lo = 0, hi = n;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (tab[mid][0] < cp) lo = mid + 1;
        else if (tab[mid][0] > cp) hi = mid;
        else return tab[mid][1];
    }
    return cp;
}

static bool in_ranges(const uint32_t (*r)[2], size_t n, uint32_t cp) {
    size_t lo = 0, hi = n;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (r[mid][1] < cp) lo = mid + 1;
        else if (r[mid][0] > cp) hi = mid;
        else return true;
    }
    return false;
}

uint32_t fr_lower(uint32_t cp) {
    if (cp < 0x80) return (cp >= 'A' && cp <= 'Z') ? cp + 32 : cp;
    return map_pair(fr_lower_tab, fr_lower_tab_n, cp);
}

uint32_t fr_upper(uint32_t cp) {
    if (cp < 0x80) return (cp >= 'a' && cp <= 'z') ? cp - 32 : cp;
    return map_pair(fr_upper_tab, fr_upper_tab_n, cp);
}

bool fr_is_word(uint32_t cp) {
    if (cp < 0x80) return (cp >= '0' && cp <= '9') || (cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z') || cp == '_';
    return in_ranges(fr_word_rng, fr_word_rng_n, cp);
}

bool fr_is_digit(uint32_t cp) {
    if (cp < 0x80) return cp >= '0' && cp <= '9';
    return in_ranges(fr_digit_rng, fr_digit_rng_n, cp);
}

bool fr_is_space(uint32_t cp) {
    if (cp < 0x80) return cp == ' ' || (cp >= 9 && cp <= 13) || (cp >= 0x1C && cp <= 0x1F);
    return in_ranges(fr_space_rng, fr_space_rng_n, cp);
}
