package main

import "strings"

func set(s string) map[string]struct{} {
	m := map[string]struct{}{}
	for _, f := range strings.Fields(s) {
		m[f] = struct{}{}
	}
	return m
}

var archiveMulti = strings.Fields(".tar.gz .tar.bz2 .tar.xz .tar.zst .tar.lz .tar.lzma .tar.lz4 .tar.z .tar.sz .tar.br")

var archiveExt = set(".zip .7z .rar .tar .tgz .tbz .tbz2 .txz .tzst .gz .bz2 .xz .zst .lz .lzma .lz4 .z .zz .br .sz .jar .war .ear .apk .aab .ipa .deb .rpm .pkg .snap .flatpak .dmg .iso .img .wim .cab .arj .lzh .lha .ace .arc .zoo .sit .sitx .sea .cpio .shar .pax .hqx .bin")

var imageExt = set(".jpg .jpeg .png .gif .bmp .tif .tiff .webp .avif .heic .heif .ico .cur .psd .psb .xcf .ppm .pgm .pbm .pnm .pfm .pam .xbm .xpm .tga .dds .exr .hdr .sgi .rgb .rgba .svg .svgz .ai .eps .raw .cr2 .cr3 .nef .nrw .arw .srf .sr2 .orf .rw2 .rwl .pef .ptx .dng .raf .mrw .dcr .kdc .erf .x3f .srw .bay .apng .flif .jxl .jp2 .jpx .j2k .jpf .jpm .mj2")

var pluginExt = set(".crx .xpi .safariextz .vsix .visx .natvis .sublime-package .plugin .bundle .kext .mdimporter .addon .addin .adp .vst .vst3 .au .lv2 .ladspa .dssi .sketchplugin .figma .xdx")

var execExt = set(".sh .bash .zsh .fish .ksh .csh .tcsh .dash .py .pyc .pyo .pyw .rb .pl .pm .lua .tcl .tk .js .mjs .cjs .ts .mts .cts .class .jar .exe .com .out .elf .o .a .lib .bat .cmd .ps1 .psm1 .psd1 .vbs .vbe .wsf .wsh .app .command .run .wasm .beam .elc .rbc .luac")

// icon mirrors the Python icon(): same precedence, same labels.
func icon(name string, isDir bool, mode uint32) string {
	if strings.HasSuffix(name, ".shortcut") {
		return "shortcut"
	}
	if isDir {
		return "dir"
	}
	lo := strings.ToLower(name)
	for _, m := range archiveMulti {
		if strings.HasSuffix(lo, m) {
			return "archive"
		}
	}
	ext := ""
	if i := strings.LastIndexByte(lo, '.'); i >= 0 {
		ext = lo[i:]
	}
	if _, ok := archiveExt[ext]; ok {
		return "archive"
	}
	if _, ok := imageExt[ext]; ok {
		return "image"
	}
	if _, ok := pluginExt[ext]; ok {
		return "plugin"
	}
	if _, ok := execExt[ext]; ok || mode&0o111 != 0 {
		return "exec"
	}
	return "plain"
}
