/* bvk-fr: find & replace engine for bashbasicsbyvk (names, contents or both; flat or recursive).
 *
 * One small static C binary, no locale / ICU / libc-regex dependency: the regex dialect, the case rules and the
 * \w \d \s classes are implemented here, so every target (glibc static, Android bionic) behaves the same.
 *
 * Module map (src/):
 *   text.c    UTF-8 decode, simple case mapping, word/digit/space classes, byte buffer
 *   tables.c  GENERATED Unicode tables (tests/findrep/gen_tables.py)
 *   regex.c   pattern compiler + backtracking matcher (Python-`re` compatible subset) and the literal fast path
 *   tree.c    directory walk -> item list (pre-order, sorted), path helpers
 *   ops.c     file contents (parallel read / replace / atomic write) and renames (plan, conflicts, apply)
 *   main.c    command line, results / stats / log files, the human preview
 */
#ifndef BVKFR_H
#define BVKFR_H

#ifndef _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS 64
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>

#define FR_PROTO 1

typedef unsigned char uchar;

/* ---- text.c ---------------------------------------------------------- */

void fr_fatal(const char *fmt, ...) __attribute__((noreturn, format(printf, 1, 2)));
void *fr_xmalloc(size_t n);
void *fr_xrealloc(void *p, size_t n);
char *fr_xstrdup(const char *s);

typedef struct {
    uchar *p;
    size_t n, cap;
} buf_t;

void buf_reserve(buf_t *b, size_t extra);
void buf_add(buf_t *b, const void *d, size_t n);
void buf_addc(buf_t *b, int c);
void buf_free(buf_t *b);

/* Decodes one char at s (< end). Invalid / overlong / surrogate / truncated bytes decode as ONE char each with
 * cp = 0xDC00 + byte (what Python's surrogateescape does). Returns the byte length (>= 1). */
int fr_decode(const uchar *s, const uchar *end, uint32_t *cp);
/* Char that ends exactly at p (p > beg). Returns its byte length. */
int fr_prev(const uchar *beg, const uchar *p, uint32_t *cp);
int fr_encode(uint32_t cp, uchar *out); /* cp -> UTF-8 (invalid-byte chars 0xDC80..0xDCFF -> the raw byte) */

uint32_t fr_lower(uint32_t cp); /* simple lower case (== str.lower() when that is one char) */
uint32_t fr_upper(uint32_t cp);
bool fr_is_word(uint32_t cp);
bool fr_is_digit(uint32_t cp);
bool fr_is_space(uint32_t cp);

/* generated tables */
extern const uint32_t fr_lower_tab[][2], fr_upper_tab[][2], fr_word_rng[][2], fr_digit_rng[][2], fr_space_rng[][2];
extern const size_t fr_lower_tab_n, fr_upper_tab_n, fr_word_rng_n, fr_digit_rng_n, fr_space_rng_n;

/* ---- regex.c ---------------------------------------------------------- */

typedef struct matcher matcher_t;
typedef struct mctx mctx_t; /* per-thread scratch state of a matcher */

typedef struct {
    bool regex;      /* pattern is a regex (else literal text) */
    bool icase;      /* match any case */
    bool word;       /* whole word only */
    bool dotall;     /* '.' also matches newline */
} mflags_t;

/* Compiles (pat, rep). On error returns NULL and writes a message into err. In literal mode rep is inserted as is; in
 * regex mode rep understands \0-\9 $0-$9 $& \n \t \r \\ \$ . */
matcher_t *matcher_new(const char *pat, size_t plen, const char *rep, size_t rlen, mflags_t fl, char *err, size_t errsz);
void matcher_free(matcher_t *m);
mctx_t *mctx_new(const matcher_t *m);
void mctx_free(mctx_t *c);
int mctx_error(const mctx_t *c); /* non-zero: the last call gave up (pattern too complex) */

/* Replaces every match in s[0..n) following Python's re.sub rules (empty matches included). Appends the result to out
 * (when out != NULL) and returns the number of replacements. *first (optional) = byte offset of the first match, or
 * (size_t)-1 when there is none. With out == NULL it only counts. */
size_t matcher_replace(const matcher_t *m, mctx_t *c, const uchar *s, size_t n, buf_t *out, size_t *first);
/* true when the pattern matches anywhere in s (no replacing, stops at the first match) */
bool matcher_test(const matcher_t *m, mctx_t *c, const uchar *s, size_t n);

/* ---- tree.c ---------------------------------------------------------- */

typedef enum { IT_FILE = 'f', IT_DIR = 'd', IT_LINK = 'l', IT_OTHER = 'o' } ittype_t;

enum { NS_NONE = 0, NS_PLAN, NS_DONE, NS_CONFLICT, NS_INVALID, NS_ERROR, NS_SKIP };
enum { CS_NONE = 0, CS_MATCH, CS_DONE, CS_ERROR, CS_BINARY, CS_LARGE, CS_SKIP };

typedef struct {
    char *path;           /* root + "/" + relative path */
    uint32_t nameoff;     /* offset of the base name inside path */
    uint32_t parent;      /* index of the parent item, UINT32_MAX = directly under the root */
    uchar typ;            /* ittype_t */
    uchar nstate;         /* NS_* */
    uchar cstate;         /* CS_* */
    int nerr;             /* errno of a failed rename */
    int cerr;             /* errno / FR_E* of a failed content edit */
    char *newname;        /* planned base name (NULL when the name does not change / does not match) */
    uint32_t *rules;      /* rules that touched the name */
    uint32_t nrules;
    uint64_t occ;         /* occurrences in the contents */
    uint32_t line;        /* line of the first match (1-based) */
    char *snippet;        /* first matching line (cut), find / preview only */
    uint64_t size;
    uint32_t subend;      /* pre-order: index just past the last descendant (dirs) */
    uchar excl;           /* left alone: --exclude / not the --only item */
} item_t;

typedef struct {
    item_t *v;
    size_t n, cap;
    size_t dirs_scanned;
    size_t unreadable;     /* directories that could not be read */
} items_t;

typedef struct {
    const char *root;
    bool recursive;
    bool hidden;           /* include dot-files / dot-folders */
    bool vcs;              /* include .git .hg .svn */
    bool need_type;        /* classify every entry (names scope or contents scope) */
} walkopt_t;

void walk_tree(const walkopt_t *o, items_t *its);
char *path_join(const char *dir, const char *name);

/* ---- ops.c ------------------------------------------------------------ */

#define FR_E_BINARY 1000
#define FR_E_TOOBIG 1001
#define FR_E_REGEX  1002

typedef struct {
    const matcher_t **rules;   /* compiled rules, applied one after the other */
    size_t nrules;
    int threads;               /* 0 = auto */
    bool do_names, do_contents;
    bool target_files, target_dirs;
    bool binary;               /* edit binary files too */
    uint64_t maxsize;          /* 0 = no limit */
    bool want_snippet;
    const char *only;          /* restrict to this one path */
    char **exclude;            /* dev/ino of these files are never touched */
    size_t nexclude;
    const char *logfile;       /* rename log "old<TAB>new" */
} runopt_t;

typedef struct {
    uint64_t *rule_occ;        /* per rule: occurrences replaced in contents */
    uint64_t *rule_files;      /* per rule: files it matched */
    uint64_t *rule_names;      /* per rule: names it changed (successful / planned renames) */
    uint64_t files_scanned, files_matched, files_changed, skipped_binary, skipped_large, content_errors;
    uint64_t names_matched, names_planned, names_renamed, names_conflict, names_invalid, names_error;
    uint64_t occ_total;
} stats_t;

/* mode: 0 find (what matches), 1 preview (what would change), 2 apply */
enum { M_FIND = 0, M_PREVIEW = 1, M_APPLY = 2 };

void ops_contents(const runopt_t *o, items_t *its, int mode, stats_t *st);
void ops_names_plan(const runopt_t *o, items_t *its, int mode, stats_t *st);
void ops_names_apply(const runopt_t *o, items_t *its, stats_t *st);
void ops_mark_excluded(const runopt_t *o, items_t *its);

#endif
