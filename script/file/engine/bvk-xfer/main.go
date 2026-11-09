// bvk-xfer: the transfer engine of bashbasicsbyvk.  One static binary, no dependencies, no node.
//
//	bvk-xfer selftest                      → prints "bvk-xfer ok" (used to decide whether this binary may be used)
//	bvk-xfer jget [-o] FIELD < json        → one JSON field on stdout (replaces a `node -e` per field)
//	bvk-xfer pack --out DIR --name N ...   → NUL-separated paths on stdin → tar → gzip → AES-256-GCM chunks in DIR
//	bvk-xfer send --dir DIR --url URL ...  → send DIR to the fileapi in the fewest possible round trips
//	bvk-xfer xfer upload|ux URL ID DIR     → the resilient blob transfer (resume, pause, offline wait) — replaces the node script
//	bvk-xfer fetch LINK OUTFILE [CONC]     → download + decrypt a link in parallel (replaces the node one-liner of do- / restore)
//	bvk-xfer untar ARCHIVE STAGE           → safe one-pass tar.gz extraction (replaces three tar passes)
//	bvk-xfer netcheck URL                  → DNS · CA roots · TLS · HTTP, stage by stage (used by `health`)
package main

import (
	"fmt"
	"os"
)

const version = "1"

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: bvk-xfer selftest|jget|pack|send")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "selftest":
		fmt.Println("bvk-xfer ok")
	case "version":
		fmt.Println(version)
	case "jget":
		os.Exit(cmdJget(os.Args[2:]))
	case "pack":
		os.Exit(cmdPack(os.Args[2:]))
	case "send":
		os.Exit(cmdSend(os.Args[2:]))
	case "fetch":
		os.Exit(cmdFetch(os.Args[2:]))
	case "untar":
		os.Exit(cmdUntar(os.Args[2:]))
	case "xfer":
		os.Exit(cmdXfer(os.Args[2:]))
	case "netcheck":
		os.Exit(cmdNetcheck(os.Args[2:]))
	default:
		fmt.Fprintf(os.Stderr, "bvk-xfer: unknown command %q\n", os.Args[1])
		os.Exit(2)
	}
}
