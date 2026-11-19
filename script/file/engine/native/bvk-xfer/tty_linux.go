//go:build linux

package main

import (
	"syscall"
	"unsafe"
)

func isTTY(fd int) bool {
	var t syscall.Termios
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&t)))
	return e == 0
}

// makeRaw puts the terminal on stdin into raw mode (keys arrive one by one, Ctrl-C arrives as a key) and returns the function that undoes it.
func makeRaw() (func(), bool) {
	var old syscall.Termios
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, 0, uintptr(syscall.TCGETS), uintptr(unsafe.Pointer(&old))); e != 0 {
		return nil, false
	}
	n := old
	n.Lflag &^= syscall.ICANON | syscall.ECHO | syscall.ISIG
	n.Cc[syscall.VMIN] = 1
	n.Cc[syscall.VTIME] = 0
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, 0, uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&n))); e != 0 {
		return nil, false
	}
	return func() {
		syscall.Syscall(syscall.SYS_IOCTL, 0, uintptr(syscall.TCSETS), uintptr(unsafe.Pointer(&old)))
	}, true
}

func termCols() int {
	var ws struct{ Row, Col, X, Y uint16 }
	for _, fd := range []uintptr{2, 1} {
		if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, fd, uintptr(syscall.TIOCGWINSZ), uintptr(unsafe.Pointer(&ws))); e == 0 && ws.Col > 0 {
			return int(ws.Col)
		}
	}
	return 60
}
