/* See LICENSE file for license details. */

#include <assert.h>
#include <errno.h>
#include <execinfo.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <netdb.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

const size_t BT_BUF_SIZE = 16;

int conn_fd = 0;
lua_State *L;

void signal_lhand(int sig);
void signal_fatal(int sig);

void die(const char *fmt, ...);
char *format(const char *format, ...);

int  llua_panic(lua_State *pL);
void llua_sdump(lua_State *pL);

int api_tty_size(lua_State *pL);
int api_conn_init(lua_State *pL);
int api_conn_fd(lua_State *pL);
int api_conn_send(lua_State *pL);
int api_conn_receive(lua_State *pL);

int
main(int argc, char **argv)
{
	/* register signal handlers */
	/* signals to whine and die on */
	struct sigaction fatal;
	fatal.sa_handler = &signal_fatal;
	sigaction(SIGILL,   &fatal, NULL);
	sigaction(SIGSEGV,  &fatal, NULL);
	sigaction(SIGFPE,   &fatal, NULL);
	sigaction(SIGBUS,   &fatal, NULL);

	/* signals to catch and handle in lua code */
	/* TODO: is handling SIGTERM a good idea? */
	struct sigaction lhand;
	lhand.sa_handler = &signal_lhand;
	sigaction(SIGHUP,   &lhand, NULL);
	sigaction(SIGINT,   &lhand, NULL);
	sigaction(SIGPIPE,  &lhand, NULL);
	sigaction(SIGUSR1,  &lhand, NULL);
	sigaction(SIGUSR2,  &lhand, NULL);
	sigaction(SIGWINCH, &lhand, NULL);

	/* init lua */
	L = luaL_newstate();
	luaL_openlibs(L);
	luaopen_table(L);
	luaopen_io(L);
	luaopen_string(L);
	luaopen_math(L);

	/* set panic function */
	lua_atpanic(L, llua_panic);

	/* get executable path */
	char buf[4096];
	char path[128];
	sprintf((char *) &path, "/proc/%d/exe", getpid());
	int len = readlink((char *) &path, (char *) &buf, sizeof(buf));
	buf[len] = '\0';

	/* trim off the filename */
	for (size_t i = strlen(buf) - 1; i > 0; --i) {
		if (buf[i] == '/' || buf [i] == '\\') {
			buf[i] = '\0';
			break;
		}
	}

	lua_pushstring(L, (char *) &buf);
	lua_setglobal(L, "__LURCH_EXEDIR");

	/* TODO: do this the non-lazy way */
	(void) luaL_dostring(L,
		"package.path = __LURCH_EXEDIR .. '/rt/?.lua;' .. package.path\n"
	);

	/* setup lurch api functions */
	static const struct luaL_Reg lurch_lib[] = {
		{ "tty_size", api_tty_size },
		{ "conn_init", api_conn_init },
		{ "conn_fd", api_conn_fd },
		{ "conn_send", api_conn_send },
		{ "conn_receive", api_conn_receive },
		{ NULL, NULL },
	};

	lua_newtable(L);
	luaL_setfuncs(L, (luaL_Reg *) &lurch_lib, 0);
	lua_pushvalue(L, -1);
	lua_setglobal(L, "lurch");

	(void) luaL_dostring(L,
		"xpcall(function()\n"
		"  rt = require('rt')\n"
		"  rt.main()\n"
		"end, function(err)\n"
		"  if rt then rt.on_lerror(err) end\n"
		"  print(debug.traceback(err, 6))\n"
		"  os.exit(1)\n"
		"end)\n"
	);

	lua_close(L);
	return 0;
}

// utility functions

void
signal_lhand(int sig)
{
	char *l = format(
		"xpcall(function()\n"
		"  rt = require('rt')\n"
		"  rt.on_signal(%d)\n"
		"end, function(err)\n"
		"  if rt then rt.on_lerror(err) end\n"
		"  print(debug.traceback(err, 6))\n"
		"  os.exit(1)\n"
		"end)\n",
	sig);
	(void) luaL_dostring(L, l);
}

void
signal_fatal(int sig)
{
	die("received signal %d; aborting.", sig);
}

void
die(const char *fmt, ...)
{
	fprintf(stderr, "fatal: ");

	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);

	if (fmt[0] && fmt[strlen(fmt) - 1] == ':') {
		perror(" ");
	} else {
		fputc('\n', stderr);
	}

	int nptrs;
	void *buffer[BT_BUF_SIZE];
	char **strings;

	nptrs = backtrace(buffer, BT_BUF_SIZE);
	strings = backtrace_symbols(buffer, nptrs);
	assert(strings);

	fprintf(stderr, "backtrace:\n");
	for (size_t i = 0; i < nptrs; ++i)
		fprintf(stderr, "   %s\n", strings[i]);
	free(strings);

	exit(1);
}

char *
format(const char *fmt, ...)
{
	static char buf[4096];
	va_list ap;
	va_start(ap, fmt);
	int len = vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	assert((size_t) len < sizeof(buf));
	return (char *) &buf;
}

int
llua_panic(lua_State *pL)
{
	(void) luaL_dostring(L,
		"if rt then rt.on_lerror(err) end\n"
		"print(debug.traceback(err, 6))\n"
		"os.exit(1)\n"
	);
	die("unable to recover; exiting");
	return 0;
}

void
llua_sdump(lua_State *pL)
{
	fprintf(stderr, "----- STACK DUMP -----\n");
	for (int i = lua_gettop(L); i; --i) {
		int t = lua_type(L, i);
		switch (t) {
		break; case LUA_TSTRING:
			fprintf(stderr, "%4d: [string] '%s'\n", i, lua_tostring(L, i));
		break; case LUA_TBOOLEAN:
			fprintf(stderr, "%4d: [bool]   '%s'\n", i, lua_toboolean(L, i) ? "true" : "false");
		break; case LUA_TNUMBER:
			fprintf(stderr, "%4d: [number] '%g'\n", i, lua_tonumber(L, i));
		break; case LUA_TNIL:
			fprintf(stderr, "%4d: [nil]\n", i);
		break; default:
			fprintf(stderr, "%4d: [%s] #%d <%p>\n", i, lua_typename(L, t), (int) lua_rawlen(L, i), lua_topointer(L, i));
		break;
		}
	}
	fprintf(stderr, "----- STACK DUMP END -----\n");
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

	struct addrinfo hints;
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

	if (sent == -1) {
		lua_pushnil(pL);
		lua_pushstring(pL, format("cannot send: %s", strerror(errno)));
		return 2;
	} else if (sent < (strlen(data) + 2)) {
		lua_pushnil(pL);
		lua_pushstring(pL, format("sent != len(data): %s", strerror(errno)));
		return 2;
	}

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
