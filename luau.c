#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#include <stdio.h>
#include <stdlib.h>

#include "luau.h"
#include "termbox.h"
#include "util.h"

extern size_t TB_ACTIVE;
extern size_t TB_INACTIVE;
extern size_t tb_state;

int
llua_panic(lua_State *pL)
{
	if (tb_state == TB_ACTIVE) {
		tb_shutdown();
		tb_state = TB_INACTIVE;
	}

	char *err = (char *) lua_tostring(pL, -1);

	/* run error handler */
	lua_getglobal(pL, "rt");
	if (lua_type(pL, -1) != LUA_TNIL) {
		lua_getfield(pL, -1, "on_lerror");
		lua_remove(pL, -2);
		int ret = lua_pcall(pL, 0, 0, 0);

		if (ret != 0) {
			/* if the call to rt.on_lerror failed, just ignore
			 * the error message and pop it. */
			lua_pop(pL, 1);
		}
	} else {
		lua_pop(pL, 1);
	}

	/* print the error, dump the lua stack, print lua traceback,
	 * and exit. */
	fprintf(stderr, "lua_call error: %s\n", err);

	char *debug = getenv("LURCH_DEBUG");
	if (debug && strtol(debug, NULL, 10) != 0) {
		fputc('\n', stderr); llua_sdump(pL); fputc('\n', stderr);
		luaL_traceback(pL, pL, err, 0);
		fprintf(stderr, "Lua traceback: %s\n\n", lua_tostring(pL, -1));
	}
	die("unable to recover; exiting");

	return 0;
}

void
llua_sdump(lua_State *pL)
{
	fprintf(stderr, "----- STACK DUMP -----\n");
	for (int i = lua_gettop(pL); i; --i) {
		int t = lua_type(pL, i);
		switch (t) {
		break; case LUA_TSTRING:
			fprintf(stderr, "%4d: [string] '%s'\n", i, lua_tostring(pL, i));
		break; case LUA_TBOOLEAN:
			fprintf(stderr, "%4d: [bool]   '%s'\n", i, lua_toboolean(pL, i) ? "true" : "false");
		break; case LUA_TNUMBER:
			fprintf(stderr, "%4d: [number] '%g'\n", i, lua_tonumber(pL, i));
#include <lualib.h>
		break; case LUA_TNIL:
			fprintf(stderr, "%4d: [nil]\n", i);
		break; default:
			fprintf(stderr, "%4d: [%s] #%d <%p>\n", i, lua_typename(pL, t), (int) llua_rawlen(pL, i), lua_topointer(pL, i));
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
