#ifndef LUAU_H
#define LUAU_H

#if LUA_VERSION_NUM >= 502
#define llua_rawlen(ST, NM) lua_rawlen(ST, NM)
#else
#define llua_rawlen(ST, NM) lua_objlen(ST, NM)
#endif

#if LUA_VERSION_NUM >= 502
#define llua_setfuncs(ST, FN) luaL_setfuncs(ST,   FN,  0);
#else
#define llua_setfuncs(ST, FN) luaL_register(ST, NULL, FN);
#endif

#define SETTABLE_INT(LU, NAME, VALUE, TABLE) \
	do { \
		lua_pushstring(LU, NAME); \
		lua_pushinteger(LU, (lua_Integer) VALUE); \
		lua_settable(LU, TABLE); \
	} while (0);

#define LLUA_ERR(LUA, ERR) \
	do { \
		lua_pushnil(LUA); \
		lua_pushstring(LUA, ERR); \
		return 2; \
	} while (0);

int  llua_panic(lua_State *pL);
void llua_sdump(lua_State *pL);
void llua_call(lua_State *pL, const char *fnname, size_t nargs,
		size_t nret);

#endif
