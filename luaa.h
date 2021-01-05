#ifndef LUAA_H
#define LUAA_H

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

int llua_openlib(lua_State *pL);

int api_conn_init(lua_State *pL);
int api_conn_send(lua_State *pL);
int api_conn_active(lua_State *pL);
int api_conn_close(lua_State *pL);
int api_tb_shutdown(lua_State *pL);
int api_tb_size(lua_State *pL);
int api_tb_clear(lua_State *pL);
int api_tb_writeline(lua_State *pL);
int api_tb_setcursor(lua_State *pL);
int api_utf8_insert(lua_State *pL);
int api_utf8_dwidth(lua_State *pL);

#endif
