/* Linux backend: raw getdents64 with a 1 MiB buffer. */
#ifdef __linux__
#define _GNU_SOURCE
#include "bvk.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

struct linux_dirent64 {
    uint64_t d_ino;
    int64_t d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[];
};

int scan_dir(const char *dir, const filter_t *f, ents_t *out, arena_t *ar) {
    int fd = open(dir, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return errno;

    const size_t BUFSZ = 1u << 20;
    char *buf = xmalloc(BUFSZ);
    int rc = 0;
    for (;;) {
        long n = syscall(SYS_getdents64, fd, buf, BUFSZ);
        if (n < 0) {
            rc = errno;
            break;
        }
        if (n == 0) break;
        for (long o = 0; o < n;) {
            struct linux_dirent64 *d = (struct linux_dirent64 *)(buf + o);
            o += d->d_reclen;
            const char *nm = d->d_name;
            size_t len = strnlen(nm, d->d_reclen - offsetof(struct linux_dirent64, d_name));
            if (d->d_ino == 0 || len == 0) continue;
            if (nm[0] == '.' && (len == 1 || (len == 2 && nm[1] == '.'))) continue;
            if (!filter_keep(f, nm, len)) continue;
            ents_push(out, (ent_t){.name = arena_strndup(ar, nm, len), .typ = d->d_type});
        }
    }
    free(buf);
    close(fd);
    return rc;
}
#endif /* __linux__ */
