# bvk-ls (C). Needs a C11 compiler + pthreads.
#   make              native build -> ./bvk-ls
#   make clean
CC      ?= cc
CFLAGS  ?= -O2
CFLAGS  += -std=c11 -Wall -Wextra -fPIE -Iinclude -D_FILE_OFFSET_BITS=64 -D_DEFAULT_SOURCE
LDFLAGS += -pie
LDLIBS  += -pthread

SRC := $(wildcard src/*.c)
OBJ := $(SRC:src/%.c=build/%.o)

bvk-ls: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LDLIBS)

build/%.o: src/%.c include/bvk.h | build
	$(CC) $(CFLAGS) -c -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf build bvk-ls

.PHONY: clean
