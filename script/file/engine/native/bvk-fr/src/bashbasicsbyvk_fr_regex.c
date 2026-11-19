/* Pattern compiler + matcher.
 *
 * Dialect = the common core of Python's `re` (what most people expect from a regex):
 *   literals, . [...] [^...] (ranges, \d \w \s \D \W \S, [:alpha:] ...), ^ $ (line anchors; ^ does not match after the very last newline) \A \Z \b \B,
 *   ( ) (?: ) (?= ) (?! ) (?<= ) (?<! ), |, * + ? {n} {n,} {,m} {n,m} and their lazy forms, \1..\9, \n \t \r \f \v \a \0 \xHH \uHHHH \UHHHHHHHH.
 *   Leading inline flags (?i) (?s) (?m) are accepted.  Everything is on UTF-8 characters; \w \d \s and case folding
 *   use the generated Unicode tables, so the result does not depend on the machine's locale.
 * Matching is a backtracking search (leftmost, ordered alternation, greedy / lazy), with a step budget so a
 * pathological pattern gives up with an error instead of hanging.
 *
 * A pattern that is NOT a regex (the default) takes the literal path: memmem / folded scan, no compile step.
 */
#include "bashbasicsbyvk_fr.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

#define STEP_LIMIT 4000000UL    /* backtracking steps per start position */
#define DEPTH_LIMIT 300000      /* nested match frames */
#define MAX_GROUPS 200
#define MAX_PARSE_DEPTH 100

enum {
    N_NOP, N_CHAR, N_ANY, N_SET, N_BOL, N_EOL, N_BOT, N_EOT, N_WB, N_NWB, N_GOPEN, N_GCLOSE, N_BREF, N_ALT,
    N_REP, N_REPEND, N_LOOK, N_LOOKEND, N_MATCH, N_NWBEF, N_NWAFT
};

typedef struct { uint32_t lo, hi; } rng_t;

enum { CF_WORD = 1, CF_NWORD = 2, CF_DIGIT = 4, CF_NDIGIT = 8, CF_SPACE = 16, CF_NSPACE = 32 };

typedef struct {
    rng_t *r;
    size_t n, cap;
    unsigned cf;
    bool neg;
    uint64_t ascii[2];
} set_t;

typedef struct node {
    uchar type;
    bool greedy, simple, neg, behind;
    struct node *next;
    uint32_t cp;               /* CHAR (already folded when icase); group index for GOPEN/GCLOSE/BREF */
    set_t *set;
    struct node **alts;
    int nalts;
    struct node *join;         /* ALT: the node every branch ends in */
    struct node *body;         /* REP / LOOK */
    struct node *rep;          /* REPEND -> REP */
    uint32_t min, max;
    int slot;
    int width;                 /* LOOK behind: chars to step back */
} node_t;

typedef struct { uchar *lit; size_t n; int grp; } rpart_t;

struct matcher {
    mflags_t fl;
    /* literal path */
    uchar *lit;
    size_t litn;
    uint32_t *litcp;           /* folded code points (icase, non-ASCII or generic path) */
    size_t litcpn;
    bool lit_ascii_fast;       /* ASCII-only pattern, no 'k': bytewise folded compare is exact */
    /* regex path */
    node_t *start;
    int ngroups, nslots;
    node_t **pool;
    size_t npool, cappool;
    set_t **sets;
    size_t nsets, capsets;
    uchar prefix[64];
    size_t prefixn;
    bool has_first;
    bool first_ok[256];
    /* replacement */
    rpart_t *parts;
    size_t nparts;
};

struct mctx {
    const matcher_t *m;
    const uchar *beg, *end;
    const uchar **gs, **cs, **ce;
    uint32_t *cnt;
    const uchar **lastp;
    unsigned long steps;
    int depth;
    int err;
    const uchar *look_target;
    const uchar *match_end;
    const uchar *search_start;
    bool must_adv;
};

/* ======================================================================== */
/* parser                                                                   */
/* ======================================================================== */

typedef struct { node_t *h, *t; } frag_t;

typedef struct {
    matcher_t *m;
    const uchar *s;
    size_t n, i;
    bool icase, dotall;
    char *err;
    size_t errsz;
    bool failed;
    int depth;
    bool open[MAX_GROUPS + 1];   /* groups whose ')' has not been read yet */
} parser_t;

static void perr(parser_t *P, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void perr(parser_t *P, const char *fmt, ...) {
    if (P->failed) return;
    P->failed = true;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(P->err, P->errsz, fmt, ap);
    va_end(ap);
}

static node_t *nnew(parser_t *P, int type) {
    matcher_t *m = P->m;
    node_t *n = calloc(1, sizeof *n);
    if (!n) fr_fatal("out of memory");
    n->type = (uchar)type;
    if (m->npool == m->cappool) {
        m->cappool = m->cappool ? m->cappool * 2 : 32;
        m->pool = fr_xrealloc(m->pool, m->cappool * sizeof *m->pool);
    }
    m->pool[m->npool++] = n;
    return n;
}

static set_t *snew(parser_t *P) {
    matcher_t *m = P->m;
    set_t *s = calloc(1, sizeof *s);
    if (!s) fr_fatal("out of memory");
    if (m->nsets == m->capsets) {
        m->capsets = m->capsets ? m->capsets * 2 : 8;
        m->sets = fr_xrealloc(m->sets, m->capsets * sizeof *m->sets);
    }
    m->sets[m->nsets++] = s;
    return s;
}

static void sadd(set_t *s, uint32_t lo, uint32_t hi) {
    if (s->n == s->cap) {
        s->cap = s->cap ? s->cap * 2 : 8;
        s->r = fr_xrealloc(s->r, s->cap * sizeof *s->r);
    }
    s->r[s->n].lo = lo;
    s->r[s->n].hi = hi;
    s->n++;
}

static int rcmp(const void *a, const void *b) {
    const rng_t *x = a, *y = b;
    return x->lo < y->lo ? -1 : x->lo > y->lo ? 1 : 0;
}

static bool set_hit1(const set_t *s, uint32_t cp) {
    size_t lo = 0, hi = s->n;
    while (lo < hi) {
        size_t mid = (lo + hi) / 2;
        if (s->r[mid].hi < cp) lo = mid + 1;
        else if (s->r[mid].lo > cp) hi = mid;
        else return true;
    }
    if (s->cf) {
        if ((s->cf & CF_WORD) && fr_is_word(cp)) return true;
        if ((s->cf & CF_NWORD) && !fr_is_word(cp)) return true;
        if ((s->cf & CF_DIGIT) && fr_is_digit(cp)) return true;
        if ((s->cf & CF_NDIGIT) && !fr_is_digit(cp)) return true;
        if ((s->cf & CF_SPACE) && fr_is_space(cp)) return true;
        if ((s->cf & CF_NSPACE) && !fr_is_space(cp)) return true;
    }
    return false;
}

static bool set_variants(const set_t *s, uint32_t cp, bool icase) {
    bool h = set_hit1(s, cp);
    if (!h && icase) {
        uint32_t l = fr_lower(cp);
        if (l != cp) h = set_hit1(s, l);
        if (!h) {
            uint32_t u = fr_upper(cp);
            if (u != cp) h = set_hit1(s, u);
        }
    }
    return h;
}

static void sfinish(set_t *s, bool icase) {
    if (s->n > 1) {
        qsort(s->r, s->n, sizeof *s->r, rcmp);
        size_t w = 0;
        for (size_t i = 1; i < s->n; i++) {
            if (s->r[i].lo <= s->r[w].hi + 1 && s->r[w].hi != UINT32_MAX) {
                if (s->r[i].hi > s->r[w].hi) s->r[w].hi = s->r[i].hi;
            } else {
                s->r[++w] = s->r[i];
            }
        }
        s->n = w + 1;
    }
    s->ascii[0] = s->ascii[1] = 0;
    for (uint32_t c = 0; c < 128; c++)
        if (set_variants(s, c, icase) != s->neg) s->ascii[c >> 6] |= 1ULL << (c & 63);
}

static bool set_match(const set_t *s, uint32_t cp, bool icase) {
    if (cp < 128) return (s->ascii[cp >> 6] >> (cp & 63)) & 1;
    return set_variants(s, cp, icase) != s->neg;
}

static int hexv(int c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static bool pat_more(parser_t *P) { return P->i < P->n; }
static int pat_peek(parser_t *P) { return P->i < P->n ? P->s[P->i] : -1; }

/* reads one pattern character (UTF-8 aware) */
static uint32_t pat_getcp(parser_t *P) {
    uint32_t cp;
    int l = fr_decode(P->s + P->i, P->s + P->n, &cp);
    P->i += (size_t)l;
    return cp;
}

/* parses the digits of \xHH \uHHHH \UHHHHHHHH ; returns false (and an error) when malformed */
static bool pat_hex(parser_t *P, int digits, uint32_t *out) {
    uint32_t v = 0;
    for (int k = 0; k < digits; k++) {
        int h = P->i < P->n ? hexv(P->s[P->i]) : -1;
        if (h < 0) {
            perr(P, "bad escape: expected %d hex digits", digits);
            return false;
        }
        v = v * 16 + (uint32_t)h;
        P->i++;
    }
    if (v > 0x10FFFF) {
        perr(P, "bad escape: code point too large");
        return false;
    }
    *out = v;
    return true;
}

/* \0, \012 : the first digit is already read, up to `more` further octal digits follow */
static uint32_t oct_rest(parser_t *P, uint32_t v, int more) {
    while (more-- > 0 && P->i < P->n && P->s[P->i] >= '0' && P->s[P->i] <= '7') v = v * 8 + (uint32_t)(P->s[P->i++] - '0');
    return v;
}

/* escapes that denote ONE character. c = the char after the backslash. Returns true when handled. */
static bool simple_escape(parser_t *P, uint32_t c, uint32_t *out, bool in_class) {
    switch (c) {
    case 'n': *out = '\n'; return true;
    case 't': *out = '\t'; return true;
    case 'r': *out = '\r'; return true;
    case 'f': *out = '\f'; return true;
    case 'v': *out = '\v'; return true;
    case 'a': *out = 7; return true;
    case 'b':
        if (in_class) { *out = 8; return true; }
        return false;
    case '0': *out = oct_rest(P, 0, 2); return true;
    case 'x': return pat_hex(P, 2, out) ? true : (P->failed = true, true);
    case 'u': return pat_hex(P, 4, out) ? true : (P->failed = true, true);
    case 'U': return pat_hex(P, 8, out) ? true : (P->failed = true, true);
    default: return false;
    }
}

static void add_posix(parser_t *P, set_t *s, const char *name, size_t nl) {
#define IS(x) (nl == strlen(x) && !memcmp(name, x, nl))
    if (IS("alpha")) { sadd(s, 'a', 'z'); sadd(s, 'A', 'Z'); }
    else if (IS("digit")) sadd(s, '0', '9');
    else if (IS("alnum")) { sadd(s, 'a', 'z'); sadd(s, 'A', 'Z'); sadd(s, '0', '9'); }
    else if (IS("upper")) sadd(s, 'A', 'Z');
    else if (IS("lower")) sadd(s, 'a', 'z');
    else if (IS("space")) { sadd(s, ' ', ' '); sadd(s, 9, 13); }
    else if (IS("blank")) { sadd(s, ' ', ' '); sadd(s, 9, 9); }
    else if (IS("punct")) { sadd(s, 33, 47); sadd(s, 58, 64); sadd(s, 91, 96); sadd(s, 123, 126); }
    else if (IS("xdigit")) { sadd(s, '0', '9'); sadd(s, 'a', 'f'); sadd(s, 'A', 'F'); }
    else if (IS("cntrl")) { sadd(s, 0, 31); sadd(s, 127, 127); }
    else if (IS("print")) sadd(s, 32, 126);
    else if (IS("graph")) sadd(s, 33, 126);
    else perr(P, "unknown character class [:%.*s:]", (int)nl, name);
#undef IS
}

/* [ ... ]  (the '[' is already consumed) */
static node_t *parse_class(parser_t *P) {
    set_t *s = snew(P);
    bool first = true;
    if (pat_peek(P) == '^') { s->neg = true; P->i++; }
    for (;;) {
        if (!pat_more(P)) { perr(P, "unterminated character set"); return NULL; }
        int pc = pat_peek(P);
        if (pc == ']' && !first) { P->i++; break; }
        first = false;
        uint32_t lo;
        bool is_cls = false;
        if (pc == '[' && P->i + 1 < P->n && P->s[P->i + 1] == ':') {
            const uchar *q = memchr(P->s + P->i + 2, ':', P->n - P->i - 2);
            if (q && q + 1 < P->s + P->n && q[1] == ']') {
                add_posix(P, s, (const char *)P->s + P->i + 2, (size_t)(q - (P->s + P->i + 2)));
                if (P->failed) return NULL;
                P->i = (size_t)(q - P->s) + 2;
                continue;
            }
        }
        if (pc == '\\') {
            P->i++;
            if (!pat_more(P)) { perr(P, "bad escape (end of pattern)"); return NULL; }
            uint32_t e = pat_getcp(P);
            if (e == 'd') { s->cf |= CF_DIGIT; is_cls = true; }
            else if (e == 'D') { s->cf |= CF_NDIGIT; is_cls = true; }
            else if (e == 'w') { s->cf |= CF_WORD; is_cls = true; }
            else if (e == 'W') { s->cf |= CF_NWORD; is_cls = true; }
            else if (e == 's') { s->cf |= CF_SPACE; is_cls = true; }
            else if (e == 'S') { s->cf |= CF_NSPACE; is_cls = true; }
            else if (e >= '1' && e <= '7') {
                lo = oct_rest(P, e - '0', 2);
                if (lo > 255) { perr(P, "octal escape value outside of range 0-0o377"); return NULL; }
            }
            else if (!simple_escape(P, e, &lo, true)) {
                if (e < 128 && isalnum((int)e)) { perr(P, "bad escape \\%c", (int)e); return NULL; }
                lo = e;
            }
            if (P->failed) return NULL;
            if (is_cls) continue;
        } else {
            lo = pat_getcp(P);
        }
        /* range? */
        if (pat_peek(P) == '-' && P->i + 1 < P->n && P->s[P->i + 1] != ']') {
            size_t save = P->i;
            P->i++;
            uint32_t hi;
            if (pat_peek(P) == '\\') {
                P->i++;
                if (!pat_more(P)) { perr(P, "bad escape (end of pattern)"); return NULL; }
                uint32_t e = pat_getcp(P);
                if (strchr("dDwWsS", (int)e) && e < 128) { /* "a-\d": '-' is literal */
                    P->i = save;
                    sadd(s, lo, lo);
                    continue;
                }
                if (!simple_escape(P, e, &hi, true)) {
                    if (e < 128 && isalnum((int)e)) { perr(P, "bad escape \\%c", (int)e); return NULL; }
                    hi = e;
                }
                if (P->failed) return NULL;
            } else {
                hi = pat_getcp(P);
            }
            if (hi < lo) { perr(P, "bad character range"); return NULL; }
            sadd(s, lo, hi);
        } else {
            sadd(s, lo, lo);
        }
    }
    sfinish(s, P->icase);
    node_t *n = nnew(P, N_SET);
    n->set = s;
    return n;
}

static node_t *set_for_class(parser_t *P, unsigned cf) {
    set_t *s = snew(P);
    s->cf = cf;
    sfinish(s, P->icase);
    node_t *n = nnew(P, N_SET);
    n->set = s;
    return n;
}

static node_t *char_node(parser_t *P, uint32_t cp) {
    node_t *n = nnew(P, N_CHAR);
    n->cp = P->icase ? fr_lower(cp) : cp;
    return n;
}

static frag_t parse_alt(parser_t *P);

static frag_t one(node_t *n) { frag_t f = {n, n}; return f; }
static frag_t none(void) { frag_t f = {NULL, NULL}; return f; }

static frag_t cat(frag_t a, frag_t b) {
    if (!a.h) return b;
    if (!b.h) return a;
    a.t->next = b.h;
    a.t = b.t;
    return a;
}

/* number of characters a chain consumes, or -1 when it is not fixed */
static int chain_width(const node_t *n, const node_t *stop) {
    int w = 0;
    while (n && n != stop) {
        switch (n->type) {
        case N_CHAR: case N_ANY: case N_SET:
            w++;
            n = n->next;
            break;
        case N_BREF:
            return -1;
        case N_ALT: {
            int bw = -2;
            for (int i = 0; i < n->nalts; i++) {
                int x = chain_width(n->alts[i], n->join);
                if (x < 0) return -1;
                if (bw == -2) bw = x;
                else if (bw != x) return -1;
            }
            w += bw < 0 ? 0 : bw;
            n = n->join->next;
            break;
        }
        case N_REP: {
            int bw = n->simple ? 1 : chain_width(n->body, NULL);
            if (bw < 0 || n->min != n->max) return -1;
            w += bw * (int)n->min;
            n = n->next;
            break;
        }
        case N_REPEND:
            return w;
        default:
            n = n->next;
            break;
        }
        if (w > 100000) return -1;
    }
    return w;
}

static bool quant_follows(parser_t *P, uint32_t *min, uint32_t *max) {
    int c = pat_peek(P);
    if (c == '*') { P->i++; *min = 0; *max = UINT32_MAX; return true; }
    if (c == '+') { P->i++; *min = 1; *max = UINT32_MAX; return true; }
    if (c == '?') { P->i++; *min = 0; *max = 1; return true; }
    if (c == '{') {
        size_t save = P->i;
        P->i++;
        if (pat_peek(P) == '}') { P->i = save; return false; }
        uint64_t lo = 0, hi = 0;
        bool hlo = false, hhi = false;
        while (pat_more(P) && isdigit(P->s[P->i])) {
            lo = lo * 10 + (uint64_t)(P->s[P->i] - '0');
            hlo = true;
            if (lo > 0xFFFFFFFEULL) { perr(P, "the repetition number is too large"); return false; }
            P->i++;
        }
        if (pat_peek(P) == ',') {
            P->i++;
            while (pat_more(P) && isdigit(P->s[P->i])) {
                hi = hi * 10 + (uint64_t)(P->s[P->i] - '0');
                hhi = true;
                if (hi > 0xFFFFFFFEULL) { perr(P, "the repetition number is too large"); return false; }
                P->i++;
            }
        } else {
            hi = lo;
            hhi = hlo;
        }
        if (pat_peek(P) != '}') { P->i = save; return false; }
        P->i++;
        *min = hlo ? (uint32_t)lo : 0;
        *max = hhi ? (uint32_t)hi : UINT32_MAX;
        if (*max < *min) { perr(P, "min repeat greater than max repeat"); return false; }
        return true;
    }
    return false;
}

static frag_t make_rep(parser_t *P, frag_t item, uint32_t min, uint32_t max, bool greedy) {
    node_t *r = nnew(P, N_REP);
    r->min = min;
    r->max = max;
    r->greedy = greedy;
    node_t *h = item.h;
    if (h == item.t && (h->type == N_CHAR || h->type == N_ANY || h->type == N_SET)) {
        r->simple = true;
        r->body = h;
        h->next = NULL;
    } else {
        node_t *e = nnew(P, N_REPEND);
        e->rep = r;
        item.t->next = e;
        r->body = h;
        r->slot = P->m->nslots++;
    }
    return one(r);
}

/* atom: returns the fragment, sets *repeatable false for anchors */
static frag_t parse_atom(parser_t *P, bool *repeatable) {
    *repeatable = true;
    int c = pat_peek(P);
    if (c == '(') {
        P->i++;
        if (++P->depth > MAX_PARSE_DEPTH) { perr(P, "pattern is nested too deeply"); return none(); }
        bool capture = true, look = false, neg = false, behind = false;
        if (pat_peek(P) == '?') {
            P->i++;
            int d = pat_peek(P);
            if (d == ':') { P->i++; capture = false; }
            else if (d == '=') { P->i++; capture = false; look = true; }
            else if (d == '!') { P->i++; capture = false; look = true; neg = true; }
            else if (d == '<' && P->i + 1 < P->n && (P->s[P->i + 1] == '=' || P->s[P->i + 1] == '!')) {
                neg = P->s[P->i + 1] == '!';
                P->i += 2;
                capture = false; look = true; behind = true;
            } else {
                perr(P, "unsupported group syntax (?%c...", d < 0 ? ' ' : d);
                return none();
            }
        }
        int gi = 0;
        if (capture) {
            if (P->m->ngroups >= MAX_GROUPS) { perr(P, "too many groups"); return none(); }
            gi = ++P->m->ngroups;
            P->open[gi] = true;
        }
        frag_t body = parse_alt(P);
        if (P->failed) return none();
        if (pat_peek(P) != ')') { perr(P, "missing ), unterminated subpattern"); return none(); }
        P->i++;
        P->depth--;
        if (capture) P->open[gi] = false;
        if (look) {
            node_t *l = nnew(P, N_LOOK);
            l->neg = neg;
            l->behind = behind;
            if (!body.h) body = one(nnew(P, N_NOP));
            if (behind) {
                int w = chain_width(body.h, NULL);
                if (w < 0) { perr(P, "look-behind requires fixed-width pattern"); return none(); }
                l->width = w;
            }
            node_t *e = nnew(P, N_LOOKEND);
            e->behind = behind;
            body.t->next = e;
            l->body = body.h;
            *repeatable = false;
            return one(l);
        }
        if (!capture) {
            if (!body.h) body = one(nnew(P, N_NOP));
            return body;
        }
        node_t *o = nnew(P, N_GOPEN), *cl = nnew(P, N_GCLOSE);
        o->cp = cl->cp = (uint32_t)gi;
        frag_t f = one(o);
        f = cat(f, body);
        f = cat(f, one(cl));
        return f;
    }
    if (c == '[') {
        P->i++;
        node_t *n = parse_class(P);
        return n ? one(n) : none();
    }
    if (c == '.') {
        P->i++;
        node_t *n = nnew(P, N_ANY);
        n->neg = P->dotall;   /* neg == dotall for ANY */
        return one(n);
    }
    if (c == '^') { P->i++; *repeatable = false; return one(nnew(P, N_BOL)); }
    if (c == '$') { P->i++; *repeatable = false; return one(nnew(P, N_EOL)); }
    if (c == '\\') {
        P->i++;
        if (!pat_more(P)) { perr(P, "bad escape (end of pattern)"); return none(); }
        uint32_t e = pat_getcp(P);
        switch (e) {
        case 'd': return one(set_for_class(P, CF_DIGIT));
        case 'D': return one(set_for_class(P, CF_NDIGIT));
        case 'w': return one(set_for_class(P, CF_WORD));
        case 'W': return one(set_for_class(P, CF_NWORD));
        case 's': return one(set_for_class(P, CF_SPACE));
        case 'S': return one(set_for_class(P, CF_NSPACE));
        case 'b': *repeatable = false; return one(nnew(P, N_WB));
        case 'B': *repeatable = false; return one(nnew(P, N_NWB));
        case 'A': *repeatable = false; return one(nnew(P, N_BOT));
        case 'Z': *repeatable = false; return one(nnew(P, N_EOT));
        default: break;
        }
        if (e >= '1' && e <= '9') {
            int g = (int)(e - '0');
            if (P->i < P->n && P->s[P->i] >= '0' && P->s[P->i] <= '9') {
                /* two digits: a group number, or (three octal digits) an octal character, as in Python */
                int d2 = P->s[P->i] - '0';
                if (e <= '7' && d2 <= 7 && P->i + 1 < P->n && P->s[P->i + 1] >= '0' && P->s[P->i + 1] <= '7') {
                    uint32_t v = oct_rest(P, (uint32_t)(e - '0'), 2);
                    if (v > 255) { perr(P, "octal escape value outside of range 0-0o377"); return none(); }
                    return one(char_node(P, v));
                }
                P->i++;
                g = g * 10 + d2;
            }
            if (g > P->m->ngroups) { perr(P, "invalid group reference %d", g); return none(); }
            if (P->open[g]) { perr(P, "cannot refer to an open group"); return none(); }
            node_t *n = nnew(P, N_BREF);
            n->cp = (uint32_t)g;
            return one(n);
        }
        uint32_t cp;
        if (simple_escape(P, e, &cp, false)) {
            if (P->failed) return none();
            return one(char_node(P, cp));
        }
        if (e < 128 && isalnum((int)e)) { perr(P, "bad escape \\%c", (int)e); return none(); }
        return one(char_node(P, e));
    }
    if (c == '*' || c == '+' || c == '?') { perr(P, "nothing to repeat"); return none(); }
    if (c == '{') {
        uint32_t a, b;
        size_t save = P->i;
        if (quant_follows(P, &a, &b)) { perr(P, "nothing to repeat"); return none(); }
        if (P->failed) return none();
        P->i = save + 1;
        return one(char_node(P, '{'));
    }
    return one(char_node(P, pat_getcp(P)));
}

static frag_t parse_seq(parser_t *P) {
    frag_t seq = none();
    for (;;) {
        int c = pat_peek(P);
        if (c < 0 || c == '|' || c == ')') break;
        bool repeatable;
        frag_t a = parse_atom(P, &repeatable);
        if (P->failed) return none();
        bool was_rep = false;
        for (;;) {
            uint32_t mn, mx;
            size_t save = P->i;
            int q = pat_peek(P);
            if (q != '*' && q != '+' && q != '?' && q != '{') break;
            if (!quant_follows(P, &mn, &mx)) {
                if (P->failed) return none();
                P->i = save;
                break;
            }
            if (!repeatable) { perr(P, "nothing to repeat"); return none(); }
            if (was_rep) { perr(P, "multiple repeat"); return none(); }
            bool greedy = true;
            if (pat_peek(P) == '?') { P->i++; greedy = false; }
            a = make_rep(P, a, mn, mx, greedy);
            was_rep = true;
        }
        seq = cat(seq, a);
    }
    return seq;
}

static frag_t parse_alt(parser_t *P) {
    frag_t first = parse_seq(P);
    if (P->failed) return none();
    if (pat_peek(P) != '|') return first;
    frag_t br[64];
    size_t nb = 0, cap = 64;
    frag_t *all = br;
    all[nb++] = first;
    while (pat_peek(P) == '|') {
        P->i++;
        frag_t f = parse_seq(P);
        if (P->failed) { if (all != br) free(all); return none(); }
        if (nb == cap) {
            frag_t *na = malloc(cap * 2 * sizeof *na);
            if (!na) fr_fatal("out of memory");
            memcpy(na, all, nb * sizeof *na);
            if (all != br) free(all);
            all = na;
            cap *= 2;
        }
        all[nb++] = f;
    }
    node_t *a = nnew(P, N_ALT), *j = nnew(P, N_NOP);
    a->join = j;
    a->nalts = (int)nb;
    a->alts = malloc(nb * sizeof *a->alts);
    if (!a->alts) fr_fatal("out of memory");
    for (size_t i = 0; i < nb; i++) {
        frag_t f = all[i];
        if (!f.h) f = one(nnew(P, N_NOP));
        f.t->next = j;
        a->alts[i] = f.h;
    }
    if (all != br) free(all);
    frag_t r = {a, j};
    return r;
}

/* ---- first-byte / prefix analysis ------------------------------------- */

static void first_add_cp(bool *ok, uint32_t cp, bool icase) {
    if (cp < 0x80) {
        ok[cp] = true;
        if (icase) {
            ok[fr_lower(cp)] = true;
            ok[fr_upper(cp)] = true;
            for (int k = 0x80; k < 256; k++) ok[k] = true;   /* e.g. the Kelvin sign folds to k */
        }
    } else if (icase) {
        for (int k = 0x80; k < 256; k++) ok[k] = true;
    } else {
        uchar b[4];
        fr_encode(cp, b);
        ok[b[0]] = true;
    }
}

/* returns true when every match must start with one of the bytes marked in ok[] */
static bool first_of(const node_t *n, bool *ok, bool icase, int depth) {
    if (depth > 50) return false;
    while (n) {
        switch (n->type) {
        case N_NOP: case N_GOPEN: case N_GCLOSE: case N_NWBEF:
            n = n->next;
            continue;
        case N_CHAR:
            first_add_cp(ok, n->cp, icase);
            return true;
        case N_SET:
            for (uint32_t c = 0; c < 128; c++)
                if ((n->set->ascii[c >> 6] >> (c & 63)) & 1) ok[c] = true;
            for (int k = 0x80; k < 256; k++) ok[k] = true;
            return true;
        case N_ANY:
            for (int k = 0; k < 256; k++) ok[k] = true;
            return true;
        case N_ALT:
            for (int i = 0; i < n->nalts; i++)
                if (!first_of(n->alts[i], ok, icase, depth + 1)) return false;
            return true;
        case N_REP:
            if (n->min == 0) return false;
            return first_of(n->body, ok, icase, depth + 1);
        default:
            return false;
        }
    }
    return false;
}

static void make_prefix(matcher_t *m, const node_t *n) {
    m->prefixn = 0;
    if (m->fl.icase) return;
    while (n && (n->type == N_NOP || n->type == N_GOPEN || n->type == N_NWBEF)) n = n->next;
    while (n && n->type == N_CHAR && m->prefixn + 4 <= sizeof m->prefix) {
        m->prefixn += (size_t)fr_encode(n->cp, m->prefix + m->prefixn);
        n = n->next;
    }
}

/* ---- replacement template ---------------------------------------------- */

static bool parse_replacement(matcher_t *m, const char *rep, size_t rl, char *err, size_t errsz) {
    rpart_t *parts = NULL;
    size_t np = 0, cap = 0;
    buf_t lit = {0};
#define FLUSH() do { if (lit.n) { if (np == cap) { cap = cap ? cap * 2 : 8; parts = fr_xrealloc(parts, cap * sizeof *parts); } \
        parts[np].lit = fr_xmalloc(lit.n); memcpy(parts[np].lit, lit.p, lit.n); parts[np].n = lit.n; parts[np].grp = -1; np++; lit.n = 0; } } while (0)
#define GROUP(g) do { FLUSH(); if (np == cap) { cap = cap ? cap * 2 : 8; parts = fr_xrealloc(parts, cap * sizeof *parts); } \
        parts[np].lit = NULL; parts[np].n = 0; parts[np].grp = (g); np++; } while (0)
    for (size_t i = 0; i < rl; i++) {
        uchar c = (uchar)rep[i];
        if ((c == '\\' || c == '$') && i + 1 < rl) {
            uchar d = (uchar)rep[i + 1];
            if (d >= '0' && d <= '9') {
                int g = d - '0';
                if (g > m->ngroups) {
                    snprintf(err, errsz, "the replacement uses group %d but the pattern has %d group(s)", g, m->ngroups);
                    buf_free(&lit);
                    return false;
                }
                GROUP(g);
                i++;
                continue;
            }
            if (c == '$' && d == '&') { GROUP(0); i++; continue; }
            if (c == '\\') {
                int o = -1;
                switch (d) {
                case 'n': o = '\n'; break;
                case 't': o = '\t'; break;
                case 'r': o = '\r'; break;
                case '\\': o = '\\'; break;
                case '$': o = '$'; break;
                default: break;
                }
                if (o >= 0) { buf_addc(&lit, o); i++; continue; }
            } else if (d == '$') {
                buf_addc(&lit, '$');
                i++;
                continue;
            }
        }
        buf_addc(&lit, c);
    }
    FLUSH();
#undef FLUSH
#undef GROUP
    buf_free(&lit);
    m->parts = parts;
    m->nparts = np;
    return true;
}

/* ---- construction -------------------------------------------------------- */

matcher_t *matcher_new(const char *pat, size_t plen, const char *rep, size_t rlen, mflags_t fl, char *err, size_t errsz) {
    if (plen == 0) {
        snprintf(err, errsz, "empty find text");
        return NULL;
    }
    matcher_t *m = calloc(1, sizeof *m);
    if (!m) fr_fatal("out of memory");
    m->fl = fl;
    if (!fl.regex) {
        m->lit = fr_xmalloc(plen + 1);
        memcpy(m->lit, pat, plen);
        m->lit[plen] = 0;
        m->litn = plen;
        if (fl.icase) {
            m->litcp = fr_xmalloc((plen + 1) * sizeof *m->litcp);
            const uchar *p = m->lit, *e = m->lit + plen;
            bool ascii = true;
            while (p < e) {
                uint32_t cp;
                int l = fr_decode(p, e, &cp);
                if (cp >= 0x80 || cp == 'k' || cp == 'K') ascii = false;
                m->litcp[m->litcpn++] = fr_lower(cp);
                p += l;
            }
            m->lit_ascii_fast = ascii;
        }
        m->parts = fr_xmalloc(sizeof *m->parts);
        m->parts[0].lit = fr_xmalloc(rlen ? rlen : 1);
        memcpy(m->parts[0].lit, rep, rlen);
        m->parts[0].n = rlen;
        m->parts[0].grp = -1;
        m->nparts = 1;
        return m;
    }
    parser_t P = {0};
    P.m = m;
    P.s = (const uchar *)pat;
    P.n = plen;
    P.icase = fl.icase;
    P.dotall = fl.dotall;
    P.err = err;
    P.errsz = errsz;
    /* leading inline flags (?i) (?s) (?m) (?is) ... */
    if (plen >= 4 && pat[0] == '(' && pat[1] == '?') {
        size_t k = 2;
        while (k < plen && (pat[k] == 'i' || pat[k] == 's' || pat[k] == 'm')) k++;
        if (k > 2 && k < plen && pat[k] == ')') {
            for (size_t j = 2; j < k; j++) {
                if (pat[j] == 'i') P.icase = true;
                if (pat[j] == 's') P.dotall = true;
            }
            P.i = k + 1;
        }
    }
    m->fl.icase = P.icase;
    m->fl.dotall = P.dotall;
    frag_t body = parse_alt(&P);
    if (!P.failed && P.i < P.n) perr(&P, "unbalanced parenthesis");
    if (P.failed) {
        matcher_free(m);
        return NULL;
    }
    frag_t whole = body.h ? body : one(nnew(&P, N_NOP));
    if (fl.word) {
        frag_t w = one(nnew(&P, N_NWBEF));
        w = cat(w, whole);
        w = cat(w, one(nnew(&P, N_NWAFT)));
        whole = w;
    }
    node_t *fin = nnew(&P, N_MATCH);
    whole.t->next = fin;
    m->start = whole.h;
    if (!parse_replacement(m, rep, rlen, err, errsz)) {
        matcher_free(m);
        return NULL;
    }
    make_prefix(m, m->start);
    if (!m->prefixn) m->has_first = first_of(m->start, m->first_ok, m->fl.icase, 0);
    return m;
}

void matcher_free(matcher_t *m) {
    if (!m) return;
    free(m->lit);
    free(m->litcp);
    for (size_t i = 0; i < m->npool; i++) {
        free(m->pool[i]->alts);
        free(m->pool[i]);
    }
    free(m->pool);
    for (size_t i = 0; i < m->nsets; i++) {
        free(m->sets[i]->r);
        free(m->sets[i]);
    }
    free(m->sets);
    for (size_t i = 0; i < m->nparts; i++) free(m->parts[i].lit);
    free(m->parts);
    free(m);
}

mctx_t *mctx_new(const matcher_t *m) {
    mctx_t *c = calloc(1, sizeof *c);
    if (!c) fr_fatal("out of memory");
    c->m = m;
    size_t g = (size_t)m->ngroups + 1;
    c->gs = fr_xmalloc(g * sizeof *c->gs);
    c->cs = fr_xmalloc(g * sizeof *c->cs);
    c->ce = fr_xmalloc(g * sizeof *c->ce);
    c->cnt = fr_xmalloc(((size_t)m->nslots + 1) * sizeof *c->cnt);
    c->lastp = fr_xmalloc(((size_t)m->nslots + 1) * sizeof *c->lastp);
    return c;
}

void mctx_free(mctx_t *c) {
    if (!c) return;
    free(c->gs); free(c->cs); free(c->ce); free(c->cnt); free(c->lastp);
    free(c);
}

int mctx_error(const mctx_t *c) { return c->err; }

/* ======================================================================== */
/* regex matcher                                                            */
/* ======================================================================== */

static int mt(mctx_t *c, const node_t *n, const uchar *p);

static inline bool word_before(const mctx_t *c, const uchar *p) {
    if (p <= c->beg) return false;
    uint32_t cp;
    fr_prev(c->beg, p, &cp);
    return fr_is_word(cp);
}

static inline bool word_after(const mctx_t *c, const uchar *p) {
    if (p >= c->end) return false;
    uint32_t cp;
    fr_decode(p, c->end, &cp);
    return fr_is_word(cp);
}

/* does the single-char node n match the char at p? returns its length or 0 */
static inline int single(const mctx_t *c, const node_t *n, const uchar *p) {
    if (p >= c->end) return 0;
    uint32_t cp;
    int l = fr_decode(p, c->end, &cp);
    switch (n->type) {
    case N_CHAR:
        if (c->m->fl.icase) cp = fr_lower(cp);
        return cp == n->cp ? l : 0;
    case N_ANY:
        return (cp == '\n' && !n->neg) ? 0 : l;
    default:
        return set_match(n->set, cp, c->m->fl.icase) ? l : 0;
    }
}

static int rep_step(mctx_t *c, const node_t *r, const uchar *p) {
    uint32_t cnt = c->cnt[r->slot];
    const uchar *lp = c->lastp[r->slot];
    int res;
    if (cnt < r->min) {
        c->lastp[r->slot] = p;
        c->cnt[r->slot] = cnt + 1;
        res = mt(c, r->body, p);
        c->cnt[r->slot] = cnt;
        c->lastp[r->slot] = lp;
        return res;
    }
    bool more = cnt < r->max && p != lp;
    if (r->greedy) {
        if (more) {
            c->lastp[r->slot] = p;
            c->cnt[r->slot] = cnt + 1;
            res = mt(c, r->body, p);
            c->cnt[r->slot] = cnt;
            c->lastp[r->slot] = lp;
            if (res) return 1;
            if (c->err) return 0;
        }
        return mt(c, r->next, p);
    }
    res = mt(c, r->next, p);
    if (res || c->err) return res;
    if (more) {
        c->lastp[r->slot] = p;
        c->cnt[r->slot] = cnt + 1;
        res = mt(c, r->body, p);
        c->cnt[r->slot] = cnt;
        c->lastp[r->slot] = lp;
    }
    return res;
}

static int rep_simple(mctx_t *c, const node_t *r, const uchar *p) {
    const node_t *b = r->body;
    uint32_t k = 0;
    const uchar *q = p;
    if (r->greedy) {
        while (k < r->max) {
            int l = single(c, b, q);
            if (!l) break;
            q += l;
            k++;
        }
        if (k < r->min) return 0;
        for (;;) {
            if (mt(c, r->next, q)) return 1;
            if (c->err || k == r->min) return 0;
            uint32_t cp;
            q -= fr_prev(p, q, &cp);
            k--;
        }
    }
    while (k < r->min) {
        int l = single(c, b, q);
        if (!l) return 0;
        q += l;
        k++;
    }
    for (;;) {
        if (mt(c, r->next, q)) return 1;
        if (c->err || k >= r->max) return 0;
        int l = single(c, b, q);
        if (!l) return 0;
        q += l;
        k++;
    }
}

static int mt_(mctx_t *c, const node_t *n, const uchar *p) {
    for (;;) {
        if (++c->steps > STEP_LIMIT) { c->err = FR_E_REGEX; return 0; }
        switch (n->type) {
        case N_NOP:
            n = n->next;
            continue;
        case N_CHAR: case N_ANY: case N_SET: {
            int l = single(c, n, p);
            if (!l) return 0;
            p += l;
            n = n->next;
            continue;
        }
        case N_BOL:
            if (p != c->beg && (p[-1] != '\n' || p == c->end)) return 0;   /* like sed / Perl: not after the final newline */
            n = n->next;
            continue;
        case N_EOL:
            if (p != c->end && *p != '\n') return 0;
            n = n->next;
            continue;
        case N_BOT:
            if (p != c->beg) return 0;
            n = n->next;
            continue;
        case N_EOT:
            if (p != c->end) return 0;
            n = n->next;
            continue;
        case N_WB:
            if (word_before(c, p) == word_after(c, p)) return 0;
            n = n->next;
            continue;
        case N_NWB:
            if (c->beg == c->end || word_before(c, p) != word_after(c, p)) return 0;   /* Python: \B never matches empty text */
            n = n->next;
            continue;
        case N_NWBEF:
            if (word_before(c, p)) return 0;
            n = n->next;
            continue;
        case N_NWAFT:
            if (word_after(c, p)) return 0;
            n = n->next;
            continue;
        case N_GOPEN: {
            const uchar *old = c->gs[n->cp];
            c->gs[n->cp] = p;
            int r = mt(c, n->next, p);
            if (!r) c->gs[n->cp] = old;
            return r;
        }
        case N_GCLOSE: {
            const uchar *os = c->cs[n->cp], *oe = c->ce[n->cp];
            c->cs[n->cp] = c->gs[n->cp];
            c->ce[n->cp] = p;
            int r = mt(c, n->next, p);
            if (!r) { c->cs[n->cp] = os; c->ce[n->cp] = oe; }
            return r;
        }
        case N_BREF: {
            const uchar *s = c->cs[n->cp], *e = c->ce[n->cp];
            if (!s) return 0;
            size_t len = (size_t)(e - s);
            if (!c->m->fl.icase) {
                if ((size_t)(c->end - p) < len || memcmp(p, s, len)) return 0;
                p += len;
            } else {
                const uchar *q = p;
                while (s < e) {
                    if (q >= c->end) return 0;
                    uint32_t a, b;
                    int la = fr_decode(s, e, &a), lb = fr_decode(q, c->end, &b);
                    if (fr_lower(a) != fr_lower(b)) return 0;
                    s += la;
                    q += lb;
                }
                p = q;
            }
            n = n->next;
            continue;
        }
        case N_ALT:
            for (int i = 0; i < n->nalts; i++) {
                if (mt(c, n->alts[i], p)) return 1;
                if (c->err) return 0;
            }
            return 0;
        case N_REP: {
            if (n->simple) return rep_simple(c, n, p);
            uint32_t oc = c->cnt[n->slot];
            const uchar *ol = c->lastp[n->slot];
            c->cnt[n->slot] = 0;
            c->lastp[n->slot] = NULL;
            int r = rep_step(c, n, p);
            c->cnt[n->slot] = oc;
            c->lastp[n->slot] = ol;
            return r;
        }
        case N_REPEND:
            return rep_step(c, n->rep, p);
        case N_LOOK: {
            size_t g = (size_t)c->m->ngroups + 1;
            const uchar *sgs[MAX_GROUPS + 1], *scs[MAX_GROUPS + 1], *sce[MAX_GROUPS + 1];
            memcpy(sgs, c->gs, g * sizeof *sgs);
            memcpy(scs, c->cs, g * sizeof *scs);
            memcpy(sce, c->ce, g * sizeof *sce);
            int r;
            if (!n->behind) {
                r = mt(c, n->body, p);
            } else {
                const uchar *q = p;
                bool ok = true;
                for (int i = 0; i < n->width; i++) {
                    if (q <= c->beg) { ok = false; break; }
                    uint32_t cp;
                    q -= fr_prev(c->beg, q, &cp);
                }
                if (!ok) r = 0;
                else {
                    const uchar *ot = c->look_target;
                    c->look_target = p;
                    r = mt(c, n->body, q);
                    c->look_target = ot;
                }
            }
            if (c->err) return 0;
            if (n->neg) {
                memcpy(c->gs, sgs, g * sizeof *sgs);
                memcpy(c->cs, scs, g * sizeof *scs);
                memcpy(c->ce, sce, g * sizeof *sce);
                if (r) return 0;
                n = n->next;
                continue;
            }
            if (!r) return 0;
            r = mt(c, n->next, p);
            if (!r) {
                memcpy(c->gs, sgs, g * sizeof *sgs);
                memcpy(c->cs, scs, g * sizeof *scs);
                memcpy(c->ce, sce, g * sizeof *sce);
            }
            return r;
        }
        case N_LOOKEND:
            return n->behind ? p == c->look_target : 1;
        case N_MATCH:
            if (c->must_adv && p == c->search_start) return 0;
            c->match_end = p;
            return 1;
        }
        return 0;
    }
}

static int mt(mctx_t *c, const node_t *n, const uchar *p) {
    if (++c->depth > DEPTH_LIMIT) {
        c->depth--;
        c->err = FR_E_REGEX;
        return 0;
    }
    int r = mt_(c, n, p);
    c->depth--;
    return r;
}

static int rx_find(const matcher_t *m, mctx_t *c, const uchar *s, size_t n, size_t from, bool adv, size_t *ms, size_t *me) {
    const uchar *end = s + n, *p = s + from;
    c->beg = s;
    c->end = end;
    c->search_start = p;
    c->must_adv = adv;
    size_t ng = (size_t)m->ngroups + 1;
    for (;;) {
        if (m->prefixn) {
            const uchar *q = memmem(p, (size_t)(end - p), m->prefix, m->prefixn);
            if (!q) return 0;
            p = q;
        } else if (m->has_first) {
            while (p < end && !m->first_ok[*p]) p++;
            if (p >= end) return 0;
        }
        for (size_t i = 0; i < ng; i++) c->gs[i] = c->cs[i] = c->ce[i] = NULL;
        c->steps = 0;
        c->depth = 0;
        if (mt(c, m->start, p)) {
            *ms = (size_t)(p - s);
            *me = (size_t)(c->match_end - s);
            c->cs[0] = p;
            c->ce[0] = c->match_end;
            return 1;
        }
        if (c->err) return -1;
        if (p >= end) return 0;
        uint32_t cp;
        p += fr_decode(p, end, &cp);
    }
}

/* ======================================================================== */
/* literal matcher                                                          */
/* ======================================================================== */

static bool lit_word_ok(const uchar *s, size_t n, size_t a, size_t b) {
    uint32_t cp;
    if (a > 0) {
        fr_prev(s, s + a, &cp);
        if (fr_is_word(cp)) return false;
    }
    if (b < n) {
        fr_decode(s + b, s + n, &cp);
        if (fr_is_word(cp)) return false;
    }
    return true;
}

static inline uchar alow(uchar c) { return (c >= 'A' && c <= 'Z') ? (uchar)(c + 32) : c; }

/* folded compare of the pattern at s+a; returns the match end offset or 0 */
static size_t lit_icase_at(const matcher_t *m, const uchar *s, size_t n, size_t a) {
    const uchar *p = s + a, *e = s + n;
    for (size_t i = 0; i < m->litcpn; i++) {
        if (p >= e) return 0;
        uint32_t cp;
        int l = fr_decode(p, e, &cp);
        if (fr_lower(cp) != m->litcp[i]) return 0;
        p += l;
    }
    return (size_t)(p - s);
}

static int lit_find(const matcher_t *m, const uchar *s, size_t n, size_t from, size_t *ms, size_t *me) {
    size_t pos = from;
    if (!m->fl.icase) {
        while (pos + m->litn <= n) {
            const uchar *q = memmem(s + pos, n - pos, m->lit, m->litn);
            if (!q) return 0;
            size_t a = (size_t)(q - s), b = a + m->litn;
            if (!m->fl.word || lit_word_ok(s, n, a, b)) { *ms = a; *me = b; return 1; }
            uint32_t cp;
            pos = a + (size_t)fr_decode(q, s + n, &cp);
        }
        return 0;
    }
    if (m->lit_ascii_fast) {
        uchar f0 = alow(m->lit[0]);
        while (pos + m->litn <= n) {
            while (pos + m->litn <= n && alow(s[pos]) != f0) pos++;
            if (pos + m->litn > n) return 0;
            size_t i = 1;
            while (i < m->litn && alow(s[pos + i]) == alow(m->lit[i])) i++;
            if (i == m->litn && (!m->fl.word || lit_word_ok(s, n, pos, pos + m->litn))) {
                *ms = pos;
                *me = pos + m->litn;
                return 1;
            }
            pos++;
        }
        return 0;
    }
    while (pos < n) {
        size_t b = lit_icase_at(m, s, n, pos);
        if (b && (!m->fl.word || lit_word_ok(s, n, pos, b))) { *ms = pos; *me = b; return 1; }
        uint32_t cp;
        pos += (size_t)fr_decode(s + pos, s + n, &cp);
    }
    return 0;
}

/* ======================================================================== */
/* replace                                                                  */
/* ======================================================================== */

static int find_next(const matcher_t *m, mctx_t *c, const uchar *s, size_t n, size_t from, bool adv, size_t *ms, size_t *me) {
    if (m->fl.regex) return rx_find(m, c, s, n, from, adv, ms, me);
    return lit_find(m, s, n, from, ms, me);
}

static void expand(const matcher_t *m, const mctx_t *c, const uchar *s, size_t ms, size_t me, buf_t *out) {
    for (size_t i = 0; i < m->nparts; i++) {
        const rpart_t *r = &m->parts[i];
        if (r->grp < 0) buf_add(out, r->lit, r->n);
        else if (r->grp == 0) buf_add(out, s + ms, me - ms);
        else if (c && c->cs[r->grp] && c->ce[r->grp]) buf_add(out, c->cs[r->grp], (size_t)(c->ce[r->grp] - c->cs[r->grp]));
    }
}

size_t matcher_replace(const matcher_t *m, mctx_t *c, const uchar *s, size_t n, buf_t *out, size_t *first) {
    size_t cnt = 0, pos = 0, last = 0;
    bool adv = false;
    if (first) *first = (size_t)-1;
    if (c) c->err = 0;
    for (;;) {
        size_t ms, me;
        int r = find_next(m, c, s, n, pos, adv, &ms, &me);
        if (r <= 0) break;
        if (cnt == 0 && first) *first = ms;
        if (out) {
            buf_add(out, s + last, ms - last);
            expand(m, c, s, ms, me, out);
        }
        last = me;
        cnt++;
        adv = (me == ms);
        pos = me;
    }
    if (out && cnt) buf_add(out, s + last, n - last);
    return cnt;
}

bool matcher_test(const matcher_t *m, mctx_t *c, const uchar *s, size_t n) {
    size_t ms, me;
    if (c) c->err = 0;
    return find_next(m, c, s, n, 0, false, &ms, &me) > 0;
}
