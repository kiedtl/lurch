CMD      = @

VERSION  = 0.1.0
NAME     = lurch
SRC      = main.c luau.c luaa.c util.c tool/dwidth.c
OBJ      = $(SRC:.c=.o)

TERMBOX  = tb/bin/termbox.a
LUA      = lua5.3
UTF8PROC = ~/local/lib/libutf8proc.a

WARNING  = -Wall -Wpedantic -Wextra -Wold-style-definition \
	   -Wmissing-prototypes -Winit-self -Wfloat-equal -Wstrict-prototypes \
	   -Wredundant-decls -Wendif-labels -Wstrict-aliasing=2 -Woverflow \
	   -Wformat=2 -Wmissing-include-dirs -Wtrigraphs -Wno-format-nonliteral \
	   -Wincompatible-pointer-types -Wunused-parameter
CC       = clang
DEF      = -D_DEFAULT_SOURCE -D_POSIX_C_SOURCE=200112L -D_XOPEN_SOURCE
INCL     = -Itb/src/ -I/usr/include/$(LUA) -I ~/local/include -Itool/
CFLAGS   = -Og -g $(DEF) $(INCL) $(WARNING)
LDFLAGS  = -L/usr/include -lm -l$(LUA)

all: $(NAME)

run: $(NAME)
	./$(NAME)

.c.o: $(HDR)
	@printf "    %-8s%s\n" "CC" $@
	$(CMD)$(CC) $(CFLAGS) -c $< -o $(<:.c=.o)

$(NAME): $(UTF8PROC) $(TERMBOX) $(OBJ)
	@printf "    %-8s%s\n" "CCLD" $@
	$(CMD)$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJ) $(UTF8PROC) $(TERMBOX)

$(TERMBOX):
	@printf "    %-8s%s\n" "MAKE" $@
	$(CMD)make -C tb CC=$(CC)

tool/dwidth.c: tool/gendwidth
	@printf "    %-8s%s\n" "GEN" $@
	$(CMD)$^ > $@

tool/gendwidth: $(UTF8PROC)
	@printf "    %-8s%s\n" "CCLD" $@
	$(CMD)$(CC) $@.c $(UTF8PROC) -o $@ $(INCL)

.PHONY: clean
clean:
	rm -f $(NAME) $(OBJ) $(TERMBOX)

