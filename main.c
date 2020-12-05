/* See LICENSE file for license details. */

#include <assert.h>
#include <errno.h>
#include <execinfo.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <netdb.h>
#include <readline/readline.h>
#include <readline/history.h> /* TODO: remove. */
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

const size_t TIMEOUT = 512;
const size_t BT_BUF_SIZE = 16;

int conn_fd = 0;
FILE *conn;
lua_State *L;

void signal_lhand(int sig);
void signal_fatal(int sig);

void die(const char *fmt, ...);
char *format(const char *format, ...);
void rl_handler(char *line);
int  rl_getc(FILE *f);

int  llua_panic(lua_State *pL);
void llua_sdump(lua_State *pL);
void llua_call(lua_State *pL, const char *fnname, size_t nargs,
		size_t nret);

/* TODO: move to separate file */
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

	/* init readline */
	rl_readline_name = "lurch";
	rl_getc_function = rl_getc;
	rl_callback_handler_install(NULL, rl_handler);
	rl_bind_key('\t', rl_insert);
	rl_initialize();

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

	luaL_dofile(L, "./rt/init.lua");
	lua_setglobal(L, "rt");

	/* run init function */
	llua_call(L, "init", 0, 0);

	/*
	 * no buffering for server,stdin,stdout. buffering causes
	 * certain escape sequences to not be output until a newline
	 * is sent, which often will badly mess up the TUI.
	 *
	 * by now, the server connection should have been opened.
	 */
	setvbuf(stdin, NULL, _IONBF, 0);
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(conn, NULL, _IONBF, 0);

	time_t trespond;
	struct timeval tv;
	tv.tv_sec  = 120;
	tv.tv_usec =   0;

	int n;
	fd_set rd;

	while ("pigs fly") {
		/* TODO: use poll(2) */
		FD_ZERO(&rd);
		FD_SET(conn_fd, &rd);
		FD_SET(0, &rd);

		n = select(conn_fd + 1, &rd, 0, 0, &tv);

		if (n < 0) {
			if (errno == EINTR)
				continue;
			die("error on select():");
		} else if (n == 0) {
			if (time(NULL) - trespond >= TIMEOUT) {
				/* TODO: run timeout handler */
				llua_call(L, "on_timeout", 0, 0);
			}

			/* TODO: run timeout handler */
			llua_call(L, "on_no_reply", 0, 0);
			continue;
		}

		if (FD_ISSET(conn_fd, &rd)) {
			llua_call(L, "on_reply", 0, 0);
			trespond = time(NULL);
		}

		if (FD_ISSET(0, &rd)) {
			llua_call(L, "on_input", 0, 0);
			rl_callback_read_char();

			/*
			 * for some reason, callback readline interface
			 * doesn't print the current line buffer, so print it manually.
			 * \r:       move cursor the the start of the terminal row.
			 * \x1b[2K:  clear the current line.
			 * \r:       move back to the start of the terminal row.
			 */
			printf("\r\x1b[2K\r%s", rl_line_buffer);
		}
	}
	
	lua_close(L);
	return 0;
}

// utility functions

void
signal_lhand(int sig)
{
	/* run error handler */
	/* TODO: do not run sig-unsafe code in this fn */
	lua_pushinteger(L, (lua_Integer) sig);
	llua_call(L, "on_signal", 1, 0);
}

void
signal_fatal(int sig)
{
	/* TODO: do not run sig-unsafe code in this fn */
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

void
rl_handler(char *line)
{
	add_history(line);
	lua_pushstring(L, line);
	llua_call(L, "on_rl_input", 1, 0);
}

int
rl_getc(FILE *f)
{
	int c = getc(f);

	if (c == '\n') {
		rl_done = 1;
		return 0;
	}

	return c;
}

int
llua_panic(lua_State *pL)
{
	int ret;

	/* run error handler */
	lua_getglobal(pL, "rt");
	lua_getfield(pL, -1, "on_lerror");
	lua_remove(pL, -2);
	ret = lua_pcall(pL, 0, 0, 0);

	if (ret != 0) {
		/* if the call to rt.on_lerror failed, just ignore
		 * the error message and pop it. */
		lua_pop(pL, 1);

		/* flush stdin, as rt.on_lerror probably didn't do
		 * it for us */
		fflush(stdin);
	}

	/* call debug.traceback and get backtrace */
	lua_getglobal(pL, "debug");
	lua_getfield(pL, -1, "traceback");
	lua_remove(pL, -2);
	lua_pushvalue(pL, 1);
	lua_pushinteger(pL, (lua_Integer) 2);
	lua_pcall(pL, 2, 1, 0);

	fprintf(stderr, "\rlua_call error: %s\n\n", lua_tostring(pL, -1));
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

void
llua_call(lua_State *pL, const char *fnname, size_t nargs, size_t nret)
{
	/* get function from rt. */
	lua_getglobal(pL, "rt");
	lua_getfield(pL, -1, fnname);
	lua_remove(pL, -2);

	/* move function before args. */
	lua_insert(pL, -nargs - 1);

	lua_call(pL, nargs, nret);
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

	if (r == NULL || ((conn = fdopen(conn_fd, "r+")) == NULL)) {
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
