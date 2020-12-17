#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <netdb.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <tls.h>
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
extern _Bool tb_active;
extern struct tls *client;
extern _Bool tls_active;

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
	{ "utf8_dwidth",   api_utf8_dwidth    },
	{ NULL, NULL },
};

int
api_conn_init(lua_State *pL)
{
	char *host = (char *) luaL_checkstring(pL, 1);
	char *port = (char *) luaL_checkstring(pL, 2);
	_Bool  tls = lua_toboolean(pL, 3);

	struct addrinfo hints = {
		.ai_protocol = IPPROTO_TCP,
		.ai_socktype = SOCK_STREAM,
		.ai_family = AF_UNSPEC,
	};
	struct addrinfo *res, *r;

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

	tls_active = tls;
	if (tls_active) {
		struct tls_config *tlscfg = tls_config_new();
		if (!tlscfg) LLUA_ERR(pL, format("tls_config_new() == NULL"));
		if (tls_config_set_ciphers(tlscfg, "compat") != 0)
			LLUA_ERR(pL, format("error when configuring tls: %s", tls_config_error(tlscfg)));
		client = tls_client();
		if (!client) LLUA_ERR(pL, format("tls_client() == NULL"));
		if (tls_configure(client, tlscfg) != 0)
			LLUA_ERR(pL, format("error when configuring tls: %s", tls_error(client)));
		tls_config_free(tlscfg);
	}

	if (r == NULL)
		LLUA_ERR(pL, format("cannot connect: %s", strerror(errno)));

	if (tls_active) {
		if (tls_connect_socket(client, conn_fd, host) != 0)
			LLUA_ERR(pL, format("tls: cannot connect: %s", tls_error(client)));
		if (tls_handshake(client) != 0)
			LLUA_ERR(pL, format("tls: cannot perform handshake: %s", tls_error(client)));
	} else {
		if (((conn = fdopen(conn_fd, "r+")) == NULL))
			LLUA_ERR(pL, format("cannot connect: %s", strerror(errno)));
	}

	lua_pushboolean(L, true);
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

	size_t len = strlen(fmtd);

	while (len) {
		ssize_t r = -1;

		if (tls_active)
			r = tls_write(client, fmtd, len);
		else
			r = send(conn_fd, fmtd, len, 0);

		if (tls_active && (r == TLS_WANT_POLLIN || r == TLS_WANT_POLLOUT))
			continue;
		if (r < 0) LLUA_ERR(pL, NETWRK_ERR());

		data += r; len -= r;
	}

	lua_pushboolean(L, true);
	return 1;
}

int
api_tb_size(lua_State *pL)
{
	assert(tb_active);
	lua_pushinteger(pL, (lua_Integer) tb_height());
	lua_pushinteger(pL, (lua_Integer) tb_width());

	return 2;
}

int
api_tb_clear(lua_State *pL)
{
	UNUSED(pL);
	assert(tb_active);

	tb_clear();
	return 0;
}

const size_t attribs[] = { TB_BOLD, TB_UNDERLINE, TB_REVERSE };
static inline void
set_color(uint32_t *old, uint32_t *new, char *color)
{
	uint32_t col = strtol(color, NULL, 10);

	*old = *new, *new = col;
	if (col < sizeof(mirc_colors))
		*new = mirc_colors[col];

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
	assert(tb_active);
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
		break; case MIRC_BOLD:      ++string; c.fg ^= TB_BOLD;
		break; case MIRC_UNDERLINE: ++string; c.fg ^= TB_UNDERLINE;
		break; case MIRC_INVERT:    ++string; c.fg ^= TB_REVERSE;
		break; case MIRC_RESET:     ++string; c.fg = 15, c.bg = 0;
		break; case MIRC_ITALIC:    ++string; break;
		break; case MIRC_BLINK:     ++string; break;
		break; case MIRC_COLOR:
			++string;
			colorbuf[0] = colorbuf[1] = colorbuf[2] = '\0';

			/* if no digits after MIRC_COLOR, reset */
			if (!isdigit(*string)) {
				c.fg = 15, c.bg = 0;
				break;
			}

			colorbuf[0] = *string;
			if (isdigit(string[1])) colorbuf[1] = *(++string);
			set_color(&oldfg, &c.fg, (char *) &colorbuf);

			++string;

			/* bg color may or may not be present */
			if (*string != ',' || !isdigit(string[1]))
				break;

			colorbuf[0] = *(++string);
			if (isdigit(string[1])) colorbuf[1] = *(++string);
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
				col += 1;
			}
		}
	}

	oldfg = c.fg, oldbg = c.bg;
	return 0;
}

int
api_tb_setcursor(lua_State *pL)
{
	assert(tb_active);
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

/* get the display width of a string. */
int
api_utf8_dwidth(lua_State *pL)
{
	const unsigned char *str =
		(const unsigned char *) luaL_checkstring(pL, 1);

	ssize_t chsz = -1;
	utf8proc_int32_t chbuf = 0;
	size_t chwidth = 0, accm = 0;

	while (*str && (chsz = utf8proc_iterate(str, -1, &chbuf))) {
		if (chsz < 0) LLUA_ERR(pL, "invalid UTF8 string.")

		str += chsz;

		chwidth = 0;
		if ((size_t) chbuf < sizeof(dwidth))
			chwidth = dwidth[chbuf];
		accm += chwidth;
	}

	lua_pushinteger(pL, (lua_Integer) accm);
	return 1;
}
