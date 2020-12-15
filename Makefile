NAME     = lurch
TERMBOX  = tb/bin/termbox.a
LUA      = lua5.3
UTF8PROC = ~/local/lib/libutf8proc.a
CC       = clang
DEF      = -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200112L -D_XOPEN_SOURCE
INCL     = -Itb/src/ -I/usr/include/$(LUA) -I ~/local/include -Itool/
CFLAGS   = -Og -g $(DEF) $(INCL)
LDFLAGS  = -L/usr/include -lm -l$(LUA)
SRC      = main.c $(UTF8PROC) $(TERMBOX)

all: $(NAME) run

run: $(NAME)
	./$(NAME)

$(NAME): $(SRC) tool/dwidth.h
	$(CC) $(SRC) -o $@ $(CFLAGS) $(LDFLAGS)

$(TERMBOX):
	make -C tb CC=$(CC)

tool/dwidth.h: tool/gendwidth
	$^ > $@

tool/gendwidth: $(UTF8PROC)
	$(CC) $@.c $(UTF8PROC) -o $@ $(INCL)

.PHONY: clean
clean:
	rm -f $(NAME) $(TERMBOX)

