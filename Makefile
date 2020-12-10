NAME     = lurch
TERMBOX  = tb/bin/termbox.a
LUA      = lua5.3
READLINE = readline
CC       = clang
CFLAGS   = -Og -g -D_POSIX_C_SOURCE=200112L -I/usr/include/$(LUA)/
LDFLAGS  = -L/usr/include -lm -l$(READLINE) -l$(LUA)
SRC      = main.c

all: $(NAME)

$(NAME): $(TERMBOX) $(SRC)
	$(CC) $(SRC) -o $@ $(CFLAGS) $(LDFLAGS)

$(TERMBOX):
	make -C tb CC=$(CC)

.PHONY: clean
clean:
	rm -f $(NAME) $(TERMBOX)

