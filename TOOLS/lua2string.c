/*
 * This file is part of mpv.
 *
 * mpv is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * mpv is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdlib.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

static const char lua2string_source[] =
#include "TOOLS/lua2string.lua.inc"
    ;

static void die(lua_State *L)
{
    const char *msg = lua_tostring(L, -1);
    fprintf(stderr, "lua2string.c: lua2string.lua: %s\n", msg);
    exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
    lua_State *L = luaL_newstate();

    luaL_openlibs(L);

    if (luaL_loadstring(L, lua2string_source))
        die(L);

    for (int n = 1; n < argc; n++)
        lua_pushstring(L, argv[n]);

    if (lua_pcall(L, argc - 1, 0, 0))
        die(L);

    return EXIT_SUCCESS;
}
