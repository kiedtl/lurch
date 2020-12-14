NAME     = lurch
TERMBOX  = tb/bin/termbox.a
LUA      = lua5.3
CC       = clang
DEF      = -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200112L -D_XOPEN_SOURCE
INCL     = -Itb/src/ -I/usr/include/$(LUA)
CFLAGS   = -Og -g $(DEF) $(INCL)
LDFLAGS  = -L/usr/include -lm -l$(LUA)
SRC      = main.c

all: $(NAME) run

run: $(NAME)
	./$(NAME)

$(NAME): $(TERMBOX) $(SRC)
	$(CC) $(SRC) $(TERMBOX) -o $@ $(CFLAGS) $(LDFLAGS)

$(TERMBOX):
	make -C tb CC=$(CC)

.PHONY: clean
clean:
	rm -f $(NAME) $(TERMBOX)

