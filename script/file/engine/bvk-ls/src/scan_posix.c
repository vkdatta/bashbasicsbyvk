/* Portable backend (macOS, BSD, ...): plain opendir/readdir. */
#ifndef __linux__
#include "bvk.h"

#include <dirent.h>
#include <errno.h>
#include <string.h>

int scan_dir(const char *dir, const filter_t *f, ents_t *out, arena_t *ar) {
    DIR *d = opendir(dir);
    if (!d) return errno;
    struct dirent *e;
    errno = 0;
    while ((e = readdir(d)) != NULL) {
        const char *nm = e->d_name;
        size_t len = strlen(nm);
        if (len == 0) continue;
        if (nm[0] == '.' && (len == 1 || (len == 2 && nm[1] == '.'))) continue;
        if (!filter_keep(f, nm, len)) continue;
        unsigned char t = 0;
        if (e->d_type == DT_DIR) t = 4;
        else if (e->d_type == DT_LNK) t = 10;
        ents_push(out, (ent_t){.name = arena_strndup(ar, nm, len), .typ = t});
    }
    int rc = errno;
    closedir(d);
    return rc;
}
#endif
