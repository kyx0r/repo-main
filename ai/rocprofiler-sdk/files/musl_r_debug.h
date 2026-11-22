/* musl does not export _r_debug; locate it via DT_DEBUG of the main program. */
#ifndef MUSL_R_DEBUG_H
#define MUSL_R_DEBUG_H
#include <link.h>
#include <elf.h>
static int musl_rdbg_cb(struct dl_phdr_info *i, size_t s, void *out)
{
    (void)s;
    for (int k = 0; k < i->dlpi_phnum; k++) {
        if (i->dlpi_phdr[k].p_type != PT_DYNAMIC) continue;
        ElfW(Dyn) *d = (ElfW(Dyn) *)(i->dlpi_addr + i->dlpi_phdr[k].p_vaddr);
        for (; d->d_tag != DT_NULL; d++)
            if (d->d_tag == DT_DEBUG && d->d_un.d_ptr) {
                *(struct r_debug **)out = (struct r_debug *)d->d_un.d_ptr;
                return 1;
            }
    }
    return 0;
}
static inline struct r_debug *musl_r_debug(void)
{
    static struct r_debug *r;
    if (!r) dl_iterate_phdr(musl_rdbg_cb, &r);
    return r;
}
#define _r_debug (*musl_r_debug())
#endif
