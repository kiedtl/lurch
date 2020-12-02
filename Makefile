CC      = gcc
CFLAGS  = -Og -ggdb -D_POSIX_C_SOURCE=200112L -I/usr/include/lua5.3/
LDFLAGS = -L/usr/include -llua5.3 -lm
SRC     = main.c

all: lurch

lurch: $(SRC)
	$(CC) $(SRC) -o $@ $(CFLAGS) $(LDFLAGS)

.PHONY: clean
clean:
	rm -f lurch
