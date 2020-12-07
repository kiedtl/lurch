LUA      = lua5.3
READLINE = readline
CC       = clang
CFLAGS   = -Og -g -D_POSIX_C_SOURCE=200112L -I/usr/include/lua5.3/
LDFLAGS  = -L/usr/include -lm -l$(READLINE) -l$(LUA)
SRC      = main.c

all: lurch

lurch: $(SRC)
	$(CC) $(SRC) -o $@ $(CFLAGS) $(LDFLAGS)

.PHONY: clean
clean:
	rm -f lurch

