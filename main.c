/* See LICENSE file for license details. */

#include <assert.h>
#include <errno.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <netdb.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

// TODO: signals

int conn_fd = 0;
lua_State *L;

int api_tty_size(lua_State *pL);
int api_conn_init(lua_State *pL);
int api_conn_fd(lua_State *pL);
int api_conn_send(lua_State *pL);
int api_conn_receive(lua_State *pL);

#define ADD_CFUNC(FUNC, NAME) do { \
		lua_pushcfunction(L, FUNC); \
		lua_setglobal(L, NAME); \
	} while (0);

int
main(int argc, char **argv)
{
	L = luaL_newstate();
	luaL_openlibs(L);
	luaopen_table(L);
	luaopen_io(L);
	luaopen_string(L);
	luaopen_math(L);

	ADD_CFUNC(api_tty_size, "__lurch_tty_size");
	ADD_CFUNC(api_conn_init, "__lurch_conn_init");
	ADD_CFUNC(api_conn_fd, "__lurch_conn_fd");
	ADD_CFUNC(api_conn_send, "__lurch_conn_send");
	ADD_CFUNC(api_conn_receive, "__lurch_conn_receive");

	(void) luaL_dostring(L,
		"xpcall(function()\n"
		"  core = require('core')\n"
		"  core.main()\n"
		"end, function(err)\n"
		"  if core then core.on_error(err) end\n"
		"  print(debug.traceback(err, 6))\n"
		"  os.exit(1)\n"
		"end)\n"
	);

	lua_close(L);
	return 0;
}

// utility functions
char *
format(const char *format, ...)
{
	static char buf[4096];
	va_list ap;
	va_start(ap, format);
	int len = vsnprintf(buf, sizeof(buf), format, ap);
	va_end(ap);
	assert((size_t) len < sizeof(buf));
	return (char *) &buf;
}

// API functions

int
api_tty_size(lua_State *pL)
{
	struct winsize w;
	ioctl(STDIN_FILENO, TIOCGWINSZ, &w);

	lua_pushinteger(pL, (lua_Integer) w.ws_row);
	lua_pushinteger(pL, (lua_Integer) w.ws_col);

	return 2;
}


int
api_conn_init(lua_State *pL)
{
	char *host = (char *) luaL_checkstring(pL, 1);
	char *port = (char *) luaL_checkstring(pL, 2);

	static struct addrinfo hints;
	struct addrinfo *res, *r;

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;

	if(getaddrinfo(host, port, &hints, &res) != 0) {
		lua_pushnil(pL);
		lua_pushstring(pL, format("cannot resolve hostname: %s", strerror(errno)));
		return 2;
	}

	for(r = res; r != NULL; r = r->ai_next) {
		if((conn_fd = socket(r->ai_family, r->ai_socktype, r->ai_protocol)) == -1)
			continue;
		if(connect(conn_fd, r->ai_addr, r->ai_addrlen) == 0)
			break;
		close(conn_fd);
	}

	freeaddrinfo(res);

	if (r == NULL) {
		lua_pushnil(pL);
		lua_pushstring(pL, format("cannot connect to host: %s", strerror(errno)));
		return 2;
	}

	// push some random integer to provide a distinction between calls to this
	// function that return nil because they failed or because there was nothing
	// to return
	lua_pushinteger(L, (lua_Integer) 1);
	return 1;
}

int
api_conn_fd(lua_State *pL)
{
	lua_pushinteger(pL, (lua_Integer) conn_fd);
	return 1;
}

int
api_conn_send(lua_State *pL)
{
	// TODO: check if connection is still open
	char *data = (char *) luaL_checkstring(pL, 1);
	char *fmtd = format("%s\r\n", data);

	ssize_t sent = send(conn_fd, fmtd, strlen(fmtd), 0);
	assert(sent == (strlen(data) + 2));

	return 0;
}

int
api_conn_receive(lua_State *pL)
{
	int len = 0;
	ioctl(conn_fd, FIONREAD, &len);
	char *bufin = malloc(len + 1);
	assert(bufin);

	int received = read(conn_fd, (void *) bufin, len);
	assert(received == len);

	lua_pushstring(pL, (const char *) bufin);
	free(bufin);

	return 1;
}
