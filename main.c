/* See LICENSE file for license details. */

#include <assert.h>
#include <errno.h>
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <tls.h>
#include <unistd.h>
#include <utf8proc.h>

#include "dwidth.h"
#include "luau.h"
#include "luaa.h"
#include "mirc.h"
#include "termbox.h"
#include "util.h"

/* maximum rate at which the screen is refreshed */
const struct timeval REFRESH = { 0, 3000 };

#define TIMEOUT 4096

/*
 * keep track of termbox's state, so
 * that we know if tb_shutdown() is safe to call.
 *
 * calling tb_shutdown twice, or before tb_init,
 * results in a call to abort().
 */
_Bool tb_active = false;

lua_State *L = NULL;
int conn_fd = 0;
FILE *conn = NULL;

_Bool tls_active = false;
struct tls *client = NULL;

void try_present(struct timeval *tcurrent, struct timeval *tpresent);
void signal_lhand(int sig);
void signal_fatal(int sig);

int
main(int argc, char **argv)
{
	/* register signal handlers */
	/* signals to whine and die on: */
	struct sigaction fatal;
	fatal.sa_handler = &signal_fatal;
	sigaction(SIGILL,   &fatal, NULL);
	sigaction(SIGSEGV,  &fatal, NULL);
	sigaction(SIGFPE,   &fatal, NULL);
	sigaction(SIGBUS,   &fatal, NULL);

	/* signals to catch and handle in lua code: */
	struct sigaction lhand;
	lhand.sa_handler = &signal_lhand;
	sigaction(SIGHUP,   &lhand, NULL);
	sigaction(SIGINT,   &lhand, NULL);
	sigaction(SIGPIPE,  &lhand, NULL);
	sigaction(SIGUSR1,  &lhand, NULL);
	sigaction(SIGUSR2,  &lhand, NULL);
	sigaction(SIGWINCH, &lhand, NULL);

	/* init termbox */
	char *errstrs[] = {
		NULL,
		"termbox: unsupported terminal",
		"termbox: cannot open terminal",
		"termbox: pipe trap error"
	};
	char *err = errstrs[-(tb_init())];
	if (err) die(err);
	tb_active = true;
	tb_select_output_mode(TB_OUTPUT_256);

	/* init lua */
	L = luaL_newstate();
	assert(L);

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
		"package.path = __LURCH_EXEDIR .. '/conf/?.lua;' .. package.path\n"
	);

	/* setup lurch api functions */
	lua_newtable(L);
	llua_setfuncs(L, (luaL_Reg *) &lurch_lib);
	lua_pushvalue(L, -1);
	lua_setglobal(L, "lurch");

	!luaL_dofile(L, "./rt/init.lua") || llua_panic(L);
	lua_setglobal(L, "rt");

	/* run init function */
	lua_settop(L, 0);
	lua_newtable(L);
	for (size_t i = 1; i < (size_t) argc; ++i) {
		lua_pushinteger(L, i);
		lua_pushstring(L, argv[i]);
		lua_settable(L, -3);
	}
	llua_call(L, "init", 1, 0);

	/*
	 * no buffering for server,stdin,stdout. buffering causes
	 * certain escape sequences to not be output until a newline
	 * is sent, which often will badly mess up the TUI.
	 *
	 * by now, the server connection should have been opened.
	 */
	setvbuf(stdin, NULL, _IONBF, 0);
	setvbuf(stdout, NULL, _IONBF, 0);
	if (!tls_active) setvbuf(conn, NULL, _IONBF, 0);

	/*
	 * trespond: last time we got something from the server.
	 * ttimeout: how long select(2) should wait for activity.
	 * tpresent: last time tb_present() was called.
	 * tcurrent: buffer for gettimeofday(2).
	 */
	time_t trespond = 0;
	struct timeval ttimeout = { 120, 0 };
	struct timeval tpresent = {   0, 0 };
	struct timeval tcurrent = {   0, 0 };

	/* select(2) stuff */
	int n = 0;
	fd_set rd;

	/* buffer for incoming server data. */
	char bufsrv[4096];

	/* length of data in bufsrv */
	size_t rc =  0;

	/* incoming user events (key presses, window resizes,
	 * mouse clicks, etc */
	struct tb_event ev;

	while ("pigs fly") {
		FD_ZERO(&rd);
		FD_SET(STDIN_FILENO, &rd);
		FD_SET(conn_fd, &rd);

		try_present(&tcurrent, &tpresent);
		n = select(conn_fd + 1, &rd, 0, 0, &ttimeout);

		if (n < 0) {
			if (errno == EINTR)
				continue;
			die("error on select():");
		} else if (n == 0) {
			if (time(NULL) - trespond >= TIMEOUT)
				llua_call(L, "on_timeout", 0, 0);

			continue;
		}

		if (FD_ISSET(conn_fd, &rd)) {
			ssize_t r = -1;
			size_t max = sizeof(bufsrv) - 1 - rc;

			if (tls_active)
				r = tls_read(client, &bufsrv[rc], max);
			else
				r = read(conn_fd, &bufsrv[rc], max);

			if (tb_active && (r == TLS_WANT_POLLIN || r == TLS_WANT_POLLOUT)) {
				continue;
			} else if (r < 0) {
				if (errno == EINTR)
					continue;
				die("error on read():");
			} else if (r == 0) {
				lua_pushstring(L, (const char *) NETWRK_ERR());
				llua_call(L, "on_disconnect", 1, 0);
				continue;
			}

			rc += r;
			bufsrv[rc] = '\0';

			char *end = NULL;
			char *ptr = (char *) &bufsrv;
			while ((end = memmem(ptr, &bufsrv[rc] - ptr, "\r\n", 2))) {
				*end = '\0';

				lua_pushstring(L, (const char *) ptr);
				llua_call(L, "on_reply", 1, 0);

				ptr = end + 2;
			}

			rc -= ptr - bufsrv;
			memmove(&bufsrv, ptr, rc);
			trespond = time(NULL);
		}

		if (FD_ISSET(STDIN_FILENO, &rd)) {
			int ret = 0;
			while ((ret = tb_peek_event(&ev, 16)) != 0) {
				assert(ret != -1); /* termbox error */

				/* don't push event.w and event.y; the Lua
				 * code can easily get those values by running
				 * lurch.tb_size() */
				lua_settop(L, 0);
				lua_newtable(L);
				SETTABLE_INT(L, "type",   ev.type, -3);
				SETTABLE_INT(L, "mod",    ev.mod,  -3);
				SETTABLE_INT(L, "ch",     ev.ch,   -3);
				SETTABLE_INT(L, "key",    ev.key,  -3);
				SETTABLE_INT(L, "mousex", ev.x,    -3);
				SETTABLE_INT(L, "mousey", ev.y,    -3);
				llua_call(L, "on_input", 1, 0);
			}
		}
	}

	cleanup();
	return 0;
}

// utility functions

/* check if (a) REFRESH time has passed, and (b) if the termbox
 * buffer has been modified; if both those conditions are met, refresh
 * the screen. */
void
try_present(struct timeval *tcurrent, struct timeval *tpresent)
{
	assert(gettimeofday(tcurrent, NULL) == 0);
	struct timeval diff;
	timersub(tcurrent, tpresent, &diff);
	if (diff.tv_sec >= REFRESH.tv_sec && diff.tv_usec >= REFRESH.tv_usec) {
		assert(gettimeofday(tpresent, NULL) == 0);
		tb_present();
	}
}

void
signal_lhand(int sig)
{
	/* run signal handler */
	lua_pushinteger(L, (lua_Integer) sig);
	llua_call(L, "on_signal", 1, 0);
}

void
signal_fatal(int sig)
{
	die("received signal %d; aborting.", sig);
}
