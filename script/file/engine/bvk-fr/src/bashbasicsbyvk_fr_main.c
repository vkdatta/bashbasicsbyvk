/* bvk-fr: find & replace in file / folder names, file contents, or both.
 *
 *   bvk-fr find|preview|apply [options]      (what matches | what would change | do it)
 *   bvk-fr selftest                           prints "bvk-fr ok"
 *   bvk-fr proto                              prints the protocol number
 *
 *   --root DIR            folder to work in (required)
 *   --scope names|contents|both
 *   --depth flat|rec      flat = only the entries directly in DIR
 *   --case exact|any      --regex 0|1      --word 0|1
 *   --hidden 0|1         include dot-files / dot-folders        --vcs 0|1   include .git .hg .svn
 *   --target files|dirs|both     which entries may be renamed / matched by name
 *   --binary 0|1          also edit files that contain NUL bytes
 *   --maxsize BYTES       skip bigger files (0 = no limit)       --threads N (0 = auto)
 *   --rules FILE          NUL separated: find NUL replacement NUL find NUL replacement NUL ...  (applied in this order)
 *   --exclude PATH        never touch this file (repeatable)     --only PATH   touch only this one entry
 *   --limit N             at most N result lines on stdout (default 300)
 *   --out FILE            NUL separated paths of the listed items, in listing order
 *   --stats FILE          key=value summary                      --log FILE   "old<TAB>new" lines of the renames done
 *
 * stdout: the numbered result lines (names are shown with control characters escaped).  Exit 0 = ran, 2 = bad
 * usage / bad pattern (message on stderr).
 */
#include "bashbasicsbyvk_fr.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

typedef struct {
    const char *cmd;
    const char *root, *scope, *depth, *casem, *target;
    bool regex, word, hidden, vcs, binary;
    uint64_t maxsize;
    int threads;
    const char *rules_file, *only, *out, *stats, *log;
    char **exclude;
    size_t nexclude;
    long limit;
} cli_t;

static const char *need(int argc, char **argv, int *i) {
    if (*i + 1 >= argc) fr_fatal("option %s needs a value", argv[*i]);
    return argv[++*i];
}

static bool truthy(const char *s) { return s[0] == '1' || !strcmp(s, "on") || !strcmp(s, "yes") || !strcmp(s, "true"); }

static void parse_cli(int argc, char **argv, cli_t *c) {
    memset(c, 0, sizeof *c);
    c->scope = "names";
    c->depth = "rec";
    c->casem = "exact";
    c->target = "both";
    c->limit = 300;
    c->cmd = argv[1];
    for (int i = 2; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--root")) c->root = need(argc, argv, &i);
        else if (!strcmp(a, "--scope")) c->scope = need(argc, argv, &i);
        else if (!strcmp(a, "--depth")) c->depth = need(argc, argv, &i);
        else if (!strcmp(a, "--case")) c->casem = need(argc, argv, &i);
        else if (!strcmp(a, "--target")) c->target = need(argc, argv, &i);
        else if (!strcmp(a, "--regex")) c->regex = truthy(need(argc, argv, &i));
        else if (!strcmp(a, "--word")) c->word = truthy(need(argc, argv, &i));
        else if (!strcmp(a, "--hidden")) c->hidden = truthy(need(argc, argv, &i));
        else if (!strcmp(a, "--vcs")) c->vcs = truthy(need(argc, argv, &i));
        else if (!strcmp(a, "--binary")) c->binary = truthy(need(argc, argv, &i));
        else if (!strcmp(a, "--maxsize")) c->maxsize = strtoull(need(argc, argv, &i), NULL, 10);
        else if (!strcmp(a, "--threads")) c->threads = atoi(need(argc, argv, &i));
        else if (!strcmp(a, "--rules")) c->rules_file = need(argc, argv, &i);
        else if (!strcmp(a, "--only")) c->only = need(argc, argv, &i);
        else if (!strcmp(a, "--out")) c->out = need(argc, argv, &i);
        else if (!strcmp(a, "--stats")) c->stats = need(argc, argv, &i);
        else if (!strcmp(a, "--log")) c->log = need(argc, argv, &i);
        else if (!strcmp(a, "--limit")) c->limit = atol(need(argc, argv, &i));
        else if (!strcmp(a, "--exclude")) {
            c->exclude = fr_xrealloc(c->exclude, (c->nexclude + 1) * sizeof *c->exclude);
            c->exclude[c->nexclude++] = (char *)need(argc, argv, &i);
        } else fr_fatal("unknown option %s", a);
    }
    if (!c->root) fr_fatal("--root is required");
    if (!c->rules_file) fr_fatal("--rules is required");
    if (strcmp(c->scope, "names") && strcmp(c->scope, "contents") && strcmp(c->scope, "both")) fr_fatal("bad --scope");
    if (strcmp(c->depth, "flat") && strcmp(c->depth, "rec")) fr_fatal("bad --depth");
    if (strcmp(c->casem, "exact") && strcmp(c->casem, "any")) fr_fatal("bad --case");
    if (strcmp(c->target, "files") && strcmp(c->target, "dirs") && strcmp(c->target, "both")) fr_fatal("bad --target");
}

/* ---- rules ---------------------------------------------------------------- */

static char *slurp(const char *file, size_t *n) {
    FILE *f = fopen(file, "rb");
    if (!f) fr_fatal("cannot read %s: %s", file, strerror(errno));
    size_t cap = 4096, len = 0;
    char *b = fr_xmalloc(cap);
    for (;;) {
        size_t r = fread(b + len, 1, cap - len, f);
        len += r;
        if (len < cap) break;
        cap *= 2;
        b = fr_xrealloc(b, cap);
    }
    fclose(f);
    *n = len;
    return b;
}

static const matcher_t **load_rules(const cli_t *c, size_t *nrules) {
    size_t n;
    char *b = slurp(c->rules_file, &n);
    const matcher_t **rs = NULL;
    size_t nr = 0, cap = 0, i = 0;
    mflags_t fl = {.regex = c->regex, .icase = !strcmp(c->casem, "any"), .word = c->word, .dotall = false};
    while (i < n) {
        const char *find = b + i;
        size_t fl_len = strnlen(find, n - i);
        i += fl_len + 1;
        const char *rep = "";
        size_t rl = 0;
        if (i < n) {
            rep = b + i;
            rl = strnlen(rep, n - i);
            i += rl + 1;
        }
        char err[256] = "";
        matcher_t *m = matcher_new(find, fl_len, rep, rl, fl, err, sizeof err);
        if (!m) fr_fatal("rule %zu: %s", nr + 1, err);
        if (nr == cap) {
            cap = cap ? cap * 2 : 16;
            rs = fr_xrealloc(rs, cap * sizeof *rs);
        }
        rs[nr++] = m;
    }
    if (!nr) fr_fatal("no rules in %s", c->rules_file);
    free(b);
    *nrules = nr;
    return rs;
}

/* ---- output ------------------------------------------------------------- */

static void put_esc(FILE *o, const char *s) {
    for (; *s; s++) {
        unsigned char ch = (unsigned char)*s;
        if (ch == '\n') fputs("\\n", o);
        else if (ch == '\t') fputs("\\t", o);
        else if (ch == '\r') fputs("\\r", o);
        else if (ch < 0x20 || ch == 0x7f) fprintf(o, "\\x%02x", ch);
        else fputc(ch, o);
    }
}

static const char *why(int e) {
    if (e == FR_E_REGEX) return "pattern too complex for this text";
    if (e == EEXIST) return "a name like that already exists";
    return strerror(e);
}

static bool reportable(const item_t *it, int mode) {
    if (mode == M_FIND) return it->nstate == NS_PLAN || it->cstate == CS_MATCH;
    if (mode == M_PREVIEW)
        return it->nstate == NS_PLAN || it->nstate == NS_CONFLICT || it->nstate == NS_INVALID || it->nstate == NS_ERROR ||
               it->cstate == CS_MATCH || it->cstate == CS_ERROR;
    return it->nstate == NS_CONFLICT || it->nstate == NS_INVALID || it->nstate == NS_ERROR || it->cstate == CS_ERROR;
}

static void print_item(FILE *o, const cli_t *c, const item_t *it, size_t idx, size_t rootlen, int mode) {
    const char *rel = it->path + rootlen;
    if (mode == M_APPLY) fputs("  ⚠ ", o);
    else fprintf(o, "%4zu) ", idx);
    put_esc(o, rel);
    if (it->typ == IT_DIR) fputc('/', o);
    if (it->newname && (mode != M_FIND) && (it->nstate == NS_PLAN || it->nstate == NS_CONFLICT || it->nstate == NS_INVALID || it->nstate == NS_ERROR)) {
        fputs("  →  ", o);
        put_esc(o, it->newname);
        if (it->typ == IT_DIR) fputc('/', o);
    }
    if (it->nstate == NS_CONFLICT) fputs("   ⚠ skipped: a name like that already exists", o);
    else if (it->nstate == NS_INVALID) fputs("   ⚠ skipped: not a usable name", o);
    else if (it->nstate == NS_ERROR) fprintf(o, "   ⚠ %s", why(it->nerr));
    if (it->cstate == CS_MATCH || it->cstate == CS_DONE) fprintf(o, "  (%llu match%s)", (unsigned long long)it->occ, it->occ == 1 ? "" : "es");
    if (it->cstate == CS_ERROR) fprintf(o, "   ⚠ not edited: %s", why(it->cerr));
    fputc('\n', o);
    if (it->snippet && mode != M_APPLY) {
        fprintf(o, "        L%u: ", it->line);
        put_esc(o, it->snippet);
        fputc('\n', o);
    }
    (void)c;
}

static void write_stats(const cli_t *c, const items_t *its, const stats_t *st, size_t nrules, size_t listed, long ms) {
    if (!c->stats) return;
    FILE *f = fopen(c->stats, "w");
    if (!f) return;
    fprintf(f, "items=%zu\ndirs_scanned=%zu\nunreadable=%zu\nlisted=%zu\nms=%ld\n", its->n, its->dirs_scanned, its->unreadable, listed, ms);
    fprintf(f, "names_matched=%llu\nnames_planned=%llu\nnames_renamed=%llu\nnames_conflict=%llu\nnames_invalid=%llu\nnames_error=%llu\n",
            (unsigned long long)st->names_matched, (unsigned long long)st->names_planned, (unsigned long long)st->names_renamed,
            (unsigned long long)st->names_conflict, (unsigned long long)st->names_invalid, (unsigned long long)st->names_error);
    fprintf(f, "files_scanned=%llu\nfiles_matched=%llu\nfiles_changed=%llu\noccurrences=%llu\ncontent_errors=%llu\nskipped_binary=%llu\nskipped_large=%llu\n",
            (unsigned long long)st->files_scanned, (unsigned long long)st->files_matched, (unsigned long long)st->files_changed,
            (unsigned long long)st->occ_total, (unsigned long long)st->content_errors, (unsigned long long)st->skipped_binary,
            (unsigned long long)st->skipped_large);
    fprintf(f, "rules=%zu\n", nrules);
    for (size_t r = 0; r < nrules; r++)
        fprintf(f, "r%zu_occ=%llu\nr%zu_files=%llu\nr%zu_names=%llu\n", r, (unsigned long long)st->rule_occ[r], r,
                (unsigned long long)st->rule_files[r], r, (unsigned long long)st->rule_names[r]);
    fclose(f);
}

static long now_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long)(t.tv_sec * 1000L + t.tv_nsec / 1000000L);
}

/* ---- selftest -------------------------------------------------------------- */

static int check(const char *pat, const char *rep, mflags_t fl, const char *in, const char *want) {
    char err[200];
    matcher_t *m = matcher_new(pat, strlen(pat), rep, strlen(rep), fl, err, sizeof err);
    if (!m) return 0;
    mctx_t *c = mctx_new(m);
    buf_t out = {0};
    size_t cnt = matcher_replace(m, c, (const uchar *)in, strlen(in), &out, NULL);
    int ok;
    if (cnt == 0) ok = strcmp(in, want) == 0;
    else ok = out.n == strlen(want) && !memcmp(out.p, want, out.n);
    buf_free(&out);
    mctx_free(c);
    matcher_free(m);
    return ok;
}

static int selftest(void) {
    mflags_t lit = {0}, rx = {.regex = true}, li = {.icase = true}, rxi = {.regex = true, .icase = true};
    int ok = 1;
    ok &= check("hello [c]", "X", lit, "a hello [c] b hello c", "a X b hello c");
    ok &= check("ÉCOLE", "x", li, "école École", "x x");
    ok &= check("(a+)(b*)", "<\\2\\1>", rx, "aab ab a", "<baa> <ba> <a>");
    ok &= check("x*", "-", rx, "abxd", "-a-b--d-");
    ok &= check("^", "> ", rx, "a\nb", "> a\n> b");
    ok &= check("[[:digit:]]+", "#", rx, "a12b3", "a#b#");
    ok &= check("(?<=a)b", "X", rxi, "ab AB cb", "aX AX cb");
    return ok;
}

/* ---- main ------------------------------------------------------------------ */

int main(int argc, char **argv) {
    if (argc < 2) fr_fatal("usage: bvk-fr find|preview|apply --root DIR --rules FILE [options] | selftest | proto");
    if (!strcmp(argv[1], "selftest")) {
        if (selftest()) { puts("bvk-fr ok"); return 0; }
        puts("bvk-fr FAILED");
        return 1;
    }
    if (!strcmp(argv[1], "proto")) {
        printf("%d\n", FR_PROTO);
        return 0;
    }
    int mode;
    if (!strcmp(argv[1], "find")) mode = M_FIND;
    else if (!strcmp(argv[1], "preview")) mode = M_PREVIEW;
    else if (!strcmp(argv[1], "apply")) mode = M_APPLY;
    else fr_fatal("unknown command \"%s\"", argv[1]);

    long t0 = now_ms();
    cli_t c;
    parse_cli(argc, argv, &c);
    static char obuf[1 << 16];
    setvbuf(stdout, obuf, _IOFBF, sizeof obuf);

    size_t nrules;
    const matcher_t **rules = load_rules(&c, &nrules);

    /* root without a trailing slash (but "/" stays) */
    char *root = fr_xstrdup(c.root);
    size_t rl = strlen(root);
    while (rl > 1 && root[rl - 1] == '/') root[--rl] = 0;
    size_t rootlen = rl + (rl == 1 && root[0] == '/' ? 0 : 1);

    runopt_t o;
    memset(&o, 0, sizeof o);
    o.rules = rules;
    o.nrules = nrules;
    o.threads = c.threads;
    o.do_names = strcmp(c.scope, "contents") != 0;
    o.do_contents = strcmp(c.scope, "names") != 0;
    o.target_files = strcmp(c.target, "dirs") != 0;
    o.target_dirs = strcmp(c.target, "files") != 0;
    o.binary = c.binary;
    o.maxsize = c.maxsize;
    o.want_snippet = (mode != M_APPLY);
    o.only = c.only;
    o.exclude = c.exclude;
    o.nexclude = c.nexclude;
    o.logfile = c.log;

    stats_t st;
    memset(&st, 0, sizeof st);
    st.rule_occ = calloc(nrules, sizeof(uint64_t));
    st.rule_files = calloc(nrules, sizeof(uint64_t));
    st.rule_names = calloc(nrules, sizeof(uint64_t));

    walkopt_t w = {.root = root, .recursive = !strcmp(c.depth, "rec"), .hidden = c.hidden, .vcs = c.vcs, .need_type = true};
    items_t its = {0};
    {
        struct stat sb;
        if (stat(root, &sb) != 0 || !S_ISDIR(sb.st_mode)) fr_fatal("%s is not a folder", root);
    }
    walk_tree(&w, &its);
    ops_mark_excluded(&o, &its);

    if (o.do_contents) ops_contents(&o, &its, mode, &st);
    if (o.do_names) {
        ops_names_plan(&o, &its, mode, &st);
        if (mode == M_APPLY) ops_names_apply(&o, &its, &st);
    }

    /* ---- listing ---- */
    FILE *outf = c.out ? fopen(c.out, "wb") : NULL;
    size_t listed = 0;
    for (size_t i = 0; i < its.n; i++) {
        const item_t *it = &its.v[i];
        if (!reportable(it, mode)) continue;
        listed++;
        if (outf && mode != M_APPLY) {
            fwrite(it->path, 1, strlen(it->path) + 1, outf);
        }
        if (c.limit <= 0 || (long)listed <= c.limit) print_item(stdout, &c, it, listed, rootlen, mode);
    }
    if (c.limit > 0 && (long)listed > c.limit) printf("  … and %zu more (not shown)\n", listed - (size_t)c.limit);
    if (outf) fclose(outf);
    write_stats(&c, &its, &st, nrules, listed, now_ms() - t0);
    if (fflush(stdout) != 0) return 1;
    return 0;
}
