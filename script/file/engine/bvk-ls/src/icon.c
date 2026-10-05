#include "bvk.h"

#include <stdlib.h>
#include <string.h>

static const char *const archive_multi[] = {
    ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lz",
    ".tar.lzma", ".tar.lz4", ".tar.z", ".tar.sz", ".tar.br", NULL};

static const char *const archive_ext[] = {
    ".zip", ".7z", ".rar", ".tar", ".tgz", ".tbz", ".tbz2", ".txz", ".tzst", ".gz", ".bz2",
    ".xz", ".zst", ".lz", ".lzma", ".lz4", ".z", ".zz", ".br", ".sz", ".jar", ".war", ".ear",
    ".apk", ".aab", ".ipa", ".deb", ".rpm", ".pkg", ".snap", ".flatpak", ".dmg", ".iso",
    ".img", ".wim", ".cab", ".arj", ".lzh", ".lha", ".ace", ".arc", ".zoo", ".sit", ".sitx",
    ".sea", ".cpio", ".shar", ".pax", ".hqx", ".bin", NULL};

static const char *const image_ext[] = {
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".webp", ".avif", ".heic",
    ".heif", ".ico", ".cur", ".psd", ".psb", ".xcf", ".ppm", ".pgm", ".pbm", ".pnm", ".pfm",
    ".pam", ".xbm", ".xpm", ".tga", ".dds", ".exr", ".hdr", ".sgi", ".rgb", ".rgba", ".svg",
    ".svgz", ".ai", ".eps", ".raw", ".cr2", ".cr3", ".nef", ".nrw", ".arw", ".srf", ".sr2",
    ".orf", ".rw2", ".rwl", ".pef", ".ptx", ".dng", ".raf", ".mrw", ".dcr", ".kdc", ".erf",
    ".x3f", ".srw", ".bay", ".apng", ".flif", ".jxl", ".jp2", ".jpx", ".j2k", ".jpf", ".jpm",
    ".mj2", NULL};

static const char *const plugin_ext[] = {
    ".crx", ".xpi", ".safariextz", ".vsix", ".visx", ".natvis", ".sublime-package", ".plugin",
    ".bundle", ".kext", ".mdimporter", ".addon", ".addin", ".adp", ".vst", ".vst3", ".au",
    ".lv2", ".ladspa", ".dssi", ".sketchplugin", ".figma", ".xdx", NULL};

static const char *const exec_ext[] = {
    ".sh", ".bash", ".zsh", ".fish", ".ksh", ".csh", ".tcsh", ".dash", ".py", ".pyc", ".pyo",
    ".pyw", ".rb", ".pl", ".pm", ".lua", ".tcl", ".tk", ".js", ".mjs", ".cjs", ".ts", ".mts",
    ".cts", ".class", ".jar", ".exe", ".com", ".out", ".elf", ".o", ".a", ".lib", ".bat",
    ".cmd", ".ps1", ".psm1", ".psd1", ".vbs", ".vbe", ".wsf", ".wsh", ".app", ".command",
    ".run", ".wasm", ".beam", ".elc", ".rbc", ".luac", NULL};

static bool in_set(const char *const *set, const char *s, size_t len) {
    for (; *set; set++)
        if (strlen(*set) == len && memcmp(*set, s, len) == 0) return true;
    return false;
}

static bool ends_with(const char *s, size_t len, const char *suf) {
    size_t sl = strlen(suf);
    return len >= sl && memcmp(s + len - sl, suf, sl) == 0;
}

/* Same precedence and labels as the original Python icon(). */
const char *icon_for(const char *name, size_t len, bool is_dir, uint32_t mode) {
    if (ends_with(name, len, ".shortcut")) return "shortcut";
    if (is_dir) return "dir";

    char stack[256];
    char *lo = len < sizeof stack ? stack : xmalloc(len + 1);
    for (size_t i = 0; i < len; i++) {
        char c = name[i];
        lo[i] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
    }
    lo[len] = 0;

    const char *res = "plain";
    bool done = false;
    for (const char *const *m = archive_multi; *m && !done; m++)
        if (ends_with(lo, len, *m)) {
            res = "archive";
            done = true;
        }
    if (!done) {
        const char *ext = "";
        size_t el = 0;
        for (size_t i = len; i > 0; i--)
            if (lo[i - 1] == '.') {
                ext = lo + i - 1;
                el = len - (i - 1);
                break;
            }
        if (in_set(archive_ext, ext, el)) res = "archive";
        else if (in_set(image_ext, ext, el)) res = "image";
        else if (in_set(plugin_ext, ext, el)) res = "plugin";
        else if (in_set(exec_ext, ext, el) || (mode & 0111)) res = "exec";
    }
    if (lo != stack) free(lo);
    return res;
}
