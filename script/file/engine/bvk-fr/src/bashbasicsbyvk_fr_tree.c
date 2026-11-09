#include "bashbasicsbyvk_fr.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_WALK_DEPTH 400

char *path_join(const char *dir, const char *name) {
    size_t dl = strlen(dir), nl = strlen(name);
    bool slash = !(dl > 0 && dir[dl - 1] == '/');
    char *r = fr_xmalloc(dl + (slash ? 1 : 0) + nl + 1);
    memcpy(r, dir, dl);
    if (slash) r[dl++] = '/';
    memcpy(r + dl, name, nl + 1);
    return r;
}

typedef struct {
    char *name;
    uchar typ;
} ent_t;

static int ent_cmp(const void *a, const void *b) { return strcmp(((const ent_t *)a)->name, ((const ent_t *)b)->name); }

static uint32_t add_item(items_t *its, char *path, size_t nameoff, uint32_t parent, uchar typ) {
    if (its->n == its->cap) {
        its->cap = its->cap ? its->cap * 2 : 1024;
        its->v = fr_xrealloc(its->v, its->cap * sizeof *its->v);
    }
    item_t *it = &its->v[its->n];
    memset(it, 0, sizeof *it);
    it->path = path;
    it->nameoff = (uint32_t)nameoff;
    it->parent = parent;
    it->typ = typ;
    return (uint32_t)its->n++;
}

static void walk_dir(const walkopt_t *o, items_t *its, const char *dir, uint32_t parent, int depth) {
    DIR *d = opendir(dir);
    if (!d) {
        its->unreadable++;
        return;
    }
    its->dirs_scanned++;
    ent_t *es = NULL;
    size_t n = 0, cap = 0;
    struct dirent *de;
    while ((de = readdir(d)) != NULL) {
        const char *nm = de->d_name;
        if (nm[0] == '.' && (nm[1] == 0 || (nm[1] == '.' && nm[2] == 0))) continue;
        if (!o->hidden && nm[0] == '.') continue;
        if (!o->vcs && nm[0] == '.' && (!strcmp(nm, ".git") || !strcmp(nm, ".hg") || !strcmp(nm, ".svn"))) continue;
        if (n == cap) {
            cap = cap ? cap * 2 : 64;
            es = fr_xrealloc(es, cap * sizeof *es);
        }
        es[n].name = fr_xstrdup(nm);
#ifdef DT_UNKNOWN
        switch (de->d_type) {
        case DT_REG: es[n].typ = IT_FILE; break;
        case DT_DIR: es[n].typ = IT_DIR; break;
        case DT_LNK: es[n].typ = IT_LINK; break;
        case DT_UNKNOWN: es[n].typ = 0; break;
        default: es[n].typ = IT_OTHER; break;
        }
#else
        es[n].typ = 0;
#endif
        n++;
    }
    closedir(d);
    qsort(es, n, sizeof *es, ent_cmp);
    size_t dl = strlen(dir);
    size_t base = dl + ((dl > 0 && dir[dl - 1] == '/') ? 0 : 1);
    for (size_t i = 0; i < n; i++) {
        char *path = path_join(dir, es[i].name);
        uchar typ = es[i].typ;
        if (!typ && o->need_type) {
            struct stat st;
            if (lstat(path, &st) != 0) { free(path); free(es[i].name); continue; }
            typ = S_ISREG(st.st_mode) ? IT_FILE : S_ISDIR(st.st_mode) ? IT_DIR : S_ISLNK(st.st_mode) ? IT_LINK : IT_OTHER;
        }
        if (!typ) typ = IT_OTHER;
        uint32_t idx = add_item(its, path, base, parent, typ);
        if (typ == IT_DIR && o->recursive) {
            if (depth + 1 > MAX_WALK_DEPTH) its->unreadable++;
            else walk_dir(o, its, path, idx, depth + 1);
        }
        its->v[idx].subend = (uint32_t)its->n;
        free(es[i].name);
    }
    free(es);
}

void walk_tree(const walkopt_t *o, items_t *its) {
    walk_dir(o, its, o->root, UINT32_MAX, 0);
}
