--[[
This file is part of mpv.

mpv is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation; either
version 2.1 of the License, or (at your option) any later version.

mpv is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
]]

local lua_version, luac, luac_strip, luac_strip_cmd, input, output = ...
luac = luac == "yes"
luac_strip = luac_strip == "yes"

local function to_cstr(s)
    return ('"%s"'):format(s:gsub("%A", function(c)
        return ("\\%o"):format((c):byte())
    end))
end

local function get_lua_chunk()
    if not luac then
        local f = assert(io.open(assert(input)))
        return assert(f:read("*a"))
    end

    -- Lua <5.3 does not have a "strip" parameter on `string.dump` so we must
    -- use an external command for it.
    if luac_strip and luac_strip_cmd ~= "" then
        local f = assert(io.popen(luac_strip_cmd:format(input)))
        local s = assert(f:read("*a"))
        assert(s ~= "", ("%q returned no output"):format(luac_strip_cmd))
        return s
    end

    local fn = assert(loadfile(assert(input)))

    -- Request deterministic bytecode from LuaJIT (if supports).
    if lua_version == "luajit" then
        return string.dump(fn, luac_strip and "sd" or "d")
    end

    return string.dump(fn, luac_strip)
end

local lua_chunk = get_lua_chunk()

local c_code = ([[
{
    .start = %s,
    .len = %d,
}
]]):format(to_cstr(lua_chunk), #lua_chunk)

local outfile = assert(io.open(assert(output), "wb"))
assert(outfile:write(c_code))
assert(outfile:close())
