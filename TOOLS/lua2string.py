#!/usr/bin/env python3

#
# This file is part of mpv.
#
# mpv is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# mpv is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with mpv.  If not, see <http://www.gnu.org/licenses/>.
#

import sys
import string
import subprocess


def cstr(s):
    conv = ["\\%o" % c for c in range(256)]

    for c in string.ascii_letters:
        conv[ord(c)] = c

    return '"%s"' % "".join(conv[c] for c in s)


[_, lua_version, luac_prog, strip, input, output] = sys.argv

if luac_prog:
    lua_chunk = subprocess.check_output(
        # We use `string.dump` directly for LuaJIT because "luajit -b" is
        # handled by "jit.bcsave" module that may not work if user has messed up
        # her `$LUA_PATH`. Also, checking availability of "-d" (the "d" flag,
        # deterministic code generation) would require some extra code.
        [
            luac_prog,
            "-e",
            "assert(io.write(string.dump(assert(loadfile(arg[1])), assert(arg[2]))))",
            # We read an empty script from stdin just to be able pass some
            # arguments to "-e".
            "-",
            input,
            ("s" if strip else "") + "d",
        ]
        if lua_version == "luajit"
        else [
            luac_prog,
            *(["-s"] if strip else []),
            "-o",
            "-",
            input,
        ]
    )
else:
    with open(input, "rb") as f:
        lua_chunk = f.read()

with open(output, "w") as f:
    f.write(
        f"""\
{{
    .start = {cstr(lua_chunk)},
    .len = {len(lua_chunk)},
}}
"""
    )
