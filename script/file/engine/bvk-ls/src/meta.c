#include "bvk.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int count_children(const char *path) {
    DIR *d = opendir(path);
    if (!d) return -1;
    int n = 0;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        const char *nm = e->d_name;
        if (nm[0] == '.' && (nm[1] == 0 || (nm[1] == '.' && nm[2] == 0))) continue;
        n++;
    }
    closedir(d);
    return n;
}

/* Exact Python stat_one() format: path|size|mtime|children|icon */
char *meta_line(const char *path) {
    struct stat st;
    char *out;
    size_t pl = strlen(path);

    if (stat(path, &st) != 0) {
        out = xmalloc(pl + 16);
        memcpy(out, path, pl);
        memcpy(out + pl, "|0|0|-1|plain", 14);
        return out;
    }
    bool is_dir = S_ISDIR(st.st_mode);
    long long size = is_dir ? 0 : (long long)st.st_size;
    int ch = is_dir ? count_children(path) : -1;

    size_t bl;
    const char *base = path_base(path, &bl);
    const char *ic = icon_for(base, bl, is_dir, (uint32_t)st.st_mode);

    size_t cap = pl + 96;
    out = xmalloc(cap);
    snprintf(out, cap, "%s|%lld|%lld|%d|%s", path, size, (long long)mtime_sec(&st), ch, ic);
    return out;
}

typedef struct {
    char *const *paths;
    char **out;
} meta_ctx_t;

static void meta_one(size_t i, void *p) {
    meta_ctx_t *c = p;
    c->out[i] = meta_line(c->paths[i]);
}

char **meta_many(char *const *paths, size_t n) {
    char **out = xmalloc((n ? n : 1) * sizeof *out);
    meta_ctx_t c = {paths, out};
    pool_run(n, 16, 1, meta_one, &c);
    return out;
}
