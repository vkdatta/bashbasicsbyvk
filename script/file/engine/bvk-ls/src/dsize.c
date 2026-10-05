#include "bvk.h"

#include <dirent.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Recursive size: directories (by d_type, symlinks not followed) are walked,
 * everything else contributes its lstat size. Unreadable dirs count as 0. */
static int64_t walk(const char *d) {
    DIR *dp = opendir(d);
    if (!dp) return 0;
    int64_t total = 0;
    struct dirent *e;
    while ((e = readdir(dp)) != NULL) {
        const char *nm = e->d_name;
        if (nm[0] == '.' && (nm[1] == 0 || (nm[1] == '.' && nm[2] == 0))) continue;

        char *full = path_join(d, nm);
        bool is_dir;
        struct stat st;
        bool have_st = false;
        if (e->d_type == DT_UNKNOWN) {
            if (lstat(full, &st) == 0) {
                have_st = true;
                is_dir = S_ISDIR(st.st_mode);
            } else {
                free(full);
                continue;
            }
        } else {
            is_dir = e->d_type == DT_DIR;
        }

        if (is_dir) {
            total += walk(full);
        } else if (have_st || lstat(full, &st) == 0) {
            total += (int64_t)st.st_size;
        }
        free(full);
    }
    closedir(dp);
    return total;
}

int64_t dir_size(const char *root) { return walk(root); }
