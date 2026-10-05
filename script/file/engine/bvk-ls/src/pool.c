#include "bvk.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>

typedef struct {
    size_t n, chunk;
    atomic_size_t next;
    pool_fn fn;
    void *ctx;
} job_t;

static void *worker(void *p) {
    job_t *j = p;
    for (;;) {
        size_t s = atomic_fetch_add(&j->next, j->chunk);
        if (s >= j->n) break;
        size_t e = s + j->chunk;
        if (e > j->n) e = j->n;
        for (size_t i = s; i < e; i++) j->fn(i, j->ctx);
    }
    return NULL;
}

int pool_ncpu(void) {
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n < 1 ? 1 : (int)n;
}

void pool_run(size_t n, int workers, size_t chunk, pool_fn fn, void *ctx) {
    if (n == 0) return;
    if (chunk == 0) chunk = 1;
    if (workers < 1) workers = 1;
    if ((size_t)workers > n) workers = (int)n;

    job_t j = {.n = n, .chunk = chunk, .fn = fn, .ctx = ctx};
    atomic_init(&j.next, 0);

    pthread_t *th = xmalloc((size_t)workers * sizeof *th);
    int started = 0;
    for (int i = 1; i < workers; i++) {
        if (pthread_create(&th[started], NULL, worker, &j) == 0) started++;
        /* on failure the remaining threads' work is simply taken by others */
    }
    worker(&j); /* caller is a worker too */
    for (int i = 0; i < started; i++) pthread_join(th[i], NULL);
    free(th);
}
