#include <assert.h>
#include <errno.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "dwidth.h"
#include "luaa.h"
#include "luau.h"
#include "mirc.h"
#include "termbox.h"
#include "util.h"
#include "utf8proc.h"

extern FILE *conn;
extern int conn_fd;
extern lua_State *L;
extern size_t TB_ACTIVE;
extern size_t TB_INACTIVE;
extern size_t tb_state;

const struct luaL_Reg lurch_lib[] = {
	{ "conn_init",     api_conn_init      },
	{ "cleanup",       api_cleanup        },
	{ "conn_send",     api_conn_send      },
	{ "tb_size",       api_tb_size        },
	{ "tb_clear",      api_tb_clear       },
	{ "tb_writeline",  api_tb_writeline   },
	{ "tb_setcursor",  api_tb_setcursor   },
	{ "mkdirp",        api_mkdir_p        },
	{ "utf8_insert",   api_utf8_insert    },
	{ NULL, NULL },
};

int
api_conn_init(lua_State *pL)
{
	char *host = (char *) luaL_checkstring(pL, 1);
	char *port = (char *) luaL_checkstring(pL, 2);

	struct addrinfo hints;
	struct addrinfo *res, *r;

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;

	if(getaddrinfo(host, port, &hints, &res) != 0) {
		LLUA_ERR(pL, format("cannot resolve hostname: %s", strerror(errno)));
	}

	for(r = res; r != NULL; r = r->ai_next) {
		if((conn_fd = socket(r->ai_family, r->ai_socktype, r->ai_protocol)) == -1)
			continue;
		if(connect(conn_fd, r->ai_addr, r->ai_addrlen) == 0)
			break;
		close(conn_fd);
	}

	freeaddrinfo(res);

	if (r == NULL || ((conn = fdopen(conn_fd, "r+")) == NULL)) {
		LLUA_ERR(pL, format("cannot connect to host: %s", strerror(errno)));
	}

	// push some random integer to provide a distinction between calls to this
	// function that return nil because they failed or because there was nothing
	// to return
	lua_pushinteger(L, (lua_Integer) 1);
	return 1;
}

int
api_cleanup(lua_State *pL)
{
	UNUSED(pL);
	cleanup();
	return 0;
}

int
api_conn_send(lua_State *pL)
{
	// TODO: check if connection is still open
	char *data = (char *) luaL_checkstring(pL, 1);
	char *fmtd = format("%s\r\n", data);

	ssize_t sent = send(conn_fd, fmtd, strlen(fmtd), 0);

	if (sent == -1) {
		LLUA_ERR(pL, format("cannot send: %s", strerror(errno)));
	} else if ((size_t) sent < (strlen(data) + 2)) {
		LLUA_ERR(pL, format("sent != len(data): %s", strerror(errno)));
	}

	return 0;
}

int
api_tb_size(lua_State *pL)
{
	assert(tb_state == TB_ACTIVE);
	lua_pushinteger(pL, (lua_Integer) tb_height());
	lua_pushinteger(pL, (lua_Integer) tb_width());

	return 2;
}

int
api_tb_clear(lua_State *pL)
{
	UNUSED(pL);
	assert(tb_state == TB_ACTIVE);

	tb_clear();
	return 0;
}


static inline void
toggle_attr(uint32_t *color, uint32_t attr)
{
	if ((*color & attr) == attr)
		*color &= 0xFF;
	else
		*color |= attr;
}

const size_t attribs[] = { TB_BOLD, TB_UNDERLINE, TB_REVERSE };
static inline void
set_color(uint32_t *old, uint32_t *new, char *color)
{
	uint32_t col = strtol(color, NULL, 10);

	*old = *new;
	if (col < sizeof(mirc_colors))
		*new = mirc_colors[col];
	else
		*new = col;

	for (size_t i = 0; i < sizeof(attribs); ++i)
		if ((*old & attribs[i]) == attribs[i])
			*new |= attribs[i];
}

/* last colors used.  This is used to cache and re-apply
 * attributes (e.g. bold) when changing colors,  as well
 * as to store the last colors used,  so that attributes
 * or colors that weren't reset when the line ended will
 * will carry over to the next lines as expected. */
static uint32_t oldfg = 0, oldbg = 0;

int
api_tb_writeline(lua_State *pL)
{
	assert(tb_state == TB_ACTIVE);
	int line = luaL_checkinteger(pL, 1);
	char *string = (char *) luaL_checkstring(pL, 2);

	int col   = 0;
	int width = tb_width();
	struct tb_cell c = { '\0', 0, 0 };

	char colorbuf[4];
	colorbuf[3] = '\0';
	size_t chwidth;
	int32_t charbuf = 0;
	ssize_t runelen = 0;

	do tb_put_cell(col, line, &c); while (++col < width);
	col = 0;

	/* restore colors of previous line. */
	c.fg = oldfg, c.bg = oldbg;

	while (*string) {
		switch (*string) {
		break; case MIRC_RESET:
			++string;
			c.fg = 15, c.bg = 0;
		break; case MIRC_BOLD:
			++string;
			toggle_attr(&c.fg, TB_BOLD);
		break; case MIRC_UNDERLINE:
			++string;
			toggle_attr(&c.fg, TB_UNDERLINE);
		break; case MIRC_INVERT:
			++string;
			toggle_attr(&c.fg, TB_REVERSE);
		break; case MIRC_ITALIC:
		break; case MIRC_BLINK:
			++string;
			break;
		break; case MIRC_COLOR:
			++string;
			colorbuf[0] = colorbuf[1] = colorbuf[2] = '\0';

			if (*string > '9' || *string < '0') {
				c.fg = 15, c.bg = 0;
				break;
			}

			colorbuf[0] = *string;
			if (IS_STRINT(string[1])) colorbuf[1] = *(++string);
			set_color(&oldfg, &c.fg, (char *) &colorbuf);

			++string;
			if (*string != ',' || !IS_STRINT(string[1]))
				break;

			colorbuf[0] = *(++string);
			if (IS_STRINT(string[1])) colorbuf[1] = *(++string);
			set_color(&oldbg, &c.bg, (char *) &colorbuf);

			string += 2;
		break; case MIRC_256COLOR:
			++string;
			colorbuf[0] = colorbuf[1] = colorbuf[2] = '\0';
			strncpy((char *) &colorbuf, string, 3);
			set_color(&oldfg, &c.fg, (char *) &colorbuf);
			string += 3;
		break; default:
			charbuf = 0;
			runelen = utf8proc_iterate((const unsigned char *) string,
				-1, (utf8proc_int32_t *) &charbuf);
	
			if (runelen < 0) {
				/* invalid UTF8 codepoint, let's just
				 * move forward and hope for the best */
				++string;
				continue;
			}
	
			assert(charbuf >= 0);
			c.ch = (uint32_t) charbuf;
			string += runelen;
	
			chwidth = 0;
			if (c.ch < sizeof(dwidth)) chwidth = dwidth[c.ch];
	
			if (chwidth > 0) {
				tb_put_cell(col, line, &c);
				col += chwidth;
			}
		}
	}

	oldfg = c.fg, oldbg = c.bg;

	return 0;
}

int
api_tb_setcursor(lua_State *pL)
{
	assert(tb_state == TB_ACTIVE);
	int x = luaL_checkinteger(pL, 1);
	int y = luaL_checkinteger(pL, 2);
	tb_set_cursor(x, y);
	return 0;
}

/* impl of mkdir -p */
int
api_mkdir_p(lua_State *pL)
{
	char *path   = (char *) luaL_checkstring(pL, 1);

	mode_t mask  = umask(0);
	mode_t pmode = 0777 & (~mask | 0300);
	mode_t mode  = 0777 & ~mask;

	char tmp[4096], *p;
	struct stat st;
	size_t created = 0;

	if (stat(path, &st) == 0) {
		if (S_ISDIR(st.st_mode))
			return 0; /* path exists */
		LLUA_ERR(pL, "Path exists and is not directory");
	}

	strncpy((char *) &tmp, path, sizeof(tmp));
	for (p = tmp + (tmp[0] == '/'); *p; ++p) {
		if (*p != '/')
			continue;

		*p = '\0';
		if (mkdir(tmp, pmode) < 0 && errno != EEXIST) {
			LLUA_ERR(pL, strerror(errno));
		}

		*p = '/';
		++created;
	}

	if (mkdir(tmp, mode) < 0 && errno != EEXIST) {
		LLUA_ERR(pL, strerror(errno));
	}

	lua_pushinteger(pL, (lua_Integer) ++created);
	return 1;
}

/* insert some text after <x> utf8 characters */
int
api_utf8_insert(lua_State *pL)
{
	char *str = (char *) luaL_checkstring(pL, 1);
	size_t loc = (size_t) luaL_checkinteger(pL, 2);
	char *txt = (char *) luaL_checkstring(pL, 3);

	size_t i = 0, len = strlen(str) + strlen(txt);
	char buf[len + 1];
	memset((void *) buf, 0x0, len);

	for (i = 0; i < loc; i += utf8_char_length(str[i]));

	strncpy((char *) buf, str, i);
	strcat((char *)  buf, txt);
	strncat((char *) buf, str + i, strlen(str) - i);

	lua_pushstring(pL, (char *) buf);
	return 1;
}
