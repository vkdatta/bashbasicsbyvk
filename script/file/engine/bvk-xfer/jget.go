package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
)

// jget [-o] FIELD   (JSON on stdin)
//
//	default: strings as they are, numbers/bools as text, null → "null", missing → ""   (what _bb_json_get printed)
//	-o:      strings as they are, objects/arrays as compact JSON, null/missing → ""      (what _pn_jf printed)
func cmdJget(args []string) int {
	objMode := false
	if len(args) > 0 && args[0] == "-o" {
		objMode = true
		args = args[1:]
	}
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: bvk-xfer jget [-o] FIELD")
		return 2
	}
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		return 0
	}
	var m map[string]json.RawMessage
	if json.Unmarshal(bytes.TrimSpace(data), &m) != nil {
		return 0 // not an object: print nothing, like the node helper did on a parse error
	}
	raw, ok := m[args[0]]
	if !ok {
		return 0
	}
	t := bytes.TrimSpace(raw)
	switch {
	case len(t) == 0:
	case t[0] == '"':
		var s string
		if json.Unmarshal(t, &s) == nil {
			fmt.Print(s)
		}
	case string(t) == "null":
		if !objMode {
			fmt.Print("null")
		}
	case t[0] == '{' || t[0] == '[':
		var buf bytes.Buffer
		if json.Compact(&buf, t) == nil {
			fmt.Print(buf.String())
		}
	default:
		fmt.Print(string(t))
	}
	return 0
}
